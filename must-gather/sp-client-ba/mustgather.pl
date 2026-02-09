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
# Parameters (REMOVED password command-line)
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

# SECURITY: Get credentials from ENVIRONMENT only
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || '';

if (!$help) {
    die "Error: --product is mandatory\n"    unless defined $product;
    die "Error: --output-dir is mandatory\n" unless defined $output_dir;
}

# ----------------------------------
# Verify product installation
# ----------------------------------
my $base_path = env::get_ba_base_path();
unless ($base_path) {
    die "Product '$product' is not installed on this machine.\n";
}

my $os = env::_os();

# ----------------------------------
# Module List
# ----------------------------------
my @all_modules      = qw(system network config logs performance server core lanfree);
my @selected_modules = $modules ? split /,/, $modules : @all_modules;

print "\n############## Starting Collection of $product diagnostic information ##############\n\n";
print "Modules to be collected (" . scalar(@selected_modules) . "): @selected_modules\n\n"
    if $verbose;

# ----------------------------------
# Detect Server Address
# ----------------------------------
my $opt_file = $optfile ? $optfile : "$base_path/dsm.opt";
my $server_ip;

if (grep { $_ eq "network" } @selected_modules) {
    my $server_address = "Unknown";

    if ($os =~ /MSWin32/i) {
        if (-e $opt_file && open(my $fh, '<', $opt_file)) {
            while (<$fh>) {
                next if /^\s*[;#]/;
                if (/^\s*(TCPSERVERADDRESS|TCPS)\s+(\S+)/i) {
                    $server_address = $2;
                    last;
                }
            }
            close $fh;
        }
    } else {
        my $dsm_sys_path = "$base_path/dsm.sys";
        my $active_server;

        if (-e $opt_file && open(my $fh, '<', $opt_file)) {
            while (<$fh>) {
                next if /^\s*[;#]/;
                if (/^\s*(SERVERNAME|SE)\s+(\S+)/i) {
                    $active_server = $2;
                    last;
                }
            }
            close $fh;
        }

        if ($active_server && -e $dsm_sys_path && open(my $fh, '<', $dsm_sys_path)) {
            my $in_target = 0;
            while (<$fh>) {
                next if /^\s*[;#]/;
                if (/^\s*(SERVERNAME|SE)\s+(\S+)/i) {
                    $in_target = ($2 eq $active_server);
                }
                elsif ($in_target && /^\s*(TCPSERVERADDRESS|TCPS)\s+(\S+)/i) {
                    $server_address = $2;
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
# Determine TCP Port
# ----------------------------------
my $port = 1500;
my $dsm_sys = "$base_path/dsm.sys";

if ($os =~ /MSWin32/i) {
    if (-e $opt_file && open(my $fh, '<', $opt_file)) {
        while (<$fh>) {
            next if /^\s*[;#]/;
            if (/^\s*(TCPPORT|TCPP)\s+(\d+)/i) {
                $port = $2;
                last;
            }
        }
        close $fh;
    }
} else {
    my $active_server;
    if (-e $opt_file && open(my $fh, '<', $opt_file)) {
        while (<$fh>) {
            next if /^\s*[;#]/;
            if (/^\s*(SERVERNAME|SE)\s+(\S+)/i) {
                $active_server = $2;
                last;
            }
        }
        close $fh;
    }

    if ($active_server && -e $dsm_sys && open(my $fh, '<', $dsm_sys)) {
        my $in_stanza = 0;
        while (<$fh>) {
            next if /^\s*[;#]/;
            if (/^\s*(SERVERNAME|SE)\s+(\S+)/i) {
                $in_stanza = ($2 eq $active_server);
            }
            elsif ($in_stanza && /^\s*(TCPPORT|TCPP)\s+(\d+)/i) {
                $port = $2;
                last;
            }
        }
        close $fh;
    }
}

# ----------------------------------
# Run Modules
# ----------------------------------
my %module_status;
my $total = scalar @selected_modules;
my $count = 0;

foreach my $module (@selected_modules) {
    $count++;
    print "Running module ($count/$total): $module\n" if $verbose;

    my $script;
    if    ($module eq "system")      { $script = "$FindBin::Bin/../common/scripts/system_info.pl"; }
    elsif ($module eq "network")     { $script = "$FindBin::Bin/../common/scripts/network_info.pl"; }
    elsif ($module eq "config")      { $script = "$FindBin::Bin/collector/config.pl"; }
    elsif ($module eq "logs")        { $script = "$FindBin::Bin/collector/log.pl"; }
    elsif ($module eq "performance") { $script = "$FindBin::Bin/collector/performance.pl"; }
    elsif ($module eq "server")      { $script = "$FindBin::Bin/../common/scripts/server_info.pl"; }
    elsif ($module eq "core")        { $script = "$FindBin::Bin/collector/core.pl"; }
    elsif ($module eq "lanfree")        { $script = "$FindBin::Bin/collector/lanfree.pl"; }
    else {
        $module_status{$module} = "SKIPPED";
        next;
    }

    my @args = ("perl", $script, "-o", $output_dir);
    push @args, ("-s", $server_ip) if $module eq "network" && $server_ip;
    push @args, ("-p", $port)      if $module eq "network" && $port;
    push @args, "-v"               if $verbose;
    push @args, ("--optfile", $optfile)
        if $optfile && ($module eq "config" || $module eq "server");

    my $exit_code = system(@args) >> 8;
    $module_status{$module} =
          $exit_code == 0 ? "Success"
        : $exit_code == 2 ? "Partial"
        :                   "Failed";
}

# ----------------------------------
# Extract Product Info
# ----------------------------------
my $product_version = "Unknown";
my $node_name       = "Unknown";
my $server_name     = "Unknown";

my $dsminfo_path = "$output_dir/config/dsminfo.txt";
if (-e $dsminfo_path && open(my $fh, '<', $dsminfo_path)) {
    while (<$fh>) {
        if (/Client\s+Version\s+(.+)/i) {
            $product_version = $1;
            $product_version =~ s/\s+$//;
        }
    }
    close $fh;
}

my $console_file = "$output_dir/config/systeminfo_console.txt";
if (-e $console_file && open(my $fh, '<', $console_file)) {
    while (<$fh>) {
        if (/Node Name:\s*(\S+)/i) {
            $node_name = $1;
        }
        elsif (/Session established with server\s+(\S+):/i) {
            $server_name = $1;
        }
    }
    close $fh;
}
unlink $console_file if -e $console_file;


# ----------------------------------
# Summary
# ----------------------------------
print "\n=== Must-Gather Collection Summary ===\n";
printf "%-20s : %s\n", "Product",     $product;
printf "%-20s : %s\n", "Version",     $product_version;
printf "%-20s : %s\n", "Node Name",   $node_name;
printf "%-20s : %s\n", "Server Name", $server_name;

print "\n    Modules         : Status\n";
print "-----------------------------\n";

my $index = 1;
 foreach my $module (sort { lc($a) cmp lc($b) } @selected_modules) {
     my $status = $module_status{$module} // "Not collected"; 

     if ($module eq "core") { 
        my $marker = "$output_dir/core/core_status.txt";
         if (-e $marker) {
             open my $fh, '<', $marker; chomp($status = <$fh>); 
             close $fh;
        } 
     } 
     printf " %d. %-15s : %s\n", $index++, $module, $status; 
 } 
     
print "\nCheck script.log inside each module folder for detailed failures.\n\n"; 
printf "%-5s : %s\n\n", "Output", "$output_dir.zip" unless $no_compress; 
printf "%-5s : %s\n\n", "Output", "$output_dir" if $no_compress;