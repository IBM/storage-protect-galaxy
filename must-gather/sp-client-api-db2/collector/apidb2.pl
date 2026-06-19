#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy;
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use system;
use Getopt::Long;

# ===============================================================
# Script Name : apidb2.pl
# Description : Collects API-DB2 specific diagnostic data for
#               IBM Spectrum Protect API for DB2
# ===============================================================

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$optfile,
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/apidb2";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Get base path and OS
# -----------------------------
my $base_path = env::get_api_base_path();
my $os = env::_os();

# Check if API client is installed
unless ($base_path) {
    die "ERROR: IBM Spectrum Protect API Client is not installed or could not be detected on this system.\n";
}

print "API Client installation detected at: $base_path\n" if $verbose;

# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print $errfh "=== Starting API-DB2 Data Collection ===\n";
print $errfh "Detected OS: $os\n";
print $errfh "Output directory: $output_dir\n\n";

# -----------------------------
# Collected items tracking
# -----------------------------
my %collected_items;

# -----------------------------
# Helper Functions
# -----------------------------

# Helper function to copy text files
sub collect_text_file {
    my ($source_path, $dest_filename, $item_name) = @_;
    
    if (-e $source_path) {
        my $dest = "$output_dir/$dest_filename";
        if (open(my $in, '<', $source_path) && open(my $out, '>', $dest)) {
            while (<$in>) { print $out $_; }
            close($in);
            close($out);
            $collected_items{$item_name} = "Success";
            print $errfh "Collected $item_name from: $source_path\n" if $verbose;
        } else {
            print $errfh "Error: Could not copy $item_name: $!\n";
            $collected_items{$item_name} = "Failed";
        }
    } else {
        print $errfh "Warning: $item_name not found at: $source_path\n";
        $collected_items{$item_name} = "NOT FOUND";
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

# =============================
# SECTION 1: API Configuration Files
# =============================
print $errfh "\n=== Section 1: API Configuration Files ===\n" if $verbose;

# 1.1 Collect dsm.opt
my $dsm_opt_path = $optfile || "$base_path/dsm.opt";
collect_text_file($dsm_opt_path, "dsm.opt", "dsm.opt");

my $dsm_sys_path = "$base_path/dsm.sys";
# 1.2 Collect dsm.sys (UNIX only)
if ($os !~ /MSWin32/i) {
    
    # Also check DSMI_DIR if set
    if ($ENV{DSMI_DIR} && -e "$ENV{DSMI_DIR}/dsm.sys") {
        $dsm_sys_path = "$ENV{DSMI_DIR}/dsm.sys";
    }
    
    collect_text_file($dsm_sys_path, "dsm.sys", "dsm.sys");
}

# =============================
# SECTION 2: API Log Files
# =============================
print $errfh "\n=== Section 2: API Log Files ===\n" if $verbose;

# 2.1 Collect dsierror.log
# 2.1 Collect dsierror.log
my $dsierror_path = "$base_path/dsierror.log";

if ($ENV{DSMI_LOG} && -e "$ENV{DSMI_LOG}/dsierror.log") {
    $dsierror_path = "$ENV{DSMI_LOG}/dsierror.log";
}

if (-e $dsierror_path) {

    my $dest = "$output_dir/dsierror.log";

    if (copy($dsierror_path, $dest)) {
        $collected_items{"dsierror.log"} = "Success";
    } else {
        $collected_items{"dsierror.log"} = "Failed";
    }

} else {

    my $errorlogname;

    if (-e $dsm_sys_path) {

        open(my $fh, '<', $dsm_sys_path);

        while (<$fh>) {
            if (/^\s*ERRORLOGNAME\s+(.+)/i) {
                $errorlogname = $1;
                $errorlogname =~ s/^\s+|\s+$//g;
                last;
            }
        }

        close($fh);
    }

    if ($errorlogname && -e $errorlogname) {

        if (copy($errorlogname, "$output_dir/dsierror.log")) {
            $collected_items{"dsierror.log"} = "Success";
        } else {
            $collected_items{"dsierror.log"} = "Failed";
        }

    } else {

        $collected_items{"dsierror.log"} = "NOT FOUND";

    }
}

# =============================
# SECTION 3: DB2 Client Information
# =============================
print $errfh "\n=== Section 3: DB2 Client Information ===\n" if $verbose;

# 3.1 Collect db2diag.log
my @db2_diag_locations = ();

if ($ENV{DB2INSTANCE}) {
    my $db2_home = $ENV{HOME} || "/home/$ENV{DB2INSTANCE}";
    push @db2_diag_locations, "$db2_home/sqllib/db2dump/db2diag.log";
}

# Common locations
if ($os =~ /MSWin32/i) {
    push @db2_diag_locations, glob("C:\\ProgramData\\IBM\\DB2\\db2diag.log");
} else {
    push @db2_diag_locations, glob("/home/db2inst1/sqllib/db2dump/db2diag.log");
    push @db2_diag_locations,
    glob("/opt/ibm/db2/*/db2dump/db2diag.log");
}

my $db2diag_found = 0;
foreach my $diag_path (@db2_diag_locations) {
    if (-e $diag_path) {
        my $dest = "$output_dir/db2diag.log";
        if (copy($diag_path, $dest)) {
            $collected_items{"db2diag.log"} = "Success";
            print $errfh "Collected db2diag.log from: $diag_path\n" if $verbose;
            $db2diag_found = 1;
            last;
        }
    }
}

if (!$db2diag_found) {
    print $errfh "Info: db2diag.log not found in common locations\n";
    $collected_items{"db2diag.log"} = "NOT FOUND";
}



# --------------------------------------------------
# DB2 Instance Discovery
# --------------------------------------------------

my @instances;

my $db2ilist_cmd = `find /opt/ibm/db2 -name db2ilist -type f 2>/dev/null | head -1`;
chomp($db2ilist_cmd);

if ($db2ilist_cmd && -x $db2ilist_cmd) {

    @instances = `$db2ilist_cmd 2>/dev/null`;
    chomp @instances;

    if (@instances) {

        open(my $fh, '>', "$output_dir/db2_instances.txt");

        foreach my $inst (@instances) {
            print $fh "$inst\n";
        }

        close($fh);

        $collected_items{"db2_instances"} = "Success";

    } else {

        $collected_items{"db2_instances"} = "NOT FOUND";

    }

} else {

    $collected_items{"db2_instances"} = "NOT FOUND";

}


# --------------------------------------------------
# 3.2 collect db2profile and userprofile for each instance
# --------------------------------------------------
foreach my $inst (@instances) {

    my @pw = getpwnam($inst);

    next unless @pw;

    my $home = $pw[7];

    collect_text_file(
        "$home/sqllib/db2profile",
        "${inst}_db2profile",
        "${inst}_db2profile"
    );

    collect_text_file(
        "$home/sqllib/userprofile",
        "${inst}_userprofile",
        "${inst}_userprofile"
    );
}


# 3.3 Collect DB2 level information
my $db2level_file = "$output_dir/db2level.txt";
if ($os =~ /MSWin32/i) {
    run_system_command("db2level >\"$db2level_file\" 2>&1", $db2level_file, "db2level");
} else {
    my $db2level_cmd = `find /opt/ibm/db2 -name db2level -type f 2>/dev/null | head -1`;
    chomp($db2level_cmd);

    if ($db2level_cmd && -x $db2level_cmd) {

        run_system_command(
            "$db2level_cmd > \"$db2level_file\" 2>&1",
            $db2level_file,
            "db2level"
        );

    } else {

        $collected_items{"db2level"} = "NOT FOUND";

    }
}


# 3.4 Collect DSM environment variables

my $dsm_env_file = "$output_dir/dsm_environment.txt";

if (open(my $envfh, '>', $dsm_env_file)) {

    my $found = 0;

    foreach my $key (sort keys %ENV) {
        if ($key =~ /^DSM/i) {
            print $envfh "$key=$ENV{$key}\n";
            $found = 1;
        }
    }

    if (!$found) {
        print $envfh "No DSM environment variables found.\n";
    }

    close($envfh);

    $collected_items{"dsm_environment"} = "Success";

} else {

    print $errfh "Error: Unable to create $dsm_env_file : $!\n";
    $collected_items{"dsm_environment"} = "Failed";

}

# 3.5 Collect DB2 instance environment (Unix/Linux)
    
if ($os !~ /MSWin32/i) {

    my $db2_proc_file = "$output_dir/db2sysc_process.txt";

    run_system_command(
        "ps -elf | grep -i db2sysc > \"$db2_proc_file\" 2>&1",
        $db2_proc_file,
        "db2sysc_process"
    );

    my $db2_env_file = "$output_dir/db2_instance_environment.txt";

    my $ps_output = `ps -elf | grep -i db2sysc | grep -v grep 2>/dev/null`;

    if ($ps_output) {

        my ($pid) = $ps_output =~ /^\S+\s+\S+\s+(\d+)/;

        if ($pid) {

            run_system_command(
                "ps eww $pid > \"$db2_env_file\" 2>&1",
                $db2_env_file,
                "db2_instance_environment"
            );

        } else {

            $collected_items{"db2_instance_environment"} = "NOT FOUND";

        }
    }

}

# 3.6 Collect DB2 instance environment (Windows)
if ($os =~ /MSWin32/i) {
    my $win_env_file = "$output_dir/windows_environment.txt";
    run_system_command("set >\"$win_env_file\" 2>&1", $win_env_file, "windows_environment");
}

# 3.7 colect db cfg
foreach my $inst (@instances) {

    my $dbdir_file =
        "$output_dir/${inst}_db_directory.txt";

    run_system_command(
        qq(su - $inst -c "db2 list db directory" > "$dbdir_file" 2>&1),
        $dbdir_file,
        "${inst}_db_directory"
    );
}

foreach my $inst (@instances) {

    my $dbdir_file =
        "$output_dir/${inst}_db_directory.txt";

    next unless -f $dbdir_file;

    open(my $fh, '<', $dbdir_file);

    while (<$fh>) {

        next unless /Database alias\s+=\s+(.+)/i;

        my $dbname = $1;
        $dbname =~ s/^\s+|\s+$//g;

        my $cfg_file =
            "$output_dir/${inst}_${dbname}_db_cfg.txt";

        run_system_command(
            qq(su - $inst -c "db2 get db cfg for $dbname" > "$cfg_file" 2>&1),
            $cfg_file,
            "${inst}_${dbname}_db_cfg"
        );
    }

    close($fh);
}

# =============================
# SECTION 5: Platform-Specific Data
# =============================
print $errfh "\n=== Section 5: Platform-Specific Data ===\n" if $verbose;

if ($os =~ /aix/i) {
    print $errfh "Collecting AIX-specific information...\n" if $verbose;
    run_system_command("lslpp -L tivoli.tsm.* >\"$output_dir/lslpp_tivoli_tsm.txt\" 2>&1", 
                       "$output_dir/lslpp_tivoli_tsm.txt", "lslpp_tivoli_tsm");

} elsif ($os =~ /solaris/i) {
    print $errfh "Collecting Solaris-specific information...\n" if $verbose;
    run_system_command("pkginfo -l TIVsmCapi >\"$output_dir/pkginfo_TIVsmCapi.txt\" 2>&1", 
                       "$output_dir/pkginfo_TIVsmCapi.txt", "pkginfo_TIVsmCapi");

} elsif ($os =~ /linux/i) {
    print $errfh "Collecting Linux-specific information...\n" if $verbose;
    run_system_command("rpm -qai TIV* >\"$output_dir/rpm_TIV.txt\" 2>&1", 
                       "$output_dir/rpm_TIV.txt", "rpm_TIV");

} elsif ($os =~ /MSWin32/i) {
    print $errfh "Collecting Windows-specific information...\n" if $verbose;
    run_system_command("reg query HKLM\\software\\ibm\\adsm\\currentversion /s >\"$output_dir/registry_ibm_adsm.txt\" 2>&1", 
                       "$output_dir/registry_ibm_adsm.txt", "registry_ibm_adsm");

} else {
    print $errfh "Warning: Platform '$os' not specifically supported for platform-specific collection\n";
    $collected_items{"platform_support"} = "UNSUPPORTED";
}


# =============================
# Final Summary
# =============================
print $errfh "\n=== Collection Complete ===\n";
close($errfh);

# -----------------------------
# Summary (only in verbose mode)
# -----------------------------
if ($verbose) {
    print "\n=== API-DB2 Module Summary ===\n";
    foreach my $item (sort keys %collected_items) {
        printf "  %-30s : %s\n", $item, $collected_items{$item};
    }
    print "Collected API-DB2 data saved in: $output_dir\n";
    print "Check script.log for any failures.\n";
}

# -----------------------------
# Determine module-level status for framework
# -----------------------------
my $success_count = 0;
my $fail_count = 0;
my $total = scalar keys %collected_items;

foreach my $status (values %collected_items) {
    $success_count++ if $status =~ /^Success/;
    $fail_count++    if $status eq "Failed";
}

my $module_status;
if ($success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

# Exit code mapping for framework (0=Success, 1=failure, 2=Partial)
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);

# Made with Bob
