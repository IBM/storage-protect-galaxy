#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2025
#                                                                              
# Name: isnap-list.sh
# Desc: List snapshots in all file systems and filesets using CLI or REST API
#
# Input: 
# -v: verbose output showing the allocated blocks, default is no verbose
# -i instance-name: name of the instance user, default is the user running this script
#
# Dependencies:
# this scripts runs on the host where the instance is running and uses sudo
# requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - file systems and fileset belonging to the instance
# - snapshot prefix
#
# Usage:
# isnap-list.sh [-i instance-user-name -s snapshot-name -v -h | --help]
#   -i instance-user-name:  Name of the instance (user) for which the snapshots are listed (optional, default is user running this command).
#   -s snapshot-name:       Snapshot name to be listed (checked) for all relevant file systems and filesets (optional, lists all snapshot by default).
#   -v:                     Show allocated blocks (optional, does not work with REST API)
#   -h | --help:            Show this help message (optional).
# 
#********************************************************************************
#
# History
# 04/30/25 added sudoCmd to snapconfig.json - version 1.2.1
# 11/13/25 allow script to be located in any directory; replace syntax by usage function - version 1.3

#---------------------------------------
# global parameters
#---------------------------------------
# name of the config file
configFile=snapconfig.json
#configFile=snapconfig.json

# path of GPFS commands
gpfsPath="/usr/lpp/mmfs/bin"

# determine the name of the instance user for reference
instUser=$(id -un)

# version of the program
ver="1.3"


#------------------------------------------------------------------
# Print usage
#------------------------------------------------------------------
function usage()
{
    if [[ ! -z $1 ]]; then
     echo "ERROR: $1"
    fi

    echo "Usage:"
    echo "isnap-list.sh [-i instance-user-name -s snapshot-name -v -h | --help]"
    echo " -i instance-user-name:  Name of the instance (user) for which the snapshots are listed (optional, default is user running this command)."
    echo " -s snapshot-name:       Snapshot name to be listed (checked) for all relevant file systems and filesets (optional, lists all snapshot by default)."
    echo " -v:                     Show allocated blocks (optional, does not work with REST API)"
    echo " -h | --help:            Show this help message (optional)."
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
# function list_apisnapshot to list snapshots for filesystem and fileset
#
# Requires $configFile
# lists snapshots 
#
# -----------------------------------------------------------------
function list_apisnapshot()
{
  # echo "DEBUG: Entering list_apisnapshot()"
  
  jqPath=/usr/bin/jq
  frc=0
  # list snapshots
  if [[ ! -z $fsetName ]]; then
    # echo "DEBUG: curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName""
	
	echo -e "\nSnapshots in file system $fsName and fileset $fsetName (via REST API):"
	if [[ -a $jqPath ]]; then
	  printf "%-23s %-7s %-7s %-23s %-31s %-10s %s\n" "SnapshotName" "Id" "State" "CreationTime" "ExpirationTime" "Fileset"
	  curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName"  2>/dev/null | jq -r '.snapshots[] | [.snapshotName, .snapID, .status, .created, .expirationTime, .filesetName] |  @csv' 2>/dev/null | sed 's/",/\t/g' | sed 's/,"/\t/g' |sed 's/\"//g'
	  frc=$?
	else
	  curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName" 2>/dev/null
	  frc=$?
	fi
  else
    # echo "DEBUG: curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName""
	
	echo -e "\nGlobal snapshots in filesystem $fsName: (via REST API)"
	if [[ -a $jqPath ]]; then
	  printf "%-23s %-7s %-7s %-23s %-31s %-10s %s\n" "SnapshotName" "Id" "State" "CreationTime" "ExpirationTime" "Fileset"
	  curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName"  2>/dev/null | jq -r '.snapshots[] | [.snapshotName, .snapID, .status, .created, .expirationTime, .filesetName] | @csv' | 2>/dev/null sed 's/",/\t/g' | sed 's/,"/\t/g' |sed 's/\"//g'
	  frc=$?
	else
	  curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName" 2>/dev/null
	  frc=$?
	fi
  fi
  
  return $frc
  
}

#---------------------------------------
# Main
#---------------------------------------

# present banner
echo -e "\n============================================================================================="
echo -e "INFO: $(date) program $0 version $ver started by $instUser"

# parse arguments from the command line
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
        usage
        exit 1;;
  *)    usage "wrong argument $1"
        exit 1;;
  esac
  shift 1
done

### determine directory where the script is started from
basePath=$(dirname $0)
if [[ $basePath = "." ]]; then
  basePath=$PWD
fi
#echo "DEBUG: base path for $0: $basePath"

configFile="$basePath/$configFile"
echo -e "DEBUG: Using config file: $configFile\n"
# echo "DEBUG: configfile: $configFile"
# Initialize the instance specific parameters and parse the config
if [[ ! -a $configFile ]]; then
  echo "ERROR: config file $configFile not found. Please provide this file first."
  exit 1
fi
dirsToSnap=""
snapPrefix=""
sudoCmd="/usr/bin/sudo"
apiServer=""
apiPort=""
apiAuth=""
parse_config
#echo -e "DEBUG: Snapshot configuration from $configFile:\n  dbName=$dbName\n  dirsToSnap=$dirsToSnap\n  snapPrefix=$snapPrefix\n  snapRet=$snapRet\n  serverInstDir=$serverInstDir\n  sudoCommand=$sudoCmd\n  apiServer=$apiServer\n  apiPort=$apiPort\n  apiAuth=$apiAuth\n"



### Check required parameters
# check that dirsToSnap exists, if not then exit
if [[ -z $dirsToSnap ]]; then
  echo "ERROR: parameter dirsToSnap is emtpy. Instance user name is $instUser."
  echo "       The user name $instUser may not be configured in $configFile."
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

# compose dParam
if [[ $verbose = 1 ]]; then
  dParam="-d --block-size auto"
else
  dParam=""
fi
# if snapName is specified compose the snapSuffix
if [[ ! -z $snapName || ! -z $apiServer ]]; then
  snapSuffix="/$snapName"
else
  snapSuffix=""
fi

# echo "DEBUG: snapshot name=$snapName, suffix=$snapSuffix"


# iterate through the dirsToSnap and list snapshot
for item in $(echo "$dirsToSnap" | sed 's/,/ /g')
do
  # echo "  DEBUG: item=$item"
  if [[ -z $item ]]; then
     continue
  else
     fsName=$(echo $item | cut -d'+' -f 1)
     fsetName=$(echo $item | cut -d'+' -f 2 -s)
     # echo "DEBUG: $fsName,$fsetName" 
     if [[ -z $fsetName ]]; then
       # global snapshot 
	   if [[ -z $apiServer ]]; then
	     # if snapName is given, then the command is different
		 if [[ -z $snapName ]]; then
           # echo "DEBUG: $gpfsPath/mmlssnapshot $fsName $dParam"
           $sudoCmd $gpfsPath/mmlssnapshot $fsName $dParam
		   (( rc = rc + $? ))
		 else
		   # echo "$gpfsPath/mmlssnapshot $fsName -s snapName $dParam"
           $sudoCmd $gpfsPath/mmlssnapshot $fsName -s $snapName $dParam
		   (( rc = rc + $? ))
		 fi
		 echo
	   else 
		 list_apisnapshot
		 (( rc = rc + $? ))
		 # echo "DEBUG: rc=$rc"
	   fi
     else
	   # fileset snapshot
	   if [[ -z $apiServer ]]; then
	     # if snapName is given, then the command is different
	     if [[ -z $snapName ]]; then
           # echo "DEBUG: $gpfsPath/mmlssnapshot $fsName -j $fsetName $dParam"
           $sudoCmd $gpfsPath/mmlssnapshot $fsName -j $fsetName $dParam
	       (( rc = rc + $? ))
		 else
           # echo "$gpfsPath/mmlssnapshot $fsName -s $fsetName:$snapName $dParam
           $sudoCmd $gpfsPath/mmlssnapshot $fsName -s $fsetName:$snapName $dParam
	       (( rc = rc + $? ))		 
		 fi
		 echo
	   else
		 list_apisnapshot
		 (( rc = rc + $? ))
		 # echo "DEBUG: rc=$rc"
	   fi
     fi
   fi
done

echo
exit 0
