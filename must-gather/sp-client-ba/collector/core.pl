#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use FindBin;
use File::Find;
use File::Path qw(make_path);
use lib "$FindBin::Bin/../../common/modules"; # include common modules
use env;
use utils;

# ===============================================================
# Script Name : core.pl
# Description : Collects crash/core dump files for diagnostic purposes.
# ===============================================================

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments. Run with --help for usage.\n";
die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/core";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup
# -----------------------------
my $os = env::_os();
my $search_root;
my @patterns;
my %collected_files;
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print "\n=== Starting Core Dump Collection ===\n" if $verbose;
print $errfh "Detected OS: $os\n";

# -----------------------------
# Define search patterns per OS
# -----------------------------
if ($os =~ /MSWin32/i) {
    # Windows typical dump locations and file patterns
    $search_root = "C:\\";
    @patterns = ( qr/\.dmp$/i, qr/\.crash$/i );
} else {
    # Linux/Unix: core files, .core, etc.
    $search_root = "/";
    @patterns = ( qr/^core(\.\d+)?$/, qr/\.core$/i, qr/\.dmp$/i );
}

# -----------------------------
# Search for dump files
# -----------------------------
my @found_files;
eval {
    find(
        {
            wanted => sub {
                my $file = $_;
                foreach my $pattern (@patterns) {
                    if ($file =~ $pattern) {
                        push @found_files, $File::Find::name;
                        last;
                    }
                }
            },
            no_chdir => 1
        },
        $search_root
    );
};
if ($@) {
    print $errfh "Error during file search: $@\n";
}

# -----------------------------
# Copy found dumps to output directory
# -----------------------------
if (@found_files) {
    foreach my $src (@found_files) {
        my ($filename) = $src =~ /([^\/\\]+)$/;
        my $dest = "$output_dir/$filename";

        # Skip massive system dumps (>1 GB)
        my $size = -s $src;
        if ($size && $size > 1_000_000_000) {
            print $errfh "Skipping large dump ($size bytes): $src\n";
            $collected_files{$filename} = "Skipped (Too Large)";
            next;
        }

        if (utils::copy_safe($src, $dest)) {
            print "Collected: $filename\n" if $verbose;
            $collected_files{$filename} = "Success";
        } else {
            print $errfh "Failed to copy $src: $!\n";
            $collected_files{$filename} = "Failed";
        }
    }
} else {
    print $errfh "No core/crash dump files found matching patterns.\n";
}

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {
    print "\n=== Core Module Summary ===\n";
    if (%collected_files) {
        foreach my $file (sort keys %collected_files) {
            printf "  %-40s : %s\n", $file, $collected_files{$file};
        }
    } else {
        print "  No core or crash dump files found.\n";
    }
    print "Collected data saved in: $output_dir\n";
    print "Check script.log for any skipped or failed files.\n";
}

# -----------------------------
# Determine exit code for framework
# -----------------------------
my $success_count = grep { $collected_files{$_} eq "Success" } keys %collected_files;
my $total = scalar keys %collected_files;
my $exit_code;

if ($total == 0) {
    $exit_code = 0; # No dumps is not a failure
} elsif ($success_count == $total) {
    $exit_code = 0;
} elsif ($success_count > 0) {
    $exit_code = 2;
} else {
    $exit_code = 1;
}

close($errfh);
exit($exit_code);
