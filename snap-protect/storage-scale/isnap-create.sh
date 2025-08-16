#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2025
#                                                                              
# Name: isnap-create.sh
# Desc: Create snapshots for instance in scale using CLI or REST API
#
# Dependencies:
# This scripts must run on the host where the instance is running,
# it must be run by the instance user and uses sudo or the REST APIs.
# Requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - database name
# - file systems and fileset belonging to the instance
# - snapshot prefix
# - REST API server if snapshots are to be done through rest API
# If custom events are installed (custom.json),
# sending events can be enabled by running this command:
#  sed -i 's/\# $sudoCmd \$gpfsPath\/mmsysmonc/$sudoCmd \$gpfsPath\/mmsysmonc/g' del-snaps.sh
# 
# Usage:
# isnap-create.sh -r | --run | -h | --help
# -r | --run:  Perform the snapshot if the prerequisites are satisfied
# -h | --help: Show this help message (optional).
# *: show usage.
#
#********************************************************************************
#
# History
# 04/30/25 added sudoCmd to snapconfig.json - version 1.9.1
# 06/27/25 added default for TSMDB1 and apiPort

#---------------------------------------
# Global parameters
#---------------------------------------
# name of the config file
configFile=/usr/local/bin/snapconfig.json

# path of GPFS commands
gpfsPath="/usr/lpp/mmfs/bin"

# maximum number of retries to suspend the Db
maxSuspendRetry=5

# number of second to sleep inbetween of suspend retries
suspendWait=50

# determine operating system
os=$(uname -s)

# determine the name of the instance user for reference
instUser=$(id -un)
#### temp setting ######
# instUser=tsminst1
########################

# temporary file for json constructs used with API call to create snapshot
tmpFile="$HOME/$instUser-crsnap.json"

# version of the program
ver=1.9.1

# -----------------------------------------------------------------
# function parse_config to parse the config file
#
# Requires $configFile
# sets the instance specific parameters: dbName, snapPrefix, dirsToSnap, snapRet, apiServer, apiPort, apiAuth
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
			      if [[ "$name" = "snapRetention" ]]; then
              snapRet=$val
            fi
            if [[ "$name" = "serverInstDir" ]]; then
              serverInstDir=$val
            fi
            if [[ "$name" = "sudoCommand" ]]; then
              sudoCmd=$val
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
# function calc_expDate calculates the expiration date based on current date and $snapRet
# This is a platform specific. On linux we use 'date -d', on AIX we use ksh93
#
# Requires: $expDate, $snapRet
#
# Output: $expDate 
#
# Return code:
# 0: success
# 1: failure
#
# -----------------------------------------------------------------
calc_expDate()
{
   echo "DEBUG: calculating expiration date on platform $os"   

   case "$os" in
   Linux)
    expDate=$(date +%Y-%m-%d-%H:%M:%S -d "$DATE + $snapRet day");;
   AIX)
	  curEp=$(date +"%s")
		(( expEp = curEp + ($snapRet * 86400) ))
	  expDate=$(ksh93 -c 'printf "%(%Y-%m-%d-%T)T\n" "#$1"' ksh93 $expEp);;
   *)
    expDate="";;
   esac

   if [[ -z $expDate ]]; then 
     return 1
   else 
     return 0
   fi 

}


# -----------------------------------------------------------------
# function create_apisnapshot creates snapshot using the REST API
#
# Requires config parameter 
#
# -----------------------------------------------------------------
function create_apisnapshot()
{
  echo "DEBUG: Entering create_apisnapshot() for file system $fsName, fileset $fsetName, expiration $expClause."
  # $fsName $snapPrefix-$snapPostfix -j $fsetName $expClause
  
  jobId=""
  
  # build the json construct
  if [[ -z $expClause ]]; then
    echo -e "{ \n   \"snapshotName\": \"$snapPrefix-$snapPostfix\" \n}" > $tmpFile
  else
    echo -e "{ \n   $expClause \n   \"snapshotName\": \"$snapPrefix-$snapPostfix\" \n}" > $tmpFile
  fi
  
  # create the snapshot jobs
  if [[ ! -z $fsetName ]]; then
    # echo "DEBUG: curl -k -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --header 'Authorization: Basic $apiAuth' -d@$tmpFile 'https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots' "

    jobId=$(curl -k -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" -d@$tmpFile "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots" 2>>/dev/null| grep "jobId" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/^ *//g')

  else
    # echo "DEBUG: curl -k -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" -d@$tmpFile 'https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots'"
	
	jobId=$(curl -k -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" -d@$tmpFile "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots" 2>>/dev/null | grep "jobId" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/^ *//g')
		
  fi
  
  # if jobId is empty, the curl call above failed
  if [[ ! -z $jobId ]]; then
    # Check the jobId to finish
    maxLoops=10
    loops=0
    sleeptime=2
    jState="RUNNING"
    while [[ $jState = "RUNNING" && ! $loops = $maxLoops ]];
    do
      echo "DEBUG: checking job $jobId for completion (Loop: $loops)."
      sleep $sleeptime

	  jState=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/jobs?fields=%3Aall%3A&filter=jobId%3D$jobId" 2>>/dev/null | grep "status" | grep -v "{" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/"//g' | sed 's/^ *//g')
	 
	  echo "DEBUG: job $jobId status: $jState"
	  # if jState is empty, then perform the jobID query without parsing
	  if [[ -z $jState ]]; then
	    echo "DEBUG: Job status is empty, performing jobID query again."
		curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/jobs?fields=%3Aall%3A&filter=jobId%3D$jobId"
	  fi
	 
	  (( loops = loops + 1 ))
  done
  else
    echo "DEBUG: no REST API job was created, snapshot create failed."
    jState="FAILED"
  fi
  
  if [[ $jState = "COMPLETED" ]]; then
    return 0
  else
    return 1
  fi
}

#---------------------------------------
# Main
#---------------------------------------

# present banner
echo -e "\n============================================================================================="
echo "INFO: $(date) program $0 version $ver started for instance $instUser on platform $os"


### check if the run parameter is specified
if [[ $1 = "-h" || $1 = "--help" ]] || [[ ! $1 = "-r" && ! $1 = "--run" ]]; then
  echo "Usage: "
  echo "isnap-create.sh -r | --run | -h | --help"
  echo " -r | --run : Perform the snapshot if the prerequisites are satisfied"
  echo " -h | --help: Show this help message (optional)."
  echo " *: show usage."
  echo
  exit 0
fi


### get the parameters for this instance user from the config_file
# Initialize the instance specific parameters and parse the config
if [[ ! -a $configFile ]]; then
  echo "ERROR: config file $configFile not found. Please provide this file first."
  # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Snapshot configuration file $confifFile not found."
  exit 1
fi
dbName="TSMDB1"
dirsToSnap=""
snapPrefix=""
snapRet=0
serverInstDir="$HOME"
sudoCmd="/usr/bin/sudo"
apiServer=""
apiPort="443"
apiAuth=""
parse_config
#echo -e "DEBUG: Snapshot configuration from $configFile:\n  dbName=$dbName\n  dirsToSnap=$dirsToSnap\n  snapPrefix=$snapPrefix\n  snapRet=$snapRet\n  serverInstDir=$serverInstDir\n  sudoCommand=$sudoCmd\n  apiServer=$apiServer\n  apiPort=$apiPort\n  apiAuth=$apiAuth\n"


### check parameters
# if dirsToSnap is empty, then exist
if [[ -z $dirsToSnap ]]; then
  echo "ERROR: parameter dirsToSnap is emtpy."
  # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Instance configuration file does not contain valid file system and fileset information."
  exit 2
fi

# If serverInstDir does not exist then exit because it might be mis-configured
if [[ ! -d $serverInstDir ]]; then 
  echo "ERROR: Server instance directory $serverInstDir does not exist in the file system."
  echo "       Specify a valid directory for parameter serverInstDir in config file $configFile."
  exit 2
fi

# if API server was specified and no credentials then exit, set API port to default 443 if not set
if [[ ! -z $apiServer ]]; then
  if [[ -z $apiAuth ]]; then
    echo "ERROR: REST API credentials not defined in configuration file"
    # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser, No apiAuthentication defined for API server $apiServer in configuration file."
    exit 2
  fi
  if [[ ! -z $apiPort ]]; then
    apiServer="$apiServer:$apiPort"
  else
    apiServer="$apiServer:443"
  fi
fi


### check if the instance is running on this node under the instance user $instUser, if not then exit
if [[ "$dbName" == "TSMDB1" ]]; then
  ### check for dsmserv (TSM)
  # procExists=$(pgrep -l -u $instUser dsmserv)
  procExists=""
  procExists=$(ps -u $instUser | grep dsmserv | grep -v grep)
  if [[ -z $procExists ]]; then
    echo "WARNING: the instance $instUser is not running on server $(hostname). Normal exit."
    # $sudoCmd $gpfsPath/mmsysmonc event custom snap_warn "$instUser,Server instance is not running for instance user $instUser. This may be normal."
    exit 0
  fi
else
  ### check for MediaManager (TSLM)
  # procExists=$(pgrep -l -u $instUser MediaManager)
  procExists=""
  procExists=$(ps -u $instUser | grep MediaManager | grep -v grep)
  if [[ -z $procExists ]]; then
    echo "WARNING: the instance $instUser is not running on server $(hostname). Normal exit."
    # $sudoCmd $gpfsPath/mmsysmonc event custom snap_warn "$instUser,Server instance is not running for instance user $instUser. This may be normal."
    exit 0
  fi
fi


# compose the expiration-time string. If snapRet=0, then we ommit this string because it only works 5.1.5 onwards
# echo "DEBUG: snapshot retention time is $snapRet days"
expClause=""
expDate=""
if (( $snapRet > 0 )); then 
  # calculate the expDate string dependent on the OS
  calc_expDate
  rc=$?
  if (( rc > 0 )); then
    echo "ERROR: Unable to calculate expiration date. Contact support."
    # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Unable to calculate expiration date."
    exit 2
  fi
  if [[ -z $apiServer ]]; then
    #expClause="--expiration-time $(date +%Y-%m-%d-%H:%M:%S -d "$DATE + $snapRet day")"
    expClause="--expiration-time $expDate"
  else
    #expClause="\"expirationTime\": \"$(date +%Y-%m-%d-%H:%M:%S -d "$DATE + $snapRet day")\","
    expClause="\"expirationTime\": \"$expDate\","
  fi
fi
# echo "DEBUG: expiration clause: $expClause"


### suspend protect Db
echo "INFO: $(date) Suspending the data base for instance $instUser"
db2 connect to $dbName
rc=$?
if (( rc > 0 )); then
  echo "ERROR: failed to connect to instance Db, exiting."
  # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Failed to connect to database."
  exit 3
fi
db2 set write suspend for db
rc=$?
i=0
# if suspend failed, then try it again 
while (( rc > 0 && i < maxSuspendRetry )); do
  (( i= i + 1 ))
  sleep $suspendWait
  echo "INFO: $i. retry to suspend the database."
  db2 set write suspend for db
  rc=$?
done
if (( rc > 0 )); then
  echo "ERROR: failed to suspend the instance Db, exiting."
  # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Failed to suspend the database."
  db2 commit
  db2 disconnect $dbName
  exit 3
fi
#db2 commit
#db2 disconnect $dbName

# run sync depending on the platform
echo "DEBUG: Sync all file systems on platform $os"
if [[ $os = "AIX" ]]; then
  /usr/sbin/sync
else
  /usr/bin/sync
fi


### create snapshot in Storage Scale
# print message
echo -e "\n-----------------------------------------------------------------------------"
if [[ -z $apiServer ]]; then
  echo -e "INFO: $(date) creating snapshots with retention time $snapRet day using CLI for: $dirsToSnap\n"
else 
  echo -e "INFO: $(date) creating snapshots with retention time $snapRet day using API ($apiServer) for: $dirsToSnap\n"
fi

# determine date string as snapshot name postfix
snapPostfix=$(date +%Y%m%d%H%M%S)


# initialize variable and iterate through the dirsToSnap and create snapshot
item=""
fsName=""
fsetName=""
rc=0
# echo "DEBUG: dirsToSnap=$dirsToSnap"
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
      echo "INFO: Creating global snapshot for file system $fsName" 
      if [[ -z $apiServer ]]; then
        # echo "$gpfsPath/mmcrsnapshot $fsName $snapPrefix-$snapPostfix $expClause"
        $sudoCmd $gpfsPath/mmcrsnapshot $fsName $snapPrefix-$snapPostfix $expClause
        (( rc = rc + $? ))
	    else 
		    create_apisnapshot
		    (( rc = rc + $? ))
		    # echo "DEBUG: rc=$rc"
	    fi
    else
	    # fileset snapshot
        echo "INFO: Creating fileset snapshot for file system $fsName and fileset $fsetName"
	    if [[ -z $apiServer ]]; then
         # echo "DEBUG: $sudoCmd $gpfsPath/mmcrsnapshot $fsName $snapPrefix-$snapPostfix -j $fsetName $expClause"
         $sudoCmd $gpfsPath/mmcrsnapshot $fsName $snapPrefix-$snapPostfix -j $fsetName $expClause
	     (( rc = rc + $? ))
	    else
		    create_apisnapshot
		    (( rc = rc + $? ))
		    # echo "DEBUG: rc=$rc"
	    fi
    fi
  fi
done
if (( rc > 0 )); then
  echo "ERROR: snapshot create failed for some entities, check the output above. The snapshot is NOT GOOD."
  # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Snapshot creation failed for one or more file systems. Check the snapshots and ensure that all file systems have one snapshot for a given point in time."
fi


### resume protect Db
echo -e "\n-----------------------------------------------------------------------------"
echo "INFO: $(date) resuming Db for instance $instUser"
db2 set write resume for db
rc=$?
if (( rc > 0 )); then
  echo "ERROR: failed to resume the instance Db. This is a critical error. Stop the instance or Db and run db2 restart db $dbName write resume."
  # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Failed to resume the database. The database must be resumed manually"
fi
db2 commit
db2 disconnect $dbName

### end program
echo -e "\nINFO: $(date) program $0 completed successfully.\n"

exit 0
