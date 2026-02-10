#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use network qw(run_ping run_port_check run_firewall run_tcpdump run_netstat);
use env;
use utils;

# ===============================================================
# Script Name : network_info.pl
# Description : Collects network-related diagnostic information
# ===============================================================

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $server_ip, $port);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "server-ip|s=s"  => \$server_ip,
    "port|p=i"       => \$port,
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/network";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup environment
# -----------------------------
my $os = env::_os();
my %collected_files;
my $error_log = "$output_dir/script.log";

# Create or open script.log
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print "\n=== Starting Network Information Collection ===\n" if $verbose;
print $errfh "Detected OS: $os\n";
print $errfh "Output directory: $output_dir\n";

$port ||= 1500;

# -----------------------------
# 1. Ping Test
# -----------------------------
if ($server_ip) {
    eval {
        print $errfh "Running ping test to $server_ip\n";
        run_ping($server_ip, $output_dir);
        $collected_files{"ping_test.txt"} = "Success";
    };
    if ($@) {
        print $errfh "Ping test failed: $@\n";
        $collected_files{"ping_test.txt"} = "Failed";
    }
} else {
    print $errfh "Warning: No server IP provided, skipping ping test.\n";
    $collected_files{"ping_test.txt"} = "Skipped";
}

# -----------------------------
# 2. Port Check
# -----------------------------
if ($server_ip) {
    eval {
        print $errfh "Running port connectivity test to $server_ip:$port\n";
        run_port_check($server_ip, $output_dir, $port);
        $collected_files{"port_test.txt"} = "Success";
    };
    if ($@) {
        print $errfh "Port test failed: $@\n";
        $collected_files{"port_test.txt"} = "Failed";
    }
} else {
    print $errfh "Warning: No server IP provided, skipping port check.\n";
    $collected_files{"port_test.txt"} = "Skipped";
}

# -----------------------------
# 3. Firewall Rules
# -----------------------------
eval {
    print $errfh "Collecting firewall configuration...\n";
    run_firewall($output_dir);
    $collected_files{"firewall_test.txt"} = "Success";
};
if ($@) {
    print $errfh "Firewall collection failed: $@\n";
    $collected_files{"firewall_test.txt"} = "Failed";
}

# -----------------------------
# 4. Netstat
# -----------------------------
eval {
    print $errfh "Running netstat to capture open ports and connections...\n";
    run_netstat($output_dir);
    $collected_files{"netstat.txt"} = "Success";
};
if ($@) {
    print $errfh "Netstat collection failed: $@\n";
    $collected_files{"netstat.txt"} = "Failed";
}


# -----------------------------
# 5. TCPDump
# -----------------------------
eval {
    print $errfh "Running limited TCP capture on port $port...\n";
    run_tcpdump($output_dir, $port);
    $collected_files{"tcpdump.txt"} = "Success";
};
if ($@) {
    print $errfh "TCPDump collection failed: $@\n";
    $collected_files{"tcpdump.txt"} = "Failed";
}

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {
    print "\n=== Network Module Summary ===\n";
    foreach my $file (sort keys %collected_files) {
        printf "  %-30s : %s\n", $file, $collected_files{$file};
    }
    print "Collected system info is in: $output_dir\n";
    print "Check script.log for any issues.\n";
}

close($errfh);

# -----------------------------
# Exit Code
# -----------------------------
my $success_count = grep { $collected_files{$_} eq "Success" } keys %collected_files;
my $total = scalar keys %collected_files;
my $exit_code = ($success_count == $total) ? 0 : 2;
exit($exit_code);
