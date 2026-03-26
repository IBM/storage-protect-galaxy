#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Find;
use File::Copy;
use File::Basename;
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;
use Getopt::Long;

# ===============================================================
# Script Name : sap-hana.pl
# Description : Collects SAP HANA specific diagnostic data
# ===============================================================

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/sap-hana";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup
# -----------------------------
my $os = env::_os();
my %collected_files;
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print "\n=== Starting SAP HANA-Specific Data Collection ===\n" if $verbose;
print $errfh "Detected OS: $os\n";
print $errfh "Note: OS info and TSM client config collected by system/config modules\n";

# -----------------------------
# Collect TSM API Configuration Files
# -----------------------------
print "Collecting TSM API configuration files...\n" if $verbose;

my @api_config_paths = (
    "/opt/tivoli/tsm/client/api/bin64/dsm.sys",
    "/opt/tivoli/tsm/client/api/bin64/dsm.opt",
    "/opt/tivoli/tsm/client/api/bin/dsm.sys",
    "/opt/tivoli/tsm/client/api/bin/dsm.opt",
);

foreach my $config_file (@api_config_paths) {

    my $filename = "api_" . basename($config_file);
    my $dest = "$output_dir/$filename";

    if (-e $config_file) {

        if (copy($config_file, $dest)) {
            print $errfh "Collected: $config_file\n";
            $collected_files{$filename} = "Success";
        }
        else {
            print $errfh "Failed to copy $config_file: $!\n";
            $collected_files{$filename} = "Failed";
        }

    }
    else {
        print $errfh "Not found: $config_file\n";
        $collected_files{$filename} = "NOT FOUND";
    }
}

# -----------------------------
# Detect SAP HANA SID
# -----------------------------
print "Detecting SAP HANA SID...\n" if $verbose;
my @sids;

if (-d "/usr/sap") {
    opendir(my $dh, "/usr/sap") or warn "Cannot open /usr/sap: $!";
    while (my $entry = readdir($dh)) {
        next if $entry =~ /^\.\.?$/;
        next if $entry eq "hostctrl";
        if (-d "/usr/sap/$entry" && $entry =~ /^[A-Z0-9]{3}$/) {
            push @sids, $entry;
        }
    }
    closedir($dh);
}

if (!@sids) {
    my $ps_output = `ps -ef | grep -i hdb | grep -v grep 2>/dev/null`;
    if ($ps_output =~ m{/usr/sap/([A-Z0-9]{3})/}) {
        push @sids, $1 unless grep { $_ eq $1 } @sids;
    }
}

if (@sids) {
    print $errfh "Detected SAP HANA SID(s): " . join(", ", @sids) . "\n";
} else {
    print $errfh "Warning: No SAP HANA SID detected\n";
    @sids = ("XXX");
}

# -----------------------------
# Collect SAP HANA Version
# -----------------------------
my $version_file = "$output_dir/hana_version.txt";

foreach my $sid (@sids) {
    next if $sid eq "XXX";

    my $sid_lc = lc($sid);
    my $cmd = "su - ${sid_lc}adm -c 'HDB version' 2>/dev/null";
    my $out = `$cmd`;

    if ($out) {
        open(my $fh, '>>', $version_file);
        print $fh "=== SAP HANA Version for SID: $sid ===\n$out\n";
        close($fh);
    }
}

$collected_files{"hana_version.txt"} = (-s $version_file) ? "Success" : "NOT FOUND";

# -----------------------------
# Collect global.ini
# -----------------------------
foreach my $sid (@sids) {

    next if $sid eq "XXX";
    my $found = 0;

    my @paths = (
        "/usr/sap/$sid/SYS/global/hdb/custom/config/global.ini",
        "/hana/shared/$sid/global/hdb/custom/config/global.ini",
    );

    foreach my $file (@paths) {

        if (-e $file) {

            my $dest = "$output_dir/global.ini_${sid}";

            if (copy($file, $dest)) {
                print $errfh "Collected: $file\n";
                $collected_files{"global.ini_${sid}"} = "Success";
            }
            else {
                print $errfh "Failed to copy $file: $!\n";
                $collected_files{"global.ini_${sid}"} = "Failed";
            }

            $found = 1;
            last;
        }
    }

    if (!$found) {
        print $errfh "Warning: global.ini not found for SID $sid\n";
        $collected_files{"global.ini_${sid}"} = "NOT FOUND";
    }
}

# -----------------------------
# Collect initSID.utl
# -----------------------------
foreach my $sid (@sids) {

    next if $sid eq "XXX";
    my $found = 0;

    my @paths = (
        "/usr/sap/$sid/SYS/global/hdb/opt/hdbconfig/init${sid}.utl",
        "/hana/shared/$sid/global/hdb/opt/hdbconfig/init${sid}.utl",
    );

    foreach my $file (@paths) {

        if (-e $file) {

            my $dest = "$output_dir/init${sid}.utl";

            if (copy($file, $dest)) {
                print $errfh "Collected: $file\n";
                $collected_files{"init${sid}.utl"} = "Success";
            }
            else {
                print $errfh "Failed to copy $file: $!\n";
                $collected_files{"init${sid}.utl"} = "Failed";
            }

            $found = 1;
            last;
        }
    }

    if (!$found) {
        print $errfh "Warning: init${sid}.utl not found\n";
        $collected_files{"init${sid}.utl"} = "NOT FOUND";
    }
}

# -----------------------------
# Helper function
# -----------------------------
sub collect_file {

    my ($src, $name) = @_;
    my $dest = "$output_dir/$name";

    if (-e $src) {

        if (copy($src, $dest)) {
            print $errfh "Collected: $src\n";
            $collected_files{$name} = "Success";
        }
        else {
            print $errfh "Failed to copy $src: $!\n";
            $collected_files{$name} = "Failed";
        }

    }
    else {
        print $errfh "Warning: $src not found\n";
        $collected_files{$name} = "NOT FOUND";
    }
}

# -----------------------------
# Collect Backup Logs
# -----------------------------
foreach my $sid (@sids) {

    next if $sid eq "XXX";

    my @trace_patterns = (
        "/usr/sap/$sid/HDB*/*/trace",
        "/hana/shared/$sid/HDB*/*/trace",
    );

    my @trace_dirs;

    foreach my $pattern (@trace_patterns) {
        push @trace_dirs, glob($pattern);
    }

    if (!@trace_dirs) {
        print $errfh "Warning: No trace directories found for SID $sid\n";
    }

    foreach my $trace_dir (@trace_dirs) {

        my $host = basename(dirname($trace_dir));

        collect_file("$trace_dir/backup.log","backup_${sid}_${host}.log");
        collect_file("$trace_dir/backint.log","backint_${sid}_${host}.log");
        collect_file("$trace_dir/backint_version_delete.log","backint_version_delete_${sid}_${host}.log");

        my $db_dir = "$trace_dir/DB_$sid";

        if (-d $db_dir) {

            foreach my $log ("backup.log","backint.log") {

                collect_file(
                    "$db_dir/$log",
                    "${log}_DB_${sid}_${host}"
                );
            }

        }
        else {
            print $errfh "Warning: DB directory not found: $db_dir\n";
        }
    }
}

# -----------------------------
# Collect setup and install logs
# -----------------------------
my $tdp_hana_dir = "/opt/tivoli/tsm/tdp_hana";

if (-d $tdp_hana_dir) {

    my $setup = "$tdp_hana_dir/setup.sh";
    my $install = "$tdp_hana_dir/installation.log";

    collect_file($setup,"setup.sh");
    collect_file($install,"installation.log");

}
else {
    print $errfh "Directory not found: $tdp_hana_dir\n";
    $collected_files{"setup.sh"} = "NOT FOUND";
    $collected_files{"installation.log"} = "NOT FOUND";
}

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {

    print "\n=== SAP HANA Module Summary ===\n";

    foreach my $file (sort keys %collected_files) {
        printf "  %-40s : %s\n", $file, $collected_files{$file};
    }

    print "\nCollected data saved in: $output_dir\n";
}

# -----------------------------
# Exit code
# -----------------------------
my $success_count = grep { $collected_files{$_} eq "Success" } keys %collected_files;
my $total = scalar keys %collected_files;

my $exit_code;

if ($success_count == 0) {
    $exit_code = 1;
}
elsif ($success_count == $total) {
    $exit_code = 0;
}
else {
    $exit_code = 2;
}

exit($exit_code);