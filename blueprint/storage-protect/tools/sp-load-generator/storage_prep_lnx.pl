#------------------------------------------------------------------------------
#  Name: storage_prep_lnx.pl                                              
#                                                                         
#  Desc:  Prepare the LVM components of the IBM Storage Protect blueprint storage on      
#         Linux x86_64 and Linux on Power.                                                   
#                                                                         
#  Usage: You must modify the disk lists below before executing this      
#         script if your disk layout differs from the blueprint           
#         specifications.  This script must be run as root.               
#                                                                         
#         perl storage_prep_lnx.pl <xsmall|small|medium|large> [-lvm] [-extdb]            
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

if (@ARGV < 1 || @ARGV > 3)
{
  print "USAGE: storage_prep_lnx.pl <xsmall|small|medium|large> [-lvm] [-extdb]\n";
  exit (1);
}

$size = "invalid";
$lvm = "no";
$xfsdb = "yes";

while ($nextArg = shift(@ARGV))
{
  if ($nextArg =~ m/(xsmall|small|medium|large)/)
  {
    $size = $nextArg;
  }
  elsif ($nextArg =~ m/-lvm/)
  {
    $lvm = "yes"; 
  }
  elsif ($nextArg =~ m/-extdb/)  
  {
    $xfsdb = "no"; 
  }
  else
  {
    print "ERROR: incorect parameter, <$nextArg> specified.\n";
    exit (1);
  }
}

if ($size !~ m/(xsmall|small|medium|large)/)
{
  print "ERROR: incorrect or no size specified.\n";
  exit (1);
}

$platform = getPlatform();

# Prepare the log file
$log = initLog();
$logHead = getlogHeader();  # write the log header information
lprint ($log, $logHead);

# Set the default number of LUNs per array.  Change this section if you have deviated from the blueprint
#New add for xsmall 
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


$fsPrefix = "/tsminst1";
$mpioPrefix = "/dev/mapper";
if ($xfsdb eq "yes")
{
  $dbFS = "XFS";
  $fstabOpts = "xfs defaults,inode64 0 0";
  $mkfsCmd = "mkfs -t xfs -K";
}
else    # If XFS will not be used for the database, file system depends on PPC vs x86
{
  if ($platform eq "LINUXPPC" || $platform eq "LINUXPPCLE")    # Use ext3 for Linux PPC
  {
    $dbFS = "EXT3";
    $fstabOpts = "ext3 defaults 0 0";
    $mkfsCmd = "mkfs -t ext3 -i 524288 -m 2 -E nodiscard";
  }
  else
  {
    $dbFS = "EXT4";
    $fstabOpts = "ext4 defaults 0 0";
    $mkfsCmd = "mkfs -t ext4 -T largefile -m 2 -E nodiscard";
  }
}
$fstabOptsStg = "xfs defaults,inode64 0 0";        # xfs file system will be used for stgpool and dbbackup volumes
$mkfsCmdStg = "mkfs -t xfs -K";

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
if ($lvm eq "no")
{
  lprint $log, "** Beginning disk configuration (without LVM).\n";
}
else
{
  lprint $log, "** Beginning disk configuration (with LVM).\n";
}
lprint $log, "** Using $dbFS file system for the database.\n";
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

#Change for xsmall 
if ($size eq "xsmall")
{
  $cmd = "lsblk -n -o NAME";
}
else
{
  $cmd = "multipath -l -v 1";
}
lprint $log, "\t==>Running command: $cmd\n";
@devs = `$cmd`;
#Change for xsmall 
if ($size eq "xsmall")
{
  @devs = grep {m/^sd[b-z]/i} @devs;
}
@devs = sort(@devs);

# Define expected size ranges for different disk types based on system size
#New add for xsmall 
if ($size eq "xsmall")
{
  $dbLow = 300;
  $dbHigh = 351;
  $actLow = 15;
  $actHigh = 31;
  $archLow = 150;
  $archHigh = 251;
  $dbbkLow = 500;
  $dbbkHigh = 1001;
  $stgLow = 2000;
  $stgHigh = 6001;
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

lprint $log, "\t==>Determining disk sizes\n";
$count = 1;
lprint $log, "\t==> ";
foreach $dev (@devs)
{
  #Change for xsmall 
  if ($size eq "xsmall")
  {
    $dev = "/dev/".$dev;
  }
  if ($count % 20)
  {
    lprint $log, "$count ";
  }
  else
  {
    lprint $log, "\n\t$count ";
  }
  chomp ($dev);
  
  #Change for xsmall   
  if ($size eq "xsmall")
  {
    @devout = `lsblk $dev`;
 
    $devShort = substr($dev,5);
    @devout = grep {m/\Q$devShort\E/} @devout;
    $diskSize = shift(@devout);

    # Add full prefix to device name
    #Change for xsmall 
    #$dev = $mpioPrefix."/".$dev;

    # Get the disk size in GB
    #Change for xsmall 
    $diskSize =~ m/\Q$devShort\E\s+\S+\s+\S+\s+([\d|\.]+)([KMGT])\s+/;
    $cap = $1;
    $unit = $2;
  }
  else{
    @devout = `multipath -l $dev`;
    @devout = grep {m/size=/} @devout;
    $diskSize = shift(@devout);

    # Add full prefix to device name
    $dev = $mpioPrefix."/".$dev;

    # Get the disk size in GB
    $diskSize =~ m/.*size=([\d|\.]+)([KMGT])\s+/;
    $cap = $1;
    $unit = $2;
  }

  if($unit eq "K")
  {
    $diskSize = $cap / 1024 / 1024;
  }
  elsif($unit eq "M")
  {
    $diskSize = $cap / 1024;
  }
  elsif($unit eq "G")
  {
    $diskSize = $cap;
  }
  elsif($unit eq "T")
  {
    $diskSize = $cap * 1024;
  }
  $diskSize = int ($diskSize);

  # Add to group based on size
  if ($diskSize >= $actLow && $diskSize < $actHigh)
  {
    push (@act_disks, $dev);
    push (@act_sizes, $diskSize);
  }
  elsif ($diskSize >= $dbLow && $diskSize < $dbHigh)
  {
    push (@db_disks, $dev);
    push (@db_sizes, $diskSize);
  }
  elsif ($diskSize >= $stgLow && $diskSize < $stgHigh)
  {
    push (@stg_disks, $dev);
    push (@stg_sizes, $diskSize);
  }
  elsif ($size eq "small" && $diskSize >= $archLow && $diskSize < $archHigh && $#arch_disks == -1)
  {
    push (@arch_disks, $dev);
    push (@arch_sizes, $diskSize);
  }
  elsif ($size ne "small" && $diskSize >= $archLow && $diskSize < $archHigh)
  {
    push (@arch_disks, $dev);
    push (@arch_sizes, $diskSize);
  }
  elsif ($diskSize >= $dbbkLow && $diskSize < $dbbkHigh)
  {
    push (@dbbk_disks, $dev);
    push (@dbbk_sizes, $diskSize);
  }
  else
  {
    lprint $log, "WARNING: Found disk: $dev, with unexpected size: $diskSize\n";
  }
  $count ++;
}
lprint $log, "\n";

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
#Change for xsmall 
if ($size eq "xsmall"){
  if ($diskCount < 2)
  {
    lprint $log, "ERROR: Fewer than two disks were identified\n";
    exit (1);
  }
  if ($#db_disks < 0 || $#act_disks < 0 || $#arch_disks < 0 || $#dbbk_disks < 0 || $#stg_disks < 0)
  {
    lprint $log, "ERROR: No disks found for one or more categories\n";
    exit (1);
  }
}
else{
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
}

# Print out the disks to be processed by group
lprint $log, "** Disks to be processed:\n";
lprint $log, "\t==>Database disks and sizes (GB)\n";
$count = 1;
for ($i=0; $i<= $#db_disks; $i++)
{
  lprint $log, "\t$count. $db_disks[$i] ($db_sizes[$i])\n";
  $count++;
}
lprint $log, "\n\t==>Active log disks and sizes (GB)\n";
for ($i=0; $i<= $#act_disks; $i++)
{
  lprint $log, "\t$count. $act_disks[$i] ($act_sizes[$i])\n";
  $count++;
}
lprint $log, "\n\t==>Archive log disks and sizes (GB)\n";
for ($i=0; $i<= $#arch_disks; $i++)
{
  lprint $log, "\t$count. $arch_disks[$i] ($arch_sizes[$i])\n";
  $count++;
}
lprint $log, "\n\t==>Database backup disks and sizes (GB)\n";
for ($i=0; $i<= $#dbbk_disks; $i++)
{
  lprint $log, "\t$count. $dbbk_disks[$i] ($dbbk_sizes[$i])\n";
  $count++;
}
lprint $log, "\n\t==>Storage pool disks and sizes (GB)\n";
for ($i=0; $i<= $#stg_disks; $i++)
{
  lprint $log, "\t$count. $stg_disks[$i] ($stg_sizes[$i])\n";
  $count++;
}


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


# Validate that disks are not already used for a file system
lprint $log, "\n";
lprint $log, "** Validating that disks are not known to hold a file system.\n";
$cmd = "blkid";
lprint $log, "\t==>Running command: $cmd\n";
@blkids = `$cmd`;
foreach $dev (@all_disks)
{
  if (grep {m/\Q$dev\E/} @blkids)
  {
    lprint $log, "ERROR: Device $dev\n  is reported in blkid output, and may already contain a file system\n";
    exit (1);
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


if ($lvm eq "no")    # By default, file systems will be formatted on the entire device without LVM
{
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

    # If there is more than one archive log disk we will need to use LVM for the archlog
    if (($curName eq "arch_disks") && ($#arch_disks > 0))
    {
      $vg = "tsmarchlog";
      lprint $log, "\t==>Create volume group ".$vg."\n";

      foreach $dev (@{$group})
      {
        $cmd = "pvcreate ".$dev;
        lprint $log, "\t==>Running command: $cmd\n";
        `$cmd`;
      }
      $cmd = "vgcreate $vg ".join(' ',@{$group});
      lprint $log, "\t==>Running command: $cmd\n";
      `$cmd`;
      @vgs = `vgs`;
      if (!grep {m/\Q$vg\E/} @vgs)
      {
        lprint $log, "ERROR: Unable to create volume group $vg\n";
        exit (1);
      }
      lprint $log, "\tVolume group $vg created\t\t\t[OK]\n";

      $sumPP = 0;
      @pvs = `pvs --units S`;
      @pvs = grep {m/\Q$vg\E\s+/} @pvs;
      foreach $pv (@pvs)  # build up list of pdisks and cumulative size
      {
        next if ($pv !~ m/tsm/);
        ($blank,$dev,$vgName,$lvmType,$attr,$pvSize,$pvFree) = split (/\s+/, $pv);
        $pvFree =~ m/(\d+)S/;
        $sumPP = $sumPP + $1;
      }
      $sumPP = $sumPP."S";

      # Create the Logical volume
      $lvName = "tsmarch00";
      $cmd = "lvcreate -L $sumPP -n $lvName $vg";
      lprint $log, "\t==>Running command: $cmd\n";
      `$cmd`;    
      @lvs = `lvs`;
      if (!grep {m/\Q$lvName\E/} @lvs)
      {
        lprint $log, "ERROR: Unable to create logical volume $lvName\n";
        exit (1);
      }
      lprint $log, "\tLogical volume $lvName created\t\t\t[OK]\n";

      # Determine file system mount point and device name
      $fsName = $fsPrefix."/".$fsNames{$curName};
      $dev = $mpioPrefix."/".$vg."-".$lvName;

      # Create the file system
      lprint $log, "\t==>Running cmd: $mkfsCmd\n\t  $dev\n";
      $cmd = $mkfsCmd." ".$dev." 2>&1";
      `$cmd`;    

      # Write an entry into the fs tab for the new file system
      lprint $log, "\t==>Adding fstab entry: $dev\n\t  $fsName $fstabOpts\n";
      $fstabLine = $dev." ".$fsName." ".$fstabOpts;
      `echo \"$fstabLine\" >> /etc/fstab`;

      # Mount the newly created file system
      if (! -d $fsName)
      {
        $cmd = "mkdir -p $fsName";
        lprint $log, "\t==>Running command: $cmd\n";
        `$cmd`;
      }
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
    else   # For all others, format file system directly on full disk
    {
      foreach $dev (@{$group})
      {
        if ($curName eq "stg_disks" || $curName eq "dbbk_disks" || $curName eq "arch_disks")
        {
          lprint $log, "\t==>Running cmd: $mkfsCmdStg\n\t  $dev\n";
          $cmd = $mkfsCmdStg." ".$dev." 2>&1";
        }
        else
        {
          lprint $log, "\t==>Running cmd: $mkfsCmd\n\t  $dev\n";
          $cmd = $mkfsCmd." ".$dev." 2>&1";
        }
        `$cmd`;    

        # Determine file system mount point
        $prefix = "";
        if ($count < 10)
        {
          $prefix = "0";
        }

        if ($curName eq "act_disks" || $curName eq "arch_disks")
        {
          $fsName = $fsPrefix."/".$fsNames{$curName};
        }
        else
        {
          $fsName = $fsPrefix."/".$fsNames{$curName}.$prefix."$count";
        }

        # Write an entry into the fs tab for the new file system
        if ($curName eq "stg_disks" || $curName eq "dbbk_disks")
        {
          lprint $log, "\t==>Adding fstab entry: $dev\n\t  $fsName $fstabOptsStg\n";
          $fstabLine = $dev." ".$fsName." ".$fstabOptsStg;
        }
        else
        {
          lprint $log, "\t==>Adding fstab entry: $dev\n\t  $fsName $fstabOpts\n";
          $fstabLine = $dev." ".$fsName." ".$fstabOpts;
        }
        `echo \"$fstabLine\" >> /etc/fstab`;

        # Mount the newly created file system
        if (! -d $fsName)
        {
          $cmd = "mkdir -p $fsName";
          lprint $log, "\t==>Running command: $cmd\n";
          `$cmd`;
        }
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
} # end of non-LVM section

else   # Use LVM for all file systems
{
  @groupNames = qw (db_disks act_disks arch_disks dbbk_disks stg_disks);
  @groupLists = (\@db_disks, \@act_disks, \@arch_disks, \@dbbk_disks, \@stg_disks);

  %vgNames = ('db_disks','tsmdb','act_disks','tsmactlog','arch_disks','tsmarchlog','dbbk_disks','tsmdbback',
              'stg_disks', 'tsmstgpool');

  # Create volume groups
  lprint $log, "\n";
  lprint $log, "** Creating volume groups.\n";

  foreach $group (@groupLists)
  {
    $curName = shift(@groupNames);
    lprint $log, "\t==>Processing group ".$curName."\n";
    $count = 0;

    foreach $dev (@{$group})
    {
      $cmd = "pvcreate ".$dev;
      lprint $log, "\t==>Running command: $cmd\n";
      `$cmd`;
    }
    $cmd = "vgcreate $vgNames{$curName} ".join(' ',@{$group});
    lprint $log, "\t==>Running command: $cmd\n";
    `$cmd`;
    @vgs = `vgs`;
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
    @pvs = `pvs --units S`;
    @pvs = grep {m/\Q$vg\E\s+/} @pvs;

    # The archlog for medium and large needs to stripe several pdisks into one lv
    if (($vg eq "tsmarchlog") && ($#arch_disks > 0))
    {
      $sumPP = 0;
      foreach $pv (@pvs)  # build up list of pdisks and cumulative size
      {
        next if ($pv !~ m/tsm/);
        ($blank,$dev,$vgName,$lvmType,$attr,$pvSize,$pvFree) = split (/\s+/, $pv);
        $pvFree =~ m/(\d+)S/;
        $sumPP = $sumPP + $1;
      }
      $sumPP = $sumPP."S";

      # Create the Logical volume
      $lvName = "tsmarch00";
      $cmd = "lvcreate -L $sumPP -n $lvName $vg";
      lprint $log, "\t==>Running command: $cmd\n";
      `$cmd`;    
      @lvs = `lvs`;
      if (!grep {m/\Q$lvName\E/} @lvs)
      {
        lprint $log, "ERROR: Unable to create logical volume $lvName\n";
        exit (1);
      }
      lprint $log, "\tLogical volume $lvName created\t\t\t[OK]\n";

      # Determine file system mount point and device name
      $fsName = $fsPrefix."/".$fsNames{$vg};
      $dev = $mpioPrefix."/".$vg."-".$lvName;

      # Create the file system
      lprint $log, "\t==>Running cmd: $mkfsCmd\n\t  $dev\n";
      $cmd = $mkfsCmd." ".$dev." 2>&1";
      `$cmd`;    

      # Write an entry into the fs tab for the new file system
      lprint $log, "\t==>Adding fstab entry: $dev\n\t  $fsName $fstabOpts\n";
      $fstabLine = $dev." ".$fsName." ".$fstabOpts;
      `echo \"$fstabLine\" >> /etc/fstab`;

      # Mount the newly created file system
      if (! -d $fsName)
      {
        $cmd = "mkdir -p $fsName";
        lprint $log, "\t==>Running command: $cmd\n";
        `$cmd`;
      }
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
        next if ($pv !~ m/tsm/);
        ($blank,$dev,$vgName,$lvmType,$attr,$pvSize,$pvFree) = split (/\s+/, $pv);

        # Determine file system mount point and device name
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
        $dev = $mpioPrefix."/".$vg."-".$lvName;

        # Create the Logical volume
        $cmd = "lvcreate -L $pvFree -i 1 -n $lvName $vg";
        lprint $log, "\t==>Running command: $cmd\n";
        `$cmd`;    
        @lvs = `lvs`;
        if (!grep {m/\Q$lvName\E/} @lvs)
        {
          lprint $log, "ERROR: Unable to create logical volume $lvName\n";
          exit (1);
        }
        lprint $log, "\tLogical volume $lvName created\t\t\t[OK]\n";

        # Create the file system
        if ($vg eq "tsmstgpool" || $vg eq "tsmdbback")
        {
          lprint $log, "\t==>Running cmd: $mkfsCmdStg\n\t  $dev\n";
          $cmd = $mkfsCmdStg." ".$dev." 2>&1";
        }
        else
        {
          lprint $log, "\t==>Running cmd: $mkfsCmd\n\t  $dev\n";
          $cmd = $mkfsCmd." ".$dev." 2>&1";
        }
        `$cmd`;    

        # Write an entry into the fs tab for the new file system
        if ($vg eq "tsmstgpool" || $vg eq "tsmdbback")
        {
          lprint $log, "\t==>Adding fstab entry: $dev\n\t  $fsName $fstabOptsStg\n";
          $fstabLine = $dev." ".$fsName." ".$fstabOptsStg;
        }
        else
        {
          lprint $log, "\t==>Adding fstab entry: $dev\n\t  $fsName $fstabOpts\n";
          $fstabLine = $dev." ".$fsName." ".$fstabOpts;
        }
        `echo \"$fstabLine\" >> /etc/fstab`;

        # Mount the newly created file system
        if (! -d $fsName)
        {
          $cmd = "mkdir -p $fsName";
          lprint $log, "\t==>Running command: $cmd\n";
          `$cmd`;
        }
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
} # end of LVM section


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
