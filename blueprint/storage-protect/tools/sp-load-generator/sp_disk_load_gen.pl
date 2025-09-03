#!/usr/bin/perl
#********************************************************************************
# IBM Storage Protect
# 
# name: sp_disk_load_gen
#
# desc: Simulates typical IBM Storage Protect workload patterns for assessing
#       the suitability of disk storage.  The workloads are
#       1) 256K sequential read+write simulating overlapped backup ingest
#          and identify duplicates (workload=stgpool mode=writeread)
#       2) 256K sequential write + random read simulating overlapped backup ingest
#          and dedup restore processing (workload=stgpool mode=writerandread)
#       3) 8K random read/write simulating database i/o (workload=db)
#
# usage:  perl sp_disk_load_gen.pl workload=stgpool|db [mode=readonly|writeonly|writeread|writerandread|randreadonly] [readers=num] 
#                                                 [fslist=/fs1,/fs2,...] [devs=dev1,dev2,...] [rand=randlow|randmed|randhigh]
#         (1): the mode option can only be combined with workload=stgpool
#
# Notice: This program is provided as a tool intended for use by IBM Internal, 
#         IBM Business Partners, and IBM Customers. This program is provided as is, 
#         without support, and without warranty of any kind expressed or implied.
#
# (C) Copyright International Business Machines Corp. 2013, 2022
#********************************************************************************
BEGIN
{
 use Config;
 die "Threads not supported\n" unless $Config{'usethreads'};
}

use threads;

$versionString = "Program version 5.1c";
$platform = getPlatform();
$SS = getpathdelimiter($platform);
$ioFlagR = "dio=1";
$ioFlagW = "dio=2";
if ($platform eq "WIN32")
{
  $ddName = "bin/windows/wdeedee.exe";
}
elsif ($platform eq "AIX")
{
  $ddName = "bin/aix/adeedee";
}
elsif ($platform eq "LINUX86")
{
  $ddName = "bin/linux/ldeedee";
}
elsif ($platform eq "LINUXPPC")
{
  $ddName = "bin/ppc-linux/pldeedee";
}
elsif ($platform eq "LINUXPPCLE")
{
  $ddName = "bin/ppc-linux/pleldeedee";
}
else
{
  print "Unsupported platform: $platform\n";
  exit (1);
}

# First check for the deedee tool in the cwd
if (-f ".".$SS.$ddName)
{
  $ddName = ".".$SS.$ddName;
}
else  # build a path based on the full path to sp_disk_load_gen.pl
{
  $fullPath = $0;
  $fullPath =~ m/(.*)(\/|\\)(\w|\.)+$/;
  $ddName = $1.$2.$ddName;
  if (! -f $ddName)
  {
    print "ERROR: Unable to locate required file $ddName\n";
    exit (1);
  }
}
if (! -x $ddName)
{
  print "ERROR: Unable to execute required file $ddName (check permissions)\n";
  exit (1);
}

srand(time);

if (@ARGV < 1 || @ARGV > 5)
{
  print "USAGE: perl sp_disk_load_gen.pl workload=db|stgpool [fslist=/fs1,/fs2,...]\n";
  print "              [mode=readonly|writeonly|writeread|writerandread|randreadonly] [readers=num]\n";
  print "              [devs=dev1,dev2,...] [rand=randlow|randmed|randhigh] [size=xsmall]\n";
  print "    (1): The mode option can only be combined with workload=stgpool\n";
  exit (1);
}

# For Linux, confirm the availability of the iostat command and determine version
my $iostatVers = "";
if ($platform =~ m/LINUX/)
{
  $iostatVers = `iostat -V`;
  if ($iostatVers =~ m/sysstat version (\d+)\.\d+\.\d+/)
  {
    $iostatVers = $1;
  }
  else
  {
    print "ERROR: Unable to execute required file iostat program\n";
    print "  Make sure the sysstat package is installed.\n";
    exit (1);  
  }
}


my ($workload, $mode, $fslist, $fsCount, @fsArray, $size, $rand);
$workload = "";
$mode = "writeread";
$rand = "randmed";         # Default to randmed which targets 2 to 1 compression
$fslist = "";
$devs = "";
@deviceArray = ();
$fsCount = 0;
$devCount = 0;
$readers = -1;
$size = "";

foreach $arg (@ARGV)
{
  if ($arg =~ m/workload=(stgpool|db)/i)    
  {
    $workload = lc($1);
  }
  elsif ($arg =~ m/mode=(readonly|writeonly|writeread|writerandread|randreadonly)/i)    
  {
    $mode = lc($1);
  }
  elsif ($arg =~ m/readers=([0-9]+)/i)    
  {
    $readers = $1;
	if ($readers <= 0)
	{
	  $readers = -1;
	}
  }
  elsif ($arg =~ m/fslist=([\S|,]+)/i)
  {
    $fslist = $1;
    # remove any trailing slashes from file system names
    $fslist =~ s/(\Q$SS\E,)/,/g;
    $fslist =~ s/(\Q$SS\E$)//g;

    @fsArray = split(',', $fslist);
    $fsCount = @fsArray;
  }
  elsif ($arg =~ m/devs=([\S|,]+)/i)
  {
    $devs = $1;
    # remove any trailing slashes from device names
    $devs =~ s/(\Q$SS\E,)/,/g;
    $devs =~ s/(\Q$SS\E$)//g;

    @deviceArray = split(',', $devs);
    $devCount = @deviceArray;
  }
  elsif ($arg =~ m/rand=(randlow|randmed|randhigh)/i)
  {
    $rand = lc($1);
  }
  elsif ($arg =~ m/size=(xsmall)/i)    
  {
    $size = lc($1);
  }

  else
  {
    print "ERROR: Unrecognized argument: $arg\n\n";
    print "USAGE: perl sp_disk_load_gen.pl workload=db|stgpool [fslist=/fs1,/fs2,...]\n";
    print "              [mode=readonly|writeonly|writeread|writerandread|randreadonly] [readers=num]\n";
    print "              [devs=dev1,dev2,...] [rand=randlow|randmed|randhigh] [size=xsmall]\n";
    print "    (1): The mode option can only be combined with workload=stgpool\n";
    exit (1);
  }
}
if ($workload eq "")
{
  print "ERROR: The workload parameter must be specified\n\n";
  print "USAGE: perl sp_disk_load_gen.pl workload=db|stgpool [fslist=/fs1,/fs2,...]\n";
  print "              [mode=readonly|writeonly|writeread|writerandread|randreadonly] [readers=num]\n";
  print "              [devs=dev1,dev2,...] [rand=randlow|randmed|randhigh] [size=xsmall]\n";
  print "    (1): The mode option can only be combined with workload=stgpool\n";
  exit (1);
}
if ($workload eq "db" && $mode ne "writeread")
{
  print "USAGE: perl sp_disk_load_gen.pl workload=db|stgpool [fslist=/fs1,/fs2,...]\n";
  print "              [mode=readonly|writeonly|writeread|writerandread|randreadonly] [readers=num]\n";
  print "              [devs=dev1,dev2,...] [rand=randlow|randmed|randhigh] [size=xsmall]\n";
  print "    (1): The mode option can only be combined with workload=stgpool\n";
  exit (1);
}


my ($blockSizeKB, $blockCount, $blockCountDB, $i, $j, $k, @semArray);
my ($dbThreadPerFS, $dbIOPerThread, $dbBatchIO, $totalDbIO, $totalMRIO);

# Variables
$filePrefix = "disk_perf_";       # prefix of filenames like disk_perf_0_1


# Some variables depend on the workload type
if ($workload eq "stgpool")
{
  $blockSizeKB="256";
  if ($mode eq "readonly" || $mode eq "randreadonly")
  {
    $fileSizeGB = 5;                   # size of each test file in GB
    $fileCount = 1;                    # number of files to iterate through per filesystem
  }
  else
  {
    $fileSizeGB = 2;                   # size of each test file in GB
    $fileCount = 5;                    # number of files to iterate through per filesystem
  }
  if ($platform eq "WIN32")
  {
    $fsPrefix = "c:${SS}tsminst1${SS}TSMfile";   # prefix of filesystems to test against
  }
  else
  {
    $fsPrefix = "/tsminst1/TSMfile";   # prefix of filesystems to test against
  }
  if ($fsCount == 0)
  {
    $fsCount = 7;                    # number of file systems to include in the test
  }
  # IO total per read thread per file in random read modes only
  $totalMRIO = int(($fileSizeGB * 1024 * 1024) / $blockSizeKB); 
}
elsif ($workload eq "db")
{
  $blockSizeKB="8";
  $fileSizeGB = 10;                   # size of each test file in GB
  $dbThreadPerFS = 2;                # number of threads per FS for db workload -- use even number
  if ($size eq "xsmall")
  {
    $dbIOperThread = 5000;           # number of i/o's per thread
  }
  else
  {
    if ($fsCount <= 4)
    {
      $dbIOperThread = 250000;
    }
    elsif ($fsCount <= 8)
    {
      $dbIOperThread = 500000;
    }
    else
    {
      $dbIOperThread = 350000;
    }
  }
  $fileCount = $dbThreadPerFS;
  if ($platform eq "WIN32")
  {
    $fsPrefix = "c:${SS}tsminst1${SS}TSMdbspace";# prefix of filesystems to test against
  }
  else
  {
    $fsPrefix = "/tsminst1/TSMdbspace";# prefix of filesystems to test against
  }
  if ($fsCount == 0)
  {
    $fsCount = 3;                    # number of file systems to include in the test
  }

  $totalDbIO = $dbIOperThread;       # IO total per thread for output purposes
}
else
{
   die "ERROR: invalid workload specified\n";
}


# Calculate the number of blocks need to reach the file size
$blockCount = int((1024 * 1024 * $fileSizeGB) / ($blockSizeKB));
$blockCountDB = (1024 * 1024 * $fileSizeGB) / (1024) ;


# Build a list of the file systems to test if not given as an argument
# Also cleanup residual files from any previous test
for ($i=0; $i<$fsCount; $i++)
{
  if ($i < 10)
  {
    push(@fsArray, ${fsPrefix}."0".${i}) if ($fslist eq ""); 
  }
  else
  {
    push(@fsArray, ${fsPrefix}.${i}) if ($fslist eq ""); 
  }
  for ($j = 1; $j <= $fileCount; $j++)
  {
    unlink ${fsArray[$i]}.$SS.$filePrefix.$i."_".$j;
    unlink ${fsArray[$i]}.$SS.$filePrefix."_1";
  }
}


# Ensure all of the specified test directories exist
foreach $fs (@fsArray)
{
  if (! -d $fs)
  {
    print "ERROR: The directory $fs does not exist\n";
    exit (1);
  }
}


# Now build a list of file systems that are actually backed by the directory list
# There may be fewer file systems than directories for some types of devices
# This list is used later as we pull from iostat output
@realFSList = qw();
if ($platform eq "WIN32")
{
  @mountOutput = `mountvol`;
}
else
{
  @mountOutput = `mount`;
}
$isGPFS = 0;
foreach $fs (@fsArray)
{
  # Gradually trim off directories until a file system is found
  $path="";
  if ($platform eq "WIN32")
  {
    @dirParts = split (m/\\/, $fs);
  }
  else
  {
    @dirParts = split ('/', $fs);
    $dirParts[0] = $SS;
  }
  foreach $dir (@dirParts)
  {
    if ($dir =~ m/\w\:$/)        # Include Windows drive letter with preceeding slash
    {
      $path = uc($dir).$SS;      
    }
    else
    {
      $path = $path.$dir.$SS; 
    }
    $path =~ s/${SS}${SS}/${SS}/g;  # remove any double slashes
    push (@pathList, $path);
  }

  for ($i=$#pathList; $i>=0; $i--)
  {
    $path = $pathList[$i];
    if ($platform ne "WIN32")
    {
      chop($path);
    }

    if ((grep {m/\s\Q$path\E\s/} @mountOutput) && ($path ne "/"))
    {
        $path =~ s/(\w\:\S*)\\/$1/;    # Trim off trailing slash for Windows
        if (! grep {m/\Q$path\E/} @realFSList)   # Only add unique file systems
        {
          push (@realFSList, $path);
          if ( (grep {m/\s\Q$path\E\s+type\s+gpfs\s/} @mountOutput) ||
               (grep {m/\s\Q$path\E\s+mmfs\s/} @mountOutput))  # Determine if FS is GPFS
          {
            $isGPFS++;
            $ioFlagR = "";  # Recommendation is to disable direct-IO with GPFS
            $ioFlagW = "";  	
          }
        }
        last;
    }
  }
}

if ( (substr($ioFlagR, 0, 3) eq "dio" or substr($ioFlagW, 0, 3) eq "dio") and $blockSizeKB % 4 != 0 ) {
  die "Block size must be divisible by 4K when using direct I/O options\n";
}

print "======================================================================\n";
print ": IBM Storage Protect disk performance test\t($versionString)\n";
print ":\n";
print ": Workload type:\t\t$workload\n";
print ": Number of filesystems:\t$fsCount\n";
print ": Mode:\t\t\t\t$mode\n";
if ($workload eq "stgpool" && $mode ne "writerandread" && $mode ne "randreadonly")
{
  print ": Files to write per fs:\t$fileCount\n";
}
elsif ($workload eq "stgpool")  # Random read version
{
  print ": Files to write per fs:\t$fileCount\n";
  print ": I/Os per read thread:\t\t$totalMRIO\n";
}
elsif ($workload eq "db")
{
  print ": Thread count per FS:\t\t$dbThreadPerFS\n";
  print ": I/Os per thread:\t\t$totalDbIO\n";
}
if ($readers > 0 && ($mode eq "writerandread" || $mode eq "randreadonly"))
{
  print ": Readers thread limit:\t\t$readers\n"; # Random reads only
}
print ": File size:\t\t\t$fileSizeGB GB\n";
print ":\n";
print "======================================================================\n";

# For DB workload, prime each filesystem with a large file.
# Also for "readonly" and "randreadonly" stgpool modes.

if ($workload eq "db" || ($workload eq "stgpool" && ($mode eq "readonly" || $mode eq "randreadonly")))
{
  print ":\n";
  $prepBlockCount = $blockCountDB;
  if ($workload eq "db")
  {
    print ": Creating files of $fileSizeGB GB to simulate IBM Storage Protect DB.\n";
  }
  else
  {
    print ": Creating files of $fileSizeGB GB to prepare to simulate IBM Storage Protect Stgpool for reads.\n";
  }
  my @child_pids=();
  my $ddcmd = "";
  foreach $fs (@fsArray)
  {
    for ($j = 1; $j <= $fileCount; $j++)
    {
      if ($platform eq "WIN32")
      {
        $ddcmd = $ddName." if=/dev/".$rand." of=".$fs.$SS.${filePrefix}."_${j} bs=1024k count=$prepBlockCount $ioFlagW > NUL 2>&1";
      }
      else
      {
        $ddcmd = $ddName." if=/dev/".$rand." of=".$fs.$SS.${filePrefix}."_${j} bs=1024k count=$prepBlockCount $ioFlagW > /dev/null 2>&1";
      }

      sleep 1;
      if ($pid = fork())
      {
        push(@child_pids, $pid);
      }
      else
      {
        print ": Issuing command $ddcmd\n";
        exec("$ddcmd");
      }
    }
  }

  foreach $child (@child_pids)   # parent waits for children to finish
  {       
    waitpid($child, 0);
  }

  sleep 2;

}


# Sub routine for write thread for stgpool workload
sub writeThreadStgpool
{
  my $indx = shift(@_);
  my $self = threads->self();

  print ": Starting write thread ID: ", $self->tid, " on filesystem $fsArray[${indx}]\n";
 
  for (my $q = 1; $q <= $fileCount; $q++)
  {
    
    my $ddcmd = $ddName." if=/dev/".$rand." of=".$fsArray[${indx}].$SS."${filePrefix}${indx}_${q} bs=${blockSizeKB}k count=$blockCount $ioFlagW 2>&1";

    # Write the file which will later be read
    #print "Issuing command $ddcmd\n";
    `$ddcmd`;

  }
}


# Sub routine for read thread for stgpool workload
sub readThreadStgpool
{
  my $indx = shift(@_);
  my $self = threads->self();
  my $filename = "";
  my $lastfile;

  print ": Starting read thread ID: ", $self->tid, " on filesystem $fsArray[${indx}]\n";

  if ($mode eq "readonly")
  {
    $lastfile = $fileCount+1;
  }
  else
  {
    $lastfile = $fileCount;
  }

  # Read all except the last file
  for (my $q = 1; $q < $lastfile; $q++)
  {
    # Wait until the next file exists before reading the previous, except in the readonly case
    my $next = $q + 1;
    if ($mode eq "readonly")
    {
      $next = $q;
      $filename = $filePrefix;
    }
    else
    {
      $filename = $filePrefix.${indx};
    }
    my $nextFile = $fsArray[${indx}].$SS.${filename}."_".$next;
    while (! -e $nextFile)
    {
      sleep 1;
    }

    if (! -e "iostatout.txt")
    {
      # Create iostat file to allow the iostat collection to begin
      open (IOSTAT, ">>iostatout.txt") or die "ERROR opening file: iostatout.txt\n";
      close (IOSTAT);
    }

    my $ddcmd = $ddName." if=".$fsArray[${indx}].$SS.${filename}."_${q} of=/dev/null bs=${blockSizeKB}k $ioFlagR 2>&1";

    #print "Issuing command: $ddcmd\n";
    `$ddcmd`;
  }

}


# Sub routine for random write thread for DB workload
sub writeThreadDb
{
  my $pth = shift(@_);
  my $seq = shift(@_);
  my $self = threads->self();
  my $seeknum = 0;
  my $tid = $self->tid();

  #print "Write thread ", $tid, " started \n";

  my $ddcmd = $ddName." if=/dev/".$rand." of=".${pth}.$SS.$filePrefix."_${seq} bs=${blockSizeKB}k count=1 conv=notrunc iterations=${dbIOperThread} $ioFlagW 2>&1";

  #print "Issuing command $ddcmd\n";
  `$ddcmd`;


}


# Sub routine for random read thread for DB workload
sub readThreadDb
{
  my $pth = shift(@_);
  my $seq = shift(@_);
  my $self = threads->self();
  my $seeknum = 0;
  my $tid = $self->tid;

  #print "Read thread ", $tid, " started \n";

  # Create iostat file to allow the iostat collection to begin
  if (! -e "iostatout.txt")
  {
    open (IOSTAT, ">>iostatout.txt") or die "ERROR opening file: iostatout.txt\n";
    close (IOSTAT);
  }

  my $ddcmd = $ddName." if=".${pth}.$SS.$filePrefix."_${seq} of=/dev/null bs=${blockSizeKB}k count=1 iterations=${dbIOperThread} $ioFlagR 2>&1";

  #print "Issuing command $ddcmd\n";
  `$ddcmd`;

}


# Sub routine for random read thread for storage pool workload
sub readThreadRandStgpool
{
  my $indx = shift(@_);
  my $self = threads->self();
  my $filename = "";
  my $lastfile;

  print ": Starting random read thread ID: ", $self->tid, " on filesystem $fsArray[${indx}]\n";

  if ($mode eq "randreadonly")
  {
    $lastfile = $fileCount+1;
  }
  else
  {
    $lastfile = $fileCount;
  }

  # Read all except the last file
  for (my $q = 1; $q < $lastfile; $q++)
  {
    # Wait until the next file exists before reading the previous, except in the randreadonly case
    my $next = $q + 1;
    if ($mode eq "randreadonly")
    {
      $next = $q;
      $filename = $filePrefix;
    }
    else
    {
      $filename = $filePrefix.${indx};
    }
    my $nextFile = $fsArray[${indx}].$SS.${filename}."_".$next;
    while (! -e $nextFile)
    {
      sleep 1;
    }

    if (! -e "iostatout.txt")
    {
      # Create iostat file to allow the iostat collection to begin
      open (IOSTAT, ">>iostatout.txt") or die "ERROR opening file: iostatout.txt\n";
      close (IOSTAT);
    }

    my $ddcmd = $ddName." if=".$fsArray[${indx}].$SS.${filename}."_${q} of=/dev/null bs=${blockSizeKB}k count=1 iterations=${totalMRIO} $ioFlagR 2>&1";

    #print "Issuing command: $ddcmd\n";
    `$ddcmd`;
  }
}


# Begin I/O test here
print ":\n";
print ": Beginning I/O test.\n";
print ": The test can take upwards of ten minutes, please be patient ...\n";

# Record the starting time
$startTime = time();

# Get the correspondence between filesystems and devices from lsblk or mountvol output

if ($isGPFS > 0)  # Prepare to use the mmpmon command
{
  $commandReset = "commandReset.txt";
  $commandFile = "commandFile.txt";

  # Verify the mmpmon command is present
  $mmpmon = `which mmpmon 2>&1`;
  if ($mmpmon =~ m/no\s+mmpmon/)
  {
    $mmpmon = "/usr/lpp/mmfs/bin/mmpmon";
    if (! -f $mmpmon)
    {
      die "ERROR: Unable to locate the mmpmon command\n";
    }
  }
  chomp ($mmpmon);

  open (CMDFILE, ">$commandReset") or die "ERROR opening file: $commandReset\n";
  print CMDFILE "reset\n";
  close (CMDFILE);
  open (CMDFILE, ">$commandFile") or die "ERROR opening file: $commandFile\n";
  print CMDFILE "io_s\n";
  close (CMDFILE);

  @deviceArray = @realFSList;
}
else
{
  if ($platform eq "WIN32")  # For Windows, prepare list of counters to monitor
  {
    open (COUNTERS, ">wincounters.txt") or die "ERROR opening file: wincounters.txt\n";
    @counterList = ("Disk Reads/sec", "Disk Writes/sec", "Disk Transfers/sec",
                  "Disk Read Bytes/sec", "Disk Write Bytes/sec", "% Idle Time");

    foreach $fs (@realFSList)
    {
      push(@deviceArray, "\\LogicalDisk(".$fs.")\\*");
      foreach $counter (@counterList)
      {
        print COUNTERS "\\LogicalDisk(".$fs.")\\".$counter."\n";
      }
    } 

    close (COUNTERS);
  }
  elsif ( $platform eq "AIX" ) {
    if ($devCount == 0)  # Skip device pairing if user provided device list
    {
      @dfOut = `df`;
      @mountOut = `mount`;
      foreach $fs (@realFSList) {
        # Warn about any file systems that are not mount with dio option
        # Note: now that we use adeedee, there is no longer a need to mount with dio option
        #if (!grep {m/\Q$fs\E.*dio/} @mountOut)
        #{
        #  print "WARNING: File system $fs is not mounted with dio option\n";
        #}

        foreach $dfoutline (@dfOut) {
          if ( $dfoutline =~ m/^\/dev\/(\S+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+$fs\s*/ ){
            $lvName  = $1;
            @lvlsOut = `lslv -l $lvName`;
            foreach $lvlsoutline (@lvlsOut) {
              next if ($lvlsoutline =~ m/^PV\s+COPIES\s+IN BAND\s+DISTRIBUTION\s*/);
              if ($lvlsoutline =~ m/^(\S+)\s+\S+\s+\S+\s+\S+\s*/ ) {
                $pvName = $1;
                if ( iscontained( $pvName, \@deviceArray ) == 0 ) {
                  push( @deviceArray, $pvName );
                }
              }
            }
          }
        }
      }
    }
  } 
  else
  {
    if ($devCount == 0)  # Skip device pairing if user provided device list
    {
      @lsblkOut = `lsblk -l -o NAME,KNAME,MOUNTPOINT`;

      foreach $lsblkoutline (@lsblkOut)
      {
        if ($lsblkoutline =~ m/\S*\s*(dm-\d+|fio\w+|sd\w+|xvd\w+|rbd\d+|md\d+|^\S\S\S\S\S\S\S\S\S\S\S+)\s+(\/\S+)/)
        {
          $devnm = $1; 
          $fsmntpnt = $2;
          
          if ($devnm =~ m/(xvd[^\d]+)\d+/)
          {
          	$devnm = $1;
          }
          
  
          if (iscontained($fsmntpnt, \@realFSList) == 1)
          {
            if (iscontained($devnm, \@deviceArray) == 0) 
            {
              push(@deviceArray, $devnm);
            }
          }
        }
      }
    }

    if (@deviceArray < 1)
    {
      print ":\n";
      print ":  ERROR: Unable to map file systems from the fslist to device names.\n";
      print ":         Verify proper multipath setup with these commands:\n";
      print ":           lsblk -l -o NAME,KNAME,MOUNTPOINT\n";
      print ":           multipath -l\n";
      print ":         Alternatively, manually specify the mappings with devs=DEV1,DEV2,...\n";
  
    }

  }
}

# Cleanup any existing iostat output file
unlink ("iostatout.txt");

# Launch a separate process for running iostat to collect performance data
if ($runiostat = fork())
{
}
else
{
  # We wait for overlapped read and write activity to avoid contaminating the
  # iostat averages taken for read
  while (! -e "iostatout.txt")
  {
    sleep 1;
  }
  if ($isGPFS > 0)
  {
    `$mmpmon -p -i $commandReset`;   # reset performance counters
    unlink ("$commandReset");
    exec("$mmpmon -p -i $commandFile -d 3000 -r 0 > iostatout.txt 2>&1");
  }
  elsif ($platform eq "WIN32")
  {
    exec("typeperf -cf wincounters.txt -f csv -o iostatout.txt -si 7 -y > NUL");
    $perfProg = "typeperf";
  }
  elsif ($platform eq "AIX"){
  	exec("sh -c \"export LANG=en_US; iostat -TdDl 7 > iostatout.txt\"");
  	$perfProg = "iostat";
  }
  else
  {
    exec("sh -c \"export LANG=en_US; iostat -xtk 7 > iostatout.txt\"");
    $perfProg = "iostat";
  }
}


# Launch IO workloads in separate threads
my @threads;

my $rlimit = $fsCount;
my $rcount = 0;
if ( $readers > 0 && $readers < $fsCount )
{
  $rlimit = $readers;
}
if ($workload eq "stgpool")
{
  for ($i = 0; $i < $fsCount; $i++)
  {
    if ($mode eq "writeread" || $mode eq "writerandread")  # Need writer threads
    {
      push(@threads, threads->create('writeThreadStgpool', $i));
      if ($mode eq "writeread")  # Sequential reader threads
      {
	    if ( $rcount < $rlimit )
		{
          push(@threads, threads->create('readThreadStgpool', $i));
		  $rcount++;
		}
      }
      else   # Random reader threads
      {
	    if ( $rcount < $rlimit )
		{
          push(@threads, threads->create('readThreadRandStgpool', $i));
		  $rcount++;
		}
      }
    }
    elsif ($mode eq "writeonly")
    {
      push(@threads, threads->create('writeThreadStgpool', $i));
      # Create iostat file to allow the iostat collection to begin, normally handled in read thread
      if (! -e "iostatout.txt")
      {
        open (IOSTAT, ">>iostatout.txt") or die "ERROR opening file: iostatout.txt\n";
        close (IOSTAT);
      }
    }
    elsif ($mode eq "readonly")  # Sequential reader threads
    {
	  if ( $rcount < $rlimit )
	  {
        push(@threads, threads->create('readThreadStgpool', $i));
		$rcount++;
      }
    }
    elsif ($mode eq "randreadonly")  # Random reader threads
    {
	  if ( $rcount < $rlimit )
	  {
        push(@threads, threads->create('readThreadRandStgpool', $i));
		$rcount++;
	  }
    }
  }
}
elsif ($workload eq "db")
{
  my $threadcount = 1;
  foreach $fs (@fsArray)
  {
    for ($i=1; $i <= $fileCount; $i+=2)
    {
      if ($mode eq "writeread")
      {
        push(@threads, threads->create('writeThreadDb', $fs,$i));
        push(@threads, threads->create('readThreadDb', $fs,$i+1));
      }
      elsif ($mode eq "writeonly")
      {
        push(@threads, threads->create('writeThreadDb', $fs,$i));
        # Create iostat file to allow the iostat collection to begin, normally handled in read thread
        if (! -e "iostatout.txt")
        {
          open (IOSTAT, ">>iostatout.txt") or die "ERROR opening file: iostatout.txt\n";
          close (IOSTAT);
        }
      }
      elsif ($mode eq "readonly")
      {
        push(@threads, threads->create('readThreadDb', $fs,$i+1));
      }
    }
  }
}

sleep 5;
while (my $thread = shift @threads)
{
  $thread->join();
}

# record the ending time, and calculate number of seconds
$endTime = time();
$elapsedSeconds = $endTime - $startTime;

# Have seen issues on Windows where proceeding past this point too quickly causes hangs with typeperf.  
# Adding a sleep to give time for threads to completely stop
sleep 2;

if ($platform eq "WIN32")
{
  $qproccmd = "tasklist | findstr typeperf.exe";

  @qproccmdOut = `$qproccmd`;

  foreach $qprocOutln (@qproccmdOut)
  {
    if ($qprocOutln =~ m/typeperf.exe\s+(\d+)\s+\w+/)
    {
      $iostatprocid = $1;
    }
  }

  print ": All threads are finished.  Stopping typeperf process with id $iostatprocid\n";
  system("taskkill /pid $iostatprocid /f");
}
elsif ( $platform eq "AIX" ){
  $qproccmd = "ps -ef";

  @qproccmdOut = `$qproccmd`;

  foreach $qprocOutln (@qproccmdOut)
  {
    if ( ($isGPFS < 1) && ($qprocOutln =~ m/\S+\s+(\d+)\s+\d+\s+\d+\s+\S+\s+\S+\s+\S+\s+iostat -TdDl/) )
    {
      $iostatprocid = $1;
    }
    elsif ( ($isGPFS > 0) && ($qprocOutln =~ m/\S+\s+(\d+)\s+\d+\s+\d+\s+\S+\s+.*mmpmon\s+3000\s+/) )
    {
      $iostatprocid = $1;
    }
  }

  print ": All threads are finished.  Stopping iostat process with id $iostatprocid\n";
  if ( $iostatprocid ne "" ) {
     system("kill -2 $iostatprocid");
  }
}
else
{
  if ($isGPFS > 0)
  {
    $qproccmd = "ps -ef | grep mmpmon";
    $signal = "-2";
  }
  else
  {
    $qproccmd = "ps -ef | grep iostat";
    $signal = "-2";
  }

  @qproccmdOut = `$qproccmd`;

  foreach $qprocOutln (@qproccmdOut)
  {
    if ($qprocOutln =~ m/\S+\s+(\d+)\s+\d\d+\s+\d+\s+\S+\s+\S+\s+\S+\s+iostat\s+-xtk/)
    {
      $iostatprocid = $1;
    }
    elsif ($qprocOutln =~ m/\S+\s+(\d+)\s+\d\d+\s+\d+\s+\S+\s+\S+\s+\S+\s+.*mmpmon\s+3000\s+/)
    {
      $iostatprocid = $1;
    }
  }

  print ": All threads are finished.  Stopping iostat process with id $iostatprocid\n";
  system("kill $signal $iostatprocid");
}


# Cleanup test files
for ($i=0; $i<$fsCount; $i++)
{
  for ($j = 1; $j <= $fileCount; $j++)
  {
    unlink $fsArray[$i].$SS.$filePrefix.$i."_".$j;
    unlink $fsArray[$i].$SS.$filePrefix."_".$j;
  }
}
if ($isGPFS > 0)
{
  unlink ("$commandFile");
  unlink ("$runmmpmon");
}


print "===================================================================\n";
print ":  RESULTS:\n";


open(IOSTATH, "<iostatout.txt") or die "Unable to open iostatout.txt\n";
@iostatcontents = <IOSTATH>;
close IOSTATH;

# For Windows, reformatting typeperf output to match the Linux iostat output
if ($platform eq "WIN32")
{
  foreach $line (@iostatcontents)
  {
    next if ($line !~ m/\d\d\/\d\d\/\d\d\d\d/);
    @elements = split (',', $line);
    $item = shift(@elements)."\n";
    $item =~ s/\"//g;
    push (@newcontents, $item);     # Write the time stamp on its own line
    foreach $d (@deviceArray)
    {
      $newline = $d;
      for ($i = 0; $i <= $#counterList; $i++)
      {
        $item = shift(@elements);
        $item =~ s/\"//g;
        $newline = $newline."\t".$item;
      }
      push (@newcontents, $newline."\n");
    }
  }
  @iostatcontents = @newcontents;
  unlink ("wincounters.txt");
}


if (@deviceArray < 1)
{
  print ":\n";
  print ":  ERROR: Unable to map file systems from the fslist to device names.\n";
  print ":         Result analysis will be skipped.\n";
  exit (1);
}
else
{
  @missingDevs = ();
  print ":  Devices reported on from $perfProg output:\n";
  foreach $d (@deviceArray)
  {
    if (grep {m/\Q$d\E/} @iostatcontents)
    {
      print ":  $d\n";
    }
    else
    {
      push (@missingDevs, $d);
    }
  }
  print ":\n";
}

# Warn on any devices not detected in iostat output
if (@missingDevs > 0)
{
  print ":  WARNING: The following devices were not detected in the iostat output:\n";
  print ":    @missingDevs\n";
  print ":\n";
}


$laststanzadate = "";
$laststanzatime = "";
$stanzatotal = 0;

@stanzaInfoArray = ();

# Summarize the iostat or mmpmon output
if ($isGPFS > 0)
{
  $lastSec = 0;

  foreach $iostatline (@iostatcontents)
  {
    if($iostatline =~ m#^\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s+(\S+)\s+\S+\s+(\S+)\s+\S+\s+(\S+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s+(\S+)\s+\S+\s+#)
    {  
      $numSec = $1;    # _t_
      $micSec = $2;    # _tu_
      $bytesR = $3;    # _br_
      $bytesW = $4;    # _bw_
      $numReads = $5;  # _rdc_
      $numWrites = $6;  # _wc_

      if ($lastSec != 0)
      {
        $elapsed = ($numSec - $lastSec) + (($micSec - $lastMic) / 1000000);
        $curReads = $numReads - $lastReads;
        $curWrites = $numWrites - $lastWrites;
        $iopstotal = ($curReads + $curWrites) / $elapsed;
        $curBR = $bytesR - $lastBR;
        $curBW = $bytesW - $lastBW;
        $thrpRtotal = getCapByKB($curBR) / $elapsed;
        $thrpWtotal = getCapByKB($curBW) / $elapsed;
        $thrpCtotal = getCapByKB($curBR + $curBW) / $elapsed;

        my $stanzainfo = {};  # start new info hash for this iostat stanza
        $stanzainfo->{date} = "";
        $stanzainfo->{time} = $numSec; 
        $stanzainfo->{iopstotal} = $iopstotal;
        $stanzainfo->{thrptotal} = $thrpCtotal;
        $stanzainfo->{thrpRtotal} = $thrpRtotal;
        $stanzainfo->{thrpWtotal} = $thrpWtotal;
		
        push(@stanzaInfoArray, $stanzainfo);

      }

      $lastSec = $numSec;
      $lastMic = $micSec;
      $lastBR = $bytesR;
      $lastBW = $bytesW;
      $lastReads = $numReads;
      $lastWrites = $numWrites;
    }

  }#end for loop
}

elsif ($platform eq "AIX")
{
  # AIX iostat repeats headers mid-stanza, so throw away extras
  $lastTime = "";
  $header = "";
  @tmpOut = qw();
  foreach $iostatline (@iostatcontents)
  {
    if($iostatline =~ m#^Disks:\s+xfers\s+read\s+write\s+queue\s+time\s*#)
    {
      $header = $iostatline;
    }
    elsif ($iostatline =~ m#hdisk.*(\d\d:\d\d:\d\d)#)
    {
      if ($lastTime eq $1)
      {
        push (@tmpOut, $iostatline);
      }
      else
      {
        $lastTime = $1;
        push (@tmpOut, $header);
        push (@tmpOut, $iostatline);
      }
    }
  }
  @iostatcontents = @tmpOut;

  foreach $iostatline (@iostatcontents)
  {
    if($iostatline =~ m#^Disks:\s+xfers\s+read\s+write\s+queue\s+time\s*#)
    {    
      if ($laststanzatime ne "")
      {
        my $stanzainfo = {};  # start new info hash for this iostat stanza
	
        $stanzainfo->{date} = $laststanzadate;
        $stanzainfo->{time} = $laststanzatime; 
        $stanzainfo->{iopstotal} = $stanzaiopstotal;
        $stanzainfo->{thrptotal} = $stanzathrptotal;
        $stanzainfo->{thrpRtotal} = $stanzathrpRtotal;
        $stanzainfo->{thrpWtotal} = $stanzathrpWtotal;
		
        push(@stanzaInfoArray, $stanzainfo);
      }
      $laststanzadate = "";
      $laststanzatime = "";
      $stanzaiopstotal = 0;  # reset to 0
      $stanzathrptotal = 0;
      $stanzathrpRtotal = 0;
      $stanzathrpWtotal = 0;
    }
    elsif($iostatline =~ m#^(\S+)\s+\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d\d:\d\d:\d\d)#)
    {  
      #Disks:      xfers     read    write   queue   time
      $devc = $1;
      $riops = $4; #r/s->rps
      $wiops = $5; #w/s->wps
      $rthrp = getCapByKB($2); #rkB/s ->bread
      $wthrp = getCapByKB($3); #wkB/s ->bwrtn
	      
      $laststanzatime = $6;
      if (iscontained($devc, \@deviceArray) == 1)
      {
        $stanzaiopstotal += ($riops + $wiops);
        $stanzathrpRtotal += $rthrp;
        $stanzathrpWtotal += $wthrp;
        $stanzathrptotal += ($rthrp + $wthrp);
      }
    }	
  }#end for loop
}
else   # Linux and Windows
{
  foreach $iostatline (@iostatcontents)
  {
    if ($iostatline =~ m#(\d\d/\d\d/\d\d\d\d)\s+(\d\d:\d\d:\d\d)#)  # get time stamp at start of new stanza
    {
      $currstanzadate = $1;
      $currstanzatime = $2;
	
      if ($laststanzatime ne "")
      {
        my $stanzainfo = {};  # start new info hash for this iostat stanza
	
        $stanzainfo->{date} = $laststanzadate;
        $stanzainfo->{time} = $laststanzatime; 
        $stanzainfo->{iopstotal} = $stanzaiopstotal;
        $stanzainfo->{thrptotal} = $stanzathrptotal;
        $stanzainfo->{thrpRtotal} = $stanzathrpRtotal;
        $stanzainfo->{thrpWtotal} = $stanzathrpWtotal;
	
        push(@stanzaInfoArray, $stanzainfo);
      }
	
      $laststanzadate = $currstanzadate;
      $laststanzatime = $currstanzatime;
      $stanzaiopstotal = 0;  # reset to 0
      $stanzathrptotal = 0;
      $stanzathrpRtotal = 0;
      $stanzathrpWtotal = 0;
    }
    elsif ($iostatline =~ m/(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/)
    {
      if ($platform eq "WIN32")
      {
        $devc = $1;
        $riops = $2;
        $wiops = $3;
        $rthrp = $5/1024;
        $wthrp = $6/1024;
      }
      elsif ($iostatVers ge "12")
      {
        $devc = $1;
        $riops = $2;
        $wiops = $8;
        $rthrp = $3;
        $wthrp = $9;
      }
      elsif ($iostatVers ge "11")
      {
        $devc = $1;
        $riops = $2;
        $wiops = $3;
        $rthrp = $4;
        $wthrp = $5;
      }
      else
      {
        $devc = $1;
        $riops = $4;
        $wiops = $5;
        $rthrp = $6;
        $wthrp = $7;
      }
	
      if (iscontained($devc, \@deviceArray) == 1)
      {
        $stanzaiopstotal += ($riops + $wiops);
        $stanzathrpRtotal += $rthrp;
        $stanzathrpWtotal += $wthrp;
        $stanzathrptotal += ($rthrp + $wthrp);
      }
    }
  }  # end of for loop
}

# Get the last stanza, including cumulative throughput for averaging

my $stanzainfo = {};  # start new info hash for this iostat stanza

$stanzainfo->{date} = $laststanzadate;
$stanzainfo->{time} = $laststanzatime;
$stanzainfo->{iopstotal} = $stanzaiopstotal;
$stanzainfo->{thrpRtotal} = $stanzathrpRtotal;
$stanzainfo->{thrpWtotal} = $stanzathrpWtotal;
$stanzainfo->{thrptotal} = $stanzathrptotal;

push(@stanzaInfoArray, $stanzainfo);
 
$overalliopstotal = 0;
$overallthrpRtotal = 0;
$overallthrpWtotal = 0;
$stanzacount = 0;
$maxiops = 0;
$maxRthrp = 0;
$maxWthrp = 0;
$maxCmbThrp = 0;
$maxiopsstanza = 0;
$maxthrpRstanza = 0;
$maxthrpWstanza = 0;
$maxthrpCmbstanza = 0;

$numstanzas = @stanzaInfoArray;

for ($p = 0; $p < $numstanzas; $p++)  
{
  $overalliopstotal += $stanzaInfoArray[$p]->{iopstotal};
  $overallthrpRtotal += $stanzaInfoArray[$p]->{thrpRtotal};
  $overallthrpWtotal += $stanzaInfoArray[$p]->{thrpWtotal};

  if ($stanzaInfoArray[$p]->{iopstotal} > $maxiops)
  {
    $maxiops = $stanzaInfoArray[$p]->{iopstotal};
    $maxiopsstanza = $stanzacount;
  }

  if ($stanzaInfoArray[$p]->{thrpRtotal} > $maxRthrp)
  {
    $maxRthrp = $stanzaInfoArray[$p]->{thrpRtotal};
    $maxthrpRstanza = $stanzacount;
  }
  if ($stanzaInfoArray[$p]->{thrpWtotal} > $maxWthrp)
  {
    $maxWthrp = $stanzaInfoArray[$p]->{thrpWtotal};
    $maxthrpWstanza = $stanzacount;
  }
  if ($stanzaInfoArray[$p]->{thrptotal} > $maxCmbThrp)
  {
    $maxCmbThrp = $stanzaInfoArray[$p]->{thrptotal};
    $maxthrpCmbstanza = $stanzacount;
  }
  $stanzacount++;
}

$averageiops = $overalliopstotal / $stanzacount;
$averageRthrp = $overallthrpRtotal / $stanzacount;
$averageWthrp = $overallthrpWtotal / $stanzacount;
$averageCthrp = ($averageRthrp + $averageWthrp) / 1024;
$maxCthrp = $maxCmbThrp / 1024;

printf (":  Average R Throughput (KB/sec):\t%.2f\n",$averageRthrp);
printf (":  Average W Throughput (KB/sec):\t%.2f\n",$averageWthrp);
printf (":  Avg Combined Throughput (MB/sec):\t%.2f\n",$averageCthrp);
printf (":  Max Combined Throughput (MB/sec):\t%.2f\n",$maxCthrp);

$iopspeak = $stanzaInfoArray[$maxiopsstanza]->{iopstotal};
$iopspeakdate = $stanzaInfoArray[$maxiopsstanza]->{date};
$iopspeaktime = $stanzaInfoArray[$maxiopsstanza]->{time};

$thrpRpeak = $stanzaInfoArray[$maxthrpRstanza]->{thrpRtotal};
$thrpWpeak = $stanzaInfoArray[$maxthrpWstanza]->{thrpWtotal};
$thrpRpeakdate = $stanzaInfoArray[$maxthrpRstanza]->{date};
$thrpWpeakdate = $stanzaInfoArray[$maxthrpWstanza]->{date};
$thrpRpeaktime = $stanzaInfoArray[$maxthrpRstanza]->{time};
$thrpWpeaktime = $stanzaInfoArray[$maxthrpWstanza]->{time};
#$thrppeaktime = $stanzaInfoArray[$maxthrpstanza]->{time};

print ":\n";
printf (":  Average IOPS:\t\t\t%.2f\n",$averageiops);
printf (":  Peak IOPS:\t\t\t\t%.2f at %s %s\n",$iopspeak, $iopspeakdate, $iopspeaktime);
# We are no longer showing peak throughput.  Our method of extracting peak across multiple disks readings
# from an iostat interval is not reliable
#print ":  Peak Read Throughput (KB/sec):\t$thrpRpeak at $thrpRpeakdate $thrpRpeaktime\n";
#print ":  Peak Write Throughput (KB/sec):\t$thrpWpeak at $thrpWpeakdate $thrpWpeaktime\n";
print ":\n";
print ":  Total elapsed time (seconds):\t$elapsedSeconds\n";
print "===================================================================\n";

sub iscontained($$)
{
  local $d = shift(@_);
  local $dRef = shift(@_);

  local $found = 0;
  local $numds = @{$dRef};
  local $p = 0;

  while (($p < $numds) && ($found == 0))
  {
    if ("$d" eq "$dRef->[$p]")
    {
      $found = 1;
    }
    ++$p;
  }
  return $found;
}

############################################################
#      sub: getPlatform
#     desc: Returns the platform type.  The type returned
#           represent constants specifying the operating system. 
#           The type is determined based on the Perl built-in
#           ^O variable. 
#   params: None
#  returns: $string containing platform type constant
############################################################
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
       elsif ($_ =~ m#ppc64le#)
       {
	 return "LINUXPPCLE";
       }
       elsif ($_ =~ m#ppc64#)
       {
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

  if ($platform eq "WIN32")
  {
    return "\\";
  }
  else
  {
    return "/";
  }
}

sub getCapByKB
{
	$cap = shift(@_);
	
	if($cap =~ m/([\d|\.]+)([KMGT])/){
		$capNew = int($1);
		$unit = $2;
		
		if($unit eq "K"){
			return $capNew;
		}elsif($unit eq "M"){
			return ($capNew * 1024);
		}elsif($unit eq "G"){
			return ($capNew * 1024 * 1024);
		}elsif($unit eq "T"){
			return ($capNew * 1024 * 1024 * 1024);
		}
	}
	return ($cap/1000);
}
