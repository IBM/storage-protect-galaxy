package network;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(run_ping run_port_check run_firewall run_tcpdump run_netstat);
use env;
use utils;
use File::Path qw(make_path);

my $sudo_password;

###############################################################################
# _get_sudo_password
#
# Purpose  : Prompt once for sudo password if required for privileged commands.
# Input    : None
# Output   : Password string (stored in global $sudo_password)
###############################################################################
sub _get_sudo_password { 
    return $sudo_password if defined $sudo_password;

    print "Enter sudo password (press Enter to skip): ";

    # Disable echo using stty (POSIX, no external Perl module)
    if ($^O !~ /MSWin32/i) {
        system("stty -echo");
    }

    chomp(my $pw = <STDIN>);

    if ($^O !~ /MSWin32/i) {
        system("stty echo");
    }
    print "\n";

    # IMPORTANT: store even empty input
    $sudo_password = $pw;   # empty string means "skip sudo"

    return $sudo_password;
}

###############################################################################
# run_ping
#
# Purpose  : Verify network connectivity to a server using ping.
# Input    : $server_ip (string), $out_dir (output directory for results)
# Output   : ping_test.txt saved in $out_dir
###############################################################################
sub run_ping {
    my $os = env::_os();
    my ($server_ip, $out_dir) = @_;
    my $cmd;

    if ($os =~ /MSWin32/i) {
        $cmd = "ping -n 4 $server_ip";
    } else {
        $cmd = "ping -c 4 $server_ip";
    }

    utils::run_to_file($cmd, "$out_dir/ping_test.txt");
}


###############################################################################
# run_port_check
#
# Purpose  : Test connectivity to server port (default 1500).
# Input    : $server_ip (string), $out_dir (output directory for results)
# Output   : port_test.txt saved in $out_dir
###############################################################################
sub run_port_check {
    my $os = env::_os();
    my ($server_ip, $out_dir,$port) = @_;
    my $cmd;
    if ($os =~ /MSWin32/i) {
        $cmd = "powershell -Command \"Test-NetConnection -ComputerName $server_ip -Port $port\"";
    } elsif ($os =~ /linux|aix|darwin|sunos|solaris/i) {
        # Use nc (netcat) if available, otherwise fallback to nmap if installed
        if (`which nc 2>/dev/null`) {
            $cmd = "nc -zv $server_ip $port 2>&1";
        } elsif (`which nmap 2>/dev/null`) {
            $cmd = "nmap -p $port $server_ip 2>&1";
        } else {
            $cmd = "echo 'Neither nc nor nmap available for port check'";
        }
    }

    utils::run_to_file($cmd, "$out_dir/port_test.txt");
}

###############################################################################
# run_firewall
#
# Purpose  : Collect firewall configuration rules.
# Input    : $out_dir (output directory for results)
# Output   : firewall_test.txt saved in $out_dir
###############################################################################
sub run_firewall {
    my $os = env::_os();
    my ($out_dir) = @_;
    my $cmd;

    if ($os =~ /MSWin32/i) {
        $cmd = "netsh advfirewall firewall show rule name=all";
    } elsif ($os =~ /linux/i) {
        my $pw = _get_sudo_password();
        # Check for nft first (modern), fallback to iptables
        if (`which nft 2>/dev/null`) {
            $cmd = "echo '$pw' | sudo -S nft list ruleset 2>&1";
        } elsif (`which iptables 2>/dev/null`) {
            $cmd = "echo '$pw' | sudo -S iptables -L -n -v 2>&1";
        } else {
            $cmd = "echo 'No firewall tools (nft/iptables) available'";
        }
    } elsif ($os =~ /aix/i) {
        $cmd = "echo 'Firewall config collection not applicable on AIX'";
    } elsif ($os =~ /sunos|solaris/i) {
        my $pw = _get_sudo_password();
        $cmd = "echo '$pw' | sudo -S ipfstat -io 2>&1";
    } elsif ($os =~ /darwin/i) {
        my $pw = _get_sudo_password();
        $cmd = "echo '$pw' | sudo -S pfctl -sr 2>&1";
    }

    utils::run_to_file($cmd, "$out_dir/firewall_test.txt");
}

###############################################################################
# run_tcpdump
#
# Purpose  : Capture limited network packets on port  (default 1500) for troubleshooting.
# Input    : $out_dir (output directory for results)
# Output   : tcpdump.txt saved in $out_dir
###############################################################################
sub run_tcpdump {
    my $os = env::_os();
    my ($out_dir,$port) = @_;
    my $cmd;
    if ($os =~ /MSWin32/i) {
        # Windows: Prefer tshark if available, otherwise print instructions
        if (`where tshark 2>nul`) {
            $cmd = "tshark -i 1 -f \"tcp port $port\" -c 10 2>&1";
        } else {
            $cmd = "echo 'Wireshark GUI required. Use filter: tcp.port==$port'";
        }
    } elsif ($os =~ /linux/i) {
        my $pw = _get_sudo_password();
        if (`which tcpdump 2>/dev/null`) {
            $cmd = "echo '$pw' | sudo -S timeout 15 tcpdump -i any port $port -c 10 2>&1";
        } else {
            $cmd = "echo 'tcpdump not found; please install tcpdump'";
        }
    } elsif ($os =~ /aix/i) {
        my $pw = _get_sudo_password();
        $cmd = "echo '$pw' | sudo -S tcpdump -i ent0 port $port -c 10 2>&1";
    } elsif ($os =~ /darwin/i) {
        my $pw = _get_sudo_password();
        $cmd = "echo '$pw' | sudo -S bash -c '(tcpdump -i en0 port $port -c 50 > \"$out_dir/tcpdump.txt\" 2>&1 &) && sleep 10 && pkill tcpdump'";
    } elsif ($os =~ /sunos/i) {
        my $pw = _get_sudo_password();
        $cmd = "echo '$pw' | sudo -S snoop -d net0 tcp port $port 2>&1";
    }

    utils::run_to_file($cmd, "$out_dir/tcpdump.txt");
}

###############################################################################
# run_netstat
#
# Purpose  : Collect active network connections, listening ports, and routing info.
# Input    : $out_dir (output directory)
# Output   : netstat.txt saved in $out_dir
###############################################################################
sub run_netstat {
    my $os = env::_os();
    my ($out_dir) = @_;
    my $cmd;
    if ($os =~ /MSWin32/i) {
        # Show all TCP and UDP connections with PID and listening ports
        $cmd = "netstat -ano";
    } elsif ($os =~ /linux/i) {
        my $pw = _get_sudo_password();
        if (`which ss 2>/dev/null`) {
            $cmd = "echo '$pw' | sudo -S ss -tulpan 2>&1";
        } else {
            $cmd = "echo '$pw' | sudo -S netstat -tulpan 2>&1";
        }
    } elsif ($os =~ /aix/i) {
        $cmd = "netstat -an | grep -v 'CLOSE_WAIT'";
    } elsif ($os =~ /darwin/i) {
        $cmd = "netstat -anv";
    } elsif ($os =~ /sunos|solaris/i) {
        $cmd = "netstat -an -f inet";
    } else {
        $cmd = "echo 'netstat command not supported on this platform'";
    }
    utils::run_to_file($cmd, "$out_dir/netstat.txt");
}

1;
