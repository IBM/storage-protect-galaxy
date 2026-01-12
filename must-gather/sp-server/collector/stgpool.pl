#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use FindBin;
use File::Path qw(make_path);
use File::Copy qw(copy);
use lib "$FindBin::Bin/../../common/modules";
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
    "optfile=s"       => \$optfile,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;
die "Error: --adminid is required\n"   unless $adminid;
die "Error: --password is required\n"  unless $password;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/stgpool";
my @subdirs = qw(backup reclamation migration container);
foreach my $sub (@subdirs) {
    make_path("$output_dir/$sub") unless -d "$output_dir/$sub";
}

# -----------------------------
# Error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Detect BA client path
# -----------------------------
my $base_path = env::get_ba_base_path();
unless ($base_path) {
    print $errfh "BA client base path not found.\n";
    close($errfh);
    die "BA client base path not found. Exiting.\n";
}


# -----------------------------
# Locate DSMADMC binary
# -----------------------------
my $dsmadmc = "$base_path/dsmadmc";
$dsmadmc .= ".exe" if $^O =~ /MSWin32/;
unless (-x $dsmadmc) {
    print $errfh "dsmadmc not found at $dsmadmc\n";
    close($errfh);
    die "dsmadmc not found at $dsmadmc\n";
}

# -----------------------------
# DSM Option File Path
# -----------------------------
my $opt_file;
if ($optfile) {
    # User-specified option file
    $opt_file = $optfile;
} else {
    $opt_file = "$base_path/dsm.opt";
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
        $full_cmd .= " 2>&1" if $^O !~ /MSWin32/;
    } else {
        $full_cmd = $cmd;
    }

    print $errfh "Running: $full_cmd\n" if $verbose;

    my $status = system($full_cmd);
    $status >>= 8;
    return $status;
}

# -----------------------------
# Define dsm administrative client queries
# -----------------------------
my %static_queries = (
    "backup" => {
        "stgpool.txt" => "q stgpool f=d",
        "libv.txt"    => "q libv f=d",
    },
    "reclamation" => {
        "stgpool.txt" => "q stgpool f=d",
        "volume.txt"  => "q volume f=d",
        "libv.txt"    => "q libv f=d",
    },
    "migration" => {
        "stgpool.txt" => "q stgpool f=d",
        "volume.txt"  => "q volume f=d",
        "libv.txt"    => "q libv f=d",
    },
    "container" => {
        "container.txt" => "q container",
    },
);

# Run static queries
foreach my $category (keys %static_queries) {
    foreach my $file (keys %{ $static_queries{$category} }) {
        my $query = $static_queries{$category}{$file};
        my $outfile = "$output_dir/$category/$file";
        my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
        run_cmd($cmd, $outfile);
    }
}

# -----------------------------
# Dynamic Queries (Per Storage Pool)
# -----------------------------
my $stglist_file = "$output_dir/stgpool_list.txt";
my $select_cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "select STGPOOL_NAME, STG_TYPE from STGPOOLS"};
run_cmd($select_cmd, $stglist_file);

open(my $sfh, '<', $stglist_file) or die "Cannot open $stglist_file: $!";
my @stgpools;
while (<$sfh>) {
    next if /^\s*$/                                  # skip blank lines
         || /ANR/                                    # skip ANR messages
         || /ANS/                                    # skip ANS messages
         || /STGPOOL_NAME/i                          # skip stgpool header
         || /-+/                                     # skip dashed lines
         || /IBM Storage Protect/i    
         || /Server/
         || /Session/                                # skip product name
         || /Command Line Administrative Interface/i # skip version info
         || /\(c\)/ 
         || /Copyright IBM Corp/i;                    # skip copyright  
    s/^\s+|\s+$//g;
    my @cols = split(/\s+/, $_, 2);
    next unless scalar @cols == 2;
    my ($name, $type) = @cols;
    push @stgpools, { name => $name, type => $type };
}
close($sfh);

# -----------------------------
# Per Storage Pool Queries
# -----------------------------
foreach my $pool (@stgpools) {
    my $name = $pool->{name};
    my $type = uc($pool->{type});
    # SHOW TRANSFERSTATS in multiple folders
    foreach my $cat (qw(backup reclamation migration)) {
        my $outfile = "$output_dir/$cat/transferstats_$name.txt";
        my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "show transferstats $name"};
        run_cmd($cmd, $outfile);
    }

    # -----------------------------
    # Container-type Queries
    # -----------------------------
    if ($type eq 'CLOUD' || $type eq 'DIRECTORY') {
        my %container_queries = (
            "showsdpool_$name.txt"        => "show sdpool $name",
            "extentupdate_$name.txt"      => "q extentupdates $name",
            "damaged_extent_$name.txt"    => "q damage $name",
            "damaged_container_$name.txt" => "q damage $name type=container",
            "damaged_node_$name.txt"      => "q damage $name type=node",
        );

        foreach my $file (sort keys %container_queries) {
            my $query = $container_queries{$file};
            my $outfile = "$output_dir/container/$file";
            my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
            run_cmd($cmd, $outfile);
        }
    }
}

# -----------------------------
#  Summary Section
# -----------------------------
my %summary;

foreach my $file (keys %static_queries) {
    my $outfile = "$output_dir/$file";
    $summary{$file} = (-s $outfile) ? "SUCCESS" : "FAILED";
}



if ($verbose) {
    print "\n=== Storage Pool Summary ===\n";
    foreach my $file (sort keys %summary) {
        printf "  %-15s : %s\n", $file, $summary{$file};
    }
    print "\nOutput directory: $output_dir\n";
    print "Error log: $error_log\n";
}

close($errfh);
