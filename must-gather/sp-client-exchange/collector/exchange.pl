#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy;
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use Getopt::Long;

# ===============================================================
# Script Name : exchange.pl
# Description : Collects Exchange-specific diagnostic data for
#               IBM Storage Protect for Mail - Data Protection for Exchange
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
$output_dir = "$output_dir/exchange";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Get base path using env.pm
# -----------------------------
my $exchange_path = env::get_exchange_base_path();
my $os = env::_os();

# Exchange is Windows-only
unless ($os =~ /MSWin32/i) {
    die "ERROR: Data Protection for Exchange is only supported on Windows.\n";
}

# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print $errfh "=== Starting Exchange-Specific Data Collection ===\n";


# -----------------------------
# Collected items tracking
# -----------------------------
my %collected_items;

# -----------------------------
# Helper Functions
# -----------------------------

# Helper function to collect text files
sub collect_text_file {
    my ($source_path, $dest_filename, $item_name) = @_;
    
    if (-e $source_path) {
        my $dest = "$output_dir/$dest_filename";
        if (open(my $in, '<', $source_path) && open(my $out, '>', $dest)) {
            while (<$in>) { print $out $_; }
            close($in);
            close($out);
            $collected_items{$item_name} = "Success";
            print $errfh "Collected $item_name from: $source_path\n";
        } else {
            print $errfh "Error: Could not copy $item_name: $!\n";
            $collected_items{$item_name} = "Failed";
        }
    } else {
        print $errfh "Warning: $item_name not found at: $source_path\n";
        $collected_items{$item_name} = "NOT FOUND";
    }
}

# Helper function to run commands and collect output
sub run_command_to_file {
    my ($cmd, $output_file, $item_name) = @_;
    
    print $errfh "Executing: $cmd\n" if $verbose;
    my $status = system("$cmd > \"$output_file\" 2>&1");
    $status >>= 8;
    
    if ($status == 0 && -s $output_file) {
        $collected_items{$item_name} = "Success";
        print $errfh "Collected $item_name\n";
    } else {
        $collected_items{$item_name} = "Failed";
        print $errfh "Warning: $item_name collection failed (exit code: $status)\n";
    }
}

# -----------------------------
# Collect Configuration Files
# -----------------------------


if ($exchange_path) {
    # TDP Exchange config file
    collect_text_file("$exchange_path\\tdpexc.cfg", "tdpexc.cfg", "tdpexc.cfg");
    
    # DSM options file
    collect_text_file("$exchange_path\\dsm.opt", "dsm.opt", "dsm.opt");
}

# -----------------------------
# Collect Log Files
# -----------------------------


if ($exchange_path) {
    # TDP Exchange log
    collect_text_file("$exchange_path\\tdpexc.log", "tdpexc.log", "tdpexc.log");
    
    # DSM error logs
    collect_text_file("$exchange_path\\dsmerror.log", "dsmerror.log", "dsmerror.log");
    collect_text_file("$exchange_path\\dsierror.log", "dsierror.log", "dsierror.log");
    collect_text_file("$exchange_path\\dsmsched.log", "dsmsched.log", "dsmsched.log");
}

# -----------------------------
# Collect TDP Exchange Queries
# -----------------------------

my $tdpexcc = "\"$exchange_path/tdpexcc\"";

# TDPEXCC QUERY TSM
run_command_to_file("$tdpexcc query tsm", "$output_dir/query_tsm.txt", "query_tsm");

# TDPEXCC QUERY EXCHANGE
run_command_to_file("$tdpexcc query exchange", "$output_dir/query_exchange.txt", "query_exchange");

# TDPEXCC QUERY TDP
run_command_to_file("$tdpexcc query tdp", "$output_dir/query_tdp.txt", "query_tdp");



# -----------------------------
# Collect Registry Information
# -----------------------------


run_command_to_file(
    "reg query HKLM\\SOFTWARE\\IBM\\ADSM\\CurrentVersion /s",
    "$output_dir/adsm_registry.txt",
    "adsm_registry"
);



# -----------------------------
# Summary
# -----------------------------
close($errfh);

if ($verbose) {
    print "\n=== Exchange Module Summary ===\n";
    foreach my $item (sort keys %collected_items) {
        printf "  %-40s : %s\n", $item, $collected_items{$item};
    }
    print "\nCollected data saved in: $output_dir\n";
    print "Check script.log for detailed information.\n";
}

# -----------------------------
# Determine exit code
# -----------------------------
my $success_count = grep { $collected_items{$_} eq "Success" } keys %collected_items;
my $total = scalar keys %collected_items;
my $exit_code;

if ($success_count == 0) {
    $exit_code = 1;  # Complete failure
} elsif ($success_count == $total) {
    $exit_code = 0;  # Complete success
} else {
    $exit_code = 2;  # Partial success
}

exit($exit_code);


