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
# isnap-fscap.sh [-i instance-user-name]
#  -i instance-user-name: instance name to the fileset capacities
#  -h | --help:            Show this help message (optional).
# 
#********************************************************************************
#
# History
# 04/30/25 added sudoCmd to snapconfig.json - version 1.3.1
# 09/10/25 summarize the capacity and calculate factor, remove syntax function - Version 1.4
# 11/13/25 allow script to be located in any directory
# 02/03/26 Fix (AIX): replace , by . for numbers fed into convert_capacity() (bc) - version 1.4.1
# 04/28/26 adopt global functions isnapfunctions.sh with new configuration file format - version 1.5


#---------------------------------------
# global parameters
#---------------------------------------
# common functions file name
funcFile="isnapfunctions.sh"

# path of GPFS commands
gpfsPath="/usr/lpp/mmfs/bin"

# name of the snapshot directory, default is .snapshots
snapshotDir=".snapshots"

# version
ver=1.5


#------------------------------------------------------------------
# Function: usage
#
# description: Print usage 
#
# input: error message (optional)
#
# output: usage and return code 0
#
#------------------------------------------------------------------
function usage()
{
    if [[ ! -z $1 ]]; then
      echo "ERROR: $1"
    fi
    echo "Usage:"
    echo "isnap-fscap.sh [-i instance-user-name]"
    echo " -i instance-user-name: instance name to the fileset capacities"
    echo " -h | --help:            Show this help message (optional)."
    echo
    return 0
}


#---------------------------------------------------------
#
# function: convert_capacity
#
# description: convert a string in the format 280k to number, base unit is GB
#
# input: userCap (string with number and unit)
#
# output: usedCapNum (number)
#
#---------------------------------------------------------
function convert_capacity()
{  
   # echo -e "  INFO: Entering convert_capacity() for $usedCap"
   unit=""
   num=0
   factor=1
   usedCapNum=""
   num=""
   frc=0
   
   # check if the string usedCap contains a unit
   u=""
   u=$(echo $usedCap | grep -E "B|K|KB|M|MB|G|GB|T|TB")
   if [[ ! -z $u ]]; then
     # if there is a unit cut the last character
     unit="${usedCap: unitLen}"
     # echo "  DEBUG: unit=$unit"
     case $unit in
     B)    factor=$(echo "scale=9; 1.0*0.00098*0.00098*0.00098" | bc | sed 's/^\./0./');;
     K|KB) factor=$(echo "scale=6; 1.0*0.00098*0.00098" | bc | sed 's/^\./0./');;
     M|MB) factor=$(echo "scale=3; 1.0*0.00098" | bc | sed 's/^\./0./');;
     G|GB) factor=1;;
     T|TB) factor=1024;;
     esac
     # echo "  DEBUG: factor=$factor"

     num=$(echo "${usedCap::unitLen}") # | sed 's/\./,/g')
     # echo "  DEBUG: number=$num"
     # (( usedCapNum = num * factor ))
   else
      # if no unit is provided, we assume Byte
      factor=$(echo "scale=9; 1.0*0.00098*0.00098*0.00098" | bc | sed 's/^\./0./')
      num=$usedCap
      # echo "  DEBUG: convert_capacity: number $num has no unit, assuming unit is GB"
   fi

   usedCapNum=$(echo "scale=2; $num *$factor" | bc | sed 's/^\./0./')
   # echo "  DEBUG: final number=$usedCapNum"

   if [[ -z $usedCapNum ]]; then
      echo "  ERROR: Unable to calculate used capacity number using string $usedCap."
      frc=1
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
echo "INFO: $(date) program $0 version $ver started by $instUser (global function $globFuncVer)"

### parse arguments from the command line
verbose=0
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


### Print method for gathering facts
if [[ -z $apiServer ]]; then
  echo "INFO: $(date) Getting capacity statistic for all filesystems of instance $instUser via command line. "
else
  echo "INFO: $(date)  Getting capacity statistic for all filesystems of instance $instUser via REST API."
fi

### set du that is platform specific, -h is not available in AIX
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


### iterate through dirsToSnap, determine file system and fileset path and get capacity for file system and snapshots
item=""
# unit length is -1 such as in 2.0G
unitLen="-1"
rc=0
for item in $(echo "$dirsToSnap" | sed 's/,/ /g')
do
  # echo "  DEBUG: item=$item"
  if [[ -z $item ]]; then
     continue
  else
    fsName=""
    fsetName=""
    fsName=$(echo $item | cut -d'+' -f 1)
    fsetName=$(echo $item | cut -d'+' -f 2 -s)
    if [[ -z $fsetName ]]; then
      # file system level 
	    fsetName=root
	  fi

    # echo "Capacity usage for filesystem $fsName, fileset $fsetName"

    # determine fileset path $fsPath
	  fsPath=""
	  if [[ -z $apiServer ]]; then
	    fsPath=$($sudoCmd $gpfsPath/mmlsfileset $fsName | grep $fsetName  | awk '{print $3}')
	  else
	    fsPath=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName" 2>>/dev/null | jq ".filesets[] | .config.path" 2>>/dev/null | sed 's/\"//g')
	  fi
    
    # if there is a fileset path then get capacities
    if [[ ! -z $fsPath ]]; then	 
	    # fsPath="$fsPath"
	    # echo "DEBUG: fsPath=$fsPath"
      fsCap=""
      fsCapNum=0
      # Fix: replace , by . in $fsCap
      fsCap=$(/usr/bin/du "$duOpt" "$fsPath" | awk '{print $1}' | sed 's/,/\./g')
      snapCap=""
      snapCapNum=0
      # Fix: replace , by . in $snapCap
      snapCap=$(/usr/bin/du "$duOpt" "$fsPath"/$snapshotDir | awk '{print $1}' | sed 's/,/\./g')
      if [[ ! -z $fsCap && ! -z $snapCap ]]; then
        # add unit G to fsCap on AIX, assuming we do du -gs
        if [[ $os == "AIX" ]]; then
          # echo "DEBUG: adding G to $fsCap and $snapCap"
          fsCap="$fsCap"G
          snapCap="$snapCap"G
        fi
        # convert file system capacity to number
        usedCap=$fsCap
        convert_capacity
        fsCapNum=$usedCapNum

        # convert file system capacity to number
        usedCap=$snapCap
        convert_capacity
        snapCapNum=$usedCapNum

        # substract the snapshot capacity from the file system capacity, because snapshot is included in file system capacity
        fsCapOnly=$(echo "scale=2; $fsCapNum - $snapCapNum" | bc | sed 's/^\./0./')

        # compare floating point numbers is more tricky, bc -l does not work on AIX        
        if [[ $(echo $fsCapOnly 0 | awk '{if ($1 > $2) print 0; else print 1}') == 0 ]]; then
          fsSnapFactor=$(echo "scale=2; $snapCapNum / $fsCapOnly" | bc | sed 's/^\./0./')
        else
          fsSnapFactor=0.0
        fi

        # print statistic 
        curDate=$(date  +"%Y-%m-%d@%T")
        printf "\n%-21s %15s %20s %18s %15s\n" "Timestamp" "FS-Name" "FS-capacity [GB]" "Snap-capacity [GB]" "Factor"
        printf "%-21s %15s %20s %18s %15s\n" $curDate $fsName $fsCapOnly $snapCapNum $fsSnapFactor
  	  else 
        echo "  WARNING: Unable to determine capacity for filesystem $fsName and fileset $fsetName (fscap=$fsCap, snapcap=$snapCap)"
        echo "           Command used was du $duOpts $fsPath | $fsPath/$snapshotDir"
	      (( rc = rc + 1 ))
      fi
    else 
      echo "  WARNING: Unable to determine path for filesystem $fsName and fileset $fsetName."
	    (( rc = rc + 1 ))
	  fi
  fi
done

echo
exit $rc

