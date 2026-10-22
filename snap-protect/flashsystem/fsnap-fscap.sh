#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2026
#
#--------------------------------------------------------------------------------
# ATTENTION: This is a beta-version and must not be used for production. Any 
# failure or damage on production system is under your own liabilit.
#--------------------------------------------------------------------------------
#
# Name: fsnap-fscap.sh
# Desc: Determines the capacity allocated in the file systems and snapshots on flashsystem.
#
# Dependencies:
# This scripts must run on the host where the instance is running
# Requires snapconfig.json that defines the instance specific parameters:
# - instance user name
# - flashsystem volume groups
# - file systems
#
# Usage:
# fsnap-fscap.sh [-i instance-user-name]
#  -i instance-user-name: instance name to the fileset capacities
#  -h | --help:            Show this help message (optional).
# 
#********************************************************************************

# History:
#----------
# 2/14/24 added support for TSLM and removed mmSharedTmpDir from output
# 10/31/24 adjusted for FlashSystem
# 03/25/25 AIX compatibility changes - version 1.2
# 04/06/25 AIX compatibility: use du -gs instead of du -hs
# 03/22/25 use common functions from $funcFile
# 05/23/25 support multiple flashsystems per instance - version 1.3
# 06/12/25 remove hard-coding of /usr/local/bin
# 09/04/25 show compact capacity statistic if vg-fs mapping exist in configFile - version 1.4
# 09/09/25 AIX: du -gs does not show unit, add unit and checking of unit, base statistic is GB
# 09/15/25 fixed bug in convert_capacty when unit is MB
# 01/28/26 AIX: fixed bug where usedCap contains , instead of . causing errors in convert_capacity (bc) - version 1.4.1
# 02/12/26 added config parameter consistentSnap
# 04/12/26 use apiCredentials in config file 
# 04/13/26 print version of global functions (fsnapfunctions.sh)
# 04/24/26 remove initialization of configuration parameter arrays (moved to fsnapfunctions.sh)
# 06/02/26 add $sudoCmd to du command
# 06/05/26 # if fsUsed == 0 then factor = snapUsed - version 1.5
# 08/13/26 add structured logging functions (log_info, log_warn, log_debug, log_error) - version 1.5 (Dominic)
# 08/31/26 fix parameter parsing when calling fsnap-list.sh, remove get_apitoken call - version 1.6

#---------------------------------------
# global parameters
#---------------------------------------
# common functions file
funcFile="fsnapfunctions.sh"

# version
ver=1.6


# -----------------------------------------------------------------
# function usage 
#
# -----------------------------------------------------------------
function usage()
{
  echo
  log_error "$1"
  echo "Usage: fsnap-fscap.sh [-i instance-user-name]"
  echo "  -i instance-user-name: instanz name to the fileset capacities"
  echo
  return 0
}


#---------------------------------------------------------
#
# function: convert_capacity
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
      # echo "  DEBUG: convert_capacity: number $num has no unit, assuming unit is Byte"
   fi

   usedCapNum=$(echo "scale=2; $num *$factor" | bc | sed 's/^\./0./')
   # echo "  DEBUG: final number=$usedCapNum"
   if [[ -z $usedCapNum ]]; then
      log_error "Unable to calculate used capacity number using string $usedCap."
      frc=1
   fi

   return $frc

}


#---------------------------------------
# Main
#---------------------------------------

### determine directory where the script is started from
basePath=$(dirname $0)
if [[ $basePath = "." ]]; then
  basePath=$PWD
fi
# echo "DEBUG: base path for $0: $basePath"

### source common functions
if [[ -f $basePath/$funcFile ]]; then
  . $basePath/$funcFile
else
  echo "ERROR: common functions file $basePath/$funcFile not found, or insufficient permission for instance user." >&2
  exit 1
fi

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
        usage "command usage"
        exit 1;;
  *)    usage "wrong argument $1"
        exit 1;;
  esac
  shift 1
done

### present banner
log_info "program $0 version $ver started for instance $instUser (global functions version $globFuncVer)"


### determe OS and set du parameter, $os comes from functions
#os=$(uname -s)
case "$os" in
Linux)
  duOpt="-hs";;
AIX)
  duOpt="-gs";;
*)
  duOpt="-unknownOS";;
esac

### get the parameters for this instance user from the config_file
if ! parse_config; then
  log_error "parsing the config file $configFile failed. Check json syntax."
  exit 1
fi


### check configuration parameters
# check if we found any entries in config file
if (( arrLen < 0 )); then
  log_error "no configuration found for user $instUser in config file $configFile."
  log_error "  Either run the program as instance user or use parameter -i [instUser]."
  exit 1
fi


### check config parameters and apply default values where possible
# echo "INFO: Checking configuration parameters."
if ! check_config; then
  exit 2
fi

### get the API tokens and log the local time of each FlashSystem
# removed because API token is fetched when running fsnap-list.sh

# print_config
# read a

### if we have mappings, then print the compact view
if (( mapIndex >= 0 )); then
  ### get capacity for file systems in $vgfs
  i=0
  unitLen="-1"
  vgfsUsed_arr=()
  rc=0
  while (( i <= mapIndex ));
  do
    vgfs=${vgfs_arr[$i]}
    fsName=""
    vgfsUsed_arr[$i]=0
    for fsName in $(echo "$vgfs" | sed 's/,/ /g');
    do
      if [[ -d $fsName ]]; then
        usedCap=""
        usedCapNum=0
        # echo -e "DEBUG: Getting capacity for file system $fsName"
        # Fix: convert , to . in usedCap
        usedCap=$(${sudoCmd_Arr[$i]} /usr/bin/du "$duOpt" $fsName | awk '{print $1}' | sed 's/,/\./g' )
        if [[ ! -z $usedCap ]]; then
          # add unit GB to usedCap, assuming we do du -gs
          if [[ $os == "AIX" ]]; then
            usedCap="$usedCap"G
          fi
          convert_capacity
          vgfsUsed_arr[$i]=$(echo "scale=2; ${vgfsUsed_arr[$i]} + $usedCapNum" | bc | sed 's/^\./0./')
        else
          log_warn "Unable to determine capacity for file system $fsName. Ensure the file system exists and it belongs to instance user $instUser."
          (( rc += 1 ))
        fi
      else
        log_warn "filesystem $fsName does not exist"
        vgfs_arr[$i]="undefined"
        (( rc += 1 ))
      fi
    done
    (( i += 1))
  done


  ### get capacity of snapshots for volume group in $vgname
  i=0
  vgsnapUsed_arr=()
  unitLen="-2"
  while (( i <= mapIndex ));
  do
    vgname=${vgname_arr[$i]}
    vgsnapUsed_arr[$i]=0
    usedCap=""
    if [[ ! -z $vgname ]]; then
      rc=0
      # echo -e "DEBUG: Getting capacity for volume group $vgname"

      while read -r usedCap;
      do
        if [[ ! -z $usedCap ]]; then
          # usedCap=$(echo $usedCap | sed 's/,/\./g')
          usedCapNum=0
          convert_capacity
          vgsnapUsed_arr[$i]=$(echo "scale=2; ${vgsnapUsed_arr[$i]} + $usedCapNum" | bc | sed 's/^\./0./')
        else
          log_warn "Unable to determine SGC capacity for volume group $vgname. Ensure the volume group exists and belongs to instance user $instUser."
          (( rc += 1 ))
        fi
        # Fix: convert , to . in usedCap
      done <<< $($basePath/fsnap-list.sh -i $instUser 2>>/dev/null | grep -w "$vgname" | grep "active" | awk '{print $10}' | sed 's/,/\./g')
    else
      log_warn "volume group name not defined (vgName=$vgname)"
      vgname_arr[$i]="undefined"
      (( rc += 1 ))
    fi
    (( i += 1 ))
  done


  ### calculate factor of snap-capacity / fs-capacity
  i=0
  fsSnapFactor_arr=()
  while (( i <= mapIndex ));
  do
    vgfsUsed=0
    vgfsUsed=$(echo ${vgfsUsed_arr[$i]} | sed 's/\./,/g')
    # compare floating point numbers is more tricky, bc -l does not work on AIX        
    if [[ $(echo $vgfsUsed 0 | awk '{if ($1 > $2) print 0; else print 1}') == 0 ]]; then
      fsSnapFactor_arr[$i]=$(echo "scale=2; ${vgsnapUsed_arr[$i]} / ${vgfsUsed_arr[$i]}" | bc | sed 's/^\./0./')
    else
      # if fsUsed == 0 then factor = snapUsed 
      fsSnapFactor_arr[$i]=${vgsnapUsed_arr[$i]}
    fi
    (( i += 1 ))
  done

  curDate=$(date  +"%Y-%m-%d@%T")

  ### print the results
  i=0
  printf "\n%-21s %15s %20s %18s %15s\n" "Timestamp" "VG-Name" "FS-capacity [GB]" "SGC-capacity [GB]" "Factor"
  while (( i <= mapIndex ));
  do
    printf "%-21s %15s %20s %18s %15s\n" $curDate ${vgname_arr[$i]} ${vgfsUsed_arr[$i]} ${vgsnapUsed_arr[$i]} ${fsSnapFactor_arr[$i]}
    (( i += 1 ))
  done

  echo -e "\n====================================================================================================\n"

# if we have no mapping, then print the tradional view
else

  # iterate through file systems and display occupation
  echo -e "\nINFO: Used capacity by file systems."
  fsName=""
  rc=0
  usedCap=""
  fSys=""
  i=0
  while (( i <= arrLen ));
  do
    fSystems=${fSystems_Arr[$i]}
    fsName=""
    rc=0
    for fsName in $(echo "$fSystems" | sed 's/,/ /g')
    do
      usedCap=$(/usr/bin/du "$duOpt" $fsName | awk '{print $1}')
      if [[ ! -z $usedCap ]]; then
        printf "%-30s %5s\n" $fsName $usedCap
        #echo -e "  $fsName:\t\t$usedCap"
        fSys="$fSys|$fsName"
      else
        log_warn "Unable to determine capacity for file system $fsName"
      fi
    done
    (( i = i + 1 ))
  done

  echo -e "\n------------------------------------------------------------------------------------------\n"

  # get the SGC statistics
  $basePath/fsnap-list.sh -i $instUser
fi

exit 0

