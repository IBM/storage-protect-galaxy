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
# Parameters
# -----------------------------
my ($output_dir, $verbose, $optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$optfile,
) or die "Invalid arguments.\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Credentials (ENV only)
# -----------------------------
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || '';

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/server";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Logging
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Validate credentials
# -----------------------------
my $server_failed = 0;
my $failure_reason = '';

unless ($adminid) {
    print $errfh "MUSTGATHER_ADMINID is required\n";
    $server_failed = 1;
    $failure_reason = "Missing AdminID";
}

unless ($password) {
    print $errfh "MUSTGATHER_PASSWORD is required\n";
    $server_failed = 1;
    $failure_reason = "Missing Password";
}

# -----------------------------
# Detect BA base path
# -----------------------------
my $base_path = env::get_ba_base_path();
unless ($base_path) {
    print $errfh "BA client base path not found.\n";
    $server_failed = 1;
    $failure_reason = "BA base path not found";
}

# -----------------------------
# Determine opt file
# -----------------------------
my $opt_file = $optfile ? $optfile : "$base_path/dsm.opt";

# -----------------------------
# Locate dsmadmc
# -----------------------------
my $os = $^O;
my $dsmadmc;

if ($os =~ /MSWin32/i) {
    $dsmadmc = `where dsmadmc.exe 2>nul`;
    chomp($dsmadmc);
    $dsmadmc ||= "$base_path\\dsmadmc.exe";
} else {
    $dsmadmc = `which dsmadmc 2>/dev/null`;
    chomp($dsmadmc);
    $dsmadmc ||= "$base_path/dsmadmc";
}

unless ($dsmadmc && -e $dsmadmc) {
    print $errfh "dsmadmc not found.\n";
    $server_failed = 1;
    $failure_reason = "dsmadmc not found";
}

my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

# -----------------------------
# Safe command runner (mask password)
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;

    my $full_cmd = qq{$cmd > "$outfile" 2>&1};

    # Mask password in logs
    my $log_cmd = $full_cmd;
    $log_cmd =~ s/-password=\S+/-password=********/i;

    print $errfh "Executing: $log_cmd\n" if $verbose;

    my $status = system($full_cmd);
    $status >>= 8;

    return $status;
}

# -----------------------------
# Connectivity Test
# -----------------------------
unless ($server_failed) {

    my $connect_file = "$output_dir/connect_test.txt";
    my $connect_cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "q status"};

    my $status = run_cmd($connect_cmd, $connect_file);

    if ($status != 0 || !-s $connect_file) {
        $server_failed = 1;
        $failure_reason = "Connectivity Failed";
    }
    else {
        open(my $fh, '<', $connect_file);
        while (<$fh>) {
            if (/ANS1025E|Authentication failure/i) {
                $server_failed = 1;
                $failure_reason = "Authentication Failed";
                last;
            }
        }
        close($fh);
    }
}

# -----------------------------
# Queries
# -----------------------------
my %server_queries = (
    "system.txt"    => "query system",
    "nodes.txt"     => "q node f=d",
    "occupancy.txt" => "q occ",
    "schedules.txt" => "q schedule f=d",
    "events.txt"    => "q event * * begindate=-7 enddate=-0",
    "backup_copygroups.txt"  => "q copygroup * * * standard type=backup f=d",
    "archive_copygroups.txt" => "q copygroup * * * standard type=archive f=d",
);

unless ($server_failed) {

    foreach my $file (sort keys %server_queries) {
        my $query = $server_queries{$file};
        my $outfile = "$output_dir/$file";
        my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
        run_cmd($cmd, $outfile);
    }

    my $actoutfile = "$output_dir/actlog.txt";
    my $act_cmd = qq{$quoted_dsm -comma -id=$adminid -password=$password -optfile=$quoted_opt "query actlog begindate=today-7"};
    run_cmd($act_cmd, $actoutfile);
}

close($errfh);

# -----------------------------
# Summary
# -----------------------------
my %summary;

foreach my $file (sort keys %server_queries) {

    if ($server_failed) {
        $summary{$file} = "Failed ($failure_reason)";
    }
    else {
        my $outfile = "$output_dir/$file";
        $summary{$file} = (-s $outfile) ? "Success" : "Failed";
    }
}

if ($verbose) {
    print "\n=== Server Module Summary ===\n";
    foreach my $file (sort keys %summary) {
        printf "  %-25s : %s\n", $file, $summary{$file};
    }
    print "Collected server info saved in: $output_dir\n";
}

# -----------------------------
# Exit Code
# -----------------------------
my $Success_count = 0;
my $fail_count = 0;
my $total = scalar keys %summary;

foreach my $status (values %summary) {
    $Success_count++ if $status =~ /^Success/;
    $fail_count++    if $status =~ /^Failed/;
}

my $module_status;
if ($Success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);