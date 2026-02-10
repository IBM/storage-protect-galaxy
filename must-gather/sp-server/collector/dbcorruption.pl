#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use FindBin;
use Getopt::Long;
use lib "$FindBin::Bin/../../common/modules";
use env;

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
# SECURITY: Get credentials from ENVIRONMENT only
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || ''; 
# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/database-corruption";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Log setup
# -----------------------------
my $log_file = "$output_dir/script.log";
open(my $logfh, '>', $log_file) or die "Cannot open $log_file: $!";

sub log_msg {
    my ($msg) = @_;
    print $logfh "$msg\n";
    print "$msg\n" if $verbose;
}


# -----------------------------
# Detect DB2 instance
# -----------------------------
my $inst_info = env::get_sp_instance_info();
die "Unable to detect DB2 instance\n" unless $inst_info;

my $db2inst   = $inst_info->{instance};
my $inst_home = $inst_info->{directory};


# -----------------------------
# Locate dsmadmc
# -----------------------------
my $base_path = env::get_ba_base_path();
die "BA client base path not found\n" unless $base_path;

my $dsmadmc = ($^O =~ /MSWin32/i)
    ? "$base_path\\dsmadmc.exe"
    : "$base_path/dsmadmc";

die "dsmadmc not found\n" unless -x $dsmadmc;

my $opt_file   = $options || "$base_path/dsm.opt";
my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

# -----------------------------
# QUERY DB
# -----------------------------
my %summary;

my $qdb_out = "$output_dir/query_db.out";
my $qdb_cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "QUERY DB FORMAT=DETAIL"};
my $rc = system("$qdb_cmd > \"$qdb_out\" 2>&1") >> 8;
$summary{"QUERY DB"} = ($rc == 0) ? "Success" : "Failed";


# -----------------------------
# Fix permissions for DB2 instance
# -----------------------------
unless ($^O =~ /MSWin32/i) {
    system("chown -R $db2inst $output_dir");
    system("chmod -R 755 $output_dir");
}

# -----------------------------
# Run db2dart
# -----------------------------
my $db_name = "TSMDB1";

# -----------------------------
# Run db2support
# -----------------------------

my $db2support_out = "$output_dir/db2support.out";
my $db2support_cmd = qq{su - $db2inst -c "cd $output_dir && db2support . -d $db_name -c -s"};
$rc = system("$db2support_cmd > \"$db2support_out\" 2>&1") >> 8;
$summary{"db2support"} = ($rc == 0) ? "Success" : "Failed";

# -----------------------------
# Summary
# -----------------------------
log_msg("\n==== Database Corruption Summary ===\n");
foreach my $k (sort keys %summary) {
    log_msg(sprintf("  %-30s : %s", $k, $summary{$k}));
}
log_msg("Output directory: $output_dir");
log_msg("Log file: $log_file");
close($logfh);

# -----------------------------
# Module status
# -----------------------------
my ($ok, $fail) = (0, 0);
foreach my $v (values %summary) {
    $v eq "Success" ? $ok++ : $fail++;
}

exit($fail == 0 ? 0 : $ok == 0 ? 1 : 2);
