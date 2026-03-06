#!/usr/bin/env perl
my $version = "V1.18";

print "**********************************************************************\n";
print "* (C) Copyright IBM Corporation 2013, 2013.  All rights reserved.    *\n";
print "*                                                                    *\n";
print "* Tivoli Storage Manager                                             *\n";
print "*                                                                    *\n";
print "* This script collects usefull information to verify server          *\n";
print "* database reorg health as documented with technote swg21590928.     *\n";
print "* See http://www-01.ibm.com/support/docview.wss?uid=swg21590928      *\n";
print "* for the latest version of the script                               *\n";
print "* You need to run the script as instance user with the DB2           *\n";
print "* initialized. The script will prompt you for the necessary          *\n";
print "* parameters required to run Successfully.                           *\n";
print "*                                                                    *\n";
print "* Usage: serverReorgInfo.pl                                          *\n";
print "*                                                                    *\n";
print "* Dependencies: UNIX or Windows                                      *\n";
print "*               Perl interpreter installed                           *\n";
print "*               TSM administrative client installed and configured   *\n";
print "*               TSM server installed on the same box                 *\n";
print "*                                                                    *\n";
print "* Note: This sample script is shipped \"AS-IS\" with all TSM server    *\n";
print "* platforms and must remain formatted with lines less than 80        *\n";
print "* characters each.                                                   *\n";
print "*                                                                    *\n";
print "* serverReorgInfo.pl " . $version . "                                           *\n";
print "*                                                                    *\n";
print "**********************************************************************\n";

# 20150710 V1.07 check OS when submitting commands from @db2commands array
# 20150729 V1.08 check for V71 tablespaces, no trace if $tracetime is 0
# 20150805 V1.09 prompt for $tracetime with default 3600s
# 20151125 V1.10 add MSGNO=3497 actlog search
# 20160629 V1.11 add query to check for BFBF_NDX INDEXTYPE (IC82886), noecho password read
# 20160829 V1.12 copy dsmserv.opt, summary as csv, $targetdir includes pmr number and server name,
#                allow overwrite of DB2INSTANCE
# 20161012 V1.13 corrected typo for filename creation, default trace now 0s
# 20161028 V1.14 added errorlogname, changed $instance handling, check for ANS8019E
# 20161031 V1.15 default to DB2INSTANCE if $instance not set
# 20180423 V1.16 copy log files (dsmffdc/db2diag)
# 20180712 V1.17 output filename redirect correction
# 20181205 V1.18 add MSGno=317 & MSGno=318 collection

use POSIX("strftime");
use Cwd;
use File::Copy;

if (($^O eq "MSWin32") || ($^O eq "Windows_NT") || ($^O eq "cygwin")) {
         require Win32API::Registry;
                 Win32API::Registry->import(qw(KEY_READ));
         require Win32::TieRegistry;
}

my $filename = $0;

# Default values:
my $server        = "localhost";    # server stanza for UNIX, TCPSERVERADDRESS for MSWin32
my $tcpport       = "1500";         # only used in MSWin32
my $administrator = "admin";        # the admin id
my $password      = "password";     # guess what?
my $pmr           = "#####,###,###"; # if doc collection is for a PMR, fully specify the number PPPPP,BBB,CCC

my $instance        = "";           # DB2 instance name, defaults to DB2INSTANCE if left blank

                                    # Note: if you see the following error message in the db2 output files
                                    # SQL10007N Message "-1390" could not be retrieved. Reason code: "3".
                                    # make sure to adjust the $instance variable to match your environment
my $dbalias       = "tsmdb1";       # DB2 database alias for TSM database

                                    # Note: if you see the following error message in the db2 output files
                                    # SQL10007N Message "-1390" could not be retrieved. Reason code: "3".
                                    # make sure to adjust the $instance variable to match your environment

my $traceflag    = "TBREORG";       # TBREORG trace collection
my $tracetime    = "0";             # sleep while collecting trace information, default 0 sec
                                    # no trace when 0
my $traceactive  = "0";             # trace active?

my $actlogdays   = "30";            # how many days to collect activity log information

my $actlog       = "1";             # collect activity log file
my $summary      = "1";             # collect summary file
my $srvropt      = "dsmserv.opt";   # copy dsmserv.opt

my $zipfiles = "1";                 # do you want to zip the docs collected?
my $logscopy = "Y";

# TSM commands to be run
my @commands = ("Q OPT",
                "Q ACTLOG BEGINDATE=TODAY-$actlogdays ENDDATE=TODAY SEARCH=ANR029",
                "Q ACTLOG BEGINDATE=TODAY-$actlogdays ENDDATE=TODAY SEARCH=ANR031",
                "Q ACTLOG BEGINDATE=TODAY-$actlogdays ENDDATE=TODAY SEARCH=ANR033",
                "Q ACTLOG BEGINDATE=TODAY-$actlogdays ENDDATE=TODAY MSGNO=3497",
                "Q ACTLOG BEGINDATE=TODAY-9999 MSGno=317",
                "Q ACTLOG BEGINDATE=TODAY-9999 MSGno=318",
                "\"select count(*) as volumes_in_volhist from volhistory\"");

# DB2 commands to be run
my @db2commands = ("\"set schema tsmdb1\"",
		   "\"select cast(TBSP_NAME as char(30)), reclaimable_space_enabled from table(mon_get_tablespace('',-1)) where TBSP_NAME in ('USERSPACE1','IDXSPACE1','LARGESPACE1','LARGEIDXSPACE1')\" > reclaimable_space.txt",
                   "\"reorgchk current statistics on table all\" > db2reorgchk.out",
                   "\"select count(*) as \"TableCount\" from global_attributes where owner='RDB' and name like 'REORG_TB_%'\"  > table_count.txt",
                   "\"select count(*) as \\\"Indices for TableCount\\\" from global_attributes where owner='RDB' and name like 'REORG_IX_%'\"> index_count.txt",
                   "\"select cast( substr(name,10,min(30,length(name)-9)) as char(30)) as \"Tablename\", substr(char(datetime),1,10) as \\\"Last Reorg\\\" from global_attributes where owner='RDB' and name like 'REORG_TB_%' and datetime is not NULL order by datetime desc\" > table_last_reorg.txt",
		   "\"select cast( substr(name,10,min(30,length(name)-9)) as char(30)) as \\\"Indices for Tablename\\\", substr(char(datetime),1,10) as \\\"Last Reorg\\\" from global_attributes where owner='RDB' and name like 'REORG_IX_%' and datetime is not NULL order by datetime desc\" > index_last_reorg.txt",
		   "\"select substr(tabname,1,25),substr(indname,1,20), sequential_pages, nleaf, density from syscat.indexes where tabname in ('BACKUP_OBJECTS', 'BF_AGGREGATED_BITFILES','ARCHIVE_OBJECTS','BF_BITFILE_EXTENTS') order by tabname\" > index_frags.txt",
		   "\"select stats_time,SUBSTR(TABNAME,1,40) from syscat.tables where tabschema='TSMDB1' AND stats_time is not null order by stats_time desc\" > runstats_time.txt",
		   "\"get snapshot for all applications\" > application_snapshot.txt",
		   "\"select application_handle, elapsed_time_sec, substr( stmt_text, 1, 512) as stmt_text from sysibmadm.mon_current_sql where elapsed_time_sec > 600\" > application_handle.txt",
		   "\"select tu.name,cast(rows_in_table as bigint),cast(table_used_mb as bigint),cast(table_alloc_mb as bigint),cast(index_used_mb as bigint),cast(index_alloc_mb as bigint) from ( select substr(tabname,1,28) as name,bigint(card) as rows_in_table,bigint(float(t.npages)/(1024/(b.pagesize/1024))) as table_used_mb from syscat.tables t, syscat.tablespaces b where t.tbspace=b.tbspace and t.tabschema='TSMDB1' ) as tu, ( select substr(tabname,1,28) as name,bigint(sum(i.nleaf)*(b.pagesize/1024)/1024) as index_used_mb from syscat.indexes i, syscat.tablespaces b where i.tbspaceid=b.tbspaceid and i.tabschema='TSMDB1' group by tabname,pagesize ) as iu, ( select substr(tabname,1,28) as name,bigint(data_object_p_size/1024) as table_alloc_mb,bigint(index_object_p_size/1024) as index_alloc_mb from sysibmadm.admintabinfo ) as ta where tu.name=iu.name and tu.name=ta.name and (table_alloc_mb+index_alloc_mb)>5 order by table_alloc_mb desc,index_alloc_mb desc,tu.name with ur\"  > table_logical_physical_space.txt",
		   "\"select tabname, colname, colcard from sysstat.columns where tabschema='TSMDB1' and colcard < -1\"  > colcard.txt",
		   "\"select substr(TABSCHEMA,1,20) as schema , substr(TABNAME,1,20) as table, TBSPACEID, substr(TBSPACE,1,20) as tablespace, substr(index_tbspace,1,20) as indexspace from syscat.tables where tabschema='TSMDB1' and TABNAME in ('BACKUP_OBJECTS','ARCHIVE_OBJECTS', 'BF_BITFILE_EXTENTS', 'BF_AGGREGATED_BITFILES') order by 3\" > V71-tablespaces.txt",
		   "\"select INDEXTYPE from sysibm.sysindexes where name='BFBF_NDX'\" > IC82886.txt");


# db2pd commands to be
my @db2pdcommands = ("-d tsmdb1 -tablespace > db2pd-tablespace.txt",
                     "-d tsmdb1 -wlocks > db2pd-wlocks.txt",
                     "-d tsmdb1 -reorg index > db2pd-reorg-index.txt",
                     "-d tsmdb1 -runstats > db2pd-runstats.txt",
                     "-d tsmdb1 -logs > db2pd-logs.txt",
                     "-d tsmdb1 -applications >db2pd-app.out",
                     "-d tsmdb1 -transactions >db2pd-txn.out",
                     "-d tsmdb1 -tcbstats > db2pd-tcbstats.txt");

# End of user settable parameters

# Check for Archive::Zip
eval "use Archive::Zip qw( :ERROR_CODES )";
if ($@) {
   if ( $zipfiles ) {
      print "Note: install the Archive::Zip module using the cpan shell \"perl -MCPAN -e shell\"\n";
      print "      at the cpan shell specify \"install archive::Zip\" to install the module from a CPAN mirror\n\n";
   }
   $zipfiles = 0;
}

# Prompt the user for information
print "Note: this script will collect data acc. to technote \n";
print "      http://www.ibm.com/support/docview.wss?uid=swg21590928\n";
print "Note: for best trace results run during the reorg window active,\n";
print "      defined via REORGBEGINTIME and REORGDURATION server options.\n";
print "Note: this script starts TSM server $traceflag trace, when cancelling\n";
print "      this script you may wish to stop server trace via the TSM\n";
print "      commands 'trace end' and 'trace dis *' such that it doesn't\n";
print "      continue to run indefinately.\n";

print "\nPress enter to accept default values shown in brackets:\n\n";
   $server = getResp("Enter the servername as found in dsm.opt or dsm.sys",$server);
   if (($^O eq "MSWin32") || ($^O eq "Windows_NT") || ($^O eq "cygwin")) {
      $tcpport = getResp("Enter the tcpport",$tcpport);
   }
   $administrator = getResp("Enter the TSM administrator login ID",$administrator);
   $password = readPassword("Enter the TSM administrator password",$password);

   if ( defined($ENV{"DB2INSTANCE"}) && $instance eq "" ) {
      $instance = $ENV{"DB2INSTANCE"};
   }

   my $instancefound = 0;

   while ( !($instancefound) ) {

      $instance = getResp("Enter the DB2 instance name", $instance);

      if ($instance ne "" ) {

         my @db2ilist = `db2ilist`;
         
         $rc = $?;
         if ($rc) { 
             print "ERROR: db2ilist returns $rc, are you running as instance user with the environment properly sourced?\n\n";
             exit;
         }
         
         my $instances = "";
         my $comma = "";

         foreach $line ( @db2ilist ) {

            chomp $line;
	    if (($^O eq "MSWin32") || ($^O eq "Windows_NT") || ($^O eq "cygwin")) {
	       # in a cluster the db2ilist looks like "INSTANCE CLUSTERRESOURCE"
	       my @clusterarr = split /\s+/, $line;
	       $line = $clusterarr[0];
	    }

            if ($line =~ /^$instance/) {
               print "Instance found in db2ilist, using $instance\n";
               $ENV{"DB2INSTANCE"} = $instance;
               $instancefound = 1;
            }
            $instances .= $comma . $line;
            $comma = ", ";

         }

         if (!$instancefound) {
            print "\nInstance \"" . $instance . "\" not found in db2ilist: $instances\n";
         }

      } 

   }

   $pmr = getResp("Enter the PMR number",$pmr);
   if ($pmr eq "#####,###,###") {
      $pmr = "";
   }

   if ($traceflag eq "") {
       $tracetime = 0;
   } else {
       $tracetime = getIntResp("Enter seconds to run $traceflag trace (no trace if 0)",$tracetime);
   }

if (($^O eq "MSWin32") || ($^O eq "Windows_NT") || ($^O eq "cygwin")) {

      $cmd = "dsmadmc -tcps=$server -tcpp=$tcpport -id=$administrator -pas=$password -scrollprompt=no -errorlogname=.\\dsmerror.log";

      if ( $ENV{'DSM_CONFIG'} eq "" ) {
	 $dsm_opt = "c:\\progra~1\\tivoli\\tsm\\baclient\\dsm.opt";
      } else {
	 $dsm_opt = $ENV{'DSM_CONFIG'};
      }

      if ( $ENV{'DSM_DIR'} eq "" ) {
         $tsmpath = "c:\\progra~1\\tivoli\\tsm\\baclient\\";
      } else {
         $tsmpath = $ENV{'DSM_DIR'};
      }

      if ( $ENV{'DB2PATH'} eq "" ) {
         $db2cmdpath = $ENV{'DB2PATH'} . "\\BIN\\";
         $db2pdcmdpath = $ENV{'DB2PATH'} . "\\BIN\\";
      } else {
         $db2cmdpath = "C:\\Progra~1\\Tivoli\\TSM\\db2\\BIN\\";
         $db2pdcmdpath = "C:\\Progra~1\\Tivoli\\TSM\\db2\\BIN\\";
      }

   } else {  #UNIX
      $cmd = "dsmadmc -servername=$server -id=$administrator -pas=$password -scrollprompt=no  -errorlogname=./dsmerror.log";

      $SIG{INT} = 'stopInstr';  #set control-C routine

      if ($^O eq "aix") {

         $fsclient = "/usr";
         $fsserver = "/opt";
	 if ( $ENV{'DSM_CONFIG'} eq "" ) {
	     $dsm_opt = $fsclient . "/tivoli/tsm/client/ba/bin64/dsm.opt";
	 } else {
	     $dsm_opt = $ENV{'DSM_CONFIG'};
	 }

	 if ( $ENV{'DSM_DIR'} eq "" ) {
             $tsmpath = $fsclient . "/tivoli/tsm/client/ba/bin64/";
	 } else {
	     $tsmpath = $ENV{'DSM_DIR'};
	 }

      } else {

         $fsclient = "/opt";
         $fsserver = "/opt";
	 if ( $ENV{'DSM_CONFIG'} eq "" ) {
	     $dsm_opt = $fsclient . "/tivoli/tsm/client/ba/bin/dsm.opt";
	 } else {
	     $dsm_opt = $ENV{'DSM_CONFIG'};
	 }

	 if ( $ENV{'DSM_DIR'} eq "" ) {
             $tsmpath = $fsclient . "/tivoli/tsm/client/ba/bin/";
	 } else {
	     $tsmpath = $ENV{'DSM_DIR'};
	 }

      }

#     $dsm_opt = "~/dsm.opt";

      $db2cmdpath = $fsserver . "/tivoli/tsm/db2/bin";
      $db2pdcmdpath = $fsserver . "/tivoli/tsm/db2/adm";

   }

my @out;
my $firstcycle = "true";
my $serverpid = 0;
my $db2supportparms = "";

my $path = $ENV{'PATH'};
$ENV{'PATH'} = $path . ";" . $tsmpath . ";" . $db2cmdpath . ";" . $db2pdcmdpath;
if ( $ENV{'DB2INSTANCE'} eq "" ) {
    $ENV{'DB2INSTANCE'} = $instance;
}
$ENV{'DSM_DIR'} = $tsmpath;
$ENV{'DSM_CONFIG'} = $dsm_opt;

print "DSM_DIR: " . $tsmpath . "\nDSM_CONFIG: " . $dsm_opt . "\n\n";

@out=`db2 connect to $dbalias`;
print @out;

my $begindate  = strftime("%m/%d/%Y", localtime());
my $begintime  = strftime("%H:%M:00", localtime());
my $begints  = strftime("%Y-%m-%d %H:%M:%S.000000", localtime());
my $actlogname = strftime("%Y%m%d-%H%M", localtime()) . "-actlog.txt";
my $summaryname = strftime("%Y%m%d-%H%M", localtime()) . "-summaryrec.csv";

my $now = strftime("%Y%m%d-%H%M", localtime());
my $begin = $now;
my $slept = 0;
my $targetdir = "";
if ($pmr != "") {
   $targetdir = $now . "-" . $pmr . "-" . $server . "-swg21590928";
} else {
   $targetdir = $now . "-" . $server . "-swg21590928";
}

# get the server pid and check we can submit TSM commands
if ($serverpid == 0) {
   $serverpid = &get_pid();
}

# create the target directory and cd to it

my $startdir = getcwd();

if (-d $now) {
   print "Target directory $now exists, exiting";
   exit;
} elsif (-f $now) {
   print "A file with the name of the target directory $now exits, exiting";
   exit;
} else {
   mkdir($targetdir) || die "Could not create $targetdir in $cwd";
   chdir($targetdir);
   $rundir = getcwd;
   print "Created target directory $rundir, starting to collect docs.\n";
   # create doc collection folders
   mkdir("autopdzip");
   chdir("autopdzip");
   mkdir("autopd");
   chdir("autopd");
   open (XMLOUT, "> autopd-collection-environment-v2.xml") || die "Can't open autopd-collection-environment-v2.xml for writing\n";
   print XMLOUT "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n" .
   "<collectionEnvironmentInfo pluginTaxonomyId=\"SSGSG7\" toolName=\"" . $filename . "\" toolVersion=\"" . $version . "\"\n";
   if ($instance ne "") {
      print XMLOUT " instance=\"$instance\"\n";
   }

   print XMLOUT " DB2INSTANCE=\"" . $ENV{"DB2INSTANCE"} . "\"\n";
   print XMLOUT " forceinstance=\"$forceinstance\"\n";

   my $login = "";
   print XMLOUT " osName=\"$^O\"\n";

   if (($^O eq "MSWin32") || ($^O eq "Windows_NT")) {

      my ( $osVername, $osMajor, $osMinor, $osId ) = Win32::GetOSVersion();
      print XMLOUT "osVersion=\"$osVername\" osMajor=\"oaMajor\" osMinor=\"$osMinor\" osId=\"$osId\"\n";

      $login = Win32::LoginName();
   } else {
      if ($^O eq "linux") {

         @lsb_release = `lsb_release -d`;

    foreach (@lsb_release) {
      my($dummy, $description) = split(/:/);
      $description =~ s/^\s+//;
      $description =~ s/\s+$//;
      print XMLOUT "osDescription=\"$description\"\n";
    }

      } else {

         @uname = `uname -a`;

    foreach $description (@uname) {
      $description =~ s/^\s+//;
      $description =~ s/\s+$//;
      print XMLOUT "unameInfo=\"$description\"\n";
    }


      }

      $login = getlogin || getpwuid($<) || "";
   }

   if ($login ne "") {
      print XMLOUT "userName=\"$login\"\n";
   }

   print XMLOUT "dbalias=\"$dbalias\"\n";
   print XMLOUT "actlogdays=\"$actlogdays\"\n";
   print XMLOUT "srvopt=\"$srvropt\"\n";
   print XMLOUT "logscopy=\"$logscopy\"\n";

   print XMLOUT "xmlns=\"http://www.ibm.com/autopd/collectionEnvironment\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.ibm.com/autopd/collectionEnvironment ../autoPD-collection-env.xsd\" />";
   close(XMLOUT);
   chdir($rundir);
}

open (SYSTEMOUT, ">$now-system.txt") || die "Can't open SHOWOUT for writing\n";
print "Submitting: QUERY SYSTEM\n";
@out=`$cmd  QUERY SYSTEM`;
print SYSTEMOUT "@out\n\n";
close(SYSTEMOUT);
$firstcycle = "false";

print "Wrote $now-system.txt\n";

foreach $command (@commands)
{
   print "Submitting: " . $command . "\n";
   @out=`$cmd  $command >> $now-show.txt`;
   print SHOWOUT "@out\n\n";
}

if (-e "$now-show.txt") {
   print "Wrote $now-show.txt\n";
} else {
   print "$now-show.txt not written!\n";
}

foreach $db2command (@db2commands)
{
   print "Submitting: db2 " . $db2command . "\n";
   if (($^O eq "MSWin32") || ($^O eq "Windows_NT") || ($^O eq "cygwin")) {
      `db2 connect to $dbalias & db2 set schema $dbalias & db2 $db2command`; # had a problem where the connection was lost, so reconnect for every command
   } else {
      `db2 connect to $dbalias; db2 set schema $dbalias; db2 $db2command`; # had a problem where the connection was lost, so reconnect for every command
   }
}

foreach $db2pdcommand (@db2pdcommands)
{
   print "Submitting: db2pd " . $db2pdcommand . "\n";
   `db2pd $db2pdcommand`;
}

# collect TBREORG trace for $tracetime
if ($tracetime) {
   open (TRCCMDSOUT, ">$now-trace-commands.txt") || die "Can't open TRCCMDSOUT for writing\n";
   print TRCCMDSOUT `$cmd "trace dis *"`;
   print TRCCMDSOUT `$cmd "trace ena $traceflag"`;
   if (($^O eq "MSWin32") || ($^O eq "Windows_NT") || ($^O eq "cygwin")) {
      print TRCCMDSOUT `$cmd "trace begin \\"$rundir/$now-tbreorg.trc\\""`;
   } else {
      print TRCCMDSOUT `$cmd "trace begin $rundir/$now-tbreorg.trc"`;
   }
   $traceactive = 1;
   print "Started $traceflag trace, sleeping for $tracetime seconds before stopping trace collection...\n";
   sleep($tracetime);
   print TRCCMDSOUT `$cmd "trace flush"`;
   print TRCCMDSOUT `$cmd "trace end"`;
   print TRCCMDSOUT `$cmd "trace dis *"`;

   close(TRCCMDSOUT);
}

if ($actlog) {
   `$cmd query actlog begindate=TODAY-$actlogdays begintime=$begintime > $actlogname`;

   if (-e "$actlogname") {
      print "Wrote $actlogname\n";
   } else {
      print "$actlogname not written!\n";
   }
}

if ($summary) {

    `$cmd -tabd -dataonly=yes "select * from summary where (date(start_time)>=current_timestamp-$actlogdays days)" > $summaryname`;
#    `$cmd -tabd "select * from summary  where (date(start_time)>=current_timestamp-$actlogdays days)" > $summaryname`;

   if (-e "$summaryname") {
      print "Wrote $summaryname\n";
   } else {
      print "$summaryname not written!\n";
   }
}

if ($srvropt ne "") {

   my $insthome = "";

   if (($^O eq "MSWin32") || ($^O eq "Windows_NT") || ($^O eq "cygwin")) {

      my $registry = "HKEY_LOCAL_MACHINE/SOFTWARE/IBM/ADSM/CurrentVersion/Server/$instance";
      my $regKey= new Win32::TieRegistry $registry, { Access=>KEY_READ(), Delimiter=>"/" };
      $insthome = $regKey->GetValue("Path") . "\\";

   } else {

      $insthome = $ENV{"DB2_HOME"};
      $insthome =~ s/sqllib//;

   }

   my $logfile = "$insthome" . "$srvropt";
   my $copytarget = "$srvropt";

   if (-e $logfile) {
      if (copy($logfile, $copytarget)) {
         print "\n-- Copied $logfile to $copytarget\n";
      }
   }
}

if ( $logscopy eq "Y" ) {

    my $insthome = "";

    if (   ( $^O eq "MSWin32" )
        || ( $^O eq "Windows_NT" )
        || ( $^O eq "cygwin" ) )
    {

        my $registry = "HKEY_LOCAL_MACHINE/SOFTWARE/IBM/ADSM/CurrentVersion/Server/$ENV{'DB2INSTANCE'}" ;

        # print "Trying to read Path for $registry\n";
        my $regKey = new Win32::TieRegistry $registry,
          { Access => KEY_READ(), Delimiter => "/" };
        $insthome = $regKey->GetValue("Path") . "\\";

    }
    else {

        $insthome = $ENV{"DB2_HOME"};
        $insthome =~ s/sqllib//;

    }

    @out = `$cmd -dataonly=yes q opt FFDCLOGNAME`;
    
    my $logfile = "";
    my $ffdcnumlogs = 0;
    my $ffdcDir = "dsmffdc-files";
    
    foreach $line (@out) {

        if ( $line =~ /^ *FFDCLOGNAME +(\S+) *$/ ) {
            my $ffdclog    = $1;
            $logfile    = "$ffdclog";
            my $copytarget = "$now-$ffdclog";

            if ( -e "$insthome$logfile" ) {
                if ( copy( "$insthome$logfile", $copytarget ) ) {
                    print "\n-- Copied $insthome$logfile to $copytarget\n";
                }
            }
        }
    }
    
    @out = `$cmd -dataonly=yes q opt FFDCNumLogs`;
    
    foreach $line (@out) {

       if ( $line =~ /^ *FFDCNumLogs +(\S+) *$/ ) {
          $ffdcnumlogs    = $1;

          if ( $ffdcnumlogs) {

             if (!( -e $ffdcDir )) {
	        mkdir($ffdcDir) ;                           
             }
            
             for ( $idx = 1 ; $idx <= $ffdcnumlogs ; $idx++ ) {
                if ( -e "$insthome/$logfile.$idx" ) {
                   zip_or_copy_file("$logfile.$idx", "$insthome", "$ffdcDir/");
                }  
             }

             print "\n";

          }

       }

    }

    $diagdir = $insthome . "sqllib/db2dump/";
    $diagtarget = "db2diag-files";
    
    for ( $idx = 0; ; $idx++ ) {

       if (!( -e $diagtarget )) {
          mkdir($diagtarget) ;                           
       }

       if ($idx == 0) {
          if ( -e $diagdir . "db2diag.log" ) {
               copy( $diagdir . "db2diag.log", "db2diag.log" )
          }
       } else {
          if ( -e $diagdir . "db2diag." . $idx . ".log" ) {
             zip_or_copy_file("db2diag." . $idx . ".log", "$diagdir", "$diagtarget");
          } else {
             last;
          }
       }
    
    }
    
}

print "Collecting db2support output\n";
print `db2support -d $dbalias $db2supportparms`;

if ($zipfiles) {
   print "Creating zip archive $startdir/$pmr-$targetdir.zip\n";
   my $zip = Archive::Zip->new();
   $zip->addTree( '.', "" );

   unless ( $zip->writeToFileNamed("$startdir/$pmr-$targetdir.zip") == AZ_OK() ) {
       die 'Write error creating zipfile.\nAll docs collected are available under $startdir/$targetdir\n\n';
   }

   print "Documentation collection complete, please provide $startdir/$pmr-$targetdir.zip and delete $startdir/$targetdir to free up space.\n";

} else {

   print "Documentation collection complete, please provide the files collected under $startdir/$targetdir. You might later delete the directory to free up space.\n";

}



exit(0);

# Subroutines:

# Get a user response and return it
sub getResp
{
   local ($prompt,$default) = @_;

   print "$prompt [$default]:";
   $| = 1;
   $_ = <STDIN>;
   chomp;
   return $_ ? $_ : $default;
}

# Get a numeric user response and return it
sub getIntResp
{
   local ($prompt,$default) = @_;

   print "$prompt [$default]:";

   do {

      $return = 0;
      $| = 1;
      $_ = <STDIN>;

      chomp;

      if ( m/[^0-9\-]/ ) {
         print "Bad number $_ - $prompt [$default]:";
      } else {

         if (length($_) == '0') {
              return $default;
         } else {
              # reset to -1 if lower
              return $_;
         }

         $return = 1;
      }

   } until $return;

}

# Stop instrumentation on the server
sub stopInstr
{
   if ($traceactive) {
      print "Interrupted, stopping active trace before exiting...\n";
      print TRCCMDSOUT `$cmd "trace flush"`;
      print TRCCMDSOUT `$cmd "trace end"`;
      print TRCCMDSOUT `$cmd "trace dis *"`;
      close(TRCCMDSOUT);
   }
   print "Documentation collection incomplete, you might want to delete $startdir/$targetdir to free up space.\n";
   exit;
}
sub get_pid() {

  open(FILE,"$cmd  SHOW THREADS |") || die "Can't open $cmd - $!";

  while (<FILE>) {

     print "$_";

     if (m/^  Server Version/) {     # check for server
        @fields = split(/\s+/,$_);
        my $version = $fields[3];
        if ($version > 6) {
           $db2supportparms = "-c -s -F"
        } else {
           $db2supportparms = "-c -s -g"
        }
     }

     if (m/^Server PID:/) {     # grab server pid from SHOW THREADS output
        @fields = split(/\s+/,$_);
        close(FILE);
        return $fields[2];
     }

     if ((m/^ANS8023E/) || (m/^ANS1217E/) || (m/^ANS0101E/) || (m/^ANS8019E/)) { # Failure contacting the server/message repository error
        close(FILE);
        exit;
     }

  }

  close(FILE);

}

# Read a password from the command line
# Tries to read the password hidden first
# Reads the password in clear text if hidden reads fail
# Different hidden read styles to work on Windows/Unix
sub readPassword {
   local ($prompt,$default) = @_;

    my $pw = undef();

   # Windows style
   eval {
      require Term::ReadKey;

      Term::ReadKey::ReadMode ('noecho');
      print "$prompt [$default] (no echo to the screen):";
      chomp($pw = <STDIN>);
      Term::ReadKey::ReadMode ('restore');
   };

   # Unix style
   if (!defined($pw)) {
      eval {
         print "$prompt [$default] (no echo to the screen):";
         system('stty','-echo');
         chop($pw=<STDIN>);
         system('stty','echo');
     };
   }

   if (defined($pw)) {
      print "*" x length($pw);
   }

   # read the password visible if we were not able to read it hidden
   if (!defined($pw)) {
      print "$prompt [$default] (warning, it will echo to the screen):";
      chop($pw=<STDIN>);
   }

   print "\n";

   return $pw;

}

sub getDB2JavaBin() {
    my @getDB2 = `db2level`;

    if ( $? == -1 )    # db2level is not available
	    {
	        return "No_DB2";
	    }

    foreach (@getDB2) 
    	{
        	$db2BaseFolder = $1 if ( $_ =~ /^Product is installed at "(.*)"/ );
    	}

    $javaFolder = ( $thisOperatingSystem eq "MSWin32" ? "" : "64" );

    return "$db2BaseFolder/java/jdk$javaFolder/bin/jar";
}

sub zip_or_copy_file() {
# zip_or_copy_file($logfile.$idx, $insthome, $ffdcDir);
                         
   my $file       = @_[0];
   my $fromdir    = @_[1];
   my $todir      = @_[2];

   $fromdir =~ s!/*$!/!; # Add a trailing slash
   $todir   =~ s!/*$!/!; # Add a trailing slash
    
   my $source = $fromdir . $file;
   my $target = $todir . $file;
   
   # print "SOURCE: $source TARGET: $target\n";
   
   $db2ZipProgram = getDB2JavaBin();
           
   if ( $db2ZipProgram ne "No_DB2" ) 
   {
       # zip file

       my $rundir = getcwd() . "/";       
       chdir("$fromdir");
           
       my $zipCommand   = "$db2ZipProgram -cvMf " . $rundir . $target . ".zip ./$file";
       print "Submitting: $zipCommand\n";
       my @callZip      = `$zipCommand`;    
       print @callZip;

       chdir($rundir);

   }
       else 
   {
       # copy file
       if ( copy( $source, $target ) ) {
          print "\n-- Copied $source to $target directory.\n";
       }

   }
}


