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
# Parse arguments
# -----------------------------
my ($output_dir, $verbose);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments\n";

die "--output-dir required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/lanfree_client";
make_path($output_dir) unless -d $output_dir;

my $error_log = "$output_dir/script.log";
open(my $errfh, ">", $error_log) or die "Cannot open script.log\n";

my %collected;

# -----------------------------
# Detect OS
# -----------------------------
my $os = $^O;

# -----------------------------
# Detect Storage Agent base path
# -----------------------------
my $sta_base;

if ($os =~ /MSWin32/i) {
    $sta_base = "C:\\Program Files\\Tivoli\\TSM\\storageagent";
}
elsif ($os =~ /aix|linux|hpux|solaris|sunos/i) {
    $sta_base = "/opt/tivoli/tsm/StorageAgent/bin";
}

unless ($sta_base && -d $sta_base) {
    print $errfh "Storage Agent base path not found\n";
    $collected{"storage_agent_path"} = "NOT FOUND";
} else {
    $collected{"storage_agent_path"} = "Success";
}

# -----------------------------
# Collect STA config/log files
# -----------------------------
my @sta_files = (
    "dsmsta.opt",
    "dsmsta.err",
    "devconfig.txt",
);

foreach my $file (@sta_files) {
    my $src = "$sta_base/$file";
    if (-e $src) {
        if (copy($src, $output_dir)) {
            $collected{$file} = "Success";
        } else {
            $collected{$file} = "Failed";
            print $errfh "Failed to copy $src: $!\n";
        }
    } else {
        $collected{$file} = "NOT FOUND";
        print $errfh "Warning: $src not found\n";
    }
}

# -----------------------------
# OS-specific LAN-free / tape info
# -----------------------------
my %os_cmds;

if ($os =~ /linux/i) {
    %os_cmds = (
        "os-release.txt"     => "cat /etc/os-release",
        "byid.txt"           => "ls -al /dev/lin_tape/by-id",
        "lsltr.txt"          => "ls -ltr /dev/IBM*",
        "sudo_ibmtape.txt"   => "cat /proc/scsi/IBMtape",
        "sgvers.txt"         => "cat /proc/scsi/sg/version",
        "sgstrs.txt"         => "cat /proc/scsi/sg/device_strs",
        "sgdevs.txt"         => "cat /proc/scsi/sg/devices",
        "tsmscsi.txt"        => "ls -l /dev/tsmscsi",
        "lbinfo.txt"         => "cat /dev/tsmscsi/lbinfo",
        "mtinfo.txt"         => "cat /dev/tsmscsi/mtinf",
        "messages.txt"       => (-e "/var/log/messages") ? "cat /var/log/messages" : "journalctl -xe",
        "lin_tape_rules.txt" => "cat /etc/udev/rules.d/98-lin_tape.rules",
        "lintapestatus.txt"  => "lin_taped status",
    );


    if (-x "/bin/rpm") {
        $os_cmds{"tape_rpm.txt"} = "rpm -qa | grep -i tape";
    }
    if (-x "/usr/bin/dpkg") {
        $os_cmds{"tape_dpkg.txt"} = "dpkg -l | grep -i tape";
    }

}
elsif ($os =~ /aix/i) {
    %os_cmds = (
        "lsdev_tape.txt"      => "lsdev -Cc tape",
        "lsdev_adsmtape.txt"  => "lsdev -Cc adsmtape",
        "atape_version.txt"   => "lslpp -l | grep Atape",
        "rmt_device.txt"      => "lscfg -vl rmt*",
        "smc_device.txt"      => "lscfg -vl smc*",
        "lsltr.txt"           => "ls -ltr /dev/IBM*",
        "errpt.txt"           => "errpt -a",
        "oslevel.txt"         => "oslevel -s",
    );
}
elsif ($os =~ /solaris|sunos/i) {
    %os_cmds = (
        "uname.txt"     => "uname -a",
        "cfgadm.txt"    => "cfgadm -al",
        "luxadm.txt"    => "luxadm probe",
        "messages.txt"  => "cat /var/adm/messages",
    );
}
elsif ($os =~ /hpux/i) {
    %os_cmds = (
        "ioscan.txt" => "ioscan -fnC tape",
        "swlist.txt" => "swlist | grep -i tape",
        "dmesg.txt"  => "dmesg",
    );
}

foreach my $out (keys %os_cmds) {
    my $dest = "$output_dir/$out";
    my $cmd  = "$os_cmds{$out} > $dest 2>>$error_log";
    my $rc   = system($cmd) >> 8;

    $collected{$out} = ($rc == 0 && -s $dest) ? "Success" : "Failed";
}

# -----------------------------
# Summary
# -----------------------------
close($errfh);

if ($verbose) {
    print "\n=== LAN-Free Client Module Summary ===\n";
    foreach my $k (sort keys %collected) {
        printf "  %-22s : %s\n", $k, $collected{$k};
    }
    print "Collected files saved in: $output_dir\n";
    print "Check script.log for failures\n";
}

# -----------------------------
# Module-level exit status
# -----------------------------
my ($ok, $fail) = (0, 0);
foreach my $v (values %collected) {
    $ok++   if $v eq "Success";
    $fail++ if $v eq "Failed";
}

exit(
    ($ok && !$fail) ? 0 :
    ($ok && $fail)  ? 2 :
                      1
);
