package system;
use strict;
use warnings;
use Exporter 'import';
use env;
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use utils;


our @EXPORT_OK = qw(
    get_os_info
    get_memory_info
    get_disk_usage
    get_processes
    get_dsm_processes
    get_vss_writers
    get_vss_providers
    get_event_logs
    get_system_event_logs
    get_application_event_logs
    get_security_event_logs
    get_ulimit_all
    get_os_release
    get_errpt
    get_linux_messages
);

###############################################################################
# get_os_info
###############################################################################
sub get_os_info {
    my $os = lc(env::_os());

    if ($os =~ /MSWin32/i) {
        return `ver 2>NUL`;
    } elsif ($os =~ /sunos/i) {
        return `uname -a 2>/dev/null; showrev -a 2>/dev/null`;
    } else {
        return `uname -a 2>/dev/null`;
    }
}

###############################################################################
# get_memory_info
###############################################################################
sub get_memory_info {
    my $os = lc(env::_os());

    if ($os =~ /aix/) {
        return `svmon -G 2>/dev/null`;
    } elsif ($os =~ /linux/) {
        my $output = `free -m 2>/dev/null`;
        if ($? != 0 || $output eq '') {
            $output = `grep -E 'MemTotal|MemFree|MemAvailable' /proc/meminfo 2>/dev/null`;
        }
        return $output;
    } elsif ($os =~ /darwin/) {
        return `vm_stat 2>/dev/null`;
    } elsif ($os =~ /sunos/) {
        return `prtconf | grep Memory 2>/dev/null`;
    } elsif ($os =~ /MSWin32/i) {
        return `systeminfo | find "Memory" 2>NUL`;
    } else {
        return "Memory info not supported on $os\n";
    }
}

###############################################################################
# get_disk_usage
###############################################################################
sub get_disk_usage {
    my $os = lc(env::_os());

    if ($os =~ /MSWin32/i) {
        return `wmic logicaldisk get size,freespace,caption 2>NUL`;
    } elsif ($os =~ /aix|linux|darwin|sunos|solaris/) {
        my $output = `df -h 2>/dev/null`;
        return $output ne '' ? $output : "Disk usage command failed on $os\n";
    } else {
        return "Disk usage not supported on $os\n";
    }
}

###############################################################################
# get_processes
###############################################################################
sub get_processes {
    my $os = lc(env::_os());

    if ($os =~ /aix|linux|sunos|solaris/) {
        return `ps -ef | head -30 2>/dev/null`;
    } elsif ($os =~ /darwin/) {
        return `ps aux | head -30 2>/dev/null`;
    } elsif ($os =~ /MSWin32/i) {
        return `sc query state= all type= service 2>NUL`;
    } else {
        return "Process listing not supported on $os\n";
    }
}

###############################################################################
# get_dsm_processes
###############################################################################
sub get_dsm_processes {
    my $os = lc(env::_os());
    my $output_dir = shift || ".";

    if ($os =~ /aix|linux|sunos|solaris/) {
        return `ps -ef | grep dsm 2>/dev/null`;
    } elsif ($os =~ /darwin/) {
        return `ps aux | grep dsm 2>/dev/null`;
    } elsif ($os =~ /MSWin32/i) {
        make_path($output_dir) unless -d $output_dir;

        my $output = "";
        my @lines = `sc query state= all type= service 2>&1`;
        my ($svc_name, $display_name, $state);

         # Add header line
        $output .= sprintf("%-40s | %-50s | %s\n", 
                           "SERVICE NAME", "DISPLAY NAME", "STATE");
        $output .= sprintf("%s\n", "-" x 110);
 
        foreach my $line (@lines) {
            chomp $line;
            if ($line =~ /^SERVICE_NAME:\s*(.+)/) {
                $svc_name = $1;
            } elsif ($line =~ /^DISPLAY_NAME:\s*(.+)/) {
                $display_name = $1;
            } elsif ($line =~ /^\s*STATE\s*:\s*\d+\s+(\S+)/) {
                $state = $1;

                if ($display_name =~ /IBM|TSM|Spectrum/i || $svc_name =~ /TSM|IBM/i) {
                    $output .= sprintf("%-40s | %-50s | %s\n",
                        $svc_name, $display_name, $state);
                }
            }
        }
        return $output;
    } else {
        return "DSM process listing not supported on $os\n";
    }
}

###############################################################################
# get_vss_writers
# Purpose: Collect list of Volume Shadow Copy writers (Windows only)
###############################################################################
sub get_vss_writers {
    my $output_dir = shift || ".";
    my $os = lc(env::_os());
    return if $os !~ /MSWin32/i;

    make_path($output_dir) unless -d $output_dir;
    my $output = `vssadmin list writers 2>NUL`;
    utils::write_to_file("$output_dir/vss_writers.txt", $output);
    return $output;
}

###############################################################################
# get_vss_providers
# Purpose: Collect list of Volume Shadow Copy providers (Windows only)
###############################################################################
sub get_vss_providers {
    my $output_dir = shift || ".";
    my $os = lc(env::_os());
    return if $os !~ /MSWin32/i;

    make_path($output_dir) unless -d $output_dir;
    my $output = `vssadmin list providers 2>NUL`;
    utils::write_to_file("$output_dir/vss_providers.txt", $output);
    return $output;
}

###############################################################################
# get_system_event_logs
# Purpose  : Collect System event logs (Windows only)
# Behavior : Collects last 100 entries from System log using wevtutil
###############################################################################
sub get_system_event_logs {
    my $output_dir = shift || ".";
    my $os = lc(env::_os());
    return if $os !~ /MSWin32/i;

    my $outfile = "$output_dir/system_eventlog.txt";
    system("wevtutil qe System /c:100 /f:text > \"$outfile\" 2>NUL");

    if (-e $outfile && -s $outfile) {
        return "System Event Logs collected successfully";
    } else {
        return "System Event Logs collection failed or empty";
    }
}

###############################################################################
# get_application_event_logs
# Purpose  : Collect Application event logs (Windows only)
# Behavior : Collects last 100 entries from Application log using wevtutil
###############################################################################
sub get_application_event_logs {
    my $output_dir = shift || ".";
    my $os = lc(env::_os());
    return if $os !~ /MSWin32/i;

    my $outfile = "$output_dir/application_eventlog.txt";
    system("wevtutil qe Application /c:100 /f:text > \"$outfile\" 2>NUL");

    if (-e $outfile && -s $outfile) {
        return "Application Event Logs collected successfully";
    } else {
        return "Application Event Logs collection failed or empty";
    }
}

###############################################################################
# get_security_event_logs
# Purpose  : Collect Security event logs (Windows only)
# Behavior : Collects last 100 entries from Security log using wevtutil
###############################################################################
sub get_security_event_logs {
    my $output_dir = shift || ".";
    my $os = lc(env::_os());
    return if $os !~ /MSWin32/i;

    my $outfile = "$output_dir/security_eventlog.txt";
    system("wevtutil qe Security /c:100 /f:text > \"$outfile\" 2>NUL");

    if (-e $outfile && -s $outfile) {
        return "Security Event Logs collected successfully";
    } else {
        return "Security Event Logs collection failed or empty";
    }
}

# Linux: /etc/os-release
sub get_os_release {
    my $os = lc(env::_os());
    return if $os !~ /linux/;
    return `cat /etc/os-release 2>/dev/null`;
}

# AIX: errpt -a
sub get_errpt {
    my $os = lc(env::_os());
    return if $os !~ /aix/;
    return `errpt -a 2>/dev/null`;
}

# Linux: /var/log/messages
sub get_linux_messages {
    my $os = lc(env::_os());
    return if $os !~ /linux/;
    return (-e "/var/log/messages")
        ? `cat /var/log/messages 2>/dev/null`
        : "File /var/log/messages not found\n";
}

#################################################################################
# get_ulimit_all()
# Purpose: Retrieve and display all current user-level resource limits for the system.
# Behavior: Executes a system command to list resource limits such as file size, open files, stack size, and process limits.
#################################################################################
sub get_ulimit_all {
    my $output_dir = shift || ".";
    my $os = lc(env::_os());
    return if $os =~ /mswin32/i;  # Not applicable on Windows

    make_path($output_dir) unless -d $output_dir;

    my $outfile = "$output_dir/ulimit.txt";

    # Use a shell so ulimit (builtin) works everywhere
    my $output = `sh -c 'ulimit -a' 2>&1`;

    if ($output && $output !~ /not found/i) {
        utils::write_to_file($outfile, $output);
        return $output;
    } else {
        utils::write_to_file($outfile,
            "Failed to collect ulimit -a\n$output");
        return "Failed to collect ulimit -a\n";
    }
}

