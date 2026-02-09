#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;

# ===============================================================
# Script Name : hyperv_info.pl
# Description : Collects Hyper-V diagnostics for IBM Spectrum Protect
#               for Virtual Environments - Data Protection for Hyper-V.
# ===============================================================

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments. Use --output-dir <dir>.\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/hyperv_info";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup
# -----------------------------
my $os = env::_os();
my %collected_files;
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";
print $errfh "Detected OS: $os\n";

# ===============================================================
# Windows only
# ===============================================================
if ($os !~ /MSWin32/i) {
    print $errfh "Hyper-V diagnostics are applicable only on Windows.\n";
    $collected_files{"Hyper-V"} = "Not Applicable";
    close($errfh);
    exit(0);
}

# ===============================================================
# PowerShell check
# ===============================================================
my $ps = `where powershell.exe 2>nul`;
chomp($ps);
unless ($ps && -f $ps) {
    print $errfh "PowerShell not found. Skipping Hyper-V collection.\n";
    $collected_files{"PowerShell"} = "Missing";
    close($errfh);
    exit(0);
}

# ===============================================================
# 1. Hyper-V PowerShell information
# ===============================================================
my $ps_dir = "$output_dir/powershell";
make_path($ps_dir);

my %ps_cmds = (
    "Get-Service -Name vm* | fl"               => "vm_services.txt",
    "Get-VMIntegrationService -VMName * | fl" => "integration_services.txt",
    "Get-VM | Select Name,Path | fl"           => "vm_inventory.txt",
);

foreach my $cmd (keys %ps_cmds) {
    my $outfile = "$ps_dir/$ps_cmds{$cmd}";
    system("powershell -Command \"$cmd\" > \"$outfile\" 2>&1");
    $collected_files{$ps_cmds{$cmd}} = (-s $outfile) ? "Success" : "Failed";
}

# ===============================================================
# 2. Export ADSM registry
# ===============================================================
my $reg_out = "$output_dir/ADSM_registry.txt";
system("reg export \"HKLM\\SOFTWARE\\IBM\\ADSM\" \"$reg_out\" /y >nul 2>&1");
$collected_files{"ADSM_registry.txt"} = (-s $reg_out) ? "Success" : "Failed";

# ===============================================================
# 3. VE / Webserver / TSMCLI / RecoveryAgent logs
#    (Common logic – summary-safe)
# ===============================================================
utils::collect_ve_component_logs(
    $output_dir,
    $errfh,
    \%collected_files
);

# ===============================================================
# 4. Cluster logs (if present)
# ===============================================================
my $cluster_dir = "$output_dir/cluster_logs";
make_path($cluster_dir);

system(
    "powershell -Command \"if (Get-Cluster -ErrorAction SilentlyContinue) { cluster log /g >nul }\" 2>nul"
);

if (-d "C:/Windows/Cluster/Reports") {
    system(
        "xcopy \"C:/Windows/Cluster/Reports\" \"$cluster_dir\" /E /I /Q >nul 2>&1"
    );
    $collected_files{"Cluster_Logs"} = "Success";
} else {
    $collected_files{"Cluster_Logs"} = "Not Found";
}

# ===============================================================
# 5. DSMC show vm
# ===============================================================
my $show_vm = `dsmc show vm all 2>&1`;
utils::write_to_file("$output_dir/show_vm.out", $show_vm);
$collected_files{"show_vm.out"} = $show_vm ? "Success" : "Failed";

# ===============================================================
# Summary
# ===============================================================
if ($verbose) {
    print "\n=== Hyper-V Module Summary ===\n";
    foreach my $k (sort keys %collected_files) {
        printf "  %-30s : %s\n", $k, $collected_files{$k};
    }
    print "Collected data saved in: $output_dir\n";
}

close($errfh);

# Exit code logic unchanged
my $success = grep { $collected_files{$_} eq "Success" } keys %collected_files;
my $total   = scalar keys %collected_files;
exit(($success == $total) ? 0 : 2);
