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
# Script Name : domino.pl
# Description : Collects Domino-specific diagnostic data for
#               IBM Storage Protect for Mail - Data Protection for Domino
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
$output_dir = "$output_dir/domino";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Get base paths using env.pm
# -----------------------------
my $domino_base = env::get_domino_base_path();
my $api_base = env::get_domino_api_path($domino_base);
my $os = env::_os();

# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print $errfh "=== Starting Domino-Specific Data Collection ===\n";
print $errfh "Detected OS: $os\n";
print $errfh "Domino base path: " . ($domino_base || "Not found") . "\n";
print $errfh "API base path: " . ($api_base || "Not found") . "\n";
print $errfh "Output directory: $output_dir\n\n";

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

# Helper function to run system commands and collect output
sub run_system_command {
    my ($cmd, $output_file, $item_name) = @_;
    
    print $errfh "Executing: $cmd\n" if $verbose;
    my $status = system($cmd);
    $status >>= 8;
    
    if ($status == 0 && -s $output_file) {
        $collected_items{$item_name} = "Success";
        print $errfh "Collected $item_name\n" if $verbose;
    } elsif (-s $output_file) {
        $collected_items{$item_name} = "Success";
        print $errfh "Collected $item_name (command returned non-zero but file exists)\n" if $verbose;
    } else {
        print $errfh "Warning: $item_name command failed or returned no data\n";
        $collected_items{$item_name} = "NOT FOUND";
    }
}


# -----------------------------
# Detect Domino user (Unix/Linux/AIX)
# -----------------------------
my $domino_user;
my $domdsmc_dir;

if ($os !~ /MSWin32/i && $domino_base) {
    $domino_user = $ENV{USER} || $ENV{LOGNAME} || `whoami 2>/dev/null`;
    chomp($domino_user) if $domino_user;
    
    if ($domino_user) {
        $domdsmc_dir = "$domino_base/domdsmc_$domino_user";
        if (!-d $domdsmc_dir) {
            # Try to find any domdsmc_* directory
            my @possible_dirs = glob("$domino_base/domdsmc_*");
            $domdsmc_dir = $possible_dirs[0] if @possible_dirs;
        }
        print $errfh "Domino user: $domino_user\n";
        print $errfh "Domdsmc directory: " . ($domdsmc_dir || "Not found") . "\n";
    }
}

# -----------------------------
# Windows-specific collection
# -----------------------------
if ($os =~ /MSWin32/i) {
   
    
    # domdsmc query commands
    run_command_to_file("domdsmc query adsm", "$output_dir/query_adsm.txt", "query_adsm");
    run_command_to_file("domdsmc query domino", "$output_dir/query_domino.txt", "query_domino");
    run_command_to_file("domdsmc query preferences", "$output_dir/query_preferences.txt", "query_preferences");
    run_command_to_file("set", "$output_dir/environment.txt", "environment");
 
    # Registry information
    run_command_to_file("reg query HKLM\\software\\ibm\\adsm\\currentversion /s", "$output_dir/registry.txt", "registry");
    
    # Configuration files
    if ($domino_base) {
        collect_text_file("$domino_base\\dsm.opt", "dsm.opt", "dsm.opt");
        collect_text_file("$domino_base\\domdsm.cfg", "domdsm.cfg", "domdsm.cfg");
    }
    
    # Log files
    my @log_files = qw(dsmerror.log dsmsched.log domdsm.log dsierror.log);
    foreach my $log (@log_files) {
        collect_text_file("$domino_base\\$log", $log, $log) if $domino_base;
    }
}
# -----------------------------
# Unix/Linux/AIX collection
# -----------------------------
else {
    # Configuration files
    if ($domdsmc_dir && -e "$domdsmc_dir/domdsm.cfg") {
        collect_text_file("$domdsmc_dir/domdsm.cfg", "domdsm.cfg", "domdsm.cfg");
    }
    if ($api_base) {
        if (-e "$api_base/dsm.opt") {
           
            collect_text_file("$api_base/dsm.opt", "dsm.opt", "dsm.opt");
        }
        
        if (-e "$api_base/dsm.sys") {
            collect_text_file("$api_base/dsm.sys", "dsm.sys", "dsm.sys");
        }
    }

    # Log files
    my @log_files = qw(dsmerror.log dsmsched.log domdsm.log dsierror.log);
    foreach my $log (@log_files) {
        collect_text_file("$domdsmc_dir/$log", $log, $log) if $domino_base;
    }
    
    # Installed packages
   print $errfh "\n=== Installed Packages ===\n" if $verbose;

if ($os =~ /aix/i) {

    print $errfh "Collecting AIX installed packages...\n" if $verbose;
    run_system_command("lslpp -L tivoli.* >\"$output_dir/lslpp_tivoli.txt\" 2>&1",
                       "$output_dir/lslpp_tivoli.txt", "lslpp_tivoli");

} elsif ($os =~ /solaris/i) {

    print $errfh "Collecting Solaris installed packages...\n" if $verbose;
    run_system_command("pkginfo -l TDPdomino >\"$output_dir/pkginfo_TDPdomino.txt\" 2>&1",
                       "$output_dir/pkginfo_TDPdomino.txt", "pkginfo_TDPdomino");

    run_system_command("pkginfo -l TIVsmCapi >\"$output_dir/pkginfo_TIVsmCapi.txt\" 2>&1",
                       "$output_dir/pkginfo_TIVsmCapi.txt", "pkginfo_TIVsmCapi");

} elsif ($os =~ /linux/i) {

    print $errfh "Collecting Linux installed packages...\n" if $verbose;
    run_system_command("rpm -qai TIV* >\"$output_dir/rpm_TIV.txt\" 2>&1",
                       "$output_dir/rpm_TIV.txt", "rpm_TIV");

    run_system_command("rpm -qai TDP* >\"$output_dir/rpm_TDP.txt\" 2>&1",
                       "$output_dir/rpm_TDP.txt", "rpm_TDP");

} else {

    print $errfh "Warning: Platform '$os' not specifically supported for installed package collection\n" if $verbose;
    $collected_items{"installed_packages"} = "UNSUPPORTED";
}
}


# -----------------------------
# Summary
# -----------------------------
close($errfh);

if ($verbose) {
    print "\n=== Domino Module Summary ===\n";
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

