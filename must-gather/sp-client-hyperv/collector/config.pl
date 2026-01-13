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
    "optfile=s"      => \$optfile,
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
my $os        = env::_os();

# -----------------------------
# Determine which dsm.opt to use
# -----------------------------
my $opt_file = $optfile ? $optfile : "$base_path/dsm.opt";

# -----------------------------
# Prepare files to collect
# -----------------------------
my $dsminfo_file = "$output_dir/dsminfo.txt";
my @log_files;

if ($os =~ /MSWin32/i) {
    @log_files = ($opt_file);
} else {
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
    $dsmc = "$base_path\\dsmc.exe" if (!$dsmc && -e "$base_path\\dsmc.exe");
} else {
    $dsmc = `which dsmc 2>/dev/null`;
    chomp($dsmc);
    $dsmc = "$base_path/dsmc" if (!$dsmc && -x "$base_path/dsmc");
}

unless ($dsmc && -x $dsmc) {
    print $errfh "Error: dsmc binary not found.\n";
    close $errfh;
    die "Error: dsmc not found\n";
}

# -----------------------------
# Run DSMC query systeminfo
# -----------------------------
my $console_out = "$output_dir/systeminfo_console.txt";
my $cmd = "\"$dsmc\" query systeminfo -filename=\"$dsminfo_file\" -optfile=\"$opt_file\" >\"$console_out\" 2>&1";

print $errfh "Executing: $cmd\n" if $verbose;
my $status = system($cmd) >> 8;
print $errfh "Error: query systeminfo failed (exit code $status)\n" if $status != 0;

# -----------------------------
# Run DSMC query vm -detail
# -----------------------------
my $vm_detail_out = "$output_dir/query_vm_detail.out";
my $vm_cmd = "\"$dsmc\" query vm -detail -optfile=\"$opt_file\" >\"$vm_detail_out\" 2>&1";

print $errfh "Executing: $vm_cmd\n" if $verbose;
my $vm_status = system($vm_cmd) >> 8;
print $errfh "Warning: query vm -detail failed (exit code $vm_status)\n" if $vm_status != 0;

# -----------------------------
# Collect dsmmsinfo.txt (Windows only)
# -----------------------------
my %collected_files;

if ($os =~ /MSWin32/i) {
    my $msinfo = "dsmmsinfo.txt";
    if (-e $msinfo) {
        my $dest = "$output_dir/$msinfo";
        if (open(my $in, '<', $msinfo) && open(my $out, '>', $dest)) {
            while (<$in>) { print $out $_; }
            close $in;
            close $out;
            $collected_files{$msinfo} = "Success";
        } else {
            print $errfh "Error copying $msinfo: $!\n";
            $collected_files{$msinfo} = "Failed";
        }
    } else {
        print $errfh "Warning: dsmmsinfo.txt not found\n";
        $collected_files{$msinfo} = "NOT FOUND";
    }
}

# -----------------------------
# Validate dsminfo + vm output
# -----------------------------
$collected_files{"dsminfo.txt"} =
    (-s $dsminfo_file) ? "Success" : "Failed";

$collected_files{"query_vm_detail.out"} =
    (-s $vm_detail_out) ? "Success" : "Failed";

# -----------------------------
# Copy config files
# -----------------------------
foreach my $file (@log_files) {
    my ($filename) = $file =~ /([^\/\\]+)$/;
    my $dest = "$output_dir/$filename";

    if (-e $file && open(my $in, '<', $file)) {
        open(my $out, '>', $dest) or do {
            print $errfh "Error writing $dest: $!\n";
            $collected_files{$filename} = "Failed";
            next;
        };
        while (<$in>) { print $out $_; }
        close $in;
        close $out;
        $collected_files{$filename} = "Success";
    } else {
        print $errfh "Warning: $file not found\n";
        $collected_files{$filename} = "NOT FOUND";
    }
}

close $errfh;

# -----------------------------
# Summary (verbose only)
# -----------------------------
if ($verbose) {
    print "\n=== Config Module Summary ===\n";
    foreach my $file (sort keys %collected_files) {
        printf "  %-25s : %s\n", $file, $collected_files{$file};
    }
    print "Output directory: $output_dir\n";
    print "Check script.log for errors.\n";
}

# -----------------------------
# Module exit status
# -----------------------------
my ($ok, $fail) = (0, 0);
foreach my $s (values %collected_files) {
    $ok++   if $s eq "Success";
    $fail++ if $s eq "Failed";
}

exit 0 if $ok && !$fail;
exit 2 if $ok && $fail;
exit 1;
