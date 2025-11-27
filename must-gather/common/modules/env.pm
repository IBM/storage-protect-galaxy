package env;
use strict;
use warnings;
use Exporter 'import';
use File::Spec;

our @EXPORT_OK = qw(_os get_ba_base_path get_server_address);

###############################################################################
# _os
#
# Purpose  : Detect the current operating system.
# Input    : None
# Output   : String representing OS ("linux", "aix", "darwin", "MSWin32", "sunos")
# Notes    : Uses Perl built-in variable $^O
###############################################################################
sub _os {
    return $^O;
}

###############################################################################
# get_ba_base_path
#
# Purpose  : Determine BA client base installation directory.
# Input    : $product (currently only 'sp-client-ba' expected)
# Output   : Absolute path to BA client bin directory, or undef if not found.
# Behavior : 
#   1. Check DSM_DIR environment variable (highest priority).
#   2. Fallback to OS-specific default install paths.
#   3. Return undef if product is not installed or path missing.
###############################################################################

sub get_ba_base_path {
    my ($product) = @_;
    my $os = _os();

    # 1. Environment override
    return $ENV{DSM_DIR} if $ENV{DSM_DIR} && -d $ENV{DSM_DIR};

    # 2. OS-specific fallback paths
    if ($os =~ /linux/i) {
        foreach my $path (
            "/opt/tivoli/tsm/client/ba/bin",
        ) {
            return $path if -d $path && -f "$path/dsm.sys";
        }
    }
    elsif ($os =~ /aix/i) {
        foreach my $path (
            "/usr/tivoli/tsm/client/ba/bin64",
            "/usr/tivoli/tsm/client/ba/bin"
        ) {
            return $path if -d $path && -f "$path/dsm.sys";
        }
    }
    elsif ($os =~ /sunos/i) {
        foreach my $path (
            "/opt/tivoli/tsm/client/ba/bin",
        ) {
            return $path if -d $path && -f "$path/dsm.sys";
        }
    }
    elsif ($os =~ /solaris/i) {
        foreach my $path (
            "/opt/tivoli/tsm/client/ba/bin",
        ) {
            return $path if -d $path && -f "$path/dsm.sys";
        }
    }
    elsif ($os =~ /darwin/i) {  # macOS
        foreach my $path (
            "$ENV{HOME}/Library/Preferences/Tivoli\ Storage\ Manager",
            "/Library/Preferences/Tivoli\ Storage\ Manager",
            "/Library/Application\ Support/tivoli/tsm/client/ba/bin"
        ) {
            return $path if -d $path && -f "$path/dsm.sys";
        }
    }
    elsif ($os =~ /MSWin32/i) {
        foreach my $path (
            "C:/Program Files/Tivoli/TSM/BACLIENT",
            "C:/Program Files (x86)/Tivoli/TSM/BACLIENT"
        ) {
            return $path if -d $path && -f "$path/dsm.opt";
        }
    }

    # 3. Not found
    return undef;
}
# -----------------------------------------------------------------------------
# get_sp_base_path
#
# Purpose  : Determine IBM Storage Protect (TSM) server base installation directory.
# Input    : None
# Output   : Absolute path to server bin directory, or undef if not found.
# Behavior : 
#   1. Check DSMSERV_DIR environment variable (highest priority).
#   2. Fallback to OS-specific default install paths.
#   3. Return undef if product is not installed or path missing.
# -----------------------------------------------------------------------------
sub get_sp_base_path {
    my $os = _os();

    # Define base paths
    my $LINUX_AIX_PATH = "/opt/tivoli/tsm/server/bin";
    my $WINDOWS_PATH   = "C:/Program Files/Tivoli/TSM/server";

    # Environment override
    return $ENV{DSMSERV_DIR} if $ENV{DSMSERV_DIR};

    # Linux or AIX default path
    if ($os =~ /linux/i || $os =~ /aix/i) {
        return $LINUX_AIX_PATH if -d $LINUX_AIX_PATH;
    }
    # Windows default path
    elsif ($os =~ /MSWin32/i) {
        return $WINDOWS_PATH if -d $WINDOWS_PATH;
    }

    # Server not installed
    return undef;
}


###############################################################################
# get_sp_instance_info
#
# Purpose  : Determine IBM Storage Protect server instance name and home directory.
# Input    : None
# Output   : Hash reference with keys:
#              instance  => instance name (e.g., tsminst1)
#              directory => absolute path to instance home directory
#            Returns undef if no instance is found.
# Behavior :
#   1. Check DB2INSTANCE and HOME environment variables (highest priority).
#   2. On Linux/AIX:
#        - Run db2ilist to enumerate Db2/Storage Protect instances.
#        - Map instance name to system user and resolve its home directory.
#   3. On Windows:
#        - Run db2ilist if available.
#        - Otherwise, query registry for instance and DB directory.
#   4. Return undef if no valid instance is discovered.
###############################################################################
sub get_sp_instance_info {
    my $os = _os();

    # --------------- Environment override ---------------
    if ($ENV{DB2INSTANCE} && $ENV{HOME}) {
        return { instance => $ENV{DB2INSTANCE}, directory => $ENV{HOME} };
    }

    # --------------- Linux / AIX ------------------------
    if ($os =~ /linux/i || $os =~ /aix/i) {
        my $db2ilist = "/opt/tivoli/tsm/db2/instance/db2ilist";
        if (-x $db2ilist) {
            my @instances = `$db2ilist 2>/dev/null`;
            chomp @instances;
            foreach my $inst (@instances) {
                # Lookup home dir of instance user
                my ($user, $home) = (getpwnam($inst))[0,7];
                return { instance => $inst, directory => $home } if $home && -d $home;
            }
        }
    }

    # --------------- Windows ----------------------------
    elsif ($os =~ /MSWin32/i) {
        my @instances = `db2ilist 2>NUL`;
        chomp @instances;

        foreach my $inst (@instances) {
            next unless $inst;  # skip empty lines
            my $base_path = 'C:\\Program Files\\Tivoli\\TSM';
            my $inst_path = "$base_path\\$inst";

            if (-d $inst_path) {
                return { instance => $inst, directory => $inst_path };
            }
        }

        # Fallback to registry if db2ilist is not available
        my $reg_query = `reg query "HKLM\\SOFTWARE\\IBM\\ADSM\\CurrentVersion\\Server" /s 2>NUL`;
        if ($reg_query) {
            my ($inst) = $reg_query =~ /HKEY_LOCAL_MACHINE.*\\Server\\([^\\\s]+)/i;
            my ($base_dir) = $reg_query =~ /Path\s+REG_SZ\s+([^\r\n]+)/i;
            if ($inst && $base_dir) {
                my $inst_dir = "$base_dir\\$inst";
                return { instance => $inst, directory => $inst_dir } if -d $inst_dir;
            }
        }
    }

    # --------------- Not found --------------------------
    return undef;
}

###############################################################################
# get_server_address
#
# Purpose  : Extract TCPSERVERADDRESS from BA client config file.
# Input    : None
# Output   : Server address (string) or undef if not found.
# Behavior : 
#   1. If DSM_DIR is set, look for dsm.opt/dsm.sys in that path.
#   2. Otherwise, use OS-specific default config locations.
#   3. For macOS, check multiple candidate paths in order.
###############################################################################
sub get_server_address {
    my $os = _os();
    my $base_path = get_ba_base_path();
    my @search_paths;
    my $file;

    # Environment override first
    if ($ENV{DSM_DIR}) {
        my $env_path = $ENV{DSM_DIR};
        foreach my $candidate ("$env_path/dsm.sys", "$env_path/dsm.opt") {
            return _parse_server_address($candidate) if -f $candidate;
        }
    }

    # Windows default: dsm.opt
    if ($os =~ /MSWin32/i) {
        $file = File::Spec->catfile($base_path, "dsm.opt");
        return _parse_server_address($file) if -f $file;
    }
    # Linux/AIX/Solaris default: dsm.sys
    elsif ($os =~ /linux/i || $os =~ /aix/i || $os =~ /sunos/i) {
        $file = File::Spec->catfile($base_path, "dsm.sys");
        return _parse_server_address($file) if -f $file;
    }
    # macOS search order
    elsif ($os =~ /darwin/i) {
        @search_paths = (
            "$ENV{HOME}/Library/Preferences/Tivoli\ Storage\ Manager/dsm.sys",
            "/Library/Preferences/Tivoli\ Storage\ Manager/dsm.sys",
            "/Library/Application\ Support/tivoli/tsm/client/ba/bin/dsm.sys"
        );
        for my $candidate (@search_paths) {
            return _parse_server_address($candidate) if -f $candidate;
        }
    }

    return undef;  # not found
}

###############################################################################
# _parse_server_address
#
# Purpose  : Internal routine to parse TCPSERVERADDRESS from config file.
# Input    : $file (path to dsm.opt or dsm.sys)
# Output   : First matching server address (string) or undef if not found.
# Notes    : Ignores blank lines and comment lines (; or #).
###############################################################################
sub _parse_server_address {
    my ($file) = @_;
    open my $fh, '<', $file or return undef;

    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        next if $line =~ /^$/ || $line =~ /^[;#]/;

        if ($line =~ /^TCPSERVERADDRESS\s+(\S+)/i) {
            close $fh;
            return $1;
        }
    }

    close $fh;
    return undef;
}

###############################################################################
# is_sp_server_running
#
# Purpose  : Detect whether the IBM Storage Protect Server is running.
#
# Input    : None
# Output   : Returns 1 (true) if running, 0 (false) otherwise.
#
# Notes    :
#   Windows :
#       - The Storage Protect server runs as a Windows Service.
#       - We first detect all services that match:
#           "IBM Storage Protect SERVER*"
#       - Then query each one and check for RUNNING state.
#
#   Linux/AIX :
#       - Detects "dsmserv" via ps -ef.
#
#   Fallback :
#       - Checks TCP port 1500 LISTEN.
###############################################################################
sub is_sp_server_running {

    my $os = $^O;
    my $process_found = 0;

    # -------------------------
    # WINDOWS LOGIC
    # -------------------------
    if ($os =~ /MSWin32/i) {

        # Step 1: Find all Storage Protect server service names
        my @svc_list = `sc query | findstr /I "IBM Storage Protect SERVER"`;

        my @sp_services;
        foreach my $line (@svc_list) {
            if ($line =~ /SERVICE_NAME:\s+(.*)/i) {
                push @sp_services, $1;
            }
        }

        # Step 2: Query each service directly
        foreach my $svc (@sp_services) {

            my @details = `sc query "$svc"`;

            # Check for RUNNING state
            if (grep { /STATE\s+:\s+4\s+RUNNING/i } @details) {
                $process_found = 1;
                last;
            }
        }
    }

    # -------------------------
    # LINUX / AIX LOGIC
    # -------------------------
    elsif ($os =~ /linux|aix/i) {
        my @ps = `ps -ef | grep dsmserv | grep -v grep`;
        if (grep { /dsmserv/ } @ps) {
            $process_found = 1;
        }
    }

    # -------------------------
    # Fallback: TCP port 1500
    # -------------------------
    unless ($process_found) {
        my @net = `netstat -an 2>/dev/null`;
        if (grep { /:1500\s+.*LISTEN/i } @net) {
            $process_found = 1;
        }
    }

    return $process_found;
}

1;