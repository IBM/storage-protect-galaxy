#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use Getopt::Long;

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $options);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$options,
) or die "Invalid arguments\n";

die "--output-dir required\n" unless $output_dir;

# -----------------------------
# Credentials from ENV
# -----------------------------
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || '';

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/lanfree";
make_path($output_dir) unless -d $output_dir;

my $error_log = "$output_dir/script.log";
open(my $errfh, ">", $error_log) or die "Cannot open script.log\n";

# -----------------------------
# Detect BA client
# -----------------------------
my $base_path = env::get_ba_base_path()
    or die "BA client not found\n";

my $dsmadmc = ($^O =~ /MSWin32/)
    ? "$base_path\\dsmadmc.exe"
    : "$base_path/dsmadmc";

die "dsmadmc not executable\n" unless -x $dsmadmc;

my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;

my $opt_file = $options || (
    $^O =~ /MSWin32/ ? "$base_path\\dsm.opt" : "$base_path/dsm.opt"
);

my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

# -----------------------------
# Prompt for LAN-free details
# -----------------------------
print "\nEnter NODE name for LAN-free validation: ";
chomp(my $node = <STDIN>);

print "Enter STORAGE AGENT name: ";
chomp(my $agent = <STDIN>);

if (!$node || !$agent) {
    print $errfh "Node or storage agent not provided\n";
    exit 1;
}

# -----------------------------
# Cross-platform command runner
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;

    my $full_cmd;

    if ($outfile) {
        $full_cmd = qq{$cmd > "$outfile"};
        $full_cmd .= " 2>&1" if $^O !~ /MSWin32/;
    } else {
        $full_cmd = $cmd;
    }

    print $errfh "Running: $full_cmd\n" if $verbose;

    my $status = system($full_cmd);
    $status >>= 8;

    return $status;
}

my %collected;

# -----------------------------
# VALIDATE LANFREE
# -----------------------------
my $validate_out = "$output_dir/validate.out";

my $validate_cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "validate lanfree $node $agent"};

my $rc = run_cmd($validate_cmd, $validate_out);

$collected{"validate.out"} =
    ($rc == 0 && -s $validate_out) ? "Success" : "Failed";

# -----------------------------
# PING SERVER
# -----------------------------
my $ping_out = "$output_dir/ping.out";

my $ping_cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "ping server $agent"};

$rc = run_cmd($ping_cmd, $ping_out);

$collected{"ping.out"} =
    ($rc == 0 && -s $ping_out) ? "Success" : "Failed";

# -----------------------------
# Call Tape module
# -----------------------------
my $tape_script = "$FindBin::Bin/tape.pl";

if (-f $tape_script) {

    my @args = (
        "perl",
        $tape_script,
        "-o", $output_dir,
    );

    push @args, "--optfile", $options if $options;
    push @args, "-v" if $verbose;

    my $tape_rc = system(@args) >> 8;

    $collected{"tape_module"} =
        ($tape_rc == 0) ? "Success" :
        ($tape_rc == 2) ? "Partial" :
                          "Failed";

} else {
    $collected{"tape_module"} = "Not Found";
}

# -----------------------------
# Module-level summary
# -----------------------------
close($errfh);

if ($verbose) {

    print "\n=== LAN-Free Module Summary ===\n";

    foreach my $k (sort keys %collected) {
        printf "  %-15s : %s\n", $k, $collected{$k};
    }

    print "Collected files in: $output_dir\n";
}

# -----------------------------
# Determine module status
# -----------------------------
my $success_count = 0;
my $fail_count    = 0;
my $total         = scalar keys %collected;

foreach my $v (values %collected) {

    $success_count++ if $v eq "Success";
    $fail_count++    if $v eq "Failed";

}

my $module_status;

if ($success_count == $total) {
    $module_status = "Success";
}
elsif ($fail_count == $total) {
    $module_status = "Failed";
}
else {
    $module_status = "Partial";
}

exit(
    $module_status eq "Success" ? 0 :
    $module_status eq "Partial" ? 2 :
                                  1
);
