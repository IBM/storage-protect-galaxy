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
$output_dir = "$output_dir/objectagent";
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
# Get Object Agent server name
# -----------------------------
my $objectagent_file = "$output_dir/objectagent_servers_raw.txt";
my $objectagent_query = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "SELECT SERVER_NAME, OBJECT_AGENT FROM SERVERS WHERE OBJECT_AGENT='Yes'"};
run_cmd($objectagent_query, $objectagent_file);

open(my $oaf, '<', $objectagent_file) or die "Cannot open $objectagent_file: $!";
my $objectagent_server;
while (<$oaf>) {
    chomp;
    # Skip blank lines
    next if /^\s*$/;

    # Skip known non-data lines
    next if /^(IBM|Command|ANS\d+|Copyright|\(c\)|Return code|---|No match|Highest return code)/i;
    next if /Session established with server/i;
    next if /Server Version/i;
    next if /Server date\/time/i;
    next if /^ANS\d+/;
    next if /ANR\d+E.*No match found/i;
    # Skip column header lines
    next if /SERVER_NAME|OBJECT_AGENT/i;
    next if /^\s*-+\s*$/;

    # Trim whitespace
    s/^\s+|\s+$//g;

    # Extract server name (first column)
    my ($server_name, $obj_agent) = split(/\s+/, $_, 2);
    if ($server_name && !$objectagent_server) {
        $objectagent_server = $server_name;
        last;  # Only one Object Agent server
    }
}
close($oaf);

unless ($objectagent_server) {
    print $errfh "No Object Agent server found (OBJECT_AGENT='Yes').\n";
    if ($verbose) {
        print "\n=== Object Agent Module Summary ===\n";
        print "No Object Agent server detected.\n";
        print "Check script.log for details.\n";
    }
    close($errfh);
    exit(0);
}

print $errfh "Object Agent server detected: $objectagent_server\n" if $verbose;

# -----------------------------
# Get Object Client nodes
# -----------------------------
my $objectclient_file = "$output_dir/objectclient_nodes_raw.txt";
my $objectclient_query = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "SELECT NODE_NAME, NODETYPE FROM NODES WHERE NODETYPE='OBJECTCLIENT'"};
run_cmd($objectclient_query, $objectclient_file);

open(my $ocf, '<', $objectclient_file) or die "Cannot open $objectclient_file: $!";
my %objectclient_nodes;
while (<$ocf>) {
    chomp;
    # Skip blank lines
    next if /^\s*$/;

    # Skip known non-data lines
    next if /^(IBM|Command|ANS\d+|Copyright|\(c\)|Return code|---|No match|Highest return code)/i;
    next if /Session established with server/i;
    next if /Server Version/i;
    next if /Server date\/time/i;
    next if /^ANS\d+/;
    next if /ANR\d+E.*No match found/i;
    # Skip column header lines
    next if /NODE_NAME|NODETYPE/i;
    next if /^\s*-+\s*$/;

    # Trim whitespace
    s/^\s+|\s+$//g;

    # Extract node name (first column)
    my ($node_name, $nodetype) = split(/\s+/, $_, 2);
    if ($node_name) {
        $objectclient_nodes{$node_name} = 1;
    }
}
close($ocf);

my @objectclient_nodes = sort keys %objectclient_nodes;

if (@objectclient_nodes) {
    print $errfh "Object Client nodes detected: " . join(", ", @objectclient_nodes) . "\n" if $verbose;
} else {
    print $errfh "No Object Client nodes found (NODETYPE='OBJECTCLIENT').\n";
}

# -----------------------------
# Define queries for Object Agent server
# -----------------------------
my %server_queries = (
    "query_server_objectagent.txt" => "query server $objectagent_server f=d",
);

# -----------------------------
# Run queries for Object Agent server
# -----------------------------
foreach my $file (sort keys %server_queries) {
    my $query = $server_queries{$file};
    my $outfile = "$output_dir/$file";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
    run_cmd($cmd, $outfile);
}

# -----------------------------
# Run queries for each Object Client node
# -----------------------------
my $qnode_dir = "$output_dir/qnode";
make_path($qnode_dir) unless -d $qnode_dir;

foreach my $node (@objectclient_nodes) {
    my $outfile = "$qnode_dir/query_node_$node.txt";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "QUERY NODE $node f=d"};
    run_cmd($cmd, $outfile);
}

# -----------------------------
# Get instance directory information
# -----------------------------
my $instance_info = env::get_sp_instance_info();
my $instance_dir;

if ($instance_info && $instance_info->{directory}) {
    $instance_dir = $instance_info->{directory};
    print $errfh "Instance directory detected: $instance_dir\n" if $verbose;
} else {
    print $errfh "Could not determine instance directory from env::get_sp_instance_info.\n";
}

# -----------------------------
# Collect Object Agent files (protect.log and config)
# -----------------------------
my %collected_files;

if ($instance_dir && -d $instance_dir && $objectagent_server) {
    # Look for object agent directory using the server name
    my $objectagent_path = "$instance_dir/$objectagent_server";
    
    if (-d $objectagent_path) {
        print $errfh "Object Agent directory found: $objectagent_path\n" if $verbose;
        
        # Look for protect.log
        my $protect_log = "$objectagent_path/protect.log";
        if (-f $protect_log) {
            my $dest = "$output_dir/protect.log";
            if (copy($protect_log, $dest)) {
                $collected_files{"protect.log"} = "Success";
                print $errfh "Collected: $protect_log\n" if $verbose;
            } else {
                $collected_files{"protect.log"} = "Failed";
                print $errfh "Failed to copy: $protect_log - $!\n";
            }
        } else {
            print $errfh "protect.log not found at: $protect_log\n";
            $collected_files{"protect.log"} = "Not Found";
        }
        
        # Look for <object-name>.config
        
        my $config_file = "$objectagent_path/spObjectAgent_${objectagent_server}_1500.config";
        if ($config_file =~ /spObjectAgent_\Q$objectagent_server\E_.*\.config$/i && -f $config_file) {
        my $dest = "$output_dir/$objectagent_server.config";
        if (copy($config_file, $dest)) {
            $collected_files{"$objectagent_server.config"} = "Success";
            print $errfh "Collected: $config_file\n" if $verbose;
        } else {
            $collected_files{"$objectagent_server.config"} = "Failed";
             print $errfh "Failed to copy: $config_file - $!\n";
        }
        } else {
            print $errfh "$objectagent_server.config not found at: $config_file\n";
            $collected_files{"$objectagent_server.config"} = "Not Found";
        }
    } else {
        print $errfh "Object Agent directory not found: $objectagent_path\n";
        $collected_files{"Object Agent directory"} = "Not Found";
    }
}

SKIP_FILES:

# -----------------------------
# Collect Object Agent process information
# -----------------------------
my $process_file = "$output_dir/objectagent_process.txt";
if ($^O =~ /MSWin32/i) {
    run_cmd("tasklist | findstr /i spObjectAgent", $process_file);
} else {
    run_cmd("ps -ef | grep spObjectAgent", $process_file);
}

# -----------------------------
# Collect summary for all queries
# -----------------------------
my %summary;

sub mark_summary {
    my ($key, $file) = @_;
    $summary{$key} = (-s $file) ? "Success" : "Failed";
}

# ---- Server queries
foreach my $file (keys %server_queries) {
    mark_summary($file, "$output_dir/$file");
}

# ---- Node queries
foreach my $node (@objectclient_nodes) {
    my $file = "$qnode_dir/query_node_$node.txt";
    mark_summary("query_node_$node.txt", $file);
}

# ---- Process info
mark_summary("objectagent_process.txt", $process_file);

# ---- Collected files
foreach my $file (keys %collected_files) {
    $summary{$file} = $collected_files{$file};
}

# ---- Print summary when verbose
if ($verbose) {
    print "\n=== Object Agent Module Summary ===\n";
    print "Object Agent Server: $objectagent_server\n";
    print "Object Client Nodes: " . (@objectclient_nodes ? join(", ", @objectclient_nodes) : "None") . "\n";
    print "\nQuery Results:\n";
    foreach my $k (sort keys %summary) {
        printf "  %-40s : %s\n", $k, $summary{$k};
    }
    print "\nObject Agent data collected in: $output_dir\n";
    print "Check script.log for command failures.\n";
}

# -----------------------------
# Done
# -----------------------------
close($errfh);