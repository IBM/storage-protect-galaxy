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
# 04/28/26 adopt global functions isnapfunctions.sh with new configuration file format - version 1.4

#---------------------------------------
# global parameters
#---------------------------------------
# common functions file name
funcFile="isnapfunctions.sh"

# path of GPFS commands
gpfsPath="/usr/lpp/mmfs/bin"

# version of the program
ver="1.4"


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
    # echo "DEBUG: curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName""
	
	echo -e "\nSnapshots in file system $fsName and fileset $fsetName (via REST API):"
	if [[ -a $jqPath ]]; then
	  printf "%-23s %-7s %-7s %-23s %-31s %-10s %s\n" "SnapshotName" "Id" "State" "CreationTime" "ExpirationTime" "Fileset"
	  curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName"  2>/dev/null | jq -r '.snapshots[] | [.snapshotName, .snapID, .status, .created, .expirationTime, .filesetName] |  @csv' 2>/dev/null | sed 's/",/\t/g' | sed 's/,"/\t/g' |sed 's/\"//g'
	  frc=$?
	else
	  curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName" 2>/dev/null
	  frc=$?
	fi
  else
    # echo "DEBUG: curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName""
	
	echo -e "\nGlobal snapshots in filesystem $fsName: (via REST API)"
	if [[ -a $jqPath ]]; then
	  printf "%-23s %-7s %-7s %-23s %-31s %-10s %s\n" "SnapshotName" "Id" "State" "CreationTime" "ExpirationTime" "Fileset"
	  curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName"  2>/dev/null | jq -r '.snapshots[] | [.snapshotName, .snapID, .status, .created, .expirationTime, .filesetName] | @csv' | 2>/dev/null sed 's/",/\t/g' | sed 's/,"/\t/g' |sed 's/\"//g'
	  frc=$?
	else
	  curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/snapshots$snapSuffix?fields=snapshotName%2Cstatus%2CsnapID%2Ccreated%2CexpirationTime%2CfilesetName" 2>/dev/null
	  frc=$?
	fi
  fi
  
  return $frc
  
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
echo -e "INFO: $(date) program $0 version $ver started by $instUser (global function $globFuncVer)"

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
        usage
        exit 1;;
  *)    usage "wrong argument $1"
        exit 1;;
  esac
  shift 1
done
 
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


### compose snap list parameter
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
