#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";  # Include common modules
use env;
use Getopt::Long;

# -----------------------------
# Parse command-line arguments
# -----------------------------
# --output-dir | -o : Directory to store performance logs
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,  # Verbose mode
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/performance";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Get base path of BA client
# -----------------------------
my $base_path = env::get_ba_base_path();

# -----------------------------
# List of performance log files to collect
# -----------------------------
my $log_dir;
my $os = env::_os();
if ($ENV{'DSM_LOG'} && -d $ENV{'DSM_LOG'} && $ENV{'DSM_LOG'} ne '/') {
    $log_dir = $ENV{'DSM_LOG'};
}
elsif ($os =~ /darwin/i) {
    $log_dir = "/Library/Logs/tivoli/tsm/";
}
else {
    $log_dir = $base_path;
}

my @log_files = (
    "dsminstr.log"
);

# -----------------------------
# Open error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Collect performance log files
# -----------------------------
my %collected_files;

foreach my $file (@log_files) {
    my $filepath = $file =~ /^\// ? $file : "$log_dir/$file";  # Absolute path
    my ($filename) = $filepath =~ /([^\/\\]+)$/;               # Extract file name
    my $dest_file = "$output_dir/$filename";

    if (-e $filepath) {
        if (open(my $fh, '<', $filepath)) {
            open(my $outfh, '>', $dest_file) or do {
                print $errfh "Error: Could not write $dest_file: $!\n";
                $collected_files{$filename} = "Failed";
                next;
            };
            while (<$fh>) { print $outfh $_; }
            close($fh);
            close($outfh);
            $collected_files{$filename} = "Success";
        } else {
            print $errfh "Error: Could not open $filepath: $!\n";
            $collected_files{$filename} = "Failed";
        }
    } else {
        print $errfh "Warning: $filepath not found\n";
        $collected_files{$filename} = "NOT FOUND";
    }
}

close($errfh);

# -----------------------------
# Summary of collected performance files
# -----------------------------
if ($verbose) {
print "\n=== Performance Module Summary ===\n";
foreach my $file (sort keys %collected_files) {
    printf "  %-15s : %s\n", $file, $collected_files{$file};
}
print "Collected performance logs saved in: $output_dir\n";
print "Check script.log for any failures.\n";
}

# -----------------------------
# Determine module-level status for framework
# -----------------------------
my $Success_count = 0;
my $fail_count = 0;
my $total = scalar keys %collected_files;

foreach my $status (values %collected_files) {
    $Success_count++ if $status eq "Success";
    $fail_count++    if $status eq "Failed";
}

my $module_status;
if ($Success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

# Exit code mapping for framework (optional: 0=Success, 1=failure, 2=Partial)
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);

