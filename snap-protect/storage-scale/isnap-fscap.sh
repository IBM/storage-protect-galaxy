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

#---------------------------------------
# global parameters
#---------------------------------------
# name of the config file
configFile=snapconfig.json

# path of GPFS commands
gpfsPath="/usr/lpp/mmfs/bin"

# name of the snapshot directory, default is .snapshots
snapshotDir=".snapshots"

# determine the name of the instance user for reference
instUser=$(id -un)

# version
ver=1.4


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

### present banner
echo -e "\n============================================================================================="
echo "INFO: $(date) program $0 version $ver started by $instUser"

### parse arguments from the command line
verbose=0
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
# echo "DEBUG: base path for $0: $basePath"

configFile="$basePath/$configFile"
echo -e "DEBUG: Using config file: $configFile\n"
### Initialize the instance specific parameters and parse the config
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
  usage "Specify the instance user with parameter -i"
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
	    fsPath=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiAuth" "https://$apiServer/scalemgmt/v2/filesystems/$fsName/filesets/$fsetName" 2>>/dev/null | jq ".filesets[] | .config.path" 2>>/dev/null | sed 's/\"//g')
	  fi
    
    # if there is a fileset path then get capacities
    if [[ ! -z $fsPath ]]; then	 
	    # fsPath="$fsPath"
	    # echo "DEBUG: fsPath=$fsPath"
      fsCap=""
      fsCapNum=0
      fsCap=$(/usr/bin/du "$duOpt" "$fsPath" | awk '{print $1}')
      snapCap=""
      snapCapNum=0
      snapCap=$(/usr/bin/du "$duOpt" "$fsPath"/$snapshotDir | awk '{print $1}')
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

