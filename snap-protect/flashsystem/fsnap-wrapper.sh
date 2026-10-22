#!/bin/bash
#********************************************************************************
# IBM Storage Protect
#
# (C) Copyright International Business Machines Corp. 2025
#
#--------------------------------------------------------------------------------
# ATTENTION: This is a beta-version and must not be used for production. Any 
# failure or damage on production system is under your own liabilit.
#--------------------------------------------------------------------------------
# 
# Name: fsnap-wrapper.sh
# Desc: Wraps fsnap-scripts and can be executed by Storage Protect client schedule
#
# Dependencies:
# - this scripts must run on the host where the instance is running
# - fsnap-scripts must exist in $fsnapPath
# - must be executed by privileged user that can invoke the $instUser via su
#
# Usage:
# fsnap-wrapper.sh -i inst-name [-c | -d age | -l | -f ]
# -i inst-name: name of the instance to be processed
# -c: create snapshot - invokes fsnap-create.sh -r
# -d age: delete snapshots older than age - invokes fsnap-del.sh -g age
# -l: list snapshots - invokes fsnap-list.sh
# -f: list fileset and snapshot capacities - invokes fsnap-fscap.sh
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
# 05/08/25 first implementation based on isnap-wrapper.sh
# 05/27/25 call fsnap-delete.sh
# 06/12/25 remove hard-coding of /usr/local/bin
# 04/13/26 remove duplicate function usage(), check if instance user exists on system - version 1.0
# 04/29/26 pass through apiCredential_Arr from environment, source instance user profile for create operation 
# 08/13/26 add structured logging functions (log_info, log_warn, log_debug, log_error) - version 1.4 (Dominic)

# Global variables
#------------------

# path of the fsnap-scripts
### determine directory where the script is started from
fsnapPath=$(dirname $0)
if [[ $fsnapPath = "." ]]; then
  fsnapPath=$PWD
fi

#log file path
logPath="/var/log/fsnap"

# operation system type
os=$(uname -s)

# version
ver=1.0


#------------------------------------------------------------------
# Print usage
#------------------------------------------------------------------
function usage()
{
     if [[ ! -z $1 ]]; then
       printf '%s [ERROR  ] WRAPPER: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2
     fi

     echo "Usage:"
     echo "fsnap-wrapper.sh -i inst-name [-c | -d age | -l | -f ]"
     echo "  -i inst-name: name of the instance to be processed (required)"
     echo
     echo "  Even one of the following operation arguments is required."
     echo "  -c:     create snapshot - invokes fsnap-create.sh -r"
     echo "  -d age: delete snapshots older than age - invokes fsnap-del.sh -g age"
     echo "  -l:     list snapshots - invokes fsnap-list.sh"
     echo "  -f:     list fileset and snapshot capacities - invokes fsnap-fscap.sh"
     echo
     echo "  To get help"
     echo "  -h | --help:   Show this help message (optional)."
     echo

     exit 8
}



#---------------------------------------
# Main
#---------------------------------------

# present banner — use printf directly since fsnapfunctions is not sourced in the wrapper
printf '%s [INFO   ] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(date) program $0 version $ver started on platform $os" >&2

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
		    usage "Instance user name is not specified."
		  else
		    instName=$1
		  fi;;

  "-c") if [[ -z $op ]]; then 
          op=create
        else
          usage "Multiple operations specified (create and $op). Specify only one operation at a time."
        fi;;

  "-l") if [[ -z $op ]]; then 
          op=list
        else
          usage "Multiple operations specified (list and $op). Specify only one operation at a time."
        fi;;

  "-f") if [[ -z $op ]]; then 
          op=fscap
        else
          usage "Multiple operations specified (fscap and $op). Specify only one operation at a time."
        fi;;

  "-d") if [[ -z $op ]]; then
          op=delete
          shift 1
          if [[ -z $1 ]]; then 
		        usage "Snapshot age is not specified."
		      else
		        age=$1
		      fi 
        else
          usage "Multiple operations specified (delete and $op). Specify only one operation at a time."
        fi;;
  "-h" | "--help")
        usage;;
  *)    usage "wrong argument: $1";;
  esac
  shift 1
done

# check if instName is given and that it exists
if [[ -z $instName ]]; then
   usage "Instance name not specified. Specify the instance name."
else
  instPath=$(cat /etc/passwd | grep -w $instName | cut -d: -f 6)
  if [[ -z $instPath ]]; then
     printf '%s [ERROR  ] WRAPPER: unable to determine instance home path. Make sure the instance user %s is configured on the system.\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$instName" >&2
     exit 8
  fi
fi

if [[ -z $op ]]; then
   usage "Operation not specified. Specify the operation to be executed."
fi
#echo "WRAPPER-DEBUG: instance-name=$instName, operation=$op"


# check if logPath exists and if not, then create it
if [[ ! -d $logPath ]]; then
   mkdir -p $logPath
   rc=$?
   if (( rc > 0 )); then
     printf '%s [ERROR  ] WRAPPER: Unable to create path for log files at %s.\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$logPath" >&2
     exit 8
   fi
fi

# if apiCredential_Arr is provided as environment variable, then pass it through
if [[ ! -z $apiCredential_Arr ]]; then
  printf '%s [INFO   ] WRAPPER: passing apiCredential_Arr from environment.\n' "$(date '+%Y-%m-%d %H:%M:%S')" >&2
fi

# perform operation
logF="$logPath/$instName-$op.log"
echo "-----------------------------------------------------------------------------" >> $logF 2>&1
printf '%s [DEBUG  ] WRAPPER: writing to logfile %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$logF" >&2
printf '%s [INFO   ] WRAPPER: %s starting operation %s (%s) for instance %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(date)" "$op" "$age" "$instName" >> $logF 2>&1
rc=0
case "$op" in
create)
  # for interacting with db2 we must source the .profile for the instance user (AIX)
  su - $instName -c ". $instPath/.profile; apiCredential_Arr=$apiCredential_Arr $fsnapPath/fsnap-create.sh -r" >> $logF 2>&1
  rc=$?
  if (( rc > 0 )); then
    rc=8
  fi;;

delete) 
  su - $instName -c "apiCredential_Arr=$apiCredential_Arr $fsnapPath/fsnap-delele.sh -g $age" >> $logF 2>&1
  rc=$?
  if (( rc > 0 )); then
    rc=8
  fi;;

list)
  su - $instName -c "apiCredential_Arr=$apiCredential_Arr $fsnapPath/fsnap-list.sh" >> $logF 2>&1
  rc=$?
  if (( rc > 0 )); then
    rc=8
  fi;;

fscap)
  su - $instName -c "apiCredential_Arr=$apiCredential_Arr $fsnapPath/fsnap-fscap.sh" >> $logF 2>&1
  rc=$?
  if (( rc > 0 )); then
    rc=8
  fi;;

*)
  printf '%s [ERROR  ] WRAPPER: Operation %s unknown. Specify the proper operation.\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$op" | tee -a "$logF" >&2
  echo -e "\nusage:   $0 create | delete age | list | fscap\n"
  rc=8;;
esac

if (( rc == 0 )); then
  printf '%s [INFO   ] WRAPPER: %s operation %s for instance %s finished successfully\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(date)" "$op" "$instName" | tee -a "$logF" >&2
else
  printf '%s [ERROR  ] WRAPPER: %s operation %s for instance %s failed (return code: %s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(date)" "$op" "$instName" "$rc" | tee -a "$logF" >&2
fi

exit $rc