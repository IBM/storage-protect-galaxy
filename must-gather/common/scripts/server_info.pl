#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use FindBin;
use File::Path qw(make_path);
use lib "$FindBin::Bin/../modules";
use env;
use utils;
# -----------------------------
# Parameters / CLI optfile
# -----------------------------
my ($output_dir, $adminid, $password, $verbose, $optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "adminid|id=s"   => \$adminid,
    "password|pwd=s" => \$password,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$optfile,
) or die "Invalid arguments. Run with --help for usage.\n";
die "Error: --output-dir is required\n" unless $output_dir;
die "Error: --adminid is required\n"   unless $adminid;
die "Error: --password is required\n"  unless $password;
# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/server";
make_path($output_dir) unless -d $output_dir;
# -----------------------------
# Error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";
# -----------------------------
# Detect BA client base path
# -----------------------------
my $base_path = env::get_ba_base_path();
unless ($base_path) {
    print $errfh "BA client base path not found.\n";
    close($errfh);
    die "BA client base path not found. Exiting.\n";
}
# -----------------------------
# Determine which dsm.opt to use
# -----------------------------
my $opt_file;
if ($optfile) {
    # User-specified option file
    $opt_file = $optfile;
} else {
    $opt_file = "$base_path/dsm.opt";
}
# -----------------------------
# Locate DSMADMC binary (platform dependent)
# -----------------------------
my $os = $^O;
my $dsmadmc;
if ($os =~ /MSWin32/i) {
    $dsmadmc = `where dsmadmc.exe 2>nul`;
    chomp($dsmadmc);
    if (!$dsmadmc || !-e $dsmadmc) {
        $dsmadmc = "$base_path\\dsmadmc.exe" if -e "$base_path\\dsmadmc.exe";
    }
} else {
    $dsmadmc = `which dsmadmc 2>/dev/null`;
    chomp($dsmadmc);
    if (!$dsmadmc || !-x $dsmadmc) {
        $dsmadmc = "$base_path/dsmadmc" if -x "$base_path/dsmadmc";
    }
}
unless ($dsmadmc && -x $dsmadmc) {
    print $errfh "dsmadmc not found at $dsmadmc\n";
    close($errfh);
    die "dsmadmc not found at $dsmadmc\n";
}
# -----------------------------
# Quote paths if they contain spaces
# -----------------------------
my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;
# -----------------------------
# Function to run a command safely
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;
    my $full_cmd;
    if ($outfile) {
        $full_cmd = qq{$cmd > "$outfile"};
        $full_cmd .= " 2>&1" if $^O !~ /MSWin32/;  # redirect stderr on Unix
    } else {
        $full_cmd = $cmd;
    }

    print $errfh "Running: $full_cmd\n" if $verbose;

    my $status = system($full_cmd);
    $status >>= 8;
    return $status;
}


# -----------------------------
# Define dsm administrative queries
# -----------------------------
my %server_queries = (
    "actlog.txt"    => "query actlog begindate=today-7",
    "system.txt"    => "query system",
    "pools.txt"     => "q stgpool f=d",
    "nodes.txt"     => "q node f=d",
    "occupancy.txt" => "q occ",
    "schedules.txt" => "q schedule f=d",
    "events.txt"    => "q event * * begindate=today-7",
);
# -----------------------------
# Run queries and collect output
# -----------------------------
foreach my $file (sort keys %server_queries) {
    my $query = $server_queries{$file};
    my $outfile = "$output_dir/$file";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
    run_cmd($cmd, $outfile);
}

# -----------------------------
# Summary
# -----------------------------
close($errfh);

my %summary;

# Static queries
foreach my $file (sort keys %server_queries) {
    my $outfile = "$output_dir/$file";
    $summary{$file} = (-s $outfile) ? "Success" : "Failed";
}
if ($verbose) {
    print "\n=== Server Module Summary ===\n";
    foreach my $file (sort keys %summary) {
        printf "  %-15s : %s\n", $file, $summary{$file};
    }
    print "Collected server info saved in: $output_dir\n";
    print "Check script.log for any failures.\n";
}
# -----------------------------
# Determine module-level status for framework
# -----------------------------
my $Success_count = 0;
my $fail_count = 0;
my $total = scalar keys %summary;
foreach my $status (values %summary) {
    $Success_count++ if $status eq "Success";
    $fail_count++    if $status eq "Failed";
}
my $module_status;
if ($Success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}
# Exit code mapping for framework (optional: 0=Success, 1=failure, 2=Partial)
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);