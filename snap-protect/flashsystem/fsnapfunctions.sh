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
# Name: fsnapfunctions.sh
# Desc: Common functions and parameters
#
# Dependencies:
# This scripts is sourced by all other scripts and provides common functions and parameters
#
#********************************************************************************

# History
#----------
# 05/22/25 first implemenation
# 06/12/25 use $basePath for config file location
# 06/13/25 add global parameter multiSysSleep which controls sleeptime between requests to different systems
# 06/13/25 do not exit, if serverInstDir does not exist, present a warning instead.
# 08/01/25 add function check_apivolumecopy() used by fsnap-create and fsnap-restore
# 09/04/25 new config file structure, implement pure jq parsing in parse_config
# 10/08/25 add $checkSeverity message to check_apivolumecopy() function
# 02/10/26 determine number of entries for $instUser in $configFile in function parse_config
# 02/12/26 add config parameter consistentSnap, revert previous change from 02/10/26
# 04/12/26 replace apiUser and apiPw by apiCredentials (base64 encoded user:password)
# 04/13/26 rename config parameter mapping to vgfsMapping, remove config parameters vgsToSnap, fSystems and assign values from vgfsMapping - version 1.1
# 04/24/26 allow apiCredential to be passed as environment variable apiCredential_Arr="cred1 cred2 ..."; initialize configuration parameter arrays here instead of all scripts - version 1.2
# 06/09/26 set config parameter to consistentSnap=true, regardless of the setting in config file - version 1.3
# 08/13/26 add structured logging functions (log_info, log_warn, log_debug, log_error) - version 1.4 (Dominic)
# 08/14/26 add log_flashsystem_time() to log the local time of each FlashSystem - version 1.5 (Dominic)
# 08/31/26 update version - version 1.6


#==================================================================
# Logging
#==================================================================

# Log levels: 0=DEBUG  1=INFO  2=WARNING  3=ERROR
# Set LOG_LEVEL before sourcing this file, or export it from the environment.
# Default is INFO (1).  Set to 0 to enable DEBUG output.
: "${LOG_LEVEL:=0}"

# All log messages are written to stderr so that scripts that capture stdout
# (e.g. fsnap-fscap.sh parsing fsnap-list.sh output) are not polluted.
function _log()
{
  local level="$1"
  local label="$2"
  local min_level="$3"
  shift 3
  if (( LOG_LEVEL <= min_level )); then
    printf '%s [%-7s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$label" "$*" >&2
  fi
}

function log_debug() { _log DEBUG   DEBUG   0 "$@"; }
function log_info()  { _log INFO    INFO    1 "$@"; }
function log_warn()  { _log WARNING WARNING 2 "$@"; }
function log_error() { _log ERROR   ERROR   3 "$@"; }

# -----------------------------------------------------------------
# db2 stdout logger — redirect db2 output through the log engine
# without forking a subshell (which would destroy the db2 connection).
#
# A named pipe (fifo) is opened once; a background reader process
# forwards every line from the pipe to log_info.  The caller then
# redirects the db2 command's stdout+stderr to the fifo so that db2
# itself runs in the main shell (connection state is preserved) while
# its output is still formatted by the log engine.
#
# Usage in fsnap-create.sh:
#
#   db2_log_start          # open pipe + start background reader
#   db2 connect to TSMDB1  > "$_DB2_FIFO" 2>&1; rc=$?
#   db2 set write suspend  > "$_DB2_FIFO" 2>&1; rc=$?
#   ...
#   db2_log_stop           # close pipe + stop background reader
#
# The exit code of each bare db2 call is available in $? immediately
# after the redirection, exactly as before.
# -----------------------------------------------------------------
_DB2_FIFO=""
_DB2_LOG_PID=""

function db2_log_start()
{
  _DB2_FIFO=$(mktemp -u /tmp/.db2log.XXXXXX)
  mkfifo "$_DB2_FIFO"
  # background reader: tag every non-empty line at INFO level
  while IFS= read -r _db2_line; do
    [[ -n "$_db2_line" ]] && log_info " IBM Db2: $_db2_line"
  done < "$_DB2_FIFO" &
  _DB2_LOG_PID=$!
  # open the fifo for writing in the main shell so the reader does not
  # see EOF until db2_log_stop closes it
  exec 9>"$_DB2_FIFO"
}

function db2_log_stop()
{
  # close the write-end so the background reader sees EOF and exits
  exec 9>&-
  wait "$_DB2_LOG_PID" 2>/dev/null
  rm -f "$_DB2_FIFO"
  _DB2_FIFO=""
  _DB2_LOG_PID=""
}


#==================================================================
# Global variables and defaults
#==================================================================

# initialize the config parameter arrays 
# an instance can have multiple json elements in the config file, each json element is an array element of the according parameter array
dbName_Arr=()
vgsToSnap_Arr=()
snapPrefix_Arr=()
snapRet_Arr=()
serverInstDir_Arr=()
sudoCmd_Arr=()
apiServer_Arr=()
apiPort_Arr=()
fSystems_Arr=()
safeGuarded_Arr=()
autoRestore_Arr=()
consistentSnap_Arr=()
token_Arr=()

# if apiCredential_Arr is set as environment variable, then initialize the array apiCredential_Arr with the elements provided
# environment variable apiCredential_Arr is set as string not as array, e.g. apiCredential_Arr="flash1-cred flash2-cred"
# environment variable overrules the config parameter apiCredential
if [[ -z $apiCredential_Arr ]]; then
  apiCredential_Arr=()
else
  i=0
  for e in $apiCredential_Arr; do
    apiCredential_Arr[$i]=$e
    # echo "DEBUG: fsnapfunctions - apiCredential_Arr[$i]=${apiCredential_Arr[$i]}"
    (( i+=1 ))
  done
fi

# arrLen is set to the last index of the parameter arrays for the instance in parse_config, initialized with -1
arrLen=-1
# mapIndex is set to the last index mapping array of the instance in parse_config, initialized with -1
mapIndex=-1


# sleeptime between requests to multiple FlashSystems
multiSysSleep=0


# name of the config file
# configFile="/usr/local/bin/fsnapconfig.json"
configFile="$basePath/fsnapconfig.json"

# defaults configuration parameter
defDbName="TSMDB1"
defServerInstDir="$HOME"
defSudoCmd="/usr/bin/sudo"
defSnapRet=1
defSafeGuarded="true"
defAutoRestore="false"
defConsistentSnap="true"

# path to jq is required
jqPath=/usr/bin/jq

# determine operating system
os=$(uname -s)

# determine the name of the instance user for reference
instUser=$(id -un)
#### temp setting ######
#instUser=tsminst1
########################

# version of the global functions
globFuncVer=1.6


#==================================================================
# Global functions
#==================================================================

# -----------------------------------------------------------------
# function parse_config to parse the config file
#
# Requires $configFile
# sets the instance specific parameters: dbName, snapPrefix, vgsToSnap, fSystems, snapRet, apiServer, apiPort, apiCredential
#
# Processing:
# - assign config parameters from config file to global variables
# - parameter apiCredential is decoded and assigned to apiUser and apiPw
# - vgName and fSystems are parsed from vgfsMapping.vgName and vgfsMapping.fSystems and assigned to arrays vgsToSnap_Arr and fSystems_Arr 
#
# -----------------------------------------------------------------
function parse_config()
{
  numInst=-1
  
  # check if configFile exists and if json format is ok
  if [[ ! -a $configFile ]]; then
    log_error "config file $configFile not found. Please provide this file first."
    return 1
  fi
  jq -e . $configFile 1>/dev/null 2>&1
  if [[ $? > 0 ]]; then
    log_error "invalid json syntax in config file $configFile, error message:"
    jq -e . $configFile 1>>/dev/null
    return 1
  fi

  # determine total number of objects with instName in config file
  numInst=$(jq ".instances[] | .instName" $configFile | wc -l)
  # new code matching instUser
  # numInst=$(jq ".instances[] | select(.instName==\"$instUser\").instName" $configFile | wc -l)
  if (( numInst == 0 )); then
    numInst=-1
  else
    (( numInst -= 1 ))
  fi
  # echo "DEBUG: Number of entries in config file: $((numInst+1))"

  # iterate through all instance objects to find the once matchin instUser
  j=0
  while (( j <= numInst ));
  do
    item=""
    item=$(jq ".instances[$j] | select(.instName==\"$instUser\").instName" $configFile)
    if [[ ! -z $item || $item == "null" ]]; then
      (( arrLen += 1 ))
      dbName_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").dbName" $configFile | sed 's/\"//g')
      snapPrefix_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").snapPrefix" $configFile | sed 's/\"//g')
      snapRet_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").snapRetention" $configFile | sed 's/\"//g')
      serverInstDir_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").serverInstDir" $configFile | sed 's/\"//g')
      sudoCmd_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").sudoCommand" $configFile | sed 's/\"//g')
      apiServer_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").apiServerIP" $configFile | sed 's/\"//g')
      apiPort_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").apiServerPort" $configFile | sed 's/\"//g')

      # obtain apiCredential_arr and assign it to apiUser_arr and apiPw_arr, each element in apiCredential is encoded in base64
      # if apiCredential_Arr is not set via environment variable, then get it from the config file
      if [[ -z ${apiCredential_Arr[$arrLen]} ]]; then
        apiCredential_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").apiCredential" $configFile | sed 's/\"//g')
      else
        log_debug "parse_config - Using API credentials from environment variable."
      fi
      if [[ ! ( -z ${apiCredential_Arr[$arrLen]} || ${apiCredential_Arr[$arrLen]} ==  "null" ) ]]; then
        apiUser_Arr[$arrLen]=$(echo ${apiCredential_Arr[$arrLen]} | base64 -d 2>>/dev/null | cut -d: -f 1 -s)
        apiPw_Arr[$arrLen]=$(echo ${apiCredential_Arr[$arrLen]}  | base64 -d 2>>/dev/null | cut -d: -f 2 -s)
      else
        (( entryNum = arrLen +1 ))
        log_warn "parse_config - parameter apiCredential is not defined for the $entryNum. entry in configuration file nor as environment variable."
      fi
      
      safeGuarded_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").safeGuarded" $configFile | sed 's/\"//g')
      autoRestore_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").autoRestore" $configFile | sed 's/\"//g')
      consistentSnap_Arr[$arrLen]=$(jq ".instances[$j] | select(.instName==\"$instUser\").consistentSnap" $configFile | sed 's/\"//g')

      # get the vgfsMapping
      mapLen=$(jq ".instances[$j] | select(.instName==\"$instUser\").vgfsMapping[].vgName" $configFile | wc -l)
      if (( mapLen == 0 )); then
        (( entryNum = arrLen +1 ))
        log_warn "parse_config - parameter vgfsMapping is not defined for the $entryNum. entry in configuration file."
        mapLen=-1
      else
        (( mapLen -= 1 ))
      fi
      k=0
      while (( k <= mapLen ));
      do
        (( mapIndex += 1 ))
        vgname_arr[$mapIndex]=$(jq ".instances[$j] | select(.instName==\"$instUser\").vgfsMapping[$k].vgName" $configFile | sed 's/\"//g')
        vgfs_arr[$mapIndex]=$(jq ".instances[$j] | select(.instName==\"$instUser\").vgfsMapping[$k].fSystems | @csv" $configFile | sed 's/\\//g' | sed 's/"//g')
        # assign the legacy parameter vgsToSnap and fSystems
        vgsToSnap_Arr[$arrLen]="${vgsToSnap_Arr[$arrLen]} ${vgname_arr[$mapIndex]}"
        fSystems_Arr[$arrLen]="${fSystems_Arr[$arrLen]} ${vgfs_arr[$mapIndex]}"
        (( k += 1 ))
      done
    fi
    (( j += 1 ))
  done 

  # echo "DEBUG: mapIndex=$mapIndex"
  return 0
}

# -----------------------------------------------------------------
# function check_config checks the parsed configuration parameters
# and sets defaults when available
#
# Requires: configuration parameter arrays that where parsed
#           default values defined in this file
#
# Output: Return code
#   0: Ok
#   2: Error
# -----------------------------------------------------------------
function check_config()
{
    frc=0
    j=0
    while (( j <= arrLen )); do
  
      ### apply defaults where possible
      if [[ -z ${dbName_Arr[$j]} || ${dbName_Arr[$j]} == "null" ]]; then
        dbName_Arr[$j]=$defDbName
      fi
      if [[ -z ${serverInstDir_Arr[$j]} || ${serverInstDir_Arr[$j]} == "null" ]]; then
        serverInstDir_Arr[$j]=$defServerInstDir
      fi
      if [[ -z ${sudoCmd_Arr[$j]} || ${sudoCmd_Arr[$j]} == "null" ]]; then
        sudoCmd_Arr[$j]=$defSudoCmd
      fi
      if [[ -z ${snapRet_Arr[$j]} || ${snapRet_Arr[$j]} == "null" ]]; then
        snapRet_Arr[$j]=$defSnapRet
      fi
      if [[ -z ${safeGuarded_Arr[$j]} || ${safeGuarded_Arr[$j]} == "null" ]]; then
        safeGuarded_Arr[$j]=$defSafeGuarded
      fi
      if [[ -z ${autoRestore_Arr[$j]} || ${autoRestore_Arr[$j]} == "null" ]]; then
        autoRestore_Arr[$j]=$defAutoRestore
      fi
      if [[ -z ${consistentSnap_Arr[$j]} || ${consistentSnap_Arr[$j]}  == "null" ]]; then
        consistentSnap_Arr[$j]=$defConsistentSnap
      # set consistentSnap=true because this is required with Storage Protect
      else
        if [[ ! ${consistentSnap_Arr[$j]} == "true" ]]; then
          log_warn "Parameter consistentSnap is set to ${consistentSnap_Arr[$j]}. This parameter is not supported and is ignored."
          consistentSnap_Arr[$j]="true"
        fi
      fi

      ### check parameters where necessary
      # use k as index + 1 for better messages
      (( k = j +1 ))

      # If serverInstDir does not exist then present a warning and do not exit
      # If serverInstDir does not exist on restore, it might be unmounted. We must still continue and check when we need it.
      if [[ ! -d ${serverInstDir_Arr[$j]} ]]; then
        log_warn "Server instance directory ${serverInstDir_Arr[$j]} defined for the $k. entry for instance $instUser does not exist."
        log_warn "  This may be normal upon restore, if the file system is not available."
        log_warn "  Otherwise, specify a valid directory for parameter serverInstDir in config file $configFile or mount the file system."
      fi

      
      # check if vgsToSnap are set for all entries
      if [[ -z ${vgsToSnap_Arr[$j]} || ${vgsToSnap_Arr[$j]} == "null" ]]; then
        log_error "parameter vgsToSnap is not set for the $k. entry of the instance $instUser in the config file $configFile."
        log_error "  Parameter vgsToSnap is derived from parameter vgfsMapping in the config file. Ensure parameter vgfsMapping is set."
        frc=2
      fi

      # check if file systems are set
      if [[ -z ${fSystems_Arr[$j]} || ${fSystems_Arr[$j]} == "null" ]]; then
        log_error "Parameter fileSystems is not set for the $k. entry of the instance $instUser in the config file $configFile."
        log_error "  Parameter fileSystems is derived from parameter vgfsMapping in the config file. Ensure parameter vgfsMapping is set."
        frc=2
      fi

      # check if SGC prefix is defined
      if [[ -z ${snapPrefix_Arr[$j]} || ${snapPrefix_Arr[$j]} == "null" ]]; then
        log_error "Parameter snapPrefix is not set for the $k. entry of the instance $instUser in the config file $configFile."
        frc=2
      fi

      # Check API server and port
      if [[ -z ${apiServer_Arr[$j]} || ${apiServer_Arr[$j]} == "null" || -z ${apiPort_Arr[$j]} || ${apiPort_Arr[$j]} == "null" ]]; then
        log_error "REST API server address and port not defined for the $k. entry of the instance $instUser in configuration file $configFile"
        frc=2
      fi

      # Check apiCredentials
      if [[ -z ${apiCredential_Arr[$j]} || ${apiCredential_Arr[$j]} ==  "null" ]]; then
        log_error "REST API credentials not specified for the $k. entry of the instance $instUser in configuration file $configFile"
        frc=2
      elif [[ -z ${apiUser_Arr[$j]} || -z ${apiPw_Arr[$j]} ]]; then
        log_error "REST API user and password are parsable from parameter apiCredentials in the $k. entry of the instance $instUser in configuration file $configFile."
        log_debug "Parameter apiCredential=${apiCredential_Arr[$j]}"
        frc=2
      fi

      # check if snapRetention is 0 and exit
      if [[ ${snapRet_Arr[$j]} = 0 ]]; then
        log_error "parameter snapRetention is set to 0 for the $k. entry of the instance $instUser in config file $configFile. Parameter snapRetention must be > 0."
        log_error "  To create snapshots without retention set parameter safeGuarded=false in the config file."
        frc=2
      fi
      
      (( j = j + 1 ))
    done

    # check that consistentSnap is set consistently
    j=0
    preVal=""
    while (( j <= arrLen )); do
      if (( j == 0 )); then
        preVal=${consistentSnap_Arr[$j]}
      else
        val=${consistentSnap_Arr[$j]}
        if [[ $preVal != $val ]]; then
          log_error "parameter consistentSnap is not set to the same value for all entries of the instance $instUser in config file $configFile."
          log_error "  Parameter consistentSnap must be set to the same value for all entries of an instance user."
          log_debug "$j. entry = $preVal; $((j+1)). entry = $val"
          frc=2
        else
          preVal=${consistentSnap_Arr[$j]}
        fi
      fi
      (( j += 1 ))
    done

    # check vgfsMapping
    # echo "DEBUG: mapIndex=$mapIndex"
    if (( mapIndex > -1 )); then
      k=0
      m=-1
      while (( k <= mapIndex ));
      do
        (( m += 1 ))
        fSys=${vgfs_arr[$m]}
        fsN=""
        for fsN in $(echo "$fSys" | sed 's/,/ /g');
        do
           # echo "DEBUG: checking file system $fsN"
           if [[ ! -d $fsN ]]; then
             log_warn "file system $fsN in vgfsMapping at index $m does not exist."
           fi
        done

        vgs=${vgname_arr[$m]}
        vg=""
        for vg in $(echo "$vgs" | sed 's/,/ /g');
        do  
            # echo "DEBUG: vg=\"$vg\""
            if [[ -z $vg || $vg == " " ]]; then
              # alternative check the flashsystem if the volume group exists.
              log_warn "volume group name $vg in vgfsMapping at index $m is not specified."
            fi
        done
        (( k += 1 ))
      done
    fi  

    # check if jq is installed
    if [[ ! -a $jqPath ]]; then
      log_error "Tool $jqPath is not installed. Please install the tool and specify the path in the script."
      frc=2
    fi

    if (( frc > 0 )); then
      log_error "============================================================================="
      return $frc
    else
      return 0
    fi
}


# -----------------------------------------------------------------
# function print_config prints configuration for all elements
#
# Requires: configuration parameter arrays that where parsed, arrLen
#
# Output: Return code
#   0: Ok
#   2: Error
# -----------------------------------------------------------------
function print_config()
{
  j=0
  while (( j <= arrLen ));
  do
    echo -e "\n-----------------------------------------------------------------"
    echo "Information for Array index $j of instance user: $instUser"
    echo "-----------------------------------------------------------------"
    echo "  dbName: ${dbName_Arr[$j]}"
    echo "  vgsToSnap: ${vgsToSnap_Arr[$j]}"
    echo "  fSystems: ${fSystems_Arr[$j]}"
    echo "  snapPrefix: ${snapPrefix_Arr[$j]}"
    echo "  snapRet: ${snapRet_Arr[$j]}"
    echo "  serverInstDir: ${serverInstDir_Arr[$j]}"
    echo "  sudoCmd: ${sudoCmd_Arr[$j]}"
    echo "  apiServer: ${apiServer_Arr[$j]}"
    echo "  apiPort: ${apiPort_Arr[$j]}"
    echo "  apiCredential: ${apiCredential_Arr[$j]}"
    echo "  safeGuarded: ${safeGuarded_Arr[$j]}"
    echo "  autoRestore: ${autoRestore_Arr[$j]}"
    echo "  consistentSnap: ${consistentSnap_Arr[$j]}"
    echo "  token: ${token_Arr[$j]}"
    (( j = j + 1 ))
  done

  j=0
   echo -e "\n----------------------------------------------------------------"
  echo "All vg-fs vgfsMapping for instance user $instUser:"
  while (( j <= mapIndex ));
  do
    echo "    $j: ${vgname_arr[$j]} | ${vgfs_arr[$j]}"
    (( j += 1 ))
  done

  echo "-----------------------------------------------------------------"

  return 0
}

# -----------------------------------------------------------------
# function get_apitoken to perform authentication and get the token
#
# Requires $configFile
#
# Return 
# 0: Ok
# 1: error
# -----------------------------------------------------------------
function get_apitoken()
{
  ### get API token
  log_info "Obtain API authentication token (via REST API) for server $apiServer, user $apiUser"
  TOKEN=$(curl -k -X POST --header 'Accept: application/json' --header "X-Auth-Username:  $apiUser" --header "X-Auth-Password:  $apiPw" "https://$apiServer/rest/v1/auth" 2>/dev/null | grep "token")
  rc=$?
  if [[ ! $rc = 0 || -z $TOKEN ]]; then
    log_error "Obtaining token for REST API user $apiUser from Flashsystem at $apiServer (rc=$rc)"
    return 1
  else
    TOKEN=$(echo $TOKEN | cut -d':' -f2 -s | sed 's/"//g' | sed 's/{//g' | sed 's/}//g' | awk '{$1=$1};1')
  fi 
  

  return 0
}


# -----------------------------------------------------------------
# function log_flashsystem_time logs the time zone and a derived local time of a FlashSystem
#
# The FlashSystem REST API has no dedicated time endpoint.  The time_zone field
# from POST /rest/v1/lssystem (e.g. "522 UTC" or "200 Asia/Calcutta") is the
# authoritative source for the system's configured timezone.  The current wall-
# clock time is then rendered in that timezone using the local 'date' command.
#
# Requires
#   $apiServer: host:port of the FlashSystem REST API
#   $TOKEN:     valid authentication token
#
# Output: INFO log line with the FlashSystem timezone and derived local time; no return value.
# -----------------------------------------------------------------
function log_flashsystem_time()
{
  local tzRaw tzName localTime
  # lssystem returns a flat key-value JSON object; extract the time_zone field.
  # The value format is "<numeric_id> <tz_name>", e.g. "522 UTC" or "200 Asia/Calcutta".
  tzRaw=$(curl -k -X POST --url "https://$apiServer/rest/v1/lssystem" \
    --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
    2>/dev/null | jq -r '.time_zone // empty' 2>/dev/null)
  if [[ -z $tzRaw ]]; then
    log_warn "Unable to retrieve time zone from FlashSystem $apiServer (lssystem)"
    return
  fi
  # Strip the leading numeric ID to get just the tz name (e.g. "UTC", "Asia/Calcutta")
  tzName=$(echo "$tzRaw" | awk '{print $2}')
  if [[ -z $tzName ]]; then
    tzName=$tzRaw
  fi
  # Render current time in the FlashSystem's configured timezone
  localTime=$(TZ="$tzName" date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)
  if [[ -z $localTime ]]; then
    # Fallback: tzName not recognised by the local OS, just report the raw value
    log_info "FlashSystem $apiServer time zone: $tzRaw (unable to render local time)"
  else
    log_info "FlashSystem $apiServer local time: $localTime (time zone: $tzRaw)"
  fi
}


# -----------------------------------------------------------------
# function check_apivolumecopy checks for volume copies (hyperswap) for volume group $vgName
#
# Requires 
#   $vgName: volume group name
#   $checkSeverity: severity of the message when Hyperswap is enabled (WARNING for fsnap-create, ERROR for fsnap-restore)
#
# Processing: performs lsvdisk and checks for FC_id
#
# Output
#  0: success, no volume in HS
#  1: failure, volumes in HS
#
# -----------------------------------------------------------------
function check_apivolumecopy()
{
  # determine if volumes in volume group have HS or PBHA enabled
  # HS enabled if FC_id != ""
  # PBHA is enabled if FC_id != "" and replication_mode != ""
  sleep 1

  if [[ -z $checkSeverity ]]; then
     checkSeverity="DEBUG"
  fi
  item=""
  replMode=""
  frc=0
  
  while read -r line;
  do 
    # echo "  DEBUG: $line"
    item=$(echo $line | awk '{print $2}')
    if [[ ! -z $item ]]; then
      replMode=$(echo $line | awk '{print $3}')
      if [[ -z $replMode ]]; then
        if [[ $checkSeverity == "ERROR" ]]; then
          log_error "volume $(echo $line | awk '{print $1}') in volume group $vgName has HyperSwap enabled (FC_ID=$item)."
        else
          log_warn "volume $(echo $line | awk '{print $1}') in volume group $vgName has HyperSwap enabled (FC_ID=$item)."
        fi
        (( frc = frc + 1 ))
      else
        log_info "volume $(echo $line | awk '{print $1}') in volume group $vgName has PBHA enabled (repl-mode=$replMode)."
      fi
    fi
  done <<< $(curl -k -X 'POST' --url "https://$apiServer/rest/v1/lsvdisk" \
  --header 'Content-Type: application/json' --header "X-Auth-Token: $TOKEN" \
  --data-raw '{
    "filtervalue": "volume_group_name='$vgName'"
  }' 2>/dev/null  | jq -r ' .[] | [ .name, .FC_id,.replication_mode ] | @csv ' | sed 's/",/ /g' | sed 's/\"//g' )
  
  return $frc
}
