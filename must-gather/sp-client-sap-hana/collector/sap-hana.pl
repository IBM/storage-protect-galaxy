#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Find;
use File::Copy;
use File::Basename;
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;
use Getopt::Long;

# ===============================================================
# Script Name : sap-hana.pl
# Description : Collects SAP HANA specific diagnostic data
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
$output_dir = "$output_dir/sap-hana";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup
# -----------------------------
my $os = env::_os();
my %collected_files;
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print "\n=== Starting SAP HANA-Specific Data Collection ===\n" if $verbose;
print $errfh "Detected OS: $os\n";
print $errfh "Note: OS info and TSM client config collected by system/config modules\n";

# -----------------------------
# Collect TSM API Configuration Files (SAP HANA specific paths)
# -----------------------------
print "Collecting TSM API configuration files (SAP HANA API paths)...\n" if $verbose;

my @api_config_paths = (
    "/opt/tivoli/tsm/client/api/bin64/dsm.sys",
    "/opt/tivoli/tsm/client/api/bin64/dsm.opt",
    "/opt/tivoli/tsm/client/api/bin/dsm.sys",
    "/opt/tivoli/tsm/client/api/bin/dsm.opt",
);

foreach my $config_file (@api_config_paths) {
    my $filename = "api_" . basename($config_file);  # Prefix to distinguish from BA client config
    my $dest = "$output_dir/$filename";
    
    if (-e $config_file) {
        if (copy($config_file, $dest)) {
            print $errfh "Collected: $config_file\n";
            $collected_files{$filename} = "Success";
        } else {
            print $errfh "Failed to copy $config_file: $!\n";
            $collected_files{$filename} = "Failed";
        }
    } else {
        print $errfh "Not found: $config_file\n";
    }
}

# -----------------------------
# Detect SAP HANA SID
# -----------------------------
print "Detecting SAP HANA SID...\n" if $verbose;
my @sids;

# Method 1: Check /usr/sap directory
if (-d "/usr/sap") {
    opendir(my $dh, "/usr/sap") or warn "Cannot open /usr/sap: $!";
    while (my $entry = readdir($dh)) {
        next if $entry =~ /^\.\.?$/;
        next if $entry eq "hostctrl";
        if (-d "/usr/sap/$entry" && $entry =~ /^[A-Z0-9]{3}$/) {
            push @sids, $entry;
        }
    }
    closedir($dh);
}

# Method 2: Check running HANA processes
if (!@sids) {
    my $ps_output = `ps -ef | grep -i hdb | grep -v grep 2>/dev/null`;
    if ($ps_output =~ m{/usr/sap/([A-Z0-9]{3})/}) {
        push @sids, $1 unless grep { $_ eq $1 } @sids;
    }
}

if (@sids) {
    print $errfh "Detected SAP HANA SID(s): " . join(", ", @sids) . "\n";
    print "Found SAP HANA SID(s): " . join(", ", @sids) . "\n" if $verbose;
} else {
    print $errfh "Warning: No SAP HANA SID detected. Using default paths.\n";
    print "Warning: No SAP HANA SID detected\n" if $verbose;
    @sids = ("XXX");  # Placeholder for manual collection
}

# -----------------------------
# Collect SAP HANA Version Information
# -----------------------------
print "Collecting SAP HANA version information...\n" if $verbose;
my $version_file = "$output_dir/hana_version.txt";

foreach my $sid (@sids) {
    next if $sid eq "XXX";
    
    # Try to get version from HDB command
    my $sid_lc = lc($sid);
    my $hdb_cmd = "su - ${sid_lc}adm -c 'HDB version' 2>/dev/null";
    my $version_output = `$hdb_cmd`;
    
    if ($version_output) {
        open(my $vfh, '>>', $version_file) or warn "Cannot write to $version_file: $!";
        print $vfh "=== SAP HANA Version for SID: $sid ===\n";
        print $vfh $version_output;
        print $vfh "\n";
        close($vfh);
    }
}

$collected_files{"hana_version.txt"} = (-s $version_file) ? "Success" : "Not Available";

# -----------------------------
# Collect SAP HANA Profile Files (global.ini)
# -----------------------------
print "Collecting SAP HANA profile files...\n" if $verbose;

foreach my $sid (@sids) {
    next if $sid eq "XXX";
    
    my @profile_paths = (
        "/usr/sap/$sid/SYS/global/hdb/custom/config/global.ini",
        "/hana/shared/$sid/global/hdb/custom/config/global.ini",
    );
    
    foreach my $profile (@profile_paths) {
        if (-e $profile) {
            my $dest = "$output_dir/global.ini_${sid}";
            if (copy($profile, $dest)) {
                print $errfh "Collected: $profile\n";
                $collected_files{"global.ini_${sid}"} = "Success";
            } else {
                print $errfh "Failed to copy $profile: $!\n";
                $collected_files{"global.ini_${sid}"} = "Failed";
            }
            last;  # Found one, move to next SID
        }
    }
}

# -----------------------------
# Collect Data Protection SAP HANA Profile (init{SID}.utl)
# -----------------------------
print "Collecting Data Protection profile files...\n" if $verbose;

foreach my $sid (@sids) {
    next if $sid eq "XXX";
    
    my @dp_profile_paths = (
        "/usr/sap/$sid/SYS/global/hdb/opt/hdbconfig/init${sid}.utl",
        "/hana/shared/$sid/global/hdb/opt/hdbconfig/init${sid}.utl",
    );
    
    foreach my $dp_profile (@dp_profile_paths) {
        if (-e $dp_profile) {
            my $dest = "$output_dir/init${sid}.utl";
            if (copy($dp_profile, $dest)) {
                print $errfh "Collected: $dp_profile\n";
                $collected_files{"init${sid}.utl"} = "Success";
            } else {
                print $errfh "Failed to copy $dp_profile: $!\n";
                $collected_files{"init${sid}.utl"} = "Failed";
            }
            last;
        }
    }
}

# -----------------------------
# Collect SAP HANA Backup Logs (backup.log)
# -----------------------------
print "Collecting SAP HANA backup logs...\n" if $verbose;

foreach my $sid (@sids) {
    next if $sid eq "XXX";
    
    # Find all backup.log files in trace directories
    my @trace_dirs;
    
    # Common trace directory patterns
    my @trace_patterns = (
        "/usr/sap/$sid/HDB*/*/trace",
        "/hana/shared/$sid/HDB*/*/trace",
    );
    
    foreach my $pattern (@trace_patterns) {
        my @matches = glob($pattern);
        push @trace_dirs, @matches;
    }
    
    foreach my $trace_dir (@trace_dirs) {
        my $backup_log = "$trace_dir/backup.log";
        if (-e $backup_log) {
            my $hostname = basename(dirname($trace_dir));
            my $dest = "$output_dir/backup_${sid}_${hostname}.log";
            
            if (copy($backup_log, $dest)) {
                print $errfh "Collected: $backup_log\n";
                $collected_files{"backup_${sid}_${hostname}.log"} = "Success";
            } else {
                print $errfh "Failed to copy $backup_log: $!\n";
                $collected_files{"backup_${sid}_${hostname}.log"} = "Failed";
            }
        }
    }

    foreach my $trace_dir (@trace_dirs) {
        my $backint_log = "$trace_dir/backint.log";
        if (-e $backint_log) {
            my $hostname = basename(dirname($trace_dir));
            my $dest = "$output_dir/backint_${sid}_${hostname}.log";
            
            if (copy($backint_log, $dest)) {
                print $errfh "Collected: $backint_log\n";
                $collected_files{"backint_${sid}_${hostname}.log"} = "Success";
            } else {
                print $errfh "Failed to copy $backint_log: $!\n";
                $collected_files{"backint_${sid}_${hostname}.log"} = "Failed";
            }
        }
    }
}

# -----------------------------
# Collect setup.sh and installation.log
# -----------------------------
print "Collecting TDP HANA setup and installation logs...\n" if $verbose;

my $tdp_hana_dir = "/opt/tivoli/tsm/tdp_hana";

if (-d $tdp_hana_dir) {

    # Collect setup.sh
    my $setup_file = "$tdp_hana_dir/setup.sh";
    if (-e $setup_file) {
        my $dest = "$output_dir/setup.sh";
        if (copy($setup_file, $dest)) {
            print $errfh "Collected: $setup_file\n";
            $collected_files{"setup.sh"} = "Success";
        } else {
            print $errfh "Failed to copy $setup_file: $!\n";
            $collected_files{"setup.sh"} = "Failed";
        }
    } else {
        print $errfh "Not found: $setup_file\n";
    }

    # Collect installation.log
    my $install_log = "$tdp_hana_dir/installation.log";
    if (-e $install_log) {
        my $dest = "$output_dir/installation.log";
        if (copy($install_log, $dest)) {
            print $errfh "Collected: $install_log\n";
            $collected_files{"installation.log"} = "Success";
        } else {
            print $errfh "Failed to copy $install_log: $!\n";
            $collected_files{"installation.log"} = "Failed";
        }
    } else {
        print $errfh "Not found: $install_log\n";
    }

} else {
    print $errfh "Directory not found: $tdp_hana_dir\n";
}



# -----------------------------
# Summary (verbose)
# -----------------------------
if ($verbose) {
    print "\n=== SAP HANA Module Summary ===\n";
    foreach my $file (sort keys %collected_files) {
        printf "  %-40s : %s\n", $file, $collected_files{$file};
    }
    print "\nCollected data saved in: $output_dir\n";
    print "Check script.log for detailed information.\n";
}

# -----------------------------
# Determine exit code
# -----------------------------
my $success_count = grep { $collected_files{$_} eq "Success" } keys %collected_files;
my $total = scalar keys %collected_files;
my $exit_code;

if ($success_count == 0) {
    $exit_code = 1;  # Complete failure
} elsif ($success_count == $total) {
    $exit_code = 0;  # Complete success
} else {
    $exit_code = 2;  # Partial success
}

exit($exit_code);

# Made with Bob
