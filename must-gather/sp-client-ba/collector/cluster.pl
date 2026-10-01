#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use Getopt::Long;

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$optfile,
) or die "Invalid arguments\n";

die "--output-dir required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/cluster";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Detect OS
# -----------------------------
my $os = env::_os();

# -----------------------------
# Error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!\n";
print $errfh "=== Starting Cluster Data Collection ===\n";

my %collected;

# ===============================================================
# Section 1 — Windows-only cluster data
# ===============================================================
if ($os =~ /MSWin32/i) {

    # ------------------------------------------------------------------
    # 1a. Microsoft Cluster log file
    # ------------------------------------------------------------------
    my $cluster_log_dir = $ENV{SystemRoot} ? "$ENV{SystemRoot}\\Cluster" : 'C:\Windows\Cluster\Reports';
    my $cluster_log     = "$cluster_log_dir\\cluster.log";

    if (-e $cluster_log) {
        my $dest = "$output_dir\\cluster.log";
        if (copy($cluster_log, $dest)) {
            $collected{"cluster.log"} = "Success";
            print $errfh "Collected: $cluster_log\n";
        } else {
            $collected{"cluster.log"} = "Failed";
            print $errfh "Error copying $cluster_log: $!\n";
        }
    } else {
        $collected{"cluster.log"} = "NOT FOUND";
        print $errfh "Warning: $cluster_log not found\n";
    }

    # ------------------------------------------------------------------
    # 1b. Windows event logs (Application, System, Cluster)  — .evtx
    # ------------------------------------------------------------------
    my %evtx_logs = (
        "Microsoft-Windows-FailoverClustering/Operational" => "Cluster_Operational.evtx",
    );

    foreach my $log_name (keys %evtx_logs) {
        my $out_file = "$output_dir\\$evtx_logs{$log_name}";
        my $cmd = "wevtutil epl \"$log_name\" \"$out_file\" 2>nul";
        my $rc  = system($cmd) >> 8;

        if ($rc == 0 && -s $out_file) {
            $collected{$evtx_logs{$log_name}} = "Success";
            print $errfh "Collected event log: $log_name\n";
        } else {
            $collected{$evtx_logs{$log_name}} = "Failed";
            print $errfh "Error collecting event log '$log_name' (exit code $rc)\n";
        }
    }

    # ------------------------------------------------------------------
    # 1c. DSMC SHOW CLUSTER (SP client cluster command)
    # ------------------------------------------------------------------
    my $base_path = env::get_ba_base_path();
    my $dsmc;

    $dsmc = `where dsmc.exe 2>nul`;
    chomp($dsmc);
    if (!$dsmc || !-e $dsmc) {
        $dsmc = "$base_path\\dsmc.exe" if -e "$base_path\\dsmc.exe";
    }

    if ($dsmc && -e $dsmc) {
        my $opt_file = $optfile ? $optfile : "$base_path\\dsm.opt";
        my $out_file = "$output_dir\\dsmc_show_cluster.txt";
        my $cmd = "\"$dsmc\" show cluster -optfile=\"$opt_file\" >\"$out_file\" 2>&1";
        my $rc  = system($cmd) >> 8;

        if ($rc == 0 && -s $out_file) {
            $collected{"dsmc_show_cluster.txt"} = "Success";
            print $errfh "Collected: dsmc show cluster\n";
        } else {
            $collected{"dsmc_show_cluster.txt"} = "Failed";
            print $errfh "Error running 'dsmc show cluster' (exit code $rc)\n";
        }
    } else {
        $collected{"dsmc_show_cluster.txt"} = "NOT FOUND";
        print $errfh "Warning: dsmc binary not found; skipping 'show cluster'\n";
    }

    # ------------------------------------------------------------------
    # 1d. PowerShell cluster commands
    # ------------------------------------------------------------------
    my %ps_cmds = (
        "Get-Cluster.txt"         => "Get-Cluster",
        "Get-ClusterNode.txt"     => "Get-ClusterNode",
        "Get-ClusterGroup.txt"    => "Get-ClusterGroup",
        "Get-ClusterResource.txt" => "Get-ClusterResource",
    );

    foreach my $out_name (sort keys %ps_cmds) {
        my $out_file = "$output_dir\\$out_name";
        my $ps_cmd   = $ps_cmds{$out_name};
        my $cmd;

        # cluster /status is a native exe; everything else is PowerShell
        if ($ps_cmd =~ /^cluster\s/) {
            $cmd = "$ps_cmd >\"$out_file\" 2>&1";
        } else {
            $cmd = "powershell -NoProfile -NonInteractive -Command \"$ps_cmd | Out-File -FilePath '$out_file' -Encoding UTF8\" 2>nul";
        }

        my $rc = system($cmd) >> 8;

        if ($rc == 0 && -s $out_file) {
            $collected{$out_name} = "Success";
            print $errfh "Collected: $ps_cmd\n";
        } else {
            $collected{$out_name} = "Failed";
            print $errfh "Error running '$ps_cmd' (exit code $rc)\n";
        }
    }

}
# ===============================================================
# Close error log
# ===============================================================
close($errfh);

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {
    print "\n=== Core Module Summary ===\n";
    if (%collected) {
        foreach my $file (sort keys %collected) {
            printf "  %-40s : %s\n", $file, $collected{$file};
        }
    } else {
        print "  No core or crash dump files found.\n";
    }
    print "Collected data saved in: $output_dir\n";
    print "Check script.log for any skipped or failed files.\n";
}

# -----------------------------
# Determine exit code for framework
# -----------------------------
my $success_count = grep { $collected{$_} eq "Success" } keys %collected;
my $total = scalar keys %collected;
my $exit_code;

if ($total == 0) {
    $exit_code = 0; # No dumps is not a failure
} elsif ($success_count == $total) {
    $exit_code = 0;
} elsif ($success_count > 0) {
    $exit_code = 2;
} else {
    $exit_code = 1;
}

exit($exit_code);
