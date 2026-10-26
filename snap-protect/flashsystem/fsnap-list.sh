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
# Name: fsnap-list.sh
# Desc: List FlashSystem volume group snapshots using the REST API
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
# fsnap-list.sh [-i instance-user-name -s snapshot-name -v -h | --help]
#   -i instance-user-name:  Name of the instance (user) for which the snapshots are listed (optional, default is user running this command).
#   -s snapshot-name:       SGC name to be listed (checked) for all relevant file systems and filesets (optional, lists all SGC by default).
#   -v:                     Verbose output.
#   -h | --help:            Show this help message (optional).
# 
#********************************************************************************

# History
#----------
# 08/13/24 Initial version (J. Basler)
# 11/04/24 further adjustments - rename to fsnap-list.sh - version 1.1 (N. Haustein)
# 11/14/24 sort by creation date
# 11/29/24 correct formatting
# 12/03/24 adjust spacing
# 03/25/25 AIX compatibility changes - version 1.2
# 03/22/25 use common functions from $funcFile
# 05/23/25 support multiple flashsystems per instance - version 1.3
# 06/12/25 remove hard-coding of /usr/local/bin
# 06/12/25 AIX compatibility: convert sed /\t/ to sed / / - version 1.4
# 02/12/26 added config parameter consistentSnap
# 04/12/26 use apiCredentials in config file 
# 04/13/26 print version of global functions (fsnapfunctions.sh)
# 04/24/26 remove initialization of configuration parameter arrays (moved to fsnapfunctions.sh)
# 08/12/26 improve table formatting (Dominic)
# 08/13/26 add structured logging functions (log_info, log_warn, log_debug, log_error) - version 1.4 (Dominic)
# 08/31/26 print blank line between volume groups  - version 1.5

#---------------------------------------
# global parameters
#---------------------------------------
# common functions file
#funcFile="/usr/local/bin/fsnapfunctions.sh"
funcFile="fsnapfunctions.sh"


# program version
ver=1.5

separatorWidth=0


# -----------------------------------------------------------------
# function usage 
#
# -----------------------------------------------------------------
function usage()
{
  echo
  log_info "$1"
  echo "Usage: fsnap-list.sh [-i instance-user-name -s SGC-name -v -h | --help]"
  echo "  -i instance-user-name:  Name of the instance (user) for which the snapshots are listed."
  echo "                          Optional, default is user running this command."
  echo "  -s SGC-name:            SGC name to be listed (checked) for all relevant volume groups (optional, lists all SGC by default)."
  echo "  -h | --help:            Show this help message (optional)."
  echo
  return 0
}


# -----------------------------------------------------------------
# function list_apisnapshot to list snapshots for a volume group
#
# Requires $configFile
# lists snapshots 
#
# -----------------------------------------------------------------
function list_apisnapshot()
{
  # log_debug "Entering list_apisnapshot()"
  frc=0

  # list snapshots
  echo
  log_info "==== Snapshots in volume group $vgName on FlashSystem $apiServer ===="
  if [[ -a $jqPath ]]; then
    if [[ -z $snapName ]]; then
      snapshotData=$(curl -k -X POST --url "https://$apiServer/rest/v1/lsvolumegroupsnapshot" \
      --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
      --data-raw '{
        "filtervalue": "volume_group_name='$vgName'"
      }' 2>/dev/null \
      | jq -r '
          def fmtts(t):
            if (t == null or t == "") then ""
            else "20" + t[0:2] + "-" + t[2:4] + "-" + t[4:6] + " " + t[6:8] + ":" + t[8:10] + ":" + t[10:12]
            end;
          .[] | [ .volume_group_name,.name,.id,.state,(fmtts(.time)),(fmtts(.expiration_time)),.safeguarded,.protection_written_capacity ] | @tsv
        ' 2>/dev/null | sort -r -k 5)
      frc=$?
    else
      snapshotData=$(curl -k -X POST --url "https://$apiServer/rest/v1/lsvolumegroupsnapshot" \
      --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
      --data-raw '{
        "volumegroup": "'"$vgName"'",
        "snapshot": "'"$snapName"'"
      }' 2>/dev/null \
      | jq -r '
          def fmtts(t):
            if (t == null or t == "") then ""
            else "20" + t[0:2] + "-" + t[2:4] + "-" + t[4:6] + " " + t[6:8] + ":" + t[8:10] + ":" + t[10:12]
            end;
          .[] | [ .volume_group_name,.name,.id,.state,(fmtts(.time)),(fmtts(.expiration_time)),.safeguarded,.protection_written_capacity ] | @tsv
        ' 2>/dev/null | sort -r -k 5)
      frc=$?
    fi

    awkOutput=$(printf '%s\n' "$snapshotData" | awk -F '\t' '
      BEGIN {
        headers[1] = "VGName"
        headers[2] = "SnapshotName"
        headers[3] = "Id"
        headers[4] = "State"
        headers[5] = "CreationTime"
        headers[6] = "ExpirationTime"
        headers[7] = "SGC"
        headers[8] = "Capacity"
        for (i = 1; i <= 8; i++) {
          widths[i] = length(headers[i])
        }
      }
      NF {
        rowCount++
        for (i = 1; i <= 8; i++) {
          rows[rowCount, i] = $i
          if (length($i) > widths[i]) {
            widths[i] = length($i)
          }
        }
      }
      END {
        lineWidth = 0
        for (i = 1; i <= 8; i++) {
          printf "%-*s", widths[i], headers[i]
          lineWidth += widths[i]
          if (i < 8) {
            printf "  "
            lineWidth += 2
          } else {
            printf "\n"
          }
        }
        for (r = 1; r <= rowCount; r++) {
          for (i = 1; i <= 8; i++) {
            printf "%-*s", widths[i], rows[r, i]
            if (i < 8) {
              printf "  "
            } else {
              printf "\n"
            }
          }
        }
        printf "__FSNAP_WIDTH__=%d\n", lineWidth
      }
    ')
    separatorWidthCandidate=$(printf '%s\n' "$awkOutput" | sed -n 's/^__FSNAP_WIDTH__=//p')
    printf '%s\n' "$awkOutput" | sed '/^__FSNAP_WIDTH__=/d'
    if [[ -n $separatorWidthCandidate ]] && (( separatorWidthCandidate > separatorWidth )); then
      separatorWidth=$separatorWidthCandidate
    fi
  else
	curl -k -X POST "https://$apiServer/rest/lsvolumegroupsnapshot" --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" 2>/dev/null
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
  "-s") shift 1
        if [[ -z $1 ]]; then
          usage "Snapshot name is not specified."
          exit 1
        else
          snapName=$1
        fi;;
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


### iterate through the vgsToSnap and list snapshot
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
    # echo "  DEBUG: volume group=$vgName"
    list_apisnapshot
    (( rc = rc + $? ))
    # echo "DEBUG: rc=$rc"
  done
  (( i = i + 1 ))
  # sleep to let the API settle if there are more elements to process
  if (( i <= arrLen )); then
    sleep $multiSysSleep
  fi
done

if (( separatorWidth > 0 )); then
  printf '%*s\n' "$separatorWidth" '' | tr ' ' '='
fi

exit $rc