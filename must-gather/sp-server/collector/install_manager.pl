#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use FindBin;
use File::Path qw(make_path);
use File::Copy qw(copy);
use Cwd qw(abs_path);
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;

# -----------------------------
# Parameters / CLI options
# -----------------------------
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/server_install_upgrade";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Detect OS
# -----------------------------
my $os = $^O;
print $errfh "Detected OS: $os\n" if $verbose;

# -----------------------------
# Locate Installation Manager tools
# -----------------------------
my $imutils;

if ($os =~ /aix|linux/i) {
    $imutils = "/opt/IBM/InstallationManager/eclipse/tools/imutilsc";
} elsif ($os =~ /MSWin32/) {
    $imutils = "c:\\Program Files\\IBM\\Installation Manager\\eclipse\\tools\\imutilsc.exe";
}

my $zipfile = "$output_dir/InstallManager_Logs.zip";

unless ($imutils && -x $imutils) {
    print $errfh "Installation Manager tool not found at expected path: $imutils\n";
} else {
    # -----------------------------
    # Export Installation Manager logs
    # -----------------------------
    my $cmd = qq{"$imutils" exportInstallData "$zipfile"};

    print $errfh "Running: $cmd\n" if $verbose;
    system($cmd);
}

# -----------------------------
# Collect general system info
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;
    my $full_cmd = qq{$cmd > "$outfile" 2>&1};
    print $errfh "Running: $full_cmd\n" if $verbose;
    system($full_cmd);
}

# -----------------------------
# Installation Manager version
# -----------------------------
if ($imutils && -x $imutils) {
    run_cmd(qq{"$imutils" version}, "$output_dir/im_version.txt");
}


# -----------------------------
# Module-level status
# -----------------------------
my %collected_files;
$collected_files{"InstallManager_Logs.zip"} = (-s $zipfile) ? "Success" : "Failed";
$collected_files{"im_version.txt"}          = (-s "$output_dir/im_version.txt") ? "Success" : "Failed";
my $Success_count = 0;
my $fail_count    = 0;
my $total         = scalar keys %collected_files;

foreach my $status (values %collected_files) {
    $Success_count++ if $status eq "Success";
    $fail_count++    if $status eq "Failed";
}

my $module_status;
if ($total == 0) {
    $module_status = "Failed";   # nothing collected
} elsif ($Success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {
    print "\n=== Server Install / Upgrade Module Summary ===\n";
    print "Installation Manager logs : ",
          (-s "$output_dir/InstallManager_Logs.zip" ? "Success\n" : "NOT FOUND\n");
    print "Output location           : $output_dir\n";
    print "Check script.log for details\n";
}

exit(
    $module_status eq "Success" ? 0 :
    $module_status eq "Partial" ? 2 : 1
);