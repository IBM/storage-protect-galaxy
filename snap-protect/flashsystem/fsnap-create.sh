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
# Name: fsnap-create.sh
# Desc: Creates FlashSystem volume group snapshots using REST API
#
# Dependencies:
# This scripts must run on the host where the instance is running, it must be run by the instance user and uses the REST API
# Requires jq in $jqPath and fsfreeze in $freezeCmd
# Requires sudo to run fsfreeze in $sudoCmd
# This script uses the Flashsystem REST API to query FlashSystem
# This script requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - database name
# - FlashSystem volume groups that correspond to the instance
# - file systems
# - SGC prefix
# - SGC retention
# - server instance directory
# - sudo command
# - REST API server and FlashSystem credentials to authenticate with the API
#
# Usage:
# fsnap-create.sh -r | --run [-i instanceUser | -h | --help]"
# -r | --run:  Create SGC. (required)"
# -i instance-user-name:  Name of the instance (user) for which SGC are created (optional). Default is the user executing the command."
# -h | --help: print the usage. (optional)"

# fsnap-create.sh -r | --run | -h | --help
# -r | --run:  Perform theSGCif the prerequisites are satisfied
# -h | --help: Show this help message (optional).
# *: show usage.
#
#********************************************************************************#

# History
#----------
# 08/13/24 Initial version (J. Basler)
# 11/04/24 further adjustments - rename to fsnap-create.sh - version 1.1 (N. Haustein)
# 12/03/24 Add delimiter prior to exit
# 02/21/25 If fsfreeze and sync do not exist, then exit  version 1.2
# 03/07/25 use ps instead of pgrep (AIX compatibility)
# 03/25/25 AIX compatibility changes, add sudo command variable - version 1.3
# 04/01/25 remove sudo for sync command
# 04/06/25 if parameter snapRetention is 0, then exit (not allowd on FS)
# 04/09/25 set $syncCmd based on platform  - version 1.4
# 04/10/25 check if serverInstDir exist and if not, then exit because it might be mis-configured
# 05/07/25 added sudoCommand parameter in config file - version 1.5
# 03/22/25 use common functions from $funcFile
# 05/23/25 support multiple flashsystems per instance - version 1.6
# 05/28/25 add freeze and unfreeze command for AIX
# 06/12/25 remove hard-coding of /usr/local/bin
# 06/12/25 AIX compatibility: convert sed /\t/ to sed / / - version 1.7
# 08/06/25 differentiate between Hyperswap and PBHA in function check_apivolumecopy
# 08/06/25 put function check_apivolumecopy in fsnapfunctions
# 02/12/26 add command line parameter -i instName, do not suspend and resume db if consistentSnap=false in config file - version 1.8
# 04/01/26 introduce global parameters maxCheckSnapCount and sleepTime for checking SGC completion after create
# 04/12/26 use apiCredentials in config file
# 04/13/26 print version of global functions (fsnapfunctions.sh)
# 04/24/26 remove initialization of configuration parameter arrays (moved to fsnapfunctions.sh)
# 08/12/26 re-exec as instance user when script is run as root (-i instUser required) - version 1.8 (Dominic)
# 08/13/26 add structured logging functions (log_info, log_warn, log_debug, log_error) - version 1.8 (Dominic)
# 08/31/26 add advice on config file permissions when running as root using -i $instUser - version 1.9

#---------------------------------------
# Global parameters
#---------------------------------------
# common functions file
funcFile="fsnapfunctions.sh"

# maximum number of retries to suspend the Db
maxSuspendRetry=5

# number of second to sleep inbetween of suspend retries
suspendWait=50

# maximum number of cycles to check for SGC to become active
# maximum check time = maxCheckSnapCount * sleepTime
maxCheckSnapCount=20
sleepTime=1

# platformspecific command to freeze the file system
freezeCmd_Linux="/usr/sbin/fsfreeze"
freezeCmd_Aix="/usr/sbin/chfs"

# platformspecific command to sync file system
syncCmd_Linux="/usr/bin/sync"
syncCmd_Aix="/usr/sbin/sync"

# determine operating system, comes from functions
# os=$(uname -s)

# version of the program
ver=1.9


# -----------------------------------------------------------------
# function usage 
#
# -----------------------------------------------------------------
function usage()
{
  echo
  log_error "$1"
  echo -e "\nUsage: fsnap-create.sh -r | --run [-i instanceUser | -h | --help]"
  echo "  -r | --run:  Create SGC. (required)"
  echo "  -i instance-user-name:  Name of the instance (user) for which SGC are created (optional). Default is the user executing the command."
  echo "  -h | --help: print the usage. (optional)"
  echo
  return 0
}


# -----------------------------------------------------------------
# function create_apisnapshot creates SGC using the REST API
#
# Requires config parameter
# vgName, snapName, snapretention, apiServer, TOKEN
# -----------------------------------------------------------------
function create_apisnapshot()
{
  frc=0

  # create snapshot
  rmsg=""
  log_info "Creating SGC $snapName for volume group $vgName on FlashSystem $apiServer (retention=$snapRet, safeguarded=$safeGuarded)"
  rmsg=$(curl -k -X POST --url "https://$apiServer/rest/v1/addsnapshot" \
  --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
  --data-raw '{
    "volumegroup": "'"$vgName"'", 
    "name": "'"$snapName"'",
    "retentiondays": "'$snapRet'",
    "safeguarded": '$safeGuarded'
  }' 2>/dev/null)
  frc=$?
  # log_debug "rc=$frc, Message=$rmsg"
  # frc is usually 0, message contains string "successfully created"
  if [[ ! $frc = 0 || -z $(echo "$rmsg" | grep "successfully created") ]]; then
    log_error "Creating SGC $snapName on volume group $vgName failed (rc=$frc, message=$rmsg)."
    return 1
  else
    log_info "Successfully created SGC $snapName on volume group $vgName"
  fi

  # Avoid FlashSystem request limits
  sleep $sleepTime 

  # determine if the SGC state is active for the volume group.
  log_info "Checking if SGC $snapName for volume group $vgName on FlashSystem $apiServer was created successfully"
  snapState=""
  count=1
  while [[ ! $snapState = "active" && ! $count = $maxCheckSnapCount ]]; do
    snapState=$(curl -k -X POST --url "https://$apiServer/rest/v1/lsvolumegroupsnapshot" \
    --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
    --data-raw '{
      "volumegroup": "'$vgName'",
      "snapshot": "'$snapName'"
     }' 2>/dev/null | jq -r ' .[] | [ .state ] | @csv ' 2>/dev/null | sed 's/",/ /g' | sed 's/\"//g' )
    rc=$?
    # log_debug "rc=$rc, snapState=$snapState"
    if [[ ! $rc = 0 || -z $snapState ]]; then
      count=$maxCheckSnapCount
    else
      log_debug "Checking state of SGC $snapName on volume group $vgName loop $count result: $snapState"
      (( count = count + 1 ))
      sleep $sleepTime
    fi
  done
  if [[ ! $snapState = "active" ]]; then
    log_error "SGC $snapName on volume group $vgName is not active (Maxloops=$maxCheckSnapCount, snapState=$snapState, count=$count)"
    log_error "  Check the SGC state on the FlashSystem. Delete the snapshots that were created at this point in time and try again."
    return 1
  fi

  log_info "SGC was created successfully (snapState=$snapState, check count=$count)"
  return 0

}


# -----------------------------------------------------------------
# function unfreeze_resume unfreezes the file systems and resumes the DB
# 
# This function is called from various places after the Db was suspended
#
# Requires config parameter
# freezeCmd, arrLen, apiServer_Arr, fSystems_Arr, sudoCmd, instUser
# -----------------------------------------------------------------
function unfreeze_resume()
{

  ### unfreeze the file systems
  if [[ -a $unfreezeCmd ]]; then
    log_info "Unfreeze file systems."
    log_debug "command=$unfreezeCmd"
    j=0
    frc=0
    while (( j <= arrLen ));
    do
      apiServer=${apiServer_Arr[$j]}:${apiPort_Arr[$j]}
      fSystems=${fSystems_Arr[$j]}
      fsName=""
      for fsName in $(echo "$fSystems" | sed 's/,/ /g')
      do
        $sudoCmd $unfreezeCmd $fsName
	      (( frc = frc + $? ))
	      # echo "  DEBUG: $unfreezeCmd $fsName ended with frc=$frc"
      done
      (( j = j + 1 ))
    done
    if (( frc > 0 )); then
      log_error "failed to unfreeze one or more file systems (rc=$frc). Manually unfreeze the file systems and try again."
      log_error "  Manually unfreeze all file systems using command: $freezeCmd --unfreeze fsName"
      log_error "  Afterwards resume the database as instance user:  db2 restart db TSMDB1 write resume"
      log_error "  Afterwards try again to create a snapshot."
      return 1
    fi
  fi

  ### resume protect Db
  if [[ $consistentSnap == "true" ]]; then
    log_info "resuming Db for instance $instUser"
    frc=0
    db2_log_start
    db2 set write resume for db >"$_DB2_FIFO" 2>&1; frc=$?
    db2_log_stop
    if (( frc > 0 )); then
      log_error "failed to resume the instance Db (rc=$frc). This is a critical error. Stop the instance or Db and run 'db2 restart db $dbName write resume'."
      db2_log_start
      db2 commit           >"$_DB2_FIFO" 2>&1
      db2 disconnect $dbName >"$_DB2_FIFO" 2>&1
      db2_log_stop
      return 1
    fi

    # commit and disconnect from Db
    db2_log_start
    db2 commit           >"$_DB2_FIFO" 2>&1
    db2 disconnect $dbName >"$_DB2_FIFO" 2>&1
    db2_log_stop
  else
    log_warn "database will not be resumed because consistent SGC is set to $consistentSnap."
  fi

  return 0
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


### check if the run parameter is specified
# save original arguments before the shift loop consumes them
origArgs=("$@")
run=0
while [[ ! -z "$*" ]];
do
  case "$1" in
  "-i") shift 1
        if [[ -z $1 ]]; then
          usage "Instance user name is not specified."
          exit 1
        else
          instUser=$1
        fi;;
  "-r" | "--run") run=1;;
  "-h" | "--help")
        usage "command usage"
        exit 1;;
  *)    usage "wrong argument $1"
        exit 1;;
  esac
  shift 1
done
if (( run == 0 )); then
  usage "run flag not specified. Specify -r with the command."
  exit 1
fi

### if running as root, re-exec the entire script as the instance user
# This ensures all commands (db2, freeze, sync, curl) run in the instance user's environment.
# sudo resets the environment (env_reset in sudoers), so we use 'bash --login -c' to source
# the instance user's login profile (which sources sqllib/db2profile and sets PATH for db2).
if [[ $(id -u) -eq 0 && $instUser != "root" ]]; then
  log_info "Running as root - re-executing script as instance user '$instUser'."
  exec sudo -u "$instUser" bash --login -c "\"$0\" ${origArgs[*]@Q}"
  # exec replaces this process; the lines below are never reached
  log_error "Failed to re-execute script as user '$instUser'."
  exit 1
fi

### source the instance user's DB2 environment if db2 is not yet in PATH
# This covers the case where the script is invoked directly (not via sudo) in a non-login shell.
if [[ -z $(command -v db2 2>/dev/null) ]]; then
  db2profile=$(eval echo "~$instUser/sqllib/db2profile")
  if [[ -f $db2profile ]]; then
    # echo "DEBUG: sourcing $db2profile"
    . "$db2profile"
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


### setting unique parameters
sudoCmd=${sudoCmd_Arr[0]}
dbName=${dbName_Arr[0]}
consistentSnap=${consistentSnap_Arr[0]}

### when consistent SGC are required, then the current user must match the instance user
curUser=$(id -un)
if [[ $consistentSnap == "true" && $curUser != $instUser ]]; then
   log_error "To create consistent SGC the user running command must be identical to the instance user."
   log_error "  Consistent SGC can only be created by the instance user."
   log_error "  If running as root, ensure sudo is configured to allow 'sudo -u $instUser' and specify -i $instUser."
   log_debug "current user = $curUser, instance user = $instUser"
   exit 1
fi

### platform specific commands
if [[ $os = "AIX" ]]; then
  if [[ ! -a $freezeCmd_Aix || ! -a $syncCmd_Aix  ]]; then
    log_error "Utilities to freeze and sync the file systems are not installed."
    log_error "  Install utilities fsfreeze and sync (Linux) or adjust global variables freezeCmd and syncCmd in this script to use the proper tools."
    exit 1
  else
    syncCmd="$syncCmd_Aix"
    freezeCmd="$freezeCmd_Aix -a freeze=60"
    unfreezeCmd="$freezeCmd_Aix -a freeze=0"
  fi
else
  if [[ ! -a $freezeCmd_Linux || ! -a $syncCmd_Linux  ]]; then
    log_error "Utilities to freeze and sync the file systems are not installed."
    log_error "  Install utilities fsfreeze and sync (Linux) or adjust global variables freezeCmd and syncCmd in this script to use the proper tools."
    exit 1
  else
    syncCmd="$syncCmd_Linux"
    freezeCmd="$freezeCmd_Linux --freeze"
    unfreezeCmd="$freezeCmd_Linux --unfreeze"
  fi
fi
log_debug "On platform $os: syncCmd=$syncCmd, freezeCmd=$freezeCmd, unfreezeCmd=$unfreezeCmd"


### check if the instance is running on this node under the instance user $instUser, if not then exit
if [[ $consistentSnap == "true" ]]; then
  if [[ $dbName == "TSMDB1" ]]; then
    ### check for dsmserv (TSM)
    # procExists=$(pgrep -l -u $instUser dsmserv 2>/dev/null)
    procExists=""
    procExists=$(ps -u $instUser | grep dsmserv | grep -v grep)
    if [[ -z $procExists ]]; then
      log_warn "the TSM instance $instUser is not running on server $(hostname). Normal exit."
      log_info "============================================================================="
      exit 0
    fi
  else
    ### check for MediaManager (TSLM)
    # procExists=$(pgrep -l -u $instUser MediaManager)
    procExists=""
    procExists=$(ps -u $instUser | grep MediaManager | grep -v grep)
    if [[ -z $procExists ]]; then
      log_warn "the ERMM instance $instUser is not running on server $(hostname). Normal exit."
      log_info "============================================================================="
      exit 0
    fi
  fi
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

### check if hyperswap is enabled on any volume of the volume group
i=0
while (( i <= arrLen ));
do
  apiServer=${apiServer_Arr[$i]}:${apiPort_Arr[$i]}
  TOKEN=${token_Arr[$i]}
  vgsToSnap=${vgsToSnap_Arr[$i]}
  vgName=""
  rc=0
  log_info "Checking volume replication for volume groups ($vgsToSnap) on FlashSystem $apiServer."
  for vgName in $(echo "$vgsToSnap" | sed 's/,/ /g')
  do
    # log_debug "volume group=$vgName"
    checkSeverity="WARNING"
    check_apivolumecopy
    rc=$?
    if (( rc > 0 )); then
      log_warn "$frc volumes in volume group $vgName on FlashSystem $apiServer have hyperswap enabled."
    fi
  done
  (( i = i + 1 ))
  # sleep to let the API settle if there are more elements to process
  if (( i <= arrLen )); then
    sleep $multiSysSleep
  fi
done


### suspend protect Db
if [[ $consistentSnap == "true" ]]; then
  log_info "Suspending the data base for instance $instUser"
  db2_log_start
  db2 connect to $dbName >"$_DB2_FIFO" 2>&1; rc=$?
  db2_log_stop
  if (( rc > 0 )); then
    log_error "failed to connect to instance Db, exiting."
    log_error "============================================================================="
    exit 3
  fi
  db2_log_start
  db2 set write suspend for db >"$_DB2_FIFO" 2>&1; rc=$?
  db2_log_stop
  i=0
  # if suspend failed, then try it again
  while (( rc > 0 && i < maxSuspendRetry )); do
    (( i= i + 1 ))
    sleep $suspendWait
    log_info "$i. retry to suspend the database."
    db2_log_start
    db2 set write suspend for db >"$_DB2_FIFO" 2>&1; rc=$?
    db2_log_stop
  done
  if (( rc > 0 )); then
    log_error "failed to suspend the instance Db, exiting."
    db2_log_start
    db2 commit             >"$_DB2_FIFO" 2>&1
    db2 disconnect $dbName >"$_DB2_FIFO" 2>&1
    db2_log_stop
    log_error "============================================================================="
    exit 3
  fi
else
  log_warn "database will not be suspended because consistent SGC is set to $consistentSnap."
fi

### sync and freeze file systems
log_info "Sync and freeze file systems."
# sync command should work without sudo, otherwise use $sudoCmd $syncCmd
$syncCmd
sleep $sleepTime
if [[ -a $freezeCmd ]]; then
  i=0
  while (( i <= arrLen ));
  do
    fSystems=${fSystems_Arr[$i]}
    fsName=""
    rc=0
    for fsName in $(echo "$fSystems" | sed 's/,/ /g')
    do
      $sudoCmd $freezeCmd $fsName
	    (( rc = rc + $? ))
	    # echo "  DEBUG: $freezeCmd $fsName ended with rc=$rc"
    done
    if (( rc > 0 )); then
      log_error "failed to freeze one or more file systems (rc=$rc). Make sure the file systems are not in use and try again."
      # unfreeze and resume Db
      unfreeze_resume
      log_error "============================================================================="
      exit 3
    else
      (( i = i + 1 ))
    fi
  done
fi


### Now create FlashSystem snapshots for all volume groups
log_info "creating snapshots for all volume groups: ${vgsToSnap_Arr[@]}"

# determine date string as SGC name postfix
snapSuffix=$(date +%Y%m%d%H%M%S)


# initialize variable and iterate through the vgsToSnap and create snapshot
i=0
while (( i <= arrLen ));
do
  apiServer=${apiServer_Arr[$i]}:${apiPort_Arr[$i]}
  TOKEN=${token_Arr[$i]}
  vgsToSnap=${vgsToSnap_Arr[$i]}
  snapRet=${snapRet_Arr[$i]}
  safeGuarded=${safeGuarded_Arr[$i]}
  snapPrefix=${snapPrefix_Arr[$i]}
  if [[ $consistentSnap == "false" ]]; then
    snapPrefix=$snapPrefix"-nc"
  fi
  snapName="$snapPrefix-$snapSuffix"
  vgName=""
  rc=0
  for vgName in $(echo "$vgsToSnap" | sed 's/,/ /g')
  do
    # echo "  DEBUG: volume group=$vgName"
    create_apisnapshot
    (( rc = rc + $? ))
  done
  if (( rc > 0 )); then
    # unfreeze and resume Db
    unfreeze_resume
    log_error "SGC create failed on $apiServer, check the output above and try again. The SGC is NOT GOOD."
    log_error "======================================================================================================"
    exit 4
  else 
    (( i = i + 1 ))
    # sleep to let the API settle if there are more elements to process
    if (( i <= arrLen )); then
      sleep $multiSysSleep
    fi
  fi
done


# unfreeze file systems
unfreeze_resume
rc=$?
if (( rc > 0 )); then
  log_error "program $0 completed with errors."
  log_error "============================================================================="
  exit 5
else
  log_info "program $0 completed successfully."
  log_info "============================================================================="
  exit 0
fi

exit $rc