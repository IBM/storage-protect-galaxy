#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path);
use File::Copy qw(copy);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;

# ===============================================================
# Script Name : vmware.pl
# Description : Collects diagnostics for IBM Spectrum Protect
#               Data Protection for VMware (Windows + Linux)
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
$output_dir = "$output_dir/vmware";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup
# -----------------------------
my $os = env::_os();
my %collected;
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print $errfh "Detected OS: $os\n";

# ===============================================================
# WINDOWS COLLECTION
# ===============================================================
if ($os =~ /MSWin32/i) {

    # -----------------------------------------------------------
    # 1. VE / Web GUI / FLR / RecoveryAgent logs (COMMON)
    # -----------------------------------------------------------
    utils::collect_ve_component_logs(
        $output_dir,
        $errfh,
        \%collected
    );

    # -----------------------------------------------------------
    # 2. VM environment info
    # -----------------------------------------------------------
    my $show_vm = `dsmc show vm all 2>&1`;
    utils::write_to_file("$output_dir/show_vm.out", $show_vm);
    $collected{"show_vm.out"} = $show_vm ? "Success" : "Failed";

    # -----------------------------------------------------------
    # 3. vmcli inquire_config (all known locations)
    # -----------------------------------------------------------
    my @vmcli_paths = (
        "C:/Program Files/IBM/SpectrumProtect/Framework/VEGUI/scripts/vmcli.cmd",
        "C:/Program Files (x86)/Common Files/Tivoli/TDPVMware/VMwarePlugin/scripts/vmcli.cmd"
    );

    my $vmcli_found;
    foreach my $vmcli (@vmcli_paths) {
        next unless -f $vmcli;
        system("\"$vmcli\" -f inquire_config > \"$output_dir/inquire_config.out\" 2>&1");
        $collected{"inquire_config.out"} = (-s "$output_dir/inquire_config.out") ? "Success" : "Failed";
        $vmcli_found = 1;
        last;
    }
    $collected{"inquire_config.out"} ||= "Not Found";

    # -----------------------------------------------------------
    # 4. Installation logs
    # -----------------------------------------------------------
    my $all_users = $ENV{ALLUSERSPROFILE} || "C:/ProgramData";
    my $inst_log  = "$all_users/TDPVMwareInstallation.log";
    if (-f $inst_log) {
        copy($inst_log, "$output_dir/TDPVMwareInstallation.log");
        $collected{"TDPVMwareInstallation.log"} = "Success";
    } else {
        $collected{"TDPVMwareInstallation.log"} = "Not Found";
    }

}
# ===============================================================
# LINUX COLLECTION
# ===============================================================
else {

    # -----------------------------------------------------------
    # 1. VM environment info
    # -----------------------------------------------------------
    my $show_vm = `dsmc show vm all 2>&1`;
    utils::write_to_file("$output_dir/show_vm.out", $show_vm);
    $collected{"show_vm.out"} = $show_vm ? "Success" : "Failed";

    # -----------------------------------------------------------
    # 2. Web GUI / vmcli logs
    # -----------------------------------------------------------
    my @log_dirs = (
        "/opt/tivoli/tsm/tdpvmware/common/logs",
        "/opt/tivoli/tsm/tdpvmware/common/webserver/usr/servers/veProfile"
    );

    foreach my $dir (@log_dirs) {
        my ($name) = $dir =~ /([^\/]+)$/;
        if (-d $dir) {
            system("cp -r \"$dir\" \"$output_dir/$name\" 2>>\"$error_log\"");
            $collected{$name} = "Success";
        } else {
            $collected{$name} = "Not Found";
        }
    }

    # -----------------------------------------------------------
    # 3. vmcli artifacts
    # -----------------------------------------------------------
    my $vmcli = "/opt/tivoli/tsm/tdpvmware/common/scripts/vmcli";
    if (-x $vmcli) {
        system("\"$vmcli\" -f inquire_config > \"$output_dir/inquire_config.out\" 2>&1");
        $collected{"inquire_config.out"} = (-s "$output_dir/inquire_config.out") ? "Success" : "Failed";
    } else {
        $collected{"inquire_config.out"} = "Not Found";
    }

    my @files = (
        "/opt/tivoli/tsm/tdpvmware/common/regtool.log",
        "/opt/tivoli/tsm/tdpvmware/common/scripts/vmcliprofile"
    );

    foreach my $f (@files) {
        my ($name) = $f =~ /([^\/]+)$/;
        if (-f $f) {
            copy($f, "$output_dir/$name");
            $collected{$name} = "Success";
        } else {
            $collected{$name} = "Not Found";
        }
    }

    # -----------------------------------------------------------
    # 4. Recovery Agent / Mount
    # -----------------------------------------------------------
    my @ra_paths = (
        "$ENV{HOME}/tivoli/tsm/ve/mount/log",
        "/opt/tivoli/tsm/tdpvmware/mount/engine/var",
        "/opt/tivoli/tsm/tdpvmware/mount/Mount.cfg"
    );

    foreach my $path (@ra_paths) {
        my ($name) = $path =~ /([^\/]+)$/;
        if (-d $path) {
            system("cp -r \"$path\" \"$output_dir/$name\" 2>>\"$error_log\"");
            $collected{"RA_$name"} = "Success";
        } elsif (-f $path) {
            copy($path, "$output_dir/$name");
            $collected{"RA_$name"} = "Success";
        } else {
            $collected{"RA_$name"} = "Not Found";
        }
    }

    # -----------------------------------------------------------
    # 5. Linux diagnostics
    # -----------------------------------------------------------
    my %cmds = (
        "df -h"                => "df_h.txt",
        "mount"                => "mount.txt",
        "ps -ef"               => "ps_ef.txt",
        "rpm -qa | grep iscsi" => "iscsi.txt",
    );

    foreach my $cmd (keys %cmds) {
        system("$cmd > \"$output_dir/$cmds{$cmd}\" 2>&1");
        $collected{$cmds{$cmd}} = "Success";
    }
}

# ===============================================================
# SUMMARY
# ===============================================================
if ($verbose) {
    print "\n=== VMware Module Summary ===\n";
    foreach my $k (sort keys %collected) {
        printf "  %-35s : %s\n", $k, $collected{$k};
    }
    print "Collected data saved in: $output_dir\n";
}

close($errfh);

# ===============================================================
# EXIT CODE
# ===============================================================
my $success = grep { $collected{$_} eq "Success" } keys %collected;
my $total   = scalar keys %collected;
exit(($success == $total) ? 0 : 2);
