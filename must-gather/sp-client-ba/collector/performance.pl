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
    "verbose|v"      => \$verbose,
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/performance";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Detect base path & OS
# -----------------------------
my $base_path = env::get_ba_base_path();
my $os        = env::_os();

# -----------------------------
# Determine default log directory
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
# Parse INSTRLOGNAME override
# -----------------------------
my $instrlog_path;
my $opt_file = "$base_path/dsm.opt";
my $dsm_sys  = "$base_path/dsm.sys";

if ($os =~ /MSWin32/i) {

    if (-e $opt_file && open(my $fh, '<', $opt_file)) {

        while (<$fh>) {

            next if /^\s*$/ || /^[#;]/;

            if (/^\s*INSTRLOGNAME\s+(.+)/i) {

                my $full = $1;
                $full =~ s/^\s+|\s+$//g;
                $full =~ s/^["']|["']$//g;

                my ($dir) = $full =~ /(.*)[\/\\]/;

                if ($dir && -d $dir) {
                    $instrlog_path = $dir;
                }

                print "Found INSTRLOGNAME override: $instrlog_path\n" if $verbose;

                last;
            }
        }

        close $fh;
    }

} else {

    # Determine active SERVERNAME from dsm.opt
    my $active_server;

    if (-e $opt_file && open(my $fh, '<', $opt_file)) {

        while (<$fh>) {

            next if /^\s*$/ || /^[#;]/;

            if (/^\s*SERVERNAME\s+(\S+)/i) {
                $active_server = $1;
                last;
            }
        }

        close $fh;
    }

    # Read INSTRLOGNAME from active stanza
    if (-e $dsm_sys && open(my $fh, '<', $dsm_sys)) {

        my $in_target_stanza = 0;

        while (<$fh>) {

            next if /^\s*$/ || /^[#;]/;

            if (/^\s*SERVERNAME\s+(\S+)/i) {

                my $current = $1;

                if ($active_server) {
                    $in_target_stanza = ($current eq $active_server) ? 1 : 0;
                } else {
                    $in_target_stanza = 1 if !$in_target_stanza;
                }

                next;
            }

            if ($in_target_stanza && /^\s*INSTRLOGNAME\s+(.+)/i) {

                my $full = $1;
                $full =~ s/^\s+|\s+$//g;
                $full =~ s/^["']|["']$//g;

                my ($dir) = $full =~ /(.*)[\/\\]/;

                if ($dir && -d $dir) {
                    $instrlog_path = $dir;
                }

                print "Found INSTRLOGNAME override: $instrlog_path\n" if $verbose;

                last;
            }
        }

        close $fh;
    }
}

# Override log directory if instrlog found
$log_dir = $instrlog_path if $instrlog_path;

# -----------------------------
# Performance logs
# -----------------------------
my @log_files = (
    "dsminstr.log"
);

# -----------------------------
# Open error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Collect performance logs
# -----------------------------
my %collected_files;

foreach my $file (@log_files) {

    my $filepath = "$log_dir/$file";

    my $dest_file = "$output_dir/$file";

    if (-e $filepath) {

        if (open(my $fh, '<', $filepath)) {

            open(my $outfh, '>', $dest_file) or do {

                print $errfh "Error: Could not write $dest_file: $!\n";
                $collected_files{$file} = "Failed";
                next;
            };

            while (<$fh>) {
                print $outfh $_;
            }

            close $fh;
            close $outfh;

            $collected_files{$file} = "Success";

        } else {

            print $errfh "Error: Could not open $filepath: $!\n";
            $collected_files{$file} = "Failed";
        }

    } else {

        print $errfh "Warning: $filepath not found\n";
        $collected_files{$file} = "NOT FOUND";
    }
}

close($errfh);

# -----------------------------
# Summary
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
# Module status
# -----------------------------
my $Success_count = 0;
my $fail_count    = 0;
my $total         = scalar keys %collected_files;

foreach my $status (values %collected_files) {

    $Success_count++ if $status eq "Success";
    $fail_count++    if $status eq "Failed";
}

my $module_status;

if ($Success_count == $total) {
    $module_status = "Success";
}
elsif ($fail_count == $total) {
    $module_status = "Failed";
}
else {
    $module_status = "Partial";
}

exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);