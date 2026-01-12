#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use Getopt::Long;

# -----------------------------
# Parse arguments
# -----------------------------
my ($output_dir, $verbose, $adminid, $password, $options);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "adminid|id=s"   => \$adminid,
    "password|pwd=s" => \$password,
    "options=s"      => \$options,
) or die "Invalid arguments\n";

die "--output-dir required\n" unless $output_dir;
die "--adminid required\n"    unless $adminid;
die "--password required\n"   unless $password;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/library_sharing";
make_path($output_dir) unless -d $output_dir;

my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die $!;

# -----------------------------
# Locate dsmadmc
# -----------------------------
my $base_path = env::get_ba_base_path() or die "BA base path not found\n";
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

my $opt_file = $options || "$base_path/dsm.opt";
my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

sub run_cmd {
    my ($cmd, $outfile) = @_;
    my $full = qq{$cmd > "$outfile" 2>&1};
    print $errfh "Running: $full\n" if $verbose;
    my $rc = system($full);
    return ($rc >> 8);
}

my %collected_files;

# -----------------------------
# Detect local server name
# -----------------------------
my $qstatus = "$output_dir/servername.out";
run_cmd(
    qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "select SERVER_NAME from status"},
    $qstatus
);

my $local_server = "";

open(my $sfh, '<', $qstatus) or die "Cannot open $qstatus: $!";
while (<$sfh>) {
    chomp;

    # Skip noise
    next if /^\s*$/;
    next if /^(IBM|Server Version|Command Line|Copyright|\(c\))/i;
    next if /^ANS\d+/;
    next if /^ANR\d+/;
    next if /^SERVER_NAME/i;
    next if /^-+/;

    s/^\s+|\s+$//g;   # trim whitespace
    $local_server = $_;
    last;             # first valid data line is enough
}
close($sfh);

die "Unable to determine local server name\n" unless $local_server;

# -----------------------------
# Run SQL query for library role detection
# -----------------------------
my $qsql = "$output_dir/library_role.out";
run_cmd(
    qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "select LIBRARY_TYPE, SHARED, PRIMARY_LIB_MGR from libraries"},
    $qsql
);

$collected_files{"library_role.out"} =
    (-s $qsql) ? "SUCCESS" : "FAILED";

# -----------------------------
# Parse SQL output and determine role
# -----------------------------
my $role = "STANDALONE";

open(my $fh, '<', $qsql) or die "Cannot open $qsql: $!";
while (<$fh>) {
    chomp;

    # Skip noise
    next if /^\s*$/;
    next if /^(IBM|Server Version|Command Line|Copyright|\(c\))/i;
    next if /^ANS\d+/;
    next if /^ANR\d+/;
    next if /^LIBRARY_TYPE/i;
    next if /^-+/;

    s/^\s+|\s+$//g;

    # Columns are whitespace-separated
    my ($lib_type, $shared, $primary_mgr) = split(/\s+/, $_, 3);

    $lib_type    = uc($lib_type // "");
    $shared      = uc($shared // "");
    $primary_mgr = uc($primary_mgr // "");

    # ---- Role detection ----
    if ($shared eq "YES") {
        $role = "LIBRARY_MANAGER";
        last;
    }
    elsif ($lib_type eq "SHARED" && $primary_mgr ne "") {
        $role = "LIBRARY_CLIENT";
        last;
    }
}
close($fh);
# -----------------------------
# Server queries (same as tape.pl)
# -----------------------------
my %server_queries = (
    "server.txt"      => "q server",
    "libraries.txt"   => "q library format=detailed",
    "devclasses.txt"  => "q devclass f=d",
    "volumes.txt"     => "q volume f=d",
    "libvol.txt"      => "q libvol f=d",
    "qsan.txt"        => "q san",
    "showlibrary.txt" => "show library",
    "showdevclass.txt"=> "show devclass",
);

# LM-only queries
if ($role eq "LIBRARY_MANAGER") {
    $server_queries{"drives.txt"} = "q drive f=d";
    $server_queries{"paths.txt"}  = "q path f=d";
}

foreach my $file (keys %server_queries) {
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$server_queries{$file}"};
    my $rc = run_cmd($cmd, "$output_dir/$file");
    $collected_files{$file} = ($rc == 0 && -s "$output_dir/$file") ? "SUCCESS" : "FAILED";
}

# -----------------------------
# SQL queries (Library Manager only)
# -----------------------------
if ($role eq "LIBRARY_MANAGER") {
    my @sqls = (
        "SELECT b.source_name, a.library_name, a.drive_name, a.drive_serial, b.device FROM drives a, paths b WHERE a.drive_name=b.destination_name",
        "SELECT source_name,source_type,destination_name,destination_type,library_name,device FROM paths",
        "SELECT library_name,count(*) FROM drives WHERE online!='YES' GROUP BY library_name",
        "SELECT source_name,count(*) FROM paths WHERE online!='YES' GROUP BY source_name",
        "SELECT source_name,destination_name,online FROM paths WHERE online!='YES'",
        "SELECT library_name,drive_name,online FROM drives WHERE online!='YES'",
        "SELECT COUNT(*) FROM paths WHERE NOT online='Yes'",
        "SELECT COUNT(*) FROM drives WHERE NOT online='Yes'",
    );

    my $sql_dir = "$output_dir/sql";
    make_path($sql_dir);

    my $i = 1;
    for my $sql (@sqls) {
        my $file = sprintf("select_%02d.txt", $i++);
        my $rc = run_cmd(
            qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$sql"},
            "$sql_dir/$file"
        );
        $collected_files{"sql/$file"} = ($rc == 0 && -s "$sql_dir/$file") ? "SUCCESS" : "FAILED";
    }
}

# -----------------------------
# OS-specific collection (FULL SET)
# -----------------------------
my %os_cmds;

if ($os =~ /linux/i) {
    my $osrelease = `cat /etc/os-release 2>/dev/null`;
    my $is_ubuntu = ($osrelease =~ /ubuntu/i);
    my $is_rhel   = ($osrelease =~ /rhel|redhat|centos/i);
    my $is_suse   = ($osrelease =~ /sles|opensuse/i);

    %os_cmds = (
        "os-release.txt"     => "cat /etc/os-release",
        "messages.txt"       => (-e "/var/log/messages") ? "cat /var/log/messages" : "journalctl -xe",
        "sgvers.txt"         => "cat /proc/scsi/sg/version",
        "sgstrs.txt"         => "cat /proc/scsi/sg/device_strs",
        "sgdevs.txt"         => "cat /proc/scsi/sg/devices",
        "ibmtape.txt"        => "cat /proc/scsi/IBMtape",
        "lsltr.txt"          => "ls -ltr /dev/IBM*",
    );

    if ($is_rhel || $is_suse) {
        $os_cmds{"rpm_packages.txt"} = "rpm -qa | grep -i tivoli";
    } elsif ($is_ubuntu) {
        $os_cmds{"dpkg_packages.txt"} = "dpkg -l | grep -i tivoli";
    }

}
elsif ($os =~ /aix/i) {
    %os_cmds = (
        "lsdev_tape.txt" => "lsdev -Cc tape",
        "lsdev_smc.txt"  => "lsdev -Cc smc",
        "errpt.txt"      => "errpt -a",
        "oslevel.txt"    => "oslevel -s",
        "lscfg.txt"      => "lscfg -vl rmt* smc*",
    );
}
elsif ($os =~ /MSWin32/i) {
    %os_cmds = (
        "systeminfo.txt" => "systeminfo",
        "drivers.txt"    => "driverquery",
    );
}

foreach my $file (keys %os_cmds) {
    my $dest = "$output_dir/$file";
    my $rc = system("$os_cmds{$file} > \"$dest\" 2>>$error_log") >> 8;
    $collected_files{$file} = ($rc == 0 && -s $dest) ? "SUCCESS" : "FAILED";
}

# -----------------------------
# Summary of collected files
# -----------------------------
if ($verbose){
print  "=== Library Sharing MustGather Summary ===\n";
print  "Detected Role: $role\n\n";

foreach my $file (sort keys %collected_files) {
    printf  "%-35s : %s\n", $file, $collected_files{$file};
}
}
# -----------------------------
# Determine module-level status for framework
# -----------------------------
my ($success, $failed) = (0,0);
foreach my $status (values %collected_files) {
    $success++ if $status eq "SUCCESS";
    $failed++  if $status eq "FAILED";
}

my $module_status;
if ($success && !$failed) {
    $module_status = "Success";
} elsif ($failed && !$success) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

close($errfh);

# Exit code mapping for framework
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);
