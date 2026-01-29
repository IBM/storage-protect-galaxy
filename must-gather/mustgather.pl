#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path remove_tree);
use FindBin;
use lib "$FindBin::Bin/common/modules";  
use utils;
use File::Spec;



# ----------------------------------
# Parameters
# ----------------------------------
# Command-line optfile for must-gather execution
my ($product, $output_dir, $time, $optfile, $modules, $no_compress, $verbose, $help, $adminid);

GetOptions(
    "product|p=s"     => \$product,      # Product name to collect
    "output-dir|o=s"  => \$output_dir,   # Base output directory
    "optfile=s"       => \$optfile,      # Path to optfile file
    "modules|m=s"     => \$modules,      # Comma-separated module list
    "no-compress"     => \$no_compress,  # Skip compression of results
    "verbose|v"       => \$verbose,      # Verbose mode
    "help|h"          => \$help,         # Show help
    "adminid|id=s"    => \$adminid,      # Server admin ID
) or die("Error in command line arguments\n");

my $caseno;
my $password;
# Mandatory arguments check
if(!$help){
    die "Error: --product is mandatory\n" unless $product;
    die "Error: --output-dir is mandatory\n" unless $output_dir;

    # Prompt for IBM Support Case Number 
    print "Enter IBM Support Case Number: ";
    $caseno = <STDIN>;
    chomp $caseno;
    die "Case number is mandatory\n" unless $caseno;

    # SECURITY: Interactive password prompt ONLY if adminid provided

    if ($adminid) {

    my $read_ok = 0;

    # Preferred method
    eval {
        require Term::ReadPassword;
        Term::ReadPassword->import();
        print "Enter password for admin '$adminid': ";
        $password = Term::ReadPassword::read_password();
        print "\n";
        chomp $password;
        $read_ok = 1;
    };

    # Unix fallback
    if (!$read_ok && $^O !~ /MSWin32/i) {
        print "Enter password for admin '$adminid': ";
        system("stty", "-echo");
        $password = <STDIN>;
        system("stty", "echo");
        print "\n";
        chomp $password;
        $read_ok = 1;
    }

    # Final fallback (visible, warned)
    if (!$read_ok) {
        warn "WARNING: Secure password masking not available. Input will be visible.\n";
        print "Enter password for admin '$adminid': ";
        $password = <STDIN>;
        chomp $password;
        $read_ok = 1;
    }

    die "Failed to read password\n" unless $read_ok;

}
}
# Generate timestamp for unique output folder
my $timestamp = utils::timestamp();

# ----------------------------------
# Cleanup previous must-gather output
# ----------------------------------
sub cleanup {
    my ($output_dir) = @_;

    # Safety: prevent deletion of root or invalid paths
    if (!$output_dir || $output_dir eq '/' || $output_dir eq 'C:\\' || $output_dir eq 'C:/') {
        warn "Refusing to clean up unsafe directory: $output_dir\n";
        return;
    }

    opendir(my $dh, $output_dir) or do {
        warn "Cannot open directory $output_dir: $!";
        return;
    };

    while (my $entry = readdir($dh)) {
        next if $entry =~ /^\.\.?$/;  # skip . and ..
        
        # Delete known must-gather folders/files only
        if ($entry =~ /^mustgather_/i || $entry =~ /^(System|Network|Config|Logs|Performance)$/) {
            my $full_path = File::Spec->catfile($output_dir, $entry);
            remove_tree($full_path, {error => \my $err});
            if (@$err) {
                warn "Errors occurred while removing $full_path:\n";
                for my $diag (@$err) {
                    my ($file, $message) = %$diag;
                    warn "$file: $message\n";
                }
            } else {
                print "Removed $full_path\n" if $verbose;
            }
        }
    }
    closedir($dh);
}

# Clean previous must-gather folders
cleanup($output_dir);

# Create fresh output folder for this run
$output_dir = File::Spec->catdir($output_dir, "mustgather_${caseno}_${product}_$timestamp");
make_path($output_dir) unless -d $output_dir;

# ----------------------------------
# Print help if requested
# ----------------------------------


# Verbose log
print "Starting must-gather for product: $product\n" if $verbose;

# ----------------------------------
# Map product to its must-gather script
# ----------------------------------
 my %product_scripts = (
        'sp-client-ba' => "$FindBin::Bin/sp-client-ba/mustgather.pl",
        'sp-server' => "$FindBin::Bin/sp-server/mustgather.pl",
        'sp-client-vmware' => "$FindBin::Bin/sp-client-vmware/mustgather.pl",
        'sp-server-sta' => "$FindBin::Bin/sp-server-sta/mustgather.pl",
        'sp-client-hyperv' => "$FindBin::Bin/sp-client-hyperv/mustgather.pl",
        # Add more products as developed
    );

# Execute corresponding product script with provided parameters
if (exists $product_scripts{$product}) {

     # SECURITY: Set credentials in environment ONLY during execution
        local %ENV = (%ENV, 
            MUSTGATHER_ADMINID => $adminid || '',
            MUSTGATHER_PASSWORD => $password || ''
        );

    my $script = $product_scripts{$product};
    my @cmd = ("perl", $script, "-o", $output_dir);
    push @cmd, ("--product", $product) if $product;
    push @cmd, ("-m", $modules)       if $modules;
    push @cmd, "--no-compress"        if $no_compress;
    push @cmd, "-v"                   if $verbose;
    push @cmd, ("--optfile", $optfile) if $optfile;
    


    system(@cmd) == 0 or die "Failed to execute $script\n";

     # CRITICAL: IMMEDIATE cleanup after child exits
        delete $ENV{MUSTGATHER_ADMINID};
        delete $ENV{MUSTGATHER_PASSWORD};
}
else{
    print_usage();
    exit 0;
}

# SECURITY: Zero memory before compression
$password = undef if defined $password;
$adminid = undef if defined $adminid;


# ----------------------------------
# Usage helper
# ----------------------------------
sub print_usage {
    print <<"USAGE";
Usage: mustgather.pl --product <name> --output-dir <path> [optfile]

Mandatory:
  --product, -p      Product name (sp-client-ba, sp-client-vmware, sp-server-sta, sp-client-sql, sp-server, sp-client-space-mgmt, sp-client-hsm, sp-client-hyperv, sp-client-oracle, sp-client-exchange, sp-client-domino, sp-client-erp-sap-hana, sp-client-erp-db2, sp-client-erp-oracle ) 
  --output-dir, -o   Target folder for collected data
  --adminid, -id    Storage Protect server admin ID (password prompted securely)
  
Optional:
  --modules, -m      Comma-separated modules (default: all)
   \x1b[33mNote : For sp-client-ba, there is no need to provide the --module parameter; it collects all by default.\x1b[0m   
  --optfile          Path to optfile file (default if not provided)
  --no-compress      Disable compression
  --verbose, -v      Verbose logging
  --help, -h         Show this help
USAGE
}

# ----------------------------------
# Compress output folder if not disabled
# ----------------------------------
if (!$no_compress) {
    my $zip_name = "$output_dir.zip";

    if ($^O =~ /MSWin32/i) {
        # Windows compression using PowerShell
        my $ps_cmd = "powershell -Command \"Compress-Archive -Path '$output_dir\\*' -DestinationPath '$zip_name' -Force\"";
        system($ps_cmd) == 0
            or warn "Failed to compress folder on Windows: $!";
    } else {
        # Unix-like compression using zip
        system("zip -r '$zip_name' '$output_dir' >/dev/null 2>&1") == 0
            or warn "Failed to compress folder on Unix-like OS: $!";
    }

    # Remove uncompressed folder after compression
    remove_tree($output_dir, {error => \my $err});
    if (@$err) {
        warn "Errors occurred while removing $output_dir:\n";
        for my $diag (@$err) {
            my ($file, $message) = %$diag;
            warn "$file: $message\n";
        }
    }
}
 print "This file can be sent to IBM Support team for analysis.\n\n";