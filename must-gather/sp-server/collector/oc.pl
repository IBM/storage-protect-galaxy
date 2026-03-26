#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(copy);
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

die "Error: --output-dir is required\n" unless $output_dir;

# SECURITY: Get credentials from ENVIRONMENT only
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || ''; 
# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/oc";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Get Storage Protect base path
# -----------------------------
my $install_dir = env::get_sp_base_path();
unless ($install_dir) {
    print $errfh "Storage Protect base path not found\n";
    close($errfh);
    die "Storage Protect base path not found\n";
}

# -----------------------------
# Normalize base path for OC
# -----------------------------
my $oc_base = $install_dir;
$oc_base =~ s{/server/bin$}{};
$oc_base =~ s{/server$}{};
$oc_base =~ s{\\server$}{}i;

print $errfh "Resolved SP base : $install_dir\n" if $verbose;
print $errfh "Resolved OC base : $oc_base\n"      if $verbose;

# -----------------------------
# Detect BA client base path
# -----------------------------
my $base_path = env::get_ba_base_path();
unless ($base_path) {
    print $errfh "BA client base path not found\n";
    close($errfh);
    die "BA client base path not found\n";
}

# -----------------------------
# Locate dsmadmc
# -----------------------------
my $dsmadmc;
if ($^O =~ /MSWin32/i) {
    $dsmadmc = `where dsmadmc.exe 2>nul`;
    chomp($dsmadmc);
    $dsmadmc = "$base_path\\dsmadmc.exe" if (!$dsmadmc && -e "$base_path\\dsmadmc.exe");
} else {
    $dsmadmc = `which dsmadmc 2>/dev/null`;
    chomp($dsmadmc);
    $dsmadmc = "$base_path/dsmadmc" if (!$dsmadmc && -x "$base_path/dsmadmc");
}

unless ($dsmadmc && -e $dsmadmc) {
    print $errfh "dsmadmc not found\n";
    close($errfh);
    die "dsmadmc not found\n";
}

# -----------------------------
# DSM option file
# -----------------------------
my $opt_file = $options ? $options : "$base_path/dsm.opt";
my $quoted_dsm = $dsmadmc =~ / / ? qq{"$dsmadmc"} : $dsmadmc;
my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;

# -----------------------------
# Command runner
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;
    my $full = qq{$cmd > "$outfile"};
    $full .= " 2>&1" if $^O !~ /MSWin32/;
    print $errfh "Running: $full\n" if $verbose;
    return system($full) >> 8;
}

# -----------------------------
# Storage Protect queries
# -----------------------------
my %sp_queries = (
    "qserver.out"    => "QUERY SERVER FORMAT=DETAIL",
    "qsess.out"      => "QUERY SESSION",
    "monserv.out"    => "SHOW MONSERVERS",
    "monsetting.out" => "QUERY MONITORSETTINGS",
);

my %collected;

foreach my $file (sort keys %sp_queries) {
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$sp_queries{$file}"};
    my $rc  = run_cmd($cmd, "$output_dir/$file");
    $collected{$file} = ($rc == 0) ? "Success" : "Failed";
}

# -----------------------------
# OC log directory
# -----------------------------
my $oc_log_dir;
if ($^O =~ /MSWin32/i) {
    $oc_log_dir = "$oc_base\\ui\\Liberty\\usr\\servers\\guiServer\\logs";
} else {
    $oc_log_dir = "$oc_base/ui/Liberty/usr/servers/guiServer/logs";
}

print $errfh "OC log directory: $oc_log_dir\n" if $verbose;

# -----------------------------
# Collect OC logs
# -----------------------------
if (-d $oc_log_dir) {

    my @fixed_logs = (
        "console.log",
        "messages.log",
        "tsm_opscntr.log",
        "tsm_opscntr1.log",
        "tsm_opscntr2.log",
        "tsm_opscntr3.log",
        "tsm_opscntr4.log",
        "tsm_opscntr5.log",
        "tsm_opscntr6.log",
        "tsm_opscntr7.log",
    );

    foreach my $f (@fixed_logs) {
        my $src = "$oc_log_dir/$f";
        my $dst = "$output_dir/$f";

        if (-e $src) {
            if (copy($src, $dst)) {
                $collected{$f} = "Success";
            } else {
                print $errfh "Failed to copy $src : $!\n";
                $collected{$f} = "Failed";
            }
        } else {
            $collected{$f} = "NOT FOUND";
        }
    }

    # -----------------------------
    # Collect EVERYTHING from logs/ffdc
    # -----------------------------
    my $ffdc_dir = "$oc_log_dir/ffdc";

    if (-d $ffdc_dir) {
        opendir(my $fdh, $ffdc_dir)
            or print $errfh "Cannot open FFDC directory: $ffdc_dir\n";

        while (my $f = readdir($fdh)) {
            next if $f eq '.' || $f eq '..';

            my $src = "$ffdc_dir/$f";
            next unless -f $src;

            my $dst = "$output_dir/ffdc_$f";

            if (copy($src, $dst)) {
                $collected{"ffdc_$f"} = "Success";
            } else {
                print $errfh "Failed to copy FFDC file $src : $!\n";
                $collected{"ffdc_$f"} = "Failed";
            }
        }
        closedir($fdh);
    } else {
        print $errfh "FFDC directory not found: $ffdc_dir\n";
    }

} else {
    print $errfh "OC log directory not found: $oc_log_dir\n";
}

close($errfh);

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {
    print "\n=== Operations Center MustGather Summary ===\n";
    foreach my $k (sort keys %collected) {
        printf "  %-45s : %s\n", $k, $collected{$k};
    }
    print "\nOperation Center data collected in: $output_dir\n";
    print "See script.log for details\n";
}

# -----------------------------
# Exit status
# -----------------------------
my ($ok, $fail) = (0, 0);
foreach my $v (values %collected) {
    $ok++   if $v eq "Success";
    $fail++ if $v eq "Failed";
}

exit($ok && !$fail ? 0 : $ok ? 2 : 1);
