#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2025
#                                                                              
# Name: isnap-fscap.sh
# Desc: Determines the capacity allocated in the file system / fileset for active data and snapshots
#
# Input: 
# -i instance-user: (optional) name of the instance user, default is the user running this script
#
# Dependencies:
# this scripts runs on a GPFS cluster node using the CLI or the REST API
# requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - file systems and fileset belonging to the instance
# - API server (optional) if REST API is used instead of command line
# requires jq to be installed 
#
# Usage:
# ./isnap-fscap.sh [-i instance-user-name]
#  -i instance-user-name: instance name to the fileset capacities
#  -h | --help:            Show this help message (optional).
# 
#********************************************************************************

#---------------------------------------
# global parameters
#---------------------------------------
# name of the config file
configFile=/usr/local/bin/snapconfig.json

# path of GPFS commands
gpfsPath="/usr/lpp/mmfs/bin"

# name of the snapshot directory, default is .snapshots
snapshotDir=".snapshots"

# determine the name of the instance user for reference
instUser=$(id -un)

# sudo command to be used
sudoCmd=/usr/bin/sudo

# version
ver=1.3


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

#------------------------------------------------------------------
# Print usage
#------------------------------------------------------------------
function usage()
{
     echo "Usage:"
     echo "./isnap-fscap.sh [-i instance-user-name]"
     echo " -i instance-user-name: instance name to the fileset capacities"
     echo " -h | --help:            Show this help message (optional)."
     echo
     return 0
}

# -----------------------------------------------------------------
# function syntax
#
# -----------------------------------------------------------------
function syntax()
{
  if [[ ! -z $1 ]]; then
     echo "ERROR: $1"
     usage
  else
     usage
  fi
  return 0
}

#---------------------------------------
# Main
#---------------------------------------

# parse arguments from the command line
verbose=0
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
  "-h" | "--help")
        syntax
        exit 1;;
  *)    syntax "wrong argument $1"
        exit 1;;
  esac
  shift 1
done


# Initialize the instance specific parameters and parse the config
if [[ ! -a $configFile ]]; then
  echo "ERROR: config file $configFile not found. Please provide this file first."
  exit 1
fi
dirsToSnap=""
snapPrefix=""
apiServer=""
apiPort=""
apiAuth=""
parse_config


### Check required parameters
# check that dirsToSnap exists, if not then exit
if [[ -z $dirsToSnap ]]; then
  echo "ERROR: parameter dirsToSnap is emtpy. Instance user name is $instUser."
  echo "       The user name $instUser may not be configured in $configFile."
  syntax "Specify the instance user with parameter -i"
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

# iterate through the dirsToSnap and list capacity
if [[ -z $apiServer ]]; then
  echo "INFO: $(date) Getting stats for all filesystems of instance $instUser (version $ver)."
else
  echo "INFO: $(date) Getting stats for all filesystems of instance $instUser (via REST API, version $ver)."
fi
i=0
item=""
fsName=""
fsetName=""
for item in $(echo "$dirsToSnap" | sed 's/,/ /g')
do
  # echo "  DEBUG: item=$item"
  if [[ -z $item ]]; then
     continue
  else
    fsName=$(echo $item | cut -d'+' -f 1)
    fsetName=$(echo $item | cut -d'+' -f 2 -s)
    if [[ -z $fsetName ]]; then
      # file system level 
	    fsetName=root
	  fi
	  fsPath=""
    echo "Capacity usage for filesystem $fsName, fileset $fsetName"
	  if [[ -z $apiServer ]]; then
	    fsPath=$($sudoCmd $gpfsPath/mmlsfileset $fsName | grep $fsetName  | awk '{print $3}')
	  else
	    fsPath=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName?fields=config.path" 2>>/dev/null | grep "\"path\" :" | cut -d':' -f2 -s | sed 's/"//g' | sed 's/\[//g' | sed 's/\]//g' | sed 's/,*$//g' | sed 's/^ *//g')
	  fi

    if [[ ! -z $fsPath ]]; then	 
	    fsPath="$fsPath"
	    # echo "DEBUG: fsPath=$fsPath"
      # du is platform specific, -h is not available in AIX
      os=$(uname -s)
      duOpt=""
      dfOpt=""
      case "$os" in
      Linux)
         duOpt="-hs"
         dfOpt="-h";;
      AIX)
         duOpt="-gs"
         dfOpt="-g";;
      *)
         duOpt="-unknownOS"
         dfOpt="-unknownOS";;
      esac
      /usr/bin/du "$duOpt" $fsPath
      /usr/bin/du "$duOpt" $fsPath/$snapshotDir
      (( rc = rc + $? ))
      echo "---------------------------------------------------"
  	else 
      echo "  WARNING: Unable to determine path for filesystem $fsName and fileset $fsetName."
	    (( rc = rc + 1 ))
      # echo "DEBUG: rc=$rc"
	  fi
  fi
done

echo "Getting global file system statistic"
df "$dfOpt" | grep -E "Size|tsm|tslm"

echo
echo "============================================================================================"
echo
exit 0

