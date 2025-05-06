#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2025
# 
# Name: isnap-wrapper.sh
# Desc: Wraps isnap-scripts and can be executed by Storage Protect client schedule
#
# Dependencies:
# - this scripts must run on the host where the instance is running
# - isnap-scripts must exist in $isnapPath
# - must be executed by privileged user that can invoke the $instUser via su
#
# Usage:
# ./isnap-wrapper.sh -i inst-name [-c | -d age | -l | -f ]
# -i inst-name: name of the instance to be processed
# -c: create snapshot - invokes isnap-create.sh -r
# -d age: delete snapshots older than age - invokes isnap-del.sh -g age
# -l: list snapshots - invokes isnap-list.sh
# -f: list fileset and snapshot capacities - invokes isnap-fscap.sh
# -h | --help:   Show this help message (optional)."
#
#*******************************************************************************
# return codes
# --------------
# 0 ok
# 4 warning
# 8 fail
#
#---------------------------------------
# history
# 04/18/25 first implementation
# 04/30/25 add logPath and log command output into logfile
# 04/30/25 add instance name as command line option, along with operation codes - version 0.91


# Global variables
#------------------

# path of the isnap-scripts
isnapPath="/usr/local/bin"

#log file path
logPath="/var/log/isnap"

# operation system type
os=$(uname -s)

# version
ver=0.91


#------------------------------------------------------------------
# Print usage
#------------------------------------------------------------------
function usage()
{
     echo "Usage:"
     echo "./isnap-wrapper.sh -i inst-name [-c | -d age | -l | -f ]"
     echo "  -i inst-name: name of the instance to be processed (required)"
     echo
     echo "  Even one of the following operation arguments is required."
     echo "  -c:     create snapshot - invokes isnap-create.sh -r"
     echo "  -d age: delete snapshots older than age - invokes isnap-del.sh -g age"
     echo "  -l:     list snapshots - invokes isnap-list.sh"
     echo "  -f:     list fileset and snapshot capacities - invokes isnap-fscap.sh"
     echo
     echo "  To get help"
     echo "  -h | --help:   Show this help message (optional)."
     echo
     return 0
}

# -----------------------------------------------------------------
# function syntax 
#
# -----------------------------------------------------------------
function syntax()
{
  echo
  if [[ ! -z $1 ]]; then
     echo "ERROR: $1"
     usage
  else
     usage
  fi

  exit 8
}



#---------------------------------------
# Main
#---------------------------------------

# present banner
echo -e "WRAPPER INFO: $(date) program $0 version $ver started on platform $os"

# parse arguments from the command line
op=""
instName=""
age=""
while [[ ! -z "$*" ]];
do
  case "$1" in
  "-i") 
      # shift because we need the next arg in $1
      shift 1
      if [[ -z $1 ]]; then 
		    syntax "Instance user name is not specified."
		  else
		    instName=$1
		  fi;;

  "-c") if [[ -z $op ]]; then 
          op=create
        else
          syntax "Multiple operations specified (create and $op). Specify only one operation at a time."
        fi;;

  "-l") if [[ -z $op ]]; then 
          op=list
        else
          syntax "Multiple operations specified (list and $op). Specify only one operation at a time."
        fi;;

  "-f") if [[ -z $op ]]; then 
          op=fscap
        else
          syntax "Multiple operations specified (fscap and $op). Specify only one operation at a time."
        fi;;

  "-d") if [[ -z $op ]]; then
          op=delete
          shift 1
          if [[ -z $1 ]]; then 
		        syntax "Snapshot age is not specified."
		      else
		        age=$1
		      fi 
        else
          syntax "Multiple operations specified (delete and $op). Specify only one operation at a time."
        fi;;
  "-h" | "--help")
        syntax;;
  *)    syntax "wrong argument: $1";;
  esac
  shift 1
done

# check arguments
if [[ -z $instName ]]; then
   syntax "Instance name not specified. Specify the instance name."
fi

if [[ -z $op ]]; then
   syntax "Operation not specified. Specify the operation to be executed."
fi
#echo "WRAPPER-DEBUG: instance-name=$instName, operation=$op"


# check if logPath exists and if not, then create it
if [[ ! -d $logPath ]]; then
   mkdir -p $logPath
   rc=$?
   if (( rc > 0 )); then
     echo "WRAPPER ERRROR: Unable to create path for log files at $logPath."
     exit 8
   fi
fi   

# perform operation
logF="$logPath/$instName-$op.log"
echo "WRAPPER DEBUG: writing to logfile $logF"
echo -e "WRAPPER INFO: $(date) starting operation $op ($age) for instance $instName" >> $logF 2>&1
rc=0
case "$op" in
create)
  su - $instName -c "$isnapPath/isnap-create.sh -r" >> $logF 2>&1
  rc=$?
  if (( rc > 0 )); then
    rc=8
  fi;;

delete) 
  su - $instName -c "$isnapPath/isnap-del.sh -g $age" >> $logF 2>&1
  rc=$?
  if (( rc > 0 )); then
    rc=8
  fi;;

list)
  su - $instName -c "$isnapPath/isnap-list.sh" >> $logF 2>&1
  rc=$?
  if (( rc > 0 )); then
    rc=8
  fi;;

fscap)
  su - $instName -c "$isnapPath/isnap-fscap.sh" >> $logF 2>&1
  rc=$?
  if (( rc > 0 )); then
    rc=8
  fi;;

*) 
  echo "WRAPPER ERROR: Operation $op unknown. Specify the proper operation."
  echo "WRAPPER ERROR: Operation $op unknown. Specify the proper operation." >> $logF 2>&1
  echo -e "\nSYNTAX:   $0 create | delete age | list | fscap\n"
  rc=8;;
esac

if (( rc == 0 )); then
  echo -e "WRAPPER INFO: $(date) operation $op for instance $instName finished successfull\n" >> $logF 2>&1
  echo -e "WRAPPER INFO: $(date) operation $op for instance $instName finished successfull\n"
else
  echo -e "WRAPPER ERROR: $(date) operation $op for instance $instName failed (return code: $rc)\n" >> $logF 2>&1
  echo -e "WRAPPER ERROR: $(date) operation $op for instance $instName failed (return code: $rc)\n"
fi

exit $rc