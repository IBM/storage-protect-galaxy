package utils;
use strict;
use warnings;
use Exporter 'import';
use File::Path qw(make_path);

# Exported functions
our @EXPORT_OK = qw(
    run_to_file
    write_to_file
    timestamp
    get_server_address
    get_tcp_port
    validate_caseno 
    get_reg_path 
    collect_ve_component_logs
);

# -----------------------------
# Run a command and save output to a file
# -----------------------------
# Arguments:
#   $cmd  - command to execute
#   $file - file path to store output
# Behavior:
#   - Ensures the parent directory exists
#   - Executes the command and redirects stdout/stderr to file
#   - Returns a status message
sub run_to_file {
    my ($cmd, $file) = @_;

    # Ensure the directory exists before writing
    if ($file =~ m{^(.*)/}) {
        my $dir = $1;
        make_path($dir) unless -d $dir;
    }

    # Run the command and redirect output to the file
    my $status = system("$cmd > \"$file\" 2>&1");  # overwrite file safely

    if ($status != 0) {
        return "Warning: Command '$cmd' exited with code " . ($status >> 8) . "\n";
    }

    return "Saved output to $file\n";
}

# -----------------------------
# Write data directly to a file
# -----------------------------
# Arguments:
#   $file     - file path to write
#   $data_ref - string or hashref
# Behavior:
#   - Ensures the parent directory exists
#   - If hashref is given, writes key=value lines
#   - Else writes raw string content
sub write_to_file {
    my ($file, $data_ref) = @_;

    # Ensure the directory exists
    my ($dir) = $file =~ m{^(.*)/};
    make_path($dir) if defined $dir && ! -d $dir;

    open(my $fh, ">", $file) or die "Cannot open $file: $!";
    if (ref($data_ref) eq 'HASH') {
        foreach my $key (sort keys %$data_ref) {
            print $fh "$key=$data_ref->{$key}\n";
        }
    } else {
        print $fh $data_ref;
    }
    close $fh;
}

# -----------------------------
# Generate timestamp string
# -----------------------------
# Format: YYYYMMDD_HHMMSS
# Example: 20250929_114530
sub timestamp {
    my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
    $year  += 1900;
    $mon   += 1;
    return sprintf("%04d%02d%02d_%02d%02d%02d",
        $year, $mon, $mday, $hour, $min, $sec);
}


# -----------------------------
# Get server address from DSM configuration files
# -----------------------------
# Arguments:
#   $opt_file  - path to dsm.opt file
#   $base_path - base installation path
#   $os        - operating system string
# Returns:
#   Server address string or undef if not found
sub get_server_address {
    my ($opt_file, $base_path, $os) = @_;
    
    my $server_address = "Unknown";
    
    if ($os =~ /MSWin32/i) {
        # Windows: read directly from dsm.opt
        if (-e $opt_file && open(my $fh, '<', $opt_file)) {
            while (<$fh>) {
                next if /^\s*;/;
                if (/^\s*TCPSERVERADDRESS\s+(\S+)/i) {
                    $server_address = $1;
                    last;
                }
            }
            close $fh;
        }
    } else {
        # Unix-like: read server name from dsm.opt, then address from dsm.sys
        my $dsm_sys_path = "$base_path/dsm.sys";
        my $active_server;
        
        if (-e $opt_file && open(my $fh, '<', $opt_file)) {
            while (<$fh>) {
                next if /^\s*;/;
                if (/^\s*SERVERNAME\s+(\S+)/i) {
                    $active_server = $1;
                    last;
                }
            }
            close $fh;
        }
        
        if ($active_server && -e $dsm_sys_path && open(my $fh, '<', $dsm_sys_path)) {
            my $in_target_stanza = 0;
            while (<$fh>) {
                next if /^\s*;/;
                if (/^\s*SERVERNAME\s+(\S+)/i) {
                    $in_target_stanza = ($1 eq $active_server) ? 1 : 0;
                } elsif ($in_target_stanza && /^\s*TCPSERVERADDRESS\s+(\S+)/i) {
                    $server_address = $1;
                    last;
                }
            }
            close $fh;
        }
    }
    
    return $server_address ne "Unknown" ? $server_address : undef;
}

# -----------------------------
# Get TCP port from DSM configuration files
# -----------------------------
# Arguments:
#   $opt_file  - path to dsm.opt file
#   $base_path - base installation path
#   $os        - operating system string
# Returns:
#   TCP port number (default: 1500)
sub get_tcp_port {
    my ($opt_file, $base_path, $os) = @_;
    
    my $port = 1500;  # Default port
    my $dsm_sys = "$base_path/dsm.sys";
    
    if ($os =~ /MSWin32/i) {
        # Windows: check dsm.opt
        if (-e $opt_file && open(my $fh, '<', $opt_file)) {
            while (<$fh>) {
                next if /^\s*[;#]/;
                if (/^TCPPORT\s+(\d+)/i) {
                    $port = $1;
                    last;
                }
            }
            close $fh;
        }
    } else {
        # Unix-like: read from dsm.sys (match server stanza)
        my $active_server;
        if (-e $opt_file && open(my $fh, '<', $opt_file)) {
            while (<$fh>) {
                next if /^\s*[;#]/;
                if (/^SERVERNAME\s+(\S+)/i) {
                    $active_server = $1;
                    last;
                }
            }
            close $fh;
        }
        
        if ($active_server && -e $dsm_sys && open(my $fh, '<', $dsm_sys)) {
            my $in_stanza = 0;
            while (<$fh>) {
                next if /^\s*[;#]/;
                if (/^SERVERNAME\s+(\S+)/i) {
                    $in_stanza = ($1 eq $active_server);
                } elsif ($in_stanza && /^TCPPORT\s+(\d+)/i) {
                    $port = $1;
                    last;
                }
            }
            close $fh;
        }
    }
    
    return $port;
}

# -----------------------------
# Validate IBM Support Case Number
# -----------------------------
# Arguments:
#   $caseno - case number string to validate
# Returns:
#   Sanitized case number or dies with error message
# Format: TS followed by 9 digits (e.g., TS020757841)
# Max length: 20 characters for safety
sub validate_caseno {
    my ($caseno) = @_;
    
    # Check if provided
    die "Error: Case number is required\n" unless defined $caseno && $caseno ne '';
    
    # Remove leading/trailing whitespace
    $caseno =~ s/^\s+|\s+$//g;
    
    # Check length (reasonable limit for filesystem compatibility)
    die "Error: Case number too long (max 20 characters)\n" if length($caseno) > 20;
    die "Error: Case number too short (min 5 characters)\n" if length($caseno) < 5;
    
    # Validate format: TS followed by 9 digits
    unless ($caseno =~ /^TS\d{9}$/i) {
        die "Error: Invalid case number format. Expected format: TS followed by 9 digits (e.g., TS020757841)\n";
    }
    
    # Normalize to uppercase
    $caseno = uc($caseno);
    
    # Additional check: only alphanumeric characters (already validated by regex, but being explicit)
    unless ($caseno =~ /^[A-Z0-9]+$/) {
        die "Error: Case number contains invalid characters. Only alphanumeric characters allowed.\n";
    }
    
    return $caseno;
}

# -----------------------------
# Get registry path value (Windows only)
# -----------------------------
# Arguments:
#   $key   - registry key path (e.g., HKEY_LOCAL_MACHINE\SOFTWARE\IBM\Tivoli Storage Manager\BA\CurrentVersion)
#   $value - registry value name to query
# Returns:
#   Registry value data or undef if not found/invalid     
sub get_reg_path {
    my ($key, $value) = @_;
    my $cmd = qq{reg query "$key" /v $value 2>NUL};
    my $out = `$cmd`;

    if ($out =~ /\Q$value\E\s+REG_\w+\s+([^\r\n]+)/i) {
        my $path = $1;
        $path =~ s/^\s+|\s+$//g;
        return $path if -d $path;
    }
    return undef;
}

###############################################################################
# collect_sp_component_logs
#
# Purpose  : Resolve install paths (default → registry) and copy logs
#            for Spectrum Protect virtual environment (Framework, Webserver, RecoveryAgent)
#
# Input    :
#   $output_dir  - destination base directory
#   $errfh       - error log filehandle
#
# Output   :
#   Hash reference { component_name => Success|Not Found }
###############################################################################
sub collect_ve_component_logs {
    my ($output_dir, $errfh, $collected_ref) = @_;

    my ($vmcli_dir, $webserver_dir, $tsmcli_dir, $recoveryagent_dir);

    # -----------------------------
    # Default locations
    # -----------------------------
    $vmcli_dir = "C:/Program Files/IBM/SpectrumProtect/Framework/VEGUI"
        if -d "C:/Program Files/IBM/SpectrumProtect/Framework/VEGUI";

    $tsmcli_dir = "C:/Program Files/IBM/SpectrumProtect/Framework/TSM/tsmcli"
        if -d "C:/Program Files/IBM/SpectrumProtect/Framework/TSM/tsmcli";

    $webserver_dir = "C:/IBM/SpectrumProtect/webserver/usr/servers/veProfile"
        if -d "C:/IBM/SpectrumProtect/webserver/usr/servers/veProfile";

    my $all_users = $ENV{ALLUSERSPROFILE} || "C:/ProgramData";
    $recoveryagent_dir = "$all_users/Tivoli/TSM/RecoveryAgent"
        if -d "$all_users/Tivoli/TSM/RecoveryAgent";

    # -----------------------------
    # Registry fallback
    # -----------------------------
    unless ($vmcli_dir || $tsmcli_dir) {
        my $fw = get_reg_path(
            'HKLM\\SOFTWARE\\IBM\\SpectrumProtect\\Framework',
            'Path'
        );
        $vmcli_dir  = "$fw/VEGUI"      if $fw && -d "$fw/VEGUI";
        $tsmcli_dir = "$fw/TSM/tsmcli" if $fw && -d "$fw/TSM/tsmcli";
    }

    unless ($webserver_dir) {
        my $ws = get_reg_path(
            'HKLM\\SOFTWARE\\IBM\\SpectrumProtect\\webserver',
            'Path'
        );
        $webserver_dir = "$ws/usr/servers/veProfile"
            if $ws && -d "$ws/usr/servers/veProfile";
    }

    unless ($recoveryagent_dir) {
        $recoveryagent_dir = get_reg_path(
            'HKLM\\SOFTWARE\\IBM\\RecoveryAgent',
            'InstallPath'
        );
    }

    # -----------------------------
    # Copy logs + ALWAYS update summary hash
    # -----------------------------
    my %log_dirs = (
        "vmcli_logs"          => $vmcli_dir,
        "veProfile"          => $webserver_dir,
        "derby_logs"         => ($vmcli_dir ? "$vmcli_dir/derby" : undef),
        "tsmcli_logs"        => $tsmcli_dir,
        "RecoveryAgent_Logs" => $recoveryagent_dir,
    );

    foreach my $k (keys %log_dirs) {
        my $src  = $log_dirs{$k};
        my $dest = "$output_dir/$k";

        if ($src && -d $src) {
            system("xcopy \"$src\" \"$dest\" /E /I /Q >nul 2>&1");
            $collected_ref->{$k} = "Success";
        } else {
            $collected_ref->{$k} = "Not Found";
            print $errfh "Directory not found: $src\n" if $src;
        }
    }

    return;   # IMPORTANT: no return value
}



1;