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
# Name: isnapfunctions.sh
# Desc: Common functions and parameters for isnap scripts
#
# Dependencies:
# This scripts is sourced by all other scripts and provides common functions and parameters
#
#********************************************************************************

# History
#----------
# 04/28/26 first implemenation: parse config with new configuration file name, pass through apiCredential_Arr from environment - version 1.0


#==================================================================
# Global variables and defaults
#==================================================================

# initialize the config parameters
dbName=""
dirsToSnap=""
snapPrefix=""
snapRet=0
serverInstDir="$HOME"
sudoCmd=""
apiServer=""
apiPort=""
autoRestore=""

# if apiCredential_Arr is set as environment variable, then initialize the array apiCredential_Arr with the elements provided
# environment variable apiCredential_Arr is set as string not as array, e.g. apiCredential_Arr="flash1-cred flash2-cred"
# environment variable overrules the config parameter apiCredential
if [[ -z $apiCredential ]]; then
  apiCredential=""
fi

# name of the config file
configFile="$basePath/isnapconfig.json"

# defaults configuration parameter
defDbName="TSMDB1"
defServerInstDir="$HOME"
defSudoCmd="/usr/bin/sudo"
defSnapRet=0
defAutoRestore="false"
defApiPort="443"

# path to jq is required
jqPath=/usr/bin/jq

# determine operating system
os=$(uname -s)

# determine the name of the instance user for reference
if [[ -z $instUser ]]; then
  instUser=$(id -un)
fi
#### temp setting ######
#instUser=tsminst1
########################

# version of the global functions
globFuncVer=1.0


#==================================================================
# Global functions
#==================================================================

# -----------------------------------------------------------------
# function parse_config to parse the config file
#
# Requires $configFile
# sets the instance specific parameters: dbName, snapPrefix, dirsToSnap, snapRet, apiServer, apiPort, apiCredential
#
# Processing:
# - assign config parameters from config file to global variables
# - if parameter apiCredential is provided as environment variable, then use the env variable
#
# -----------------------------------------------------------------
function parse_config()
{ 

  # check if jq is installed
  if [[ ! -a $jqPath ]]; then
    echo "ERROR: Tool $jqPath is not installed. Please install the tool and specify the path in the script."
    return 1 
  fi      

  # check if configFile exists 
  if [[ ! -a $configFile ]]; then
    echo "ERROR: config file $configFile not found. Create a configuration file and place it in $basePath"
    return 1
  fi

  # check if the format of the config file is ok
  jq -e . $configFile 1>/dev/null 2>&1
  if [[ $? > 0 ]]; then
    echo "ERROR: invalid json syntax in config file $configFile, error message:"
    jq -e . $configFile 1>>/dev/null
    return 1
  fi

  item=""
  item=$(jq ".[] | select(.instName==\"$instUser\").instName" $configFile)
  if [[ ! -z $item || $item == "null" ]]; then
    dbName=$(jq ".[] | select(.instName==\"$instUser\").dbName" $configFile | sed 's/\"//g')
    snapPrefix=$(jq ".[] | select(.instName==\"$instUser\").snapPrefix" $configFile | sed 's/\"//g')
    snapRet=$(jq ".[] | select(.instName==\"$instUser\").snapRetention" $configFile | sed 's/\"//g')
    serverInstDir=$(jq ".[] | select(.instName==\"$instUser\").serverInstDir" $configFile | sed 's/\"//g')
    sudoCmd=$(jq ".[] | select(.instName==\"$instUser\").sudoCommand" $configFile | sed 's/\"//g')
    apiServer=$(jq ".[] | select(.instName==\"$instUser\").apiServerIP" $configFile | sed 's/\"//g')
    apiPort=$(jq ".[] | select(.instName==\"$instUser\").apiServerPort" $configFile | sed 's/\"//g')
    autoRestore=$(jq ".[] | select(.instName==\"$instUser\").autoRestore" $configFile | sed 's/\"//g')
    dirsToSnap=$(jq ".[] | select(.instName==\"$instUser\").dirsToSnap | @csv" $configFile | sed 's/\\//g' | sed 's/"//g')
   
    # obtain apiCredential which is encoded in base64
    # if apiCredential is not set via environment variable, then get it from the config file
    if [[ -z $apiCredential ]]; then
        apiCredential=$(jq ".[] | select(.instName==\"$instUser\").apiCredential" $configFile | sed 's/\"//g')
    else
      echo "  DEBUG: parse_config - Using API credentials from environment variable."
    fi
#    if [[ -z $apiCredential || $apiCredential ==  "null" ]]; then
#      echo "ERROR: parse_config - parameter apiCredential is not defined in configuration file nor as environment variable."
#      return 1
#    fi
  else
     echo "ERROR: no configuration found for user $instUser in config file $configFile"
     return 1
  fi
  
  return 0
}

# -----------------------------------------------------------------
# function check_config checks the parsed configuration parameters
# and sets defaults when available
#
# Requires: configuration parameter that where parsed
#           default values defined in this file
#
# Output: Return code
#   0: Ok
#   2: Error
# -----------------------------------------------------------------
function check_config()
{
    frc=0
 
    ### apply defaults where possible
    if [[ -z $dbName || $dbName == "null" ]]; then
        dbName=$defDbName
    fi
    if [[ -z $serverInstDir || $serverInstDir == "null" ]]; then
        serverInstDir=$defServerInstDir
    fi
    if [[ -z $sudoCmd || $sudoCmd == "null" ]]; then
        sudoCmd=$defSudoCmd
    fi
    if [[ -z $snapRet || $snapRet == "null" ]]; then
        snapRet=$defSnapRet
      fi
    if [[ -z $autoRestore || $autoRestore == "null" ]]; then
        autoRestore=$defAutoRestore
    fi
    if [[ -z $autoRestore || $autoRestore == "null" ]]; then
        autoRestore=$defAutoRestore
    fi
    if [[ -z $apiPort || $apiPort == "null" ]]; then
        apiPort=$defApiPort
    fi

    ### check parameters where necessary
    # If serverInstDir does not exist then present a warning and do not exit
    # If serverInstDir does not exist on restore, it might be unmounted. We must still continue and check when we need it.
    if [[ ! -d $serverInstDir ]]; then 
        echo "WARNING: Server instance directory $serverInstDir for instance $instUser does not exist."
        echo "         This may be normal upon restore, if the file system is not available."
        echo "         Otherwise, specify a valid directory for parameter serverInstDir in config file $configFile or mount the file system."
    fi
  
    # check if vgsToSnap are set for all entries
    if [[ -z $dirsToSnap || $dirsToSnap == "null" ]]; then
      echo "ERROR: parameter dirsToSnap is not set forthe instance $instUser in the config file $configFile."
      frc=2
    fi

    # check if SGC prefix is defined
    if [[ -z $snapPrefix || $snapPrefix == "null" ]]; then 
      echo "ERROR: Parameter snapPrefix is not set for instance $instUser in the config file $configFile."
      frc=2
    fi

    # Check API server, port may have a default
    if [[ ! (-z $apiServer || $apiServer == "null") ]]; then
      apiServer=$apiServer:$apiPort
      if [[ ! (-z $apiCredential || $apiCredential ==  "null") ]]; then
        rc=0
        rc=$(curl -k -X GET --header 'Accept: application/json' --header "Authorization: Basic $apiCredential" "https://$apiServer/scalemgmt/v2/access" 2>/dev/null| jq ". | .status.code" | sed 's/\"//g')
        if (( rc != 200 )); then
          echo "ERROR: REST API connection to $apiServer failed. Check REST API configuration in configuration file"
          frc=2
        fi
      else
        echo "ERROR: REST API credentials not specified for instance $instUser in configuration file $configFile or as environment variable."
        frc=2
      fi
    else
      apiServer=""
    fi

    if (( frc > 0 )); then 
      echo -e "=============================================================================\n"
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
  echo -e "\n-----------------------------------------------------------------"
  echo "Information for instance user: $instUser"
  echo "-----------------------------------------------------------------"
  echo "  dbName: $dbName"
  echo "  dirsToSnap: $dirsToSnap"
  echo "  snapPrefix: $snapPrefix"
  echo "  snapRetention: $snapRet"
  echo "  serverInstDir: $serverInstDir"
  echo "  sudoCmd: $sudoCmd"
  echo "  apiServer: $apiServer"
  echo "  apiPort: $apiPort"
  echo "  apiCredential: $apiCredential"
  echo "  autoRestore: $autoRestore"

  return 0
}
