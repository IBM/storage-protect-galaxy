#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2025
#                                                                              
# Name: isnap-del.sh
# Desc: Delete snapshot from file systems and filesets via the CLI or REST API
# this script runs on any node in the cluster and requires sudo when not using the REST API
#
# Input: 
# -s snapshotname: name of the snapshot to be deleted (required) (mutually exclusing with -g)
# -i instanceuser: name of the instance user, default is the user running this script
# -g age: snapshots older then age days are delete (mutually exclusing with -s)
# -p: preview mode, does not do deletion, just lists snapnames to be deleted (optional)
#
# Dependencies:
# this scripts runs on a GPFS (storage) cluster node using the CLI or the REST API
# requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - database name
# - file systems and fileset belonging to the instance
# - snapshot prefix
# - API server (optional) if REST API is used instead of command line
# - requires jq to be installed 
# - if custom events are installed (custom.json), sending events can be enabled by running this command:
#   sed -i 's/\# $sudoCmd \$gpfsPath\/mmsysmonc/$sudoCmd \$gpfsPath\/mmsysmonc/g' isnap-del.sh
#
# Usage:
# $ ./isnap-del.sh -s snapshot-name | -g snapshot-age [-i instance-name -p]
#   -s snapshot-name: Name of the snapshot to be deleted from all file systems. Required if -g is not specified.
#   -g snapshot-age:  Age of snapshots in days to be deleted from all file systems. Required if -s is not specified.
#   -i instance-name: Instance user name, default is the user running this script (optional)
#   -p:               Preview snapshot names to be deleted from all file systems (optional)
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

# time to sleep between snapshot deletes
sleepTime=1

# sudo command to be used
sudoCmd=/usr/bin/sudo

# version
ver=1.7

# -----------------------------------------------------------------
# function syntax 
#
# -----------------------------------------------------------------
function syntax()
{
  echo
  echo "ERROR: $1"
  echo "Syntax: isnap-del.sh -s snapshot-name | -g snapshot-age [-i instance-name -p]"
  echo "  -s snapshot-name: Name of the snapshot to be deleted from all file systems. Required if -g is not specified."
  echo "  -g snapshot-age:  Age of snapshots in days to be deleted from all file systems. Required if -s is not specified."
  echo "  -i instance-name: Instance user name, default is the user running this script (optional)"
  echo "  -p:               Preview snapshot names to be deleted from all file systems (optional)"  
  echo
  return 0
}


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
            if [[ "$name" = "snapPrefix" ]]; then
              snapPrefix=$val
            fi
            if [[ "$name" = "dirsToSnap" ]]; then
              dirsToSnap=$val
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
# Requires: $delDate, $snapAge
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
   os=$(uname -s)
   echo "DEBUG: calculating deletion date on platform $os"   

   case "$os" in
   Linux)
    delDate=$(date +%Y%m%d%H%M%S -d "$DATE - $snapAge day");;
   AIX)
	  curEp=$(date +"%s")
		(( expEp = curEp - ($snapAge * 86400) ))
	  delDate=$(ksh93 -c 'printf "%(%Y%m%d%H%M%S)T\n" "#$1"' ksh93 $expEp);;
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
# function del_apisnapshot to delete snapshots for filesystem and fileset
#
# Requires $configFile
# deletes snapshots 
#
# -----------------------------------------------------------------
function del_apisnapshot()
{
  echo "DEBUG: Entering del_apisnapshot() to delete snap $1 from $fsName in fileset $fsetName"
  
  sn=$1
  jobId=""
  frc=0

  # delete the snapshot which creates a job
  if [[ ! -z $fsetName ]]; then
    # echo "DEBUG: curl -k -X DELETE --header 'Content-Type: application/json' --header 'Accept: application/json' --header 'Authorization: Basic $apiAuth' 'https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots/$sn' "

    jobId=$(curl -k -X DELETE --header 'Content-Type: application/json' --header 'Accept: application/json' --header "Authorization: Basic $apiAuth"  "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots/$sn" 2>>/dev/null | grep "jobId" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/^ *//g')

  else
    echo "DEBUG: curl -k -X DELETE --header 'Content-Type: application/json' --header 'Accept: application/json' --header 'Authorization: Basic $apiAuth' 'https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots/$sn' "

    jobId=$(curl -k -X DELETE --header 'Content-Type: application/json' --header 'Accept: application/json' --header "Authorization: Basic $apiAuth"  "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots/$sn" 2>>/dev/null  | grep "jobId" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/^ *//g')
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
      echo "INFO: checking job $jobId for completion ($loops)."
      sleep $sleeptime

	    jState=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/jobs?fields=%3Aall%3A&filter=jobId%3D$jobId" 2>>/dev/null | grep "status" | grep -v "{" | cut -d':' -f 2 | sed 's/,*$//g' | sed 's/"//g' | sed 's/^ *//g')
	 
	    echo "  DEBUG: job $jobId status: $jState, loop: $loops"
	    # if jState is empty, then perform the jobID query without parsing
	    if [[ -z $jState ]]; then
	      echo "  DEBUG: Job status is empty, performing jobID query again."
		    curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/jobs?fields=%3Aall%3A&filter=jobId%3D$jobId"
	    fi

	    (( loops = loops + 1 ))
    done
  else
    echo "ERROR: no REST API job was created, snapshot delete failed."
    jState="FAILED"
  fi
  
  if [[ $jState = "COMPLETED" ]]; then
    return 0
  else
    echo "ERROR: job $jobId did not complete, status=$jState"
    return 1
  fi
  
}


# -----------------------------------------------------------------
# function match_apisnapshot identifies snapshots that are older than specified age
#
# Requires fsName, fsetName, delDate
# 
#
# -----------------------------------------------------------------
function match_apisnapshot()
{

  while read -r line;
  do
    if [[ -z $line ]]; then
      continue
    fi

    # get the snapshot creation date from the snapname, last 14 chars
    sName=$(echo $line | awk '{print $1}')
    sDate=$(echo "${sName: -14}")
    # old code: sDate=$(date +%Y%m%d%H%M%S -d "$(echo $line | awk '{print $4" "$5}')")
    # echo "DEBUG: snapDate=$sDate, delDate=$delDate"
    if [[ "$sDate" < "$delDate" ]]; then
      snapName=$snapName" "$sName
      # echo "DEBUG: identified snap: $sName $sDate"
    fi
  done  <<< $(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName$fSet/snapshots?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName" 2>/dev/null | jq -r '.snapshots[] | [.snapshotName] | @csv' | sed 's/,/\" \"/g' | sed 's/\"//g')

  return 0

}

#---------------------------------------
# Main
#---------------------------------------

### present banner
echo "========================================================================================"
echo "INFO: $(date) program $0 version $ver started for instance $instUser"

# parse arguments from the command line
snapName=""
snapAge=""
preview=0
while [[ ! -z "$*" ]];
do
  case "$1" in
  "-i") # shift because we need the next arg in $1
        shift 1
        if [[ -z $1 ]]; then 
		  syntax "Instance user name is not specified."
		  exit 1
		else
		  instUser=$1
		fi;;
  "-s") shift 1
        if [[ -z $1 ]]; then 
		  syntax "Snapshot name is not specified."
		  exit 1
		else
		  snapName=$1
		fi;;
  "-g") shift 1
        if [[ -z $1 ]]; then 
		  syntax "Snapshot age is not specified."
		  exit 1
		else
		  snapAge=$1
		fi;;
  "-p") preview=1;;
  "-h" | "--help")
        syntax "command syntax"
        exit 1;;
  *)    syntax "wrong argument $1"
        exit 1;;
  esac
  shift 1
done

if [[ -z $snapName && -z $snapAge ]]; then
  syntax "Snapshot name (parameter -s) or snapshot age (parameter -g) not specified."
  exit 1
else
  if [[ ! -z $snapName && ! -z $snapAge ]]; then
    syntax "Snapshot name (parameter -s) and snapshot age (parameter -g) are mutual exclusive."
	exit 1
  fi
fi


# Initialize the instance specific parameters and parse the config
if [[ ! -a $configFile ]]; then
  echo "ERROR: config file $configFile not found. Please provide this file first."
  # $sudoCmd $gpfsPath/mmsysmonc event custom delsnap_fail "$instUser,Snapshot configuration file $confifFile not found."
  exit 2
fi
dirsToSnap=""
snapPrefix=""
apiServer=""
apiPort=""
apiAuth=""
parse_config


# check parameters
if [[ -z $dirsToSnap ]]; then
  syntax "Parameter dirsToSnap is emtpy. User name invoking this script is $instUser"
  # $sudoCmd $gpfsPath/mmsysmonc event custom delsnap_fail "$instUser,Instance configuration file does not contain valid file system and fileset information for $instUser."
  exit 3
fi
# if API server was specified and no credentials then exit, set API port to default 443 if not set
if [[ ! -z $apiServer ]]; then
  if [[ -z $apiAuth ]]; then
    echo "ERROR: REST API credentials not defined in configuration file"
    # $sudoCmd $gpfsPath/mmsysmonc event custom delsnap_fail "$instUser, No apiAuthentication defined for API server $apiServer in configuration file."
    exit 4
  fi
  if [[ ! -z $apiPort ]]; then
    apiServer="$apiServer:$apiPort"
  else
    apiServer="$apiServer:443"
  fi
fi

# calculate the date of snapshots to be deleted
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
    echo "ERROR: Unable to calculate deletion date. Contact support."
    # $sudoCmd $gpfsPath/mmsysmonc event custom snap_fail "$instUser,Unable to calculate expiration date."
    exit 2
  fi
  if [[ -z $apiServer ]]; then
    echo "INFO: $op snapshots deletion for snaps older than $snapAge days ($delDate) using CLI as $instUser"
  else
    echo "INFO: $op snapshots deletion for snaps older than $snapAge days ($delDate) using API server $apiServer"
  fi
else
  if [[ -z $apiServer ]]; then
    echo "INFO: $op snapshot deletion for snap $snapName using CLI as $instUser"
  else
    echo "INFO: $op snapshot deletion for snap $snapName using API server $apiServer"
  fi
fi


# iterate through the dirsToSnap and delete snapshots
rc=0
fsName=""
fsetname=""
item=""
for item in $(echo "$dirsToSnap" | sed 's/,/ /g')
do
  # echo "  DEBUG: item=$item"
  if [[ -z $item ]]; then
     continue
  else
    fsName=$(echo $item | cut -d'+' -f 1)
    fsetName=$(echo $item | cut -d'+' -f 2 -s)
	  fSet=""
    if [[ -z $fsetName ]]; then
	    fSet=""
	  else
	    if [[ -z $apiServer ]]; then
	      fSet="-j $fsetName"
	    else
	      fSet="/filesets/$fsetName"
	    fi
	  fi

    echo "INFO: processing file system $fsName fileset $fsetName"
	 
	  # determine all snapshots in file system and fileset that are older than snapAge
	  if [[ ! -z $snapAge ]]; then
	    snapName=""
	    if [[ -z $apiServer ]]; then
	      # if no API server is specified check using command line
  	    while read -r line;
	      do
		      if [[ -z $line ]]; then
		        continue
		      fi
          # get the snapshot creation date from the snapname, last 14 chars
          sName=$(echo $line | awk '{print $1}')
          sDate=$(echo "${sName: -14}")
	        # old code: sDate=$(date +%Y%m%d%H%M%S -d "$(echo $line | awk '{print $5" "$6" "$7" "$8}')")
	        # echo "DEBUG: snapDate=$sDate, delDate=$delDate"
	        if [[ "$sDate" < "$delDate" ]]; then
		        snapName=$snapName" "$sName
		        # echo "DEBUG: identified snap: $sName $sDate"
	        fi
	      done  <<< $($sudoCmd $gpfsPath/mmlssnapshot $fsName $fSet | grep "$snapPrefix")
	    else
        # with apiServer specified check via rest API
        snapName=""
        match_apisnapshot
        rc=$?
      fi
    fi
	  if [[ ! -z $snapName ]]; then
      for snap in $snapName; 
	    do
	      if (( preview == 1 )); then
           echo -e "Snapshots candidate for deletion: \t$snap"
	      else
	        if [[ -z $apiServer ]]; then
	          # echo "$sudoCmd $gpfsPath/mmdelsnapshot $fsName $snap $fSet"
			      $sudoCmd $gpfsPath/mmdelsnapshot $fsName $snap $fSet
		        (( rc = rc + $? ))
		      else
		        del_apisnapshot $snap
		        (( rc = rc + $? ))
		      fi
		      sleep $sleepTime
	      fi
	    done
	  else
	    echo "INFO: No snapshot is candidate for deletion."
	  fi
  fi
done

if (( rc > 0 )); then
  echo "ERROR: $op snapshot deletion failed, check the log."
  if [[ $op = "perform" ]]; then 
    # if this path is not active, just pretend to sleep a second
	  sleep 0
    # $sudoCmd $gpfsPath/mmsysmonc event custom delsnap_fail "$instUser,Snapshot deletion failed, check the log."
  fi
  exit 5
else
  echo "INFO: $(date) $op snapshot deletion completed successfully."
fi 

exit 0
