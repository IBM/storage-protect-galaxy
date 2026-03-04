#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy;
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use system;
use utils;
use Getopt::Long;

# ===============================================================
# Script Name : oracle.pl
# Description : Collects Oracle-specific diagnostic data for
#               IBM Storage Protect for Databases - Data Protection for Oracle
# ===============================================================

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $optfile, $rman_script, $rman_msglog, $oracle_user);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$optfile,
    "rman-script=s"  => \$rman_script,
    "rman-msglog=s"  => \$rman_msglog,
    "oracle-user=s"  => \$oracle_user,
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/oracle";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Get base path of Oracle client
# -----------------------------
my $base_oracle_path = env::get_oracle_base_path();
my $os = env::_os();

# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print $errfh "=== Starting Oracle-Specific Data Collection ===\n";
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
            $collected_items{$dest_filename} = "Success";
            print $errfh "Collected $item_name from: $source_path\n" if $verbose;
        } else {
            print $errfh "Error: Could not copy $item_name: $!\n";
            $collected_items{$dest_filename} = "Failed";
        }
    } else {
        print $errfh "Warning: $item_name not found at: $source_path\n";
        $collected_items{$dest_filename} = "NOT FOUND";
    }
}

# Helper function to run system commands and collect output
sub run_system_command {
    my ($cmd, $output_file, $item_name) = @_;
    
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
# SECTION 1: TDP Oracle Configuration
# =============================
print $errfh "=== Section 1: TDP Oracle Configuration ===\n" if $verbose;

# 1.1 Determine which tdpo.opt to use 
my $tdpo_opt_file;
if ($optfile) {
    $tdpo_opt_file = $optfile;
} else {
    $tdpo_opt_file = "$base_oracle_path/tdpo.opt";
}

# 1.2 Collect tdpo.opt file
collect_text_file($tdpo_opt_file, "tdpo.opt", "tdpo.opt");

# 1.3 Locate tdpoconf binary
my $tdpoconf;
if ($os =~ /MSWin32/i) {
    $tdpoconf = `where tdpoconf.exe 2>nul`;
    chomp($tdpoconf);
    if (!$tdpoconf || !-e $tdpoconf) {
        $tdpoconf = "$base_oracle_path\\tdpoconf.exe" if -e "$base_oracle_path\\tdpoconf.exe";
    }
} else {
    $tdpoconf = `which tdpoconf 2>/dev/null`;
    chomp($tdpoconf);
    if (!$tdpoconf || !-x $tdpoconf) {
        $tdpoconf = "$base_oracle_path/tdpoconf" if -x "$base_oracle_path/tdpoconf";
    }
}

# Helper function to run tdpoconf commands
sub run_tdpoconf_command {
    my ($command, $output_file, $item_name) = @_;
    
    return unless $tdpoconf && -x $tdpoconf;
    
    my $cmd = "\"$tdpoconf\" $command >\"$output_file\" 2>&1";
    print $errfh "Executing: $cmd\n" if $verbose;
    
    my $status = system($cmd);
    $status >>= 8;
    
    if ($status == 0 && -s $output_file) {
        $collected_items{$item_name} = "Success";
        print $errfh "Collected $item_name output\n" if $verbose;
    } else {
        print $errfh "Warning: $command failed or returned no data\n";
        $collected_items{$item_name} = "Failed";
    }
}

# 1.4 Collect tdpoconf showenv output
if ($tdpoconf && -x $tdpoconf) {
    run_tdpoconf_command("showenv", "$output_dir/tdpoconf_showenv.txt", "tdpoconf_showenv");
} else {
    print $errfh "Warning: tdpoconf not found\n";
    $collected_items{"tdpoconf_showenv"} = "NOT FOUND";
}

# 1.6 Collect dsm.opt file (specified in tdpo.opt via DSMI_ORC_CONFIG)
my $dsm_opt_path;

if (-e $tdpo_opt_file && open(my $fh, '<', $tdpo_opt_file)) {
    while (<$fh>) {
        next if /^\s*[;#]/;

        if (/^\s*DSMI_ORC_CONFIG\s+(.+)/i) {
            $dsm_opt_path = $1;
            $dsm_opt_path =~ s/^\s+|\s+$//g;  # trim leading/trailing spaces

            print $errfh "Found DSMI_ORC_CONFIG: $dsm_opt_path\n" if $verbose;
            last;
        }
    }
    close $fh;
}

if ($dsm_opt_path) {
    collect_text_file($dsm_opt_path, "oracle_dsm.opt", "dsm.opt");
} else {
    print $errfh "Warning: dsm.opt not found (DSMI_ORC_CONFIG not set or file missing)\n";
    $collected_items{"dsm.opt"} = "NOT FOUND";
}

# 1.7 Collect dsm.sys (UNIX only)
if ($os !~ /MSWin32/i) {
    collect_text_file("$base_oracle_path/dsm.sys", "oracle_dsm.sys", "dsm.sys");
}

# =============================
# SECTION 2: Log Files Collection
# =============================
print $errfh "\n=== Section 2: Log Files Collection ===\n" if $verbose;

sub collect_log_file {
    my ($filename, $source_path) = @_;

    if (-e $source_path) {

        my $dest = "$output_dir/$filename";

        if (copy($source_path, $dest)) {
            $collected_items{$filename} = "Success";
            print $errfh "Collected $filename\n" if $verbose;
        }
        else {
            print $errfh "Error: Could not copy $filename: $!\n";
            $collected_items{$filename} = "Failed";
        }

    }
    else {
        print $errfh "Warning: $filename not found at: $source_path\n";
        $collected_items{$filename} = "NOT FOUND";
    }
}

# -----------------------------
# Detect DSMI_LOG from tdpo.opt
# -----------------------------
my $tdpo_log_dir;

if (-e $tdpo_opt_file && open(my $fh, '<', $tdpo_opt_file)) {

    while (<$fh>) {

        next if /^\s*$/ || /^[#;]/;

        if (/^\s*DSMI_LOG\s+(.+)/i) {

            $tdpo_log_dir = utils::clean_path($1);
            print $errfh "Found DSMI_LOG: $tdpo_log_dir\n" if $verbose;
        }
    }

    close($fh);
}

# -----------------------------
# Resolve BA log paths
# -----------------------------
my ($errorlog_path, $schedlog_path, $instrlog_path);

my $opt_file = $dsm_opt_path;
my $dsm_sys  = "$base_oracle_path/dsm.sys";

my $active_server;

if ($opt_file && -e $opt_file && open(my $fh, '<', $opt_file)) {

    while (<$fh>) {

        next if /^\s*$/ || /^[#;]/;

        if (/^\s*SERVERNAME\s+(\S+)/i) {
            $active_server = $1;
            last;
        }
    }

    close $fh;
}

foreach my $conf (grep { defined && -f } ($opt_file, $dsm_sys)) {

    open(my $fh, '<', $conf) or next;

    my $in_target_stanza = 0;

    while (<$fh>) {

        next if /^\s*$/ || /^[#;]/;

        if (/^\s*SERVERNAME\s+(\S+)/i) {

            my $current = $1;

            if ($active_server) {
                $in_target_stanza = ($current eq $active_server) ? 1 : 0;
            }
            else {
                $in_target_stanza = 1 if !$in_target_stanza;
            }

            next;
        }

        if ($in_target_stanza && /^\s*ERRORLOGNAME\s+(.+)/i) {
            $errorlog_path = utils::clean_path($1);
        }

        if ($in_target_stanza && /^\s*SCHEDLOGNAME\s+(.+)/i) {
            $schedlog_path = utils::clean_path($1);
        }

        if ($in_target_stanza && /^\s*INSTRLOGNAME\s+(.+)/i) {
            $instrlog_path = utils::clean_path($1);
        }
    }

    close($fh);
}

# -----------------------------
# Collect BA logs
# -----------------------------
collect_log_file(
    "dsmerror.log",
    $errorlog_path || "$base_oracle_path/dsmerror.log"
);

collect_log_file(
    "dsmsched.log",
    $schedlog_path || "$base_oracle_path/dsmsched.log"
);

collect_log_file(
    "dsminstr.log",
    $instrlog_path || "$base_oracle_path/dsminstr.log"
);

# -----------------------------
# Collect TDPO log
# -----------------------------
my $tdpo_log = $tdpo_log_dir
    ? "$tdpo_log_dir/tdpoerror.log"
    : "$base_oracle_path/tdpoerror.log";

collect_log_file(
    "tdpoerror.log",
    $tdpo_log
);

# =============================
# SECTION 3: Oracle Database Information
# =============================
print $errfh "\n=== Section 3: Oracle Database Information ===\n" if $verbose;


# 3.1 Oracle Info
my $oracle_info_file = "$output_dir/oracle_info.txt";
open(my $oracle_fh, '>', $oracle_info_file);

if ($oracle_fh) {

    print $oracle_fh "=== Running Oracle Instances ===\n";

    if ($os !~ /MSWin32/i) {
        print $oracle_fh `ps -ef | grep pmon | grep -v grep`;
    }

    print $oracle_fh "\nORACLE_HOME=$ENV{ORACLE_HOME}\n" if $ENV{ORACLE_HOME};
    print $oracle_fh "ORACLE_SID=$ENV{ORACLE_SID}\n" if $ENV{ORACLE_SID};

    close $oracle_fh;
    $collected_items{"oracle_info"} = "Success";
}

# 3.2 Collect Oracle-specific environment variables

run_system_command(
    ($os =~ /MSWin32/i ? "set" : "env") .
    " > \"$output_dir/oracle_environment.txt\" 2>&1",
    "$output_dir/oracle_environment.txt",
    "oracle_environment"
);

if ($oracle_user && $os !~ /MSWin32/i) {
    run_system_command(
        "su - $oracle_user -c env > \"$output_dir/env_oracle_user.txt\" 2>&1",
        "$output_dir/env_oracle_user.txt",
        "env_oracle_user"
    );
} else {
    $collected_items{"env_oracle_user"} = "Skipped";
}

# =============================
# SECTION 4: RMAN Script Collection (Interactive)
# =============================
print $errfh "\n=== Section 4: RMAN Script Collection ===\n" if $verbose;

# -----------------------------
# RMAN Script
# -----------------------------
if ($rman_script) {
    $rman_script = utils::clean_path($rman_script);
    collect_log_file(
        (split(/[\/\\]/, $rman_script))[-1],
        $rman_script
    );
} else {
    $collected_items{"rman_script"} = "Skipped";
}

# -----------------------------
# RMAN Msglog
# -----------------------------
if ($rman_msglog) {
    $rman_msglog = utils::clean_path($rman_msglog);
    collect_log_file(
        (split(/[\/\\]/, $rman_msglog))[-1],
        $rman_msglog
    );
} else {
    $collected_items{"rman_msglog"} = "Skipped";
}

# =============================
# SECTION 5: Platform-Specific Oracle Data
# =============================
print $errfh "\n=== Section 5: Platform-Specific Oracle Data ===\n" if $verbose;

if ($os =~ /aix/i) {
    print $errfh "Collecting AIX-specific Oracle information...\n" if $verbose;
    run_system_command("lslpp -L tivoli.tsm.* >\"$output_dir/lslpp_tivoli_tsm.txt\" 2>&1",
                       "$output_dir/lslpp_tivoli_tsm.txt", "lslpp_tivoli_tsm");
    run_system_command("find / -name 'libobk*' -exec ls -l {} \\; 2>/dev/null >\"$output_dir/libobk_search.txt\"",
                       "$output_dir/libobk_search.txt", "libobk_search");

} elsif ($os =~ /solaris/i) {
    print $errfh "Collecting Solaris-specific Oracle information...\n" if $verbose;
    run_system_command("pkginfo -l TDPoracle32 >\"$output_dir/pkginfo_TDPoracle32.txt\" 2>&1",
                       "$output_dir/pkginfo_TDPoracle32.txt", "pkginfo_TDPoracle32");
    run_system_command("pkginfo -l TDPoracle64 >\"$output_dir/pkginfo_TDPoracle64.txt\" 2>&1",
                       "$output_dir/pkginfo_TDPoracle64.txt", "pkginfo_TDPoracle64");
    run_system_command("pkginfo -l TIVsmCapi >\"$output_dir/pkginfo_TIVsmCapi.txt\" 2>&1",
                       "$output_dir/pkginfo_TIVsmCapi.txt", "pkginfo_TIVsmCapi");
    run_system_command("find / -name 'libobk*' -exec ls -l {} \\; 2>/dev/null >\"$output_dir/libobk_search.txt\"",
                       "$output_dir/libobk_search.txt", "libobk_search");

} elsif ($os =~ /linux/i) {
    print $errfh "Collecting Linux-specific Oracle information...\n" if $verbose;
    run_system_command("rpm -qai TIV* >\"$output_dir/rpm_TIV.txt\" 2>&1",
                       "$output_dir/rpm_TIV.txt", "rpm_TIV");
    run_system_command("rpm -qai TDP* >\"$output_dir/rpm_TDP.txt\" 2>&1",
                       "$output_dir/rpm_TDP.txt", "rpm_TDP");
    run_system_command("find / -name 'libobk*' -exec ls -l {} \\; 2>/dev/null >\"$output_dir/libobk_search.txt\"",
                       "$output_dir/libobk_search.txt", "libobk_search");

} elsif ($os =~ /MSWin32/i) {
    print $errfh "Collecting Windows-specific Oracle information...\n" if $verbose;
    run_system_command("reg query HKLM\\software\\ibm\\adsm\\currentversion /s >\"$output_dir/registry_ibm_adsm.txt\" 2>&1",
                       "$output_dir/registry_ibm_adsm.txt", "registry_ibm_adsm");
    run_system_command("dir /a /s /b c:\\ 2>nul | findstr /i orasbt.dll >\"$output_dir/orasbt_dll_search.txt\" 2>&1",
                       "$output_dir/orasbt_dll_search.txt", "orasbt_dll_search");

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
    print "\n=== Oracle Module Summary ===\n";
    foreach my $item (sort keys %collected_items) {
        printf "  %-30s : %s\n", $item, $collected_items{$item};
    }
    print "Collected Oracle data saved in: $output_dir\n";
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

# 
