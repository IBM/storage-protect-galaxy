#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use Getopt::Long;

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose);

GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"     => \$verbose,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/snapdiff";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Detect OS
# -----------------------------
my $os = env::_os();

# -----------------------------
# Error log
# -----------------------------
my $error_log = "$output_dir/script.log";

open(my $errfh, '>', $error_log)
    or die "Cannot open $error_log: $!";

print $errfh "=== Starting SnapDiff Data Collection ===\n";
print $errfh "No additional local SnapDiff files to collect.\n";

# ===============================================================
# SnapDiff / NetApp Information
# ===============================================================

print "\n";
print "============================================================\n";
print "SnapDiff Additional Information Required\n";
print "============================================================\n";

print "\n";
print "1. Exact SnapDiff command used for running the backup\n";
print "------------------------------------------------------------\n";
print "Please provide the exact SnapDiff command used to run the\n";
print "backup or reproduce the reported issue.\n";

print "\n";
print "2. NetApp Cluster Information\n";
print "------------------------------------------------------------\n";
print "From the NetApp cluster, run the following commands and\n";
print "provide the output:\n\n";

print "security login show -user-or-group-name snapdiff_user\n";
print "security login role show -role snapdiff_role\n";

print "\n";
print "3. NetApp Data ONTAP Version/Level\n";
print "------------------------------------------------------------\n";
print "Please provide the NetApp Data ONTAP version/level of the\n";
print "affected cluster.\n";

print "\n";
print "4. NetApp Logs\n";
print "------------------------------------------------------------\n";
print "Please provide the following NetApp logs covering the\n";
print "complete timeframe of the reported issue:\n\n";

print "backup.log  - Backup process log\n";
print "ndmpd.log   - NDMP service log\n";
print "ndmpd.##### - NDMP rotated log, where applicable\n";

print "\n";
print "NetApp log locations:\n";
print "ONTAP 8.1 and newer releases: /etc/log/mlog/\n";
print "7-Mode: /etc/log/\n";

print "\n";
print "============================================================\n";
print "Please include the above information with the MustGather.\n";
print "============================================================\n\n";

# -----------------------------
# Close error log
# -----------------------------
close($errfh);

# -----------------------------
# Verbose summary
# -----------------------------
if ($verbose) {
    print "=== SnapDiff Module Summary ===\n";
    print "SnapDiff-specific information is displayed above.\n";
    print "Check script.log for details.\n";
}

exit 0;