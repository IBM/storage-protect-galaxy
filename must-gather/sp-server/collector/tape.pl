#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";  # Include common modules
use env;
use Getopt::Long;

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $adminid, $password, $optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "adminid|id=s"   => \$adminid,
    "password|pwd=s" => \$password,
    "optfile=s"       => \$optfile,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;
die "Error: --adminid is required\n"   unless $adminid;
die "Error: --password is required\n"  unless $password;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/tape";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Open error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Detect BA client base path
# -----------------------------
my $base_path = env::get_ba_base_path();
unless ($base_path) {
    print $errfh "BA client base path not found.\n";
    close($errfh);
    die "BA client base path not found. Exiting.\n";
}

# -----------------------------
# Locate DSMADMC binary
# -----------------------------
my $os = $^O;
my $dsmadmc;

if ($os =~ /MSWin32/i) {
    $dsmadmc = `where dsmadmc.exe 2>nul`;
    chomp($dsmadmc);
    if (!$dsmadmc || !-e $dsmadmc) {
        $dsmadmc = "$base_path\\dsmadmc.exe" if -e "$base_path\\dsmadmc.exe";
    }
} else {
    $dsmadmc = `which dsmadmc 2>/dev/null`;
    chomp($dsmadmc);
    if (!$dsmadmc || !-x $dsmadmc) {
        $dsmadmc = "$base_path/dsmadmc" if -x "$base_path/dsmadmc";
    }
}

unless ($dsmadmc && -x $dsmadmc) {
    print $errfh "dsmadmc not found at $dsmadmc\n";
    close($errfh);
    die "dsmadmc not found at $dsmadmc\n";
}

# -----------------------------
# DSM Option File Path
# -----------------------------
my $opt_file;
if ($optfile) {
    # User-specified option file
    $opt_file = $optfile;
} else {
    $opt_file = "$base_path/dsm.opt";
}

# -----------------------------
# Quote paths if they contain spaces
# -----------------------------
my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

# -----------------------------
# Function to run a command safely
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;

    my $full_cmd;
    if ($outfile) {
        $full_cmd = qq{$cmd > "$outfile"};
        $full_cmd .= " 2>&1" if $^O !~ /MSWin32/;  # redirect stderr on Unix
    } else {
        $full_cmd = $cmd;
    }

    print $errfh "Running: $full_cmd\n" if $verbose;

    my $status = system($full_cmd);
    $status >>= 8;
    return $status;
}
# -----------------------------
# Define dsm administrative client queries
# -----------------------------
my %server_queries = (
    "qserver.txt"    =>"q server f=d",   
    "libraries.txt"  => "q library format=detailed",
    "drives.txt"     => "q drive f=d",
    "paths.txt"      => "q path f=d",
    "devclasses.txt" => "q devclass f=d",
    "volumes.txt"    => "q volume f=d",
    "libvol.txt"     => "q libvol f=d",
    "qsan.txt"       => "q san",
    "showlibrary.txt"=> "show library",
    "showdevclass.txt"=> "show devclass",
);

# -----------------------------
# Define SQL select statements
# -----------------------------
my @selects = (
    #This query shows all defined drive paths between sources and destinations in the system
    "SELECT b.source_name, a.library_name, a.drive_name, a.drive_serial, b.device FROM drives a, paths b WHERE a.drive_name=b.destination_name",
    
    #This query shows all defined tape drive paths in the system
    "SELECT source_name,source_type,destination_name,destination_type,library_name,device FROM paths",

    #This query gives you a summary of offline tape drives per each library
    "SELECT library_name,count(*) FROM drives WHERE online!='YES' GROUP BY library_name",

    #This query shows how many drive paths are offline per source.
    "SELECT source_name,count(*) FROM paths WHERE online!='YES' GROUP BY source_name",

    #This query gives list of all offline tape drive paths.
    "SELECT source_name,destination_name,online FROM paths WHERE online!='YES'",

    #This query shows list of all drives which are offline.
    "SELECT library_name,drive_name,online FROM drives WHERE online!='YES'",

    #This query is counting the number of tape drive paths that are not online
    "SELECT COUNT(*) FROM paths WHERE NOT online='Yes'",

    #That query is counting the number of tape drives that are not online.
    "SELECT COUNT(*) FROM drives WHERE NOT online='Yes'",
);

# -----------------------------
# Run dsm administrative client queries
# -----------------------------
my %collected_files;

foreach my $file (sort keys %server_queries) {
    my $query = $server_queries{$file};
    my $outfile = "$output_dir/$file";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
    run_cmd($cmd, $outfile);
}


# -----------------------------
# Collect library names via SQL query
# -----------------------------
my $raw_lib_file = "$output_dir/raw_libraries.txt";
my $sql_query = 'select library_name from libraries';
my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$sql_query"};
run_cmd($cmd, $raw_lib_file);

# -----------------------------
# Extract library names from SQL output and run SHOW SLOTS
# -----------------------------
my $showslots_file = "$output_dir/showslots.txt";
my @libs;

# Read library names from raw_libraries.txt
if (-s $raw_lib_file && open(my $lfh, '<', $raw_lib_file)) {
    while (<$lfh>) {
        s/\r//g;

        # Skip unwanted lines
        next if /LIBRARY_NAME/i;    # skip header
        next if /^[-\s]*$/;         # skip blank or dashed lines
        next if /Session/;          # skip session info
        next if /Server/;           # skip server info
        next if /IBM Storage Protect/i;  # skip product name
        next if /Command Line Administrative Interface/i;  # skip version info
        next if /\(c\)/i;   # skip copyright line
        next if /ANS8002I/i;             # skip return code line
        next if /^ANR/i;
        next if /^ANS/i;
        chomp;
        my $lib = $_;
        $lib =~ s/^\s+|\s+$//g;
        push @libs, $lib if $lib ne '';
    }
    close($lfh);
}


open(my $sfh, '>', $showslots_file) or do {
    print $errfh "Cannot open $showslots_file: $!\n";
    $collected_files{"showslots.txt"} = "FAILED";
    goto SHOWSLOTS_DONE;
};

if (@libs) {
    foreach my $lib (@libs) {
        print $sfh "===== SHOW SLOTS for $lib =====\n";
        my $tmp_out = "$output_dir/showslots_$lib.txt";
        my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "show slots $lib"};
        run_cmd($cmd, $tmp_out);  
    }
    $collected_files{"showslots.txt"} = "SUCCESS";
} else {
    print $errfh "No libraries detected in $raw_lib_file\n";
    $collected_files{"showslots.txt"} = "NOT FOUND";
}

SHOWSLOTS_DONE:
close($sfh);


# -----------------------------
# Run SQL select statements (query + output)
# -----------------------------
my $sql_dir = "$output_dir/sql";
make_path($sql_dir) unless -d $sql_dir;

my $sql_count = 1;
foreach my $select (@selects) {
    my $file = sprintf("select_%02d.txt", $sql_count++);
    my $outfile = "$sql_dir/$file";

    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$select"};
    print $errfh "Executing: $cmd\n" if $verbose;
    run_cmd($cmd,$outfile);
}

# -----------------------------
# OS-specific tape info collection
# -----------------------------
my %os_queries;
if ($os =~ /linux/i) {
    my $osrelease = `cat /etc/os-release 2>/dev/null`;
    my $is_ubuntu = ($osrelease =~ /ubuntu/i) ? 1 : 0;
    my $is_suse   = ($osrelease =~ /sles|opensuse/i) ? 1 : 0;
    my $is_rhel   = ($osrelease =~ /rhel|redhat|centos/i) ? 1 : 0;

    %os_queries = (
        "byid.txt"           => "ls -al /dev/lin_tape/by-id",
        "lsltr.txt"          => "ls -ltr /dev/IBM*",
        "sudo_ibmtape.txt"   => "cat /proc/scsi/IBMtape",
        "sgvers.txt"         => "cat /proc/scsi/sg/version",
        "sgstrs.txt"         => "cat /proc/scsi/sg/device_strs",
        "sgdevs.txt"         => "cat /proc/scsi/sg/devices",
        "tsmscsi.txt"        => "ls -l /dev/tsmscsi",
        "lbinfo.txt"         => "cat /dev/tsmscsi/lbinfo",
        "mtinfo.txt"         => "cat /dev/tsmscsi/mtinf",
        "messages.txt"       => (-e "/var/log/messages") ? "cat /var/log/messages" : "journalctl -xe",
        "lin_tape_rules.txt" => "cat /etc/udev/rules.d/98-lin_tape.rules",
        "lintapestatus.txt"  => "lin_taped status",
    );

    if ($is_rhel || $is_suse) {
        $os_queries{"rpm_tape_output.txt"} = "rpm -qa | grep -i tape";
    } elsif ($is_ubuntu) {
        $os_queries{"dpkg_tape_output.txt"} = "dpkg -l | grep -i tape";
    }

} elsif ($os =~ /aix/i) {
    %os_queries = (
        "lsdev_tape.txt"      => "lsdev -Cc tape",
        "lsdev_adsmtape.txt"  => "lsdev -Cc adsmtape",
        "atape_version.txt"   => "lslpp -l | grep Atape",
        "rmt_device.txt"      => "lscfg -vl rmt*",
        "smc_device.txt"      => "lscfg -vl smc*",
        "lsltr.txt"           => "ls -ltr /dev/IBM*",
        "errpt.txt"           => "errpt -a",
        "oslevel.txt"         => "oslevel -s",
    );
}

foreach my $outfile (keys %os_queries) {
    my $dest_file = "$output_dir/$outfile";
    my $cmd = "$os_queries{$outfile} > $dest_file 2>>$error_log";
    my $status = system($cmd);
    $status >>= 8;
    if ($status == 0) {
        $collected_files{$outfile} = "SUCCESS";
    } else {
        $collected_files{$outfile} = "FAILED";
        print $errfh "Error: Failed to run $os_queries{$outfile}. Exit code: $status\n";
    }
}

# -----------------------------
# Collect tsmdlst output on Windows
# -----------------------------
if ($os =~ /MSWin32/i) {
    my $tsmdlst_exe = "C:\\Program Files\\Tivoli\\TSM\\console\\tsmdlst.exe";
    my $tsmdlst_out = "$output_dir/tsmdlst.out";
    if (-x $tsmdlst_exe) {
        my $status = system("\"$tsmdlst_exe\" > \"$tsmdlst_out\" 2>>$error_log");
        $status >>= 8;
        $collected_files{"tsmdlst.out"} = ($status == 0) ? "SUCCESS" : "FAILED";
    } else {
        $collected_files{"tsmdlst.out"} = "NOT FOUND";
        print $errfh "Warning: tsmdlst not found at $tsmdlst_exe\n";
    }
}

# -----------------------------
# Summary of collected files
# -----------------------------
close($errfh);
my %summary;

# Static queries
foreach my $file (sort keys %server_queries) {
    my $outfile = "$output_dir/$file";
    $summary{$file} = (-s $outfile) ? "SUCCESS" : "FAILED";
}

if ($verbose) {
    print "\n=== Tape Module Summary ===\n";
    foreach my $file (sort keys %summary) {
        printf "  %-15s : %s\n", $file, $summary{$file};
    }
    foreach my $file (sort keys %collected_files) {
        printf "  %-15s : %s\n", $file, $collected_files{$file};
    }
    print "Collected tape files saved in: $output_dir\n";
    print "Check script.log for any failures.\n";
}

# -----------------------------
# Determine module-level status for framework
# -----------------------------
my $Success_count = 0;
my $fail_count = 0;
my $total = scalar keys %collected_files;

foreach my $status (values %collected_files) {
    $Success_count++ if $status eq "SUCCESS";
    $fail_count++    if $status eq "FAILED";
}

my $module_status;
if ($Success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

# Exit code mapping for framework (optional: 0=Success, 1=Failure, 2=Partial)
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);
