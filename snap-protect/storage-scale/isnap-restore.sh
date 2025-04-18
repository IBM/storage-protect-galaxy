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
# -h | --help: displays syntax
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
# $ ./isnap-restore.sh snapshot-name
#   snapshot-name: name of the snapshot to be restored on all relevant file sets.
# 
#********************************************************************************


#---------------------------------------
# global parameters
#---------------------------------------
# name of the config file
configFile=/usr/local/bin/snapconfig.json

# path of GPFS commands
gpfsPath="/usr/lpp/mmfs/bin"

# initialized snapName to be given as argument
snapName=""

# determine the name of the instance user for reference
instUser=$(id -un)
#### temp test setting ######
#instUser=tsminst1
########################

# sudo command to be used
sudoCmd=/usr/bin/sudo


# program version
ver=1.9

# -----------------------------------------------------------------
# function parse_config to parse the config file
#
# Requires $configFile
# sets the instance specific parameters: dbName, snapPrefix, dirsToSnap 
#
# -----------------------------------------------------------------
function parse_config()
{
  # read the config file and assign the values based on the instance user name
  found=0
  while read -r line;
  do
    if [[ $line =~ ^#.* ]]; then
      continue
    else
      name=$(echo $line | cut -d':' -f1 -s | sed 's/"//g' | sed 's/^ *//g')
      val=$(echo $line | cut -d':' -f2 -s | sed 's/"//g' | sed 's/\[//g' | sed 's/\]//g' | sed 's/,*$//g' | sed 's/^ *//g')
	  # echo "DEBUG: name=$name, val=$val"
	  if [[ -z $name || -z $val ]]; then
        continue
      else
        if [[ "$name" = "instName" ]]; then
          if [[ "$val" = "$instUser" ]]; then
            found=1
          else 
            found=0
          fi
        else 
          if (( found == 1 )); then
            if [[ "$name" = "dbName" ]]; then
              dbName=$val
            fi
            if [[ "$name" = "snapPrefix" ]]; then
              snapPrefix=$val
            fi
            if [[ "$name" = "dirsToSnap" ]]; then
              dirsToSnap=$val
            fi
            if [[ "$name" = "serverInstDir" ]]; then
              serverInstDir=$val
            fi
			      if [[ "$name" = "apiServerIP" ]]; then
              apiServer=$val
            fi
			      if [[ "$name" = "apiServerPort" ]]; then
              apiPort=$val
            fi
			      if [[ "$name" = "apiCredentials" ]]; then
              apiAuth=$val
            fi
          fi
        fi
      fi
    fi
  done < $configFile
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
    # echo "DEBUG: curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots?filter=snapshotName%3D$snapName""
	
	if [[ -a $jqPath ]]; then
	  sName=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots?filter=snapshotName%3D$snapName" 2>/dev/null | jq -r '.snapshots[] | [.snapshotName] | @csv' | sed 's/,/\" \"/g' | sed 's/\"//g')
	  frc=$?
	else
	  sName=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots?filter=snapshotName%3D$snapName" 2>/dev/null | grep "snapshotName" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/"//g' | sed 's/^ *//g') 
	  frc=$?
	fi
	echo "DEBUG: snapshot on file system $fsName and fileset $fsetName: $sName"
  else
    # echo "DEBUG: curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots?filter=snapshotName%3D$snapName""
	
	if [[ -a $jqPath ]]; then
	  sName=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots?filter=snapshotName%3D$snapName" 2>/dev/null | jq -r '.snapshots[] | [.snapshotName] | @csv' | sed 's/,/\" \"/g' | sed 's/\"//g')
	  frc=$?
	else
	  sName=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots?filter=snapshotName%3D$snapName" 2>/dev/null | grep "snapshotName" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/"//g' | sed 's/^ *//g')
	  frc=$?
	fi
	echo "DEBUG: snapshot on file system $fsName: $sName"
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

### present banner
echo "INFO: $(date) program $0 version $ver started for instance $instUser"


### Provide syntax with help parameter, otherwise $1 is the name of the snapshot
if [[ $1 = "-h" || $1 = "--help" || $1 = "-?" || -z $1 ]]; then
  echo "Syntax: isnap-restore.sh snapshot-name"
  echo "  snapshot-name: name of the snapshot to be restored on all relevant file sets."
  echo
  exit 0
fi


### get the parameters for this instance user from the config_file
# Initialize the instance specific parameters and parse the config
if [[ ! -a $configFile ]]; then
  echo "ERROR: config file $configFile not found. Please provide this file first."
  exit 1
fi
dbName=""
dirsToSnap=""
snapPrefix=""
apiServer=""
apiPort=""
apiAuth=""
serverInstDir="$HOME"
parse_config

### check the required parameters
# if dirsToSnap is empty, then exist
if [[ -z $dirsToSnap ]]; then
  echo "ERROR: parameter dirsToSnap is emtpy."
  exit 2
fi

# Present Warning if serverInstDir does not exist (could be corrupted)
if [[ ! -d $serverInstDir ]]; then 
  echo "WARNING: Server instance directory $serverInstDir does not exist in the file system. This may be normal in case the file system is corrupted."
  echo "         Specify a valid directory for parameter serverInstDir in config file $configFile."
fi

# if API server was specified and no credentials then exit, set API port to default 443 if not set
if [[ ! -z $apiServer ]]; then
  if [[ -z $apiAuth ]]; then
    echo "ERROR: REST API credentials not defined in configuration file"
    exit 2
  fi
  if [[ ! -z $apiPort ]]; then
    apiServer="$apiServer:$apiPort"
  else
    apiServer="$apiServer:443"
  fi
fi


### check that that instance is stopped, if not then exit
echo "INFO: checking if the server instance is stopped."
if [[ "$dbName" == "TSMDB1" ]]; then
  ### check for dsmserv (TSM)
  # procExists=$(pgrep -l -u $instUser dsmserv)
  procExists=""
  procExists=$(ps -u $instUser | grep dsmserv | grep -v grep)
  if [[ ! -z $procExists ]]; then
    echo "ERROR: Instance $instUser is still running. It must be stopped for restore."
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
    echo "ERROR: Instance $instUser is still running. It must be stopped for restore."
    echo "  DEBUG: active process: $procExists"
    echo "  Ensure you are running this program on the right instance server."
    exit 1
  fi
else
  ### no TSM or TSLM
  echo "ERROR: Instance $instUser is not a Storage Protect or TSLM instance."
  exit 1
fi


### check that snapshot name is given and assign it snapName
snapName=$1
echo "INFO: checking if snapshot to be restored ($snapName) exists on all relevant file systems and filesets."
if [[ -z $apiServer ]]; then
  echo "INFO: Using commmand line as user $instUser"
else
  echo "INFO: Using REST API server $apiServer"
fi
if [[ -z $snapName ]]; then
  echo "ERROR: snapshot name not specified."
  echo "       syntax: isnap-restore.sh snapshotname"
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
    echo "ERROR: snapshot name $snapName does not exist on all relevant file systems."
	exit 5
  fi
fi

echo "INFO: snapshot $snapName exists on all relevant filesystem and filesets, continuing."

### Print the snapshot restore instruction
# iterate through the dirsToSnap and restore the snapshot
echo "INFO: $(date) Restoring snapshots for all relevant file systems and filesets."
item=""
fsName=""
fsetName=""
rc=0
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
	    if [[ -z $apiServer ]]; then
        # echo "$sudoCmd $gpfsPath/mmrestorefs $fsName $snapName"
        $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName
	      (( rc = rc + $? ))
	   else
	     echo
		   echo "==========================================================================="
	     echo "WARNING: snapshot restore is not implemented using the REST API. Perform the snapshot restore manually."
		   echo "ACTION:  run the following command as Scale admin user on the storage cluster:"
		   echo "         # $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName"
       # rc=1391 means that the API is used
		   rc=1391
	    fi
    else
	    if [[ -z $apiServer ]]; then
        # echo "$sudoCmd $gpfsPath/mmrestorefs $fsName $snapName -j $fsetName"
        $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName -j $fsetName
	      (( rc = rc + $? ))
	    else
	      echo
		    echo "==========================================================================="		 
	      echo "WARNING: snapshot restore is not implemented using the REST API. Perform the snapshot restore manually:"
		    echo "ACTION:  run the following command as Scale admin user on the storage cluster:"
		    echo "         # $sudoCmd $gpfsPath/mmrestorefs $fsName $snapName -j $fsetName"
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
echo -e "Your Input [CTRL-C | yes]: \c"
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
  df -h | grep -E "Use%$fsList"
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
         mmlsfileset $line
	     else
	       echo "Filesets in file system $line:"
		     echo -e "Name\t\tStatus\t\tPath"
	       curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$line/filesets?fields=:all:" 2>/dev/null | jq -r '.filesets[] | [.filesetName, .config.status, .config.path ] | @csv' | sed 's/,/\t\t/g' | sed 's/\"//g'
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
    echo "---------------------------------------------------------------------"
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
