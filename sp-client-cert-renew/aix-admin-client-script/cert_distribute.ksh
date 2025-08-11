#!/bin/ksh

################################################################################
#       Copyright (C) 2025, International Business Machines Corp. (IBM)        #
#                          All rights reserved.                                #
#                                                                              #
#       Automated Distribution of SP Server Certificate to Clients             #
#                                                                              #
# This KSH script is the automation utility, responsible for distributing the  #
# Spectrum Protect server certificate to all BA and TDP clients. Eliminating   #
# the need of log-in on each client machine connected to server and manually   #
# adding the new certificate.                                                  #
#                                                                              #
# This utility consists of a KSH script file cert_distribute.sh and            #
# the corresponding configuration file cert_distribute.ini                     #
#                                                                              #
# Prerequisites:                                                               #
# 1. The ADMIN CLIENT (dsmadmc) running on AIX OS has been configured to be    #
#    able to connect to the Spectrum Protect server.                           #
# 2. The client scheduler has been configured for all BA and TDP clients.      #
#                                                                              #
# Procedure:                                                                   #
#                                                                              #
# 1. Generate a new certificate on Spectrum Protect server for distributing    #
#    to all clients using CREATE CERTIFICATE command.                          #
#                                                                              #
# 2. Copy the new generated certificate file from server to admin client.      #
#    You can skip this step if the server and the admin client are installed   #
#    on the same box.                                                          #
#                                                                              #
# 3. Place this script and cert_distribute.ini file in the same directory on   #
#    the admin client box, and modify the settings in cert_distribute.ini file #
#    as appropriate.                                                           #
#                                                                              #
# 4. Execute this script with argument "-action distribute" to START the job   #
#    of certificate distribution. A set of client schedules will be defined    #
#    against all BA and TDP clients.                                           #
#                                                                              #
# 5. Execute this script with argument "-action report" to monitor PROGRESS of #
#    the certificate distribution job. The distribute schedules will be run on #
#                                                                              #
#    This will generate the report with current status of distribution process #
#    of all BA and TDP clients.                                                #
#                                                                              #
#    Schedules defined in the previous step will be executed by the client     #
#    scheduler on a daily basis.                                               #
#                                                                              #
#    Leave those schedules to run for certain days.                            #
#                                                                              #
#    Report will show status as "Completed" for clients where certificate      #
#    is distributed successfully.                                              #
#                                                                              #
#    For clients with status other than "Completed", give them a chance to     #
#    retry by waiting for few more days, as the scheduler will execute those   #
#    schedules again.                                                          #
#                                                                              #
#    NOTE:                                                                     #
#    Some clients might still not be seen with status as "Completed" after     #
#    certain days of retries, either because of client scheduler not running   #
#    or some other issues. Those clients are considered failed. Please go th-  #
#    rough the manual steps to distribute certification for the failed clients.#
#                                                                              #
# 7. When the certificate distribute job is considered done,                   #
#    i.e. for all clients report file shows status as "Completed".             #
#    Execute this script with argument "-action cleanup" to remove all defined #
#    schedules from SP server.                                                 #
#                                                                              #
# POST-EXECUTION STEPS: i.e after successful distribution of the certificate   #
# on all BA and TDP Clients.                                                   #
#                                                                              #
# To set the distributed server certificate to default:                        #
# 1. Execute command :                                                         #
#                                                                              #
#    SET DEFAULTTLSCERT <certificate-label>                                    #
#                                                                              #
#    Here, in above command, "certificate-label" is the label mentioned in the #
#    configurations file cert_distribute.ini used while executing the script.  #
#                                                                              #
# 2. RESTART the Spectrum Protect server to get the new certificate in effect  #
#    for further communication with all BA and TDP clients.                    #
#                                                                              #
# SCRIPT USAGE Examples :                                                      #
# To start a certificate distribution job:                                     #
# ./cert_distribute.ksh -id dsmadmc-username                                   #
#                       -password dsmadmc-user-password                        #
#                       -action distribute                                     #
#                                                                              #
# To monitor status of existing certificate distribution job:                  #
# ./cert_distribute.ksh -id dsmadmc-username                                   #
#                       -password dsmadmc-user-password                        #
#                       -action report                                         #
#                                                                              #
# To cleanup existing certificate distribution job:                            #
# ./cert_distribute.ksh -id dsmadmc-username                                   #
#                       -password dsmadmc-user-password                        #
#                       -action cleanup                                        #
#                                                                              #
################################################################################

action=""
certificateLabel=""
certLines=""
certText=""
set -A certTextLines
configFile='cert_distribute.ini'
currentDir=""
set -A domainPlatformPairs
macroDEFINEcmdOutputFile='output_define_result.out'
macroDELETEcmdOutputFile='output_delete_result.out'
dsmadmcpath=''
dsmoptfile=''
id=""
isSection=0
LOGFILE="cert_distribute.log"
macroFile="output_define_schedules.macro"
set -A mandateKeys "action" "id" "password"
mandatoryCounter=0
newClientSideCertificateFile=''
newcertfile=''
nodeListFile="output_nodelist.out"
password=""
platformstrwin="WIN"
platformstrlnx="LNX"
platformstraix="AIX"
platformstrmac="MAC"
platformstrunx="UNX"
platformstrtbd="TBD"
reportPrefix='distribute.report.'
sectionName=''
sectionNamePattern='\[(.*)\]'
scheddelay=0
schedduration=0
set -A certTextParts
scheduleGSKit=''
scheduleWinCertPath=''
totalSchedulesCount=0
schedulePart00=''
schedulePart01=''
schedulePart02=''
schedulePart03=''
schedulePart04=''
scheduleprefix=''
startdelay=0
set -A supportedPlatforms "WIN" "UNX" "LNX" "AIX" "MAC"
tempCertificateFileName=""
set -A validActions "distribute" "report" "cleanup"
varValuePAttern='(.*)=(.*)'
windowsCertKDBPathFile="kdb_path.out"

updateOutputFilesPath(){
    # Making sure all output files are present in same directory.
    curDir=$1
    suffix='/'
    if [[ $curDir = *$suffix ]]; then
        configFile="${curDir}${configFile}"
        macroDEFINEcmdOutputFile="${curDir}${macroDEFINEcmdOutputFile}"
        macroDELETEcmdOutputFile="${curDir}${macroDELETEcmdOutputFile}"
        LOGFILE="${curDir}${LOGFILE}"
        macroFile="${curDir}${macroFile}"
        nodeListFile="${curDir}${nodeListFile}"
    else
        configFile="${curDir}/${configFile}"
        macroDEFINEcmdOutputFile="${curDir}/${macroDEFINEcmdOutputFile}"
        macroDELETEcmdOutputFile="${curDir}/${macroDELETEcmdOutputFile}"
        LOGFILE="${curDir}/${LOGFILE}"
        macroFile="${curDir}/${macroFile}"
        nodeListFile="${curDir}/${nodeListFile}"
    fi
}

getTimeStamp(){
    timeStamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo $timeStamp
}

LOG(){
    DATETIME=$(getTimeStamp)
    LOGTYPE=$1
    if [ "$LOGTYPE" = "INFO" ] || [ "$LOGTYPE" = "WARN" ]; then
        LOGTYPE="$LOGTYPE " # Adding space to align text entries in log file correctly.
    fi
    LOGMESSAGE=$2
    printf "%s : %s %s\n" "$DATETIME" "$LOGTYPE" "$LOGMESSAGE" >> $LOGFILE
}

updateVariables() {
    upVarRetCode=0
    case "$1" in  
        "dsmadmcpath")  
            dsmadmcpath=$2
            ;;  
        "dsmoptfile")  
            dsmoptfile=$2  
            ;;  
        "scheduleprefix")  
            scheduleprefix=$2  
            ;;  
        "newcertfile")  
            newcertfile=$2  
            ;;  
        "action")  
            action=$2  
            ;;  
        "id")  
            id=$2  
            ;;  
        "pa")  
            password=$2  
            ;;  
        "pass")  
            password=$2  
            ;;  
        "password")  
            password=$2  
            ;;  
        "startdelay")
            startdelay=$2
            ;;
        "scheddelay")
            scheddelay=$2
            ;;
        "schedduration")
            schedduration=$2
            ;;
        *)  
            upVarRetCode=1
            ;;  
    esac
    if [ "$upVarRetCode" -eq "1" ]; then
        echo ""
        echo "ERROR : Unknown parameter '$1'. Please confirm input arguments provided while executing this utility and set in configurations INI file are correct."
        LOG "ERROR" "Unknown parameter '$1'. Please confirm input arguments provided while executing this utility and set in configurations INI file are correct."
        echo ""
        printUsage
        exit 1
    fi
}

printVariables() {
    echo "dsmadmcpath    = $dsmadmcpath"
    echo "dsmoptfile     = $dsmoptfile"
    echo "newcertfile    = $newcertfile"
}

validateConfigPaths(){
    # Check if paths in INI file given are correct.
    if [ ! -d $dsmadmcpath ]; then
        echo ""
        echo "ERROR : Invalid PATH set to administrative client (dsmadmc) installation directory in configurations INI file. Please confirm if values set in configurations INI file are correct."
        LOG "ERROR" "ERROR : Invalid PATH set to administrative client (dsmadmc) installation directory in configurations INI file. Please confirm if values set in configurations INI file are correct."
        echo ""
        echo ">> PATHs from INI file are:"
        printVariables
        exit 1
    fi

    if [ ! -f $dsmoptfile ]; then
        echo ""
        echo "ERROR : Invalid PATH set to administrative client (dsmadmc) OPTIONS File in configurations INI file. Please confirm if values set in configurations INI file are correct."
        LOG "ERROR" "ERROR : Invalid PATH set to administrative client (dsmadmc) OPTIONS File in configurations INI file. Please confirm if values set in configurations INI file are correct."
        echo ""
        echo ">> PATHs from INI file are:"
        printVariables
        exit 1
    fi
}

printUsage(){
    echo "--------------------------------------------------------------------------------"
    echo "Utility to distribute Spectrum Protect Server Certificate to Clients."
    echo ""
    echo "./cert_distribute.ksh -id dsmadmc_user -password dsmadmc_user_password -action action_to_perform"
    echo ""
    echo "Mandetory paramenters to execute this script are."
    echo ""
    echo "    id       : Username for logging into DSMADMC console."
    echo ""
    echo "    password : Password for logging into DSMADMC console."
    echo ""
    echo "    action   :"
    echo "               distribute - To dispatch certificates to all nodes."
    echo "               report     - To monitor status of existing certification distribute job."
    echo "               cleanup    - To cleanup existing certification distribute job."
    echo "--------------------------------------------------------------------------------"
}

isValidAction(){
    if [ "$action" = "distribute" ] || [ "$action" = "report" ] || [ "$action" = "cleanup" ]; then
        echo 0
    else
        echo 1
    fi
}

checkArguments(){
    LOG "INFO" "checkArguments - Checking input arguments to script."

    if [ ! "$#" == "6" ]; then
        echo ""
        echo "ERROR : Incorrect number of arguments were provided while executing script."
        LOG "ERROR" "Incorrect number of arguments were provided while executing script."
        echo ""
        printUsage
        exit 1
    fi

    set -A variables
    set -A values

    varCounter=0
    valCounter=0

    for ARGUMENT in "$@"
    do
        if [[ $ARGUMENT = -* ]]; then
            variables[$varCounter]="$ARGUMENT"
            ((varCounter=$varCounter+1))
        else
            values[$valCounter]="$ARGUMENT"
            ((valCounter=$valCounter+1))
        fi
    done

    for n in 0 1 2
    do
        KEY=$(echo "${variables[n]}" | cut -f2 -d-)
        if [[ ${mandateKeys[@]} = *$KEY* ]]; then
            VALUE="${values[n]}"
            ((mandatoryCounter=$mandatoryCounter+1))
            updateVariables $KEY $VALUE
        fi
    done

    if [ "$mandatoryCounter" -lt "${#mandateKeys[*]}" ]; then
        echo ""
        echo "ERROR : One or more of the mandatory parameters were not provided.";
        LOG "ERROR" "Mandatory parameters were not provided while executing script."
        echo ""
        printUsage
        exit 1
    fi
    result=$(isValidAction)
    if [ "$result" == "1" ]; then
        echo ""
        echo "ERROR : Invalid value provided for parameter named action.";
        LOG "ERROR" "Invalid value provided for parameter named action."
        echo ""
        printUsage
        exit 1
    fi
}

readConfigFile(){
    LOG "INFO" "readConfigFile - Reading file $file."

    while read line; do
        
        if [[ $line = '#'* ]]; then
            continue
        fi

        if [[ $line = *=* ]]; then
            variable=$(echo "${line% = *}" | sed 's/ //g')
            value=$(echo "${line#* = }")
            updateVariables $variable $value
        fi

    done < $configFile
}

getNodesSQLStatement(){
    local sql="SELECT DISTINCT nd.domain_name, CASE WHEN Upper(Substr(nd.platform_name, 1, 3)) = 'WIN' OR Upper(Substr(nd.client_os_name, 1, 3)) = 'WIN' OR Upper(Substr(nd1.platform_name, 1, 3)) = 'WIN' OR Upper(Substr(nd1.client_os_name, 1, 3)) = 'WIN' OR Substr(fs.filespace_name, 1, 1) = '\' THEN 'WIN' WHEN Upper(Substr(nd.platform_name, 1, 3)) IN ( 'UNI', 'AIX' ) OR Upper(Substr(nd1.client_os_name, 1, 3)) = 'AIX' OR Upper(Substr(nd1.platform_name, 1, 3)) IN ( 'UNI', 'AIX' ) OR Upper(Substr(nd1.client_os_name, 1, 3)) = 'AIX' THEN 'AIX' WHEN Upper(Substr(nd.platform_name, 1, 3)) = 'MAC' OR Upper(Substr(nd.client_os_name, 1, 3)) = 'MAC' OR Upper(Substr(nd1.platform_name, 1, 3)) = 'MAC' OR Upper(Substr(nd1.client_os_name, 1, 3)) = 'MAC' THEN 'MAC' WHEN Upper(Substr(nd.platform_name, 1, 3)) IN ( 'LIN', 'LNX' ) OR Upper(Substr(nd.client_os_name, 1, 3)) IN ( 'LNX', 'SOL', 'HPX' ) OR Upper(Substr(nd1.platform_name, 1, 3)) IN ( 'LIN', 'LNX' ) OR Upper(Substr(nd1.client_os_name, 1, 3)) IN ( 'LNX', 'SOL', 'HPX' ) OR Substr(fs.filespace_name, 1, 1) = '/' THEN 'LNX' ELSE 'TBD' END AS platform, nd.node_name FROM nodes nd LEFT JOIN filespaces fs ON fs.node_name = nd.node_name LEFT JOIN nodes nd1 ON nd1.proxy_target LIKE '%' || nd.node_name || '%' WHERE nd.nodetype NOT IN ( 'NAS', 'OBJECTCLIENT' ) ORDER BY nd.domain_name, nd.node_name WITH UR FOR READ ONLY"
    echo "$sql"
}

getClientNodes(){
    LOG "INFO" "getClientNodes - Getting client nodes details."
    nodesSQLStatement=$(getNodesSQLStatement)

    cd $dsmadmcpath
    OUTPUT=$(./dsmadmc -id=$1 -password=$2 \
        -DATAONLY=yes -COMMAdelimited \
        -DISPLaymode=TABle -optfile=$dsmoptfile \
        -outfile=$3 \
        $nodesSQLStatement)
    exitCode=$?
    echo "$exitCode"
}

readFewLines(){
    START_LINE_NO=$1
    END_LINE_NO=$2
    outputString=""
    i=0
    while read line; do
        i=$(( i + 1 ))
        if [ $i -ge $START_LINE_NO ] && [ $i -le $END_LINE_NO ]; then
            if [ $i -eq $END_LINE_NO ]; then
                outputString="${outputString}${line}"
            else
                outputString="${outputString}${line}\n"
            fi
        fi
    done < $newcertfile
    echo "$outputString"
}

getRandomString(){
    randomString=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 7 ; echo '')
    echo $randomString
}

getGSKLinuxCommand(){
    cl=$certificateLabel
    cf=$newClientSideCertificateFile
    linuxCommand="z='/dsmcert.kdb';"
    linuxCommand="${linuxCommand}y='/opt/tivoli/tsm/client/';"
    linuxCommand="${linuxCommand}a=\$PASSWORDDIR\$z;"
    linuxCommand="${linuxCommand}b=\$DSM_DIR\$z;"
    linuxCommand="${linuxCommand}c=~'/IBM/StorageProtect/certs'\$z;"
    linuxCommand="${linuxCommand}d=\$y'ba/bin64'\$z;"
    linuxCommand="${linuxCommand}e=\$y'ba/bin'\$z;"
    linuxCommand="${linuxCommand}f=\$y'api/bin64'\$z;"
    linuxCommand="${linuxCommand}g=\$y'api/bin'\$z;"
    linuxCommand="${linuxCommand}if [ -f \$a ]; then h=\$a;"
    linuxCommand="${linuxCommand}elif [ -f \$b ]; then h=\$b;"
    linuxCommand="${linuxCommand}elif [ -f \$c ]; then h=\$c;"
    linuxCommand="${linuxCommand}elif [ -f \$d ]; then h=\$d;"
    linuxCommand="${linuxCommand}elif [ -f \$e ]; then h=\$e;"
    linuxCommand="${linuxCommand}elif [ -f \$f ]; then h=\$f;"
    linuxCommand="${linuxCommand}else h=\$g;"
    linuxCommand="${linuxCommand}fi;"
    linuxCommand="${linuxCommand}/usr/local/ibm/gsk8_64/bin/gsk8capicmd_64"
    linuxCommand="${linuxCommand} -cert -add  -label ${cl}  -file ${cf}"
    linuxCommand="${linuxCommand} -db \$h -stashed"
    echo $linuxCommand
}

getGSKAIXCommand(){
    cl=$certificateLabel
    cf=$newClientSideCertificateFile
    aixCommand="z='dsmcert.kdb';"
    aixCommand="${aixCommand}y='/usr/tivoli/tsm/client/';"
    aixCommand="${aixCommand}a='\${PASSWORDDIR}/'\${z};"
    aixCommand="${aixCommand}b='\${DSM_DIR}/'\${z};"
    aixCommand="${aixCommand}d=\${y}'ba/bin64/'\${z};"
    aixCommand="${aixCommand}e=\${y}'ba/bin/'\${z};"
    aixCommand="${aixCommand}f=\${y}'api/bin64/'\${z};"
    aixCommand="${aixCommand}g=\${y}'api/bin/'\${z};"
    aixCommand="${aixCommand}h='';"
    aixCommand="${aixCommand}if [ -f \$a ]; then h=\$a;"
    aixCommand="${aixCommand}elif [ -f \$b ]; then h=\$b;"
    aixCommand="${aixCommand}elif [ -f \$d ]; then h=\$d;"
    aixCommand="${aixCommand}elif [ -f \$e ]; then h=\$e;"
    aixCommand="${aixCommand}elif [ -f \$f ]; then h=\$f;"
    aixCommand="${aixCommand}elif [ -f \$g ]; then h=\$g;"
    aixCommand="${aixCommand}fi;"
    aixCommand="${aixCommand}/usr/opt/ibm/gsk8_64/bin/gsk8capicmd_64"
    aixCommand="${aixCommand} -cert -add  -label ${cl}  -file ${cf} -db \$h -stashed"
    echo $aixCommand
}

getGSKMACCommand(){
    cl=$certificateLabel
    cf=$newClientSideCertificateFile
    macCommand="z=dsmcert.kdb;"
    macCommand="${macCommand}y=/Library/Application\ Support/tivoli/tsm/client/;"
    macCommand="${macCommand}a=\${PASSWORDDIR}/\${z};"
    macCommand="${macCommand}b=\${DSM_DIR}/\${z};"
    macCommand="${macCommand}e=\${y}ba/bin/\${z};"
    macCommand="${macCommand}g=\${y}api/bin/\${z};"
    macCommand="${macCommand}h=\"\";"
    macCommand="${macCommand}if [ -f \"\$a\" ]; then h=\$a;"
    macCommand="${macCommand}elif [ -f \"\$b\" ]; then h=\$b;"
    macCommand="${macCommand}elif [ -f \"\$e\" ]; then h=\$e;"
    macCommand="${macCommand}elif [ -f \"\$g\" ]; then h=\$g;"
    macCommand="${macCommand}fi;"
    macCommand="${macCommand}/Library/ibm/gsk8/bin/gsk8capicmd"
    macCommand="${macCommand} -cert -add  -label ${cl} -file ${cf} -db \"\$h\" -stashed"
    echo $macCommand
}

getWindowsCertKDBPathSchedule(){
    winCertKDBPathCommand="powershell if(Test-Path $windowsCertKDBPathFile){Remove-Item -Path $windowsCertKDBPathFile};\$z='\dsmcert.kdb';\$y=(get-location).path;\$x='C:\Program Files\';\$a=\$x+'Tivoli\TSM\'+'baclient'+\$z;\$b=\$(\$env:DSM_DIR)+\$z;\$c=\$x+'Common Files\Tivoli\TSM\'+'api64'+\$z;\$d=\$(\$env:PASSWORDDIR)+\$z;\$e=\$(\$env:USERPROFILE)+'\IBM\SpectrumProtect\'+'certs'+\$z;if(Test-Path \$a){\$f=\$a}elseif(Test-Path \$b){\$f=\$b}elseif(Test-Path \$c){\$f=\$c}elseif(Test-Path \$d){\$f=\$d}elseif(Test-Path \$e){\$f=\$e};Add-Content $windowsCertKDBPathFile \$f -NoNewline"
    echo $winCertKDBPathCommand
}

getGSKWindowsCommand(){
    cl=$certificateLabel
    cf=$newClientSideCertificateFile
    winCommand="powershell \$p1 = Get-Content -Path $windowsCertKDBPathFile;\$y=(get-location).path;\$env:Path=\$env:Path+';c:\progra~1\ibm\gsk8\'+'bin\;c:\progra~1\ibm\gsk8\lib64\;';cd 'C:\Program Files\IBM\gsk8';cd 'bin';.\gsk8capicmd_64 -cert -add -label $cl -file \$y\\$cf -db \$p1 -stashed"
    echo $winCommand
}

getGSKCommand(){
    platform=$1
    gskCommand=""
    if [ "$platform" = "UNX" ]; then
        gskCommand=$(getGSKLinuxCommand)
    elif [ "$platform" = "LNX" ]; then
        gskCommand=$(getGSKLinuxCommand)
    elif [ "$platform" = "AIX" ]; then
        gskCommand=$(getGSKAIXCommand)
    elif [ "$platform" = "MAC" ]; then
        gskCommand=$(getGSKMACCommand)
    elif [ "$platform" = "WIN" ]; then
        gskCommand=$(getGSKWindowsCommand)
    fi
    echo $gskCommand
}

updateScheduleInMacroFile(){
    domainName=$1
    platformCode=$2
    clientName=$3
    minutes=0

    set -A macroSchedules
    mschCounter=0
    scheduleID=0

    # For every text part in array $certTextParts
    for text in "${certTextParts[@]}"; do
        minutes=$((scheduleID * scheddelay))
        if [ "$platformCode" = "$platformstrwin" ]; then
            
            # Replace "\n" with "`n" and " " with "` " for Windows ECHO.
            text=$(echo "$text" | awk 1 ORS='`n')
            text=$(echo $text | sed 's/ /\` /g')

            # Remove last escaped newline character.
            text=$(echo "$text" | rev | cut -c3- | rev)
            
            # For windows powershell echo is needed.
            if [ "$scheduleID" -eq "0" ]; then
                # First schedule to create file.
                schedulePart="powershell echo \"${text}\" \> ${newClientSideCertificateFile}"
            else
                # Next schedules to append in file.
                schedulePart="powershell echo \"${text}\" \>> ${newClientSideCertificateFile}"
            fi

            schedule="def sch ${domainName} ${scheduleprefix}_${scheduleID}_${platformCode} act=c startt=now+0${startdelay}:${minutes} DUR=${schedduration} DURU=MINUTES obj='${schedulePart}'"
            macroSchedules[$mschCounter]="$schedule"
        elif [ "$platformCode" = "$platformstrlnx" ]; then

            # Escape new line.
            text=$(echo "$text\c" | awk 1 ORS='\\n')

            # For Linux echo -e is needed.
            if [ "$scheduleID" -eq "0" ]; then
                # First schedule to create file.
                schedulePart="echo -e '${text}\c' \> ${newClientSideCertificateFile}"
            else
                # Next schedules to append in file.
                schedulePart="echo -e '${text}\c' \>> ${newClientSideCertificateFile}"
            fi
            
            schedule="def sch ${domainName} ${scheduleprefix}_${scheduleID}_${platformCode} act=c startt=now+0${startdelay}:${minutes} DUR=${schedduration} DURU=MINUTES obj=\"${schedulePart}\""
            macroSchedules[$mschCounter]="$schedule"
        else
            # Escape new line.
            text=$(echo "$text" | awk 1 ORS='\\n')
            
            # For platform apart from Linux and Windows i.e. AIX echo is needed.
            # Appended '\c' at end to skip extra new line getting added on AIX in echo.
            if [ "$scheduleID" -eq "0" ]; then
                # First schedule to create file.
                schedulePart="echo '${text}\c' \> ${newClientSideCertificateFile}"
            else
                # Next schedules to append in file.
                schedulePart="echo '${text}\c' \>> ${newClientSideCertificateFile}"
            fi

            schedule="def sch ${domainName} ${scheduleprefix}_${scheduleID}_${platformCode} act=c startt=now+0${startdelay}:${minutes} DUR=${schedduration} DURU=MINUTES obj=\"${schedulePart}\""
            macroSchedules[$mschCounter]="$schedule"
        fi
        (( mschCounter+=1 ))
        scheduleID=$((scheduleID + 1))
    done

    # Last schedule having GSK command according to platform.
    minutes=$((scheduleID * scheddelay))

    schedulePart=$(getGSKCommand $platformCode)

    if [ "$platformCode" = "$platformstrmac" ]; then
        # Double quotes in commamd of last schedule for MAC. Thus inclosing in single quote obj=''.
        scheduleGSKit="def sch ${domainName} ${scheduleprefix}_${scheduleID}_${platformCode} act=c startt=now+0${startdelay}:${minutes} DUR=${schedduration} DURU=MINUTES obj='${schedulePart}'"
    elif  [ "$platformCode" = "$platformstrwin" ]; then

        scheduleWinCertPart=$(getWindowsCertKDBPathSchedule)
        scheduleWinCertPath="def sch ${domainName} ${scheduleprefix}_${scheduleID}_${platformCode} act=c startt=now+0${startdelay}:${minutes} DUR=${schedduration} DURU=MINUTES obj=\"${scheduleWinCertPart}\""

        scheduleID=$((scheduleID + 1))
        minutes=$((scheduleID * scheddelay))
        scheduleGSKit="def sch ${domainName} ${scheduleprefix}_${scheduleID}_${platformCode} act=c startt=now+0${startdelay}:${minutes} DUR=${schedduration} DURU=MINUTES obj=\"${schedulePart}\""
    else
        scheduleGSKit="def sch ${domainName} ${scheduleprefix}_${scheduleID}_${platformCode} act=c startt=now+0${startdelay}:${minutes} DUR=${schedduration} DURU=MINUTES obj=\"${schedulePart}\""
    fi

    # Checking 512 characters limit. For all scheules before appending in MACRO file.
    for macroSchedule in "${macroSchedules[@]}"; do
        
        # Extract text between obj="<text>" or obj='<text>' and check length
        s1=$(echo "$macroSchedule" | sed 's/.* obj=.\(.*\)./\1/')        
        cmdSize=${#s1}

        if [ "$cmdSize" -gt "512" ]; then
            echo "ERROR : Certificate file $newcertfile appears to be corrupted. Please verify if the certificate conforms to the standard format."
            LOG "ERROR" "Certificate file $newcertfile appears to be corrupted. Please verify if the certificate conforms to the standard format."
            LOG "INFO" "Terminating script execution."
            exit 1
        fi

        # Append schedule schedule in MACRO file.
        printf "%s\n" "$macroSchedule" >> $macroFile
    done

    # Append GSKit schedule in MACRO file.

    # Append Windows Certificate Key Store Path locating Schedule First.
    if  [ "$platformCode" = "$platformstrwin" ]; then
        printf "%s\n" "$scheduleWinCertPath" >> $macroFile
    fi

    printf "%s\n" "$scheduleGSKit" >> $macroFile

}

deleteScheduleInMacroFile(){
    domainName=$1
    platformCode=$2
    scheduleName="$platformCode"
    lastCount=$totalSchedulesCount

    # Checking here less than because indexing starts with 0 when defining schedules.
    n=0
    while (( n < $totalSchedulesCount ))
    do
        schedule="delete schedule ${domainName} ${scheduleprefix}_${n}_${scheduleName}"
        printf "%s\n" "$schedule" >> $macroFile
        (( n+=1 ))
    done

    # Add one more schedule because we have 2 schedules for GSKit for Windows client.
    if [ "$platformCode" = "$platformstrwin" ]; then
        schedule="delete schedule ${domainName} ${scheduleprefix}_${lastCount}_${scheduleName}"
        printf "%s\n" "$schedule" >> $macroFile
    fi
}

updateAssocInMacroFile(){
    domainName=$1
    platformCode=$2
    clientName=$3
    scheduleName="$platformCode"
    lastCount=$totalSchedulesCount

    # Checking here less than because indexing starts with 0 when defining schedules.
    n=0
    while (( n < $totalSchedulesCount ))
    do
        assoc="def assoc $domainName ${scheduleprefix}_${n}_${scheduleName} $clientName"
        printf "%s\n" "$assoc" >> $macroFile
        (( n+=1 ))
    done

    # Add one more schedule because we have 2 schedules for GSKit for Windows client.
    if [ "$platformCode" = "$platformstrwin" ]; then
        assoc="def assoc $domainName ${scheduleprefix}_${lastCount}_${scheduleName} $clientName"
        printf "%s\n" "$assoc" >> $macroFile
    fi
}

processClientNodes(){
    # Delete Existing MACRO File.
    rm -f $macroFile

    clientInfoFile=$1

    # Read certificate text lines in array $certTextLines
    linesCounter=0
    while read line; do
        certTextLines[$linesCounter]="$line"
        (( linesCounter+=1 ))
    done < $newcertfile

    # Converting certLines to integer for arithmatic comparison on loop.
    certLines=$((certLines + 0))

    # Select 7 lines from certificate text file at a time.
    # Add these text parts into the array named $schedules.
    textPartCounter=0
    i=1
    while (( i <= $certLines ))
    do
        last_index=$((i + 6))
        if (( $last_index > $certLines )); then
            last_index=$certLines
        fi
        text=$(readFewLines $i $last_index)
        certTextParts[$textPartCounter]=$text
        ((textPartCounter=$textPartCounter+1))
        (( i+=7 ))
    done

    while read line; do
        # Each client node information string in file looks like,
        # domain_name,platform_code,client_name
        # Thus splitting string using comma delimeter to get details.
        LIST=$(echo $line | sed 's/,/ /g')
        set -A arrIN $LIST

        domainName="${arrIN[0]}"
        platformCode="${arrIN[1]}"
        clientName="${arrIN[2]}"

        # Unsupported Platform.
        if [[ ! ${supportedPlatforms[@]} = *$platformCode* ]]; then
            # TODO : Check for TDP clients. how it gives platform code.
            LOG "INFO" "Client : $clientName Platform $platformCode is not supported."
            continue
        fi

        # For all clients under same domain and platform. Common schedule will be there.
        # check if domain_platform name present in already created schedule name prefix.
        dpPair="$domainName-$platformCode"
        pairPresent=0
        
        # Checking if pair is already present..
        for elem in "${domainPlatformPairs[@]}"; do
            if [ "$elem" = "$dpPair" ]; then
                pairPresent=1
            fi
        done

        if [ "$pairPresent" == "1" ]; then
            # Already schedule name created for this pair.
            # Directly associate client with this schedule.
            updateAssocInMacroFile $domainName $platformCode $clientName
        else
            # New entry in array. Create schedule for this and,
            # associate client on this schedule.
            domainPlatformPairs[${#domainPlatformPairs[*]}+1]="$dpPair"
            updateScheduleInMacroFile $domainName $platformCode $clientName
            updateAssocInMacroFile $domainName $platformCode $clientName
        fi

    done < $clientInfoFile
}

executeMacroFile(){
    cd $dsmadmcpath
    OUTPUT=$(./dsmadmc -id=$id -password=$password \
        -optfile=$dsmoptfile \
        -outfile=$1 \
        -ITEMCOMMIT macro "$macroFile")
    exitCode=$?
    echo "${exitCode}"
}

distributeCertificates(){
    LOG "INFO" "distributeCertificates - Starting to distribute certificate to all clients."

    userName=$id
    password=$password
    exitCode=$(getClientNodes $userName $password $nodeListFile)

    if [ "$exitCode" -ne "0" ] || [ ! -f $nodeListFile ]; then
        echo "ERROR : Error in getting client nodes information. EXIT Code : $exitCode"
        LOG "ERROR" "Getting client nodes information. EXIT Code : $exitCode"
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    # Generate Certificate Label.
    rString=$(getRandomString)
    certificateLabel="spcert_$rString"
    newClientSideCertificateFile="${certificateLabel}.crt"

    processClientNodes $nodeListFile
    if [ ! -f $macroFile ]; then
        
        errorMSG1="There are no clients / nodes available for processing."
        errorMSG2="Validate nodes and their platform information using server administrator console command <query node>."
        errorMSG3="For more details on supported client / node types please refer the product documentation."

        echo ""
        echo $errorMSG1
        echo ""
        echo $errorMSG2
        echo ""
        echo $errorMSG3
        echo ""

        LOG "ERROR" "${errorMSG1} ${errorMSG2} ${errorMSG3}"
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    exitCode=$(executeMacroFile $macroDEFINEcmdOutputFile)
    
    SPRETCODE=$(grep -E 'ANS8002I' $macroDEFINEcmdOutputFile)
    LOG "INFO" "executeMacroFile  : ${SPRETCODE}"

    if [ "$exitCode" -ne "0" ]; then
        echo ""
        echo "${SPRETCODE}"
        echo ""
        echo "Error in defining schedules ${scheduleprefix}*."
        echo "For more information, take a look at DISTRIBUTE MACRO commands output file $macroDEFINEcmdOutputFile"
        LOG "ERROR" "Error in defining schedules ${scheduleprefix}*. For more information, take a look at DISTRIBUTE MACRO commands output file $macroDEFINEcmdOutputFile"
        echo ""
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    echo ""
    echo "${SPRETCODE}"
    echo ""
    echo ">> Schedules are defined to distribute the certificate to clients."
    echo ">> A return code other than 0 indicates an error. For more information, take a look at the log file."
    echo ">> The log file is located at $LOGFILE"
    echo ">> Client nodes will begin receiving a new certificate after $startdelay hours from the start time of the scheduler window."
    echo ">> To monitor the progress of certificate distribution, it is recommended to run this script in Report mode regularly for a couple of days."
    echo ""
}

generateReport(){
    LOG "INFO" "generateReport - Starting to generate report."
    timeStamp=$(date +%Y-%m-%d-%H_%M_%S)
    reportPrefix="${scheduleprefix}_${reportPrefix}"
    reportFile01="${reportPrefix}_01_${timeStamp}"
    reportFile02="${reportPrefix}_02_${timeStamp}"
    reportFile="${currentDir}/${reportPrefix}${timeStamp}"

    # Check for last schedule status.
    lastScheduleID=$((totalSchedulesCount - 1))
    schedpattern="${scheduleprefix}_${lastScheduleID}_"
    winschedpattern="${scheduleprefix}_${totalSchedulesCount}_"

    sql="SELECT DISTINCT nd.domain_name, nd.platform_name, nd.node_name, CASE WHEN Min(ev.status) IS NOT NULL THEN Min(ev.status) ELSE 'Unknown' END status FROM nodes nd LEFT JOIN events ev ON ( ev.domain_name = nd.domain_name AND ev.node_name = nd.node_name ) WHERE ( ( Upper(ev.schedule_name) LIKE Upper('$winschedpattern%') AND Upper(Substr(nd.platform_name, 1, 3)) = 'WIN' ) OR ( Upper(ev.schedule_name) LIKE Upper('$schedpattern%') AND Upper(Substr(nd.platform_name, 1, 3)) NOT IN ( 'WIN' ) ) ) GROUP  BY nd.domain_name, nd.platform_name, nd.node_name"
    sql2="SELECT status, Count(*) node_count FROM (${sql}) GROUP BY status WITH UR FOR READ ONLY"

    cd $dsmadmcpath
    # Calling SQL2 First
    OUTPUT=$(./dsmadmc -id=$id -password=$password \
        -COMMAdelimited -DATAONLY=YES -DISPLaymode=TABle \
        -optfile=$dsmoptfile \
        -outfile=$reportFile01 \
        $sql2)
    exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo "ERROR : Error in getting status of schedule operation on client nodes."
        LOG "ERROR" "Error in getting status of schedule operation on client nodes."
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    # Append output from reportFile02 in report file.
    echo ""
    echo "Summary of certificate distribution status on all processed clients / nodes :"
    echo ""

    echo "" >> $reportFile
    echo "Summary of certificate distribution status on all processed clients / nodes :" >> $reportFile
    echo "" >> $reportFile
    printf "%+20s %+20s\n" "STATUS" "NODE COUNT"
    printf "%+20s %+20s\n" "STATUS" "NODE COUNT" >> $reportFile
    echo "-----------------------------------------"
    echo "-----------------------------------------" >> $reportFile
    while IFS=',' read -r status nodeCount; do
        printf "%+20s %+20s\n" "$status" "$nodeCount"
        printf "%+20s %+20s\n" "$status" "$nodeCount" >> $reportFile
    done < $reportFile01

    # Calling SQL.
    sql="${sql} WITH UR FOR READ ONLY"
    OUTPUT=$(./dsmadmc -id=$id -password=$password \
        -COMMAdelimited -DATAONLY=YES -DISPLaymode=TABle \
        -optfile=$dsmoptfile \
        -outfile=$reportFile02 \
        $sql)
    exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo "ERROR : Error in getting status of schedule operation on client nodes."
        LOG "ERROR" "Error in getting status of schedule operation on client nodes."
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    # Append output from reportFile02 in report file.
    echo "" >> $reportFile
    echo "Detailed status of certificate distribution for all processed clients / nodes :" >> $reportFile
    echo "" >> $reportFile
    printf "%20s %20s %20s %20s\n" "DOMAIN" "PLATFORM" "CLIENT NAME" "STATUS" >> $reportFile
    echo "------------------------------------------------------------------------------------" >> $reportFile
    while IFS=',' read -r domainName platformCode clientName status; do
        printf "%+20s %+20s %+20s %+20s\n" "$domainName" "$platformCode" "$clientName" "$status"  >> $reportFile
    done < $reportFile02

    LOG "INFO" "The detailed status report is : $reportFile"

    echo ""
    echo "The detailed status report is : $reportFile"
    echo ""
    echo ">> Any status other than 'Completed' indicates a failure."
    echo ">> Client nodes with status ‘Missed’ specifies that the scheduled startup window is already passed."
    echo ">> Client nodes with status ‘Future’ specifies that the beginning of the startup window is in the future."
    echo ">> For ‘Missed’ and ‘Future’ status there is a chance that they will catch up as these schedules will be re-run on a daily basis."
    echo ">> Please regularly monitor the progress of certificate distribution status, by executing this script in Report mode for a couple of days."
    echo ">> Client nodes that are still in failed state, it is recommended to follow the manual steps for adding the certificate."
    echo ">>     1. Copy the new certificate file over to the client box."
    echo ">>     2. Execute below command to add the certificate."
    echo ">>        gsk8capicmd_64 -cert -add -label \"<<New Certificate Label>>\" -file \"<<New Certificate File Path>>\" -db dsmcert.kdb -stashed"
    echo ">>        Tip: The dsmcert.kdb file is located in client installation directory.  On Unix, Linux and Mac systems, if client sessions were ever started from a non-root user, copies of the certificate can be located in \$HOME/IBM/StorageProtect/certs/ or in the directory determined by the PASSWORDDIR client option."
    echo ""
}

cleanup(){
    LOG "INFO" "cleanup - Starting cleanup."

    # Delete Existing MACRO File.
    rm -f $macroFile

    userName=$id
    password=$password
    exitCode=$(getClientNodes $userName $password $nodeListFile)
    
    if [ "$exitCode" -ne "0" ] || [ ! -f $nodeListFile ]; then
        echo "ERROR : Error in getting client nodes information. EXIT Code : $exitCode"
        LOG "ERROR" "Getting client nodes information. EXIT Code : $exitCode"
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    while read line; do
        # Each client node information string in file looks like,
        # domain_name,platform_code,client_name
        # Thus splitting string using comma delimeter to get details.
        LIST=$(echo $line | sed 's/,/ /g')
        set -A arrIN $LIST

        domainName="${arrIN[0]}"
        platformCode="${arrIN[1]}"
        clientName="${arrIN[2]}"

        # Unsupported Platform.
        if [[ ! ${supportedPlatforms[@]} = *$platformCode* ]]; then
            # TODO : Check for TDP clients. how it gives platform code.
            LOG "INFO" "Client : $clientName Platform $platformCode is not supported."
            continue
        fi

        dpPair="$domainName-$platformCode"
        pairPresent=0
        
        # Checking if pair is already present..
        for elem in "${domainPlatformPairs[@]}"; do
            if [ "$elem" = "$dpPair" ]; then
                pairPresent=1
            fi
        done

        if [ "$pairPresent" == "1" ]; then
            # Already schedule name created for this pair.
            # Directly associate client with this schedule.
            continue
        else
            # New entry in array. Create schedule for this and,
            # associate client on this schedule.
            domainPlatformPairs[${#domainPlatformPairs[*]}+1]="$dpPair"
            deleteScheduleInMacroFile $domainName $platformCode
        fi

    done < $nodeListFile

    if [ ! -f $macroFile ]; then
        echo "ERROR in cleaning up schedules ${scheduleprefix}*. Please confirm if distribute action was performed before cleanup."
        LOG "ERROR" "ERROR in cleaning up schedules ${scheduleprefix}*. Please confirm if distribute action was performed before cleanup."
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    exitCode=$(executeMacroFile $macroDELETEcmdOutputFile)

    SPRETCODE=$(grep -E 'ANS8002I' $macroDELETEcmdOutputFile)
    LOG "INFO" "executeMacroFile  : ${SPRETCODE}"

    if [ "$exitCode" -ne "0" ]; then
        echo ""
        echo "${SPRETCODE}"
        echo ""
        echo "ERROR in cleaning up schedules *${scheduleprefix}*."
        echo "For more information, take a look at Cleanup MACRO commands output file $macroDELETEcmdOutputFile"
        LOG "ERROR" "ERROR in cleaning up schedules *${scheduleprefix}*. For more information, take a look at Cleanup MACRO commands output file $macroDELETEcmdOutputFile"
        echo ""
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    echo ""
    echo "${SPRETCODE}"
    echo ""
    echo ">> Cleanup Completed."
    echo ">> A return code other than 0 indicates an error. For more information, take a look at the log file."
    echo ">> The log file is located at $LOGFILE"
    echo ""
}

execute(){
    currentDir="${0%/*}"
    if [ "$currentDir" == "cert_distribute.ksh" ]; then
        # If program was run as 'cert_distribute.ksh -id ...' instead of './cert_distribute.ksh'
        currentDir=$(pwd)
    elif [ "$currentDir" == "." ]; then
        # If current directory path is obtained as '.',
        # because script was executed by only script name.
        # Then get current directory path.
        currentDir=$(pwd)
    fi

    updateOutputFilesPath $currentDir

    LOG "INFO" "Starting Script Execution."

    if [ ! -f $configFile ]; then
        echo "ERROR : Configurations INI File $configFile not present. Please check pre-requisite steps to execute script again."
        LOG "ERROR" "Configurations INI File $configFile not present. Please check pre-requisite steps to execute script again."
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    checkArguments  "$@"

    readConfigFile

    validateConfigPaths

    # Update PATH of certificate file.
    # This certificate file will be in the same directory where the script is.
    suffix='/'
    if [[ $currentDir = *$suffix ]]; then
        newcertfile="${currentDir}${newcertfile}"
    else
        newcertfile="${currentDir}/${newcertfile}"
    fi

    # Check if certificate file is present or not. EXIT if not.
    # For any action between distribute / report / cleanup we need this file to be present.
    if [ ! -f $newcertfile ]; then
        
        # Update PATH of certificate file based on current directory for this script.
        # This certificate file will be in the same directory where the script is.
        suffix='/'
        if [[ $currentDir = *$suffix ]]; then
            newcertfile="${currentDir}${newcertfile}"
        else
            newcertfile="${currentDir}/${newcertfile}"
        fi

        # Again check if file exists in the 
        if [ ! -f $newcertfile ]; then
            echo "ERROR : Certificate File not present. Please check pre-requisite steps to execute script again."
            LOG "ERROR" "Certificate File not present. Please check pre-requisite steps to execute script again."
            LOG "INFO" "Terminating script execution."
            exit 1
        fi
    fi

    # Get certificate text in certText.
    certText=$(cat $newcertfile)

    CERTLINESCOUNT=$(cat $newcertfile| wc -l)
    exitCode=$?
    if [ "$exitCode" -ne "0" ]; then
        echo "ERROR : Error in getting lines count from certificate file. EXIT Code : $exitCode"
        LOG "ERROR" "Getting lines count from certificate file. EXIT Code : $exitCode"
        LOG "INFO" "Terminating script execution."
        exit 1
    fi
    certLines=$(echo "${CERTLINESCOUNT}" | sed 's/^ *//g')

    # Check for validity of certificate text.
	# WHETHER TODO ? First line and last line check or based on number of lines ?
	# Currently we are checking this using number of lines in the certificate file.
	# CA Signed certificate has 26 lines and Self Signed certificateh has 21 lines it it.

    if [[ ! "$certLines" -ge "21" && "$certLines" -le "28" ]]; then
        echo "Error : Number of Lines in certificate file $newcertfile exceed the supported limit."
        LOG "ERROR" "Number of Lines in certificate file $newcertfile exceed the supported limit."
        LOG "INFO" "Terminating script execution."
        exit 1
    fi

    # Calculate total number of scheules. This value will be used in all actions.
    # Taking 7 here because we are reading 7 lines at a time from cert when distributing for 512 chars limit.
    linesReadLimit=7
    divisionVal=$((certLines / linesReadLimit))
    reminderVal=$((certLines % linesReadLimit))
    if [ "$reminderVal" -eq "0" ]; then
        # i.e. Total text parts scheules + GSKit schedule.
        totalSchedulesCount=$((divisionVal + 1))
    else
        totalSchedulesCount=$((divisionVal + 2))
    fi

    if [ "$action" == "distribute" ]; then
        distributeCertificates
    elif [ "$action" == "report" ]; then
        generateReport
    elif [ "$action" == "cleanup" ]; then
        cleanup
    fi

    LOG "INFO" "Script Execution Completed."
}

execute "$@"


