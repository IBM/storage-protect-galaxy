exit;    # This script is destructive, so by default it exits.  Comment-out this line to proceed.

#!/usr/bin/perl
#********************************************************************************
# IBM Storage Protect
# 
# name: sp_cleanup
#
# desc: CAUTION:
#       The script sp_cleanup.pl can be used to completely clenaup and remove 
#       a IBM Storage Protect server that was configured using the blueprint configuration script.
#       This script is destructive and should only be used for troubleshooting purposes 
#       during initial testing of the blueprint script.  This script depends on the 
#       existence of the file named serversetupstatefileforcleanup.txt which is generated
#       by the script sp_config.pl.  The state file is only generated when 
#       sp_cleanup.pl exists in the same directory as sp_config.pl when 
#       it is run.
#
#       To use this script:

#       1) Edit sp_cleanup.pl and comment-out the exit on the first line
#       2) Copy sp_cleanup.pl into the same folder where sp_config.pl is located
#          prior to running sp_config.pl
#       3) perl sp_config.pl
#       4) perl sp_cleanup.pl
#
# usage:  perl sp_cleanup.pl
#
# Notice: This program is provided as a tool intended for use by IBM Internal, 
#         IBM Business Partners, and IBM Customers. This program is provided as is, 
#         without support, and without warranty of any kind expressed or implied.
#
# (C) Copyright International Business Machines Corp. 2013, 2022
#********************************************************************************
$versionString = "Program version 5.1";

use Cwd;

$platform = getPlatform();

$SS = getpathdelimiter($platform);

if ($platform eq "WIN32")
{
  $systemdrive = $ENV{SYSTEMDRIVE};
}

$statefile = "serversetupstatefileforcleanup.txt";

$currentdir = Cwd::cwd();

# If Linux, determine whether running SLES
$isSLES = 0;
$isUbuntu = 0;
if ($platform =~ m/LINUX/)
{
  if (-f "/etc/SuSE-release")
  {
    $isSLES = 1;
  }
  else
  {
    $uName = `uname -a`;
    if ($uName =~ m/Ubuntu/)
    {
      $isUbuntu = 1;
    }
  }
}

print "\n*-----------------------------------------------------------------------*\n";
print "** Beginning IBM Storage Protect blueprint cleanup script.\n";
print "** $versionString\n";

if ($platform eq "WIN32")
{
  $currentdir =~ s#/#\\#g;
}

if ( -f $statefile )
{
  initializeHash(); 
  populateHash();  # reset the hash contents from the information in the state file

  $stepnumber = $stateHash{laststep}; 
  $serverPath = $stateHash{serverpath};
  $db2Path = $stateHash{db2path}; 
  if ($platform eq "WIN32")
  {
    $db2cmdPath = $stateHash{db2cmdpath};
    $db2exePath = $stateHash{db2exepath};
  }
}
else
{
  print "ERROR: Unable to locate the state file $statefile.  The cleanup is unable to continue.\n";
  die;
}

if (exists $stateHash{db2user})
{
  print "\n!! WARNING: This script will cleanup the IBM Storage Protect server and all stored data\n";
  print "  for the instance running under the DB2 instance $stateHash{db2user}.\n";
  print "  Do not continue unless you are absolutely certain there is no data you need to save.\n";
  print "  To continue, enter 'YES' in uppercase, or 'quit'\n";
  $userinput="NO";
  while (($userinput ne "YES") && ($userinput !~ m/quit/i))
  {
    $userinput = "";
    print "  Continue? : ";
    $userinput = <STDIN>;
    chomp($userinput);
  }
  if ($userinput eq "quit")
  {
    print "Quitting ...\n";
    exit (1);
  }
}
else
{
  print "ERROR: DB2 user is not defined in the state file.  The cleanup is unable to continue.\n";
  die;
}

@instancedirfilestodelete = ("cert256.arm", "cert.arm", "cert.crl", "cert.kdb", "cert.rdb", "cert.sth",
                             "cit.log", "citScanOutput.xml", "devconf.dat", "dsmffdc.log", "dsmserv.dbid",
                             "dsmserv.opt", "dsmserv.v6lock", "NODELOCK", "tsmdbmgr.log", "tsmdbmgr.opt",
                             "tsmdbmgr.env", "TSM.PWD", "volhist.dat");

# we need to get the list of mounted filesystems

@mountedfs = ();  # to save the list of mounted filesystems
@mountedgpfs = (); # to save the list of mounted GPFS filesystems 

if (($platform eq "LINUX86") || ($platform eq "AIX") || ($platform =~ m/LINUXPPC/))
{
  @mountOut = `mount`;
}
elsif ($platform eq "WIN32")
{
  @mountVolOut = `mountvol`;
}

if (($platform eq "LINUX86") || ($platform eq "AIX") || ($platform =~ m/LINUXPPC/))
{
  foreach $mntpnt (@mountOut)
  {
    if ( (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
	  	  && (($mntpnt =~ m#^/dev\S+\s+on\s+(\S+)\s+type\s+ext3\s+\((\S+)\)#) ||
              ($mntpnt =~ m#^/dev\S+\s+on\s+(\S+)\s+type\s+ext4\s+\((\S+)\)#) ||
              ($mntpnt =~ m#^/dev\S+\s+on\s+(\S+)\s+type\s+xfs\s+\((\S+)\)#)) )
    {
      $mpt = $1;
      push(@mountedfs, $mpt);
           
    }
    elsif ( (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
	  	 && ($mntpnt =~ m#^/dev\S+\s+on\s+(\S+)\s+type\s+gpfs\s+\((\S+)\)#) ||
                    ($mntpnt =~ m#/dev\S+\s+(\S+)\s+mmfs\s+.*\s+(\S+dev\S+)#) )
    {
      $mpt = $1;
      push(@mountedgpfs, $mpt);
    }
    elsif (($platform eq "AIX") && ($mntpnt =~ m#^\s*/dev\S+\s+(\S+)\s+jfs2#))
    {
      push(@mountedfs, $1);
    }
  }
}

if ($platform eq "WIN32")
{
  
  foreach $mntvolline (@mountVolOut)
  {
    if (($mntvolline !~ m/\\\\/) && ($mntvolline =~ m/\s+(\w:\S*)\\$/))
    {
      push(@mountedfs, $1);
    }
  }
}
 
if ((exists $stateHash{db2user}) && ((userexists($stateHash{db2user})) == 1))
{
  $db2usr = $stateHash{db2user};
  $db2homedir = $stateHash{db2home};

  # Check if server is running

  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
  {
    $serverisrunning = 0;

    $psdsmservCommand = "ps -ef | grep dsmserv";

    @psdsmservOut = `$psdsmservCommand`;

    foreach $psline (@psdsmservOut)
    {
      if ($psline =~ m#^${db2usr}\s+(\d+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+/opt/tivoli/tsm/server/bin/dsmserv#)
     {
        $serverisrunning = 1;
        $dsmservprocid = $1;
      }
    }
  }
  if ($platform eq "WIN32")
  {
    $serverisrunning = 0;

    $qdsmservserviceCommand = "tasklist";

    @qdsmservserviceOut = `$qdsmservserviceCommand`;

    foreach $qtaskline (@qdsmservserviceOut)
    {
      if ($qtaskline =~ m#^dsmsvc.exe#)
      {
        $serverisrunning = 1;
      }
    }
  }

  if ($serverisrunning == 1)
  {
    print "Stopping the IBM Storage Protect server. Please be patient . . .\n";

    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
    {
      $killservercmd = "kill $dsmservprocid";
      print "Issuing command: $killservercmd\n";
      system("$killservercmd");

      do
      {
        $serverStopped = 1;
      
        sleep 5;
      
        @psdsmservOut = `$psdsmservCommand`;

        foreach $psline (@psdsmservOut)
        {
          if ($psline =~ m#/opt/tivoli/tsm/server/bin/dsmserv#)
          {
            $serverStopped = 0;
          }
        }
      } while ($serverStopped == 0);

    }
    elsif ($platform eq "WIN32")
    {
      $stopdsmservservicecmd = "net stop \"TSM server_${db2usr}\"";
      print "Issuing command: $stopdsmservservicecmd\n";
      system("$stopdsmservservicecmd");
      
      do
      {
        $serverStopped = 1;
        sleep 5;
  
        @qdsmservOut = `$qdsmservserviceCommand`;

        foreach $qline (@qdsmservOut)
        {
          if (($qline =~ m#dsmsvc.exe#) || ($qline =~ m#db2stop.exe#) || ($qline =~ m#db2sysc.exe#))
          {
            $serverStopped = 0;
          }
        }
      } while ($serverStopped == 0);
    }
    print "Server is stopped\n";
  }

  $instprocs = 0;
  # Perform a final check to see if other processess are running under the instance user
  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
  {
    $psdsmservCommand = "ps -ef | grep $stateHash{db2user}";

    @psdsmservOut = `$psdsmservCommand`;

    foreach $psline (@psdsmservOut)
    {
      if ($psline =~ m#^$stateHash{db2user}\s+(\d+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)#)
      {
        print "ERROR: Process still running as $stateHash{db2user} pid: $1 \($2\)\n";
        $instprocs++;
      }
    }
  }
  if ($platform eq "WIN32")
  {
    $qdsmservserviceCommand = "tasklist";

    @qdsmservserviceOut = `$qdsmservserviceCommand`;

    foreach $qtaskline (@qdsmservserviceOut)
    {
      if ($qtaskline =~ m#^dsmsvc.exe# || $qtaskline =~ m#^servermon.exe# || $qtaskline =~ m#^db2syscs.exe#)
      {
        print "ERROR: Process still running: $qtaskline\n";
        $instprocs++;
      }
    }
  }
  if ($instprocs > 0)
  {
    print "ERROR: There are still $instprocs conflicting processes running\n";
    print "After manually stopping these processes, run the cleanup script again\n";
    exit 1;
  }

  # Cleanup the IBM Storage Protect service

  $tsmservicefound == 0;
  
  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
  {
    if ($isSLES == 1 || $isUbuntu == 1)
    {
      $servicescript = "/etc/init.d/${db2usr}";
    }
    else
    {
      $servicescript = "/etc/rc.d/init.d/${db2usr}";
    }

    if ($isUbuntu)
    {
      $listservicecmd = "invoke-rc.d $db2usr status";

      print "Issuing command: $listservicecmd\n";
      @chkconfigListOut = `$listservicecmd`;

      foreach $chkconfigListOutline (@chkconfigListOut)
      {
        if ($chkconfigListOutline =~ m/$db2usr.*preset:\s+enabled/) 
        {
          $tsmservicefound = 1;
        }
      }
    }
    else
    {
      $listservicecmd = "chkconfig --list $db2usr";

      print "Issuing command: $listservicecmd\n";
      @chkconfigListOut = `$listservicecmd`;

      foreach $chkconfigListOutline (@chkconfigListOut)
      {
        if ($chkconfigListOutline =~ m/$db2usr\s+\d:\w+\s+\d:\w+\s+\d:\w+\s+\d:\w+\s+\d:\w+\s+\d:\w+\s+\d:\w+/)
        {
          $tsmservicefound = 1;
        }
      }
    }
  } 
  elsif ($platform eq "AIX")
  {
    if (exists $stateHash{instdirmountpoint})
    {
      $instancedirectory = $stateHash{instdirmountpoint};  

      $inittabfile = "/etc/inittab";
  
      if (open(INITTABH, "<$inittabfile"))
      {
        @inittabcontents = <INITTABH>;
        close INITTABH;
      }  

      sleep 1;

      open(INITTABH, ">$inittabfile");
      
      foreach $inittabline (@inittabcontents)
      {
        if ($inittabline !~ m#tsm1:2:once:/opt/tivoli/tsm/server/bin/rc.dsmserv\s+-u\s+$db2usr\s+-i\s+$instancedirectory#)
        {
          print INITTABH "$inittabline";
        }
      }
     
      close INITTABH;
    }
  }
  elsif ($platform eq "WIN32")
  { 
    $qservicecmd = "sc query \"TSM server_${db2usr}\"";

    @qserviceOut = `$qservicecmd`;

    foreach $qserviceOutline (@qserviceOut)
    {
      if ($qserviceOutline =~ m/SERVICE_NAME:\s+TSM\s+server_${db2usr}/)
      {
        $tsmservicefound = 1;
      }
    }
  }

  if ($tsmservicefound == 1)
  {
    print "Removing the $db2usr service\n";

    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
    {
      if ($isUbuntu)
      {
        $delservicecmd = "update-rc.d $db2usr remove";
        print "Issuing command: $delservicecmd\n";
        system("$delservicecmd");

        print "Removing the $db2usr service script\n";
        print "Issuing command: rm $servicescript\n";
        system("rm $servicescript");
      }
      else
      {
        $delservicecmd = "chkconfig --del $db2usr";
        print "Issuing command: $delservicecmd\n";
        system("$delservicecmd");

        print "Removing the $db2usr service script\n";
        print "Issuing command: rm $servicescript\n";
        system("rm $servicescript");
      }
    }
    elsif ($platform eq "WIN32")
    {
      $delservicecmd = "sc delete \"TSM server_${db2usr}\"";
      print "Issuing command: $delservicecmd\n";
      system("$delservicecmd");
    }
  }
  elsif ((($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/)) && ( -f $servicescript ))
  { 
    print "Removing the $db2usr service script\n";
    print "Issuing command: rm $servicescript\n";
    system("rm $servicescript");
  }

  #
  # Remove the TSMDB1 database if it exists
  #

  $tsmdb1found = 0;

  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
  {
    $listdbdircmd = "su - $db2usr -c \"db2 list db directory\"";
  }
  elsif ($platform eq "WIN32")
  {
    $listdbdircmdfile = "${currentdir}${SS}listdbdircmdfile.bat";
    
    $listdbdircmd = "$db2exePath list db directory";

    if (open(LISTDBDIRH, ">$listdbdircmdfile"))
    {
      print LISTDBDIRH "\@echo off\n";
      print LISTDBDIRH "set db2instance=${db2usr}\n";
      print LISTDBDIRH "$db2cmdPath /c /w /i $listdbdircmd\n";  
      close LISTDBDIRH;
    }
  }

  print "Issuing command: $listdbdircmd\n";

  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
  {
    @listdbdircmdOut = `$listdbdircmd`;
  }
  elsif ($platform eq "WIN32")
  {
    @listdbdircmdOut = `$listdbdircmdfile`;
  }

  foreach $listdbdirlne (@listdbdircmdOut)
  {
    if ($listdbdirlne =~ m/Database\s+name\s+=\s+TSMDB1/)
    {
      $tsmdb1found = 1;
    }
  }

  if ($tsmdb1found == 1)
  {
    $tsmdbsuccessfullyremoved = 0;

    print "Removing the TSMDB1 database\n";
    $respfile = "$currentdir" . "${SS}" . "response.txt";
    open (RESPFH, ">$respfile") or die "Unable to open $respfile\n";
    print RESPFH "y\n";
    close RESPFH;

    $instancedirectory = $stateHash{instdirmountpoint};
    $dsmservoptfile = "${instancedirectory}" . "${SS}" . "dsmserv.opt";

    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
    {
      $removedbcmd0 = "/opt/tivoli/tsm/server/bin/dsmserv -o $dsmservoptfile -i $instancedirectory removedb TSMDB1";
      $removedbcmd = "su - $db2usr -c \"${removedbcmd0}\"";
    }
    elsif ($platform eq "WIN32")
    {
      $removedbcmdfile = "$currentdir" . "${SS}" . "removetsmdb.bat";
      $removedbcmd = "${serverPath}${SS}dsmserv -k $db2usr -o $dsmservoptfile removedb TSMDB1";

      if (open(RMDBH, ">$removedbcmdfile"))
      {
        print RMDBH "\@echo off\n";
        print RMDBH "set PATH=%PATH%;$db2Path${SS}bin\n";
        print RMDBH "$removedbcmd < \"$respfile\"\n";
        close RMDBH;
      }
    }
    print "Issuing command: $removedbcmd\n";

    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
    { 
      @removedbcmdOut = `$removedbcmd < \"$respfile\"`;
    }
    elsif ($platform eq "WIN32")
    {
      @removedbcmdOut = `$removedbcmdfile`;
    }
    foreach $rmdbln (@removedbcmdOut)
    {
      print "$rmdbln\n";
      if ($rmdbln =~ m/Database\s+TSMDB1\s+was\s+removed\s+successfully/)
      {
        $tsmdbsuccessfullyremoved = 1;
      }
    }

    if ($tsmdbsuccessfullyremoved == 1)
    {
      print "TSMDB1 was successfully removed\n";
    }
    else
    {
#      die "There was an problem removing the TSMDB1 database\n";
    }
  }
 
  # Check if instance exists
  # if so drop the instance
   
  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
  {
    $listInstCmd = "/opt/tivoli/tsm/db2/instance/db2ilist";
  }
  elsif ($platform eq "WIN32")
  {
    $listInstCmd = "${db2Path}${SS}bin${SS}db2ilist";
  }

  $instanceexists = 0;

  print "Issuing command: $listInstCmd\n";

  @listInstCmdOut = `$listInstCmd`;

  foreach $outln (@listInstCmdOut)
  {
    if ((($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX")) && ($outln =~ m/$db2usr/))
    {
      $instanceexists = 1;
    }
    elsif (($platform eq "WIN32") && ($outln =~ m/$db2usr/i))
    {
      $instanceexists = 1;
    }
  }

  if ($instanceexists == 1)
  {
    # drop the instance

    print "Dropping the $db2usr instance\n";

    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
    {
      $dropInstCmd = "/opt/tivoli/tsm/db2/instance/db2idrop $db2usr";
    }
    elsif ($platform eq "WIN32")
    {
      $dropInstCmd = "${db2Path}${SS}bin${SS}db2idrop $db2usr";
    }

    print "Issuing command: $dropInstCmd\n";

    @dropInstCmdOut = `$dropInstCmd`;  
    foreach $drpinstln (@dropInstCmdOut)
    {
      print "$drpinstln\n";
    }  
  }
  
  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
  {
    $clientoptionfile = "/opt/tivoli/tsm/client/api/bin64/dsm.sys";
    $clientoptionfile2 = "/opt/tivoli/tsm/server/bin/dbbkapi/dsm.sys";

    if ( -f $clientoptionfile )
    {
      print "Removing the dsm.sys file under ../client/api/bin64\n";
      print "Issuing command: rm $clientoptionfile\n";
      system("rm $clientoptionfile");
    }

    if ( -f $clientoptionfile2 )
    {
      print "Removing the dsm.sys file under ../server/bin/dbbkapi\n";
      print "Issuing command: rm $clientoptionfile2\n";
      system("rm $clientoptionfile2");
    }

    print "Removing $db2usr entries from the limits.conf file\n";

    $limitsconffile = "/etc/security/limits.conf";

    if (open(LIMITSH, "<$limitsconffile"))
    {
      @limitsconfilecontents = <LIMITSH>;
      close LIMITSH;
    }

    unlink($limitsconffile);

    if (open(LIMITSH, ">$limitsconffile")) 
    {
      foreach $limitsfileline (@limitsconfilecontents)
      {
        if ($limitsfileline !~ m/^$db2usr/)
        {
          print LIMITSH "$limitsfileline";
        }
      }
    }

    print "Chowning all paths back to root:root\n";

    chownPaths();
  }
  if ($platform eq "AIX")
  {
    print "Chowning all paths back to root:system\n";

    chownPaths();
  }
  if ($platform eq "WIN32")  # Remove the registry key for the server instance
  {
    $queryserverinstancekeycmd = "reg query HKLM${SS}SOFTWARE${SS}IBM${SS}ADSM${SS}CurrentVersion${SS}Server${SS}${db2usr}";

    $serverinstancekeyfound = 1;

    $registryqueryoutfile = "${currentdir}${SS}regqueryout.txt";

    system("$queryserverinstancekeycmd 2> \"$registryqueryoutfile\"");

    if (open(ERRH, "<$registryqueryoutfile"))
    {
      while (<ERRH>)
      {
        if ($_ =~ m/ERROR:\s+The\s+system\s+was\s+unable\s+to\s+find\s+the\s+specified\s+registry\s+key\s+or\s+value/)
        {
          $serverinstancekeyfound = 0;
        }
      }
      close ERRH;
    }
    
    if ($serverinstancekeyfound == 1)
    {
      print "Removing registry key associated with server instance $db2usr\n";

      $delserverinstancekeycmd = "reg delete HKLM${SS}SOFTWARE${SS}IBM${SS}ADSM${SS}CurrentVersion${SS}Server${SS}${db2usr} /f";

      print "Issuing command: $delserverinstancekeycmd\n";
      
      system("$delserverinstancekeycmd");
    }
  }
    
  # remove the user and group, if it was created by the configuration script

  $userscreatedbyconfigArrayRef = $stateHash{createdusers};
  $numberofcreatedusers = @{$userscreatedbyconfigArrayRef};

  foreach $usr (@{$userscreatedbyconfigArrayRef})
  {
    print "Removing the user $usr\n";

    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
    {
      $delusercmd = "userdel -r $usr";
    }
    elsif ($platform eq "WIN32")
    {
      $delusercmd = "net user $usr /delete";
    }
    print "Issuing command: $delusercmd\n";
    system("$delusercmd");

    # remove the user home directory if it is not already removed

    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
    {
      if (($usr eq "$db2usr") && ( -d $db2homedir ))
      {
        print "Removing the $db2usr user home directory\n";

        $deluserhomedircmd = "rm -rf $db2homedir";
        print "Issuing command: $deluserhomedircmd\n";
        system("$deluserhomedircmd");
      }
    }
  }
}

# Perform a final check that the DB2 instance does not exist before performing any further cleanup to avoid cases
# where an error was missed above so we do not remove files when they are still needed
  
if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
{
  $listInstCmd = "/opt/tivoli/tsm/db2/instance/db2ilist";
}
elsif ($platform eq "WIN32")
{
  $listInstCmd = "${db2Path}${SS}bin${SS}db2ilist";
}

$instanceexists = 0;

print "Issuing command: $listInstCmd\n";

@listInstCmdOut = `$listInstCmd`;

foreach $outln (@listInstCmdOut)
{
  if ((($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX")) && ($outln =~ m/$db2usr/))
  {
    $instanceexists = 1;
  }
  elsif (($platform eq "WIN32") && ($outln =~ m/$db2usr/i))
  {
    $instanceexists = 1;
  }
}

if ((exists $stateHash{db2group}) && ((groupexists($stateHash{db2group})) == 1) && ($instanceexists == 0))
{
  $groupscreatedbyconfigArrayRef = $stateHash{createdgroups};
  $numberofcreatedgroups = @{$groupscreatedbyconfigArrayRef};

  foreach $grp (@{$groupscreatedbyconfigArrayRef})
  {
    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
    {
      print "Removing the $grp group\n";
      $delgroupcmd = "groupdel $grp";
      print "Issuing command: $delgroupcmd\n";
      system("$delgroupcmd");
    }
    elsif ($platform eq "AIX")
    {
      print "Removing the $grp group\n";
      $delgroupcmd = "rmgroup $grp";
      print "Issuing command: $delgroupcmd\n";
      system("$delgroupcmd");
    }
  }
}

if ($instanceexists == 0)
{
  if ($platform eq "WIN32")
  { 
    if ( -f $listdbdircmdfile )
    {
      unlink($listdbdircmdfile);
    }
    if ( -f $registryqueryoutfile )
    {
      unlink($registryqueryoutfile);
    }
    if ( -f $removedbcmdfile )
    {
      unlink($removedbcmdfile);
    }
  }
  unlink($respfile);

  # remove directories created by config script, in reverse order to that in which they were created

  $dirscreatedbyconfigArrayRef = $stateHash{createddirs};
  $numberofcreateddirs = @{$dirscreatedbyconfigArrayRef};

  for ($l = ($numberofcreateddirs - 1); $l >= 0; $l--)
  { 
    $dirtoremove = $dirscreatedbyconfigArrayRef->[$l];
    if ( -d $dirtoremove )
    {
      cleanupdir($dirtoremove);
      $rmdircmd = "rmdir $dirtoremove";
      print "Issuing command: $rmdircmd\n";
      system("$rmdircmd");   
    }
  }

  # cleanup the contents of the active log and archive log

  print "Cleaning up the active log directory\n";
  if (exists $stateHash{actlogpath})
  {
    $activelogpath = $stateHash{actlogpath};

    if ( -d $activelogpath )
    {
      cleanupdir($activelogpath);
    }
  }

  print "Cleaning up the archive log directory\n";

  if (exists $stateHash{archlogpath})
  {
    $archivelogpath = $stateHash{archlogpath};

    if ( -d $archivelogpath )
    {
      cleanupdir($archivelogpath);
    }
  }
  
  # cleanup the contents of the IBM Storage Protect DB directories

  print "Cleaning up the DB backup directories\n";

  $dbdirpathArrayRef = $stateHash{dbdirpaths};

  foreach $p (@{$dbdirpathArrayRef})
  {
    if ( -d $p )
    {
      cleanupdir($p);
    }
  }   

  # cleanup the contents of the IBM Storage Protect DB backup directories

  print "Cleaning up the DB backup directories\n";

  $dbbackdirpathArrayRef = $stateHash{dbbackdirpaths};

  foreach $p (@{$dbbackdirpathArrayRef})
  {
    if ( -d $p )
    {
      cleanupdir($p);
    }
  }   

  # cleanup the contents of the IBM Storage Protect storage directories

  print "Cleaning up the IBM Storage Protect storage directories\n";

  $tsmstgpathArrayRef = $stateHash{tsmstgpaths};

  foreach $p (@{$tsmstgpathArrayRef})
  { 
    if ( -d $p )
    {
      cleanupdir($p);
    }     
  }

  # cleanup the server instance directory

  if (exists $stateHash{instdirmountpoint})
  {
    $instancedirectory = $stateHash{instdirmountpoint};

    # if the instance directory still exists at this point, just remove server files under the instance directory

    if ( -d $instancedirectory )
    {
      foreach $srvfile (@instancedirfilestodelete)
      {
        $srvfilefullpath = "$instancedirectory" . "${SS}" . "$srvfile";

        if ( -f $srvfilefullpath )
        {
          if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
          {
            $rmcmd = "rm $srvfilefullpath";
          }
          elsif ($platform eq "WIN32")
          {
            $rmcmd = "del $srvfilefullpath";
          }
          print "Issuing command: $rmcmd\n";
          system("$rmcmd");
        }
      }
        
      if (exists $stateHash{db2user})
      {
        $db2usr = $stateHash{db2user};

        $db2usrsubdir = "$instancedirectory" . "${SS}" . "$db2usr";

        if ( -d $db2usrsubdir )
        {
          cleanupdir($db2usrsubdir);

          $rmdircmd = "rmdir $db2usrsubdir";
          print "Issuing command: $rmdircmd\n";
          system("$rmdircmd");
        }
      }
    }
  }


  # With client levels of 8.1.2 and newer, SSL keys may have been stashed that will be invalid
  # after the server is cleaned up. Clear out the client SSL keys records

  if ($platform =~ m/LINUX/)
  {
    $clientDir = "/opt/tivoli/tsm/client/ba/bin";
    if ( -f $clientDir."/dsmcert.idx" )
    {
      print "Removing the dsmcert.idx, dsmcert.kdb, and dsmcert.sth in the baclient directory\n";
      unlink($clientDir."/dsmcert.idx");
      unlink($clientDir."/dsmcert.kdb");
      unlink($clientDir."/dsmcert.sth");
    }
  }
  elsif ($platform eq "AIX")
  {
    $clientDir = "/usr/tivoli/tsm/client/ba/bin64";
    if ( -f $clientDir."/dsmcert.idx" )
    {
      print "Removing the dsmcert.idx, dsmcert.kdb, and dsmcert.sth in the baclient directory\n";
      unlink($clientDir."/dsmcert.idx");
      unlink($clientDir."/dsmcert.kdb");
      unlink($clientDir."/dsmcert.sth");
    }
  }
  elsif ($platform eq "WIN32")
  {
    $clientDir = "c:\\program files\\tivoli\\tsm\\baclient";
    $admindDir = "c:\\ProgramData\\Tivoli\\TSM\\baclient\\Nodes\\ADMIN";
    $dbbDir = "c:\\ProgramData\\Tivoli\\TSM\\baclient\\Nodes\\\$\$_TSMDBMGR_\$\$";
    print "Removing the dsmcert.idx, dsmcert.kdb, and dsmcert.sth in the baclient and ADMIN directories\n";
    unlink($clientDir."\\dsmcert.idx");
    unlink($clientDir."\\dsmcert.kdb");
    unlink($clientDir."\\dsmcert.sth");
    unlink($admindDir."\\spclicert.idx");
    unlink($admindDir."\\spclicert.kdb");
    unlink($admindDir."\\spclicert.sth");
    unlink($admindDir."\\spclicert.crl");
    unlink($admindDir."\\spclicert.rdb");
    unlink($dbbDir."\\spclicert.idx");
    unlink($dbbDir."\\spclicert.kdb");
    unlink($dbbDir."\\spclicert.sth");
    unlink($dbbDir."\\spclicert.crl");
    unlink($dbbDir."\\spclicert.rdb");
  }
}  # end of section that requires DB2 instance not to exist

#################################################################################################

sub chownPaths
{
  @chownedpaths = ();  # needed to keep track of paths already chowned, to avoid redundant chowns

  if (exists $stateHash{instdirmountpoint})
  {
    $instdirmntpnt = $stateHash{instdirmountpoint};
  }
  else
  {
    $instdirmntpnt = "";
  }

  if (exists $stateHash{actlogpath})
  {
    $actlogpth = $stateHash{actlogpath};
  }
  else
  {
    $actlogpth = "";
  }

  if (exists $stateHash{archlogpath})
  {
    $archlogpth = $stateHash{archlogpath};
  }
  else
  {
    $archlogpth = "";
  }

  $dbbackdir = $stateHash{dbbackDir};
  $dbdirpths = $stateHash{dbdirpaths};
  $tsmstgpths = $stateHash{tsmstgpaths};
  $dbbackdirpths = $stateHash{dbbackdirpaths};
  $db2usr = $stateHash{db2user};
  $db2homedir = $stateHash{db2home};

  if (($instdirmntpnt ne "") && (issubpath($instdirmntpnt, "$db2homedir") == 0))   # only chown if the instance directory is not a subdirectory of the user's home directory
  {
    if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
    {
      $chowncmd = "chown -R root:root $instdirmntpnt";
    }
    elsif ($platform eq "AIX")
    {
      $chowncmd = "chown -R root:system $instdirmntpnt";
    }
    push(@chownedpaths, $instdirmntpnt);
    print "Issuing command: $chowncmd\n";
    system("$chowncmd");
  }
  
  if (($actlogpth ne "") && (issubpath($actlogpth, "$db2homedir") == 0))         # only chown if the active log directory is not a subdirectory of the user's home directory
  {                                                                              # and has not already been chowned
    $isalreadychowned = 0;

    foreach $p (@chownedpaths)
    {
      if (issubpath($actlogpth, $p) == 1)
      {
        $isalreadychowned = 1;
      }
    }

    if ($isalreadychowned == 0)
    {
      if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
      {
        $chowncmd = "chown -R root:root $actlogpth";
      }
      elsif ($platform eq "AIX")
      {
        $chowncmd = "chown -R root:system $actlogpth";
      }
      push(@chownedpaths, $actlogpth);
      print "Issuing command: $chowncmd\n";
      system("$chowncmd");
    }
  }

  if (($archlogpth ne "") && (issubpath($archlogpth, "$db2homedir") == 0))        # only chown if the archive log directory is not a subdirectory of the user's home directory
  {                                                                               # and has not already been chowned
    $isalreadychowned = 0;

    foreach $p (@chownedpaths)
    {
      if (issubpath($archlogpth, $p) == 1)
      {
        $isalreadychowned = 1;
      }
    }
 
    if ($isalreadychowned == 0)
    {
      if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
      {
        $chowncmd = "chown -R root:root $archlogpth";
      }
      elsif ($platform eq "AIX")
      {
        $chowncmd = "chown -R root:system $archlogpth";
      }
      push(@chownedpaths, $archlogpth);
      print "Issuing command: $chowncmd\n";
      system("$chowncmd");
    }
  }

  foreach $pth (@{$dbdirpths})
  {
    if (issubpath($pth, "$db2homedir") == 0) 
    { 
      $isalreadychowned = 0;

      foreach $p (@chownedpaths)
      {
        if (issubpath($pth, $p) == 1)
        {
          $isalreadychowned = 1;
        }
      }

      if ($isalreadychowned == 0)
      {
        if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
        {
          $chowncmd = "chown -R root:root $pth";
        }
        elsif ($platform eq "AIX")
        {
          $chowncmd = "chown -R root:system $pth";
        }
        push(@chownedpaths, $pth);
        print "Issuing command: $chowncmd\n";
        system("$chowncmd");
      }
    }
  }

  foreach $pth (@{$dbbackdirpths})
  {
    if (issubpath($pth, "$db2homedir") == 0) 
    { 
      $isalreadychowned = 0;

      foreach $p (@chownedpaths)
      {
        if (issubpath($pth, $p) == 1)
        {
          $isalreadychowned = 1;
        }
      }

      if ($isalreadychowned == 0)
      {
        if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
        {
          $chowncmd = "chown -R root:root $pth";
        }
        elsif ($platform eq "AIX")
        {
          $chowncmd = "chown -R root:system $pth";
        }
        push(@chownedpaths, $pth);
        print "Issuing command: $chowncmd\n";
        system("$chowncmd");
      }
    }
  }

  foreach $pth (@{$tsmstgpths})
  {
    if (issubpath($pth, "$db2homedir") == 0) 
    { 
      $isalreadychowned = 0;

      foreach $p (@chownedpaths)
      {
        if (issubpath($pth, $p) == 1)
        {
          $isalreadychowned = 1;
        }
      }

      if ($isalreadychowned == 0)
      {
        if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/))
        {
          $chowncmd = "chown -R root:root $pth";
        }
        elsif ($platform eq "AIX")
        {
          $chowncmd = "chown -R root:system $pth";
        }
        push(@chownedpaths, $pth);
        print "Issuing command: $chowncmd\n";
        system("$chowncmd");
      }
    }
  }
}

sub userexists
{
  $username = shift(@_);

  $usrexists = 0;

  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))
  {
    $catpasswdcmd = "cat /etc/passwd | grep $username";

    @catpasswdOut = `$catpasswdcmd`;

    foreach $catOut (@catpasswdOut)
    {
      if ($catOut =~ m/$username/)
      {
        $usrexists = 1;
      }
    }
  }
  elsif ($platform eq "WIN32")
  {
    $qusercmd = "net user $username";
    @qusercmdOut = `$qusercmd`;

    foreach $quserline (@qusercmdOut)  # Check if user exists
    {
      if ($quserline =~ m/^\S+\s+\S*\s*$username/)
      {
        $usrexists = 1;
      }
    }
  }
  return $usrexists;
}
  
sub groupexists
{
  $groupname = shift(@_);

  $grpexists = 0;

  $catgroupcmd = "cat /etc/group | grep $groupname";

  @catgroupOut = `$catgroupcmd`;

  foreach $catOut (@catgroupOut)
  {
    if ($catOut =~ m/$groupname/)
    {
      $grpexists = 1;
    }
  }

  return $grpexists;
}

############################################################
#      sub: initializeHash
#     desc: Initializes the state hash, including initializing
#           the arrays that will contain the list of db directories
#           and storage directories to empty arrays
#
#   params: none
#  returns: none
#
############################################################

sub initializeHash
{
  %stateHash = ();

  my $dbdirpathArrayRef = [];  # initialize reference to empty array for the db directories

  my $tsmstgpathArrayRef = [];  # initialize reference to empty array for the tsm storage directories

  my $dbbackdirpathArrayRef = [];  # initialize reference to empty array for the db backup directories

  my $dirscreatedbyconfigRef = [];  # initialize reference to empty array for created directories

  my $userscreatedbyconfigArrayRef = []; # initialize reference to users that are created by the script

  my $groupscreatedbyconfigArrayRef = []; # initialize reference to groups that are created by the script

  $stateHash{dbdirpaths} = $dbdirpathArrayRef;
  $stateHash{tsmstgpaths} = $tsmstgpathArrayRef;
  $stateHash{dbbackdirpaths} = $dbbackdirpathArrayRef;
  $stateHash{createddirs} = $dirscreatedbyconfigRef;
  $stateHash{createdusers} = $userscreatedbyconfigArrayRef;
  $stateHash{createdgroups} = $groupscreatedbyconfigArrayRef;
  $stateHash{runfile} = $runfilename;
  $stateHash{formatsuccessflag} = 0;
  $stateHash{startserversuccessflag} = 0;
}

############################################################
#      sub: populateHash
#     desc: Repopulates the state hash, from the state file contents;
#           this is called when the user restarts the script after
#           having quit with the intent to continue from
#           where he left off
#
#   params: none
#  returns: none
#
############################################################

sub populateHash
{
  $dbdirpthcnt = 0;
  $tsmstgpthcnt = 0;
  $dbbackdirpthcnt = 0;
  $createddirscnt = 0;
  $createduserscnt = 0;
  $createdgroupscnt = 0;

  $dbdirpathArrayRef = $stateHash{dbdirpaths};
  $tsmstgpathArrayRef = $stateHash{tsmstgpaths};
  $dbbackdirpathArrayRef = $stateHash{dbbackdirpaths};
  $dirscreatedbyconfigArrayRef = $stateHash{createddirs};
  $userscreatedbyconfigArrayRef = $stateHash{createdusers};
  $groupscreatedbyconfigArrayRef = $stateHash{createdgroups};
  
  open (STATEFH, "<$statefile") or die "Unable to open $statefile\n";
  while (<STATEFH>)
  {
    if ($_ =~ m/(\w+)\s+---\s+(\S+)/)
    {
      $thekey = $1;
      $thevalue = $2;

      if (($thekey ne "dbdirpath") && ($thekey ne "tsmstgpath") && ($thekey ne "dbbackdirpath") && ($thekey ne "createddir") && ($thekey ne "createduser") && ($thekey ne "createdgroup"))
      {
        $stateHash{$thekey} = $thevalue;
      }
      elsif ($thekey eq "dbdirpath")  # add the db directory paths to the db directory array
      {
        $dbdirpathArrayRef->[$dbdirpthcnt] = $thevalue;
        $dbdirpthcnt++;
      }
      elsif ($thekey eq "tsmstgpath") # add the tsm storage directory paths to the tsm storage directory array
      {
        $tsmstgpathArrayRef->[$tsmstgpthcnt] = $thevalue;
        $tsmstgpthcnt++;
      }
      elsif ($thekey eq "dbbackdirpath") # add the db backup directory paths to the db backup directory array
      {
        $dbbackdirpathArrayRef->[$dbbackdirpthcnt] = $thevalue;
        $dbbackdirpthcnt++;
      }
      elsif ($thekey eq "createddir")  # add the created directory paths to the created directories array
      {
        $dirscreatedbyconfigArrayRef->[$createddirscnt] = $thevalue;
        $createddirscnt++;
      }
      elsif ($thekey eq "createduser")  # add the created users to the created users array
      {
        $userscreatedbyconfigArrayRef->[$createduserscnt] = $thevalue;
        $createduserscnt++;
      }
      elsif ($thekey eq "createdgroup")  # add the created directory groups to the created groups array
      {
        $groupscreatedbyconfigArrayRef->[$createdgroupscnt] = $thevalue;
        $createdgroupscnt++;
      }
    }
  }
  close STATEFH;
}

# remove the contents of directory without removing lost+found

sub cleanupdir 
{
  my $dirtocleanup = shift(@_);
	
  opendir(DIRH, $dirtocleanup) or die "Cannot open directory $dirtocleanup\n";
  my @objList = readdir(DIRH);
  closedir(DIRH);

  if (($platform eq "LINUX86") || ($platform =~ m/LINUXPPC/) || ($platform eq "AIX"))	
  {
    foreach $item (@objList)
    {
      unless (("$item" eq ".") or ("$item" eq "..") or ("$item" eq "lost+found"))
      {
        my $itemPath;

        $itemPath = "$dirtocleanup" . "${SS}" . "$item";

        if ( -f $itemPath )
        {
          $rmcmd = "rm $itemPath";
          print "Issuing command: $rmcmd\n";
          system("$rmcmd");
        }
        elsif (( -d $itemPath ) && (isprefixofmountpoint($itemPath) == 0))
        {
          $rmcmd = "rm -rf $itemPath";
          if ($itemPath ne "/")
          {
            print "Issuing command: $rmcmd\n";
            system("$rmcmd");
          }
        }
        elsif (( -d $itemPath ) && (isprefixofmountpoint($itemPath) == 1))
        {
          cleanupdir($itemPath);
        }
      }
    }
  }
  elsif ($platform eq "WIN32")
  {
    foreach $item (@objList)
    {
      unless (("$item" eq ".") or ("$item" eq "..") or ("$item" eq "System Volume Information") or ("$item" eq "\$RECYCLE.BIN"))
      {
        my $itemPath;

        $itemPath = "$dirtocleanup" . "${SS}" . "$item";

        if ( -f $itemPath )
        {
          $rmcmd = "del $itemPath";
          print "Issuing command: $rmcmd\n";
          system("$rmcmd");
        }
        elsif (( -d $itemPath ) && (isprefixofmountpoint($itemPath) == 0))
        {
          $rmcmd = "rd /S /Q $itemPath";
          print "Issuing command: $rmcmd\n";
          system("$rmcmd");
        }
        elsif (( -d $itemPath ) && (isprefixofmountpoint($itemPath) == 1))
        {
          cleanupdir($itemPath);
        }
      }
    }
  }
}

sub isprefixofmountpoint
{
  $pth = shift(@_);
  
  my $isprefix = 0;

  foreach $mntpnt (@mountedfs)
  {
    my $currprefix = $mntpnt;

    if ($platform eq "WIN32")
    {
      if (uc($currprefix) eq uc($pth))
      {
        $isprefix = 1;
      }
    }
    else
    {
      if ("$currprefix" eq "$pth")
      {
        $isprefix = 1;
      }
    }

    $lastdelimiterindex = rindex($currprefix, "$SS");

    while (($lastdelimiterindex >= 0) && ($isprefix == 0))
    {
      $currprefix = substr($currprefix, 0, $lastdelimiterindex);
     
      if ($platform eq "WIN32")
      {
        if (uc($currprefix) eq uc($pth))
        {
          $isprefix = 1;
        }
      }
      else
      {
        if ("$currprefix" eq "$pth")
        {
          $isprefix = 1;
        }
      }
      $lastdelimiterindex = rindex($currprefix, "$SS"); 
    }
  }

  foreach $mntpnt (@mountedgpfs)
  {
    my $currprefix = $mntpnt;

    if ($platform eq "WIN32")
    {
      if (uc($currprefix) eq uc($pth))
      {
        $isprefix = 1;
      }
    }
    else
    {
      if ("$currprefix" eq "$pth")
      {
        $isprefix = 1;
      }
    }

    $lastdelimiterindex = rindex($currprefix, "$SS");

    while (($lastdelimiterindex >= 0) && ($isprefix == 0))
    {
      $currprefix = substr($currprefix, 0, $lastdelimiterindex);
     
      if ($platform eq "WIN32")
      {
        if (uc($currprefix) eq uc($pth))
        {
          $isprefix = 1;
        }
      }
      else
      {
        if ("$currprefix" eq "$pth")
        {
          $isprefix = 1;
        }
      }
      $lastdelimiterindex = rindex($currprefix, "$SS"); 
    }
  }
  return $isprefix;
}

sub issubpath
{
  $pth1 = shift(@_);
  $pth2 = shift(@_);

  if (($platform eq "LINUX86") || ($platform eq "AIX") || ($platform =~ m/LINUXPPC/))
  {
    @pth1subdirs = split('/', "$pth1");
    @pth2subdirs = split('/', "$pth2");
  }
  elsif ($platform eq "WIN32")
  {
    @pth1subdirs = split(/\\/, "$pth1");
    @pth2subdirs = split(/\\/, "$pth2");
  }

  $l1 = @pth1subdirs;
  $l2 = @pth2subdirs;

  $isasubpath = 1;
  $i = 0;

  if ($l1 < $l2)
  {
    return 0;
  }
  else
  {
    for ($i = 0; $i < $l2; $i++)
    {
      if ("$pth1subdirs[$i]" ne "$pth2subdirs[$i]")
      {
        $isasubpath = 0;
      }
    }
  }

  return $isasubpath;
}

sub getPlatform()
{
  $platfrm = $^O;      # $^O is built-in variable containing osname
  if ($platfrm =~ m#^aix#)                  { return "AIX" };
  if ($platfrm =~ m#^MSWin32#)              { return "WIN32" };
  
  if ($platfrm =~ m#^linux#)
  {
     my @uname = `uname -a`;
   
     foreach (@uname)
     {
       if  ($_ =~ m#x86_64#)   
       {
	 return "LINUX86";
       }
       elsif($_ =~ m#ppc64le#){
       	return "LINUXPPCLE";
       }       
       elsif($_ =~ m#ppc64#){
       	return "LINUXPPC";
       }
     }	
  }
  # We haven't found a match yet, so return UNKNOWN
  return "UNKNOWN";
}

sub getpathdelimiter
{
  $pltfrm = shift(@_);

  if ($pltfrm eq "WIN32")
  {
    return "\\";
  }
  else
  {
    return "/";
  }
}


			
