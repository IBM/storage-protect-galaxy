#!/usr/bin/perl
use File::Copy qw(copy);
use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;

# ===============================================================
# Script Name : sql.pl
# Description : Collects diagnostics for IBM Storage Protect
#               Data Protection for Microsoft SQL Server
# ===============================================================

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments. Use --output-dir <dir>\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/sql";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup
# -----------------------------
my $base_path = env::get_ba_base_path();
my $os = env::_os();
my %results;
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print "\n=== Starting SQL Must-Gather Collection ===\n" if $verbose;

# -----------------------------
# Windows only
# -----------------------------
if ($os !~ /MSWin32/i) {
    print $errfh "Data Protection for SQL is supported only on Windows.\n";
    $results{"SQL_Module"} = "Not Applicable";
    close($errfh);
    exit(0);
}

# -----------------------------
# Installation directory
# -----------------------------
my $install_dir = env::get_sql_base_path();

unless (-d $install_dir) {
    print $errfh "TDPSQL install directory not found: $install_dir\n";
}
# ===============================================================
# 3. Data Protection for SQL version
# ===============================================================
my $tdpsqlc = "\"$install_dir/tdpsqlc\"";
utils::run_to_file(
    "$tdpsqlc query tdp",
    "$output_dir/tdpsql_version.txt"
);
$results{"tdpsql_version.txt"} = (-s "$output_dir/tdpsql_version.txt") ? "Success" : "Failed";

# ===============================================================
# 4. Registry dump
# ===============================================================
my $reg_out = "$output_dir/adsm_registry.txt";
system("reg query \"HKLM\\SOFTWARE\\IBM\\ADSM\\CurrentVersion\" /s > \"$reg_out\" 2>&1");
$results{"adsm_registry.txt"} = (-s $reg_out) ? "Success" : "Failed";

# ===============================================================
# 5. Log files
# ===============================================================
my @log_files = (
    "$install_dir/tdpsql.log",
    "$install_dir/dsierror.log",
    "$install_dir/tdpsql.cfg",
    "$install_dir/dsm.opt",
    "$install_dir/dsminstr.log",
);

foreach my $file (@log_files) {
    my ($name) = $file =~ /([^\/\\]+)$/;
    my $dest = "$output_dir/$name";


    if (-e $file) {
        if (copy($file, $dest)) {
            $results{$name} = (-s $dest) ? "Success" : "Failed";
        } else {
            $results{$name} = "Failed";
            print $errfh "Copy failed for $file: $!\n";
        }
    } else {
        $results{$name} = "Not Found";
        print $errfh "Missing file: $file\n";
    }
}

# ===============================================================
# 6. TDPSQLC queries
# ===============================================================
my %tdp_cmds = (
    "tdpsql_q_tsm.txt" => "$tdpsqlc query tsm",
    "tdpsql_q_tdp.txt" => "$tdpsqlc query tdp",
    "tdpsql_q_sql.txt" => "$tdpsqlc query sql",
);

foreach my $outfile (keys %tdp_cmds) {
    utils::run_to_file(
        $tdp_cmds{$outfile},
        "$output_dir/$outfile"
    );
    $results{$outfile} = (-s "$output_dir/$outfile") ? "Success" : "Failed";
}

# ===============================================================
# 7. VSS-related data (optional but recommended)
# ===============================================================

# 7.1 List VSS services registered with Spectrum Protect
my $dsmcutil_list = "$output_dir/dsmcutil_list.txt";
utils::run_to_file(
    "$base_path/dsmcutil list",
    $dsmcutil_list
);
$results{"dsmcutil_list.txt"} = (-s $dsmcutil_list) ? "Success" : "Failed";

# 7.2 Query each VSS service returned by dsmcutil list
if (-s $dsmcutil_list) {

    open my $fh, '<', $dsmcutil_list;
    while (my $line = <$fh>) {
        chomp $line;

        # Skip headers / empty lines
        next if $line =~ /^\s*$/;
        next if $line =~ /Service\s+Name/i;

        # Extract service name (first column)
        my ($service) = split(/\s+/, $line);
        next unless $service;

        my $outfile = "$output_dir/dsmcutil_query_$service.txt";

        utils::run_to_file(
            "$base_path/dsmcutil query /name:\"$service\"",
            $outfile
        );

        $results{"dsmcutil_query_$service.txt"} =
            (-s $outfile) ? "Success" : "Failed";
    }
    close $fh;

} else {
    print $errfh "dsmcutil list output is empty; skipping per-service queries\n";
}


# ===============================================================
# Summary
# ===============================================================
if ($verbose) {
    print "\n=== SQL Must-Gather Summary ===\n";
    foreach my $k (sort keys %results) {
        printf "  %-35s : %s\n", $k, $results{$k};
    }
    print "Collected data saved in: $output_dir\n";
    print "Check script.log for failures or missing data.\n";
}

close($errfh);

# ===============================================================
# Exit code
# ===============================================================
my $success = grep { $results{$_} eq "Success" } keys %results;
my $total   = scalar keys %results;

exit(($success == $total) ? 0 : 2);
