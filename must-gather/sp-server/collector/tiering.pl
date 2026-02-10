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
my ($output_dir, $verbose, $options);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "options=s"       => \$options,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;

# SECURITY: Get credentials from ENVIRONMENT only
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || ''; 
# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/tiering";
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

sub save_file_if_exists {
    my ($src, $dest_dir, $dest_name) = @_;
    return 0 unless $src;
    if (-e $src) {
        my $bn = $dest_name || (File::Spec->splitpath($src))[2];
        my $dst = File::Spec->catfile($dest_dir, $bn);
        if (copy($src, $dst)) {
            print $errfh "Saved: $src -> $dst\n" if $verbose;
            return 1;
        } else {
            print $errfh "Failed to copy $src to $dst: $!\n";
            return 0;
        }
    } else {
        print $errfh "Not found: $src\n" if $verbose;
        return 0;
    }
}
sub run_cmd_capture {
    my ($cmd) = @_;
    print $errfh "Capture Running: $cmd\n" if $verbose;
    my $out = `$cmd 2>&1`;
    chomp $out;
    return $out;
}
sub run_db2_cmd {
    my ($cmd, $os, $instance) = @_;

    if ($os eq 'windows') {
        # Run DB2 in silent DB2CMD environment
        return run_cmd_capture("db2cmd /c /w /i  \"$cmd\"");
    } else {
        # Linux/AIX: switch to instance owner
        return run_cmd_capture("su - $instance -c \"$cmd\"");
    }
}

#------------------------------
# Collect db2diag.log
#------------------------------
my %collected_files;
sub collect_db2_diag{
    my ($outdir) = @_;
    my $info = env::get_sp_instance_info();   # <-- Use your simplified instance discovery

    unless ($info && $info->{instance} && $info->{directory}) {
        print $errfh "No SP/DB2 instance discovered.\n";
        return;
    }

    my $inst = $info->{instance};
    my $home = $info->{directory};
    my $os   = env::_os();
    if ($os =~ /MSWin32/i) {
        my $diagpath_cmd_out = run_db2_cmd('db2 get dbm cfg | findstr /i diagpath','windows');
        my $diagpath = "";

        if ($diagpath_cmd_out =~ /Diagpath\s*\=\s*(.*)/i) {
            $diagpath = $1;
            $diagpath =~ s/^\s+|\s+$//g;   # trim whitespace
        }

        # If diagpath is not specified, fallback to DB2INSTPROF
        if (!$diagpath) {
            my $db2instprof_out = run_db2_cmd('db2set db2instprof');
            if ($db2instprof_out =~ /DB2INSTPROF=(.*)/i) {
                $diagpath = $1;
                $diagpath =~ s/^\s+|\s+$//g;
            }
        }

        # Final fallback using DB2PATH + instance name
        if (!$diagpath) {
            my $db2path_out = run_db2_cmd('db2set db2path','windows');
            my $db2instance_out = run_db2_cmd('db2set db2instance','windows');

            if ($db2path_out =~ /DB2PATH=(.*)/i && $db2instance_out =~ /DB2INSTANCE=(.*)/i) {
                my $db2path = $1;
                my $instance = $2;
                $db2path =~ s/^\s+|\s+$//g;
                $instance =~ s/^\s+|\s+$//g;
                $diagpath = "$db2path\\$instance";
            }
        }

        print $errfh "Resolved DB2 diagnostic path: $diagpath\n" if $verbose;

        if ($diagpath && -d $diagpath) {

            # Find the newest db2diag.log file
            my $latest_db2diag = "";
            opendir(my $dh, $diagpath);
            my @candidates = grep { /^db2diag/i } readdir($dh);
            closedir($dh);

            if (@candidates) {
                @candidates = sort { 
                    (stat("$diagpath\\$b"))[9] <=> (stat("$diagpath\\$a"))[9] 
                } @candidates;

                $latest_db2diag = "$diagpath\\$candidates[0]";

                print $errfh "Latest db2diag resolved: $latest_db2diag\n" if $verbose;

                save_file_if_exists($latest_db2diag, $outdir, "${inst}_db2diag.log");
                $collected_files{"${inst}_db2diag.log"} = "Success";
            } else {
                $collected_files{"${inst}_db2diag.log"} = "No db2diag files found";
            }

        } else {
            $collected_files{"${inst}_db2diag.log"} = "DB2 diag path not found";
            print $errfh "DB2 diagnostic directory could not be determined.\n";
        }
    }
    else{
        # -----------------------------
        # Collect DB2DIAG.LOG on Linux/AIX
        # -----------------------------
        # Get DIAGPATH from DB2 config output
        my $diagpath_cmd = run_db2_cmd("db2 get dbm cfg | grep -i DIAGPATH",'unix',$inst);
        my $diagpath_unix = "";

        # Prefer Current member resolved DIAGPATH
        if ($diagpath_cmd =~ /Current member resolved DIAGPATH\s*=\s*(.*)/i) {
            $diagpath_unix = $1;
        }
        # Otherwise fallback to DIAGPATH
        elsif ($diagpath_cmd =~ /DIAGPATH\s*=\s*(.*)/i) {
            $diagpath_unix = $1;
        }

        # Trim whitespace and trailing slash or characters like $m
        $diagpath_unix =~ s/^\s+|\s+$//g;
        $diagpath_unix =~ s/[\/\s\$m]+$//g;

        # Default if still empty
        if (!$diagpath_unix) {
            $diagpath_unix = File::Spec->catdir($home, "sqllib", "db2dump");
        }

        print $errfh "Resolved DB2 diagnostic path (UNIX): $diagpath_unix\n" if $verbose;

        if (-d $diagpath_unix) {
            opendir(my $dh, $diagpath_unix);
            my @candidates = grep { /^db2diag/i } readdir($dh);
            closedir($dh);

            if (@candidates) {
                @candidates = sort {
                    (stat("$diagpath_unix/$b"))[9] <=> (stat("$diagpath_unix/$a"))[9]
                } @candidates;

                my $latest_db2diag = "$diagpath_unix/$candidates[0]";
                print $errfh "Latest db2diag resolved: $latest_db2diag\n" if $verbose;

                save_file_if_exists($latest_db2diag, $outdir, "${inst}_db2diag.log");
                $collected_files{"${inst}_db2diag.log"} = "Success";
            } else {
                $collected_files{"${inst}_db2diag.log"} = "Not found";
            }
        } else {
            $collected_files{"${inst}_db2diag.log"} = "Invalid diagpath";
        }
    }
}
collect_db2_diag($output_dir);
# -----------------------------
# Collect Storage Rules
# -----------------------------
my %tiering_files;
my $rule_file = "$output_dir/stgrules.txt";
my $cmd_rules = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "q stgrule f=d"};
run_cmd($cmd_rules, $rule_file);
$tiering_files{"stgrules.txt"} = (-s $rule_file) ? "Success" : "Failed";

# -----------------------------
# Get Rule Names & collect Subrules
# -----------------------------
my $rule_name_file = "$output_dir/stgrule_names.txt";
my $cmd_list_rules = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "select RULENAME from stgrules"};
run_cmd($cmd_list_rules, $rule_name_file);

open(my $rfh, '<', $rule_name_file) or die "Cannot open $rule_name_file: $!";
my @rulenames;
while (<$rfh>) {
    chomp;

    # Trim leading & trailing whitespace
    s/^\s+|\s+$//g;

    # Skip empty lines
    next if $_ eq '';

    # Skip known headers / banners
    next if /^(IBM|Server Version|Command Line|Copyright|\(c\))/i;
    next if /^ANS\d+/;
    next if /^ANR\d+/;
    next if /^RULENAME$/i;
    next if /^-+$/;

    # Allow only valid rule names (alphanumeric + underscore)
    next unless /^[A-Za-z0-9_]+$/;

    push @rulenames, $_;
}
close($rfh);

foreach my $rulename (@rulenames) {
    my $file = "$output_dir/subrule_$rulename.txt";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "q subrule $rulename f=d"};
    run_cmd($cmd, $file);
    $tiering_files{"subrule_$rulename.txt"} = (-s $file) ? "Success" : "Failed";
}

# -----------------------------
# Dynamic Queries (Per Storage Pool)
# -----------------------------
my $stglist_file = "$output_dir/stgpool_list.txt";
my $select_cmd = qq{$quoted_dsm -id=$adminid -password=$password -dataonly=yes -optfile=$quoted_opt "select STGPOOL_NAME, STG_TYPE from STGPOOLS"};
run_cmd($select_cmd, $stglist_file);

open(my $sfh, '<', $stglist_file) or die "Cannot open $stglist_file: $!";
my @stgpools;
while (<$sfh>) {
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

    next if /stgpool_name/i;
    next if /^\s*-+\s*$/;

    # Trim whitespace
    s/^\s+|\s+$//g;

    my @cols = split(/\s+/, $_, 2);
    next unless scalar @cols == 2;
    my ($name, $type) = @cols;
    push @stgpools, { name => $name, type => $type };
}
close($sfh);

foreach my $pool (@stgpools) {
    my $name = $pool->{name};
    my $type = uc($pool->{type});

    if ($type eq 'CLOUD' || $type eq 'DIRECTORY') {
        my $outfile = "$output_dir/damaged_$name.txt";
        my $query   = qq{q damaged $name};
        my $cmd     = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
        run_cmd($cmd, $outfile);
    }

}    

# -----------------------------
# Collect Connection details (Cloud Tiering)
# -----------------------------

my $conn_file = "$output_dir/connection.txt";
my $cmd_conn = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "q connection f=d"};
run_cmd($cmd_conn, $conn_file);
$tiering_files{"connection.txt"} = (-s $conn_file) ? "Success" : "Failed";

# -----------------------------
# Tiering Module Summary Display (Verbose Only)
# -----------------------------

my %summary;

# Static queries
foreach my $file (sort keys %collected_files) {
    my $outfile = "$output_dir/$file";
    $summary{$file} = (-s $outfile) ? "Success" : "Failed";
}

# Tiering-specific files status
foreach my $file (sort keys %tiering_files) {
    my $filepath = "$output_dir/$file";
    $tiering_files{$file} = (-s $filepath) ? "Success" : "Failed"
        unless defined $tiering_files{$file};
}

if ($verbose) {
    print "\n=== Tiering Module Summary ===\n";

    foreach my $file (sort keys %summary) {
        printf "  %-15s : %s\n", $file, $summary{$file};
    }

    foreach my $file (sort keys %tiering_files) {
        printf "  %-15s : %s\n", $file, $tiering_files{$file};
    }

    print "Collected tiering files saved in: $output_dir\n";
    print "Check script.log for any failures.\n";
}
# -----------------------------
# Determine module-level status for framework
# -----------------------------
my $Success_count = 0;
my $fail_count    = 0;
my $total         = scalar keys %tiering_files;

foreach my $status (values %tiering_files) {
    $Success_count++ if $status eq "Success";
    $fail_count++    if $status eq "Failed";
}

my $module_status;
if ($Success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);
