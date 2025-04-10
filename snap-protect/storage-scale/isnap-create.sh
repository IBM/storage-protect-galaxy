#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2025 IBM Corporation                             			   #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to deal#
# in the Software without restriction, including without limitation the rights #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell    #
# copies of the Software, and to permit persons to whom the Software is        #
# furnished to do so, subject to the following conditions:                     #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,#
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE#
# SOFTWARE.                                                                    #
################################################################################

# Author: N. Haustein
# 
# Program:
#   Create snapshots for instance in scale using CLI or REST API
#
# Dependencies:
# this scripts must run on the host where the instance is running, it must be run by the instance user and uses sudo or the REST API
# requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - database name
# - file systems and fileset belonging to the instance
# - snapshot prefix
# - REST API server if snapshots are to be done through rest API
# if custom events are installed (custom.json), sending events can be enabled by running this command:
#   sed -i 's/\# $sudoCmd \$gpfsPath\/mmsysmonc/$sudoCmd \$gpfsPath\/mmsysmonc/g' del-snaps.sh
#
#---------------------------------------
# history
# 12/20/23 fixed loop waiting for snapshot create to complete (type mismatch) - version 1.4
# 02/20/24 adjust for TSLM: check if TSM or TSLM Media Manager is running - version 1.5
# 02/28/24 if jobID query fails, then do more debugging in create_apisnapshot()
# 03/07/25 use ps instead of pgrep (AIX compatibility), improve iterating dirsToSnap
# 03/25/25 AIX compatibility changes
# 03/25/25 add sudo command variable - version 1.8
# 01/04/15 add full path of sync command
#


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

# determine the name of the instance user for reference
instUser=$(id -un)
#### temp setting ######
# instUser=tsminst1
########################

# temporary file for json constructs used with API call to create snapshot
tmpFile="$HOME/$instUser-crsnap.json"

# sudo command to be used
sudoCmd=/usr/bin/sudo

# version of the program
ver=1.8

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
echo "INFO: $(date) program $0 version $ver started for instance $instUser"


### check if the run parameter is specified
if [[ ! $1 = "-r" && ! $1 = "--run" ]]; then
  echo "Syntax: isnap-create.sh -r | --run"
  echo "  -r | --run: perform the snapshot if the prerequisites are satisfied"
  echo "  *: show syntax."
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
dbName=""
dirsToSnap=""
snapPrefix=""
snapRet=0
apiServer=""
apiPort=""
apiAuth=""
parse_config


### check parameters
# if dirsToSnap is empty, then exist
if [[ -z $dirsToSnap ]]; then
  echo "ERROR: parameter dirsToSnap is emtpy."
  # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Instance configuration file does not contain valid file system and fileset information."
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
/usr/bin/sync


### create snapshot in Storage Scale
if [[ -z $apiServer ]]; then
  echo "INFO: $(date) creating snapshots using CLI for: $dirsToSnap"
else 
  echo "INFO: $(date) creating snapshots using API ($apiServer) for: $dirsToSnap"
fi

# determine date string as snapshot name postfix
snapPostfix=$(date +%Y%m%d%H%M%S)

# compose the expiration-time string. If snapRet=0, then we ommit this string because it only works 5.1.5 onwards
# echo "DEBUG: snapshot retention time is $snapRet days"
if [[ $snapRet = "0" ]]; then
  expClause=""
else
  if [[ -z $apiServer ]]; then
    expClause="--expiration-time $(date +%Y-%m-%d-%H:%M:%S -d "$DATE + $snapRet day")"
  else
    expClause="\"expirationTime\": \"$(date +%Y-%m-%d-%H:%M:%S -d "$DATE + $snapRet day")\","
  fi 
fi

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
echo
echo "INFO: $(date) program $0 completed successfully."
echo "============================================================================="
echo

exit 0
