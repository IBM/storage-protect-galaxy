#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2025
#                                                                              
# Name: isnap-restore.sh
# Desc: Restore file system or filesets from snapshot and start the database manager
# this scripts runs on the host where the instance is running and uses sudo or the REST API
#
# Input: 
# snapshotname: name of the snapshot to be restore 
# -h | --help: displays usage
#
# Dependencies:
# this scripts must run on the host where the instance is running, it must be run by the instance user and uses sudo or the REST API
# requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - database name
# - file systems and fileset belonging to the instance
# - snapshot prefix
# - API server: optional, when REST API is used. In this case, the snapshot restore is not performed.
#
# Usage:
# isnap-restore.sh snapshot-name
#  snapshot-name: Name of the snapshot to be restored on all relevant file sets.
#  -h | --help:   Show this help message (optional)."
# 
#********************************************************************************
#
# History
# 04/30/25 added sudoCmd to snapconfig.json - version 1.9.1
# 08/15/25 added logic for autoRestore config parameter (enforced with CLI, set to false with REST API)
# 08/15/25 set default for configuration parameter dbName (TSMDB1)
# 11/13/25 allow script to be located in any directory
# 04/28/26 adopt global functions isnapfunctions.sh with new configuration file format, print command to copy & paste, fix df for AIX - version 2.0

#---------------------------------------
# global parameters
#---------------------------------------
# common functions file name
funcFile="isnapfunctions.sh"

# path of GPFS commands
gpfsPath="/usr/lpp/mmfs/bin"

# initialized snapName to be given as argument
snapName=""

# program version
ver=2.0


#------------------------------------------------------------------
# Print usage
#------------------------------------------------------------------
function usage()
{
  if [[ ! -z $1 ]]; then
    echo "ERROR: $1"
  fi
  echo "Usage:"
  echo "isnap-restore.sh -s snapshot-name [-i instance-name]"
  echo "  -s snapshot-name: Name of the snapshot to be restored on all relevant file sets."
  echo "  -i instance-name: Instance user name, default is the user running this script (optional)"  
  echo "  -h | --help:      Show this help message (optional)."
  echo
  exit 0
  return 0
}


# -----------------------------------------------------------------
# function check_apisnapshot to check if a snapshotname exists
#
# Requires $configFile
# check snapshot
#
# -----------------------------------------------------------------
function check_apisnapshot()
{
  # echo "DEBUG: Entering check_apisnapshot()"
  
  jqPath=/usr/bin/jq
  sName=""
  frc=0
  # list snapshots
  if [[ ! -z $fsetName ]]; then
    # echo "DEBUG: curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots?filter=snapshotName%3D$snapName""
	
	if [[ -a $jqPath ]]; then
	  sName=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots?filter=snapshotName%3D$snapName" 2>/dev/null | jq -r '.snapshots[] | [.snapshotName] | @csv' | sed 's/,/\" \"/g' | sed 's/\"//g')
	  frc=$?
	else
	  sName=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots?filter=snapshotName%3D$snapName" 2>/dev/null | grep "snapshotName" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/"//g' | sed 's/^ *//g') 
	  frc=$?
	fi
	echo "  DEBUG: snapshot on file system $fsName and fileset $fsetName: $sName"
  else
    # echo "DEBUG: curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots?filter=snapshotName%3D$snapName""
	
	if [[ -a $jqPath ]]; then
	  sName=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots?filter=snapshotName%3D$snapName" 2>/dev/null | jq -r '.snapshots[] | [.snapshotName] | @csv' | sed 's/,/\" \"/g' | sed 's/\"//g')
	  frc=$?
	else
	  sName=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots?filter=snapshotName%3D$snapName" 2>/dev/null | grep "snapshotName" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/"//g' | sed 's/^ *//g')
	  frc=$?
	fi
	echo "  DEBUG: snapshot on file system $fsName: $sName"
  fi
  
  if [[ $snapName = $sName ]]; then
    return 0
  else
    return 1
  fi
  
}

#---------------------------------------
# Main
#---------------------------------------

### determine directory where the script is started from and source the function file
# this will set the $instUser (may be overwritten with parameter -i)
basePath=$(dirname $0)
if [[ $basePath = "." ]]; then
  basePath=$PWD
fi
#echo "DEBUG: base path for $0: $basePath"

### source common functions
if [[ -a $basePath/$funcFile ]]; then
  . $basePath/$funcFile
else
  echo "  ERROR: common functions in file $funcFile not found in $PWD."
  exit 1 
fi


### present banner
echo -e "\n============================================================================================="
echo -e "INFO: $(date) program $0 version $ver started for instance $instUser on platform $(uname -s) (global function $globFuncVer) "


# parse arguments from the command line
snapName=""
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
  "-s") shift 1
        if [[ -z $1 ]]; then 
		       usage "Snapshot name is not specified."
		       exit 1
		    else
		       snapName=$1
		    fi;;
  "-h" | "--help")
        usage
        exit 1;;
  *)    usage "wrong argument $1"
        exit 1;;
  esac
  shift 1
done

if [[ -z $snapName ]]; then
  usage "Snapshot name (parameter -s) not specified."
  exit 1
fi

### get the parameters for this instance user from the config_file
echo "INFO: Parsing configuration parameters from config file $configFile for instance user $instUser."
if ! parse_config; then
  exit 2
fi

### check config parameters and apply default values where possible
# echo "INFO: Checking configuration parameters."
if ! check_config; then
  exit 2
fi
#print_config


# if API server was specified and autoRestore is true present a Warning
if [[ ! -z $apiServer &&  $autoRestore == true ]]; then
  echo "WARNING: automatic restore is not possible when using the REST API. Setting autoRestore to false."
  autoRestore=false
fi
if [[ -z $autoRestore ]]; then
  autoRestore=false
fi

### check that that instance is stopped, if not then exit
echo -e "\nINFO: checking if the server instance is stopped."
if [[ "$dbName" == "TSMDB1" ]]; then
  ### check for dsmserv (TSM)
  # procExists=$(pgrep -l -u $instUser dsmserv)
  procExists=""
  procExists=$(ps -u $instUser | grep dsmserv | grep -v grep)
  if [[ ! -z $procExists ]]; then
    echo "  ERROR: Instance $instUser is still running. It must be stopped for restore."
    echo "  DEBUG: active process: $procExists"
    echo "  Ensure you are running this program on the right instance server."
    exit 1
  fi
elif [[ "$dbName" == "ERMM" ]]; then
  ### check for MediaManager (TSLM)
  # procExists=$(pgrep -l -u $instUser MediaManager)
  procExists=""
  procExists=$(ps -u $instUser | grep MediaManager | grep -v grep)
  if [[ ! -z $procExists ]]; then
    echo "  ERROR: Instance $instUser is still running. It must be stopped for restore."
    echo "  DEBUG: active process: $procExists"
    echo "  Ensure you are running this program on the right instance server."
    exit 1
  fi
else
  ### no TSM or TSLM
  echo "  ERROR: Instance $instUser is not a Storage Protect or TSLM instance."
  exit 1
fi


### check that snapshot name is given and exists and assign it snapName
echo -e "\nINFO: checking if snapshot to be restored ($snapName) exists on all relevant file systems and filesets."
if [[ -z $apiServer ]]; then
  echo "  INFO: Using commmand line as user $instUser"
else
  echo "  INFO: Using REST API server $apiServer"
fi
if [[ -z $snapName ]]; then
  echo "  ERROR: snapshot name not specified."
  echo "  Usage:"
  echo "  isnap-restore.sh snapshot-name"
  echo "    snapshot-name: Name of the snapshot to be restored on all relevant file sets."
  echo "    -h | --help:   Show this help message (optional)."
  echo
  exit 4
else
  rc=0
  for item in $(echo "$dirsToSnap" | sed 's/,/ /g')
  do
    # echo "  DEBUG: item=$item"
    if [[ -z $item ]]; then
      continue
    else
      fsName=$(echo $item | cut -d'+' -f 1)
      fsetName=$(echo $item | cut -d'+' -f 2 -s)
      if [[ -z $fsetName ]]; then
	      # global snapshot
		    if [[ -z $apiServer ]]; then
		      # echo "$sudoCmd $gpfsPath/mmlssnapshot $fsName -s $snapName"
          $sudoCmd $gpfsPath/mmlssnapshot $fsName -s $snapName > /dev/null 2>&1
		      (( rc = rc + $? ))
		    else
		      check_apisnapshot
		      (( rc = rc + $? ))
		      #echo "DEBUG: rc=$rc"
		      echo "----------------------------------------------------------------------------------"
		    fi
      else
	      if [[ -z $apiServer ]]; then
          # echo "$sudoCmd $gpfsPath/mmlssnapshot $fsName -s $fsetName:$snapName"
          $sudoCmd $gpfsPath/mmlssnapshot $fsName -s $fsetName:$snapName > /dev/null 2>&1
		      (( rc = rc + $? ))
		    else
		     check_apisnapshot
		     (( rc = rc + $? ))
		     #echo "DEBUG: rc=$rc"
		     echo "----------------------------------------------------------------------------------"
		    fi
      fi
	  fi
  done
  if (( rc > 0 )); then
    echo "  ERROR: snapshot name $snapName does not exist on all relevant file systems."
	exit 5
  fi
fi

echo "  INFO: snapshot $snapName exists on all relevant filesystem and filesets, continuing."

### Print the snapshot restore instruction
# iterate through the dirsToSnap and restore the snapshot
if [[ $autoRestore == false ]]; then
  echo -e "\n==============================================================================="
  echo "INFO: Manual restore requested (autoRestore=$autoRestore)"
  echo "-------------------------------------------------"
  echo "      When using the REST API then the restore can only be done manually!"
  echo "      Follow the instructions on the console. Press [Enter] to continue."
  echo -e "===============================================================================\n"
  echo -e "Press [Enter] to continue or CTRL-C to quit: \c"
  read
else
  echo -e "\nINFO: $(date) Automatically Restoring snapshots for all relevant file systems and filesets."
fi

item=""
fsName=""
fsetName=""
rc=0
copyCmd=""
# need to leave the instance directory because the restore does not work when sitting there
curDir=$(pwd)
cd /tmp
for item in $(echo "$dirsToSnap" | sed 's/,/ /g')
do
  # echo "  DEBUG: item=$item"
  if [[ -z $item ]]; then
     continue
  else
    fsName=$(echo $item | cut -d'+' -f 1)
    fsetName=$(echo $item | cut -d'+' -f 2 -s)

    if [[ -z $fsetName ]]; then
      # differentiate manual or automatic restore
	    if [[ $autoRestore == true ]]; then
        # echo "$sudoCmd $gpfsPath/mmrestorefs $fsName $snapName"
        echo -e "\n---------------------------------------------------------------------------------"
        echo -e "INFO: Restoring snapshot $snapName for file system $fsName" 
        $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName
	      (( rc = rc + $? ))
	   else
		   echo -e "\nACTION:  run the following command as Scale admin user on the storage cluster:"
		   echo -e "         # $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName"
       copyCmd="$copyCmd $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName;\n" 
       # rc=1391 means that the API is used
		   rc=1391
	    fi
    else
      # differentiate manual or automatic restore
	    if [[ $autoRestore == true ]]; then
	      # echo "$sudoCmd $gpfsPath/mmrestorefs $fsName $snapName -j $fsetName"
        echo -e "\n---------------------------------------------------------------------------------"
        echo -e "INFO: Restoring snapshot $snapName for fileset $fsetName on file system $fsName"
        $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName -j $fsetName
	      (( rc = rc + $? ))
	    else
		    echo -e "\nACTION:  run the following command as Scale admin user on the storage cluster:"
		    echo -e "         # $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName -j $fsetName"
        copyCmd="$copyCmd $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName -j $fsetName;\n"
        # rc=1391 means that the API is used
		    rc=1391
	    fi
    fi
  fi
done
# go back to the instance dir
cd $curDir

# if rc is 0 then restart the Db and start the server in maintenance (not the case if the APi is used)
if (( rc == 0 )); then
  ### starting the Db manager and resuming the DB
  echo -e "\n-----------------------------------------------------------------------------"
  echo "INFO: $(date) snapshot restore finished, starting Db manager and resuming the DB $dbName."
  echo -e "-----------------------------------------------------------------------------\n"
  db2start
  db2 restart db $dbName write resume
  rc=$?
  if (( rc > 0 )); then
    echo "ERROR: failed to resume the instance Db. This is a critical error. Stop the instance or Db and run db2 restart db $dbName write resume."
    exit 7
  fi
  ### starting the instance
  if [[ "$dbName" == "TSMDB1" ]]; then
    ### start dsmserv (TSM)

    # if the server instance directory is given, then change to this directory
    cd $serverInstDir

    echo "INFO: $(date) starting the instance in maintenance mode, client session are not allowed."
    echo "      Check the instance and if everything is good, stop it (halt) and start it as service." 
    dsmserv maintenance
    exit 0
  elif [[ "$dbName" == "ERMM" ]]; then
    ### message for MediaManager (TSLM)
    echo "INFO: $(date) the TSLM server could be started!"
    echo "      Run ermmStart with the ermm user and check if the server come up." 
    echo "      Start the Library Manager using ermmLmStart if everything is OK!" 
    exit 0
  else
    ### no TSM or TSLM
    echo "ERROR: Instance $instUser is not a Storage Protect or TSLM instance."
    exit 1
  fi
fi

if (( rc > 0 && rc != 1391 )); then
  echo "ERROR: $(date) snapshot restore FAILED for snap $snapName. Cannot start the database."
  echo "       Review the console outputs and the GPFS logs. Correct the problem and restart the program."
  exit 6
fi

# take this path if API is used
# print copy command
echo -e "\nCOPY COMMAND: You can copy and paste the commands below to accommodate the action:\n$copyCmd"
echo
echo "==========================================================================="
echo "WAIT: For the completion of the snapshot restores on the storage cluster"
echo 
echo "ATTENTION: Snapshot restore may fail if QUOTA is enabled on the file system and filesets."
echo "           Either disable Quota or unmount the file systems prior to executing the restore."
echo 
echo "ACTION: Enter 'yes' if the snapshot restore completed successfully."
echo 
echo "NOTE:   If the snapshot restore failed, then enter no or CTRl-C and resolve the problem."
echo "        You can restart this script any time after the problem was resolved."
echo "---------------------------------------------------------------------------"
echo -e "Your Input [yes | CTRL-C]: \c"
read a
if [[ "$a" == "yes" ]]; then
  echo
  echo "========================================================================="
  echo "INFO: $(date) The snapshot restore finished, follow the guidance below."
  echo "ACTION: check the output of the commands below to determine if the instance can be started."
  echo "========================================================================="
  echo
  echo "ATTENTION: Check that all required file systems are mounted. If not, then mount the file system (mmmount)"
  echo "-------------------------------------------------------------------------"
  echo "DEBUG: file system mount state (df)"
  fsList=""
  item=""
  for item in $(echo "$dirsToSnap" | sed 's/,/ /g')
  do
    # echo "  DEBUG: item=$item"
    if [[ -z $item ]]; then
      continue
    else
      fsName=$(echo $item | cut -d'+' -f 1)
	    if [[ ! -z $fsName ]]; then
	      fsList="$fsList|$fsName"
	    fi
	  fi
  done

  ### set du that is platform specific, -h is not available in AIX
  os=$(uname -s)
  dfOpt=""
  case "$os" in
  Linux)
    dfOpt="-h";;
  AIX)
    dfOpt="-g";;
*)
    dfOpt="-unknownOS";;
  esac
  df $dfOpt | grep -E "Use%$fsList"
  
  echo
  echo "-------------------------------------------------------------------------"
  echo "INFO: Showing the fileset states for all relevant file systems and filesets"
  echo "      Check that all required filesets are linked."
  echo "-------------------------------------------------------------------------"
  echo
  echo "DEBUG: fileset state for all relevant file systems"
  echo "$fsList" | sed 's/|/\n/g' | while read line;
  do 
     if [[ ! -z $line ]]; then
       if [[ -z $apiServer ]]; then
         $sudoCmd $gpfsPath/mmlsfileset $line
	     else
	       echo "Filesets in file system $line:"
		     echo -e "Name\t\tStatus\t\tPath"
	       curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$line/filesets?fields=:all:" 2>/dev/null | jq -r '.filesets[] | [.filesetName, .config.status, .config.path ] | @csv' | sed 's/,/\t\t/g' | sed 's/\"//g'
	     fi
	     echo
	   fi
  done
  echo
  echo "-------------------------------------------------------------------------"
  echo "ACTION: Check that all required filesets are linked. If nested dependend filesets "
  echo "        are in unlinked state, then it might not have been restored. This can happen "
  echo "        with Storage Scale version below 5.2.1."
  echo "        If filesets are not linked, then press CTRL-C and follow these steps:"
  echo "        1. Link the unlinked fileset (mmlinkfileset)"
  echo "        2. Delete the old files in the fileset directories that were unlinked (rm -rf)"
  echo "        3. Copy the content of the fileset that were unlinked from the snapshot (mmxcp)."
  echo "           Example: mmxcp enable --source /fs/.snapshot/$snapName/fset-Path --target /fs/fset-Path -N 'all' --force"
  echo "        4. When all files were copied from the snapshot into the fileset directory, then restart this program."
  echo
  echo "  Press enter to continue, if file systems and fileset are in a good state."
  echo "  You can also abort (CTRL-C) and restart later."
  echo "-------------------------------------------------------------------------"
  echo -e "Press Enter to continue [Enter | CTRL-C]: \c"
  read
  echo
  ### check if TSM or TSLM
  if [[ "$dbName" == "TSMDB1" ]]; then
  ### message for dsmserv (TSM)
    echo "DEBUG: Instance user $instUser services (cat /etc/services):"
    cat /etc/services | grep $instUser
    echo
    echo "-------------------------------------------------------------------------"
    echo "DEBUG: Instance user $instUser Db2 list (db2ilist | grep $instUser):"
    db2ilist | grep $instUser
    echo
    echo "-------------------------------------------------------------------------"
    echo "DEBUG: DB2 node configuration ($DB2_HOME/db2nodes.cfg) for instance user $instUser:"
    cat $DB2_HOME/db2nodes.cfg
    echo
    echo "==========================================================================="
    echo "INFO: Make sure that the output above is appropriate for the instance to start."
    echo "ACTION: Start and resume the Storage Protect database."
    echo "        As instance user, run the following command:"
    echo "# su - $instUser"
    echo "# db2start"
    echo "# db2 restart db $dbName write resume"
    echo
    
    # if the server instance directory is given, then change to this directory
    echo "ACTION: Change the directory to server instance directory $serverInstDir"
    echo "# cd $serverInstDir"
    echo

    echo "ACTION: Start the instance in maintenance mode, client session are not allowed."
    echo "Check the instance and if everything is good, stop it (halt) and start it as service." 
    echo "# dsmserv maintenance"
    echo
    echo "INFO: After starting the server in maintenance mode, check the actlog,"
    echo "      and run audit storage pool for all pools. When the server state is good,"
    echo "      then stop the server (halt) and start the instance. Good luck!"
    echo
    echo "==========================================================================="
    echo
    exit 0
  elif [[ "$dbName" == "ERMM" ]]; then
    ### message for MediaManager (TSLM)
    echo "DEBUG: Instance user $instUser services (cat /etc/services):"
    cat /etc/services | grep -i db2 | grep inst
    echo
    echo "-------------------------------------------------------------------------"
    echo "DEBUG: Instance user $instUser Db2 list (db2ilist | grep $instUser):"
    db2ilist
    echo
    echo "-------------------------------------------------------------------------"
    echo "DEBUG: DB2 node configuration ($DB2_HOME/db2nodes.cfg) for instance user $instUser:"
    cat $DB2_HOME/db2nodes.cfg
    echo
    echo "==========================================================================="
    echo "INFO: Make sure that the output above is appropriate for the instance to start."
    echo "ACTION: Start and resume the database of the instance."
    echo "        As instance user, run the following command:"
    echo "---------------------------------------------------------------------"
    echo "# su - $instUser"
    echo "# db2start"
    echo "# db2 restart db $dbName write resume"
    echo
    echo "INFO: The TSLM server could be started!"
    echo "      Run ermmStart with the ermm user and check if the server come up."
    echo "# ermmStart" 
    echo "      Start the Library Manager using ermmLmStart if everything is OK!" 
    echo "# ermmLmStart"
    exit 0
  else
    ### no TSM or TSLM
    echo "ERROR: Instance $instUser is not a Storage Protect or TSLM instance."
    exit 1 
  fi
else
  echo "ERROR: you indicated that the snapshot restore failed. Correct the problem. You can rerun this progam any time."
fi

echo
exit 0
