#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);          
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
# Utilities
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;
    if ($outfile) {
        my $full = qq{$cmd > "$outfile" 2>&1};
        print $logfh "Running: $full\n" if $verbose;
        my $rc = system($full);
        $rc >>= 8;
        return $rc;
    } else {
        print $logfh "Running capture: $cmd\n" if $verbose;
        my $out = `$cmd 2>/dev/null`;
        chomp $out;
        return $out;
    }
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

sub collect_db2support {

    my ($outdir) = @_;

    my $info = env::get_sp_instance_info();
    return unless $info && $info->{instance} && $info->{directory};

    my $inst = $info->{instance};
    my $home = $info->{directory};

    my $support_dir = File::Spec->catdir($outdir, 'db2support');
    make_path($support_dir) unless -d $support_dir;

    # -------- FIX: ownership for instance user --------
    if ($^O !~ /MSWin32/i) {
        system("chown -R $inst $support_dir");
        system("chmod -R 755 $support_dir");
    }

    my $support_out = File::Spec->catfile($outdir, "${inst}_db2support.out");
    my $target_zip  = File::Spec->catfile($outdir, "${inst}_db2support.zip");

    if ($^O =~ /MSWin32/i) {

        my $rc = run_cmd(
            qq{db2cmd /i /w /c db2support "$support_dir" -d TSMDB1 -c -s},
            $support_out
        );

        my $zip = File::Spec->catfile($support_dir, 'db2support.zip');
        if (-e $zip && -s $zip) {
            copy($zip, $target_zip);
            $summary{"$inst:db2support.zip"} = 'Success';
        } else {
            $summary{"$inst:db2support.zip"} = ($rc == 0 ? 'ATTEMPTED' : 'Failed');
        }

    } else {

        my $cmd = qq{
            . ~$inst/sqllib/db2profile &&
            cd "$support_dir" &&
            db2support . -d TSMDB1 -c -s
        };

        my $rc = run_cmd(qq{su - $inst -c '$cmd'}, $support_out);

        my $zip = File::Spec->catfile($support_dir, 'db2support.zip');
        if (-e $zip && -s $zip) {
            copy($zip, $target_zip);
            $summary{"$inst:db2support.zip"} = 'Success';
        } else {
            $summary{"$inst:db2support.zip"} = ($rc == 0 ? 'ATTEMPTED' : 'Failed');
        }
    }
}

collect_db2support($output_dir);

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
