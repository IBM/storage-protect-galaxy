#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use FindBin;
use File::Path qw(make_path);
use lib "$FindBin::Bin/../modules";   # include common modules
use system;
use utils;

# -----------------------------
# Parameters / CLI optfile
# -----------------------------
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/system";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print $errfh "=== Starting System Information Collection ===\n";
print $errfh "Output directory: $output_dir\n";

# -----------------------------
# Store module results
# -----------------------------
my %results;

# -----------------------------
# Collect OS info
# -----------------------------
eval {
    print $errfh "Collecting OS information...\n";
    $results{"os_info.txt"} = system::get_os_info();
    utils::write_to_file("$output_dir/os_info.txt", $results{"os_info.txt"});
    print $errfh "OS info collection completed.\n";
};
if ($@) { print $errfh "Error collecting OS info: $@\n"; }

# -----------------------------
# Collect Memory info
# -----------------------------
eval {
    print $errfh "Collecting memory information...\n";
    $results{"memory_info.txt"} = system::get_memory_info();
    utils::write_to_file("$output_dir/memory_info.txt", $results{"memory_info.txt"});
    print $errfh "Memory info collection completed.\n";
};
if ($@) { print $errfh "Error collecting memory info: $@\n"; }

# -----------------------------
# Collect Disk Usage
# -----------------------------
eval {
    print $errfh "Collecting disk usage...\n";
    $results{"disk_usage.txt"} = system::get_disk_usage();
    utils::write_to_file("$output_dir/disk_usage.txt", $results{"disk_usage.txt"});
    print $errfh "Disk usage collection completed.\n";
};
if ($@) { print $errfh "Error collecting disk usage: $@\n"; }

# -----------------------------
# Collect Processes
# -----------------------------
eval {
    print $errfh "Collecting process information...\n";
    $results{"processes.txt"} = system::get_processes();
    utils::write_to_file("$output_dir/processes.txt", $results{"processes.txt"});
    print $errfh "Process info collection completed.\n";
};
if ($@) { print $errfh "Error collecting processes: $@\n"; }

# -----------------------------
# Collect DSM Processes
# -----------------------------
eval {
    print $errfh "Collecting DSM processes...\n";
    $results{"dsm_processes.txt"} = system::get_dsm_processes($output_dir);
    utils::write_to_file("$output_dir/dsm_processes.txt", $results{"dsm_processes.txt"});
    print $errfh "DSM process collection completed.\n";
};
if ($@) { print $errfh "Error collecting DSM processes: $@\n"; }

# -----------------------------
# Collect Ulimit
# -----------------------------
if ($^O !~ /MSWin32/i){
    $results{"ulimit.txt"} = system::get_ulimit_all($output_dir);
    utils::write_to_file("$output_dir/ulimit.txt", $results{"ulimit.txt"});
}

# -----------------------------
# Linux: /etc/os-release
# -----------------------------
$results{"os_release.txt"} = system::get_os_release();
utils::write_to_file(
    "$output_dir/os_release.txt",
    $results{"os_release.txt"}
) if $results{"os_release.txt"};

# -----------------------------
# Linux: /var/log/messages
# -----------------------------
$results{"messages.log"} = system::get_linux_messages();
utils::write_to_file(
    "$output_dir/messages.log",
    $results{"messages.log"}
) if $results{"messages.log"};

# -----------------------------
# AIX: errpt -a
# -----------------------------
$results{"errpt.txt"} = system::get_errpt();
utils::write_to_file(
    "$output_dir/errpt.txt",
    $results{"errpt.txt"}
) if $results{"errpt.txt"};

# -----------------------------
# Windows-specific: VSS and Event Logs
# -----------------------------
if ($^O =~ /MSWin32/i) {
    eval {
        print $errfh "Collecting VSS and Event Logs (Windows only)...\n";

        # VSS Writers
        $results{"vss_writers.txt"} = system::get_vss_writers($output_dir);
        utils::write_to_file("$output_dir/vss_writers.txt", $results{"vss_writers.txt"}) if $results{"vss_writers.txt"};

        # VSS Providers
        $results{"vss_providers.txt"} = system::get_vss_providers($output_dir);
        utils::write_to_file("$output_dir/vss_providers.txt", $results{"vss_providers.txt"}) if $results{"vss_providers.txt"};

        # Event Logs
        $results{"system_eventlog.txt"}       = system::get_system_event_logs($output_dir);
        $results{"application_eventlog.txt"}  = system::get_application_event_logs($output_dir);
        $results{"security_eventlog.txt"}     = system::get_security_event_logs($output_dir);

        print "Collected System, Application, and Security event logs\n" if $verbose;
        print $errfh "Windows VSS and Event Logs collection completed.\n";
    };
    if ($@) { print $errfh "Error collecting VSS/Event logs: $@\n"; }
}

# -----------------------------
# Concise Summary
# -----------------------------
if ($verbose) {
    print "\n=== System Module Summary ===\n";
    foreach my $file (sort keys %results) {
        my $path = "$output_dir/$file";
        my $status = (-e $path && -s $path) ? "Success" : "Failed";
        printf "  %-25s : %s\n", $file, $status;
    }
    print "Collected system info is in: $output_dir\n";
    print "Check script.log for any issues.\n";
}

# -----------------------------
# Determine module-level status for framework
# -----------------------------
my $success_count = 0;
my $fail_count = 0;
my $total = scalar keys %results;

foreach my $file (keys %results) {
    my $path = "$output_dir/$file";
    if (-e $path && -s $path) {
        $success_count++;
    } else {
        $fail_count++;
        print $errfh "Warning: Missing or empty file - $file\n";
    }
}

my $module_status;
if ($success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

print $errfh "System module completed with status: $module_status\n";
close($errfh);

# -----------------------------
# Exit code mapping for framework (0=Success, 1=Failure, 2=Partial)
# -----------------------------
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);
