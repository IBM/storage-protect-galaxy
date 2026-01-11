#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../common/modules";  # Include common modules
use env;
use Getopt::Long;

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $adminid, $password,$optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "adminid|id=s"   => \$adminid,
    "password|pwd=s" => \$password,
    "optfile=s"       => \$optfile,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;
die "Error: --adminid is required\n"   unless $adminid;
die "Error: --password is required\n"  unless $password;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/config";
make_path($output_dir) unless -d $output_dir;



# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Detect base path of BA client
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
my $os = $^O;
my $dsmadmc;

if ($os =~ /MSWin32/i) {
    $dsmadmc = `where dsmadmc.exe 2>nul`;
    chomp($dsmadmc);
    if (!$dsmadmc || !-e $dsmadmc) {
        $dsmadmc = "$base_path\\dsmadmc.exe" if -e "$base_path\\dsmadmc.exe";
    }
} else {
    $dsmadmc = `which dsmadmc 2>/dev/null`;
    chomp($dsmadmc);
    if (!$dsmadmc || !-x $dsmadmc) {
        $dsmadmc = "$base_path/dsmadmc" if -x "$base_path/dsmadmc";
    }
}

unless ($dsmadmc && -x $dsmadmc) {
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
# Define dsm administrative client queries
# -----------------------------
my %server_queries = (
    "actlog.txt"    => "query actlog begindate=today-7",
    "system.txt"    => "query system",
    "policies.txt"  => "q policy f=d",
    "nodes.txt"     => "q node f=d",
    "occupancy.txt" => "q occ",
    "policyset.txt" => "q policyset",
);

# -----------------------------
# Run queries and collect output
# -----------------------------
foreach my $file (sort keys %server_queries) {
    my $query = $server_queries{$file};
    my $outfile = "$output_dir/$file";
    my $cmd = qq{$quoted_dsm -id=$adminid -password=$password -optfile=$quoted_opt "$query"};
    run_cmd($cmd, $outfile);
}

# -----------------------------
# Collect server instance-specific files
# -----------------------------
my %collected_files;
my $instance_info = env::get_sp_instance_info();
if ($instance_info) {
    my $inst_name = $instance_info->{instance};
    my $inst_dir  = $instance_info->{directory};

    my @server_files = (
        "$inst_dir/dsmserv.opt",
        "$inst_dir/dsmserv.err",
        "$inst_dir/dsmffdc.log",
        "$inst_dir/tsmdlst"
    );

    foreach my $filepath (@server_files) {
        my ($filename) = $filepath =~ /([^\/\\]+)$/;
        my $dest_file  = "$output_dir/$filename";

        if (-e $filepath) {
            if (open(my $fh, '<', $filepath)) {
                open(my $outfh, '>', $dest_file) or do {
                    print $errfh "Error: Could not write $dest_file: $!\n";
                    $collected_files{$filename} = "FAILED";
                    next;
                };
                while (<$fh>) { print $outfh $_; }
                close($fh);
                close($outfh);
                $collected_files{$filename} = "SUCCESS";
            } else {
                print $errfh "Error: Could not open $filepath: $!\n";
                $collected_files{$filename} = "FAILED";
            }
        } else {
            print $errfh "Warning: $filepath not found for instance $inst_name\n";
            $collected_files{$filename} = "NOT FOUND";
        }
    }
} else {
    print $errfh "Warning: Could not detect server instance information\n";
}
# -----------------------------
# Summary of collected files
# -----------------------------
close($errfh);

my %summary;

# Static queries
foreach my $file (sort keys %server_queries) {
    my $outfile = "$output_dir/$file";
    $summary{$file} = (-s $outfile) ? "SUCCESS" : "FAILED";
}


if ($verbose) {
    print "\n=== Server Config Module Summary ===\n";
    foreach my $file (sort keys %summary) {
        printf "  %-15s : %s\n", $file, $summary{$file};
    }
    foreach my $file (sort keys %collected_files) {
        printf "  %-15s : %s\n", $file, $collected_files{$file};
    }
    print "Collected server config files saved in: $output_dir\n";
    print "Check script.log for any failures.\n";
}

# -----------------------------
# Determine module-level status for framework
# -----------------------------
my $Success_count = 0;
my $fail_count = 0;
my $total = scalar keys %collected_files;

foreach my $status (values %collected_files) {
    $Success_count++ if $status eq "SUCCESS";
    $fail_count++    if $status eq "FAILED";
}

my $module_status;
if ($Success_count == $total) {
    $module_status = "Success";
} elsif ($fail_count == $total) {
    $module_status = "Failed";
} else {
    $module_status = "Partial";
}

# Exit code mapping for framework (0=Success, 1=Failed, 2=Partial)
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);
