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
# Name: fsnap-volstate.sh
# Desc: Show volumes and states in volume group
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
# fsnap-volstate.sh -i instance-user-name [-h | --help]
#   -i instance-user-name:  Name of the instance (user) for which the snapshots are listed (optional, default is user running this command).
#   -h | --help:            Show this help message (optional).
# 
#********************************************************************************

# History
#----------
# 11/13/24 first implementation
# 03/25/25 AIX compatibility changes - version 1.1
# 03/22/25 use common functions from $funcFile
# 05/23/25 support multiple flashsystems per instance - version 1.2
# 06/12/25 remove hard-coding of /usr/local/bin
# 06/12/25 AIX compatibility: convert sed /\t/ to sed / / - version 1.3
# 08/06/25 display replication mode
# 02/12/26 added config parameter consistentSnap
# 04/12/26 use apiCredentials in config file 
# 04/13/26 print version of global functions (fsnapfunctions.sh)
# 04/24/26 remove initialization of configuration parameter arrays (moved to fsnapfunctions.sh)
# 08/13/26 add structured logging functions (log_info, log_warn, log_debug, log_error) - version 1.3 (Dominic)
# 08/31/26 print blank line between volume groups - version 1.4

#---------------------------------------
# global parameters
#---------------------------------------
# common functions file
funcFile="fsnapfunctions.sh"

# program version
ver=1.4

# -----------------------------------------------------------------
# function usage 
#
# -----------------------------------------------------------------
function usage()
{
  echo
  log_error "$1"
  echo "Usage: fsnap-volstate.sh [-i instance-user-name -v -h | --help]"
  echo "  -i instance-user-name:  Name of the instance (user) for which the volumes are listed"
  echo "                          Optional, default is user running this command."
  echo "  -v:                     verbose mode (not implemented yet)"
  echo "  -h | --help:            Show this help message (optional)."
  echo
  return 0
}


# -----------------------------------------------------------------
# function list_apicvolumes to list volumes for a volume group
#
# Requires $vgName
# lists volumes
#
# -----------------------------------------------------------------
function list_apivolumes()
{
  # log_debug "Entering list_apivolumes()"
  frc=0

  # list volumes
  echo
  log_info "==== Volumes in volume group $vgName on FlashSystem $apiServer:"
  if [[ -a $jqPath ]]; then
	printf "%-25s %10s %10s %10s %8s %8s %7s %11s\n" "Volume Name" "Status" "Capacity" "SGC-Count" "Restore" "Vol-ID" "FC_id" "Repl-mode"
  curl -k -X POST --url "https://$apiServer/rest/v1/lsvdisk" \
    --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
    --data-raw '{
      "filtervalue": "volume_group_name='$vgName'"
    }' 2>/dev/null \
    | jq -r ' .[] | [ .name,.status,.capacity,.safeguarded_snapshot_count,.restore_in_progress,.volume_id,.FC_name,.replication_mode ] | @csv ' 2>/dev/null | sed 's/",/ /g' | sed 's/\"//g' | awk '{printf "%-25s %10s %10s %10s %8s %8s %7s %11s\n", $1, $2, $3, $4, $5, $6, $7, $8}'

    frc=$rc
  else
	curl -k -X POST "https://$apiServer/rest/v1/lsvdisk" --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" 2>/dev/null
	frc=$?
  fi
 
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
verbose=0
snapName=""
while [[ ! -z "$*" ]];
do
  case "$1" in
  "-i") # shift because we need the next arg in $1
        shift 1
        if [[ -z $1 ]]; then
          usage "Instance user name is not specified."
          exit 1
        else
          instUser=$1
        fi;;
  "-v") verbose=1;;
  "-h" | "--help")
        usage "command usage"
        exit 1;;
  *)    usage "wrong argument $1"
        exit 1;;
  esac
  shift 1
done


### get the parameters for this instance user from the config_file
# echo "INFO: Parsing configuration parameters from config file $configFile."
parse_config
# echo "DEBUG: vgsToSnap=$vgsToSnap"


# check if we found any entries in config file
if (( arrLen < 0 )); then
  log_error "no configuration found for user $instUser in config file $configFile"
  exit 1
fi

### check config parameters and apply default values where possible
# echo "INFO: Checking configuration parameters."
if ! check_config; then
  exit 2
fi

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


### iterate through the vgsToSnap and list volumes
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
    list_apivolumes
    (( rc = rc + $? ))
    # echo "DEBUG: rc=$rc"
  done
  (( i = i + 1 ))
  # sleep to let the API settle if there are more elements to process
  if (( i <= arrLen )); then
    sleep $multiSysSleep
  fi
done

log_info "============================================================================================"
exit $rc
