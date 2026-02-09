#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path);
use Cwd 'abs_path';
use FindBin;
use lib "$FindBin::Bin/../common/modules";  
use utils;
use File::Spec;
use env;

# ----------------------------------
# Parameters
# ----------------------------------
my ($product, $output_dir, $optfile, $modules, $no_compress, $verbose, $help);

GetOptions(
    "product|p=s"       => \$product,
    "output-dir|o=s"    => \$output_dir,
    "optfile=s"         => \$optfile,
    "modules|m=s"       => \$modules,
    "no-compress"       => \$no_compress,
    "verbose|v"         => \$verbose,
    "help|h"            => \$help,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --product is mandatory\n" unless defined $product;
die "Error: --output-dir is mandatory\n" unless defined $output_dir;



# ----------------------------------
# Verify product installation
# ----------------------------------
my $base_path = env::get_sp_base_path();
my $ba_base_path = env::get_ba_base_path();
unless ($base_path) {
    die "Product '$product' is not installed on this machine.\n";
}

my $os = env::_os();

# ----------------------------------
# Module List (ensure config runs first, no duplicates)
# ----------------------------------
my @default_modules = qw(config network system);  # Always run config
my @requested_modules = $modules ? split /,/, $modules : qw(system network server tape replication stgpool dbbackup tiering install-upgrade librarysharing oc dbreorganisation expiration lanfree server-crash);

# Combine and remove duplicates
my %seen;
my @selected_modules = grep { !$seen{$_}++ } (@default_modules, @requested_modules);

print "\n############## Starting Collection of $product diagnostic information ##############\n\n"; 
print "Modules to be collected (" . scalar(@selected_modules) . "): @selected_modules\n\n" if $verbose;


# ----------------------------------
# Detect Server Address (for network module)
# ----------------------------------
my $opt_file;
if ($optfile) {
    # User-specified option file
    $opt_file = $optfile;
} else {
    $opt_file = "$ba_base_path/dsm.opt";
}
my $server_ip;
if (grep { $_ eq "network" } @selected_modules) {
    
    my ($dsm_opt_path, $dsm_sys_path);
    my $server_address = "Unknown";

    if ($os =~ /MSWin32/i) {
        $dsm_opt_path = $opt_file;
        if (-e $dsm_opt_path && open(my $fh, '<', $dsm_opt_path)) {
            while (<$fh>) {
                next if /^\s*;/;
                if (/^\s*TCPSERVERADDRESS\s+(\S+)/i) {
                    $server_address = $1;
                    last;
                }
            }
            close $fh;
        }
    } 
    else {
        $dsm_opt_path = $opt_file;
        $dsm_sys_path = "$ba_base_path/dsm.sys";
        my $active_server;

        if (-e $dsm_opt_path && open(my $fh, '<', $dsm_opt_path)) {
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

    $server_ip = $server_address ne "Unknown" ? $server_address : undef;
    print "Detected server address: " . ($server_ip // 'Not found') . "\n" if $verbose;
}

# ----------------------------------
# Determine TCP Port (for server module)
# ----------------------------------

my $port = 1500;  # Default
    my ($dsm_opt, $dsm_sys) = ($opt_file, "$ba_base_path/dsm.sys");

    if ($os =~ /MSWin32/i) {
        # Windows: check dsm.opt
        if (-e $dsm_opt && open(my $fh, '<', $dsm_opt)) {
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
        if (-e $dsm_opt && open(my $fh, '<', $dsm_opt)) {
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
# ----------------------------------
# Run Modules
# ----------------------------------
my %module_status;   # track module execution status
my $total = scalar @selected_modules;
my $count = 0;

foreach my $module (@selected_modules) {
    $count++;
    print "Running module ($count/$total): $module\n" if $verbose;

    my $exit_code = 1;
    my $script;
        # Check if SP server is running for modules that require it
    if ($module =~ /^(config|tape|replication|stgpool|server|dbbackup|librarysharing|oc|tiering|dbreorganisation|expiration|lanfree)$/) {
        unless (env::is_sp_server_running()) {
            warn "Storage Protect Server is NOT running. Skipping $module module...\n";
            $module_status{$module} = "SKIPPED";
            next;
        }
    }

    # Map each module to its respective script path
    if ($module eq "system") {
        $script = File::Spec->catfile($FindBin::Bin, "..", "common", "scripts", "system_info.pl");
    } 
    elsif ($module eq "network") {
        $script = File::Spec->catfile($FindBin::Bin, "..", "common", "scripts", "network_info.pl");
    } 
    elsif ($module eq "config") {
        $script = File::Spec->catfile($FindBin::Bin, "collector", "config.pl");
    } 
    elsif ($module eq "server") {
        $script = File::Spec->catfile($FindBin::Bin, "..", "common", "scripts", "server_info.pl");
    } 
    elsif ($module eq "tape") {
        $script = File::Spec->catfile($FindBin::Bin, "collector", "tape.pl");
    } 
    elsif ($module eq "replication") {
        $script = File::Spec->catfile($FindBin::Bin, "collector", "replication.pl");
    }
    elsif ($module eq "stgpool") {
        $script = File::Spec->catfile($FindBin::Bin, "collector", "stgpool.pl");
    }
    elsif ($module eq "dbbackup") {
        $script = File::Spec->catfile($FindBin::Bin, "collector", "dbbackup.pl");
    }
    elsif ($module eq "tiering") {
        $script = File::Spec->catfile($FindBin::Bin, "collector", "tiering.pl");
    }
    elsif ($module eq "install-upgrade"){
        $script = File::Spec->catfile($FindBin::Bin, "collector", "install_manager.pl");
    }
    elsif ($module eq "librarysharing"){
        $script = File::Spec->catfile($FindBin::Bin, "collector", "librarysharing.pl");
    }
    elsif ($module eq "oc"){
        $script = File::Spec->catfile($FindBin::Bin, "collector", "oc.pl");
    }
    elsif ($module eq "dbreorganisation"){
        $script = File::Spec->catfile($FindBin::Bin, "collector", "dbreorganisation.pl");
    }
    elsif ($module eq "expiration"){
        $script = File::Spec->catfile($FindBin::Bin, "collector", "expiration.pl");
    }
    elsif ($module eq "lanfree"){
        $script = File::Spec->catfile($FindBin::Bin, "collector", "lanfree.pl");
    }
    elsif ($module eq "server-crash"){
        $script = File::Spec->catfile($FindBin::Bin, "collector", "server_crash.pl");
    }
    else {
        warn "Warning: Unknown module '$module'. Skipping...\n";
        $module_status{$module} = "SKIPPED";
        next;
    }


    # Construct command dynamically
    my @args = ("perl", $script, "-o", $output_dir);

    # Add optional arguments
    push @args, ("-s", $server_ip) if $module eq "network" && $server_ip;
    push @args, ("-p", $port) if $module eq "network" && $port;
    push @args, "-v" if $verbose;
    push @args, ("--optfile",$optfile) if ($module eq "config" || $module eq "server" || $module eq "tape" || $module eq "replication" ||$module eq "stgpool" ||$module eq "dbbackup" || $module eq "tiering" || $module eq "librarysharing" || $module eq "oc" || $module eq "expiration" || $module eq "lanfree"  || $module eq "dbreorganisation") && $optfile;
    # Execute the script
    $exit_code = system(@args);
    $exit_code >>= 8;  # Normalize child exit code

    # Update module status
    if    ($exit_code == 0) { $module_status{$module} = "Success"; }
    elsif ($exit_code == 2) { $module_status{$module} = "Partial"; }
    else                    { $module_status{$module} = "Failed";  }
}


# ----------------------------------
# Extract Product Info from Q SYSTEM
# ----------------------------------

my $product_name    = "Unknown";
my $product_version = "Unknown";
my $os_platform     = "Unknown";
my $server_name     = "Unknown";

my $qsystem_path = "$output_dir/config/system.txt";

my $in_qstatus_table = 0;
my $seen_separator   = 0;

if (-e $qsystem_path) {
    open my $fh, '<', $qsystem_path or die "Cannot open $qsystem_path: $!";
    while (my $line = <$fh>) {
        chomp $line;

        # --------------------------------------------------
        # Product + version
        # --------------------------------------------------
        if ($line =~ /IBM\s+Storage\s+Protect\s+Server\s+for\s+(.+?)\s+-\s+Version\s+(\d+),\s*Release\s+(\d+),\s*Level\s+([\d.]+)/i) {
            $product_name    = "IBM Storage Protect Server";
            $os_platform     = $1;
            $product_version = "$2.$3.$4";
            next;
        }

        # --------------------------------------------------
        # 1️ Preferred: Key-Value format
        # --------------------------------------------------
        if ($line =~ /^Server\s+Name\s*:\s*(\S+)/i) {
            $server_name = $1;
            last;
        }

        # --------------------------------------------------
        # Detect Q STATUS section
        # --------------------------------------------------
        if ($line =~ /^\*+\s*--->\s*Q\s+STATUS/i) {
            $in_qstatus_table = 1;
            next;
        }

        # --------------------------------------------------
        # Separator line before data
        # --------------------------------------------------
        if ($in_qstatus_table && $line =~ /^-+\s+/) {
            $seen_separator = 1;
            next;
        }

        # --------------------------------------------------
        # 2️ Fallback: First column of table data
        # --------------------------------------------------
        if ($in_qstatus_table && $seen_separator) {
            next if $line =~ /^\s*$/;  # skip blank lines
            if ($line =~ /^\s*(\S+)/) {
                $server_name = $1;
                last;
            }
        }
    }
    close $fh;
}



# ----------------------------------
# Concise Summary
# ----------------------------------
print "\n=== Must-Gather Collection Summary ===\n";
printf "%-20s : %s\n", "Product", $product_name;
printf "%-20s : %s\n", "Version", "Version $product_version" // "N/A";
printf "%-20s : %s\n", "Platform", $os_platform // "Unknown";
printf "%-20s : %s\n", "Server Name", $server_name // "Unknown";

print "\n    Modules         : Status\n";
print "-----------------------------\n";

my $index = 1;
foreach my $module (sort { lc($a) cmp lc($b) } @selected_modules) {
    my $status = $module_status{$module} // "Not collected";
    printf " %d. %-15s : %s\n", $index++, $module, $status;
}

print "\nCheck script.log inside each module folder for detailed failures.\n\n";
printf "%-5s : %s\n\n", "Output", "$output_dir.zip" unless $no_compress;
printf "%-5s : %s\n\n", "Output", "$output_dir" if $no_compress;