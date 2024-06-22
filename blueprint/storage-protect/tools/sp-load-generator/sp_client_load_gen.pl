#!/usr/bin/perl
#********************************************************************************
# IBM Storage Protect
# 
# name: sp_client_load_gen
#
# desc:  The sp_client_load_gen (or sesstest) utility is used to test scalability of
#        IBM Storage Protect server sessions, with the ability to control the deduplication and
#        compression result when testing against a container storage pool.
#        There are two modes that this script can operate in:
#          a) iterative where sessions counts from 1 to n are looped thorugh
#             (when -sessmin is omitted)
#          b) single mode were a specific session count is tested
#             (when -sessmin is used)
#
#        Usage note: in order to test restore, you must first run through a
#        backup cycle with the same or greater number of sessions you will be
#        testing restore with. To avoid all reads from cache, perform the backup
#        prior to restore using -dedup=1.
#
#        "USAGE: perl sp_client_load_gen <-sesspeak=v> [-sessmin=x] [-objsize=yk|m|g] [-objcount=z] [-rest]\n";
#        "                 [-dedup=1-100] [-node=nodeprefix] [-nodepw=abc12345] [-onenode]\n";
#        "                 [-fscount=1-10]\n";
#        "  Defaults:  sessmin=1 fscount=1 objsize=128m  objcount=50 dedup=50 node=nodetest nodepw=passw0rd\n";
#
# Notice: This program is provided as a tool intended for use by IBM Internal, 
#         IBM Business Partners, and IBM Customers. This program is provided as is, 
#         without support, and without warranty of any kind expressed or implied.
#
# (C) Copyright International Business Machines Corp. 2013, 2021
#********************************************************************************

if (@ARGV < 1 || @ARGV > 7)
{
  print "USAGE: perl sp_client_load_gen <-sesspeak=v> [-sessmin=x] [-objsize=yk|m|g] [-objcount=z] [-rest]\n";
  print "                 [-dedup=1-100] [-node=nodeprefix] [-nodepw=abc12345] [-onenode]\n";
  print "                 [-fscount=1-10]\n";
  print "  Defaults:  sessmin=1 fscount=1 objsize=128m  objcount=50 dedup=50 node=nodetest nodepw=passw0rd\n";
  exit;
}

$version = "Version 1.5b";
$nodePrefix = "sp_client_load_gen";
$sessPeak = 0;
$sessMin = 0;
$fsCount = 1;
$objSize = "128m";
$objCount = "50";
$dedupPct = "50";
$nodePw = "passw0rd";
$timeoutMinutes = 360;

use Sys::Hostname;
$hostname = hostname;


while ($nextArg = shift(@ARGV))
{
  if ($nextArg =~ m/-sesspeak=(\d+)/i)
  {
    $sessPeak = $1;
  }
  elsif ($nextArg =~ m/-sessmin=(\d+)/i)
  {
    $sessMin = $1;
  }
  elsif ($nextArg =~ m/-objsize=(\d+)(k|m|g)/i)
  {
    $objSize = $1.$2;
  }
  elsif ($nextArg =~ m/-objcount=(\d+)/i)
  {
    $objCount = $1;
  }
  elsif ($nextArg =~ m/-dedup=(\d+)/i)
  {
    $dedupPct = $1;
  }
  elsif ($nextArg =~ m/-node=(\S+)/i)
  {
    $nodePrefix = $1;
  }
  elsif ($nextArg =~ m/-nodepw=(\S+)/i)
  {
    $nodePw = $1;
  }
  elsif ($nextArg =~ m/-log=(\S+)/i)
  {
    $logFile = $1;
  }
  elsif ($nextArg =~ m/-rest/i)
  {
    $rest = 1;
  }
  elsif ($nextArg =~ m/-onenode/i)
  {
    $onenode = 1;
  }
  elsif ($nextArg =~ m/-fscount=(\d+)/i)
  {
    $fsCount = $1;
    if ($fsCount < 1 || $fsCount > 10)
    {
      print "ERROR: The -fscount parameter must be in the range 1-10\n";
      exit 1;
    }
    if ( ($fsCount > 1) && ($onenode == 1) )
    {
      print "ERROR: The -fscount parameter and -onenode cannot be used together\n";
      exit 1;
    }
  }
  else
  {
    print "ERROR: unreconized parameter: $nextArg\n";
    exit 1;
  }
}

if ($sessPeak == 0)
{
  print "ERROR: sesspeak is a required paramter\n";
  exit 1;
}

# Smaller object sizes need to use a smaller API buffer size to be able to control dedup %
if ($objSize =~ m/^\dk/ || $objSize =~ m/^\d\dk/ || $objSize =~ m/^[1-2]\d\dk/)   # Up to 299k
{
  $objSize =~ m/^(\d+)k/;
  $val = int($1 / 2);
  $blockSize = "-b ".$val."k";
}
elsif ($objSize =~ m/^\d\d\dk/ || $objSize =~ m/^1\d\d\dk/ || $objSize =~ m/^1m/)     # 300k - 1m
{
  $blockSize = "-b 200k";
}
elsif ($objSize =~ m/^\d\d\d\dk/ || $objSize =~ m/^\dm/)   # 2m through 9m
{
  $blockSize = "-b 512k";
}
else
{
  $blockSize = "-b 1m";
}

$platform = getPlatform();
if ($platform =~ m/LINUX86/)
{
  $prog = "./bin/linux/fakeload_lnx";
}
elsif ($platform eq "LINUXPPC")
{
  $prog = "./bin/ppc-linux/fakeload_plnx";
}
elsif ($platform eq "LINUXPPCLE")
{
  $prog = "./bin/ppc-linux/fakeload_plelnx";
}
elsif ($platform =~ m/AIX/)
{
  $prog = "./bin/aix/fakeload_aix";
}
elsif ($platform =~ m/WIN/)
{
  $prog = "./bin/windows/fakeload_win.exe";
}
else
{
  print "ERROR: platform $platform is not supported\n";
  exit 1;
}

if (! -e $prog)
{
  print "ERROR: Cannot locate the required file $prog\n";
  exit;
}

print "===================================================================\n";
print ": IBM Storage Protect fakeload session test $version\n";
print ":\n";
print ": Object size:\t\t$objSize\n";
print ": Object count:\t\t$objCount\n";
print ": Dedup pct:\t\t$dedupPct\n";
if ($onenode)
{
  print ": Sessions, min=$sessMin  peak=$sessPeak, all sessions share one node\n";
}
else
{
  print ": Sessions, min=$sessMin  peak=$sessPeak, one node per session\n";
}

if ($rest)
{
  print ": Testing restore\n";
}
else
{
  print ": Testing backup\n";
}
print "===================================================================\n";

if ( -e $logFile) {
  #file exists
  open(CSV, "+>${logFile}") or die "Unable to open ${logFile}.csv\n";
} else {
  # Create a .csv log file
  open(CSV, ">sp_client_load_gen_${sessPeak}_${objSize}.csv") or die "Unable to open sp_client_load_gen_${numSess}_${objSize}.csv\n";
}

# Launch iostat to monitor CPU usage
# Cleanup any existing iostat output file
unlink ("iostatout.".$hostname."txt");

if ($sessMin == 0)     # The case of iterating across different session counts
{
  $start = 1;
  $endi = $sessPeak;
  $endj = 0;
  $endk = 1;
}
elsif ($fsCount == 1)  # The case of a fixed session count, including -onenode
{
  $start = $sessMin;
  $endi = $sessMin;
  $endj = $sessPeak - 1;
  $endk = 1;
}
elsif ($fsCount > 1)  # The case of a fixed node count and multiple file space per node
{
  $start = $sessMin;
  $endi = $sessMin;
  $endj = $sessPeak - 1;
  $endk = $fsCount;
}

for ($i = $start; $i <= $endi; $i++)
{
  if ($sessMin == 0)
  {
    print ": Running tests with session count of $i ...\n";
  }
  elsif ($fsCount == 1)
  {
    print ": Running tests with $sessPeak sessions ...\n";
  }
  elsif ($fsCount > 1)
  {
    $totSess = $sessPeak * $fsCount;
    print ": Running tests with $sessPeak nodes each with $fsCount sessions for $totSess sessions in total ...\n";
  }

  # Make the test data unique again for this pass for those files which will be used
  if (! $rest)
  {
    `perl uniquify_data_files.pl $sessPeak`;
  }

  # Launch a separate process for running iostat to collect performance data
  if ($runiostat = fork())
  {
  }
  else
  {
    # We wait for overlapped read and write activity to avoid contaminating the
    # iostat averages taken for read
    if ($platform eq "WIN32")
    {
      open (COUNTERS, ">wincounters.txt") or die "ERROR opening file: wincounters.txt\n";
      print COUNTERS "\\Processor Information(_Total)\\% User Time\n";
      close (COUNTERS);
      exec("typeperf -cf wincounters.txt -f csv -o iostatout.".$hostname."txt -si 7 -y > NUL");
      $perfProg = "typeperf";
    }
    elsif ($platform eq "AIX"){
    	exec("iostat -Tl 7 > iostatout.".$hostname."txt");
    	$perfProg = "iostat";
    }
    else
    {
      exec("iostat -xtk 7 > iostatout.".$hostname."txt");
      $perfProg = "iostat";
    }
  }

  # Flush Linux fs caches prior to a restore test
  if ($rest && $platform =~ m/LINUX/)
  {
    `echo 3 > /proc/sys/vm/drop_caches`;
  }

  my $expectedSess = 0;
  if ($fsCount > 1)
  {
    $expectedSess = ($i + $endj - $start + 1) * $fsCount;  
  }
  else
  {
    $expectedSess = $i + $endj - $start + 1;
  }

  # Launch enough fakeload sessions to reach the current target
  $benchNum=1;
  for ($j = $start; $j <= ($i + $endj); $j++)
  {
    # Either use one node per session, or all in one session
    if ($onenode)
    {
      $curFS = 1;
      if ($sessMin > 1)
      {
        $curNode = ${nodePrefix}.$sessMin;
        $curFS = $j - $sessMin +1;
      }
      else
      {
        $curNode = ${nodePrefix}."1";
      }
      $fsName = "-s /${objSize}_FS${curFS}";
    }
    else
    {
      $curNode = ${nodePrefix}.${j};
      $fsName = "";
    }

    $startTime = time();    
    for ($k = 1; $k <= $endk; $k++)
    {
      $outName = "fake".$hostname.${j}.".out";
      if ($fsCount > 1)
      {   
        $fsName = "-s /${objSize}_FS${k}";
        $outName = "fake".$hostname.${j}."_".${k}.".out";
      }
      if ($platform eq "WIN32")
      {
        if ($rest)
        {
          $cmd = "start /b ${prog} res $objSize $objCount ${curNode} ${fsName} -p $nodePw > ${outName}";
        }
        else
        {
          $cmd = "start /b ${prog} sel $objSize $objCount ${curNode} ${fsName} -p $nodePw -f benchdata\\bench${benchNum} -pd $dedupPct $blockSize -E > ${outName}";
        }
      }
      else
      {
        if ($rest)
        {
          $cmd = "${prog} res $objSize $objCount ${curNode} ${fsName} -p $nodePw > ${outName} &";
        }
        else
        {
          $cmd = "${prog} sel $objSize $objCount ${curNode} ${fsName} -p $nodePw -f benchdata/bench${benchNum} -pd $dedupPct $blockSize -E > ${outName} &";
        }
      }
      system( "$cmd" );
      $benchNum++;
    } # end k loop
  }

  # Wait for fakeload processes to finish
  $timeOut = 0;
  while ($timeOut < ($timeoutMinutes*60/5))
  {
    sleep(1);
    if ($platform eq "WIN32")
    {
      @psOut = `tasklist | findstr $prog`;
    }
    else
    {
      @psOut = `ps -ef | grep $prog`;
    }
    if ( ( $platform ne "WIN32" and ! grep {m/$prog (sel|res)/} @psOut ) or
	     ( $platform eq "WIN32" and ! grep {m/$prog/} @psOut ) )
    {
      last;
    }
    $timeOut++;
  }
  if ($timeOut > ($timeoutMinutes*60/5))
  {
    die "ERROR: Excessive time taken for backup to complete\n";
  }
  $endTime = time();

  # Stop the iostat process
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

    print ": All sessions are finished.  Stopping typeperf process with id $iostatprocid\n";
    system("taskkill /pid $iostatprocid /f");
    unlink "wincounters.txt";
  }
  elsif ( $platform eq "AIX" ){
    $qproccmd = "ps -ef | grep iostat";

    @qproccmdOut = `$qproccmd`;

    foreach $qprocOutln (@qproccmdOut)
    {
      if ($qprocOutln =~ m/root\s+(\d+)\s+\d+\s+\d+\s+\S+\s+\S+\s+\S+\s+iostat -Tl/)
      {
        $iostatprocid = $1;
      }
    }

    print ": All sessions are finished.  Stopping iostat process with id $iostatprocid\n";
    system("kill -2 $iostatprocid");
  }
  else
  {
    $qproccmd = "ps -ef | grep iostat";
    $signal = "-2";

    @qproccmdOut = `$qproccmd`;

    foreach $qprocOutln (@qproccmdOut)
    {
      if ($qprocOutln =~ m/root\s+(\d+)\s+\d\d+\s+\d+\s+\S+\s+\S+\s+\S+\s+iostat\s+-xtk/)
      {
        $iostatprocid = $1;
      }
    }
    print ": All sessions are finished.  Stopping iostat process with id $iostatprocid\n";
    system("kill $signal $iostatprocid");
  }

  # Make some throughput calculations
  $countSuccess = 0;
  $slowTput = 999999999999;
  $fastTput = 0;
  $avgTput = 0;
  for ($j = $start; $j <= ($i + $endj); $j++)
  {
    for ($k = 1; $k <= $fsCount; $k++)
    {
      $inFile = "fake".$hostname.${j}.".out";
      if ($fsCount > 1)
      {
        $inFile = "fake".$hostname.${j}."_".${k}.".out";
      }
    
      open(FAKEOUT, "<${inFile}") or die "Unable to open ${inFile}\n";
      @fakeOut = <FAKEOUT>;
      close FAKEOUT;

      foreach $ln (@fakeOut)
      {
        if ($ln =~ m/Successful\.\s+Throughput\s+is\s+(\S+)\s+KB/)
        {
          $avgTput = $avgTput + $1;
          if ($1 < $slowTput)
          {
            $slowTput = $1;
          }
          if ($1 > $fastTput)
          {
            $fastTput = $1;
          }
          $countSuccess++;
          unlink ($inFile);
        }
      }
    }

  }
  if ($countSuccess > 0)
  {
    if ($countSuccess < $expectedSess)
    {
      print "WARNING: Fewer sessions completed successfully than expected.  See fake#.out and dsierror.log for possible reasons\n"; 
    }
    $totalTput = $avgTput / 1024;
    $avgTput = $avgTput / $countSuccess;
  }
  else
  {
    print "ERROR: No sessions completed successfully.  See fake#.out files and dsierror.log for possible reasons\n\n";
    exit 1;
  }

  open(IOSTATH, "<iostatout.".$hostname."txt") or die "Unable to open iostatout.".$hostname."txt\n";
  @iostatcontents = <IOSTATH>;
  close IOSTATH;
  unlink "iostatout.".$hostname."txt";

  $maxCPU = 0;
  $nextCPU = 0;
  foreach $ln (@iostatcontents)
  {
    if ($platform ne "WIN32")
    {
      if ($nextCPU == 1 && ($ln =~ m/\s+(\S+)\s+\S+\s+(\S+)\s+\S+\s+\S+\s+\S+/))
      {
        if (($platform eq "LINUX86" || $platform =~ m/LINUXPPC/) && $maxCPU < $1)
        {
          $maxCPU = $1;
        }
        elsif ($platform eq "AIX" && $maxCPU < $2)
        {
          $maxCPU = $2;
        }

        $nextCPU = 0;
      }
      if ($ln =~ m/avg\-cpu/)
      {
        $nextCPU = 1;
      }
    }
    else
    {
      if ($ln =~ m/\".*\d\d\d\d.*\"\,\"(\S+)\"/)
      {
        if ($maxCPU < $1)
        {
          $maxCPU = $1;
        }
      }
    }
  }

  $elapsedTime = $endTime - $startTime;
  print ": \n";
  printf (": Slowest session:\t%8.1f  KB/sec\n: Fastest session:\t%8.1f  KB/sec\n: Average throughput:\t%8.1f  KB/sec\n: Total throughput:\t%8.1f  MB/sec\n: Maximum CPU:\t\t%8.1f%% user\n: Total time:\t\t%8d  seconds\n\n",$slowTput, $fastTput, $avgTput, $totalTput, $maxCPU, $elapsedTime);
  if ($sessMin == 0)
  {
    print CSV "${i},${slowTput},${fastTput},${avgTput},${totalTput},${maxCPU}\n";
  }
  else
  {
    print CSV "${sessPeak},${slowTput},,${fastTput},${avgTput},${totalTput},${maxCPU}\n";
  }

}


close CSV;

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
       elsif  ($_ =~ m#ppc64le#)   
       {
	 return "LINUXPPCLE";
       }
       elsif  ($_ =~ m#ppc64#)   
       {
	 return "LINUXPPC";
       }
     }	
  }
  # We haven't found a match yet, so return UNKNOWN
  return "UNKNOWN";
}

