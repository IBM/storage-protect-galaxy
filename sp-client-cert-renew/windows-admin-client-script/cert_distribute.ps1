################################################################################
#                                                                              #
#       Copyright (C) 2023, International Business Machines Corp. (IBM)        #
#                          All rights reserved.                                #
#                                                                              #
#       Automated Distribution of SP Server Certificate to Clients             #
#                                                                              #
# This POWERSHELL script is the automation utility, responsible for distribut- #
# ing the Spectrum Protect server certificate to all BA and TDP clients.       #
# Eliminating the need of log-in on each client machine connected to server    #
# and manually adding the new certificate.                                     #
#                                                                              #
# This utility consists of a POWERSHELL script file cert_distribute.ps1 and    #
# the corresponding configuration file cert_distribute.ini                     #                                              
#                                                                              #
# Prerequisites:                                                               #
# 1. The ADMIN CLIENT (dsmadmc) running on Windows OS has been configured to   #
#    be able to connect to the Spectrum Protect server.                        #
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
# powershell .\cert_distribute.ps1 -id dsmadmc-username                        #
#                                  -password dsmadmc-user-password             #
#                                  -action distribute                          #
#                                                                              #
# To monitor status of existing certificate distribution job:                  #
# powershell .\cert_distribute.ps1 -id dsmadmc-username                        #
#                                  -password dsmadmc-user-password             #
#                                  -action report                              #
#                                                                              #
# To cleanup existing certificate distribution job:                            #
# powershell .\cert_distribute.ps1 -id dsmadmc-username                        #
#                                  -password dsmadmc-user-password             #
#                                  -action cleanup                             #
#                                                                              #
################################################################################

param (
    [Parameter(Mandatory=$true)][string]$action,
	[Parameter(Mandatory=$true)][string]$id,
	[Parameter(Mandatory=$true)][string]$password
)

Function Parse-IniFile ($file) {
  $ini = @{}

  # Create a default section if none exist in the file. Like a java prop file.
  $section = "NO_SECTION"
  $ini[$section] = @{}

  switch -regex -file $file {
    "^\[(.+)\]$" {
      $section = $matches[1].Trim()
      $ini[$section] = @{}
    }
    "^\s*([^#].+?)\s*=\s*(.*)" {
      $name,$value = $matches[1..2]
      # skip comments that start with semicolon:
      if (!($name.StartsWith(";"))) {
        $ini[$section][$name] = $value.Trim()
      }
    }
  }
  $ini
}

function Get-RandomString() {
	param(
		[int]$length=10,
		[char[]]$sourcedata
	)

	for($loop=1; $loop -le $length; $loop++) {
		$TempPassword+=($sourcedata | GET-RANDOM | %{[char]$_})
	}
	return $TempPassword
}

$currentDir=$PSScriptRoot
$iniFilePath = $currentDir + "\cert_distribute.ini"

# Read sciprt configuration from cert_distribute.ini
$iniFile = Parse-IniFile $iniFilePath

$newcertfile = $iniFile.CERT.newcertfile

$dsmadmcpath = $iniFile.TSM.dsmadmcpath
$dsmoptfile = $iniFile.TSM.dsmoptfile
$scheduleprefix = $iniFile.TSM.scheduleprefix

$startdelay = $iniFile.SCHED.startdelay
$scheddelay = $iniFile.SCHED.scheddelay
$schedduration = $iniFile.SCHED.schedduration

#$certfilename = (New-Guid)
$certlabel = "spcert_"+(Get-RandomString -length 7 -sourcedata (48..57 + 65..90 + 97..122))
$certfilename = $certlabel + ".crt"

# Constants
# ----------------

# Save current dir
$workingdir = (get-location).path

# Switch to dsmadmc dir
cd $dsmadmcpath

# $homedir = (Get-Item 'ENV:\USERPROFILE').value + "\"
$actiondistribute = "distribute"
$actionreport = "report"
$actioncleanup = "cleanup"

# Update path to full path for all output files along with certificate file.
$newcertfile = $currentDir + "\$newcertfile"
$nodelistfile = $currentDir + "\output_nodelist.out"
$macrofile = $currentDir + "\output_define_schedules.macro"
$reportprefix = $currentDir + "\$scheduleprefix`_distribute.report."
$logfile = $currentDir + "\cert_distribute.log"
$tempfile = $currentDir + "\output_tempfile.out"
$macroDEFINEcmdOutputFile = $currentDir + '\output_define_result.out'
$macroDELETEcmdOutputFile = $currentDir + '\output_delete_result.out'

$windowsCertKDBPathFile="kdb_path.out"

$minCertLines = 21
$maxCertLines = 28

$schedbase = "def sch DOMAIN_NAME SCHED_NAME_PLATFORM_NAME act=c startt=START_TIME DUR=$schedduration DURU=m obj="
$schednamebase = $scheduleprefix + "_"
$schedstartbase = "now+0" + $startdelay + ":"

# This client side script for Windows

$schedwincertkdbpath = "`"powershell if(Test-Path $windowsCertKDBPathFile){Remove-Item -Path $windowsCertKDBPathFile};`$z='\dsmcert.kdb';`$y=(get-location).path;`$x='C:\Program Files\';`$d=`$(`$env:PASSWORDDIR)+`$z;`$e=`$(`$env:USERPROFILE)+'\IBM\SpectrumProtect\certs'+`$z;`$b=`$(`$env:DSM_DIR)+`$z;`$a=`$x+'Tivoli\TSM\baclient'+`$z;`$c=`$x+'Common Files\Tivoli\TSM\api64'+`$z;if(Test-Path `$a){`$f=`$a}elseif(Test-Path `$b){`$f=`$b}elseif(Test-Path `$c){`$f=`$c}elseif(Test-Path `$d){`$f=`$d}elseif(Test-Path `$e){`$f=`$e};Add-Content $windowsCertKDBPathFile `$f -NoNewline`""
$schedfinalwin = "`"powershell `$p1 = Get-Content -Path $windowsCertKDBPathFile;`$y=(get-location).path;`$p=`$env:Path+';c:\progra~1\ibm\gsk8\bin\;c:\progra~1\ibm\gsk8\lib64\;';`$env:Path=`$p;cd 'C:\Program Files\IBM\gsk8\bin';.\gsk8capicmd_64 -cert -add -label $certlabel -file `$y\$certfilename -db `$p1 -stashed`""
# This client side script for Linux
$schedfinallnx = "'z=`"/dsmcert.kdb`";y=`"/opt/tivoli/tsm/client/`";a=`$PASSWORDDIR`$z;b=`$DSM_DIR`$z;c=~`"/IBM/StorageProtect/certs`"`$z;d=`$y`"ba/bin64`"`$z;e=`$y`"ba/bin`"`$z;f=`$y`"api/bin64`"`$z;g=`$y`"api/bin`"`$z;if [ -f `$a ];then h=`$a;elif [ -f `$b ];then h=`$b;elif [ -f `$c ];then h=`$c;elif [ -f `$d ];then h=`$d;elif [ -f `$e ];then h=`$e;elif [ -f `$e ];then h=`$f;else h=`$g;fi;/usr/local/ibm/gsk8_64/bin/gsk8capicmd_64 -cert -add -label $certlabel -file $certfilename -db `$h -stashed'"
# This client side script for Aix
$schedfinalaix = "'z=`"/dsmcert.kdb`";y=`"/usr/tivoli/tsm/client/`";a=`$PASSWORDDIR`$z;b=`$DSM_DIR`$z;d=`$y`"ba/bin64`"`$z;e=`$y`"ba/bin`"`$z;f=`$y`"api/bin64`"`$z;g=`$y`"api/bin`"`$z;if [ -f `$a ];then h=`$a;elif [ -f `$b ];then h=`$b;elif [ -f `$d ];then h=`$d;elif [ -f `$e ];then h=`$e;elif [ -f `$e ];then h=`$f;else h=`$g;fi;/usr/opt/ibm/gsk8_64/bin/gsk8capicmd_64 -cert -add -label $certlabel -file $certfilename -db `$h -stashed'"
# This client side script for Mac
$schedfinalmac = "'z=dsmcert.kdb;y=/Library/Application\ Support/tivoli/tsm/client/;a=`${PASSWORDDIR}/`${z};b=`${DSM_DIR}/`${z};e=`${y}ba/bin/`${z};g=`${y}api/bin/`${z};h=`"`";if [ -f `"`$a`" ]; then h=`$a;elif [ -f `"`$b`" ]; then h=`$b;elif [ -f `"`$e`" ]; then h=`$e;else h=`$g;fi;/Library/ibm/gsk8/bin/gsk8capicmd -cert -add -label $certlabel -file $certfilename -db `"`$h`" -stashed'"

$platformstrwin = "WIN"
$platformstrlnx = "LNX"
$platformstraix = "AIX"
$platformstrmac = "MAC"
$platformstrtbd = "TBD"

#Log header
"****************************************" | Out-File -Append $logfile
"Run with action: "+$action+" at: "+(Get-Date -format "yyyy-MM-dd-HH:mm:ss")+"`n" | Out-File -Append $logfile

# Shared variables
# ----------------

if ($action -eq $actiondistribute -or $action -eq $actioncleanup)
{
	# Remove old nodelist if has any
	if (Test-Path -path $nodelistfile)
	{
		Remove-Item -Path $nodelistfile
	}

	# Generate nodelist and domainlist
	$sql = "SELECT DISTINCT nd.domain_name, CASE WHEN Upper(Substr(nd.platform_name, 1, 3)) = 'WIN' OR Upper(Substr(nd.client_os_name, 1, 3)) = 'WIN' OR Upper(Substr(nd1.platform_name, 1, 3)) = 'WIN' OR Upper(Substr(nd1.client_os_name, 1, 3)) = 'WIN' OR Substr(fs.filespace_name, 1, 1) = '\' THEN 'WIN' WHEN Upper(Substr(nd.platform_name, 1, 3)) IN ( 'UNI', 'AIX' ) OR Upper(Substr(nd1.client_os_name, 1, 3)) = 'AIX' OR Upper(Substr(nd1.platform_name, 1, 3)) IN ( 'UNI', 'AIX' ) OR Upper(Substr(nd1.client_os_name, 1, 3)) = 'AIX' THEN 'AIX' WHEN Upper(Substr(nd.platform_name, 1, 3)) = 'MAC' OR Upper(Substr(nd.client_os_name, 1, 3)) = 'MAC' OR Upper(Substr(nd1.platform_name, 1, 3)) = 'MAC' OR Upper(Substr(nd1.client_os_name, 1, 3)) = 'MAC' THEN 'MAC' WHEN Upper(Substr(nd.platform_name, 1, 3)) IN ( 'LIN', 'LNX' ) OR Upper(Substr(nd.client_os_name, 1, 3)) IN ( 'LNX', 'SOL', 'HPX' ) OR Upper(Substr(nd1.platform_name, 1, 3)) IN ( 'LIN', 'LNX' ) OR Upper(Substr(nd1.client_os_name, 1, 3)) IN ( 'LNX', 'SOL', 'HPX' ) OR Substr(fs.filespace_name, 1, 1) = '/' THEN 'LNX' ELSE 'TBD' END AS platform, nd.node_name FROM nodes nd LEFT JOIN filespaces fs ON fs.node_name = nd.node_name LEFT JOIN nodes nd1 ON nd1.proxy_target LIKE '%' || nd.node_name || '%' WHERE nd.nodetype NOT IN ( 'NAS', 'OBJECTCLIENT' ) ORDER BY nd.domain_name, nd.node_name WITH UR FOR READ ONLY"
	.\dsmadmc -id="$id" -password="$password" -DATAONLY=yes -COMMAdelimited -DISPLaymode=TABle -optfile="$dsmoptfile" -outfile="$nodelistfile" "$sql"

	# Log admadmc result
	Get-Content -Path $nodelistfile | Out-File -Append $logfile

	$nodelist = Get-Content -Path $nodelistfile | sort -Unique

	#$templist = $nodelist | sort -Unique
	$templist = [Object[]]::new($nodelist.count)
	$k = 0
	foreach ($i in $nodelist)
	{
		$s = $i.Split(",")
		$templist[$k] = $s[0]+","+$s[1]
		$k ++
	}
	$domainlist = $templist | sort -Unique
}

# Functions
# ----------------

function distribute_new()
{
	# Delete Existing MACRO File.
	if (Test-Path -path $macrofile)
	{
		Remove-Item -Path $macrofile
	}

	# Get certificate text lines.
	$certline = Get-Content -Path $newcertfile

	# Get total number of lines in certificate file.
	$certLinesCount = @($certline).length

	# Check for validity of certificate text.
	# WHETHER TODO ? First line and last line check or based on number of lines ?
	# Currently we are checking this using number of lines in the certificate file.
	# CA Signed certificate has 26 lines and Self Signed certificateh has 21 lines it it.

	if (!($certLinesCount -ge $minCertLines -And $certLinesCount -le $maxCertLines)){
		$certLinesError = "`nError : Number of Lines in certificate file $newcertfile exceed the supported limit.`n"
		$certLinesError | Out-File -Append $logfile
		$certLinesError
		exit
	}

	$schedcmd = ""
	$scheduleWinCertPath = ""
	$schedlist = @()
	$schedidx = 0

	# Select 7 lines from certificate text file at a time.
	For ($i=0; $i -le $certLinesCount; $i=$i+7) {

		$last_index = $i + 6

		if ($last_index -gt $certLinesCount){
			$last_index = $certLinesCount
		}

		$lines = [String]::Join("``n",$certline[$i..$last_index])

		# $lines=$lines.Replace("`r`n", "``n")
	    # $lines=$lines.Replace(" ", "`` ")

		$schedcmd = $schedbase + "'ECHO_CMD `"" + $lines

		$schedname = $schednamebase + $schedidx.ToString()

		if ($i -eq 0){
			$schedcmd += "`" \> $certfilename'"
		}
		else{
			$schedcmd += "`" \>> $certfilename'"
		}

		$schedule = $schedcmd.replace("SCHED_NAME",$schedname).replace("START_TIME", $schedstartbase+($schedidx*$scheddelay).ToString())

		$schedlist += ,$schedule

		$schedidx += 1
	}

	# Define schedule for each domain, platform
	foreach ($i in $domainlist)
	{
		$dom = $i.Split(",")
		foreach ($sched in $schedlist)
		{
			$preDom = $dom[0]
			$schedcmd = $sched.replace("DOMAIN_NAME", $dom[0])
			if ($dom[1] -eq $platformstrwin)
			{
				$schedcmd = $schedcmd.replace("ECHO_CMD", "powershell echo").replace("PLATFORM_NAME", $platformstrwin).replace("BEGIN CERTIFICATE", "BEGIN`` CERTIFICATE").replace("END CERTIFICATE", "END`` CERTIFICATE")
			}
			elseif ($dom[1] -eq $platformstrlnx)
			{
				$schedcmd = $schedcmd.replace("ECHO_CMD", "echo -e").replace("``n", "\n").replace("PLATFORM_NAME", $platformstrlnx)
			}
			elseif ($dom[1] -eq $platformstraix)
			{
				$schedcmd = $schedcmd.replace("ECHO_CMD", "echo").replace("``n", "\n").replace("PLATFORM_NAME", $platformstraix)
			}
			elseif ($dom[1] -eq $platformstrmac)
			{
				$schedcmd = $schedcmd.replace("ECHO_CMD", "echo").replace("``n", "\n").replace("PLATFORM_NAME", $platformstrmac)
			}
			else
			{
				# Platform TBD line, skip it so far
			}

			# Check for limit of 512 characters.
			$found = $schedcmd -match ".*obj='(.*)'.*"
			$limited_text = $matches[1]
			$lineslength = $limited_text.Length
			if ($lineslength -gt 512){
				$certTextError = "ERROR : Certificate file $newcertfile appears to be corrupted. Please verify if the certificate conforms to the standard format."
				$certTextError
				$certTextError | Out-File -Append $logfile
				exit
			}

			# Append schedule command in macrofile.
			$schedcmd | Out-File -Encoding ASCII -Append $macrofile

		}

		# Generate the gsk commands
		$gskcmd = ""
		if ($dom[1] -eq $platformstrwin)
		{
			$scheduleWinCertPath = $schedbase.replace("DOMAIN_NAME", $dom[0]).replace("PLATFORM_NAME", $platformstrwin).replace("SCHED_NAME", $schednamebase+$schedidx.ToString()).replace("START_TIME", $schedstartbase+($schedidx*$scheddelay).ToString())+$schedwincertkdbpath
			
			$gskschedidx = $schedidx + 1
			$gskcmd = $schedbase.replace("DOMAIN_NAME", $dom[0]).replace("PLATFORM_NAME", $platformstrwin).replace("SCHED_NAME", $schednamebase+$gskschedidx.ToString()).replace("START_TIME", $schedstartbase+($gskschedidx*$scheddelay).ToString())+$schedfinalwin
		}
		elseif ($dom[1] -eq $platformstrlnx)
		{
			$gskcmd = $schedbase.replace("DOMAIN_NAME", $dom[0]).replace("PLATFORM_NAME", $platformstrlnx).replace("SCHED_NAME", $schednamebase+$schedidx.ToString()).replace("START_TIME", $schedstartbase+($schedidx*$scheddelay).ToString())+$schedfinallnx
		}
		elseif ($dom[1] -eq $platformstraix)
		{
			$gskcmd = $schedbase.replace("DOMAIN_NAME", $dom[0]).replace("PLATFORM_NAME", $platformstraix).replace("SCHED_NAME", $schednamebase+$schedidx.ToString()).replace("START_TIME", $schedstartbase+($schedidx*$scheddelay).ToString())+$schedfinalaix
		}
		elseif ($dom[1] -eq $platformstrmac)
		{
			$gskcmd = $schedbase.replace("DOMAIN_NAME", $dom[0]).replace("PLATFORM_NAME", $platformstrmac).replace("SCHED_NAME", $schednamebase+$schedidx.ToString()).replace("START_TIME", $schedstartbase+($schedidx*$scheddelay).ToString())+$schedfinalmac
		}
		else
		{
			# Platform TBD line, skip it so far
		}

		# Append Windows Certificate Key Store Path locating Schedule First.
		if ($dom[1] -eq $platformstrwin){
			$scheduleWinCertPath | Out-File -Encoding ASCII -Append $macrofile
		}

		# Append GSKit schedule command in macrofile.
		$gskcmd | Out-File -Encoding ASCII -Append $macrofile
	}

	# Define assocaition for each node, based on its domain, platform
	$assocmdbase = "def assoc DOMAIN_NAME SCHED_NAME_PLATFORM_NAME NODE_NAME"
	foreach ($i in $nodelist)
	{
		$node = $i.Split(",")
		$assocmd = $assocmdbase.replace("DOMAIN_NAME", $node[0]).replace("NODE_NAME", $node[2])
		if ($node[1] -eq $platformstrwin -or $node[1] -eq $platformstrlnx -or $node[1] -eq $platformstraix -or $node[1] -eq $platformstrmac)
		{
			for ($k=0;$k -le $schedidx; $k++)
			{
				$assocmd.replace("PLATFORM_NAME", $node[1]).replace("SCHED_NAME", $schednamebase+$k) | Out-File -Encoding ASCII -Append $macrofile
			}

			# Add one more schedule because we have 2 schedules for GSKit for Windows client.
			if ($node[1] -eq $platformstrwin){
				$gskschedidx = $schedidx + 1
				$assocmd.replace("PLATFORM_NAME", $node[1]).replace("SCHED_NAME", $schednamebase+$gskschedidx) | Out-File -Encoding ASCII -Append $macrofile
			}

		}
		else
		{
			# Platform TBD line, skip it so far
		}
	}

	if (!(Test-Path -path $macrofile)){

		$errorMSG1="There are no clients / nodes available for processing."
		$errorMSG2="Validate nodes and their platform information using server administrator console command <query node>."
		$errorMSG3="For more details on supported client / node types please refer the product documentation."

		$errorMSG1
		$errorMSG2
		$errorMSG3

		$errorMSG = "${errorMSG1} ${errorMSG2} ${errorMSG3}"
		$errorMSG | Out-File -Append $logfile
		exit
	}

	# Run define macrofile
	$result = (.\dsmadmc -id="$id" -password="$password" -optfile="$dsmoptfile" -outfile="$macroDEFINEcmdOutputFile" -ITEMCOMMIT macro "$macrofile")

	$SPRETCODE = (Get-Content $macroDEFINEcmdOutputFile | Select-String -Pattern "ANS8002I")
	$SPRETCODE

	# Log admadmc result
	Get-Content -Path $macroDEFINEcmdOutputFile | Out-File -Append $logfile

	$out  = "`n>> Schedules are defined to distribute the certificate to clients.`n"
	$out += ">> A return code other than 0 indicates an error. For more information, take a look at the log file.`n"
	$out += ">> The log file is located at $logfile`n"
	$out += ">> Client nodes will begin receiving a new certificate after $startdelay hours from the start time of the scheduler window.`n"
	$out += ">> To monitor the progress of certificate distribution, it is recommended to run this script in Report mode regularly for a couple of days."

	$out
	$out | Out-File -Append $logfile
}

function distribute_report()
{
	$reportfile = $reportprefix + (Get-Date -format "yyyy-MM-dd-HH_mm_ss")
	$schedpattern = ""
	
	$certLinesCount=(Get-Content $newcertfile).Length

	# Again checking for validity of certificate text.
	# WHETHER TODO ? First line and last line check or based on number of lines ?
	# Currently we are checking this using number of lines in the certificate file.
	# CA Signed certificate has 26 lines and Self Signed certificateh has 21 lines it it.

	if (!($certLinesCount -ge $minCertLines -And $certLinesCount -le $maxCertLines)){
		$certLinesError = "`nNumber of Lines in certificate file $newcertfile exceed the supported limit.`n"
		$certLinesError | Out-File -Append $logfile
		$certLinesError
		exit
	}

	# Final schedule ID for report.
	$schedpattern = ""
	if ($certLinesCount -eq $minCertLines){
		$schedpattern = $schednamebase+"3_"
		$winschedpattern = $schednamebase+"4_"
	}
	elseif ($certLinesCount -gt $minCertLines -And $certLinesCount -le $maxCertLines){
		$schedpattern = $schednamebase+"4_"
		$winschedpattern = $schednamebase+"5_"
	}

	$sql="SELECT DISTINCT nd.domain_name, nd.platform_name, nd.node_name, CASE WHEN Min(ev.status) IS NOT NULL THEN Min(ev.status) ELSE 'Unknown' END status FROM nodes nd LEFT JOIN events ev ON ( ev.domain_name = nd.domain_name AND ev.node_name = nd.node_name ) WHERE ( ( Upper(ev.schedule_name) LIKE Upper('$winschedpattern%') AND Upper(Substr(nd.platform_name, 1, 3)) = 'WIN' ) OR ( Upper(ev.schedule_name) LIKE Upper('$schedpattern%') AND Upper(Substr(nd.platform_name, 1, 3)) NOT IN ( 'WIN' ) ) ) GROUP  BY nd.domain_name, nd.platform_name, nd.node_name"
    $sql2="SELECT status, Count(*) node_count FROM ($sql) GROUP BY status WITH UR FOR READ ONLY"

	$result = (.\dsmadmc -id="$id" -password="$password" -COMMAdelimited -DATAONLY=YES -DISPLaymode=TABle -optfile="$dsmoptfile" -outfile="$tempfile" "$sql2")

	# Append output in report file.
	$tempString = "`nSummary of certificate distribution status on all processed clients / nodes :`n"
	$tempString
	$tempString | Out-File -Append $reportfile

	$tempString = "{0,20} {1,20}" -f "STATUS", "NODE COUNT"
	$tempString
	$tempString | Out-File -Append $reportfile

	$tempString = "-----------------------------------------"
	$tempString
	$tempString | Out-File -Append $reportfile

	foreach($line in Get-Content "$tempfile") {
		$ADDR = $line.Split(",")
		$status = $ADDR[0]
		$nodeCount = $ADDR[1]
		$tempString = "{0,20} {1,20}" -f "$status", "$nodeCount"
		$tempString
		$tempString | Out-File -Append $reportfile
	}

	# Delete previous SQL tempfile File for new SQL
	if (Test-Path -path $tempfile)
	{
		Remove-Item -Path $tempfile
	}

	$sql = "$sql WITH UR FOR READ ONLY"
	$result = (.\dsmadmc -id="$id" -password="$password" -COMMAdelimited -DATAONLY=YES -DISPLaymode=TABle -optfile="$dsmoptfile" -outfile="$tempfile" "$sql")

	$tempString = "`nDetailed status of certificate distribution for all processed clients / nodes :`n"
	$tempString | Out-File -Append $reportfile

	"{0,20} {1,20} {2,20} {3,20}" -f "DOMAIN", "PLATFORM", "CLIENT NAME", "STATUS" | Out-File -Append $reportfile
	"------------------------------------------------------------------------------------" | Out-File -Append $reportfile

	foreach($line in Get-Content "$tempfile") {
		$ADDR = $line.Split(",")
		$domainName = $ADDR[0]
		$platformCode = $ADDR[1]
		$clientName = $ADDR[2]
		$status = $ADDR[3]
		"{0,20} {1,20} {2,20} {3,20}" -f "$domainName", "$platformCode", "$clientName", "$status" | Out-File -Append $reportfile
	}
	
	$out = "`nThe detailed status report is : $reportfile.`n"
	$out += "`n"
	$out += ">> Any status other than 'Completed' indicates a failure.`n"
	$out += ">> Client nodes with status 'Missed' specifies that the scheduled startup window is already passed.`n"
	$out += ">> Client nodes with status 'Future' specifies that the beginning of the startup window is in the future.`n"
	$out += ">> For 'Missed' and 'Future' status there is a chance that they will catch up as these schedules will be re-run on a daily basis.`n"
	$out += ">> Please regularly monitor the progress of certificate distribution status, by executing this script in Report mode for a couple of days.`n"
	$out += ">> Client nodes that are still in failed state, it is recommended to follow the manual steps for adding the certificate.`n"
	$out += ">>     1. Copy the new certificate file over to the client box.`n"
	$out += ">>     2. Execute below command to add the certificate.`n"
	$out += ">>        gsk8capicmd_64 -cert -add -label `"<<New Certificate Label>>`" -file `"<<New Certificate File Path>>`" -db dsmcert.kdb -stashed`n"
	$out += ">>        Tip: The dsmcert.kdb file is located in client installation directory. On Unix, Linux and Mac systems, if client sessions were ever started from a non-root user, copies of the certificate can be located in `$HOME/IBM/StorageProtect/certs/ or in the directory determined by the PASSWORDDIR client option."

	$out
	$out | Out-File -Append $logfile
}

function distribute_cleanup()
{
	# Remove old macro if has any
	if (Test-Path -path $macrofile)
	{
		Remove-Item -Path $macrofile
	}

	$certLinesCount=(Get-Content $newcertfile).Length

	# Again checking for validity of certificate text.
	# WHETHER TODO ? First line and last line check or based on number of lines ?
	# Currently we are checking this using number of lines in the certificate file.
	# CA Signed certificate has 26 lines and Self Signed certificateh has 21 lines it it.

	if (!($certLinesCount -ge $minCertLines -And $certLinesCount -le $maxCertLines)){
		$certLinesError = "`nNumber of Lines in certificate file $newcertfile exceed the supported limit.`n"
		$certLinesError | Out-File -Append $logfile
		$certLinesError
		exit
	}

	# Schedule count.
	$schedcount = ""
	if ($certLinesCount -eq $minCertLines){
		$schedcount = 3
	}
	elseif ($certLinesCount -gt $minCertLines -And $certLinesCount -le $maxCertLines){
		$schedcount = 4
	}

	$delschebase = "delete sched DOMAIN_NAME SCHED_NAME_PLATFORM_NAME"
	$unixDone = 0
	$preDom = ""
	foreach ($i in $domainlist)
	{
		$dom = $i.Split(",")
		$delcmd = $delschebase.replace("DOMAIN_NAME", $dom[0])
		if ($dom[1] -eq $platformstrwin -or $dom[1] -eq $platformstrlnx -or $dom[1] -eq $platformstraix -or $dom[1] -eq $platformstrmac)
		{
			for ($k=0;$k -le $schedcount; $k++)
			{
				$delcmd.replace("PLATFORM_NAME", $dom[1]).replace("SCHED_NAME", $schednamebase+$k) | Out-File -Encoding ASCII -Append $macrofile
			}

			# Add one more schedule because we have 2 schedules for GSKit for Windows client.
			if ($dom[1] -eq $platformstrwin){
				$gskschedidx = $schedcount + 1
				$delcmd.replace("PLATFORM_NAME", $dom[1]).replace("SCHED_NAME", $schednamebase+$gskschedidx) | Out-File -Encoding ASCII -Append $macrofile
			}
		}
		else
		{
			# Platform TBD line, skip it so far
		}
	}	

	# Run delete macrofile
	$result = (.\dsmadmc -id="$id" -password="$password" -optfile="$dsmoptfile" -outfile="$macroDELETEcmdOutputFile" -ITEMCOMMIT macro "$macrofile")
	$result | Select-String "ANS8002I"

	# Log admadmc result
	$result | Out-File -Append $logfile

	$out  = "`n>> Cleanup Completed.`n"
	$out += ">> A return code other than 0 indicates an error. For more information, take a look at the log file.`n"
	$out += ">> The log file is located at $logfile"

	$out
	$out | Out-File -Append $logfile
}

function print_usage()
{
	$out  = "Unknown Action type: $action`n"
	$out += "To start a certification distribute job:`n"
	$out += "  powershell .\cert_distribute.ps1 -id dsmadmc_id -password dsmadmc_password -action $actiondistribute`n"
	$out += "To monitor status of existing certification distribute job:`n"
	$out += "  powershell .\cert_distribute.ps1 -id dsmadmc_id -password dsmadmc_password -action $actionreport`n"
	$out += "To cleanup existing certification distribute job:`n"
	$out += "  powershell .\cert_distribute.ps1 -id dsmadmc_id -password dsmadmc_password -action $actioncleanup`n"

	$out
	$out | Out-File -Append $logfile
}


# Main
# ----------------

if ($action -eq $actiondistribute)
{
	distribute_new
}
elseif ($action -eq $actionreport)
{
	distribute_report
}
elseif ($action -eq $actioncleanup)
{
	distribute_cleanup
}
else
{
	print_usage
}

cd $workingdir
