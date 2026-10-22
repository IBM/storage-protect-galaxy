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
# Name: fsnap-restore.sh
# Desc: restore volume groups from SGC in FlashSystem and start the database manager
#
# Dependencies:
# This scripts must run on the host where the instance is running, it must be run by the instance user and uses sudo or the REST API
# The Storage Protect instance must be stopped.
# Requires jq in $jqPath and fsfreeze in $freezeCmd
# Requires sudoCommand to run mount and unmount 
# This script uses the Flashsystem REST API to query FlashSystem
# This script requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - database name
# - volume group names
# - file systems
# - server instance directory
# - sudo command
# - API server: optional, when REST API is used. In this case, the SGC restore is not performed.
#
# Usage:
# fsnap-restore.sh snapshot-name
#  snapshot-name: Name of the SGC to be restored for all relevant volume groups.
#  -h | --help:   Show this help message (optional)."
# 
#********************************************************************************

# History
#----------
# 11/04/24 Initial implementation - renamed to fsnap-restore.sh -  version 1.1 (N. Haustein)
# 11/13/24 add check if volumes are online
# 11/29/24 list autorestore option (version 1.2)
#          for manual restore list commands for copy & paste
# 02/21/25 Replace INST_DIR by DB2_HOME
# 03/07/25 use ps instead of pgrep (AIX compatibility)
# 03/25/25 AIX compatibility changes, add sudo command variable, add variable serverInstDir - version 1.3
# 03/31/25 Add message at the end to enable Hyperswap when it was enabled before
# 01/04/25 Add message to become instance user before starting the Db2
# 04/09/25 add serverInstDir to config file - version 1.4
# 04/10/25 present warning instead of error if directory $serverInstDir does not exist
# 04/14/25 when autoRestore=false then do not check hyperswap again, because it is checked in the main path - version 1.5
# 05/07/25 added sudoCommand parameter in config file - version 1.6
# 03/22/25 use common functions from $funcFile
# 05/26/25 support multiple flashsystems per instance - version 1.7
# 06/12/25 remove hard-coding of /usr/local/bin
# 06/12/25 AIX compatibility: convert sed /\t/ to sed / / - version 1.8
# 06/13/25 AIX compatibility: upon mount check use df -P instead of df
# 06/23/25 improve console messages for manual restore
# 08/06/25 differentiate between Hyperswap and PBHA in function check_apivolumecopy
# 08/06/25 put function check_apivolumecopy in fsnapfunctions
# 08/13/25 order file systems for mount and unmount using sort (-r) - version 1.9
# 02/12/26 add command line parameter -i instName, do not check and start the instance if consistentSnap false in config file - version 2.0
# 04/12/26 use apiCredentials in config file 
# 04/13/26 print version of global functions (fsnapfunctions.sh)
# 04/24/26 remove initialization of configuration parameter arrays (moved to fsnapfunctions.sh)
# 06/08/26 added sudoCmd when running /usr/bin/df
# 06/09/26 added messages to disable replication after restore - version 2.1
# 08/13/26 add structured logging functions (log_info, log_warn, log_debug, log_error) - version 2.1 (Dominic)


#---------------------------------------
# global parameters
#---------------------------------------
# common functions file
funcFile="fsnapfunctions.sh"

# initialized snapName to be given as argument
snapName=""

# Sleep time in seconds and max number of loops checking for restore completion in check_apivolumestatus
# max time for completion checking is (inProgressSleep * maxInProgressCount)
inProgressSleep=5
maxInProgressCount=100

# Refresh the token after the specified number of loops waiting for SGC restore completion
tokenRefreshLoops=100

# determine home directory of instance user
instDir=$HOME

# program version
ver=2.1

# -----------------------------------------------------------------
# function usage 
#
# -----------------------------------------------------------------
function usage()
{
  echo
  log_error "$1"
  echo -e "\nUsage: fsnap-restore.sh -s snapName [-i instanceUser | -h | --help]"
  echo "  -s snapName: Name of the SGC to be restored (required)."
  echo "  -i instance-user-name:  Name of the instance (user) for which SGC are restored (optional). Default is user executing the command."
  echo "  -h | --help: print the usage. (optional)"
  echo

  return 0
}



# -----------------------------------------------------------------
# function check_apisnapshot to check if a snapshotname exists
#
# Requires $configFile, vgName, snapName
# check if SGC snapName exists on vgName
#
# -----------------------------------------------------------------
function check_apisnapshot()
{
  # echo "DEBUG: Entering check_apisnapshot()"
  sName=""
  frc=0

  sleep 1

  # check if SGC snapName exists on volume group vgName
  sName=$(curl -k -X POST --url "https://$apiServer/rest/v1/lsvolumegroupsnapshot" \
  --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
  --data-raw '{
    "volumegroup": "'$vgName'",
    "snapshot": "'$snapName'"
  }' 2>/dev/null | jq -r ' .[] | [ .name ] | @csv ' 2>/dev/null | sed 's/",/ /g' | sed 's/\"//g' )
  frc=$?
  
  if [[ ! $frc = 0 || -z $sName ]]; then
    log_error "Failed to check SGC $snapName on volume group $vgName (rc=$frc, snapshot=$sName)"
    return 1
  fi
  
  if [[ $snapName = $sName ]]; then
    return 0
  else
    return 1
  fi
 
}


# -----------------------------------------------------------------
# function restore_apisnapshot restores the SGC $snapName on volume group $vgName
#
# Requires $configFile, vgName, snapName
#
# -----------------------------------------------------------------
function restore_apisnapshot()
{
  # echo "DEBUG: Entering check_apisnapshot()"
  frc=0
  
  # sleep to avoid concurrency
  sleep 1
  
  log_info "Invoking SGC restore for SGC $snapName for volume group $vgName on Flashsystem $apiServer."
  rmsg=""
  rmsg=$(curl -k -X POST --url "https://$apiServer/rest/v1/restorefromsnapshot" \
  --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
  --data-raw '{
    "volumegroup": "'"$vgName"'", 
    "snapshot": "'"$snapName"'"
  }' 2>/dev/null)
  frc=$?
  # echo "DEBUG: rc=$frc, Message=$rmsg"
  # frc is usually 0, message is "" when successfull, otherwise not
  if [[ ! $frc = 0 || ! $rmsg = '""' ]]; then
    log_error "Restoring SGC $snapName on volume group $vgName failed (rc=$frc, message=$rmsg)."
    return 1
  else
    log_info "Successfully restored SGC $snapName on volume group $vgName."
    return 0
  fi
}

# -----------------------------------------------------------------
# function check_apivolumestatus checks if volumes are online for volume group $vgName
#
# This function is used for two purposes: 
# a) check volume status prior to restore
# b) check volume status after restore to confirm that restore was successful
#
# Requires vgName
#
# Processing: performs lsvdisk and checks if volume status = online
#
# Input: $1: message
#
# Output
#  0: success (all volumes are online)
#  1: failure (not all volumes are online)
#
# -----------------------------------------------------------------
function check_apivolumestatus()
{
  msg=$1
  if [[ -z $msg ]]; then
    msg="volume status"
  fi
# determine volume status to be online
  log_info "Checking for $msg in volume group $vgName"
  sleep 1
  item=""
  frc=0

  while read -r line;
  do 

    # echo "  DEBUG: $line"
    item=$(echo $line | awk '{print $2}')
    if [[ ! $item = "online" ]]; then
      log_warn "Status of volume $(echo $line | awk '{print $1}') in volume group $vgName is $item."
     (( frc = frc + 1 ))
    # else 
      # echo "  DEBUG: Status of volume $(echo $line | awk '{print $1}') in volume group $vgName is $item."
    fi
  done <<< $(curl -k -X 'POST' --url "https://$apiServer/rest/v1/lsvdisk" \
  --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
  --data-raw '{
   "filtervalue": "volume_group_name='$vgName'"
  }' 2>/dev/null  | jq -r ' .[] | [ .name, .status ] | @csv ' | sed 's/",/ /g' | sed 's/\"//g' )

  return $frc

}


# -----------------------------------------------------------------
# function check_apiusergroup checks if user is a group Administrator
#
# Requires $apiUser
#
# Output
#  0: success, user in group Administrator or SecurityAdmin
#  1: failure, user not in group Administrator or SecurityAdmin
#
# -----------------------------------------------------------------
check_apiusergroup()
{
  grpID=2
  grpID=$(curl -k -X 'POST' --url "https://$apiServer/rest/v1/lsuser/$apiUser" \
  --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" 2>/dev/null | jq -r ' . | [ .usergrp_id ] | @csv ' | sed 's/",/ /g' | sed 's/\"//g' )
  if [[ ! -z $grpID ]]; then
  if (( grpID > 1 )); then
    log_error "API user $apiUser does not have permission to restore SGC (group_ID=$grpID)."
    log_error "  Provide an API user with 'Administrator' privileges in the configuration file $configFile and try again."
    return 1
  else
    log_info "API user $apiUser has permission to restore SGC."
  fi
else
  log_error "Unable to determine the user group for API user $apiUser (response=$grpID)."
  log_error "  Check and provide a valid REST API user name with 'Administrator' privileges in config file $configFile"
  return 1
fi

  return 0
  
}


#---------------------------------------------------------------------------------
# Main
#---------------------------------------------------------------------------------

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
while [[ ! -z "$*" ]];
do
  case "$1" in
  "-s") shift 1
        if [[ -z $1 ]]; then
          usage "SGC name is not specified."
          exit 1
        else
          snapName=$1
        fi;;
  "-i") shift 1
        if [[ -z $1 ]]; then
          usage "Instance name not specified."
          exit 1
        else
          instUser=$1
        fi;;
  "-h" | "--help")
        usage "command usage"
        exit 1;;
  *)    usage "wrong argument $1"
        exit 1;;
  esac
  shift 1
done
if [[ -z $snapName ]]; then
  usage "SGC name to be restored not specified. Use the parameter -s snapName to specify the SGC name."
  exit 1
fi

### get the parameters for this instance user from the config_file
log_info "Parsing configuration parameters from config file $configFile."
parse_config
# log_debug "vgsToSnap=$vgsToSnap"

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


### setting unique config parameters
sudoCmd=${sudoCmd_Arr[0]}
dbName=${dbName_Arr[0]}
autoRestore=${autoRestore_Arr[0]}
serverInstDir=${serverInstDir_Arr[0]}
consistentSnap=${consistentSnap_Arr[0]}

### when consistent SGC are required, then the current user must match the instance user
curUser=$(id -un)
if [[ $consistentSnap == "true" && $curUser != $instUser ]]; then
   log_error "To restore consistent SGC the user running the command must be identical to the instance user."
   log_error "  Consistent SGC can only be restored by the instance user."
   log_debug "current user = $curUser, instance user = $instUser"
   exit 1
fi


### skip these steps when consistentSnap = false
if [[ $consistentSnap == "true" ]]; then
  ### Exit if we are in instance home directory
  curDir=$PWD
  if [[ "$curDir" = "$instDir" ]]; then
    log_error "The program cannot be started from the instance home directory ($curDir)."
    log_error "  As instance user change to some other the directory (e.g. /tmp). Make sure that the instance user profile is sourced."
    exit 1
  fi


  ### check that that instance is stopped, if not then exit
  log_info "Checking if the server instance is stopped."
  if [[ "$dbName" == "TSMDB1" ]]; then
    ### check for dsmserv (TSM)
    # procExists=$(pgrep -l -u $instUser dsmserv 2>/dev/null)
    procExists=""
    procExists=$(ps -u $instUser | grep dsmserv | grep -v grep)
    if [[ ! -z $procExists ]]; then
      log_error "TSM Instance $instUser is still running. It must be stopped for restore."
      log_debug "active process: $procExists"
      log_error "  Ensure you are running this program on the right instance server."
      exit 1
    fi
  elif [[ "$dbName" == "ERMM" ]]; then
    ### check for MediaManager (TSLM)
    # procExists=$(pgrep -l -u $instUser MediaManager 2>/dev/null)
    procExists=""
    procExists=$(ps -u $instUser | grep MediaManager | grep -v grep)
    if [[ ! -z $procExists ]]; then
      log_error "ERMM Instance $instUser is still running. It must be stopped for restore."
      log_debug "active process: $procExists"
      log_error "  Ensure you are running this program on the right instance server."
      exit 1
    fi
  else
    ### no TSM or TSLM
    log_error "Instance $instUser is not a Storage Protect or TSLM instance."
    exit 1
  fi
else
  log_info "Skipping check for server instance because consistent SGC is set to $consistentSnap"
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
log_info "Checking if hyperswap is enabled on any volume of the volume group."
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
    log_info "Checking volume replication for volume group $vgName on FlashSystem $apiServer"
    checkSeverity="ERROR"
    check_apivolumecopy
    (( rc = rc + $? ))
  done
  (( i = i + 1 ))
  # sleep to let the API settle if there are more elements to process
  if (( i <= arrLen )); then
    sleep $multiSysSleep
  fi
done
if (( rc > 0 )); then
  log_error "Hyperswap is enabled on some volumes. Remove HyperSwap configuration for the volume and try again."
  log_error "  To remove Hyperswap use the GUI or the CLI command:"
  log_error "  # rmvolumecopy -pool [pool-name-secondary-site] -removefcmaps [volume-name-or-id]"
  exit 4
else
  log_info "Hyperswap is not enabled on any volume in volume groups, continuing."
fi


### check if all volume of the volume groups are online
log_info "Checking volume status for all volume groups."
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
    check_apivolumestatus "volumes status"
    (( rc = rc + $? ))
  done
  (( i = i + 1 ))
  # sleep to let the API settle if there are more elements to process
  if (( i <= arrLen )); then
    sleep $multiSysSleep
  fi
done
if (( rc > 0 )); then
  log_error "Some volumes in volume groups are not online. Bring the volumes online and try again."
  exit 4
fi
log_info "All volumes are online, continuing."


### check that SGC exists on all relevant volume groups
log_info "Checking if SGC $snapName exists on all relevant volume groups."
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
    check_apisnapshot
    (( rc = rc + $? ))
  done
  (( i = i + 1 ))
  # sleep to let the API settle if there are more elements to process
  if (( i <= arrLen )); then
    sleep $multiSysSleep
  fi
done
if (( rc > 0 )); then
  log_error "SGC name $snapName does not exist on all relevant file systems and cannot be restored."
  exit 4
fi
log_info "SGC $snapName exists on all relevant volumegroups, continuing."


### autoRestore is true then perform automatic restore
if [[ $autoRestore = "true" ]]; then
  log_info "Performing automatic restore (autoRestore=$autoRestore)."
  # check if API user is Administrator
  log_info "Checking if Flashsystem REST API user $apiUser has permission to restore SGC:"
  rc=0
  i=0
  while (( i <= arrLen ));
  do
    apiServer=${apiServer_Arr[$i]}:${apiPort_Arr[$i]}
    TOKEN=${token_Arr[$i]}
    apiUser=${apiUser_Arr[$i]}
    check_apiusergroup
    (( rc = rc + $? ))
    (( i = i + 1 ))
    # sleep to let the API settle if there are more elements to process
    if (( i <= arrLen )); then
      sleep $multiSysSleep
    fi
  done
  if (( rc > 0 )); then 
    exit 4
  fi

  # need to leave the instance directory because the restore does not work when sitting there
  curDir=$(pwd)
  cd /tmp
  log_debug "Changed directory from $curDir to $PWD"

  # unmount the file systems
  log_info "Unmounting all relevant file systems"
  i=0
  rcc=0
  while (( i <= arrLen ));
  do
    fSystems=${fSystems_Arr[$i]}
    fsName=""
    rc=0
    for fsName in $(echo "$fSystems" | sed 's/,/ /g' | xargs -n1 | sort -r)
    do
      $sudoCmd umount $fsName 
	     rc=$?
	     if (( rc > 0 )); then
	       log_warn "Failed to unmount $fsName (rc=$rc), fuser: $(fuser $fsName)"
	       log_warn "  Check if the file system is already unmounted. If the file system is unmounted, then continue. If not, then try to unmount it using: umount -f $fsName"
	       log_warn "  Also make sure that the instance user $instUser uses bash as login shell. Korn shell causes the device busy message."
	       echo "======================================================================================"
	       echo "PRESS ENTER if you want to continue, or CTRL-C if you want to exit and restart later."
	       echo
	       read a
	     fi
    done
    (( i = i + 1 ))
    (( rcc = rcc + rc ))
  done
  if (( rcc > 0 )); then
    log_warn "Unmount failed on some file systems and was confirmed by user. Continuing with SGC restore."
  fi

  # sleep to let is settle
  sleep 1
  
  # iterate through the vgsToSnap and restore the snapshot
  log_info "Restoring snapshots for all relevant volume groups."
  rc=0
  i=0
  while (( i <= arrLen ));
  do
    apiServer=${apiServer_Arr[$i]}:${apiPort_Arr[$i]}
    TOKEN=${token_Arr[$i]}
    apiUser=${apiUser_Arr[$i]}
    vgName=""
    for vgName in $(echo "$vgsToSnap" | sed 's/,/ /g')
    do
      # restore via rest api
	    restore_apisnapshot
      (( rc = rc + $? ))
    done
    if (( rc > 0 )); then
      log_error "SGC restore FAILED for snap $snapName on $apiServer."
      log_error "  Review the console outputs and the Flashsystem logs. Correct the problem and restart the program."
      exit 6
    else
      (( i = i + 1 ))
      if (( i <= arrLen )); then
        sleep $multiSysSleep
      fi
    fi
  done
  
  # sleep to settle
  sleep 1

  # check if restore_in_progress on any volume group and wait until it finishes
  log_info "Checking restore completion for all relevant volume groups."
  rc=1
  count=0
  while (( rc > 0 && count < $maxInProgressCount )); 
  do 
    i=0
    rc=0
    while (( i <= arrLen ));
    do
      apiServer=${apiServer_Arr[$i]}:${apiPort_Arr[$i]}
      TOKEN=${token_Arr[$i]}
      apiUser=${apiUser_Arr[$i]}
      vgName=""
      for vgName in $(echo "$vgsToSnap" | sed 's/,/ /g')
      do
        # echo "  DEBUG: volume group=$vgName"
        # check for restore_in_progress on volume group
        check_apivolumestatus "restore completion"
        (( rc = rc + $? ))
      done
      (( i = i + 1 ))
      # sleep to let the API settle if there are more elements to process
      if (( i <= arrLen )); then
        sleep $multiSysSleep
      fi
    done
	  (( count = count + 1))
    if (( rc > 0 )); then
      log_warn "Check loop $count of $maxInProgressCount. Not all volumes are online (rc=$rc)."
	    sleep $inProgressSleep
	    if (( count % 10 == 0 )); then
	      ### get API token
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
	    fi
	  fi
  done
  if (( rc > 0 && count == $maxInProgressCount )); then
    log_error "SGC restore failed, some volumes are not online."
    log_error "  Check the console output. Bring all volumes online and try again."
    log_error "  ATTENTION: Do not mount the file systems because some volumes are not online."
    exit 6
  fi
  
  # sleep to let it settle
  sleep 1

  # mount the file system
  log_info "Mounting all relevant file systems"
  i=0
  rc=0
  while (( i <= arrLen ));
  do
    fSystems=${fSystems_Arr[$i]}
    fsName=""
    for fsName in $(echo "$fSystems" | sed 's/,/ /g' | xargs -n1 | sort)
    do
      # echo "  DEBUG: file system=$fsName"
      $sudoCmd mount $fsName
      (( rc = rc + $? ))
    done
    (( i = i + 1 ))
  done
  if (( rc > 0 )); then
    log_error "failed to mount one or more file systems (rc=$rc). Investigate the problem and mount the file systems manually."
    log_error "  Mount all file systems again and try the restore again."
    exit 5
  fi

  log_info "SGC restore finished."
  echo -e "\n-------------------------------------------------------------------------------------------------\n"

  ### start db2 and instance only if consistentSnap=true
  if [[ $consistentSnap == "true" ]]; then
    ### starting the Db manager and resuming the DB
    # go back to the instance dir
    log_debug "Changing to instance home directory $instDir"
    cd $instDir

    log_info "Starting Db manager and resuming the DB $dbName."
    db2start
    db2 restart db $dbName write resume
    rc=$?
    if (( rc > 0 )); then
      log_error "failed to resume the instance Db. This is a critical error. Stop the instance or Db and run db2 restart db $dbName write resume."
      exit 7
    fi
    ### starting the instance
    if [[ "$dbName" == "TSMDB1" ]]; then
      # change to serverInstDir
      if [[ -d $serverInstDir ]]; then
        cd $serverInstDir
      else
        log_error "Server instance directory $serverInstDir does not exist."
        log_error "  Either the config parameter serverInstDir is not set correctly in $configFile,"
        log_error "  or the associated file system is not mounted correctly. Make the server instance directory"
        log_error "  $serverInstDir available and try again."
        exit 8
      fi
      echo -e "\n-------------------------------------------------------------------------------"
      log_info "starting the instance in maintenance mode, client session are not allowed."
      echo "      Check the instance and if everything is good, stop it (halt) and start it as service."
      echo -e "\nIMPORTANT: If node replication is enabled, then disable replication while in maintenance mode using commmand: disable replication"
      echo -e "-------------------------------------------------------------------------------\n"
      dsmserv maintenance
      # at the end print a message to activate hyperswap
      echo -e "\n-------------------------------------------------------------------------------"
      echo -e "ACTION: Do not forget the enable Hyperswap, if it was enabled before the restore."
      echo -e "        To enable  Hyperswap use the GUI or the CLI command:"
      echo -e "        # addvolumecopy -inconsistentownershipgroup -iogrp [io-group-secondary-site] -pool [pool-name-secondary site] -unit b [volume-name-or-id]"
      echo -e "\nACTION: If node replication is enabled, then disable replication while in maintenance mode using commmand: disable replication"
      echo -e "        To re-synchronize source and target server follow the procedure to Replicate client node data after a database restore"
      echo -e "        (https://www.ibm.com/docs/en/storage-protect/8.2.1?topic=replication-replicating-client-node-data-after-database-restore)"
      echo -e "-------------------------------------------------------------------------------\n"
      exit 0
    elif [[ "$dbName" == "ERMM" ]]; then
      ### message for MediaManager (TSLM)
      log_info "the TSLM server could be started!"
      echo "      Run ermmStart with the ermm user and check if the server come up."
      echo "      Start the Library Manager using ermmLmStart if everything is OK!"
      exit 0
    else
      ### no TSM or TSLM
      log_error "Instance $instUser is not a Storage Protect or TSLM instance."
      exit 1
    fi
  else
    log_info "Automatic restore of SGC $snapName for instance $instUser on FlashSystem $apiServer finished."
    log_info "  Instance will not be started because consistent SGC is set to $consistentSnap."
  fi

#-----------------------------------------------------------------------------------
# if autoRestore false then do not perform restore but print instructions 
#-----------------------------------------------------------------------------------


else
  # need to leave the instance directory because the restore does not work when sitting there
  curDir=$(pwd)
  cd /tmp
  
  ### print instruction to unmount all relevant file systems
  echo
  echo "==========================================================================="
  echo "#                                                                         #"
  echo "# INFO: Manual restore requested. Follow the instructions on the screen.  #"
  echo "#       Press 'enter' to continue.                                        #"
  echo "#                                                                         #"
  echo "---------------------------------------------------------------------------"
  read a

  ### Hyperswap was checked before, so we can skip it here.

  ### File system unmount
  
  log_info "All relevant file systems must be unmounted. Follow instructions below."
  echo -e "      This may require root privileges."
  echo -e "---------------------------------------------------------------------------\n"
  copyString=""
  i=0
  rc=0
  while (( i <= arrLen ));
  do
    fSystems=${fSystems_Arr[$i]}
    fsName=""
    for fsName in $(echo "$fSystems" | sed 's/,/ /g' | xargs -n1 | sort -r)
    do
      # echo "  DEBUG: file system=$fsName"
      echo "ACTION:  Unmount the file system $fsName on the SP server"
	    echo -e "         # umount $fsName\n"
	    echo
	    copyString="$copyString umount $fsName;"
    done
    (( i = i + 1 ))
  done
  echo -e "COPY COMMAND: You can copy and paste the command below to accommodate the action:\n$copyString"  

  # ask for the umount completion
  echo
  echo "---------------------------------------------------------------------------"
  echo "ACTION: Press 'enter' when all file system are unmounted."
  echo 
  echo "NOTE:   If one or more file systems are already unmounted, then no action is required."
  echo "        If the unmount fails, then try to force unmount using the command: umount -f. "
  echo "        Also make sure that the instance user $instUser uses bash as login shell. Korn shell may cause the device busy message."
  echo
  echo "        If unmounting fails, then press no or CTRl-C and resolve the problem."
  echo "        You can restart this script any time after the problem was resolved."
  echo "---------------------------------------------------------------------------"
  echo -e "Your Input [enter | CTRL-C]: \c"
  read a

  # check that file systems are unmounted
  log_info "Checking file systems to be unmounted"
  i=0
  rc=0
  rcc=0
  while (( i <= arrLen ));
  do
    fSystems=${fSystems_Arr[$i]}
    fsName=""
    for fsName in $(echo "$fSystems" | sed 's/,/ /g')
    do
      rc=0
      ${sudoCmd_Arr[$i]} /usr/bin/df -P | awk '{ print $6 }' | grep -q -w "$fsName"
	    rc=$?
 	    if (( rc == 0 )); then
 	      log_error "file system $fsName is not unmounted"
 	      (( rcc = rcc + 1 ))
 	    fi
    done
    (( i = i + 1 ))
  done
  if (( rcc > 0 )); then
    log_error "One or more file systems are not unmounted. Unmount all relevant file systems and restart the restore."
    log_error "==========================================================================="
    exit 5
  fi

  log_info "All file systems are unmounted."
  log_info "==========================================================================="
  
  
  ### print instruction to do perform the SGC restore
  log_info "Restore SGC for all relevant volume groups (${vgsToSnap_Arr[@]})"
  echo -e "NOTE: The Flashsystem user must be in user group Administrator!\n"
  i=0
  rc=0
  copyString=""
  while (( i <= arrLen ));
  do
    vgsToSnap=${vgsToSnap_Arr[$i]}
    apiServer=${apiServer_Arr[$i]}
    vgName=""
    for vgName in $(echo "$vgsToSnap" | sed 's/,/ /g')
    do
      echo "ACTION:  restore SGC $snapName for volume group $vgName on FlashSystem $apiServer with Administrator privileges:"
      echo -e "         # restorefromsnapshot -snapshot $snapName -volumegroup $vgName\n"
      copyString="$copyString restorefromsnapshot -snapshot $snapName -volumegroup $vgName;"
    done
    (( i = i + 1 ))
  done
  echo -e "COPY COMMAND: You can copy and paste the command below to accommodate the action:\n$copyString"


  # wait for the SGC restore to finish and continue
  echo
  echo "---------------------------------------------------------------------------"
  echo "ACTION: Wait for the completion of the SGC restores on the Flashsystem. "
  echo 
  echo "ACTION: Enter 'yes' if the SGC restore completed successfully on all volume groups."
  echo 
  echo "NOTE:   If the SGC restore failed, then enter no or CTRl-C and resolve the problem."
  echo "        You can restart this script any time after the problem was resolved."
  echo "---------------------------------------------------------------------------"
  echo -e "Your Input [yes | no]: \c"
  read a
  echo 

  if [[ "$a" == "yes" ]]; then
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

    # check if there are restore in progress
    log_info "Checking if SGC restores are finished and volumes are online."
    i=0
    rc=0
    while (( i <= arrLen ));
    do
      vgsToSnap=${vgsToSnap_Arr[$i]}
      vgName=""
      for vgName in $(echo "$vgsToSnap" | sed 's/,/ /g')
      do
        # echo "  DEBUG: volume group=$vgName"
        # check for restore_in_progress on volume group
	      check_apivolumestatus "restore completion"
        (( rc = rc + $? ))
      done
      (( i = i + 1 ))
      if (( i <= arrLen )); then
        sleep $multiSysSleep
      fi
    done
    if (( rc > 0 )); then
      log_error "SGC restore FAILED for snap $snapName. Some volumes are not in proper state."
      log_error "  Review the console outputs and the Flashsystem logs. Correct the problem, mount the file systems and restart the restore."
      log_error "==========================================================================="
      exit 6
    fi


    log_info "The SGC restore finished."
    log_info "==========================================================================="


    ### print instruction to mount file systems
    log_info "Mount all relevant file systems. Follow instructions below."
    echo -e "      This may require root privileges."
    echo -e "---------------------------------------------------------------------------\n"
    copyString=""
    i=0
    rc=0
    while (( i <= arrLen ));
    do
      fSystems=${fSystems_Arr[$i]}
      fsName=""
      for fsName in $(echo "$fSystems" | sed 's/,/ /g' | xargs -n1 | sort)
      do
        # echo "  DEBUG: file system=$fsName"
        echo "ACTION:  Mount the file system $fsName on the SP server"
	      echo -e "         # mount $fsName\n"
	      echo
	      copyString="$copyString mount $fsName;"
      done
      (( i = i + 1 ))
    done
    echo -e "COPY COMMAND: You can copy and paste the command below to accommodate the action:\n$copyString"  

    # ask for the mount completion
    echo
    echo "---------------------------------------------------------------------------"
    echo "ACTION: Press 'enter' when all file system are mounted."
    echo 
    echo "NOTE:   If mounting a file system fails, then resolve the problem."
    echo 
    echo "        If the problem persists, then press CTRL-C. You can restart this script after the problem was resolved."
    echo "---------------------------------------------------------------------------"
    echo -e "Your Input [enter | CTRL-C]: \c"
    read a

    # check that the file systems are mounted
    echo -e "\nINFO: Checking if file systems are mounted"
    i=0
    rcc=0
    while (( i <= arrLen ));
    do
      fSystems=${fSystems_Arr[$i]}
      fsName=""
      for fsName in $(echo "$fSystems" | sed 's/,/ /g')
      do
        #echo "  DEBUG: file system=$fsName"
        rc=0
        ${sudoCmd_Arr[$i]} /usr/bin/df -P | awk '{ print $6 }' | grep -q -w "$fsName"
        rc=$?
        if (( rc > 0 )); then
	         log_error "file system $fsName is not mounted"
	         (( rcc = rcc + 1 ))
	      fi
      done
      (( i = i + 1 ))
    done
    if (( rcc > 0 )); then
      log_error "One or more file systems are not mounted. Mount all relevant file systems and restart the restore."
      log_error "==========================================================================="
      exit 5
    fi

    log_info "All file systems are mounted."
    log_info "==========================================================================="


    ### if consistentSnap=true, print instruction to check instance specific setting
    if [[ $consistentSnap == "true" ]]; then
      log_info "Check Storage Protect instance specific setting."
      echo -e "-------------------------------------------------------------------------\n"
      # go back to the instance dir
      cd $curDir
      ### check if TSM or TSLM
      if [[ "$dbName" == "TSMDB1" ]]; then
        ### message for dsmserv (TSM)
        log_debug "Instance user $instUser services (cat /etc/services):"
        cat /etc/services | grep $instUser
        echo
        echo "-------------------------------------------------------------------------"
        log_debug "Instance user $instUser Db2 list (db2ilist | grep $instUser):"
        db2ilist | grep $instUser
        echo
        echo "-------------------------------------------------------------------------"
        log_debug "Instance user $instUser in db2 node configuration ($instDir/sqllib/db2nodes.cfg):"
        cat $instDir/sqllib/db2nodes.cfg
        echo
        echo "==========================================================================="
        log_info "Make sure that the output above is appropriate for the instance to start."
        echo 
        if [[ ! -d $instDir ]]; then
          echo -e "\nERROR: Instance home directory $instDir does not exist."
          echo -e "       Check if the instance home directory exists. Try to mount the instance home directory."
          echo -e "       Make sure the instance home directory $instDir is mounted before running the restore again.\n"
          exit 6
        else
          log_info "ACTION: Run the following commands as instance user on the Storage Protect server:"
          echo "        This resumes the database and starts the instance."
          echo "# su - $instUser"
          echo "# db2start"
          echo "# db2 restart db $dbName write resume"
        fi
      
        echo

        if [[ ! -d $serverInstDir ]]; then
          log_error "Server instance directory $serverInstDir does not exist."
          log_error "  Either the config parameter serverInstDir is not set correctly in $configFile,"
          log_error "  or the associated file system is not mounted correctly. Make the server instance directory"
          log_error "  $serverInstDir available run the restore script again."
          exit 6
        else
          echo -e "\nACTION: Change the directory to server instance directory $serverInstDir"
          echo -e "# cd $serverInstDir\n"
        fi
      
	      echo "ACTION: Start the instance in maintenance mode:"
        echo "# dsmserv maintenance"
        echo
        echo "--------------------------------------------------------------------------------"	  
        echo "ACTION: If node replication is enabled, then disable replication in maintencance mode using commmand: disable replication"
        echo "        To re-synchronize source and target server follow the procedure to Replicate client node data after a database restore"
        echo "        (https://www.ibm.com/docs/en/storage-protect/8.2.1?topic=replication-replicating-client-node-data-after-database-restore)"
        echo
        echo "ACTION: After starting the server in maintenance mode, check the actlog,"
        echo "      and run audit storage pool for all pools. When the server state is good,"
        echo "      then stop the server (halt) and start the instance in background. Good luck!"

        # at the end print a message to activate hyperswap
        echo -e "\nACTION: Do not forget the enable Hyperswap, if it was enabled before the restore."
        echo -e "      To enable  Hyperswap use the GUI or the CLI command:"
        echo -e "      # addvolumecopy -inconsistentownershipgroup -iogrp [io-group-secondary-site] -pool [pool-name-secondary site] -unit b [volume-name-or-id]"
        echo -e "-------------------------------------------------------------------------------\n"
        exit 0
      elif [[ "$dbName" == "ERMM" ]]; then
        ### message for MediaManager (TSLM)
        log_debug "Instance user $instUser services (cat /etc/services):"
        cat /etc/services | grep -i db2 | grep inst
        echo
        echo "-------------------------------------------------------------------------"
        log_debug "Instance user $instUser Db2 list (db2ilist | grep $instUser):"
        db2ilist
        echo
        echo "-------------------------------------------------------------------------"
        log_debug "Instance user $instUser in db2 node configuration ($DB2_HOME/db2nodes.cfg):"
        cat $DB2_HOME/db2nodes.cfg
        echo
        echo "==========================================================================="
        log_info "Make sure that the output above is appropriate for the instance to start."
        echo "ACTION: Run the following commands as instance user on the client cluster:"
        echo "        This resumes the database and starts the instance."
        echo "---------------------------------------------------------------------"
        echo "# su - $instUser"
        echo "# db2start"
        echo "# db2 restart db $dbName write resume"
        echo
        log_info "The TSLM server could be started!"
        echo "      Run ermmStart with the ermm user and check if the server come up."
        echo "# ermmStart"
        echo "      Start the Library Manager using ermmLmStart if everything is OK!"
        echo "# ermmLmStart"
        exit 0
      else
        ### no TSM or TSLM
        log_error "Instance $instUser is not a Storage Protect or TSLM instance."
        exit 1
      fi
    else
      log_info "Manual restore of SGC $snapName for instance $instUser on FlashSystem $apiServer finished."
      log_info "  Instructions to start instance are skipped because consistent SGC is set to $consistentSnap."
    fi
  else
    log_error "you indicated that the SGC restore failed. Correct the problem and run this program again."
    exit 5
  fi

fi

echo
exit 0