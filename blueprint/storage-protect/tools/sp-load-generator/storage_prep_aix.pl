#------------------------------------------------------------------------------
#  Name: storage_prep_aix.pl                                                   
#                                                                              
#  Desc:  Prepare the LVM components of the IBM Storage Protect blueprint storage on AIX.      
#                                                                              
#  Usage: By default, this script will attempt to determine which disks        
#         to use for different volume groups based on the disk size.           
#         If you have varied from the blueprint specifications, you can        
#         modify the disk lists below before executing this script and          
#         specify the -uselist option when invoking the script                  
#                                                                               
#         perl storage_prep_aix.pl <small|medium|large> [-uselist]              
#                                                                               
# Notice: This program is provided as a tool intended for use by IBM Internal, 
#         IBM Business Partners, and IBM Customers. This program is provided as is, 
#         without support, and without warranty of any kind expressed or implied.
#
# (C) Copyright International Business Machines Corp. 2013, 2022
#------------------------------------------------------------------------------

sub lprint($$);

$versionString = "Program version 5.1b";
$| = 1;     # Force standard out flushing with every print

if (@ARGV < 1 || @ARGV > 2)
{
  print "USAGE: storage_prep_aix.pl <small|medium|large> [-uselist]\n";
  exit (1);
}

if (@ARGV == 1)
{
  $size = shift (@ARGV);
}
else
{
  ($size,$uselist) = @ARGV;
}
if ($size !~ m/(small|medium|large)/)
{
  print "ERROR: incorect size, <$size> specified.\n";
  exit (1);
}
if (defined($uselist) && $uselist !~ m/-uselist/)
{
  print "ERROR: incorect parameter, <$uselist> specified.\n";
  exit (1);
}

if ($uselist =~ m/uselist/)
{
  $uselist = 1;
}
else
{
  $uselist = 0;
}

$platform = getPlatform();

# Set the default number of LUNs per array.  Change this section if you have deviated from the blueprint
if ($size eq "small")
{
  $lunsPerArray = 4;
}
elsif ($size eq "medium")
{
  $lunsPerArray = 12;
}
elsif ($size eq "large")
{
  $lunsPerArray = 32;
}
else
{
  print "ERROR: incorect size, <$size> specified.\n";
  exit (1);
}

# Prepare the log file
$log = initLog();
$logHead = getlogHeader();  # write the log header information
lprint ($log, $logHead);

$fsPrefix = "/tsminst1";
@db_disks = qw ();
@db_sizes = qw ();
@act_disks = qw ();
@act_sizes = qw ();
@arch_disks = qw ();
@arch_sizes = qw ();
@dbbk_disks = qw ();
@dbbk_sizes = qw ();
@stg_disks = qw ();
@stg_sizes = qw ();


lprint $log, "\n*-----------------------------------------------------------------------*\n";
lprint $log, "** Beginning LVM and disk configuration.\n";
lprint $log, "** $versionString\n";

if (! -d $fsPrefix)
{
  lprint $log, "\t==>Creating parent directory $fsPrefix\n";
  `mkdir $fsPrefix`;
  if (! -d $fsPrefix)
  {
    lprint $log, "ERROR: could not create parent directory $fsPrefix.\n";
    exit (1);
  }
}

$cmd = "lsdev -Ccdisk";
lprint $log, "\t==>Running command: $cmd\n";
@lsdev = `$cmd`;

# Edit these disk grouping if you are manually specifying the disks to process
# with the -uselist option
if ($uselist)
{
  lprint $log, "** Defining list of disks (-uselist specified).\n";
  if ($size eq "small")
  {
    @db_disks = qw (hdisk2 hdisk3 hdisk4 hdisk5);
    @act_disks = qw (hdisk6);
    @arch_disks = qw (hdisk7);
    @dbbk_disks = qw (hdisk8 hdisk9 hdisk10 hdisk11);
    @stg_disks = qw (hdisk12 hdisk13 hdisk14 hdisk15 hdisk16 hdisk17 hdisk18
          hdisk19 hdisk20 hdisk21 hdisk22 hdisk23 hdisk24 hdisk25 hdisk26
          hdisk27 hdisk28 hdisk29 hdisk30 hdisk31);
  }
  elsif ($size eq "medium")
  {
    @db_disks = qw (hdisk2 hdisk3 hdisk4 hdisk5);
    @act_disks = qw (hdisk6);
    @arch_disks = qw (hdisk7 hdisk8);
    @dbbk_disks = qw (hdisk9 hdisk10 hdisk11 hdisk12);
    @stg_disks = qw (hdisk13 hdisk14 hdisk15 hdisk16 hdisk17 hdisk18
          hdisk19 hdisk20 hdisk21 hdisk22 hdisk23 hdisk24 hdisk25 hdisk26
          hdisk27 hdisk28 hdisk29 hdisk30 hdisk31 hdisk32);
  }
  elsif ($size eq "large")
  {
    @db_disks = qw (hdisk3 hdisk4 hdisk5 hdisk6 hdisk7 hdisk8 hdisk9 hdisk10 hdisk11 hdisk12 hdisk13 hdisk14);
    @act_disks = qw (hdisk15);
    @arch_disks = qw (hdisk16 hdisk17 hdisk18 hdisk19);
    @dbbk_disks = qw (hdisk20 hdisk21 hdisk22 hdisk23 hdisk24 hdisk25);
    @stg_disks = qw (hdisk26 hdisk27 hdisk28 hdisk29
           hdisk30 hdisk31 hdisk32 hdisk33 hdisk34 hdisk35 hdisk36 hdisk37 hdisk38 hdisk39
           hdisk40 hdisk41 hdisk42 hdisk43 hdisk44 hdisk45 hdisk46 hdisk47 hdisk48 hdisk49
           hdisk50 hdisk51 hdisk52 hdisk53 hdisk54 hdisk55 hdisk56 hdisk57 hdisk58 hdisk59
           hdisk60 hdisk61 hdisk62 hdisk63 hdisk64 hdisk65 hdisk66 hdisk67 hdisk68 hdisk69
           hdisk70 hdisk71 hdisk72 hdisk73 hdisk74 hdisk75 hdisk76 hdisk77 hdisk78 hdisk79
           hdisk80 hdisk81 hdisk82 hdisk83 hdisk84 hdisk85 hdisk86 hdisk87 hdisk88 hdisk89
           hdisk90 hdisk91 hdisk92 hdisk93 hdisk94 hdisk95 hdisk96 hdisk97 hdisk98 hdisk99
           hdisk100);
  }
  else
  {
    lprint $log, "ERROR: could not determine hdisk list.\n";
    exit (1);
  }

  # Record size of each disk
  foreach $disk (@db_disks)
  {
    $diskSize = `bootinfo -s $disk`;
    chomp $diskSize;
    $diskSize = $diskSize / 1024;
    push (@db_sizes, $diskSize);
  }
  foreach $disk (@act_disks)
  {
    $diskSize = `bootinfo -s $disk`;
    chomp $diskSize;
    $diskSize = $diskSize / 1024;
    push (@act_sizes, $diskSize);
  }
  foreach $disk (@arch_disks)
  {
    $diskSize = `bootinfo -s $disk`;
    chomp $diskSize;
    $diskSize = $diskSize / 1024;
    push (@arch_sizes, $diskSize);
  }
  foreach $disk (@dbbk_disks)
  {
    $diskSize = `bootinfo -s $disk`;
    chomp $diskSize;
    $diskSize = $diskSize / 1024;
    push (@dbbk_sizes, $diskSize);
  }
  foreach $disk (@stg_disks)
  {
    $diskSize = `bootinfo -s $disk`;
    chomp $diskSize;
    $diskSize = $diskSize / 1024;
    push (@stg_sizes, $diskSize);
  }
}
else  
{
  lprint $log, "** Determining the list of disks to process\n";
  @internalDisks = qw();
  foreach $dev (@lsdev)
  {
    ($hdisk) = split (/\s+/, $dev);
    if ($dev =~ m/SAS Disk Drive/ || $dev =~ m/SAS RAID/)
    {
      push (@internalDisks, $hdisk);
    }
  }

  # Define expected size ranges for different disk types based on system size
  if ($size eq "small")
  {
    $dbLow = 301;
    $dbHigh = 500;
    $actLow = 100;
    $actHigh = 190;
    $archLow = 1025;
    $archHigh = 1499;
    $dbbkLow = 1500;
    $dbbkHigh = 3500;
    $stgLow = 3501;
    $stgHigh = 16000;
  }
  if ($size eq "medium")
  {
    $dbLow = 200;
    $dbHigh = 899;
    $actLow = 100;
    $actHigh = 199;
    $archLow = 900;
    $archHigh = 2499;
    $dbbkLow = 2500;
    $dbbkHigh = 15499;
    $stgLow = 15500;
    $stgHigh = 50000;
  }
  if ($size eq "large")
  {
    $dbLow = 600;
    $dbHigh = 999;
    $actLow = 250;
    $actHigh = 599;
    $archLow = 2000;
    $archHigh = 4999;
    $dbbkLow = 5000;
    $dbbkHigh = 18999;
    $stgLow = 19000;
    $stgHigh = 60000;
  }

  # Get a list of physical disks, and group them by size
  $cmd = "lspv";
  lprint $log, "\t==>Running command: $cmd\n";
  @lspv = `$cmd`;
  foreach $dev (@lspv)
  {
    chomp ($dev);
    ($hdisk,$pvid,$vgname,$state) = split (/\s+/, $dev);

    # Always skip hdisk0
    next if ($hdisk eq "hdisk0");

    $cmd = "bootinfo -s $hdisk";
    $diskSize = `$cmd`;
    chomp ($diskSize);

    # Skip over disks expected to be internal
    next if (grep {m/\Q$hdisk\E$/} @internalDisks);

    # Skip over disks belong to another volume group
    next if ($vgname ne "None");

    # Get the disk size in GB
    $diskSize = int($diskSize / 1024);

    # Add to group based on size
    if ($diskSize >= $actLow && $diskSize < $actHigh)
    {
      push (@act_disks, $hdisk);
      push (@act_sizes, $diskSize);
    }
    elsif ($diskSize >= $dbLow && $diskSize < $dbHigh)
    {
      push (@db_disks, $hdisk);
      push (@db_sizes, $diskSize);
    }
    elsif ($diskSize >= $stgLow && $diskSize < $stgHigh)
    {
      push (@stg_disks, $hdisk);
      push (@stg_sizes, $diskSize);
    }
    elsif ($size eq "small" && $diskSize >= $archLow && $diskSize < $archHigh && $#arch_disks == -1)
    {
      push (@arch_disks, $hdisk);
      push (@arch_sizes, $diskSize);
    }
    elsif ($size ne "small" && $diskSize >= $archLow && $diskSize < $archHigh)
    {
      push (@arch_disks, $hdisk);
      push (@arch_sizes, $diskSize);
    }
    elsif ($diskSize >= $dbbkLow && $diskSize < $dbbkHigh)
    {
      push (@dbbk_disks, $hdisk);
      push (@dbbk_sizes, $diskSize);
    }
    else
    {
      lprint $log, "WARNING: Found disk: $hdisk, with unexpected size: $diskSize\n";
    }
  }

}  # End of automatic disk identification

# Reorder the disks within the storage pool group to alternate I/O between arrays
@tmpList = qw();

$numberArrays = ($#stg_disks + 1) / $lunsPerArray;
for ($i=0; $i < $lunsPerArray; $i++)
{
  for ($j=0; $j < $numberArrays; $j++)
  {
    push (@tmpList, $stg_disks[$i + ($j * $lunsPerArray)]);
  }
}
@stg_disks = @tmpList;


@all_disks = (@db_disks, @act_disks, @arch_disks, @dbbk_disks, @stg_disks);
$diskCount= $#all_disks + 1;
lprint $log, "\t==>Number of disks identified: $diskCount\n";
if ($diskCount < 5)
{
  lprint $log, "ERROR: Fewer than five disks were identified\n";
  exit (1);
}
if ($#db_disks < 0 || $#act_disks < 0 || $#arch_disks < 0 || $#dbbk_disks < 0 || $#stg_disks < 0)
{
  lprint $log, "ERROR: No disks found for one or more categories\n";
  exit (1);
}

# Print out the disks to be processed by group
lprint $log, "** Disks to be processed:\n";
lprint $log, "\t==>Database disks and sizes (GB)\n\t";
$count = 1;
for ($i=0; $i<= $#db_disks; $i++)
{
  lprint $log, "$count. $db_disks[$i] ($db_sizes[$i]) ";
  if (! (($i + 1) % 4))
  {
    lprint $log, "\n\t";
  }
  $count++;
}
lprint $log, "\n\t==>Active log disks and sizes (GB)\n\t";
for ($i=0; $i<= $#act_disks; $i++)
{
  lprint $log, "$count. $act_disks[$i] ($act_sizes[$i]) ";
  if (! (($i + 1) % 4))
  {
    lprint $log, "\n\t";
  }
  $count++;
}
lprint $log, "\n\t==>Archive log disks and sizes (GB)\n\t";
for ($i=0; $i<= $#arch_disks; $i++)
{
  lprint $log, "$count. $arch_disks[$i] ($arch_sizes[$i]) ";
  if (! (($i + 1) % 4))
  {
    lprint $log, "\n\t";
  }
  $count++;
}
lprint $log, "\n\t==>Database backup disks and sizes (GB)\n\t";
for ($i=0; $i<= $#dbbk_disks; $i++)
{
  lprint $log, "$count. $dbbk_disks[$i] ($dbbk_sizes[$i]) ";
  if (! (($i + 1) % 4))
  {
    lprint $log, "\n\t";
  }
  $count++;
}
lprint $log, "\n\t==>Storage pool disks and sizes (GB)\n\t";
for ($i=0; $i<= $#stg_disks; $i++)
{
  lprint $log, "$count. $stg_disks[$i] ($stg_sizes[$i]) ";
  if (! (($i + 1) % 4))
  {
    lprint $log, "\n\t";
  }
  $count++;
}

# Validate that available devices exist for each disk
lprint $log, "\n\n";
lprint $log, "** Validating that available devices exist for each disk.\n";

foreach $disk (@all_disks)
{
  if (!grep {m/\Q$disk\E\s+Available/} @lsdev)
  {
    lprint $log, "ERROR: No available device found for disk: $disk\n";
    exit (1);
  }
}
lprint $log, "\tAvailable device check complete\t\t\t[OK]\n";

# Validate that the disks in each grouping have the same size
# except for large which can have two different sizes for DB and STGPOOL
lprint $log, "\n";
lprint $log, "** Validating that disks within each grouping have the same size.\n";
@groupNames = qw (db_disks act_disks arch_disks dbbk_disks stg_disks);
$sizeMismatch = 0;
foreach $group (\@db_disks, \@act_disks, \@arch_disks, \@dbbk_disks, \@stg_disks)
{
  $curName = shift(@groupNames);
  lprint $log, "\t==>Processing group ".$curName."\n";
  $refSize = 0;
  $refSize2 = 0;
  $groupWarn = 0;
  foreach $disk (@{$group})
  {
    $curSize = `bootinfo -s $disk`;
    chomp ($curSize);
    if ($refSize == 0)
    {
      $refSize = $curSize;
    }
    elsif ($size ne "small" && ($curName eq "dbbk_disks" || $curName eq "stg_disks") 
           && $curSize != $refSize && $refSize2 == 0)
    {
      $refSize2 = $curSize;
    }
    elsif ($curSize != $refSize && $curSize != $refSize2)
    {
      lprint $log, "\t==>WARNING: Disk $disk has size: $curSize which differs from $refSize\n";
      $sizeMismatch = 1;
      $groupWarn = 1;
    }
  }
  if ($groupWarn == 0)
  {
    if ($refSize2 == 0)
    {
      lprint $log, "\t==>All disks in this group have the same size: $refSize\n";
    }
    else
    {
      lprint $log, "\t==>All disks in this group have the same size: $refSize or $refSize2\n";
    }
  }
}
if ($sizeMismatch == 0)
{
  lprint $log, "\tDisk sizes within groups validated successfully\t\t[OK]\n";
}
else
{
  lprint $log, "\n!! WARNING: Disks within one or more groups have mismatched sizes.\n";
  lprint $log, "  This usually indicates disk LUNs were mapped in the incorrect sequence.\n";
  lprint $log, "  It is recommended that you quit and correct this before continuing.\n";
  lprint $log, "  To continue, enter 'YES' in uppercase, or 'quit'\n";
  $userinput="NO";
  while (($userinput ne "YES") && ($userinput !~ m/quit/i))
  {
    $userinput = "";
    lprint $log, "  Continue? : ";
    $userinput = <STDIN>;
    chomp($userinput);
  }
  if ($userinput eq "quit")
  {
    lprint $log, "Quitting ...\n";
    exit (1);
  }
}


# Validate that disks are not already used in an existing volume group
lprint $log, "\n";
lprint $log, "** Validating that disks are not already used in an existing volume group.\n";
$cmd = "lsvg";
lprint $log, "\t==>Running command: $cmd\n";
@vgs = `$cmd`;
foreach $vg (@vgs)
{
  chomp ($vg);
  $cmd = "lsvg -p $vg";
  lprint $log, "\t==>Running command: $cmd\n";
  @pvs = `$cmd`;
  foreach $pv (@pvs)
  {
    next if ($pv !~ /hdisk\d+/);
    $pv =~ s/(hdisk\d+)\s+.*/$1/;
    chomp ($pv);
    if (grep {m/\Q$pv\E$/} @all_disks)
    {
      lprint $log, "ERROR: Disk $pv already used in volume group $vg\n";
      exit (1);
    }
  }
}
lprint $log, "\tDisk check in existing volume groups complete\t[OK]\n";

lprint $log, "\n!! WARNING: proceeding will initialize all of the disks listed above.\n";
lprint $log, "  To continue, enter 'YES' in uppercase, or 'quit'\n";
$userinput="NO";
while (($userinput ne "YES") && ($userinput !~ m/quit/i))
{
  $userinput = "";
  lprint $log, "  Continue? : ";
  $userinput = <STDIN>;
  chomp($userinput);
}
if ($userinput eq "quit")
{
  lprint $log, "Quitting ...\n";
  exit (1);
}


# Update queue depth, max transfer size, reserve_policy, and round_robin for all disks
lprint $log, "\n";
lprint $log, "** Updating queue_depth to 32, max_transfer to 0x100000, reserve_policy to no_reserve,\n";
lprint $log, "   and algorithm to round_robin for each disk.\n";

foreach $disk (@all_disks)
{
  `chdev -l $disk -a max_transfer=0x100000`;
  `chdev -l $disk -a queue_depth=32`;
  `chdev -l $disk -a reserve_policy=no_reserve`;
  `chdev -l $disk -a algorithm=round_robin`;
}
lprint $log, "\tQueue depth, max transfer, reserve_policy, and algorithm updates complete\t\t\t[OK]\n";


# Create volume groups
lprint $log, "\n";
lprint $log, "** Creating volume groups.\n";

@groupNames = qw (db_disks act_disks arch_disks dbbk_disks stg_disks);
@groupLists = (\@db_disks, \@act_disks, \@arch_disks, \@dbbk_disks, \@stg_disks);
%vgNames = ('db_disks','tsmdb','act_disks','tsmactlog','arch_disks','tsmarchlog','dbbk_disks','tsmdbback',
            'stg_disks', 'tsmstgpool');

foreach $group (@groupLists)
{
  $curName = shift(@groupNames);
  lprint $log, "\t==>Processing group ".$curName."\n";

  $cmd = "mkvg -S -y $vgNames{$curName} ".join(' ',@{$group});
  lprint $log, "\t==>Running command: $cmd\n";
  `$cmd`;
  @vgs = `lsvg`;
  if (!grep {m/\Q$vgNames{$curName}\E/} @vgs)
  {
    lprint $log, "ERROR: Unable to create volume group $vgNames{$curName}\n";
    exit (1);
  }
  lprint $log, "\tVolume group $vgNames{$curName} created\t\t\t[OK]\n";
}


# Create logical volumes and file systems
%lvNames = ('tsmdb','tsmdb','tsmactlog','tsmact','tsmarchlog','tsmarch','tsmdbback','tsmdbbk',
            'tsmstgpool', 'tsmstg');
%fsNames = ('tsmdb','TSMdbspace','tsmactlog','TSMalog','tsmarchlog','TSMarchlog','tsmdbback','TSMbkup',
            'tsmstgpool', 'TSMfile');

@vgs = qw (tsmdb tsmactlog tsmarchlog tsmdbback tsmstgpool);
foreach $vg (@vgs)
{
  lprint $log, "\n";
  lprint $log, "** Creating logical volumes and file systems for the volume group $vg.\n";
  @pvs = `lsvg -p $vg`;

  # The archlog for medium and large needs to stripe several pdisks into one lv
  if (($vg eq "tsmarchlog") && ($size ne "small"))
  {
    $allPdisks = "";
    $sumPP = 0;
    foreach $pv (@pvs)  # build up list of pdisks and cumulative size
    {
      next if ($pv !~ m/hdisk/);
      ($dev,$state,$totalPP,$freePP,$distrib) = split (/\s+/, $pv);
      $allPdisks = $allPdisks." ".$dev;
      $sumPP = $sumPP + $freePP;
    }

    # Create the Logical volume
    $lvName = "tsmarch00";
    $cmd = "mklv -y $lvName -t jfs2 -x $sumPP $vg $sumPP $allPdisks";
    lprint $log, "\t==>Running command: $cmd\n";
    `$cmd`;    
    @lvs = `lsvg -l $vg`;
    if (!grep {m/\Q$lvName\E/} @lvs)
    {
      lprint $log, "ERROR: Unable to create logical volume $lvName\n";
      exit (1);
    }
    lprint $log, "\tLogical volume $lvName created\t\t\t[OK]\n";

    # Create the file system using the rbrw flag and INLINE log
    $fsName = $fsPrefix."/".$fsNames{$vg};
    $cmd = "crfs -v jfs2 -d $lvName -p rw -a logname=INLINE -a options=rbrw,noatime -a agblksize=4096 -m $fsName -A yes";

    lprint $log, "\t==>Running command: $cmd\n";
    `$cmd`;    

    # Mount the newly created file system
    `mount $fsName`;

    # Validate the file system was created successfully
    @fss = `mount`;
    if (!grep {m/\Q$fsName\E/} @fss)
    {
      lprint $log, "ERROR: Unable to create or mount file system $fsName\n";
      exit (1);
    }
    lprint $log, "\tFile system $fsName created\t[OK]\n";
  }
  else   # For all others, one pdisk per LV
  {
    $count = 0;
    foreach $pv (@pvs)
    {
      next if ($pv !~ m/hdisk/);
      ($dev,$state,$totalPP,$freePP,$distrib) = split (/\s+/, $pv);
      # Note: no longer subtracting one after change to INLINE jfs2 log
      # $freePP = $freePP - 1;
      $prefix = "";
      if ($count < 10)
      {
        $prefix = "0";
      }

      $lvName = $lvNames{$vg}.$prefix.$count;
      if ($vg eq "tsmactlog" || $vg eq "tsmarchlog")
      {
        $fsName = $fsPrefix."/".$fsNames{$vg};
      }
      else
      {
        $fsName = $fsPrefix."/".$fsNames{$vg}.$prefix."$count";
      }

      # Create the Logical volume
      $cmd = "mklv -y $lvName -t jfs2 -u 1 -x $freePP $vg $freePP $dev";
      lprint $log, "\t==>Running command: $cmd\n";
      `$cmd`;    
      @lvs = `lsvg -l $vg`;
      if (!grep {m/\Q$lvName\E/} @lvs)
      {
        lprint $log, "ERROR: Unable to create logical volume $lvName\n";
        exit (1);
      }
      lprint $log, "\tLogical volume $lvName created\t\t\t[OK]\n";

      # Create the file system using the rbrw flag and INLINE log
      $cmd = "crfs -v jfs2 -d $lvName -p rw -a logname=INLINE -a options=rbrw,noatime -a agblksize=4096 -m $fsName -A yes";

      lprint $log, "\t==>Running command: $cmd\n";
      `$cmd`;    

      # Mount the newly created file system
      `mount $fsName`;

      # Validate the file system was created successfully
      @fss = `mount`;
      if (!grep {m/\Q$fsName\E/} @fss)
      {
        lprint $log, "ERROR: Unable to create or mount file system $fsName\n";
        exit (1);
      }
      lprint $log, "\tFile system $fsName created\t[OK]\n";

      $count++;
    }
  }
}


lprint $log, "** All storage preparations have completed successfully.\n";
lprint $log, "\n*-----------------------------------------------------------------------*\n";


############################################################
#      sub: getPlatform
#     desc: Returns the platform type.  The type returned
#           represent constants which are used throughout the test
#           automation.  The type is determined based on the Perl built-in
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
       
       if($_ =~ m#ppc64#){
       	return "LINUXPPC";
       }
     }	
  }
  # We haven't found a match yet, so return UNKNOWN
  return "UNKNOWN";
}


############################################################
#      sub: initLog
#     desc: Initialize the script log, by adding the date stamp
#           and if log(s) with the same date already exist
#           append the first unused index to the end of the
#           name starting from 1 (e.g., the log will be 
#           setupLog_130515_2.log if setupLog_130515_1.log already
#           exists, but setupLog_130515_2.log does not already 
#           exist)
#
#   params: none
#  returns: the name of the script log
#
############################################################

sub initLog
{
  @currenttime = localtime();
  $day = $currenttime[4] + 1;               # Adjust month 0..11 range to 1..12 range
  $day = "0".$day if($day < 10);     # Adjust month 0 as 00
  $currenttime[5] = $currenttime[5] - 100 if($currenttime[5] > 99);   # Adjust year 2000 as 00
  $currenttime[5] = "0".$currenttime[5] if($currenttime[5] < 10);     # Adjust year 0 as 00
  $currenttime[3] = "0".$currenttime[3] if($currenttime[3] < 10);     # Adjust day 0 as 00
  $date = $currenttime[5].$day.$currenttime[3];

  $serversetupLogBase = "storagePrep";
  $setuplogname_base = $serversetupLogBase . "_" . ${date};
  $setuplogname = $setuplogname_base . ".log";
  
  $cnt = 1;

  while ( -f $setuplogname )
  {
    $setuplogname = $setuplogname_base . "_" . $cnt . ".log"; 
    $cnt++;
  }

  open(LOGH, ">$setuplogname") or die "Unable to open $setuplogname\n";
  close LOGH;

  return $setuplogname;
}


############################################################
#      sub: getlogHeader
#     desc: constructs the log header string
#                    
#   params: none
#
#  returns: the log header string
#
############################################################

sub getlogHeader 
{
  @cur = localtime();
  $day = $cur[4] + 1;    # Adjust month 0..11 range to 1..12 range
  $day = "0" . $day if ( $day < 10 );    # Adjust month 0 as 00
  $cur[5] = $cur[5] - 100 if ( $cur[5] > 99 );    # Adjust year 2000 as 00
  $cur[5] = "0" . $cur[5] if ( $cur[5] < 10 );    # Adjust year 0 as 00
  $cur[3] = "0" . $cur[3] if ( $cur[3] < 10 );    # Adjust day 0 as 00

  $line =
"********************************************************************************\n";
  my $longtestcase = "**  IBM Storage Protect storage preparation script ($platform) log\n";
  my $date         =
  sprintf( "**  Date:  %2.2d/%2.2d/%2.2d", $cur[5], $day, $cur[3] );
  my $time     = sprintf( " %2.2d:%2.2d:%2.2d\n", $cur[2], $cur[1], $cur[0] );

  $banner = $line
    . $longtestcase
    . $date
    . $time
    . $line;
  return $banner;
}


############################################################
#      sub: lprint
#     desc: Prints a string to both a log file and to the screen
#   params: $logfile: Filename to log the string
#           $string: String to be logged
#  returns: $rc: 0 for success, 1 for failure
############################################################
sub lprint ($$)
{
  if (@_ != 2)
  {
    print "USAGE: lprint logfile string\n";
    return 1;
  }
  $file = shift(@_);
  $string = shift(@_);

  # It's possible that the log is not inited
  if ($file ne "")
  {
     # Attempt to open the log file for appending
     if (! open (LOG, ">>$file"))
     {
       print "lprint: could not write to log file: $file!\n";
       print "$string";
       return 1;
     }
  }
  # Append the string to the log
  print LOG "$string";

  # Close the log file
  close LOG;

  # Now print to STDOUT
  print "$string";

  return 0;
}