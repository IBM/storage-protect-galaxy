## Appendix B. Configuring the disk system by using commands

### Large system

1. Connect to and log in to the disk system by issuing the ssh command. For example:
   ```
    ssh superuser@yourLargeStorageSystemHostname
   ```
1. <a name="large-system-step-2"></a>Increase the memory that is available for the RAIDs to 125 MB by issuing the chiogrp command:
   ```
    chiogrp -feature raid -size 125 io_grp0
   ```
1. List drive IDs for each type of disk so that you can create the MDisk arrays in [Step "5"](#large-system-step-5). Issue the **lsdrive** command. The output can vary, based on slot placement for the different disks. The output is similar to what is returned for small and medium systems.
1. Create the MDisk groups for the IBM Storage Protect database and storage pool. Issue the **mkmdiskgroup** command for each pool, specifying 1024 for the extent size:
   ```
    mkmdiskgrp -name db_grp0 -ext 1024
    mkmdiskgrp -name stgpool_grp0 -ext 1024
   ```
1. <a name="large-system-step-5"></a>Create arrays by using the mkdistributedarray command. Specify the commands to add the MDisk arrays to the data pools that you created in the previous step. </br>For example:
   ```
    mkdistributedarray -name db_array0 -level raid6 -driveclass 0 -drivecount 9 -stripewidth 8 -rebuildareas 1 -strip 256 db_grp0
    mkdistributedarray -name stgpool_array0 -level raid6 -driveclass 1 -drivecount 46 -stripewidth 12 -rebuildareas 2 -strip 256 stgpool_grp0
    mkdistributedarray -name stgpool_array1 -level raid6 -driveclass 1 -drivecount 46 -stripewidth 12 -rebuildareas 2 -strip 256 stgpool_grp0
    mkdistributedarray -name stgpool_array2 -level raid6 -driveclass 1 -drivecount 46 -stripewidth 12 -rebuildareas 2 -strip 256 stgpool_grp0
    mkdistributedarray -name stgpool_array3 -level raid6 -driveclass 1 -drivecount 46 -stripewidth 12 -rebuildareas 2 -strip 256 stgpool_grp0
   ```
1. <a name="large-system-step-6"></a>Create the storage volumes for the system. Issue the mkvdisk command for each volume, specifying the volume sizes in MB. </br> For example:
   ```
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_01 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_02 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_03 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_04 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_05 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_06 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_07 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_08 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_09 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_10 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp db_grp0 -size 858000 -unit mb -name db_11 -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp db_grp0 -size 563200 -unit mb -name alog -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 4200000 -unit mb -name archlog -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 18874368 -unit mb -name backup_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 18874368 -unit mb -name backup_01 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 18874368 -unit mb -name backup_02 -iogrp 0 -nofmtdisk

    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_00 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_01 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_02 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_03 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_04 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_05 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_06 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_07 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_08 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_09 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_10 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_11 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_12 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_13 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_14 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_15 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_16 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_17 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_18 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_19 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_20 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_21 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_22 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_23 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_24 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_25 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_26 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_27 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_28 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_29 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_30 -iogrp 0 -nofmtdisk
    mkvdisk -mdiskgrp stgpool_grp0 -size 32856064 -unit mb -name filepool_31 -iogrp 0 -nofmtdisk
   ```
1. Create a logical host object by using the mkhost command. Specify the Fibre Channel WWPNs from your operating system and specify the name of your host. For instructions about obtaining the WWPNs from your system, see ["Step 1: Setup and configure hardware"](#step-1-setup-and-configure-hardware). For example, to create a host that is named hostone with a list that contains FC WWPNs 10000090FA3D8F12 and 10000090FA49009E , issue the following command:
   ```
    mkhost -name hostone -fcwwpn 10000090FA3D8F12:10000090FA3D8F13:10000090FA49009E:10000090FA49009F -iogrp 0 -type=generic -force
   ```
1. Map the volumes that you created in [Step "6"](#large-system-step-6) to the new host. Issue the **mkvdiskhostmap** command for each volume. For example, issue the following commands where hostname is the name of your host:
   ```
    mkvdiskhostmap -host hostname -scsi 0 db_00
    mkvdiskhostmap -host hostname -scsi 1 db_01
    mkvdiskhostmap -host hostname -scsi 2 db_02
    mkvdiskhostmap -host hostname -scsi 3 db_03
    mkvdiskhostmap -host hostname -scsi 4 db_04
    mkvdiskhostmap -host hostname -scsi 5 db_05
    mkvdiskhostmap -host hostname -scsi 6 db_06
    mkvdiskhostmap -host hostname -scsi 7 db_07
    mkvdiskhostmap -host hostname -scsi 8 db_08
    mkvdiskhostmap -host hostname -scsi 9 db_09
    mkvdiskhostmap -host hostname -scsi 10 db_10
    mkvdiskhostmap -host hostname -scsi 11 db_11

    mkvdiskhostmap -host hostname -scsi 12 alog

    mkvdiskhostmap -host hostname -scsi 13 archlog

    mkvdiskhostmap -host hostname -scsi 14 backup_00
    mkvdiskhostmap -host hostname -scsi 15 backup_01
    mkvdiskhostmap -host hostname -scsi 16 backup_02

    mkvdiskhostmap -host hostname -scsi 17 filepool_00
    mkvdiskhostmap -host hostname -scsi 18 filepool_01
    mkvdiskhostmap -host hostname -scsi 19 filepool_02
    mkvdiskhostmap -host hostname -scsi 20 filepool_03
    mkvdiskhostmap -host hostname -scsi 21 filepool_04
    mkvdiskhostmap -host hostname -scsi 22 filepool_05
    mkvdiskhostmap -host hostname -scsi 23 filepool_06
    mkvdiskhostmap -host hostname -scsi 24 filepool_07
    mkvdiskhostmap -host hostname -scsi 25 filepool_08
    mkvdiskhostmap -host hostname -scsi 26 filepool_09
    mkvdiskhostmap -host hostname -scsi 27 filepool_10
    mkvdiskhostmap -host hostname -scsi 28 filepool_11
    mkvdiskhostmap -host hostname -scsi 29 filepool_12
    mkvdiskhostmap -host hostname -scsi 30 filepool_13
    mkvdiskhostmap -host hostname -scsi 31 filepool_14
    mkvdiskhostmap -host hostname -scsi 32 filepool_15
    mkvdiskhostmap -host hostname -scsi 33 filepool_16
    mkvdiskhostmap -host hostname -scsi 34 filepool_17
    mkvdiskhostmap -host hostname -scsi 35 filepool_18
    mkvdiskhostmap -host hostname -scsi 36 filepool_19
    mkvdiskhostmap -host hostname -scsi 37 filepool_20
    mkvdiskhostmap -host hostname -scsi 38 filepool_21
    mkvdiskhostmap -host hostname -scsi 39 filepool_22
    mkvdiskhostmap -host hostname -scsi 40 filepool_23
    mkvdiskhostmap -host hostname -scsi 41 filepool_24
    mkvdiskhostmap -host hostname -scsi 42 filepool_25
    mkvdiskhostmap -host hostname -scsi 43 filepool_26
    mkvdiskhostmap -host hostname -scsi 44 filepool_27
    mkvdiskhostmap -host hostname -scsi 45 filepool_28
    mkvdiskhostmap -host hostname -scsi 46 filepool_29
    mkvdiskhostmap -host hostname -scsi 47 filepool_30
    mkvdiskhostmap -host hostname -scsi 48 filepool_31
   ```