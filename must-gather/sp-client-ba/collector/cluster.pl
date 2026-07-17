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
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $optfile);

GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$optfile,
) or die "Invalid arguments.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/cluster";
make_path($output_dir) unless -d $output_dir;

my $os = env::_os();

# Cluster collection only valid on Windows
exit(0) unless ($os =~ /MSWin32/i);

# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

my %collected_files;

# -----------------------------
# Locate dsmc.exe
# -----------------------------
my $base_path = env::get_ba_base_path();

my $opt_file;
if ($optfile) {
    $opt_file = $optfile;
} else {
    $opt_file = "$base_path\\dsm.opt";
}

my $dsmc = `where dsmc.exe 2>nul`;
chomp($dsmc);

if (!$dsmc || !-e $dsmc) {
    $dsmc = "$base_path\\dsmc.exe";
}

# -----------------------------
# Collect SHOW CLUSTER
# -----------------------------
if ($dsmc && -e $dsmc) {

    my $cluster_out = "$output_dir/show_cluster.txt";

    my $cmd =
        "\"$dsmc\" show cluster -optfile=\"$opt_file\" > \"$cluster_out\" 2>&1";

    my $rc = system($cmd);
    $rc >>= 8;

    if ($rc == 0 && -s $cluster_out) {
        $collected_files{"show_cluster.txt"} = "Success";
    } else {
        $collected_files{"show_cluster.txt"} = "Failed";
        print $errfh "Failed to collect SHOW CLUSTER output\n";
    }
}

# -----------------------------
# Collect Cluster Groups
# -----------------------------
my $cluster_groups = "$output_dir/cluster_groups.txt";

system(
    "cmd /c cluster group > \"$cluster_groups\" 2>&1"
);

$collected_files{"cluster_groups.txt"} =
    (-s $cluster_groups) ? "Success" : "Failed";

# -----------------------------
# Collect Cluster Resources
# -----------------------------
my $cluster_resources = "$output_dir/cluster_resources.txt";

system(
    "cmd /c cluster resource > \"$cluster_resources\" 2>&1"
);

$collected_files{"cluster_resources.txt"} =
    (-s $cluster_resources) ? "Success" : "Failed";

# -----------------------------
# Collect SAN / SCSI Disk Info
# -----------------------------
my $disk_info = "$output_dir/disk_info.txt";

system(
    "cmd /c wmic diskdrive get Model,InterfaceType,SerialNumber,Size > \"$disk_info\" 2>&1"
);

$collected_files{"disk_info.txt"} =
    (-s $disk_info) ? "Success" : "Failed";

# -----------------------------
# Collect Diskpart Output
# -----------------------------
my $diskpart_script = "$output_dir/diskpart.txt";

open(my $dp, '>', $diskpart_script);
print $dp "list disk\n";
print $dp "list volume\n";
close($dp);

my $diskpart_out = "$output_dir/diskpart_output.txt";

system(
    "cmd /c diskpart /s \"$diskpart_script\" > \"$diskpart_out\" 2>&1"
);

$collected_files{"diskpart_output.txt"} =
    (-s $diskpart_out) ? "Success" : "Failed";

# -----------------------------
# Copy Cluster Logs
# -----------------------------
my $cluster_log_dir = "C:\\Windows\\Cluster";

if (-d $cluster_log_dir) {

    opendir(my $dh, $cluster_log_dir);

    while (my $file = readdir($dh)) {

        next if $file =~ /^\.\.?$/;

        my $src = "$cluster_log_dir\\$file";
        my $dst = "$output_dir\\$file";

        if (-f $src) {
            copy($src, $dst);
        }
    }

    closedir($dh);

    $collected_files{"cluster_logs"} = "Success";
}
else {
    $collected_files{"cluster_logs"} = "NOT FOUND";
}

# -----------------------------
# Export Event Logs
# -----------------------------
my %event_logs = (
    "Application" => "application.evtx",
    "System"      => "system.evtx",
    "Microsoft-Windows-FailoverClustering/Operational"
                  => "cluster.evtx",
);

foreach my $log (keys %event_logs) {

    my $outfile = "$output_dir\\$event_logs{$log}";

    my $cmd =
      "wevtutil epl \"$log\" \"$outfile\"";

    system($cmd);

    $collected_files{$event_logs{$log}} =
        (-s $outfile) ? "Success" : "Failed";
}

close($errfh);

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {

    print "\n=== Cluster Module Summary ===\n";

    foreach my $file (sort keys %collected_files) {
        printf "  %-25s : %s\n",
            $file,
            $collected_files{$file};
    }

    print "Collected files saved in: $output_dir\n";
}

# -----------------------------
# Determine module status
# -----------------------------
my $success_count = 0;
my $fail_count    = 0;
my $total         = scalar keys %collected_files;

foreach my $status (values %collected_files) {
    $success_count++ if $status eq "Success";
    $fail_count++    if $status eq "Failed";
}

my $module_status;

if ($success_count == $total) {
    $module_status = "Success";
}
elsif ($fail_count == $total) {
    $module_status = "Failed";
}
else {
    $module_status = "Partial";
}

exit($module_status eq "Success" ? 0 :
     $module_status eq "Partial" ? 2 : 1);