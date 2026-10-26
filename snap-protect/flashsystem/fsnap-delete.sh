#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2026
#
#--------------------------------------------------------------------------------
# ATTENTION: This is a beta-version and must not be used for production. Any 
# failure or damage on production system is under your own liabilit.
#--------------------------------------------------------------------------------
#                     
# Name: fsnap-delete.sh
# Desc: Delete SGC for volume groups. 
#
# Input: 
# -s snapshotname: name of the SGC to be deleted (required) (mutually exclusing with -g)
# -i instanceuser: name of the instance user, default is the user running this script
# -g age: snapshots older then age days are delete (mutually exclusing with -s)
# -p: preview mode, does not do deletion, just lists snapnames to be deleted (optional)
#
# Dependencies:
# This scripts can run on the host where the instance is running.
# Requires jq in $jqPath 
# This script uses the Flashsystem REST API to query FlashSystem
# This script requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - FlashSystem volume groups that correspond to the instance
# - REST API server and FlashSystem credentials to authenticate with the API
#
# Usage:
# fsnap-delete.sh -s snapshot-name | -g snapshot-age [-i instance-name -p]
#  -s snapshot-name: Name of the SGC to be deleted from all file systems. Required if -g is not specified.
#  -g snapshot-age:  Age of snapshots in days to be deleted from all file systems. Required if -s is not specified.
#  -i instance-name: Instance user name, default is the user running this script (optional)
#  -p:               Preview SGC names to be deleted from all file systems (optional)
#  -h | --help:      Show this help message (optional).
#
#********************************************************************************

# History
#---------
# 08/13/24 Initial version (J. Basler)
# 11/04/24 further adjustments - rename to fsnap-del.sh - version 1.1 (N. Haustein)
# 03/25/25 AIX compatibility changes - version 1.2
# 04/06/25 add function calc_expdate for platform specific calculation of deletion date
# 04/10/25 fixed expiration date calculation (plus instead of minus $age)
# 05/08/25 fixed deletion date format %y instead of %Y
# 03/22/25 use common functions from $funcFile
# 05/23/25 support multiple flashsystems per instance - version 1.3
# 06/12/25 remove hard-coding of /usr/local/bin
# 06/12/25 AIX compatibility: convert sed /\t/ to sed / / - version 1.4
# 02/12/26 added config parameter consistentSnap
# 02/12/26 provide snapName and vgName instead of snapid when deleting SGC using rmsnapshot endpoint - version 1.5
# 04/01/26 use global parameter sleepTime when waiting for API requests to settle
# 04/12/26 use apiCredentials in config file 
# 04/13/26 print version of global functions (fsnapfunctions.sh)
# 04/24/26 remove initialization of configuration parameter arrays (moved to fsnapfunctions.sh)
# 08/13/26 add structured logging functions (log_info, log_warn, log_debug, log_error) - version 1.5 (Dominic)

#---------------------------------------
# global parameters
#---------------------------------------
# common functions file
funcFile="fsnapfunctions.sh"

# initialized snapName to be given as argument
snapName=""

# time to sleep between SGC deletes
sleepTime=1

# version
ver=1.5


# -----------------------------------------------------------------
# function usage 
#
# -----------------------------------------------------------------
function usage()
{
  echo
  echo "Usage: fsnap-delete.sh -g SGC-age | -s SGC-name [-i instance-name -p]"
  echo "  -g SGC-age:       Age of snapshots in days to be deleted from all file systems. Required if -s is not specified."
  echo "  -s SGC-name:      Name of the SGC (mutually exclusive with parameter -g)."
  echo "  -i instance-name: Instanz user name, default is the user running this script (optional)"
  echo "  -p:               Preview SGC names to be deleted from all file systems (optional)"
  echo
  return 0
}


# -----------------------------------------------------------------
# function calc_expDate calculates the expiration date based on current date and $age
# This is a platform specific. On linux we use 'date -d', on AIX we use ksh93
#
# Input:  $snapAge
#
# Output: $delDate in format yymmddhhssmm 
#
# Return code:
# 0: success
# 1: failure
#
# -----------------------------------------------------------------
calc_expDate()
{
   # $os comes from functions
   #os=$(uname -s)
   log_debug "calculating deletion date on platform $os"

   case "$os" in
   Linux)
    delDate=$(date +%y%m%d%H%M%S -d "$DATE - $snapAge day");;
   AIX)
	  curEp=$(date +"%s")
		(( expEp = curEp - ($snapAge * 86400) ))
	  delDate=$(ksh93 -c 'printf "%(%y%m%d%H%M%S)T\n" "#$1"' ksh93 $expEp);;
   *)
    delDate="";;
   esac

   if [[ -z $delDate ]]; then 
     return 1
   else 
     return 0
   fi 
}


# -----------------------------------------------------------------
# function del_apisnapshots perform SGC deletion
#
# Requires: vgName, snapAge, snapName
#
# Return 
# 0: success
# 1: fail
# -----------------------------------------------------------------
function del_apisnapshot ()
{
   
  frc=0
  rmsg=""
  count=0
  while read -r line;
  do
    sDate=""
    sName=""
    sID=""
    if [[ -z $line ]]; then
      continue
    fi
	  # if snapAge is set, then compare the date to select eligible snapshots
    if [[ ! -z $snapAge ]]; then
    sDate=$(echo $line | awk '{print $5}')
    # log_debug "snapDate=$sDate, delDate=$delDate"
    if [[ "$sDate" < "$delDate" ]]; then
      sName=$(echo $line | awk '{print $2}')
      sID=$(echo $line | awk '{print $1}')
      log_debug "Eligible snapshot: name=$sName id=$sID createtime=$sDate"
    fi
  else
    sName=$(echo $line | awk '{print $2}')
    if [[ $snapName = $sName ]]; then
      sDate=$(echo $line | awk '{print $5}')
      sID=$(echo $line | awk '{print $1}')
      log_debug "Eligible snapshot: name=$sName id=$sID createtime=$sDate"
    fi
  fi

  if [[ "$op" == "perform" && ! -z $sID ]]; then
    log_info "Deleting SGC $snapName from volume group $vgName"
      
      # Avoid FlashSystem request limits
	    sleep $sleepTime
      rmsg=$(curl -k -X POST --url "https://$apiServer/rest/rmsnapshot" \
      --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
      --data-raw '{
        "snapshot": "'"$sName"'", 
        "volumegroup": "'"$vgName"'"
      }' 2>/dev/null)
      frc=$?
      if [[ ! $frc = 0 || ! $rmsg = '""' ]]; then
        log_error "Failed to delete SGC $sName from volume group $vgName (rc=$frc, message=$rmsg)"
        (( frc = frc + 1 ))
      else
        (( count = count + 1 ))
      fi
    fi
  done  <<<  $(curl -k -X POST --url "https://$apiServer/rest/v1/lsvolumegroupsnapshot" \
  --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
  --data-raw '{
     "filtervalue": "volume_group_name='$vgName'"
  }' 2>/dev/null \
  | jq -r ' .[] | [ .id,.name,.volume_group_id,.volume_group_name,.time,.state ] | @csv ' 2>/dev/null | sed 's/",/ /g' | sed 's/\"//g')

  # if we deleted no SGC then present a warning
  if (( count == 0 && frc == 0)); then
    log_warn "No snapshots found matching the criteria."
  fi

  # return in accordance with return code
  return $frc
  
}

#---------------------------------------
# Main
#---------------------------------------

### determine directory where the script is started from
basePath=$(dirname $0)
if [[ $basePath = "." ]]; then
  basePath=$PWD
fi
# echo "DEBUG: base path for $0: $basePath"

### source common functions
if [[ -f $basePath/$funcFile ]]; then
  . $basePath/$funcFile
else
  echo "ERROR: common functions file $basePath/$funcFile not found, or insufficient permission for instance user." >&2
  exit 1
fi

### present banner
log_info "program $0 version $ver started for instance $instUser (global functions version $globFuncVer)"


### parse arguments from the command line
snapName=""
snapAge=""
preview=0
while [[ ! -z "$*" ]];
do
  case "$1" in
  "-i") shift 1 # shift because we need the next arg in $1
        if [[ -z $1 ]]; then
          usage "Instance user name is not specified."
          exit 1
        else
          instUser=$1
        fi;;
  "-s") shift 1
        if [[ -z $1 ]]; then
          usage "Snapshot name is not specified."
          exit 1
        else
          snapName=$1
        fi;;
  "-g") shift 1
        if [[ -z $1 ]]; then
          usage "Snapshot age is not specified."
          exit 1
        else
          snapAge=$1
        fi;;
  "-p") preview=1;;
  "-h" | "--help")
        usage "command usage"
        exit 1;;
  *)    usage "wrong argument $1"
        exit 1;;
  esac
  shift 1
done

if [[ -z $snapName && -z $snapAge ]]; then
  usage "Snapshot name (parameter -s) or SGC age (parameter -g) not specified."
  exit 1
else
  if [[ ! -z $snapName && ! -z $snapAge ]]; then
    usage "Snapshot name (parameter -s) and SGC age (parameter -g) are mutual exclusive."
	exit 1
  fi
fi


### get the parameters for this instance user from the config_file
log_info "Parsing configuration parameters from config file $configFile."
parse_config
# log_debug "vgsToSnap=$vgsToSnap"


### check configuration parameters
# check if we found any entries in config file
if (( arrLen < 0 )); then
  log_error "no configuration found for user $instUser in config file $configFile"
  exit 1
fi

### check config parameters and apply default values where possible
log_info "Checking configuration parameters."
if ! check_config; then
  exit 2
fi

### set operation variable
if (( preview == 1 )); then
  op=preview
else
  op=perform
fi

# calculate platform specific deletion date 
delDate=""
if [[ ! -z $snapAge ]]; then
  delDate=""
  calc_expDate
  rc=$?
  if (( rc > 0 )); then
    log_error "Unable to calculate deletion date. Contact support."
    exit 2
  fi
  if [[ ! -z $snapAge ]]; then
    log_info "$op snapshots deletion for snaps older than $snapAge days ($delDate) using API server $apiServer"
  else
    log_info "$op SGC deletion for snap $snapName using API server $apiServer"
  fi
fi

# iterate through the vgsToSnap and delete snapshots
### get the API tokens
i=0
while (( i <= arrLen ));
do
  apiServer=${apiServer_Arr[$i]}:${apiPort_Arr[$i]}
  apiUser=${apiUser_Arr[$i]}
  apiPw=${apiPw_Arr[$i]}
  if ! get_apitoken; then
    exit 3
  else
    token_Arr[$i]=$TOKEN
  fi
  (( i = i + 1 ))
    # sleep to let the API settle if there are more elements to process
  if (( i <= arrLen )); then
    sleep $multiSysSleep
  fi
done

### log the local time of each FlashSystem
i=0
while (( i <= arrLen ));
do
  apiServer=${apiServer_Arr[$i]}:${apiPort_Arr[$i]}
  TOKEN=${token_Arr[$i]}
  log_flashsystem_time
  (( i = i + 1 ))
done

# Avoid FlashSystem request limits
sleep $sleepTime

# iterate through the volume groups and delete the relevant snapshots
rc=0
i=0
while (( i <= arrLen ));
do
  apiServer=${apiServer_Arr[$i]}:${apiPort_Arr[$i]}
  TOKEN=${token_Arr[$i]}
  vgsToSnap=${vgsToSnap_Arr[$i]}
  vgName=""
  for vgName in $(echo "$vgsToSnap" | sed 's/,/ /g')
  do
    # log_debug "volume group=$vgName"
    log_info "processing volume group $vgName on FlashSystem $apiServer"
    del_apisnapshot
    (( rc = rc + $? ))
  done
  (( i = i + 1 ))
  # sleep to let the API settle if there are more elements to process
  if (( i <= arrLen )); then
    sleep $multiSysSleep
  fi
done
if (( rc > 0 )); then
  log_error "$op SGC deletion failed, check the console output."
  log_error "============================================================================================"
  exit 5
else
  log_info "$op SGC deletion completed successfully."
  log_info "============================================================================================"
fi

exit 0