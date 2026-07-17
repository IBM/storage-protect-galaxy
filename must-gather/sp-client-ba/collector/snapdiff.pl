#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use Getopt::Long;

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments. Run with --help for usage.\n";

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/snapdiff";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Open error log
# -----------------------------
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

my %collected_files;

sub run_to_file {
    my ($cmd, $dest, $label) = @_;

    my $status = system("$cmd > \"$dest\" 2>&1");
    $status >>= 8;

    if ($status == 0 && -e $dest && -s $dest) {
        $collected_files{$label} = 'Success';
        return 1;
    }

    print $errfh "Warning: Command failed for $label (exit code $status): $cmd\n";
    unlink $dest if -e $dest && !-s $dest;
    $collected_files{$label} = 'NOT FOUND';
    return 0;
}

sub copy_file {
    my ($src, $dest, $label) = @_;

    if (!-e $src) {
        print $errfh "Warning: $src not found\n";
        $collected_files{$label} = 'NOT FOUND';
        return 0;
    }

    open(my $in, '<', $src) or do {
        print $errfh "Error: Could not open $src: $!\n";
        $collected_files{$label} = 'Failed';
        return 0;
    };

    open(my $out, '>', $dest) or do {
        print $errfh "Error: Could not write $dest: $!\n";
        close $in;
        $collected_files{$label} = 'Failed';
        return 0;
    };

    while (<$in>) {
        print $out $_;
    }

    close $out;
    close $in;
    $collected_files{$label} = 'Success';
    return 1;
}



# -----------------------------
# Collect NetApp logs from known locations
# -----------------------------
my %targets = (
    'backup.log' => [ '/etc/log/mlog/backup.log', '/etc/log/backup.log' ],
    'ndmpd.log'  => [ '/etc/log/mlog/ndmpd.log',  '/etc/log/ndmpd.log'  ],
);

for my $name (sort keys %targets) {
    my $found = 0;

    for my $src (@{ $targets{$name} }) {
        if (-e $src) {
            copy_file($src, "$output_dir/$name", $name);
            $found = 1;
            last;
        }
    }

    if (!$found) {
        print $errfh "Warning: $name not found in known locations\n";
        $collected_files{$name} = 'NOT FOUND';
    }
}

# -----------------------------
# Collect ndmpd.* rotated logs if present
# -----------------------------
my @ndmp_dirs = ('/etc/log/mlog', '/etc/log');
my $rotated_found = 0;

for my $dir (@ndmp_dirs) {
    next unless -d $dir;

    opendir(my $dh, $dir) or do {
        print $errfh "Warning: Cannot open $dir: $!\n";
        next;
    };

    my @files = sort grep { /^ndmpd\.\d+$/ && -f "$dir/$_" } readdir($dh);
    closedir($dh);

    for my $file (@files) {
        copy_file("$dir/$file", "$output_dir/$file", $file);
        $rotated_found = 1;
    }
}

$collected_files{'ndmpd_rotated_logs'} = $rotated_found ? 'Success' : 'NOT FOUND';

close($errfh);

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {
    print "\n=== Snapdiff Module Summary ===\n";
    foreach my $file (sort keys %collected_files) {
        printf "  %-40s : %s\n", $file, $collected_files{$file};
    }
    print "Collected snapdiff data saved in: $output_dir\n";
    print "Check script.log for details.\n";
}

# -----------------------------
# Module status
# -----------------------------
my $success_count = 0;
my $fail_count    = 0;
my $total         = scalar keys %collected_files;

foreach my $status (values %collected_files) {
    $success_count++ if $status eq 'Success';
    $fail_count++    if $status eq 'Failed';
}

my $module_status;
if ($success_count == $total) {
    $module_status = 'Success';
} elsif ($fail_count == $total) {
    $module_status = 'Failed';
} else {
    $module_status = 'Partial';
}

exit($module_status eq 'Success' ? 0 : $module_status eq 'Partial' ? 2 : 1);
