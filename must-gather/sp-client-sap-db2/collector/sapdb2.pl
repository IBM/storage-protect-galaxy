#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;
use Getopt::Long;

# ===============================================================
# Script Name : sapdb2.pl
# Description : Collects SAP DB2 specific configuration and diagnostic data
#               (Does not duplicate files collected by config.pl and log.pl)
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
$output_dir = "$output_dir/sapdb2";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup
# -----------------------------
my $os = env::_os();
my $base_path = env::get_sap_db2_base_path();
my %collected;
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print "\n=== Starting SAP DB2 Data Collection ===\n" if $verbose;
print $errfh "Detected OS: $os\n";
print $errfh "Base Path: " . ($base_path || "NOT FOUND") . "\n";

unless ($base_path) {
    print $errfh "Error: SAP DB2 installation not found\n";
    close($errfh);
    exit(1);
}

# -----------------------------
# Collect Version Information
# -----------------------------
print "Collecting version information...\n" if $verbose;
my $version_file = "$output_dir/version_info.txt";
open(my $vfh, '>', $version_file) or do {
    print $errfh "Error: Cannot create version_info.txt: $!\n";
    $collected{"version_info.txt"} = "Failed";
};

if ($vfh) {
    # Get backint version
    print $vfh "=== Data Protection for SAP Version ===\n";
    my $backint_cmd;
    if ($os =~ /MSWin32/i) {
        $backint_cmd = "cd /d \"$base_path\" && backint 2>&1";
    } else {
        $backint_cmd = "cd \"$base_path\" && ./backint 2>&1";
    }
    
    my $backint_output = `$backint_cmd`;
    print $vfh $backint_output;
    print $vfh "\n";
    
    # Get package version based on OS
    print $vfh "=== Package Information ===\n";
    if ($os =~ /aix/i) {
        my $pkg_info = `lslpp -l tivoli.tsm* 2>&1`;
        print $vfh $pkg_info;
    } elsif ($os =~ /linux/i) {
        my $pkg_info = `rpm -qa TIVsm* 2>&1`;
        print $vfh $pkg_info;
    } elsif ($os =~ /sunos|solaris/i) {
        my $pkg_info = `pkginfo TIVsm* 2>&1`;
        print $vfh $pkg_info;
    } elsif ($os =~ /MSWin32/i) {
        # Windows: Get API version from registry
        my $reg_query = `reg query "HKLM\\SOFTWARE\\IBM\\ADSM\\CurrentVersion\\Api64" /v Path 2>NUL`;
        print $vfh "=== API Registry Information ===\n";
        print $vfh $reg_query;
    }
    
    close($vfh);
    $collected{"version_info.txt"} = "Success";
}

# -----------------------------
# Collect SAP-specific configuration files
# -----------------------------
print "Collecting SAP-specific configuration...\n" if $verbose;

# Look for init<SID>.sap and init<SID>.utl files
my @sap_config_patterns = ("init*.sap", "init*.utl");
foreach my $pattern (@sap_config_patterns) {
    # Quote the path for Windows compatibility with spaces
    my $search_path = $os =~ /MSWin32/i ? "\"$base_path\\$pattern\"" : "$base_path/$pattern";
    my @files = glob($search_path);
    
    foreach my $file (@files) {
        my ($filename) = $file =~ /([^\/\\]+)$/;
        my $dest = "$output_dir/$filename";
        
        if (-e $file) {
            if (copy($file, $dest)) {
                print "Collected: $filename\n" if $verbose;
                $collected{$filename} = "Success";
            } else {
                print $errfh "Failed to copy $file: $!\n";
                $collected{$filename} = "Failed";
            }
        }
    }
}

# -----------------------------
# Collect DB2 Configuration
# -----------------------------
print "Collecting DB2 configuration...\n" if $verbose;

my $db2_config_file = "$output_dir/db2_config.txt";
open(my $db2fh, '>', $db2_config_file) or do {
    print $errfh "Error: Cannot create db2_config.txt: $!\n";
    $collected{"db2_config.txt"} = "Failed";
};

if ($db2fh) {
    print $db2fh "=== DB2 Database Configuration ===\n";
    my $db2_output = `db2 get db cfg 2>&1`;
    if ($db2_output) {
        print $db2fh $db2_output;
    } else {
        print $db2fh "DB2 command not available or failed to execute\n";
        print $errfh "Warning: 'db2 get db cfg' command failed or returned no output\n";
    }
    print $db2fh "\n";
    
    print $db2fh "=== DB2 Database Manager Configuration ===\n";
    my $dbm_output = `db2 get dbm cfg 2>&1`;
    if ($dbm_output) {
        print $db2fh $dbm_output;
    } else {
        print $db2fh "DB2 command not available or failed to execute\n";
        print $errfh "Warning: 'db2 get dbm cfg' command failed or returned no output\n";
    }
    print $db2fh "\n";
    
    print $db2fh "=== Environment Variables (Filtered) ===\n";
    if ($os =~ /MSWin32/i) {
        my $env_output = `set 2>&1`;
        # Filter out sensitive info
        foreach my $line (split /\n/, $env_output) {
            next if $line =~ /PASSWORD|SECRET|KEY/i;
            print $db2fh "$line\n";
        }
    } else {
        my $env_output = `env 2>&1`;
        # Filter out sensitive info
        foreach my $line (split /\n/, $env_output) {
            next if $line =~ /PASSWORD|SECRET|KEY/i;
            print $db2fh "$line\n";
        }
    }
    
    close($db2fh);
    $collected{"db2_config.txt"} = "Success";
}

# -----------------------------
# Collect vendor.env file (if DB2_VENDOR_INI is set)
# -----------------------------
if ($ENV{DB2_VENDOR_INI} && -e $ENV{DB2_VENDOR_INI}) {
    my $vendor_env = $ENV{DB2_VENDOR_INI};
    my ($filename) = $vendor_env =~ /([^\/\\]+)$/;
    my $dest = "$output_dir/$filename";
    
    if (copy($vendor_env, $dest)) {
        print "Collected: $filename\n" if $verbose;
        $collected{$filename} = "Success";
    } else {
        print $errfh "Failed to copy $vendor_env: $!\n";
        $collected{$filename} = "Failed";
    }
}

# -----------------------------
# Collect DB2 diagnostic log (db2diag.log)
# -----------------------------
my @db2_diag_paths;
if ($os =~ /MSWin32/i) {
    @db2_diag_paths = (
        "C:/ProgramData/IBM/DB2/db2diag.log",
    );
    push @db2_diag_paths, "$ENV{DB2PATH}/db2diag.log" if $ENV{DB2PATH};
} else {
    @db2_diag_paths = (
        "$ENV{HOME}/sqllib/db2dump/db2diag.log",
        "/home/db2inst1/sqllib/db2dump/db2diag.log",
    );
}

my $db2diag_collected = 0;
foreach my $diag_path (@db2_diag_paths) {
    next unless $diag_path && -e $diag_path;
    
    my $dest = "$output_dir/db2diag.log";
    if (copy($diag_path, $dest)) {
        print "Collected: db2diag.log\n" if $verbose;
        print $errfh "Collected db2diag.log from: $diag_path\n";
        $collected{"db2diag.log"} = "Success";
        $db2diag_collected = 1;
        last;
    } else {
        print $errfh "Failed to copy db2diag.log from $diag_path: $!\n";
        $collected{"db2diag.log"} = "Failed";
    }
}

# Mark as not found if db2diag.log was not collected
if (!$db2diag_collected) {
    $collected{"db2diag.log"} = "Not Found";
    print $errfh "db2diag.log not found in expected locations\n";
}

# Collect TDP DB2 specific log files (tdpdb2.<SID>.<NODE>.log)
# -----------------------------
my @tdp_logs = glob("$base_path/tdpdb2.*.log");
foreach my $log (@tdp_logs) {
    my ($filename) = $log =~ /([^\/\\]+)$/;
    my $dest = "$output_dir/$filename";
    
    if (copy($log, $dest)) {
        print "Collected: $filename\n" if $verbose;
        $collected{$filename} = "Success";
    } else {
        print $errfh "Failed to copy $log: $!\n";
        $collected{$filename} = "Failed";
    }
}

# -----------------------------
# Collect API Client Configuration Files
# -----------------------------
print "Collecting API client configuration...\n" if $verbose;

# Create API subdirectory for organization
my $api_dir = "$output_dir/api";
make_path($api_dir) unless -d $api_dir;

# Collect dsm.sys from API directories
my @api_dsm_paths;
if ($os =~ /MSWin32/i) {
    @api_dsm_paths = (
        "C:/Program Files/Tivoli/TSM/api/dsm.opt",
        "C:/Program Files/Tivoli/TSM/api/bin/dsm.opt",
        "C:/Program Files/Tivoli/TSM/api/bin64/dsm.opt",
    );
} else {
    @api_dsm_paths = (
        "/opt/tivoli/tsm/client/api/bin/dsm.sys",
        "/opt/tivoli/tsm/client/api/bin64/dsm.sys",
        "/usr/tivoli/tsm/client/api/bin/dsm.sys",
        "/usr/tivoli/tsm/client/api/bin64/dsm.sys",
    );
}

my $api_dsm_collected = 0;
foreach my $api_path (@api_dsm_paths) {
    if (-e $api_path) {
        my ($filename) = $api_path =~ /([^\/\\]+)$/;
        my $dest = "$api_dir/api_$filename";
        
        if (copy($api_path, $dest)) {
            print "Collected: API $filename from $api_path\n" if $verbose;
            print $errfh "Collected API config from: $api_path\n";
            $collected{"api/$filename"} = "Success";
            $api_dsm_collected = 1;
        } else {
            print $errfh "Failed to copy $api_path: $!\n";
        }
    }
}

# Collect file referenced by DSMI_CONFIG
if ($ENV{DSMI_CONFIG}) {
    print $errfh "DSMI_CONFIG environment variable: $ENV{DSMI_CONFIG}\n";
    
    if (-e $ENV{DSMI_CONFIG}) {
        my ($filename) = $ENV{DSMI_CONFIG} =~ /([^\/\\]+)$/;
        my $dest = "$api_dir/dsmi_config_$filename";
        
        if (copy($ENV{DSMI_CONFIG}, $dest)) {
            print "Collected: DSMI_CONFIG file ($filename)\n" if $verbose;
            print $errfh "Collected DSMI_CONFIG from: $ENV{DSMI_CONFIG}\n";
            $collected{"api/dsmi_config_$filename"} = "Success";
            
            # For Windows, also collect {server}.opt from same directory
            if ($os =~ /MSWin32/i) {
                my ($dir) = $ENV{DSMI_CONFIG} =~ /^(.+)[\/\\][^\/\\]+$/;
                if ($dir) {
                    my @opt_files = glob("$dir/*.opt");
                    foreach my $opt_file (@opt_files) {
                        next if $opt_file eq $ENV{DSMI_CONFIG};
                        my ($opt_name) = $opt_file =~ /([^\/\\]+)$/;
                        my $opt_dest = "$api_dir/$opt_name";
                        
                        if (copy($opt_file, $opt_dest)) {
                            print "Collected: $opt_name\n" if $verbose;
                            $collected{"api/$opt_name"} = "Success";
                        }
                    }
                }
            }
        } else {
            print $errfh "Failed to copy DSMI_CONFIG file: $!\n";
            $collected{"api/dsmi_config"} = "Failed";
        }
    } else {
        print $errfh "Warning: DSMI_CONFIG points to non-existent file: $ENV{DSMI_CONFIG}\n";
    }
}

# Collect file from DSMI_DIR
if ($ENV{DSMI_DIR}) {
    print $errfh "DSMI_DIR environment variable: $ENV{DSMI_DIR}\n";
    
    my $dsmi_dir_config = $os =~ /MSWin32/i ? "$ENV{DSMI_DIR}/dsm.opt" : "$ENV{DSMI_DIR}/dsm.sys";
    if (-e $dsmi_dir_config) {
        my ($filename) = $dsmi_dir_config =~ /([^\/\\]+)$/;
        my $dest = "$api_dir/dsmi_dir_$filename";
        
        if (copy($dsmi_dir_config, $dest)) {
            print "Collected: DSMI_DIR config ($filename)\n" if $verbose;
            print $errfh "Collected DSMI_DIR config from: $dsmi_dir_config\n";
            $collected{"api/dsmi_dir_$filename"} = "Success";
        } else {
            print $errfh "Failed to copy DSMI_DIR config: $!\n";
        }
    }
}

# -----------------------------
# Collect API Error Logs (dsierror.log and ERRORLOGNAME)
# -----------------------------
print "Collecting API error logs...\n" if $verbose;

# Helper function to parse ERRORLOGNAME from config file
sub parse_errorlogname {
    my ($config_file) = @_;
    return unless -e $config_file;
    
    if (open(my $cfh, '<', $config_file)) {
        while (<$cfh>) {
            next if /^\s*\*/;  # Skip comments
            if (/^\s*ERRORLOGNAME\s+(.+?)\s*$/i) {
                my $logname = $1;
                $logname =~ s/["']//g;  # Remove quotes
                close($cfh);
                return $logname;
            }
        }
        close($cfh);
    }
    return;
}

# Collect all API config files we found to parse ERRORLOGNAME
my @api_configs_to_parse;

# Add standard API paths
push @api_configs_to_parse, @api_dsm_paths;

# Add DSMI_CONFIG if set
push @api_configs_to_parse, $ENV{DSMI_CONFIG} if $ENV{DSMI_CONFIG};

# Add DSMI_DIR config if set
if ($ENV{DSMI_DIR}) {
    my $dsmi_dir_cfg = $os =~ /MSWin32/i ? "$ENV{DSMI_DIR}/dsm.opt" : "$ENV{DSMI_DIR}/dsm.sys";
    push @api_configs_to_parse, $dsmi_dir_cfg;
}

# Parse ERRORLOGNAME from API configs
my %errorlog_paths;
my %errorlog_dirs;  # Track directories for dsmerror.log collection

foreach my $config (@api_configs_to_parse) {
    next unless $config && -e $config;
    
    my $errorlog = parse_errorlogname($config);
    if ($errorlog) {
        print $errfh "Found ERRORLOGNAME in $config: $errorlog\n";
        $errorlog_paths{$errorlog} = 1;
        
        # Track directory for dsmerror.log collection
        my ($dir) = $errorlog =~ /^(.+)[\/\\][^\/\\]+$/;
        if ($dir) {
            $errorlog_dirs{$dir} = 1;
        }
    }
}

# Collect ERRORLOGNAME files
my $errorlogname_collected = 0;
foreach my $errorlog (keys %errorlog_paths) {
    if (-e $errorlog) {
        my ($filename) = $errorlog =~ /([^\/\\]+)$/;
        my $dest = "$api_dir/api_$filename";
        
        if (copy($errorlog, $dest)) {
            print "Collected: API error log ($filename) from ERRORLOGNAME\n" if $verbose;
            print $errfh "Collected API ERRORLOGNAME log from: $errorlog\n";
            $collected{"api/errorlogname_$filename"} = "Success";
            $errorlogname_collected++;
        } else {
            print $errfh "Failed to copy ERRORLOGNAME log $errorlog: $!\n";
            $collected{"api/errorlogname_$filename"} = "Failed";
        }
    }
}

# Mark as not found if no ERRORLOGNAME files were collected
if (!$errorlogname_collected && keys %errorlog_paths) {
    $collected{"api/errorlogname_logs"} = "Not Found";
    print $errfh "ERRORLOGNAME logs not found in expected locations\n";
}

# Collect dsierror.log from default locations
my @api_log_paths;
if ($os =~ /MSWin32/i) {
    @api_log_paths = (
        "C:/Program Files/Tivoli/TSM/api/dsierror.log",
        "C:/Program Files/Tivoli/TSM/api/bin/dsierror.log",
        "C:/Program Files/Tivoli/TSM/api/bin64/dsierror.log",
    );
    push @api_log_paths, "$ENV{DSMI_DIR}/dsierror.log" if $ENV{DSMI_DIR};
} else {
    @api_log_paths = (
        "/opt/tivoli/tsm/client/api/bin/dsierror.log",
        "/opt/tivoli/tsm/client/api/bin64/dsierror.log",
        "/usr/tivoli/tsm/client/api/bin/dsierror.log",
        "/usr/tivoli/tsm/client/api/bin64/dsierror.log",
    );
    push @api_log_paths, "$ENV{DSMI_DIR}/dsierror.log" if $ENV{DSMI_DIR};
}

my $dsierror_collected = 0;
foreach my $log_path (@api_log_paths) {
    if (-e $log_path) {
        my $dest = "$api_dir/dsierror.log";
        
        if (copy($log_path, $dest)) {
            print "Collected: API error log (dsierror.log)\n" if $verbose;
            print $errfh "Collected API error log from: $log_path\n";
            $collected{"api/dsierror.log"} = "Success";
            $dsierror_collected = 1;
            last;
        } else {
            print $errfh "Failed to copy API error log from $log_path: $!\n";
            $collected{"api/dsierror.log"} = "Failed";
        }
    }
}

# Mark as not found if dsierror.log was not collected
if (!$dsierror_collected) {
    $collected{"api/dsierror.log"} = "Not Found";
    print $errfh "dsierror.log not found in default API locations\n";
}

# Collect dsmerror.log with priority logic:
# 1. First try from ERRORLOGNAME directory (if ERRORLOGNAME was found)
# 2. If not found, try default API directories
my $api_dsmerror_collected = 0;

# Priority 1: Check if ERRORLOGNAME was found and collect dsmerror.log from that directory
if (keys %errorlog_dirs) {
    foreach my $dir (keys %errorlog_dirs) {
        my $dsmerror = $os =~ /MSWin32/i ? "$dir\\dsmerror.log" : "$dir/dsmerror.log";
        
        if (-e $dsmerror) {
            my $dest = "$api_dir/api_dsmerror.log";
            
            if (copy($dsmerror, $dest)) {
                print "Collected: API dsmerror.log from ERRORLOGNAME directory\n" if $verbose;
                print $errfh "Collected API dsmerror.log from ERRORLOGNAME directory: $dsmerror\n";
                $collected{"api/api_dsmerror.log"} = "Success";
                $api_dsmerror_collected = 1;
                last;
            } else {
                print $errfh "Failed to copy dsmerror.log from ERRORLOGNAME directory $dsmerror: $!\n";
                $collected{"api/api_dsmerror.log"} = "Failed";
            }
        }
    }
}

# Priority 2: If not collected from ERRORLOGNAME directory, try default API directories
if (!$api_dsmerror_collected) {
    my @api_dsmerror_paths;
    if ($os =~ /MSWin32/i) {
        @api_dsmerror_paths = (
            "C:/Program Files/Tivoli/TSM/api/dsmerror.log",
            "C:/Program Files/Tivoli/TSM/api/bin/dsmerror.log",
            "C:/Program Files/Tivoli/TSM/api/bin64/dsmerror.log",
        );
        push @api_dsmerror_paths, "$ENV{DSMI_DIR}/dsmerror.log" if $ENV{DSMI_DIR};
    } else {
        @api_dsmerror_paths = (
            "/opt/tivoli/tsm/client/api/bin/dsmerror.log",
            "/opt/tivoli/tsm/client/api/bin64/dsmerror.log",
            "/usr/tivoli/tsm/client/api/bin/dsmerror.log",
            "/usr/tivoli/tsm/client/api/bin64/dsmerror.log",
        );
        push @api_dsmerror_paths, "$ENV{DSMI_DIR}/dsmerror.log" if $ENV{DSMI_DIR};
    }
    
    foreach my $log_path (@api_dsmerror_paths) {
        if (-e $log_path) {
            my $dest = "$api_dir/api_dsmerror.log";
            
            if (copy($log_path, $dest)) {
                print "Collected: API dsmerror.log from default directory\n" if $verbose;
                print $errfh "Collected API dsmerror.log from default directory: $log_path\n";
                $collected{"api/api_dsmerror.log"} = "Success";
                $api_dsmerror_collected = 1;
                last;
            } else {
                print $errfh "Failed to copy API dsmerror.log from $log_path: $!\n";
                $collected{"api/api_dsmerror.log"} = "Failed";
            }
        }
    }
}

# Mark as not found if API dsmerror.log was not collected from either location
if (!$api_dsmerror_collected) {
    $collected{"api/api_dsmerror.log"} = "Not Found";
    print $errfh "API dsmerror.log not found in ERRORLOGNAME directory or default API locations\n";
}

# Document init<SID>.utl location if found
my @utl_files = glob("$base_path/init*.utl");
if (@utl_files) {
    my $location_file = "$output_dir/init_utl_locations.txt";
    if (open(my $locfh, '>', $location_file)) {
        print $locfh "=== init<SID>.utl File Locations ===\n\n";
        foreach my $utl (@utl_files) {
            print $locfh "$utl\n";
            
            # Check if referenced in vendor.env
            if ($ENV{DB2_VENDOR_INI} && -e $ENV{DB2_VENDOR_INI}) {
                if (open(my $vfh, '<', $ENV{DB2_VENDOR_INI})) {
                    while (<$vfh>) {
                        if (/XINT_PROFILE.*$utl/i) {
                            print $locfh "  Referenced by XINT_PROFILE in vendor.env\n";
                            last;
                        }
                    }
                    close($vfh);
                }
            }
        }
        close($locfh);
        $collected{"init_utl_locations.txt"} = "Success";
    }
}

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {
    print "\n=== SAP DB2 Module Summary ===\n";
    foreach my $file (sort keys %collected) {
        printf "  %-40s : %s\n", $file, $collected{$file};
    }
    print "Collected data saved in: $output_dir\n";
    print "Check script.log for any failures.\n";
}

# -----------------------------
# Determine exit code
# -----------------------------
my $success_count = grep { $collected{$_} eq "Success" } keys %collected;
my $total = scalar keys %collected;
my $exit_code;

if ($total == 0) {
    $exit_code = 1;
} elsif ($success_count == $total) {
    $exit_code = 0;
} elsif ($success_count > 0) {
    $exit_code = 2;
} else {
    $exit_code = 1;
}

close($errfh);
exit($exit_code);

# Made with Bob
