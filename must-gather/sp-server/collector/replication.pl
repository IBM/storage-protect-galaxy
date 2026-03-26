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
my ($output_dir, $verbose, $optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,  
    "verbose|v"      => \$verbose,
    "optfile=s"       => \$optfile,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;

# SECURITY: Get credentials from ENVIRONMENT only
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || '';
# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/replication";
make_path($output_dir) unless -d $output_dir;

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
# Get all nodes with replication enabled
# -----------------------------
my $nodes_file = "$output_dir/nodes_raw.txt";
my $node_query = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "SELECT NODE_NAME FROM NODES WHERE REPL_STATE='ENABLED'"};
run_cmd($node_query, $nodes_file);

open(my $nf, '<', $nodes_file) or die "Cannot open $nodes_file: $!";
my %nodes_hash;
while (<$nf>) {
    chomp;
    # Skip blank lines
    next if /^\s*$/;

    # Skip only known non-data lines — not lines that might contain real node names
    next if /^(IBM|Command|ANS\d+|Replication|----|Copyright|\(c\)|Return code|No match|Highest return code)/i;
    next if /Session established with server/i;
    next if /Server Version/i;
    next if /Server date\/time/i;
    next if /^ANS\d+/;
    next if /ANR\d+E.*No match found/i; 
    # Skip column header lines
    next if /NODE_NAME/i;
    next if /^\s*-+\s*$/;

    # Trim whitespace
    s/^\s+|\s+$//g;

    # Store unique node names
    $nodes_hash{$_} = 1 if $_ ne '';
}
close($nf);
my @nodes = sort keys %nodes_hash;

# -----------------------------
# Get target replication server (second server preferred)
# -----------------------------
my $repl_file = "$output_dir/replserver_raw.txt";
my $repl_cmd  = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "QUERY REPLSERVER FORMAT=DETAILLIST"};
run_cmd($repl_cmd, $repl_file);

open(my $rf2, '<', $repl_file) or die "Cannot open $repl_file: $!";
my @lines = <$rf2>;
close($rf2);

my @servers;

foreach my $line (@lines) {
    next unless defined $line;
    chomp($line);
    $line =~ s/^\s+|\s+$//g;
    next if $line eq '';

    # Match "Server Name:" entries from the detailed output
    if ($line =~ /^Server Name:\s+(\S+)/i) {
        push @servers, $1;
    }
}

# Determine target replication server
my $target_server;
if (scalar @servers >= 2) {
    # Prefer second server (replication target)
    $target_server = $servers[1];
} elsif (scalar @servers == 1) {
    # Fallback to first if only one found
    $target_server = $servers[0];
    print $errfh "Only one replication server detected. Using '$target_server' as target.\n";
} else {
    # No servers detected
    print $errfh "No replication servers detected from QUERY REPLSERVER output.\n";
    $target_server = "";
}


# -----------------------------
# Define dsm administrative client queries
# -----------------------------
my %server_queries = (
    "replrule.txt"                => "query replrule",
    "replfailures_summary.txt"    => "query replfailures type=summary",
    "replfailures_objects.txt"    => "query replfailures type=objects",
    "replnodes.txt"               => "query replnode *",
    "replserver.txt"              => "query replserver",
    "filespace.txt"               => "query filespace * f=d",
    "occupancy.txt"               => "query occupancy",
    "stgrule.txt"                 => "query stgrule f=d",
    "unresolvedchunks.txt"        => "show unresolvedchunks",
);

run_cmd(
    qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "query occupancy"},
    "$output_dir/qocc.csv"
);

run_cmd(
    qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "query auditoccupancy"},
    "$output_dir/qauditocc.csv"
);

# -----------------------------
# Run QUERY REPLICATION for all nodes
# -----------------------------
my $qrepl="$output_dir/qrepl";
make_path($qrepl) unless -d $qrepl;
foreach my $node (@nodes) {
    my $outfile = "$qrepl/replication_$node.txt";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "QUERY REPLICATION $node"};
    run_cmd($cmd, $outfile);
}

# -----------------------------
# Run VALIDATE REPLPOLICY for target server
# -----------------------------
my $validate_file = "$output_dir/validate_replpolicy.txt";
my $validate_cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "VALIDATE REPLPOLICY $target_server"};
run_cmd($validate_cmd, $validate_file);

# -----------------------------
# Run other Administrative BA client queries
# -----------------------------
foreach my $file (sort keys %server_queries) {
    my $query = $server_queries{$file};
    my $outfile = "$output_dir/$file";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
    run_cmd($cmd, $outfile);
}
# =========================================================
# STORAGE POOL DISCOVERY (CLOUD / DIRECTORY ONLY)
# =========================================================
my $stglist_file = "$output_dir/stgpool_list.txt";
run_cmd(
    qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "select STGPOOL_NAME, STG_TYPE from STGPOOLS"},
    $stglist_file
);
make_path("$output_dir/container") unless -d "$output_dir/container";

open(my $sfh, '<', $stglist_file) or die "Cannot open $stglist_file";
while (<$sfh>) {
    next if /^\s*$/ || /ANR|ANS|STGPOOL_NAME|-+|IBM Storage Protect|Session/i;
    s/^\s+|\s+$//g;
    my ($name, $type) = split(/\s+/, $_, 2);
    next unless $name && $type;

    # ONLY CLOUD or DIRECTORY
    next unless $type eq 'CLOUD' || $type eq 'DIRECTORY';

    my %container_queries = (
        "showsdpool_$name.txt"        => "show sdpool $name",
        "extentupdate_$name.txt"      => "query extentupdates $name",
    );

    foreach my $file (sort keys %container_queries) {
        run_cmd(
            qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$container_queries{$file}"},
            "$output_dir/container/$file"
        );
    }
}
close($sfh);
# -----------------------------
# Collect summary for all queries
# -----------------------------
my %summary;

sub mark_summary {
    my ($key, $file) = @_;
    $summary{$key} = (-s $file) ? "Success" : "Failed";
}

# ---- Static server queries
foreach my $file (keys %server_queries) {
    mark_summary($file, "$output_dir/$file");
}

# ---- CSV outputs
mark_summary("qocc.csv",       "$output_dir/qocc.csv");
mark_summary("qauditocc.csv",  "$output_dir/qauditocc.csv");

# ---- QUERY REPLICATION per node
foreach my $node (@nodes) {
    my $file = "$output_dir/qrepl/replication_$node.txt";
    mark_summary("replication_$node.txt", $file);
}

# ---- VALIDATE REPLPOLICY
mark_summary("validate_replpolicy.txt", $validate_file)
    if $target_server;

# ---- Container / CLOUD / DIRECTORY queries
my $container_dir = "$output_dir/container";
if (-d $container_dir) {
    opendir(my $dh, $container_dir);
    while (my $f = readdir($dh)) {
        next if $f =~ /^\./;
        mark_summary($f, "$container_dir/$f");
    }
    closedir($dh);
}

# ---- Print summary when verbose
if ($verbose) {
    print "\n=== Replication Module Summary ===\n";
    foreach my $k (sort keys %summary) {
        printf "  %-35s : %s\n", $k, $summary{$k};
    }
    print "\nReplication data collected in: $output_dir\n";
    print "Check script.log for command failures.\n";
}

# -----------------------------
# Done
# -----------------------------

close($errfh);
