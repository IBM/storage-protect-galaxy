#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use FindBin;
use Getopt::Long;
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;

# --------------------------------------------------
# Parse command-line arguments
# --------------------------------------------------
my ($output_dir, $options, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "optfile=s"      => \$options,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments\n";

die "Error: --output-dir is required\n" unless $output_dir;

# SECURITY: Get credentials from ENVIRONMENT only
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || ''; 

# --------------------------------------------------
# Prepare output directory
# --------------------------------------------------
$output_dir = "$output_dir/nas-ndmp";
make_path($output_dir) unless -d $output_dir;

# --------------------------------------------------
# Logging
# --------------------------------------------------
my $log_file = "$output_dir/script.log";
open(my $logfh, '>', $log_file) or die "Cannot open $log_file: $!";

sub log_msg {
    my ($msg) = @_;
    print $logfh "$msg\n";
    print "$msg\n" if $verbose;
}


# --------------------------------------------------
# Locate dsmadmc
# --------------------------------------------------
my $base_path = env::get_ba_base_path();
die "BA client base path not found\n" unless $base_path;

my $dsmadmc = ($^O =~ /MSWin32/i)
    ? "$base_path\\dsmadmc.exe"
    : "$base_path/dsmadmc";

die "dsmadmc not found\n" unless -e $dsmadmc;

my $opt_file   = $options ? $options : "$base_path/dsm.opt";
my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

# --------------------------------------------------
# User inputs (interactive)
# --------------------------------------------------
print "\nEnter NAS Node name: ";
my $node = <STDIN>; chomp($node);

die "Node name is required\n" unless $node;

print "Enter Data Mover name (required for backup issues): ";
my $mover = <STDIN>; chomp($mover);

print "Enter Filespace name (required for restore issues): ";
my $filespace = <STDIN>; chomp($filespace);

print "\nSelect issue type:\n";
print "  1) NAS NDMP Backup failure\n";
print "  2) NAS NDMP Restore issue\n";
print "Enter choice (1 or 2): ";

my $choice = <STDIN>;
chomp($choice);

die "Invalid choice\n" unless $choice eq '1' || $choice eq '2';

log_msg("Node      : $node");
log_msg("Mover     : $mover")     if $mover;
log_msg("Filespace : $filespace") if $filespace;
log_msg("Issue type: " . ($choice == 1 ? "Backup failure" : "Restore issue"));

# --------------------------------------------------
# Command runner
# --------------------------------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;
    my $full = qq{$cmd > "$outfile" 2>&1};
    print $logfh "Running: $cmd";
    return system($full) >> 8;
}

my %collected;

# --------------------------------------------------
# Backup failure collection
# --------------------------------------------------
if ($choice eq '1') {

    die "Mover name is required for backup failure\n" unless $mover;

    my %backup_cmds = (
        "node.out"               => qq{QUERY NODE $node TYPE=NAS FORMAT=DETAIL},
        "mover.out"              => qq{QUERY DATAMOVER $node TYPE=NAS FORMAT=DETAIL},
        "drive.out"              => qq{QUERY DRIVE FORMAT=DETAIL},
        "path.out"               => qq{QUERY PATH $mover FORMAT=DETAIL},
        "filespace.out"          => qq{QUERY FILESPACE $node},
        "virtualfsmapping.out"   => qq{QUERY VIRTUALFSMAPPING $node},
    );

    foreach my $file (sort keys %backup_cmds) {
        my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$backup_cmds{$file}"};
        my $rc  = run_cmd($cmd, "$output_dir/$file");
        $collected{$file} = ($rc == 0) ? "Success" : "Failed";
    }
}

# --------------------------------------------------
# Restore issue collection
# --------------------------------------------------
else {

    die "Filespace name is required for restore issue\n" unless $filespace;

    my %restore_cmds = (
        "node.out"        => qq{QUERY NODE $node TYPE=NAS FORMAT=DETAIL},
        "mover.out"       => qq{QUERY DATAMOVER $node TYPE=NAS FORMAT=DETAIL},
        "version.out"     => qq{SHOW VERSION $node $filespace},
        "nasbackup.out"   => qq{QUERY NASBACKUP $node $filespace},
    );

    foreach my $file (sort keys %restore_cmds) {
        my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$restore_cmds{$file}"};
        my $rc  = run_cmd($cmd, "$output_dir/$file");
        $collected{$file} = ($rc == 0) ? "Success" : "Failed";
    }
}

# --------------------------------------------------
# Summary
# --------------------------------------------------
log_msg("");
log_msg("==== NAS NDMP MustGather Summary ===");

foreach my $k (sort keys %collected) {
    log_msg(sprintf("  %-40s : %s", $k, $collected{$k}));
}

log_msg("Output directory : $output_dir");
log_msg("Log file         : $log_file");

close($logfh);

# --------------------------------------------------
# Exit status
# --------------------------------------------------
my ($ok, $fail) = (0, 0);
foreach my $v (values %collected) {
    $ok++   if $v eq "Success";
    $fail++ if $v ne "Success";
}

exit($fail ? 2 : 0);
