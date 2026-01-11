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
my ($output_dir, $verbose , $optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"       => \$optfile,
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/config";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Get base path of BA client
# -----------------------------
my $base_path = env::get_ba_base_path();
my $os = env::_os();

# -----------------------------
# Determine which dsm.opt to use  
# -----------------------------
my $opt_file;
if ($optfile) {
    # User-specified option file
    $opt_file = $optfile;
} else {
    $opt_file = "$base_path/dsm.opt";
}

# -----------------------------
# Prepare files to collect
# -----------------------------
my $dsminfo_file = "$output_dir/dsminfo.txt";
my @log_files;
if($os =~ /MSWin32/i) {
     @log_files = ($opt_file);
}else {
     @log_files = ("$base_path/dsm.sys", $opt_file);
}
# -----------------------------
# Error log setup
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Locate DSMC binary
# -----------------------------

my $dsmc;

if ($os =~ /MSWin32/i) {
    $dsmc = `where dsmc.exe 2>nul`;
    chomp($dsmc);
    if (!$dsmc || !-e $dsmc) {
        $dsmc = "$base_path\\dsmc.exe" if -e "$base_path\\dsmc.exe";
    }
} else {
    $dsmc = `which dsmc 2>/dev/null`;
    chomp($dsmc);
    if (!$dsmc || !-x $dsmc) {
        $dsmc = "$base_path/dsmc" if -x "$base_path/dsmc";
    }
}

unless ($dsmc && -x $dsmc) {
    print $errfh "Error: dsmc not found on this system.\n";
    close($errfh);
    die "Error: dsmc binary not found.\n";
}

# -----------------------------
# Run DSM query for system info
# -----------------------------
my $cmd;
my $console_out = "$output_dir/systeminfo_console.txt";
if ($os =~ /MSWin32/i) {
    $cmd = "\"$dsmc\" query systeminfo -filename=\"$dsminfo_file\" -optfile=\"$opt_file\" >\"$console_out\" 2>&1";
} else {
    $cmd = "\"$dsmc\" query systeminfo -filename=\"$dsminfo_file\" -optfile=\"$opt_file\" >\"$console_out\" 2>&1";
}


print $errfh "Executing: $cmd\n" if $verbose;
my $status = system($cmd);
$status >>= 8;
print $errfh "Error: Failed to run dsmc query systeminfo (exit code $status)\n" if $status != 0;


# -----------------------------
# Copy config/log files to output directory
# -----------------------------
my %collected_files;

if (-s $dsminfo_file) {
    $collected_files{"dsminfo.txt"} = "Success";
} else {
    $collected_files{"dsminfo.txt"} = "Failed";
    print $errfh "Error: dsminfo.txt was not created or is empty.\n";
}

foreach my $file (@log_files) {
    my $filepath = $file =~ /^\// ? $file : "$file";
    my ($filename) = $filepath =~ /([^\/\\]+)$/;
    my $dest_file = "$output_dir/$filename";

    if (-e $filepath) {
        if (open(my $fh, '<', $filepath)) {
            open(my $outfh, '>', $dest_file) or do {
                print $errfh "Error: Could not write $dest_file: $!\n";
                $collected_files{$filename} = "Failed";
                next;
            };
            while (<$fh>) { print $outfh $_; }
            close($fh);
            close($outfh);
            $collected_files{$filename} = "Success";
        } else {
            print $errfh "Error: Could not open $filepath: $!\n";
            $collected_files{$filename} = "Failed";
        }
    } else {
        print $errfh "Warning: $filepath not found\n";
        $collected_files{$filename} = "NOT FOUND";
    }
}

close($errfh);

# -----------------------------
# Summary (only in verbose mode)
# -----------------------------
if ($verbose) {
    print "\n=== Config Module Summary ===\n";
    foreach my $file (sort keys %collected_files) {
        printf "  %-15s : %s\n", $file, $collected_files{$file};
    }
    print "Collected config files saved in: $output_dir\n";
    print "Check script.log for any failures.\n";
}

# -----------------------------
# Determine module-level status for framework
# -----------------------------
my $Success_count = 0;
my $fail_count = 0;
my $total = scalar keys %collected_files;

foreach my $status (values %collected_files) {
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

# Exit code mapping for framework (optional: 0=Success, 1=failure, 2=Partial)
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);
