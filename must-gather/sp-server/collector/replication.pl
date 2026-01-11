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
# Parameters / CLI options
# -----------------------------
my ($output_dir, $adminid, $password, $verbose, $options);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "adminid|id=s"   => \$adminid,
    "password|pwd=s" => \$password,
    "verbose|v"      => \$verbose,
    "options=s"       => \$options,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;
die "Error: --adminid is required\n"   unless $adminid;
die "Error: --password is required\n"  unless $password;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/replication";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Error log
# -----------------------------
my $error_log = "$output_dir/error.log";
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
# Hardcoded dsm.opt for Windows
# -----------------------------
my $opt_file;
if ($options) {
    # User-specified option file
    $opt_file = $options;
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
# Define static server queries
# -----------------------------
my %server_queries = (
    "replrule.txt"       => "QUERY REPLRULE",
    "replfailures.txt"   => "QUERY REPLFAILURES",
    "replnodes.txt"      => "QUERY REPLNODE *",
    "replserver.txt"     => "QUERY REPLSERVER",
    "replication.txt"    => "QUERY REPLICATION * F=D",       
    "replfailures_summary.txt" => "QUERY REPLFAILURES TYPE=SUMMARY",
    "replfailures_objects.txt" => "QUERY REPLFAILURES TYPE=OBJECTS",
    "filespace.txt"            => "QUERY FILESPACE * F=D",
    "stgrule.txt"              => "QUERY STGRULE F=D",

);

# -----------------------------
# Run QUERY REPLICATION for all nodes
# -----------------------------
foreach my $node (@nodes) {
    my $outfile = "$output_dir/replication_$node.txt";
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
# Run other static queries
# -----------------------------
foreach my $file (sort keys %server_queries) {
    my $query = $server_queries{$file};
    my $outfile = "$output_dir/$file";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
    run_cmd($cmd, $outfile);
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

#---------------------------
#Extentupdates for container
#----------------------------
foreach my $pool (@stgpools) {

    my $name = $pool->{name};
    my $type = uc($pool->{type});
    if ($type eq 'CLOUD' || $type eq 'DIRECTORY') {
        my $outfile = "$output_dir/extentupdate_$name.txt";
        my $query   = qq{q extentupdates $name};
        my $cmd     = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
        run_cmd($cmd, $outfile);
    }
    
}
# -----------------------------
# Collect summary for all queries
# -----------------------------
my %summary;

# Static queries
foreach my $file (sort keys %server_queries) {
    my $outfile = "$output_dir/$file";
    $summary{$file} = (-s $outfile) ? "SUCCESS" : "FAILED";
}

# QUERY REPLICATION per node
foreach my $node (@nodes) {
    my $outfile = "$output_dir/replication_$node.txt";
    $summary{"replication_$node.txt"} = (-s $outfile) ? "SUCCESS" : "FAILED";
}

# VALIDATE REPLPOLICY
$summary{"validate_replpolicy.txt"} = (-s $validate_file) ? "SUCCESS" : "FAILED";

# -----------------------------
# Print summary if verbose
# -----------------------------
if ($verbose) {
    print "\n=== Replication Module Summary ===\n";
    foreach my $file (sort keys %summary) {
        printf "  %-15s : %s\n", $file, $summary{$file};
    }
    print "Collected server info saved in: $output_dir\n";
    print "Check error.log for any failures.\n";
}

# -----------------------------
# Done
# -----------------------------

close($errfh);