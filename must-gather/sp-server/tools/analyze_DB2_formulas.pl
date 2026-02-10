#!/usr/bin/env perl

my $version = "V1.15";
my $filename = $0;

# 1.10 - add -o and -i options
# 1.11 - make -i the default
# 1.12 - add support for solaris
# 1.13 - add -s option
# 1.14 - remove -i, add -c
# 1.15 - add support for zlinux

sub usage
{
print "**********************************************************************\n";
print "* (C) Copyright IBM Corporation 2014, 2019.  All rights reserved.    *\n";
print "*                                                                    *\n";
print "* Tivoli Storage Manager                                             *\n";
print "*                                                                    *\n";
print "* You need to run the script as instance user with the DB2           *\n";
print "* initialized. The script will prompt you for the necessary          *\n";
print "* parameters required to run Successfully.                           *\n";
print "*                                                                    *\n";
print "* Usage: " . $filename . " [-c] [-d] [-h] [-l <directory>] [-o] [-s] [-v] [-z] *\n";
print "* -c check the reorgchk formula thresholds                           *\n";
print "* -d delete log file directory after creating the zip                *\n";
print "* -h help                                                            *\n";
print "* -l log file directory. defaults to current working directory       *\n";
print "* -o offline mode, does not need to connect to database, need files  *\n";
print "* -s process SD_ tables                                              *\n";
print "* -v verbose                                                         *\n";
print "* -z create zip file of log file directory                           *\n";
print "*                                                                    *\n";
print "* Dependencies: UNIX or Windows                                      *\n";
print "*               Perl interpreter installed                           *\n";
print "*               TSM server installed on the same box                 *\n";
print "*                                                                    *\n";
print "* " . $filename . " " . $version . "                                   *\n";
print "*                                                                    *\n";
print "**********************************************************************\n";
}

use POSIX;
use Cwd;
use IO::File;
use Scalar::Util qw(looks_like_number);
use Getopt::Std;

# Default values:

my $preview_only_mode = 1;              # do not execute reorg
my $verbose_mode = 0;                   # enable trace for debug
my $cleanup_without_reclaim = 0;        # cleanup verse cleanup+reclaim extents
my $base_log_directory = getcwd();      # log files will be stored in a subdiretory
                                        # under base_log_directory
my $zipfiles    = 0;                    # do you want to zip the log file directory 
my $deldir      = 0;                    # delete the log file directory if zipfile is created...
my $no_reduce_max = 0;                  # do not execute REDUCE MAX
my $no_runstats = 0;                    # do not execute RUNSTATS
my $dbalias     = "TSMDB1";             # DB2 database alias for TSM database
my $offline_mode = 0;                   # don't run "db2" or "db2pd" commands
                                        # inputs are these files
                                        # db2reorgchk.out
                                        # table_logical_physiscal_space.txt
                                        # db2pd-tablespace.txt
my $ignore_threshold = 1;               # calculate space regardless of asterick
my $ignore_SD_tables = 1;               # don't process SD_ tables

# End of user settable parameters
# typically you do not need to make any changes from here on

my $log_sub_directory;

use constant TABLE_LOGICAL_PHYSICAL_SPACE_FILE  => "table_logical_physiscal_space.txt";
use constant DB2REORGCHK_FILE                   => "db2reorgchk.out";
use constant DB2TABLESPACE_FILE                 => "db2pd-tablespace.txt";
use constant INTERMEDIATE_FILE_1                => "intermediate1.out";
use constant INTERMEDIATE_FILE_2                => "intermediate2.out";
use constant INTERMEDIATE_FILE_3                => "intermediate3.out";
use constant INTERMEDIATE_FILE_4                => "intermediate4.out";
use constant SUMMARY_FILE                       => "summary.out";
use constant TRACE_FILE                         => "trace.out";
use constant TEMP_FILE                          => "temporary_work_file";
use constant DB2_COMMAND_FILE                   => "tsmidx_cmd.db2";


$platform = getPlatform();
if ($platform eq "WIN32")
{
  $SS = "\\";
}
else
{
  $SS = "/";
}

my @logical_physical_space = ();
my @tables_requiring_reorg = ();

my %options=();
getopts("cdhl:osvz", \%options);

  if (defined $options{h})
  {
    &usage;
    exit 0;
  }

  if ($options{l})
  {
    $base_log_directory = $options{l};
    $base_log_directory =~ s/\\/\//g;

    if (!(-d $base_log_directory))
    {
      print "$base_log_directory either does not exist or is not a valid directory\n";
      print "The directory specified with the -l option must be pre existing, valid directory\n";
      exit 1;
    }
  }

  if (defined $options{z})
  {
    $zipfiles = 1;
  }

  if (defined $options{d})
  {
    $deldir = 1;
  }

  if (defined $options{v})
  {
    $verbose_mode = 1;
  }

  if (defined $options{o})
  {
    $offline_mode = 1;
  }

  if (defined $options{c})
  {
    $ignore_threshold = 0;
  }

  if (defined $options{s})
  {
    $ignore_SD_tables = 0;
  }

# Check for Archive::Zip
eval "use Archive::Zip qw( :ERROR_CODES )";
if ($@) {
   if ( $zipfiles ) {
      print "Note: install the Archive::Zip module using the cpan shell \"perl -MCPAN -e shell\"\n";
      print "      at the cpan shell specify \"install Archive::Zip\" to install the module from a CPAN mirror\n\n";
   }
   $zipfiles = 0;
   $deldir = 0;
}

# Check for File::Path
eval "use File::Path 2.07 qw(remove_tree)";
if ($@) {
   if ( $deldir )
   {
     print "Note: If you install FilePath 2.07 or newer the script can clean up the temporary directory used for doc collection.\n  ";
     print "      Install the File::Path module using the cpan shell \"perl -MCPAN -e shell\"\n";
     print "      at the cpan shell specify \"install File::Path 2.07\" to install the module from a CPAN mirror\n\n";
   }
   $deldir = 0;
}

# db2pd commands to be run
my @db2pdcommands = ("-d $dbalias -tablespace > db2pd-tablespace.txt",
                     "-d $dbalias -runstats > db2pd-runstats.txt");


# print "Note: this script will collect data acc. to technote \n";
# print "      http://www.ibm.com/support/docview.wss?uid=swg21683633\n";

$SIG{INT} = 'stopInstr';  #set control-C routine
$fsclient = "/usr";
$fsserver = "/opt";
$db2cmdpath = $fsserver . "/tivoli/tsm/db2/bin";
$db2pdcmdpath = $fsserver . "/tivoli/tsm/db2/adm";

my $path = $ENV{'PATH'};
$ENV{'PATH'} = $path . ";" . $tsmpath . ";" . $db2cmdpath . ";" . $db2pdcmdpath;

chdir($base_log_directory) || unSuccessfulExit("chdir to $base_log_directory Failed\n",0);
my $temp_directory = getcwd();
if (!( $base_log_directory eq $temp_directory ))
{
  unSuccessfulExit("current working directory $temp_directory is not $base_log_directory\n",0);
}

my $begindate  = strftime("%m/%d/%Y", localtime());
my $begintime  = strftime("%H:%M:00", localtime());
my $begints  = strftime("%Y-%m-%d %H:%M:%S.000000", localtime());

my $now = strftime("%Y%m%d-%H%M", localtime());
my $begin = $now;
$log_sub_directory = $now;

if (-f $log_sub_directory ) {
  unSuccessfulExit("A file with the name of the target directory $log_sub_directory exists\n",0);
} else {
  mkdir($log_sub_directory) || unSuccessfulExit("Could not create $log_sub_directory in $cwd",0);
  print "Created log file directory $base_log_directory/$log_sub_directory\n";
  chdir($log_sub_directory);
  $rundir = getcwd;
  chdir($rundir);
}

open ($SUMMARY,   ">", SUMMARY_FILE);
print $SUMMARY "BEGIN SUMMARY\n";

if ( $verbose_mode == 1 )
{
  open ($DEBUGFILE, ">>", TRACE_FILE);
  trace("BEGIN TRACE\n");
}

if ( $offline_mode == 1 )
{
  `cp ../db2reorgchk.out db2reorgchk.out`;
  `cp ../table_logical_physiscal_space.txt table_logical_physiscal_space.txt`;
  `cp ../db2pd-tablespace.txt db2pd-tablespace.txt`;
}
else
{
  foreach $db2pdcommand (@db2pdcommands) 
  {
    if ( system("db2pd $db2pdcommand") != 0 )
    {
      unSuccessfulExit("db2pd $db2pdcommand Failed\n",1);
    }
  }

  # Query to get table / index usage information
  $tblUsageQuery = "select tu.name,cast(rows_in_table as bigint),cast(table_used_mb as bigint),cast(table_alloc_mb as bigint),cast(index_used_mb as bigint),cast(index_alloc_mb as bigint) from ( select substr(tabname,1,28) as name,bigint(card) as rows_in_table,bigint(float(t.npages)/(1024/(b.pagesize/1024))) as table_used_mb from syscat.tables t, syscat.tablespaces b where t.tbspace=b.tbspace and t.tabschema='$dbalias' ) as tu, ( select substr(tabname,1,28) as name,bigint(sum(i.nleaf)*(b.pagesize/1024)/1024) as index_used_mb from syscat.indexes i, syscat.tablespaces b where i.tbspaceid=b.tbspaceid and i.tabschema='$dbalias' group by tabname,pagesize ) as iu, ( select substr(tabname,1,28) as name,bigint(data_object_p_size/1024) as table_alloc_mb,bigint(index_object_p_size/1024) as index_alloc_mb from sysibmadm.admintabinfo ) as ta where tu.name=iu.name and tu.name=ta.name and (table_alloc_mb+index_alloc_mb)>1024 order by table_alloc_mb desc,index_alloc_mb desc,tu.name with ur"; 

  &db2Query ($tblUsageQuery,TABLE_LOGICAL_PHYSICAL_SPACE_FILE);

  $reorgchkQuery = "reorgchk current statistics on table all";

  &db2Query ($reorgchkQuery,DB2REORGCHK_FILE);
}



# main sub routines

&parse_db2pd_tablespaces;
&parse_table_logical_physical_space;
&print_logical_physical_space;
&parse_db2reorgchk;
&analyze_DB2_formulas;

print $SUMMARY "END SUMMARY\n";
close $SUMMARY;

if ( $verbose_mode )
{
  trace("END TRACE\n");
  close $DEBUGFILE;
}

if ($zipfiles) {
   print "Creating zip archive $base_log_directory/$log_sub_directory.zip\n";
   my $zip = Archive::Zip->new();
   $zip->addTree( '.', "" );

   unless ( $zip->writeToFileNamed("$base_log_directory/$log_sub_directory.zip") == AZ_OK() ) {
       $deldir = 0; 
       print "Write error creating zipfile.\nLog files are available under $base_log_directory/$log_sub_directory\n\n";
   }

   print "Log files are in $base_log_directory/$log_sub_directory.zip\n";
} else {
   $deldir = 0;
   print "Log files are available under $base_log_directory/$log_sub_directory\n";
}

chdir($base_log_directory);     

# try to remove the directory we used during doc collection, zipfile is available
if ($deldir) {
  remove_tree( "$log_sub_directory" );
  if (-e "$log_sub_directory") {
    print "Failed to delete $log_sub_directory in $base_log_directory, please remove this yourself.\n";
  } else {
    print "Deleted log file directory $base_log_directory/$log_sub_directory\n";
  }
}

print "The script was SuccessFUL\n";
exit(0);

sub parse_db2pd_tablespaces {
  my $OUTFILE;

  open ($OUTFILE,   ">", INTERMEDIATE_FILE_1);

  trace("BEGIN parse_db2pd_tablespaces\n");

  my $ver71 = 0;

  my $fileName = DB2TABLESPACE_FILE;

  # read the db2pd -tablespace file into memory
  my @wholeFile = ();
  @wholeFile = &getFile( $fileName );
  my $numLines = $#wholeFile;

  # Get the schema name
  my $thisSchema = &getSchema( $numLines, @wholeFile );
  trace( "Found database name $thisSchema\n");

  # Get the line numbers of interest for the two stanzas of interest
  ( $loConfig, $hiConfig, $loStat, $hiStat ) = &findRowsOfInterest( $numLines, @wholeFile );
  die if ( $hiConfig - $loConfig != $hiStat - $loStat );

  my $cumTotal = 0; my $cumUsable = 0; my $cumUsed = 0; my $cumFree = 0;

  my $delta = $loStat - $loConfig;

  for ( $idx = $loConfig; $idx < $hiConfig; $idx++ )
  {
    my @thisLine = split( /\s+/, $wholeFile[ $idx ] );
    my @thatLine = split( /\s+/, $wholeFile[ $idx+$delta ] );

    # Make sure the ids match
    die if ( $thisLine[ 1 ] != $thatLine[ 1 ] );

    # Make sure we have enough values on each line 
    die if ( $#thisLine < 14 );
    die if ( $#thisLine < 12 );

    my $id = $thisLine[ 1 ];
    my $pagesize = $thisLine[ 4 ];
    my $tblSpaceName = $thisLine[ 14 + $ver71 ];

    my $totalPgs = $thatLine[ 2 ];
    my $usablePgs = $thatLine[ 3 ];
    my $usedPgs = $thatLine[ 4 ];
    my $pndFreePgs = $thatLine[ 5 ];
    my $freePgs = $thatLine[ 6 ];

    my $temp_number;

    # add to the cumulative totals
    $cumTotal += &genValue( $totalPgs, $pagesize );
    $cumUsable += &genValue( $usablePgs, $pagesize );
    $cumUsed += &genValue( $usedPgs, $pagesize );
    $temp_number = &genValue( $freePgs, $pagesize );
    trace("$temp_number\n");
    $cumFree += $temp_number;

    if ( $temp_number > 1024*1024*1024 )
    {
      $temp_gig = &genGig( $temp_number );
      print $SUMMARY "\"db2 alter tablespace $tblSpaceName reduce max\" will return $temp_gig to the operating system file system\n";
    }

    print $OUTFILE "TblSpaceName $tblSpaceName(id $id)," .
                   " TotalPgs=$totalPgs" . &genGig( &genValue( $totalPgs, $pagesize ) ) .
                   " UsablePgs=$usablePgs" . &genGig( &genValue( $usablePgs, $pagesize ) ) .
                   " UsedPgs=$usedPgs" . &genGig( &genValue( $usedPgs, $pagesize ) ) .
                   " freePgs=$freePgs" . &genGig( &genValue( $freePgs, $pagesize ) ) .
                   "\n";

# Get the Database name from this line of the db2pd -tablespace command output
# Database Partition 0 -- Database TSMDB1 -- Active -- Up 0 days 22:38:17 -- Date 2013-03-14-09.25.28.049000
sub getSchema
{
  my $numLines = $_[0];
  my $found = 0;
  my $schema = "";
  for ( $idx = 1; $found == 0 && $idx < $numLines; $idx++ )
  {
    my $line = $_[$idx];
    if ( $line =~ /^Database Partition/ )
    {
      $found = 1; 
    }
    if ( $line =~ /^Database Member/ )
    {
      $found = 1; 
      $ver71 = 1;
    }

    if ( $found )
    {
      my @items = split( /\s+/, $line );
      my $thisSize = @items;
      die if ( $thisSize < 5 );
      $schema = $items[5];
    }
  }

  die if ( $schema eq "" );
  $schema;

} #sub getSchema
  }

  print $OUTFILE "     CumTotalPgs". &genGig( $cumTotal ) . 
                 " CumUsablePgs" . &genGig( $cumUsable ) . 
                 " CumUsedPgs" . &genGig( $cumUsed ) . 
                 " CumFreePgs" . &genGig( $cumFree ) . 
                 "\n";

  close $OUTFILE;
}



sub parse_table_logical_physical_space {
  my $line = "";
  my $thisLineNum = 0, my $thisTableLineNum = 99999, my $thisIndexLineNum = 99999;
  my $thisTableLine = "", my $thisIndexLine = "";
  my $tabName = $idxName = "";
  my $headerLine = 0;
  my $INFILE;

  open ($INFILE,    "<", TABLE_LOGICAL_PHYSICAL_SPACE_FILE );

  trace("BEGIN parse_table_logical_physical_space\n");

  while ( $line = <$INFILE>)
  {
    $thisLineNum++;

    trace("Top of loop thisLineNum = $thisLineNum, headerLine = $headerLine\n");

    chop $line;

    trace($line . "\n");

    my @items = split( /\s+/, $line );
    my $thisSize = @items;
    trace("Looking for 6. This size = " . $thisSize . "\n");

    if ( $thisSize == 6 )
    {
      trace( "thisSize is 6 thisLineNum = $thisLineNum, headerLine = $headerLine\n");
      if ( ( $items[ 0 ] =~ "NAME" ) &&
           ( $items[ 1 ] =~ "ROWS_IN_TABLE" ) &&
           ( $items[ 2 ] =~ "TABLE_USED_MB" ) &&
           ( $items[ 3 ] =~ "TABLE_ALLOC_MB" ) &&
           ( $items[ 4 ] =~ "INDEX_USED_MB" ) &&
           ( $items[ 5 ] =~ "INDEX_ALLOC_MB" ) )
      {
        $headerLine = $thisLineNum;
        trace("found header line headerLine = $headerLine, thisLineNum = $thisLineNum\n");
      }

      if ( !( looks_like_number($items[ 2 ]) &&
           looks_like_number($items[ 3 ]) &&
           looks_like_number($items[ 4 ]) &&
           looks_like_number($items[ 5 ]) ) )
      {
        next;
      }

      if ( ( $headerLine > 0 ) &&
           ( $thisLineNum > ( $headerLine + 1 ) ) )
      {
        my $beginsWith = begins_with($items[ 0 ],"SD");
        trace("begins_with $beginsWith\n");

        if ( ( $beginsWith eq 0 ) || ( $ignore_SD_tables eq 0 ) )
        {
          $rec = {
            NAME            => $items[ 0 ],
            TABLE_USED_MB   => $items[ 2 ],
            TABLE_ALLOC_MB  => $items[ 3 ],
            INDEX_USED_MB   => $items[ 4 ],
            INDEX_ALLOC_MB  => $items[ 5 ]
          };
          trace("NAME $rec->{NAME}\n");
          trace("TABLE_USED_MB $rec->{TABLE_USED_MB}\n");
          trace("TABLE_ALLOC_MB $rec->{TABLE_ALLOC_MB}\n");
          trace("INDEX_USED_MB $rec->{INDEX_USED_MB}\n");
          trace("INDEX_ALLOC_MB $rec->{INDEX_ALLOC_MB}\n");
  
          $logical_physical_space{$items[ 0 ]} = $rec;
        }
      }
    }
    else
    {
      next;
    }
  } #while

  trace("Number of lines = $thisLineNum\n");
  close $INFILE;
}

sub print_logical_physical_space {
  trace("BEGIN print_logical_physical_space\n");

  my $temp = scalar keys %logical_physical_space;

  trace("number of items in logical_physical_space $temp\n");

  foreach my $key ( keys %logical_physical_space )
  {
    trace($logical_physical_space{$key}->{NAME} . "\n");
  }
}

sub parse_db2reorgchk {
  my $thisSchema = $dbalias;
  my $line = "";
  my $thisLineNum = 0, my $thisTableLineNum = 99999, my $thisIndexLineNum = 99999;
  my $thisTableLine = "", my $thisIndexLine = "";
  my $tabName = $idxName = "";
  my $INFILE;
  my $OUTFILE;

  open ($INFILE,    "<", DB2REORGCHK_FILE);
  open ($OUTFILE,   ">", INTERMEDIATE_FILE_2);

  my $addOn = 0;

  trace("BEGIN parse_db2reorgchk\n");

  while ($line = <$INFILE>)
  {
    my $justDidIdx = 0;

    $thisLineNum++;

    trace("Top of loop. Line # " . $thisLineNum . "\n");

    chop $line;

    trace($line . "\n");
      
    if ( $line =~ /Table\s*[:]\s*$thisSchema[.]/   | # english
         $line =~ /Tabelle\s*[:]\s*$thisSchema[.]/ | # german
         $line =~ /Tabel\s*[:]\s*$thisSchema[.]/   | # denish
         $line =~ /Tabela\s*[:]\s*$thisSchema[.]/  | # spanish
         $line =~ /Tabella\s*[:]\s*$thisSchema[.]/   # italian
       )
    {
      $thisTableLineNum = $thisLineNum;
      $thisTableLine = $line; 
    }

    if ( $thisTableLineNum < $thisLineNum &&
         $thisIndexLineNum < $thisLineNum )
    {
      my @items = split( /\s+/, $line );
      my $thisSize = @items;
      trace("Looking for 17 or 18. This size = " . $thisSize . "\n");
      if ( $thisSize != 17 && $thisSize != 18 )
      {
        trace("Can't parse $line into 17 data points for " .
              "table $thisTableLine at location $thisTableLineNum.\n");
      }
      else
      {
        $addOn = 0;
        $addOn = $addOn + 1 if ( $thisSize == 18 );

        $_ = $thisTableLine;
        print $OUTFILE $thisTableLine;

        if ( /Table\s*[:]\s*$thisSchema[.](\w+)/    |
             /Tabelle\s*[:]\s*$thisSchema[.](\w+)/  |
             /Tabel\s*[:]\s*$thisSchema[.](\w+)/    |
             /Tabela\s*[:]\s*$thisSchema[.](\w+)/   |
             /Tabella\s*[:]\s*$thisSchema[.](\w+)/
           )
        {
          $tabName = $1;
        }

        $_ = $thisIndexLine;

        if ( /Index\s*[:]\s*$thisSchema[.](\w+)/  |
             /Indeks\s*[:]\s*$thisSchema[.](\w+)/ |
             /\xCDndice\s*[:]\s*$thisSchema[.](\w+)/ |
             /Indice\s*[:]\s*$thisSchema[.](\w+)/ |
             /Index\s*[:]\s*SYSIBM[.](\w+)/  |
             /Indeks\s*[:]\s*SYSIBM[.](\w+)/ |
             /\xCDndice\s*[:]\s*SYSIBM[.](\w+)/ |
             /Indice\s*[:]\s*SYSIBM[.](\w+)/
           )
        {
          $idxName = $1;
        }

        print $OUTFILE "table=$tabName,index=$idxName," .
          &scrubIt("indcard", $items[ 1 ] ) . "," .
          &scrubIt("leaf", $items[ 2 ] ) . "," .
          &scrubIt("eleaf", $items[ 3 ] ) . "," .
          &scrubIt("lvls", $items[ 4 ] ) . "," .
          &scrubIt("ndel", $items[ 5 ] ) . "," .
          &scrubIt("keys", $items[ 6 ] ) . "," .
          &scrubIt("leaf_recsize", $items[ 7 ] ) . "," .
          &scrubIt("nleaf_recsize", $items[ 8 ] ) . "," .
          &scrubIt("leaf_page_overhead", $items[ 9 ] ) . "," .
          &scrubIt("nleaf_page_overhead", $items[ 10 ] ) . "," .
          &scrubIt("f4", $items[ 11+$addOn ] ) . "," .
          &scrubIt("f5", $items[ 12 + $addOn ] ) . "," .
          &scrubIt("f6", $items[ 13 + $addOn ] ) . "," .
          &scrubIt("f7", $items[ 14 + $addOn ] ) . "," .
          &scrubIt("f8", $items[ 15 + $addOn ] ) . "," .
          &scrubIt("reorg", $items[ 16 + $addOn ] ) . ",\n" ;
      }
      $thisIndexLineNum = 9999;
      $justDidIdx = 1;
    }

    if ( $thisTableLineNum < $thisLineNum )
    {
      if ( $line =~ /Index\s*[:]\s*$thisSchema[.]/  |
           $line =~ /Indeks\s*[:]\s*$thisSchema[.]/ |
           $line =~ /\xCDndice\s*[:]\s*$thisSchema[.]/ |
           $line =~ /Indice\s*[:]\s*$thisSchema[.]/ |
           $line =~ /Index\s*[:]\s*SYSIBM[.]/  |
           $line =~ /Indeks\s*[:]\s*SYSIBM[.]/ |
           $line =~ /\xCDndice\s*[:]\s*SYSIBM[.]/ |
           $line =~ /Indice\s*[:]\s*SYSIBM[.]/
         )
      {
        $thisIndexLineNum = $thisLineNum;
        $thisIndexLine = $line; 
      }
      elsif ( $justDidIdx == 0 )
      {
        my @items = split( /\s+/, $line );
        my $thisSize = @items;
        trace("Looking for 11. This size = " . $thisSize . "\n");
        if ( $thisSize != 11 )
        {
          if ( $thisLineNum == ($thisTableLineNum+1) )
          {
            trace("Can't parse $line into 10 data points for " .
                  "table $thisTableLine at location $thisTableLineNum.\n");
          }
        }
        else
        {
          $_ = $thisTableLine;

          if ( /Table\s*[:]\s*$thisSchema[.](\w+)/    |
               /Tabelle\s*[:]\s*$thisSchema[.](\w+)/  |
               /Tabel\s*[:]\s*$thisSchema[.](\w+)/    |
               /Tabela\s*[:]\s*$thisSchema[.](\w+)/   |
               /Tabella\s*[:]\s*$thisSchema[.](\w+)/
             )
          {
            $tabName = $1;
          }

          print $OUTFILE "table=$tabName," .
            &scrubIt("card", $items[ 1 ] ) . "," .
            &scrubIt("ov", $items[ 2 ] ) . "," .
            &scrubIt("np", $items[ 3 ] ) . "," .
            &scrubIt("fp", $items[ 4 ] ) . "," .
            &scrubIt("actblk", $items[ 5 ] ) . "," .
            &scrubIt("tsize", $items[ 6 ] ) . "," .
            &scrubIt("f1", $items[ 7 ] ) . "," .
            &scrubIt("f2", $items[ 8 ] ) . "," .
            &scrubIt("f3", $items[ 9 ] ) . "," .
            &scrubIt("reorg", $items[ 10 ] ) . ",\n" ;
        }
        $thisTableLineNum = 9999;
      }
    }
  } #while

  trace("Number of lines = $thisLineNum\n");
  close $OUTFILE;
  close $INFILE;
}

sub analyze_DB2_formulas {
  my $PctFree               = 5;
  my $recordHeaderSize      = 2;
  my $ridSize               = 6;
  my $ridFlagSize           = 1;
  my $thisIndexPageSize     = 0;

  # Extra 5% for PCTFREE; Extra 2% for nonLeafPages
  my $pctFreeAdj = 1.05;
  my $nonleafPageAdj = 1.02;
  
  my %theData = ();
  my $line = "";
  my $lineNum = 0;

  my $totalSpaceSavings = 0;

  my $INFILE;
  my $OUTFILE;

  open ($INFILE,    "<", INTERMEDIATE_FILE_2);
  open ($OUTFILE,   ">", INTERMEDIATE_FILE_3);
  open ($OUTFILE2,  ">", INTERMEDIATE_FILE_4);

  trace("BEGIN analyze_DB2_formulas\n");

  while ( $line = <$INFILE>)
  {
    chop $line;
    $lineNum++;

    if ( $line =~ /Can't parse/ )
    {
      next;
    }

    my $tableName = &GetItem( $line, "table=" );
    my $indexName = &GetItem( $line, "index=" );

    if ( $tableName eq "" )
    {
      trace("Invalid line $line at $lineNum\n");
    }
    else
    {
      if ( exists $logical_physical_space{$tableName} )
      {
        if ( $indexName eq "" )
        {
          trace($tableName . " IS present in logical_physical_space\n");
          # This is a tableName line only
          $theData{ $tableName } = $line . ";" ;
        }
        else
        {
          # Catenate the index data in at the end of the current record
          $theData{ $tableName } = $theData{ $tableName } . $line . ";" ;
        }
      }
    }
  } #while

  my %largestTables = ();
  my %largestTablesSizes = ();
  my $largestTablesIdx = 0;
  {
    my %tempCopy = %theData;
    my $didSomething = 1;

    while ( $didSomething == 1 )
    {
      my $maxTSize = 0; my $maxTblName = "";
      my $tblName = "";  my $tblData = "";

      $didSomething = 0;

      # Prune out all the records which don't have tsize in them. 
      while ( ( $tblName, $tblData ) = each( %tempCopy ) )
      {
        my $thisTSize = &GetItem( $tblData, "tsize=" );

        if ( length( $thisTSize ) == 0 )
        {
          delete $tempCopy{ $tblName };
        }
      }

      # Now process the records which have tsize in them.
      while ( ( $tblName, $tblData ) = each( %tempCopy ) )
      {
        my $thisTSize = &GetItem( $tblData, "tsize=" );

        if ( $thisTSize > $maxTSize )
        {
          $maxTSize = $thisTSize;
          $maxTblName = $tblName;
        }
      }

      if ( $maxTSize > 0 )
      {
        $didSomething = 1;
        $largestTables{ $largestTablesIdx } = $maxTblName;
        $largestTablesSizes{ $largestTablesIdx } = $maxTSize; 
        $largestTablesIdx++;
        trace("Table $maxTblName has size $maxTSize\n");
        delete $tempCopy{ $maxTblName };
      }
    }
  }

  # Now locate the indices for the largest tables and display the 
  # sizes associated with them.
  my $idx = 0;
  for ( $idx = 0; $idx < $largestTablesIdx; $idx++ )
  {
    my $thisTbl = $largestTables{ $idx };
    my $thisRecord = $theData{ $thisTbl } ;

    my $thisTSize = &GetItem( $thisRecord, "tsize=" );
    my $thisTReorg = &GetItem( $thisRecord, "reorg=" );
    my $thisCard = &GetItem( $thisRecord, "card=" );
    my $thisF1 = &GetItem( $thisRecord, "f1=" );
    my $thisF2 = &GetItem( $thisRecord, "f2=" );
    my $thisF3 = &GetItem( $thisRecord, "f3=" );
    my $reorgRequired = 0;
    my $reorgRequired2 = 0;

    my $thisTSizeBytes = $thisTSize;
    $thisTSize = &toMeg( $thisTSize );
    $thisCard = &toReadableNum( $thisCard );

    # Derive the pagesize for the indices for this table.
    $thisIndexPageSize = &getIdxPageSize( $thisTbl );

    my $outRec = "\nTable $thisTbl, ";
    while ( length( $outRec ) < 30 )
    {
      $outRec .= " ";
    }

    $outRec .= "reorg=$thisTReorg($thisF1,$thisF2,$thisF3), tsize=$thisTSize, card=$thisCard ";
    print $OUTFILE "$outRec\n";
    trace("$outRec\n");

    trace("thisTReorg $thisTReorg\n");

    # check table formulas F1 and F2
    if ( ( ( $thisTReorg =~ /^[\*]/ ) ||
         ( $thisTReorg =~ /^.[\*]/ ) ) ||
         ( $ignore_threshold == 1 ) )
    {
      $reorgRequired = 1;
      print $OUTFILE2 "$outRec\n";
    }

    my $idxCntr = 1; my $done = 0;
    my $sumIdxZ = 0;

    while ( $done == 0 )
    {
      my $thisIdx = &GetIdx( $idxCntr, $thisRecord );

      if ( length( $thisIdx ) == 0 )
      {
        $done = 1;

        # for space map page overhead
        my $numberOfPagesPerSpaceMapPage = $thisIndexPageSize - 128;
        my $allIdxOverhead = ceil( $sumIdxZ / $numberOfPagesPerSpaceMapPage);

        $sumIdxZ += $allIdxOverhead;

        $outRec = "       " .
                  " sumZIdxSize=" . &toMeg( $sumIdxZ ) . "--ZIdxOverhead=". &toMeg( $allIdxOverhead ). "\n";

        print $OUTFILE "$outRec\n";
        trace("$outRec\n");

        trace("reorgRequired $reorgRequired\n");
        if ( $reorgRequired == 1 )
        {
          my ($tempTable,$tempIndex) = potentialSpaceSavings($thisTbl,$thisTSizeBytes,$sumIdxZ);
          $totalSpaceSavings += ($tempTable+$tempIndex);

          if ( $ignore_threshold == 1 )
          {
            print $SUMMARY "If $thisTbl were to be off line reorganized the estimated savings is Table $tempTable GB, Index $tempIndex GB\n";
            trace("If $thisTbl were to be off line reorganized the estimated savings is Table $tempTable GB, Index $tempIndex GB\n");
          }
          else
          {
            print $SUMMARY "$thisTbl needs to be reorganized. estimated savings Table $tempTable GB, Index $tempIndex GB\n";
            trace("$thisTbl needs to be reorganized. estimated savings Table $tempTable GB, Index $tempIndex GB\n");
          }
          $temp = trim($thisTbl);
          my $rec = {
            NAME            => $temp
          };
          $tables_requiring_reorg{$temp} = $rec;
        }
      }
      else
      {
        my $thisIdxName = &GetItem( $thisIdx, ",index=" );
        my $thisCard = &GetItem( $thisIdx, ",indcard=" );
        my $thisKeys = &GetItem( $thisIdx, ",keys=" );
        my $thisNdel = &GetItem( $thisIdx, ",ndel=" );
        my $thisLeafrecsize = &GetItem( $thisIdx, ",leaf_recsize=" );
        my $this_nLeaf_recsize = &GetItem( $thisIdx, ",nleaf_recsize=" );
        my $thisReorg = &GetItem( $thisIdx, ",reorg=" );
        my $this_leaf_page_overhead = &GetItem( $thisIdx, ",leaf_page_overhead=" );
        my $this_nonLeafPageOverhead = &GetItem( $thisIdx, ",nleaf_page_overhead=" );
        my $thisF4 = &GetItem( $thisIdx, "f4=" );
        my $thisF5 = &GetItem( $thisIdx, "f5=" );
        my $thisF6 = &GetItem( $thisIdx, "f6=" );
        my $thisF7 = &GetItem( $thisIdx, "f7=" );
        my $thisF8 = &GetItem( $thisIdx, "f8=" );

        my $outRec = " Index=$thisIdxName, ";

        while ( length( $outRec ) < 30 )
        {
          $outRec .= " ";
        }

        $outRec .= "reorg=$thisReorg($thisF4,$thisF5,$thisF6,$thisF7,$thisF8),";

        trace("thisReorg $thisReorg\n");

      # check index formulas F5, F7 and F8
        if ( ( ( $thisReorg =~ /^.[\*]/ ) ||
             ( $thisReorg =~ /^...[\*]/ ) ||
             ( $thisReorg =~ /^....[\*]/ ) ) ||
             ( $ignore_threshold == 1 ) )
        {
          $reorgRequired = 1;
          trace("setting reorgRequired\n");
          $reorgRequired2 = 1;
        }
        else
        {
          $reorgRequired2 = 0;
        }

        # The original index size value
        if ( length( $thisCard ) > 0 && length( $thisKeys ) > 0 && 
             length( $thisNdel ) > 0 && 
             length( $thisLeafrecsize ) > 0 && length( $this_nLeaf_recsize ) > 0 && 
             length( $this_leaf_page_overhead ) > 0 && 
             length( $this_nonLeafPageOverhead ) > 0 )
        {
          my $value = 0.0;
          my $megValue = 0.0;
          if ( $thisCard == $thisKeys )
          {
            $outRec .= "indcard=keys=$thisCard, " ;
          }
          else
          {
            $outRec .= "indCard=$thisCard, keys=$thisKeys, " ;
          }
        }

        {
          $value = &calcIdxSizeZ( $recordHeaderSize, $ridSize, $ridFlagSize,
                                  $thisKeys, $thisLeafrecsize, $thisCard,
                                  $PctFree, $thisIndexPageSize,
                                  $this_leaf_page_overhead, $this_nLeaf_recsize,
                                  $this_nonLeafPageOverhead );

          $sumIdxZ += $value;

          $megValue = &toMeg( $value );
          $outRec .= "z-IdxSize=$megValue, " ;

          $outRec .= "ndel=$thisNdel " if ( length( $thisNdel ) > 0 );
        }

        print $OUTFILE "$outRec\n";
        trace("$outRec\n");

        if ( $reorgRequired2 == 1 )
        {
          print $OUTFILE2 "$outRec\n";
        }

        $idxCntr++;
      }
    } # while
  }

  print $SUMMARY "Total estimated savings $totalSpaceSavings GB\n";

  close $OUTFILE;
  close $INFILE;
}




sub potentialSpaceSavings
{
  my $tblName = $_[0];
  my $thisTSize = $_[1];
  my $sumIdxZ = $_[2];
  my $retValue1 = 0;
  my $retValue2 = 0;
  my $temp_table_savings;
  my $temp_index_savings;

  trace("BEGIN potentialSpaceSavings\n");

  trace("tblName $tblName thisTSize $thisTSize sumIdxZ $sumIdxZ\n");

  $temp_table_savings = $logical_physical_space{$tblName}->{TABLE_ALLOC_MB} - ( $thisTSize / ( 1024 * 1024 ) );
  trace("potential table savings $temp_table_savings MB\n");
  $temp_index_savings = $logical_physical_space{$tblName}->{INDEX_ALLOC_MB} - ( $sumIdxZ / ( 1024 * 1024 ) );
  trace("potential index savings $temp_index_savings MB\n");

  $temp_table_savings = $temp_table_savings/1024;
  if ( $temp_table_savings < 0 )
  {
    $temp_table_savings = 0;
  }

  $retValue1 = sprintf( "%4.0f", $temp_table_savings );

  $temp_index_savings = $temp_index_savings/1024;
  if ( $temp_index_savings < 0 )
  {
    $temp_index_savings = 0;
  }

  $retValue2 = sprintf( "%4.0f", $temp_index_savings );

  return ($retValue1,$retValue2);
}

sub db2Query
{
  my $query = $_[0];
  my $outputFilename = $_[1];
  my $currentdir = Cwd::cwd();

  trace("BEGIN db2Query\n");
  trace("outputFilename = $outputFilename\n");
  trace("query = $query\n");

  if (($platform eq "LINUX86") || ($platform eq "AIX") || ($platform eq "LINUXPPC") || ($platform eq "SOLARIS") || ($platform eq "ZLINUX"))
  {
    $db2cmdFile = DB2_COMMAND_FILE;
    trace("db2cmdFile $db2cmdFile\n");
  }
  elsif ($platform eq "WIN32")
  {
    $db2cmdFile = "DB2_COMMAND_FILE";
    trace("db2cmdFile $db2cmdFile\n");
    $db2batFile = "DB2_COMMAND_FILE.bat";
    trace("db2batFile $db2batFile\n");
  }


  # Build a command file to find table usage information for any table great than XX
  $query =~ s/\n//g;
  if (open(DB2CMD, ">$db2cmdFile"))
  {
    print DB2CMD "connect to $dbalias;\n";
    print DB2CMD "set schema $dbalias;\n";
    print DB2CMD "$query;\n";
    print DB2CMD "terminate;\n";
  }
  else
  {
    unSuccessfulExit("Could not open file: $db2cmdFile\n",1);
  }
  close DB2CMD;

  if ($platform eq "WIN32")
  {
    if (open(DB2BAT, ">$db2batFile"))
    {
      print DB2BAT "db2cmd /c /w /i db2 -tf $db2cmdFile\n";
    }
    else
    {
      unSuccessfulExit("Could not open file: $db2batFile\n",1);
    }
    close DB2BAT;
  }

  if (($platform eq "LINUX86") || ($platform eq "AIX") || ($platform eq "LINUXPPC") || ($platform eq "SOLARIS"))
  {
    system("chmod u+x $db2cmdFile");
    my $temp = "db2 -tf $db2cmdFile > $outputFilename";
    system($temp);
    unlink $db2cmdFile;
  }
  elsif ($platform eq "WIN32")
  {
    my $temp = "$db2batFile > $outputFilename";
    system($temp);
    unlink $db2cmdFile;
    unlink $db2batFile;
  }

  @out = &getFile( $outputFilename );

  if ((grep {m/DB20000I/} @out) < 1)
  {
    unSuccessfulExit("SQL command Failed: $query\n",1);
  }
}

sub getPlatform()
{
  $platfrm = $^O;      # $^O is built-in variable containing osname
  if ($platfrm =~ m#^aix#)                  { return "AIX" };
  if ($platfrm =~ m#^MSWin32#)              { return "WIN32" };
  if ($platfrm =~ m#^solaris#)              { return "SOLARIS" };
  
  if ($platfrm =~ m#^linux#)
  {
     my @uname = `uname -a`;
   
     foreach (@uname)
     {
       if  ($_ =~ m#x86_64#){
	 return "LINUX86";
       }
       
       if($_ =~ m#ppc64#){
       	 return "LINUXPPC";
       }

       if($_ =~ m#s390x#){
         return "ZLINUX"
       }
     }	
  }
  # We haven't found a match yet, so return UNKNOWN
  return "UNKNOWN";
}

# This is to find the first and last tablespace rows for the 
# 'Tablespace Configuration' and the 'Tablespace Statistics' 
# stanzas.
sub findRowsOfInterest
{
  my @result = ();

  my $numLines = $_[0];
  my $done = 0;
  my $idx = 0;
  for ( $idx = 1; $done == 0 && $idx < $numLines;   )
  {
    my $line = $_[$idx];
    if ( $line =~ /^Tablespace Configuration/ ||
         $line =~ /^Tablespace Statistics/ )
    {
      $done = ( $line =~ /^Tablespace Statistics/ );

      my $idy = 0;
      my $stanzaDone = 0;
      my $loVal = $idx+2; my $hiVal = $idx+2;

      # Figure out the line numbers of the first and last tablespaces
      # in the "Tablespace Configuration" section
      for ( $idy = $loVal; $stanzaDone == 0 && $idy < $numLines; $idy++  )
      {
        my $line = $_[$idy];

        if ( $line =~ /^0x/ )
        {
          # If we've got a good line, go onto the next one
          # Don't increment hiVal on the first line.
          if ( $idy == $idx + 2 )
          {
            next;
          }
          else
          {
            $hiVal++;
          }
        }
        else
        {
          $stanzaDone = 1;
          die if ( $hiVal <= $loVal );
          push( @result, $loVal, $hiVal );
          $idx = $idy;
        }
      }
    }
    else 
    {
      $idx++;
    }
  } #for

  my $numValues = @result;
  die if ( $numValues != 4 );
  @result;
} #  findRowsOfInterest

# Convert the input number of pages to the number of bytes occupied by such, given
# the page size in the second parm.
sub genValue
{
  my $numPages = $_[0];
  my $pagesize = $_[1];
  my $finalVal = 0;

  if ( $numPages > 0 )
  {
    $finalVal = $numPages * $pagesize; 
  }

  $finalVal;
} # genValue

# Convert the input to gigabytes with one decimal point.
sub genGig
{
  my $inValue = $_[0];
  $inValue /= ( 1024 * 1024 * 1024 );
  my $outString = sprintf( "=%5.1fG", $inValue );

  $outString;
} # genGig

# read the whole file into an array and return it
sub getFile
{
  my $fileName = $_[0];
  my @theValues = (); 
  my $inHandle = new IO::File;

  open( $inHandle, $fileName );
  @theValues = <$inHandle>;
  close $inHandle; 

  @theValues;
} #sub getFile

# If a field has value "-", return nothing. Replace ',' in the value with '.'.
# Return label=value.
sub scrubIt
{
  my $label = $_[0];
  my $value = $_[1];
  my $retValue = "";

  if ( $value eq "-" )
  {
    $retValue = "";
  }
  else
  {
    $value =~ tr/,/./;
    $retValue = "$label=$value";
  }
  $retValue;
}

# Given a record, fish out the nth index--the first is 1, the second is 2, etc.
sub GetIdx
{
  my $indexNum = $_[0];
  my $thisRecord = $_[1];
  my $theSemi = index( $thisRecord, ";" );
  my $nextSemi = -1; my $foundCnt = 0;
  my $retValue = "";

  while ( $theSemi > -1 && $foundCnt < $indexNum )
  {
    $thisRecord = substr( $thisRecord, $theSemi+1 );
    $nextSemi = index( $thisRecord, ";" );
    $foundCnt++;

    if ( $foundCnt == $indexNum && $nextSemi != -1 )
    {
      $retValue = substr( $thisRecord, 0, $nextSemi );
    }
    else
    {
      $theSemi = index( $thisRecord, ";" );
    }
  }

  $retValue;
}

# If a field has value "-", return nothing. Replace ',' in the value with '.'.
# Return label=value.
sub GetItem
{
  my $line = $_[0];
  my $label = $_[1];
  my $addon = 0; my $endLoc = 0;
  my $retValue = "";

  my $thisLoc = index( $line, $label );
  if ( $thisLoc > -1 )
  {
    if ( substr( $line, $thisLoc, 1 ) eq "," )
    {
      $addon = 1;
    }
    else
    {
      $addon = 0;
    }

    $endLoc = index( substr( $line, $thisLoc + $addon ), "," );
    if ( $endLoc > -1 )
    {
      $retValue = substr( $line, $thisLoc + length( $label ), 
      $endLoc - length( $label ) + $addon );
    }
  }

  if ( $retValue =~ /[=]|[,]/ )
  {
    my $stop = 1;
  }

  $retValue;
}

# Convert something to meg with one decimal place
sub toMeg
{
  my $value = $_[0];
  my $toMeg = 1024 * 1024;
  my $retValue = 0;

  if ( length( $value ) > 0 )
  {
    $retValue = $value / $toMeg;
    $retValue = sprintf("%2.1f", $retValue ) . "M" ;
  }
  $retValue;
}

# Convert numbers (i.e. cardinality) to thousands, millions, etc.
# by dividing by 1000.  Leaveone decimal place
sub toReadableNum
{
  my $value = $_[0];
  my $retValue = 0;
  my $tenBillion = 10000000000;
  my $tenMillion = 10000000;
  my $tenThousand = 10000;

  if ( length( $value ) > 0 )
  {
    $retValue = $value;
    if ( $value > $tenBillion )
    {
      $retValue = $value / $tenBillion * 10 ;
      $retValue = sprintf("%2.1f", $retValue ) . "E9" ;
    }
    elsif ( $value > $tenMillion )
    {
      $retValue = $value / $tenMillion * 10;
      $retValue = sprintf("%2.1f", $retValue ) . "E6" ;
    }
    elsif ( $value > $tenThousand )
    {
      $retValue = $value / $tenThousand * 10;
      $retValue = sprintf("%2.1f", $retValue ) . "E3" ;
    }
  }
  $retValue;
}

# The Z method for calculating index sizes.
sub calcIdxSizeZ
{
  # for 8k pagesize tablespace 4
  my $recordHeaderSize      = $_[0];
  my $ridSize               = $_[1];
  my $ridFlagSize           = $_[2];

  my $fullkeycard           = $_[3];
  my $leaf_recsize          = $_[4];
  my $indCard               = $_[5];
  if ( $indCard == 1499855 )
  {
    my $bozo = 33;
  }
  my $PctFree               = $_[6];
  my $indexPageSize         = $_[7];
  my $leaf_page_overhead    = $_[8];
  my $nleaf_recsize         = $_[9];
  my $nleaf_page_overhead    = $_[10];

  my $numOfPagesForIdxInObj = 1; #for meta index
  my $leafRecordOverhead = $recordHeaderSize + $ridSize + $ridFlagSize;
  my $nonLeafRecordOverhead = $leafRecordOverhead;   ### hack for now !!!
  my $duplicateKeyOverhead = $ridSize + $ridFlagSize;

  my $numberOfBytesOfDataOnLeafLevel = 
    $fullkeycard * ( $leafRecordOverhead + $leaf_recsize ) +
    ( $indCard - $fullkeycard ) * $duplicateKeyOverhead;

  # average amount of wasted space per page
  my $availableSpacePerLeafPage = 
    ( ( 1.00 - $PctFree/100) * ( $indexPageSize - $leaf_page_overhead ) ) -
    ( ( $leafRecordOverhead + $leaf_recsize ) / 2); 

  my $leafSpaceRequiredInPages = ceil( $numberOfBytesOfDataOnLeafLevel / $availableSpacePerLeafPage );

  $numOfPagesForIdxInObj += $leafSpaceRequiredInPages;
  my $lowerLevelSpaceRequiredInpages = $leafSpaceRequiredInPages;
  my $Level2PctFree =  5; #min( 10, $PctFree );
  my $nonLeafPctFree = $Level2PctFree;

  while( $lowerLevelSpaceRequiredInpages > 1 )
  {
    # average amount of wasted space per non-leaf page
    my $numberOfBytesOfDataOnNonLeaf = 
      ( $lowerLevelSpaceRequiredInpages * ( $nonLeafRecordOverhead + $nleaf_recsize ) ) -
      ( ( $nonLeafRecordOverhead + $nleaf_recsize ) / 2); 

    my $availableSpacePerNonLeafPage = 
      ( 1 - $nonLeafPctFree / 100) * ( $indexPageSize - $nleaf_page_overhead );

    my $nonLeafLevelSpaceRequireInPages = 
      ceil( $numberOfBytesOfDataOnNonLeaf / $availableSpacePerNonLeafPage );

    $numOfPagesForIdxInObj += $nonLeafLevelSpaceRequireInPages;
    $lowerLevelSpaceRequiredInpages = $nonLeafLevelSpaceRequireInPages;
  }

  $numOfPagesForIdxInObj += 1; # for the index info page

  my $numBytesForIdxInObj = $numOfPagesForIdxInObj * $indexPageSize ;

  $numBytesForIdxInObj;
} # CalcIdxSizeZ

# Figure out if the input table have indices in the 32K index tablespace or the 8k one.
# Return the pagesize.
sub getIdxPageSize
{
  my $thisIdxPagesize;
  my $thisTbl = $_[0];
  trace( "BEGIN getIdxPageSize\n");

  if ( $offline_mode == 1)
  {
    my $found = 0;
    my @pageSz32Tbls = ("TEMP_SQL_VOLUMEUSAGE",
                        "SPACEMAN_OBJECTS",
                        "OPTIONS_SQL",
                        "VOLUMES_SQL",
                        "DRMEDIA_SQL",
                        "DRMSRPF_SQL",
                        "DRMTRPF_SQL",
                        "ARCHIVE_OBJECTS",
                        "BACKUP_OBJECTS");
  
    my $currTbl;
    foreach $currTbl ( @pageSz32Tbls )
    {
      if ( $thisTbl eq $currTbl )
      {
        $found = 1;
        last;
      }
    } #foreach
  
    $thisIdxPagesize = ( ( $found == 1 ) ? 32 : 8 ) ;
    $thisIdxPagesize *= 1024;
  }
  else
  {
    $thisIdxPagesize = getIdxPageSize2($thisTbl);
    trace("table = $thisTbl, getIdxPageSize2 = $thisIdxPagesize\n");
  }
  
  $thisIdxPagesize;
} #getIdxPageSize


sub getIdxPageSize2
{
  my $thisTbl = $_[0];
  trace("BEGIN getIdxPageSize2\n");

  my $sql_command="select t1.PAGESIZE from syscat.tablespaces t1 left join syscat.tables t2 on (t1.TBSPACE=t2.INDEX_TBSPACE) where t2.tabname='$thisTbl'";
  &db2Query($sql_command,TEMP_FILE);

  my @wholeFile = ();
  @wholeFile = &getFile(TEMP_FILE);
  unlink TEMP_FILE;
  my $numLines = $#wholeFile;

  my $headerLineNumber = -1;

  my $returnValue;

  for ( $idx = 0; $idx < $numLines; $idx++ )
  {
    my $line = trim($wholeFile[ $idx ]);
    trace("index = $idx, line = $line\n");

    my @items = split( /\s+/, $line );
    my $thisSize = @items;
    trace("thisSize = $thisSize\n");
    trace("items = $items[ 0 ]\n");

    if ( $thisSize == 1 )
    {
      if ( $items[ 0 ] =~ "PAGESIZE" )
      {
        $headerLineNumber = $idx;
        trace("setting headerLineNumber = $headerLineNumber\n");
      }
      if ( ($headerLineNumber != -1)&&
           ($idx == ($headerLineNumber+2)) )
      {
        $returnValue = $items[ 0 ];
        trace("setting returnValue = $returnValue\n");
      }
    }
    else
    {
      next;
    }
  }

  trace("returnValue = $returnValue\n");
  $returnValue;
}

sub getIndexTablespaceName
{
  my $thisTbl = $_[0];

  trace("BEGIN getIndexTablespaceName\n");

  my $sql_command="select t1.index_tbspace from syscat.tables t1 left join syscat.tablespaces t2 on (t1.TBSPACEID=t2.TBSPACEID) where t1.tabname='$thisTbl'";
  &db2Query($sql_command,TEMP_FILE);

  my @wholeFile = ();
  @wholeFile = &getFile(TEMP_FILE);
  unlink TEMP_FILE;
  my $numLines = $#wholeFile;

  my $headerLineNumber = -1;

  my $returnValue;

  for ( $idx = 0; $idx < $numLines; $idx++ )
  {
    my $line = trim($wholeFile[ $idx ]);
    trace("index = $idx, line = $line\n");

    my @items = split( /\s+/, $line );
    my $thisSize = @items;
    trace("thisSize = $thisSize\n");

    if ( $thisSize == 1 )
    {
      if ( $items[ 0 ] =~ "INDEX_TBSPACE" )
      {
        $headerLineNumber = $idx;
      }
      if ( ($headerLineNumber != -1)&&
           ($idx == ($headerLineNumber+2)) )
      {
        $returnValue = $items[ 0 ];
      }
    }
    else
    {
      next;
    }
  }

  $returnValue;
}

sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

sub printFileToDEBUGFILE
{
  trace("BEGIN printFileToDEBUGFILE\n");

  my @wholeFile = ();
  @wholeFile = &getFile(TEMP_FILE);
  my $numLines = $#wholeFile;

  for ( $idx = 0; $idx < $numLines; $idx++ )
  {
    my $line = trim($wholeFile[ $idx ]);
    trace("index = $idx, line = $line\n");
  }
}



sub trace
{
  if ( $verbose_mode == 1 )
  {
    print $DEBUGFILE $_[0];
  }
}


sub unSuccessfulExit
{
  print $_[0];

  if ( $_[1] )
  {
    print "The script was UNSuccessFUL. The log files are in $base_log_directory/$log_sub_directory\n";
  }
  else
  {
    print "The script was UNSuccessFUL.\n";
  }

  exit 1;
}

sub begins_with
{
    if ( substr($_[0], 0, length($_[1])) eq $_[1] )
    {
      return 1;
    }
    else
    {
      return 0;
    }
}
