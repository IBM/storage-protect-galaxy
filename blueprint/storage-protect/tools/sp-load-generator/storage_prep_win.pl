#-----------------------------------------------------------------------------
#  Name: storage_prep_win.pl                                              
#                                                                         
#  Desc:  Prepare the LVM components of the IBM Storage Protect blueprint storage on      
#         Microsoft Windows 2016 or 2019.                                         
#                                                                         
#  Usage: By default, this script will attempt to determine which disks   
#         to use for different volume groups based on the disk size.      
#         If you have varied from the blueprint specifications, you can   
#         modify the disk lists below before executing this script and    
#         specify the -uselist option when invoking the script            
#                                                                         
#         perl storage_prep_win.pl <small|medium|large> [-uselist]        
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
  print "USAGE: storage_prep_win.pl <xsmall|small|medium|large> [-uselist]\n";
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
if ($size !~ m/(xsmall|small|medium|large)/)
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

# Prepare the log file
$log = initLog();
$logHead = getlogHeader();  # write the log header information
lprint ($log, $logHead);

# Set the default number of LUNs per array.  Change this section if you have deviated from the blueprint
if ($size eq "xsmall")
{
  $lunsPerArray = 1;
}
elsif ($size eq "small")
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

$SS = "\\";
$fsPrefix = "c:${SS}tsminst1";
$diskPartIn = "diskpart.in";
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
lprint $log, "** Beginning disk configuration.\n";
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

@dpCmds = qw();
push (@dpCmds, "rescan\n");
push (@dpCmds, "list disk");
writeFile($diskPartIn, @dpCmds);
$cmd = "diskpart /s $diskPartIn";
lprint $log, "\t==>Running command: $cmd\n";
displayList(@dpCmds);
@lsdev = `$cmd`;


# Edit these disk grouping if you are manually specifying the disks to process
# with the -uselist option
if ($uselist)
{
  lprint $log, "** Defining list of disks (-uselist specified).\n";
  if ($size eq "small")
  {
    @db_disks = ("Disk 1", "Disk 2", "Disk 3", "Disk 4");
    @act_disks = ("Disk 5");
    @arch_disks = ("Disk 6");
    @dbbk_disks = ("Disk 7", "Disk 8", "Disk 9", "Disk 10");
    @stg_disks = ("Disk 11", "Disk 12", "Disk 13", "Disk 14", "Disk 15", "Disk 16",
                  "Disk 17", "Disk 18", "Disk 19", "Disk 20", "Disk 21", "Disk 22",
                  "Disk 23", "Disk 24", "Disk 25", "Disk 26", "Disk 27", "Disk 28",
                  "Disk 29", "Disk 30"); 
  }
  elsif ($size eq "medium")
  {
    @db_disks = ("Disk 1", "Disk 2", "Disk 3", "Disk 4");
    @act_disks = ("Disk 5");
    @arch_disks = ("Disk 6", "Disk 7");
    @dbbk_disks = ("Disk 8", "Disk 9", "Disk 10", "Disk 11");
    @stg_disks = ("Disk 12", "Disk 13", "Disk 14", "Disk 15", "Disk 16", "Disk 17",
                  "Disk 18", "Disk 19", "Disk 20", "Disk 21", "Disk 22", "Disk 23",
                  "Disk 24", "Disk 25", "Disk 26", "Disk 27", "Disk 28", "Disk 29",
                  "Disk 30", "Disk 31"); 
  }
  elsif ($size eq "large")
  {
    @db_disks = ("Disk 1", "Disk 2", "Disk 3", "Disk 4", "Disk 5", "Disk 6", "Disk 7", "Disk 8",
                 "Disk 9","Disk 10","Disk 11","Disk 12");
    @act_disks = ("Disk 13");
    @arch_disks = ("Disk 14", "Disk 15", "Disk 16");
    @dbbk_disks = ("Disk 16", "Disk 17", "Disk 18", "Disk 19", "Disk 20", "Disk 21");
    @stg_disks = ("Disk 22", "Disk 23", "Disk 24", "Disk 25", "Disk 26", "Disk 27",
                  "Disk 28", "Disk 29", "Disk 30", "Disk 31", "Disk 32", "Disk 33",
                  "Disk 34", "Disk 35", "Disk 36", "Disk 37", "Disk 38", "Disk 39",
                  "Disk 40", "Disk 41", "Disk 42", "Disk 43", "Disk 44", "Disk 45",
                  "Disk 46", "Disk 47", "Disk 48", "Disk 49", "Disk 50", "Disk 51",
                  "Disk 52", "Disk 53", "Disk 54", "Disk 55", "Disk 56", "Disk 57",
                  "Disk 58", "Disk 59", "Disk 60", "Disk 61", "Disk 62", "Disk 63",
                  "Disk 64", "Disk 65", "Disk 66", "Disk 67", "Disk 68", "Disk 69",
                  "Disk 70", "Disk 71", "Disk 72", "Disk 73", "Disk 74", "Disk 75",
                  "Disk 76", "Disk 77", "Disk 78", "Disk 79", "Disk 80", "Disk 81",
                  "Disk 82", "Disk 83", "Disk 84", "Disk 85", "Disk 86", "Disk 87",
                  "Disk 88", "Disk 89", "Disk 90", "Disk 91", "Disk 92", "Disk 93",
                  "Disk 94", "Disk 95", "Disk 96"); 
  }
  else
  {
    lprint $log, "ERROR: could not determine hdisk list.\n";
    exit (1);
  }

  # Record size of each disk
  foreach $disk (@db_disks)
  {
    ($curDisk) = grep {m/\Q$disk\E\s/} @lsdev;
    $curDisk =~ m/\s+\S+\s+\S+\s+\S+\s+(\d+)\s+/;
    $diskSize = $1;
    push (@db_sizes, $diskSize);
  }
  foreach $disk (@act_disks)
  {
    ($curDisk) = grep {m/\Q$disk\E\s/} @lsdev;
    $curDisk =~ m/\s+\S+\s+\S+\s+\S+\s+(\d+)\s+/;
    $diskSize = $1;
    push (@act_sizes, $diskSize);
  }
  foreach $disk (@arch_disks)
  {
    ($curDisk) = grep {m/\Q$disk\E\s/} @lsdev;
    $curDisk =~ m/\s+\S+\s+\S+\s+\S+\s+(\d+)\s+/;
    $diskSize = $1;
    push (@arch_sizes, $diskSize);
  }
  foreach $disk (@dbbk_disks)
  {
    ($curDisk) = grep {m/\Q$disk\E\s/} @lsdev;
    $curDisk =~ m/\s+\S+\s+\S+\s+\S+\s+(\d+)\s+/;
    $diskSize = $1;
    push (@dbbk_sizes, $diskSize);
  }
  foreach $disk (@stg_disks)
  {
    ($curDisk) = grep {m/\Q$disk\E\s/} @lsdev;
    $curDisk =~ m/\s+\S+\s+\S+\s+\S+\s+(\d+)\s+/;
    $diskSize = $1;
    push (@stg_sizes, $diskSize);
  }
}
else  
{
  lprint $log, "** Determining the list of disks to process\n";

  # Define expected size ranges for different disk types based on system size
  if ($size eq "xsmall")
  {
    $dbLow = 99;
    $dbHigh = 101;
    $actLow = 25;
    $actHigh = 35;
    $archLow = 200;
    $archHigh = 300;
    $dbbkLow = 800;
    $dbbkHigh = 2000;
    $stgLow = 4000;
    $stgHigh = 8001;
  }
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
  foreach $dev (@lsdev)
  {
    chomp ($dev);
    next if ($dev !~ m/Disk\s\d+/);
    ($pad,$diskPre,$hdisk,$status,$diskCap,$unitCap,$diskSize,$unitSize,$dynamic,$GPT) = split (/\s+/, $dev);

    # Skip over disks which are not empty
    if ($diskCap ne $diskSize)
    {
      lprint $log, "\t==>Skipping non-empty disk:\n\t$dev\n";
      next;
    }
    # Skip over disks which are not on-line
    if ($status ne "Online")
    {
      lprint $log, "\t==>Skipping disk that is not on-line:\n\t$dev\n";
      next;
    }

    $hdisk = $diskPre." ".$hdisk;
    if ($unitSize eq "TB")
    {
      $diskSize = $diskSize*1024;
    }
    elsif ($unitSize eq "MB")
    {
      $diskSize = $diskSize/1024;
    }
    elsif ($unitSize eq "GB")
    {
      $diskSize = $diskSize;
    }
    else
    {
      lprint $log, "ERROR: Found disk: $hdisk, with unexpected unit: $unitSize\n";
      exit (1);
    }

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
  if (!grep {m/\Q$disk\E\s+Online/} @lsdev)
  {
    lprint $log, "ERROR: No on-line device found for disk: $disk\n";
    exit (1);
  }
}
lprint $log, "\tAvailable device check complete\t\t\t[OK]\n";

# Validate that the disks in each grouping have the same size
# except for large which can have two different sizes for DB and STGPOOL
lprint $log, "\n";
lprint $log, "** Validating that disks within each grouping have the same size.\n";
@groupNames = qw (db_disks act_disks arch_disks dbbk_disks stg_disks);
@sizeLists = (\@db_sizes, \@act_sizes, \@arch_sizes, \@dbbk_sizes, \@stg_sizes);
$sizeMismatch = 0;
foreach $group (\@db_disks, \@act_disks, \@arch_disks, \@dbbk_disks, \@stg_disks)
{
  $count = 0;
  $curSizeList = shift(@sizeLists);
  $curName = shift(@groupNames);
  lprint $log, "\t==>Processing group ".$curName."\n";
  $refSize = 0;
  $refSize2 = 0;
  $groupWarn = 0;
  foreach $disk (@{$group})
  {
    $curSize = $$curSizeList[$count];
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
    $count++;
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
lprint $log, "** Validating that selected disks do not already contain partitions.\n";

$count=1;
lprint $log, "\t==>Checking disk: ";
foreach $curDisk (@all_disks)
{
  if ($count % 20)
  {
    lprint $log, "$count ";
  }
  else
  {
    lprint $log, "\n\t$count ";
  }
  chomp ($curDisk);
  @dpCmds = qw();
  push (@dpCmds, "select $curDisk\n");
  push (@dpCmds, "list partition");
  writeFile($diskPartIn, @dpCmds);
  $cmd = "diskpart /s $diskPartIn";
  @parts = `$cmd`;
  if (! grep {m/There are no partitions on this disk\E/} @parts)
  {
    lprint $log, "ERROR: Disk $curDisk already contains partitions\n";
    exit (1);
  }
  $count++;
}
lprint $log, "\n\tCheck for existing partitions complete\t[OK]\n";

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


# Disable delete notify to the storage system which can cause extremely slow file system formats
my $disableDeleteNotify = 0;
my $out = `fsutil behavior query DisableDeleteNotify`;
if ($out =~ m/NTFS DisableDeleteNotify = 0/)
{
  lprint $log, "\n";
  lprint $log, "** Disabling storage delete notify with: fsutil behavior set DisableDeleteNotify 1\n";
  `fsutil behavior set DisableDeleteNotify 1`;
  $disableDeleteNotify = 1;
}

@groupNames = qw (db_disks act_disks arch_disks dbbk_disks stg_disks);
@groupLists = (\@db_disks, \@act_disks, \@arch_disks, \@dbbk_disks, \@stg_disks);

# File system name prefixes
%fsNames = ('db_disks','TSMdbspace','act_disks','TSMalog','arch_disks','TSMarchlog','dbbk_disks','TSMbkup',
          'stg_disks', 'TSMfile');

lprint $log, "\n";
lprint $log, "** Formatting file systems.\n";

foreach $group (@groupLists)
{
  $curName = shift(@groupNames);
  lprint $log, "\t==>Processing group ".$curName."\n";
  $count = 0;

  # If there is more than one archive log disk need to stripe across two LUNs
  if (($curName eq "arch_disks") && ($#arch_disks > 0))
  {
    lprint $log, "\t==>Create striped disk set for the archive log\n";
    # Determine file system mount point
    $fsName = $fsPrefix.$SS.$fsNames{$curName};
    $volName = $fsNames{$curName};

    # Make the mount point directory if it does not already exist
    if (! -d $fsName)
    {
      lprint $log, "\t==>Creating the directory: mkdir $fsName\n";
      `mkdir $fsName`;
    }

    @dpCmds = qw();
    $diskList = "";
    foreach $dev (@{$group})
    {
      push (@dpCmds, "select $dev\n");
      push (@dpCmds, "convert gpt\n");
      push (@dpCmds, "convert dynamic\n");
      $dev =~ m/Disk\s+(\d+)/;
      if ($diskList ne "")
      {
        $diskList = $diskList.",".$1;
      }
      else
      {
        $diskList = $diskList.$1;
      }

    }
    push (@dpCmds, "create volume stripe disk=$diskList\n");
    push (@dpCmds, "assign mount=$fsName\n");
    push (@dpCmds, "format FS=NTFS LABEL=$volName UNIT=64K QUICK");
    writeFile($diskPartIn, @dpCmds);
    $cmd = "diskpart /s $diskPartIn";
    lprint $log, "\t==>Running command: $cmd\n";
    displayList(@dpCmds);
    `$cmd`;

    # Validate the file system was created successfully
    @fss = `chkdsk $fsName /I /C`;
    if (!grep {m/and found no problems/i} @fss)
    {
      lprint $log, "ERROR: Unable to create or mount file system $fsName\n";
      exit (1);
    }
    lprint $log, "\tFile system $fsName created\t[OK]\n";
    $count++;
  }
  else   # For all others, format file system directly on full disk partition
  {
    foreach $dev (@{$group})
    {
      lprint $log, "\t==>Processing disk: $dev\n";
 
      # Determine file system mount point
      $prefix = "";
      if ($count < 10)
      {
        $prefix = "0";
      }

      if ($curName eq "act_disks" || $curName eq "arch_disks")
      {
        $fsName = $fsPrefix.$SS.$fsNames{$curName};
        $volName = $fsNames{$curName};
      }
      else
      {
        $fsName = $fsPrefix.$SS.$fsNames{$curName}.$prefix.$count;
        $volName = $fsNames{$curName}.$prefix.$count;
      }

      # Make the mount point directory if it does not already exist
      if (! -d $fsName)
      {
        lprint $log, "\t==>Creating the directory: mkdir $fsName\n";
        `mkdir $fsName`;
      }

      @dpCmds = qw();
      push (@dpCmds, "select $dev\n");
      push (@dpCmds, "convert gpt\n");
      push (@dpCmds, "create partition primary\n");
      push (@dpCmds, "assign mount=$fsName\n");
      # Use a large 64K allocation size for volumes with sequential workloads
      if ($curName eq "act_disks" || $curName eq "db_disks")
      {
        push (@dpCmds, "format FS=NTFS LABEL=$volName UNIT=4096 QUICK");
      }
      else
      {
        push (@dpCmds, "format FS=NTFS LABEL=$volName UNIT=64K QUICK");
      }
      writeFile($diskPartIn, @dpCmds);
      $cmd = "diskpart /s $diskPartIn";
      lprint $log, "\t==>Running command: $cmd\n";
      displayList(@dpCmds);
      `$cmd`;

      # Validate the file system was created successfully
      @fss = `chkdsk $fsName /I /C`;
      if (!grep {m/and found no problems/i} @fss)
      {
        lprint $log, "ERROR: Unable to create or mount file system $fsName\n";
        exit (1);
      }
      lprint $log, "\tFile system $fsName created\t[OK]\n";
      $count++;
    }
  }
}


unlink ($diskPartIn);

# If we turned of delete notify, we need to restore the previous setting
if ($disableDeleteNotify == 1)
{
  lprint $log, "\n";
  lprint $log, "** Re-enabling storage delete notify with: fsutil behavior set DisableDeleteNotify 0\n";
  `fsutil behavior set DisableDeleteNotify 0`;
}

lprint $log, "** All storage preparations have completed successfully.\n";
lprint $log, "\n*-----------------------------------------------------------------------*\n";


sub writeFile ($@)
{
  if (@_ < 2)
  {
    print "USAGE: writeFile filename listofstrings\n";
    return 1;
  }
  ($file,@lines) = @_;
  open INFILE, ">$file" or die "writeFile: error opening file: $file\n";

  # Append the string
  foreach $ln (@lines)
  {
    print INFILE "$ln";
  }

  # Close the file
  close INFILE;

  return 0;
}

sub displayList (@)
{
  foreach $ln (@_)
  {
    chomp ($ln);
    print "\t\t$ln\n";
  }
}


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
