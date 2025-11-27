#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Basename;
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
    "verbose|v"      => \$verbose,
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/logs";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Detect base path & OS
# -----------------------------
my $base_path = env::get_ba_base_path();
my $os = env::_os();

# -----------------------------
# Determine default log directory (DSM_LOG or OS defaults)
# -----------------------------
my $log_dir;

if ($ENV{'DSM_LOG'} && -d $ENV{'DSM_LOG'} && $ENV{'DSM_LOG'} ne '/') {
    $log_dir = $ENV{'DSM_LOG'};
}
elsif ($os =~ /darwin/i) {
    $log_dir = "/Library/Logs/tivoli/tsm/";
}
else {
    $log_dir = $base_path;
}

# -----------------------------
# Parse config files for overrides (ERRORLOGNAME, SCHEDLOGNAME)
# -----------------------------
my ($errorlog_path, $schedlog_path);
foreach my $conf ("$base_path/dsm.opt", "$base_path/dsm.sys") {
    next unless -f $conf;
    open(my $fh, '<', $conf) or next;
    while (<$fh>) {
        next if /^\s*$/ || /^[#;]/;
        if (/^\s*ERRORLOGNAME\s+(\S+)/i) {
            my $full = $1;
            my $dir = dirname($full);
            $errorlog_path = $dir if -d $dir;
            print "Found ERRORLOGNAME override: $errorlog_path\n" if $verbose;
        }
        if (/^\s*SCHEDLOGNAME\s+(\S+)/i) {
            my $full = $1;
            my $dir = dirname($full);
            $schedlog_path = $dir if -d $dir;
            print "Found SCHEDLOGNAME override: $schedlog_path\n" if $verbose;
        }
    }
    close($fh);
}

print "Base log directory: $log_dir\n" if $verbose;

# -----------------------------
# Log files to collect
# -----------------------------
my %log_map = (
    "dsmerror.log" => $errorlog_path || $log_dir,
    "dsmsched.log" => $schedlog_path || $log_dir,
    "dsmj.log"     => $log_dir,
    "dsmwebcl.log" => $log_dir,
);

# -----------------------------
# Open error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Collect log files
# -----------------------------
my %collected_files;

foreach my $file (sort keys %log_map) {
    my $src_dir = $log_map{$file};
    my $filepath = "$src_dir/$file";
    my $dest_file = "$output_dir/$file";

    if (-e $filepath) {
        if (open(my $fh, '<', $filepath)) {
            open(my $outfh, '>', $dest_file) or do {
                print $errfh "Error: Cannot write $dest_file: $!\n";
                $collected_files{$file} = "Failed";
                next;
            };
            while (<$fh>) { print $outfh $_; }
            close($fh);
            close($outfh);
            $collected_files{$file} = "Success";
        } else {
            print $errfh "Error: Cannot open $filepath: $!\n";
            $collected_files{$file} = "Failed";
        }
    } else {
        print $errfh "Warning: $filepath not found\n";
        $collected_files{$file} = "NOT FOUND";
    }

}

close($errfh);

# -----------------------------
# Summary (verbose)
# -----------------------------
if ($verbose) {
    print "\n=== Logs Module Summary ===\n";
    foreach my $file (sort keys %collected_files) {
        printf "  %-15s : %s\n", $file, $collected_files{$file};
    }
    print "Collected log files saved in: $output_dir\n";
    print "Check script.log for details.\n";
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
my $exit_code = $module_status eq "Success" ? 0 :
                $module_status eq "Partial" ? 2 : 1;

exit($exit_code);

