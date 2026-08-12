#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Basename;
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use Getopt::Long;

# ===============================================================
# Script Name : hsm.pl
# Description : Collects HSM-specific diagnostic data for
#               IBM Spectrum Protect HSM Client (Unix/Linux)
#               Based on IBM technote collect.pl script
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
$output_dir = "$output_dir/hsm";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Get base path using env.pm
# -----------------------------
my $hsm_path = env::get_hsm_base_path();
my $os = env::_os();

# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print $errfh "=== Starting HSM-Specific Data Collection ===\n";
print $errfh "Detected OS: $os\n";
print $errfh "HSM Base Path: " . ($hsm_path || "NOT FOUND") . "\n\n";

# -----------------------------
# Collected items tracking
# -----------------------------
my %collected_items;

# -----------------------------
# Helper Functions
# -----------------------------

# Helper to run command and save output
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

# ===============================================================
# HSM SPECIFIC INFORMATION COLLECTION
# Based on section 1.7 from IBM technote collect.pl
# ===============================================================

print $errfh "\n=== HSM Specific Information Collection ===\n";

# -----------------------------------------------------------
# 1. Check if HSM is installed using dsmmigquery
# -----------------------------------------------------------
my $hsm_check_file = "$output_dir/hsm_check.txt";
my $hsm_check_cmd;

if ($os =~ /MSWin32/i) {
    $hsm_check_cmd = "\"$hsm_path\\dsminfo.exe\" all";
}
else {
    $hsm_check_cmd = 'dsmmigquery 2>&1';
}

run_command_to_file(
    $hsm_check_cmd,
    $hsm_check_file,
    "HSM_Check"
);

# Check if HSM is actually installed
my $hsm_installed = 0;
if (-f $hsm_check_file) {
    open my $fh, '<', $hsm_check_file;
    my $content = do { local $/; <$fh> };
    close $fh;
    
    # If command not found or returns specific error codes, HSM is not installed
    if ($content !~ /command not found/i && $content !~ /not recognized/i) {
        $hsm_installed = 1;
    }
}

if (!$hsm_installed) {
    print $errfh "HSM does not appear to be installed on this system\n";
    $collected_items{"HSM_Installation"} = "NOT FOUND";
    
    close($errfh);
    
    if ($verbose) {
        print "\n=== HSM Module Summary ===\n";
        print "HSM is not installed on this system\n";
    }
    
    exit 1;
}

print $errfh "HSM is installed, proceeding with data collection...\n";

# -----------------------------------------------------------
# 2. dsmc query systeminfo with HSM optfile
# Collect system information using HSM client configuration
# -----------------------------------------------------------
my $ba_path = env::get_ba_base_path();
my $dsmc;

if ($os =~ /MSWin32/i) {
    $dsmc = `where dsmc.exe 2>nul`;
    chomp($dsmc);
    if (!$dsmc || !-e $dsmc) {
        $dsmc = "$ba_path\\dsmc.exe" if -e "$ba_path\\dsmc.exe";
    }
} else {
    $dsmc = `which dsmc 2>/dev/null`;
    chomp($dsmc);
    if (!$dsmc || !-x $dsmc) {
        $dsmc = "$ba_path/dsmc" if -x "$ba_path/dsmc";
    }
}

unless ($dsmc && -x $dsmc) {
    print $errfh "Error: dsmc not found on this system.\n";
    close($errfh);
    die "Error: dsmc binary not found.\n";
}
# -----------------------------
# Run DSM query for system info
# -----------------------------
my $cmd;
my $console_out = "$output_dir/hsmsysteminfo_console.txt";
my $opt_file= "$hsm_path/dsm.opt";
my $systeminfo_file = "$output_dir/hsmsysteminfo.txt";
if ($os =~ /MSWin32/i) {
    $cmd = "\"$dsmc\" query systeminfo -filename=\"$systeminfo_file\" -optfile=\"$opt_file\"  >\"$console_out\" 2>&1";
} else {
    $cmd = "\"$dsmc\" query systeminfo -filename=\"$systeminfo_file\" -optfile=\"$opt_file\" >\"$console_out\" 2>&1";
}

# -----------------------------------------------------------
# Platform-specific HSM commands
# -----------------------------------------------------------
if ($os =~ /MSWin32/i) {
    # Windows-specific HSM commands
    print $errfh "\n=== Collecting Windows HSM Information ===\n";
    
    # 3. dsminfo.exe all
    # Collect all HSM information
    run_command_to_file(
        "\"$hsm_path\\dsminfo.exe\" all",
        "$output_dir/hsminfo.txt",
        "HSM_Info"
    );
    
    # 4. dsmhsmclc.exe -query
    # Query HSM client configuration
    run_command_to_file(
         "\"$hsm_path\\dsmhsmclc.exe\" -query",
        "$output_dir/dsmhsmclc.txt",
        "HSM_Client_Query"
    );
    
    # 5. dsmhsmclc.exe check
    # Check HSM client status
    run_command_to_file(
        "\"$hsm_path\\dsmhsmclc.exe\" check",
        "$output_dir/dsmhsmclc_check.txt",
        "HSM_Client_Check"
    );
    
    # 6. dsmclc.exe listfilespaces
    # List HSM file spaces
    run_command_to_file(
        "\"$hsm_path\\dsmclc.exe\" listfilespaces",
        "$output_dir/hsmfilespaces.txt",
        "HSM_Filespaces"
    );
    
} else {
    # Unix/Linux-specific HSM commands
    print $errfh "\n=== Collecting Unix/Linux HSM Information ===\n";
    
    # 3. dsmmigfs q -detail
    # Query file system migration details
    run_command_to_file(
        'dsmmigfs q -detail 2>&1',
        "$output_dir/dsmmigfs_q_detail.txt",
        "dsmmigfs_q_detail"
    );
    
    # 4. dsmmigfs q -f
    # Query file system migration with full details
    run_command_to_file(
        'dsmmigfs q -f 2>&1',
        "$output_dir/dsmmigfs_q_f.txt",
        "dsmmigfs_q_f"
    );
    
    # 5. dsmdf
    # Display HSM disk space information
    run_command_to_file(
        'dsmdf 2>&1',
        "$output_dir/dsmdf.txt",
        "dsmdf"
    );
    
    # 6. ls -lR /etc/adsm/SpaceMan
    # List HSM SpaceMan configuration directory
    if (-d "/etc/adsm/SpaceMan") {

    run_command_to_file(
        'ls -lR /etc/adsm/SpaceMan',
        "$output_dir/spaceman_config.txt",
        "SpaceMan_Config"
    );
}
else {
    $collected_items{"SpaceMan_Config"} = "Not Found";
}
    
    # 7. dsmmigquery -o
    # Query HSM options
    run_command_to_file(
        'dsmmigquery -o 2>&1',
        "$output_dir/dsmmigquery_o.txt",
        "dsmmigquery_options"
    );
    
    # 8. dsmmigquery -mgmt -detail
    # Query HSM management details
    run_command_to_file(
        'dsmmigquery -mgmt -detail 2>&1',
        "$output_dir/dsmmigquery_mgmt_detail.txt",
        "dsmmigquery_mgmt"
    );
}

# -----------------------------------------------------------
# 9. HSM Processes (OS-specific)
# -----------------------------------------------------------
if ($os =~ /MSWin32/i) {
    run_command_to_file(
        'tasklist /FI "IMAGENAME eq dsm*" 2>&1',
        "$output_dir/hsm_processes.txt",
        "HSM_Processes"
    );
} else {
    run_command_to_file(
        'ps -ef | grep -i hsm | grep -v grep 2>&1',
        "$output_dir/hsm_processes.txt",
        "HSM_Processes"
    );
}

# -----------------------------------------------------------
# 10. HSM Daemons/Services (OS-specific)
# -----------------------------------------------------------
if ($os =~ /MSWin32/i) {
    run_command_to_file(
        'sc query state= all | findstr /i "hsm dsm" 2>&1',
        "$output_dir/hsm_services.txt",
        "HSM_Services"
    );
} elsif ($os =~ /linux/i) {
    run_command_to_file(
        'systemctl list-units | grep -i hsm 2>&1',
        "$output_dir/hsm_services.txt",
        "HSM_Services"
    );
} elsif ($os =~ /aix/i) {
    run_command_to_file(
        'lssrc -a | grep -i hsm 2>&1',
        "$output_dir/hsm_services.txt",
        "HSM_Services"
    );
} 


# -----------------------------------------------------------
# 11. HSM Environment Variables
# -----------------------------------------------------------

# Registry information
if ($os =~ /MSWin32/i) {
    run_command_to_file(
        'reg query "HKEY_LOCAL_MACHINE\SOFTWARE\IBM\ADSM\CurrentVersion\HsmClient" /s',
        "$output_dir/hsm_reg.txt",
        "HSM_Registry"
    );
}


# ===============================================================
# SUMMARY
# ===============================================================
close($errfh);

if ($verbose) {
    print "\n=== HSM Module Summary ===\n";
    foreach my $item (sort keys %collected_items) {
        printf "  %-30s : %s\n", $item, $collected_items{$item};
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

# Made with Bob
