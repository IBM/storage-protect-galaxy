#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);
use FindBin;
use Getopt::Long;
use Cwd qw(abs_path);
use File::Spec;

use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $options);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$options,
) or die "Invalid arguments\n";

die "Error: --output-dir is required\n" unless $output_dir;

# SECURITY: credentials from ENV only
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || '';

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/database-reorganisation";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

sub log_msg {
    my ($msg) = @_;
    print $errfh "$msg\n";
    print "$msg\n" if $verbose;
}

log_msg("Starting Storage Protect Database Reorganisation MustGather");

# -----------------------------
# Detect DB2 instance info
# -----------------------------
my $info = env::get_sp_instance_info();
unless ($info && $info->{instance} && $info->{directory}) {
    log_msg("ERROR: Unable to determine DB2 instance");
    close $errfh;
    exit 1;
}

my $inst = $info->{instance};
my $home = $info->{directory};

log_msg("Detected DB2 instance : $inst");
log_msg("Instance home         : $home");

# -----------------------------
# Utilities
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;
    if ($outfile) {
        my $full = qq{$cmd > "$outfile" 2>&1};
        print $errfh "Running: $full\n" if $verbose;
        my $rc = system($full);
        $rc >>= 8;
        return $rc;
    } else {
        print $errfh "Running capture: $cmd\n" if $verbose;
        my $out = `$cmd 2>/dev/null`;
        chomp $out;
        return $out;
    }
}
# -----------------------------
# Prepare instance-owned work dir
# -----------------------------
my $instance_work_dir = File::Spec->catdir($output_dir, 'instance-run');
make_path($instance_work_dir) unless -d $instance_work_dir;

if ($^O !~ /MSWin32/i) {
    system("chown -R $inst $instance_work_dir");
    system("chmod -R 755 $instance_work_dir");
}

# -----------------------------
# Locate dsmadmc
# -----------------------------
my $base_path = env::get_ba_base_path();
unless ($base_path) {
    log_msg("ERROR: BA client base path not found");
    close $errfh;
    exit 1;
}

my $dsmadmc;
if ($^O =~ /MSWin32/i) {
    $dsmadmc = `where dsmadmc.exe 2>nul`;
    chomp $dsmadmc;
    $dsmadmc = "$base_path\\dsmadmc.exe" if (!$dsmadmc && -e "$base_path\\dsmadmc.exe");
} else {
    $dsmadmc = `which dsmadmc 2>/dev/null`;
    chomp $dsmadmc;
    $dsmadmc = "$base_path/dsmadmc" if (!$dsmadmc && -x "$base_path/dsmadmc");
}

unless ($dsmadmc && -x $dsmadmc) {
    log_msg("ERROR: dsmadmc not found");
    close $errfh;
    exit 1;
}

my $opt_file   = $options ? $options : "$base_path/dsm.opt";
my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

# -----------------------------
# Collect ACTLOG (last 30 days)
# -----------------------------
log_msg("Collecting ACTLOG (last 30 days)");

my %collected_files;
my $actlog_out = "$output_dir/actlog_last_30_days.txt";

my $actlog_cmd =
    qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "q actlog begind=-30"};

my $rc = system("$actlog_cmd > \"$actlog_out\" 2>&1") >> 8;

$collected_files{'actlog_last_30_days.txt'} =
    (-s $actlog_out && $rc == 0) ? "Success" : "Failed";

# -----------------------------
# Locate reorg tools
# -----------------------------
my $tools_dir = abs_path("$FindBin::Bin/../tools");

my %scripts = (
    serverReorgInfo      => "$tools_dir/serverReorgInfo.pl",      # interactive
    analyze_DB2_formulas => "$tools_dir/analyze_DB2_formulas.pl", # non-interactive
);

foreach my $p (values %scripts) {
    unless (-e $p) {
        log_msg("ERROR: Missing required script: $p");
        close $errfh;
        exit 1;
    }
}

# -----------------------------
# Execute scripts as instance owner
# -----------------------------
foreach my $key (sort keys %scripts) {

    my $src = $scripts{$key};
    my $script = (File::Spec->splitpath($src))[2];
    my $dst = File::Spec->catfile($instance_work_dir, $script);

    copy($src, $dst);

    if ($^O !~ /MSWin32/i) {
        system("chown $inst $dst");
        system("chmod 755 $dst");
    }

    log_msg("Executing $script as instance owner");

    if ($^O =~ /MSWin32/i) {

        my $rc = system(qq{cd /d "$instance_work_dir" && perl "$dst"}) >> 8;
        $collected_files{$script} = ($rc == 0) ? "Success" : "Failed";

    } else {

        my $cmd = qq{
            . ~$inst/sqllib/db2profile &&
            cd "$instance_work_dir" &&
            perl "$script"
        };

        # Interactive script
        if ($key eq 'serverReorgInfo') {

            my $rc = system(qq{su - $inst -c '$cmd'}) >> 8;
            $collected_files{$script} = ($rc == 0) ? "Success" : "Failed";

        }
        # Non-interactive script
        else {

            my $rc = run_cmd(
                qq{su - $inst -c '$cmd'},
                File::Spec->catfile($instance_work_dir, "$script.out")
            );

            $collected_files{$script} = ($rc == 0) ? "Success" : "Failed";
        }
    }
}

# -----------------------------
# Collect generated files
# -----------------------------
opendir(my $dh, $instance_work_dir);
while (my $f = readdir($dh)) {
    next if $f =~ /^\./;
    my $src = "$instance_work_dir/$f";
    my $dst = "$output_dir/$f";
    next unless -f $src;

    open(my $in, '<', $src) or next;
    open(my $out, '>', $dst) or next;
    while (<$in>) { print $out $_ }
    close $in;
    close $out;

    $collected_files{$f} ||= "Success";
}
closedir($dh);

# -----------------------------
# Summary
# -----------------------------
close $errfh;

if ($verbose) {
    print "\n=== Database Reorganisation Module Summary ===\n";
    foreach my $f (sort keys %collected_files) {
        printf "  %-35s : %s\n", $f, $collected_files{$f};
    }
    print "Collected files saved in: $output_dir\n";
}

# -----------------------------
# Exit status
# -----------------------------
my ($ok, $fail) = (0, 0);
$ok++   for grep { $_ eq 'Success' } values %collected_files;
$fail++ for grep { $_ eq 'Failed'  } values %collected_files;

exit($fail == 0 ? 0 : $ok == 0 ? 1 : 2);
