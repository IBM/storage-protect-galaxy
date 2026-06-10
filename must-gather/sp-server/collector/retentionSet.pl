#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use Getopt::Long;

# -----------------------------
# Parse arguments
# -----------------------------
my ($output_dir, $verbose, $optfile);
GetOptions(
    "output-dir|o=s"       => \$output_dir,
    "verbose|v"            => \$verbose,
    "optfile=s"            => \$optfile,
) or die "Invalid arguments\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Retention Rule Input
# -----------------------------
my $retention_rulename;
if (!$retention_rulename) {
    print "Enter Retention Rule Name: ";
    chomp($retention_rulename = <STDIN>);
}

die "Error: retention_rulename cannot be empty\n" unless $retention_rulename;

# -----------------------------
# Credentials (ENV)
# -----------------------------
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || '';

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/retentionSet";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Detect BA base path
# -----------------------------
my $base_path = env::get_ba_base_path();
unless ($base_path) {
    print $errfh "BA client base path not found\n";
    close($errfh);
    die "BA client base path not found\n";
}

# -----------------------------
# Locate DSMADMC
# -----------------------------
my $os = $^O;
my $dsmadmc;

if ($os =~ /MSWin32/i) {
    $dsmadmc = `where dsmadmc.exe 2>nul`;
    chomp($dsmadmc);
    $dsmadmc = "$base_path\\dsmadmc.exe" if !$dsmadmc;
} else {
    $dsmadmc = `which dsmadmc 2>/dev/null`;
    chomp($dsmadmc);
    $dsmadmc = "$base_path/dsmadmc" if !$dsmadmc;
}

unless ($dsmadmc && -x $dsmadmc) {
    print $errfh "dsmadmc not found\n";
    close($errfh);
    die "dsmadmc not found\n";
}

# -----------------------------
# Option file
# -----------------------------
my $opt_file = $optfile || "$base_path/dsm.opt";

my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

# -----------------------------
# Run command helper
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;

    my $full_cmd = qq{$cmd > "$outfile"};
    $full_cmd .= " 2>&1" if $^O !~ /MSWin32/;

    print $errfh "Running: $full_cmd\n" if $verbose;

    my $status = system($full_cmd);
    $status >>= 8;
    return $status;
}

# -----------------------------
# Define retention queries
# -----------------------------
my %retention_queries = (
    "retset.out"            => "query retset",
    "retrule.out"           => "query retrule f=d",
    "qjob.out"              => "query job",
    "qjobinterrupt.out"     => "query job status=interrupted",
    "qjobterm.out"          => "query job status=terminated",
    "qretsetcontent.out"    => "query retsetcontents retrulename=$retention_rulename f=d",
);

# -----------------------------
# Execute queries
# -----------------------------
foreach my $file (sort keys %retention_queries) {
    my $query = $retention_queries{$file};
    my $outfile = "$output_dir/$file";

    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
    run_cmd($cmd, $outfile);
}

# -----------------------------
# Summary
# -----------------------------
close($errfh);

my %summary;

foreach my $file (keys %retention_queries) {
    my $outfile = "$output_dir/$file";
    $summary{$file} = (-s $outfile) ? "Success" : "Failed";
}

if ($verbose) {
    print "\n=== RetentionSet Module Summary ===\n";
    foreach my $file (sort keys %summary) {
        printf "  %-25s : %s\n", $file, $summary{$file};
    }
    print "Collected files saved in: $output_dir\n";
    print "Check script.log for details\n";
}

# -----------------------------
# Exit status
# -----------------------------
my $success = grep { $_ eq "Success" } values %summary;
my $total   = scalar keys %summary;

my $module_status;
if ($success == $total) {
    $module_status = "Success";
} elsif ($success == 0) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);