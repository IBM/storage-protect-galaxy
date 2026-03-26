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
my $base_path=env::get_ba_base_path();

my $exchange_path = env::get_exchange_base_path();
unless ($exchange_path) {
    die "Product '$product' is not installed on this machine.\n" ;
       
}

my $os = env::_os();


# ----------------------------------
# Module Lists
# ----------------------------------
my @default_modules = qw(network system server config);  # Always run config
my @requested_modules = $modules ? split /,/, $modules : qw(system network config logs performance server exchange);

# Combine and remove duplicates
my %seen;
my @selected_modules = grep { !$seen{$_}++ } (@default_modules, @requested_modules);


# ----------------------------------
# Detect Server Address and TCP Port
# ----------------------------------
my $opt_file = $optfile ? $optfile : "$base_path/dsm.opt";
my $server_ip;
my $port;

if (grep { $_ eq "network" } @selected_modules) {
    $server_ip = utils::get_server_address($opt_file, $base_path, $os);
}

$port = utils::get_tcp_port($opt_file, $base_path, $os);

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
    if ($module eq "system") {
        $script = File::Spec->catfile($FindBin::Bin, "..", "common", "scripts", "system_info.pl");
    } elsif ($module eq "network") {
        $script = File::Spec->catfile($FindBin::Bin, "..", "common", "scripts", "network_info.pl");
    } elsif ($module eq "performance") {
        $script = File::Spec->catfile($FindBin::Bin,"..","sp-client-ba", "collector", "performance.pl");
    } elsif ($module eq "config") {
        $script = File::Spec->catfile($FindBin::Bin,"..","sp-client-ba" ,"collector", "config.pl");
    } elsif ($module eq "logs") {
        $script = File::Spec->catfile($FindBin::Bin,"..","sp-client-ba", "collector", "log.pl");
    } elsif ($module eq "exchange") {
        $script = File::Spec->catfile($FindBin::Bin, "collector", "exchange.pl");
    } elsif ($module eq "server") {
        $script = File::Spec->catfile($FindBin::Bin, "..", "common", "scripts", "server_info.pl");
    }
    else {
        warn "Warning: Unknown module '$module'. Skipping...\n";
        $module_status{$module} = "SKIPPED";
        next;
    }

    my @args = ("perl", $script, "-o", $output_dir);
    push @args, ("-s", $server_ip) if $module eq "network" && $server_ip;
    push @args, ("-p", $port)      if $module eq "network" && $port;
    push @args, "-v"               if $verbose;
    push @args, ("--optfile", $optfile)
        if $optfile && ($module eq "config");

    my $exit_code = system(@args) >> 8;
    $module_status{$module} =
          $exit_code == 0 ? "Success"
        : $exit_code == 2 ? "Partial"
        :                   "Failed";
}

## ----------------------------------
# Extract Product Info
# ----------------------------------
my $product_version = "Unknown";
my $node_name       = "Unknown";
my $server_name     = "Unknown";

my $query_tdp = "$output_dir/exchange/query_tdp.txt";

if (-e $query_tdp && open(my $fh, '<', $query_tdp)) {
    while (my $line = <$fh>) {
        chomp $line;
        # Version line
        if ($line =~ /^Version\s+(.+)/i && $product_version eq "Unknown") {
            $product_version = $1;
        }
        }
    
    close $fh;
}

my $console_file = "$output_dir/config/systeminfo_console.txt";
if (-e $console_file && open(my $fh, '<', $console_file)) {
    while (<$fh>) {
        if (/Node Name:\s*(\S+)/i) {
            $node_name = $1;
        } elsif (/Session established with server\s+(\S+):/i) {
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
    printf " %d. %-15s : %s\n", $index++, $module, $status;
}

print "\nCheck script.log inside each module folder for detailed failures.\n\n";
printf "%-5s : %s\n\n", "Output", "$output_dir.zip" unless $no_compress;
printf "%-5s : %s\n\n", "Output", "$output_dir" if $no_compress;
