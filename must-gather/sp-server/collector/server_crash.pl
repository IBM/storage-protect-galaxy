#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;
use FindBin;
use File::Path qw(make_path);
use File::Copy qw(copy);
use File::Spec;
use Cwd qw(abs_path);
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;

# --------------------------------------------------
# Parameters
# --------------------------------------------------
my ($output_dir, $verbose);

GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
) or die "Invalid arguments\n";

die "Error: --output-dir is required\n" unless $output_dir;

# SECURITY: ENV only
my $adminid  = $ENV{MUSTGATHER_ADMINID}  || '';
my $password = $ENV{MUSTGATHER_PASSWORD} || '';

# --------------------------------------------------
# Prompt utility
# --------------------------------------------------
sub prompt {
    my ($msg, $default) = @_;
    print $msg;
    print " [$default]" if defined $default && $default ne '';
    print ": ";
    chomp(my $input = <STDIN>);
    return length($input) ? $input : $default;
}

# --------------------------------------------------
# Interactive input
# --------------------------------------------------
my $program  = prompt("Enter program name (dsmserv / dsmsta)", "dsmserv");
my $corefile = prompt("Enter full path to core file (leave blank if not available)", "");
undef $corefile unless $corefile;

# --------------------------------------------------
# Prepare output directory
# --------------------------------------------------
$output_dir = File::Spec->catdir($output_dir, 'server-crash');
make_path($output_dir) unless -d $output_dir;

# --------------------------------------------------
# Error log
# --------------------------------------------------
my $error_log = File::Spec->catfile($output_dir, 'script.log');
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# --------------------------------------------------
# Utilities
# --------------------------------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;
    my $full = $outfile ? qq{$cmd > "$outfile" 2>&1} : $cmd;
    print $errfh "Running: $full\n" if $verbose;
    return (system($full) >> 8);
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
# --------------------------------------------------
# Detect OS
# --------------------------------------------------
my $os = $^O;
my %collected_files;

# ==================================================
# AIX
# ==================================================
if ($os eq 'aix') {

    if ($corefile && -f $corefile) {
        my $rc = run_cmd(
            "snapcore -d $output_dir $corefile $program",
            File::Spec->catfile($output_dir, 'snapcore.out')
        );
        $collected_files{'snapcore.pax'} = ($rc == 0 ? 'Success' : 'Failed');
    } else {
        $collected_files{'snapcore.pax'} = 'NOT PROVIDED';
    }

    # DBX analysis (if available)
    if ($corefile && -x '/usr/bin/dbx') {
        my $stack = File::Spec->catfile($output_dir, 'stack.out');
        my $regs  = File::Spec->catfile($output_dir, 'registers.out');

        run_cmd(
            qq{echo "where\nregisters\nquit" | dbx $program $corefile},
            File::Spec->catfile($output_dir, 'dbx.out')
        );

        $collected_files{'dbx_analysis'} = 'Attempted';
    }

    # tsmdiag (valid on AIX)
    my $rc = run_cmd(
        "cd /opt/tivoli/tsm/server/bin/tsmdiag && tsmdiag -id $adminid -pa $password",
        File::Spec->catfile($output_dir, 'tsmdiag.out')
    );
    $collected_files{'tsmdiag_results.tar'} = ($rc == 0 ? 'Success' : 'Failed');

    # Copy binaries and libs
    save_file_if_exists("/opt/tivoli/tsm/server/bin/$program", $output_dir);
    save_file_if_exists("/opt/tivoli/tsm/server/bin/dsmlicense", $output_dir);
    save_file_if_exists("/opt/lib/libC.a", $output_dir);
    save_file_if_exists("/opt/lib/libpthreads.a", $output_dir);
}

# ==================================================
# LINUX
# ==================================================
if ($os eq 'linux') {

    my $bin_dir = "/opt/tivoli/tsm/server/bin";
    my $exe     = "$bin_dir/$program";

    # getcoreinfo
    if ($corefile && -f $corefile) {
        my $rc = run_cmd(
            "$bin_dir/getcoreinfo $exe $corefile",
            File::Spec->catfile($output_dir, 'getcoreinfo.txt')
        );
        $collected_files{'getcoreinfo'} = ($rc == 0 ? 'Success' : 'Failed');

        # capture shlibs if generated
        if (-e "$bin_dir/getcoreinfo-shlibs.tar.gz") {
            copy("$bin_dir/getcoreinfo-shlibs.tar.gz", $output_dir);
            $collected_files{'getcoreinfo-shlibs.tar.gz'} = 'Success';
        }
    } else {
        $collected_files{'getcoreinfo'} = 'NOT PROVIDED';
    }

    # ldd output
    my $ldd_out = File::Spec->catfile($output_dir, 'ldd_dsmserv.out');
    run_cmd("ldd $exe", $ldd_out);
    $collected_files{'ldd_output'} = 'Success';

    # copy shared libraries
    if (open my $fh, '<', $ldd_out) {
        while (<$fh>) {
            if (/\s+=>\s+(\/\S+)/) {
                save_file_if_exists($1, $output_dir);
            }
        }
        close $fh;
        $collected_files{'shared_libraries'} = 'Success';
    }

    # additional files
    save_file_if_exists("/var/log/messages", $output_dir);
    save_file_if_exists($exe, $output_dir);

}

# ==================================================
# WINDOWS
# ==================================================
if ($os =~ /MSWin32/i) {

    my @files = qw(
        dsmserv.dmp dsmsvc.dmp dsmsta.dmp
        dsmserv.exe dsmserv.pdb dsmsvc.pdb
        ndmpspi.pdb adsmdll.pdb
    );

    my $base = 'C:\\Program Files\\Tivoli\\TSM\\Server';

    foreach my $f (@files) {
        my $src = "$base\\$f";
        if (-e $src) {
            copy($src, File::Spec->catfile($output_dir, $f));
            $collected_files{$f} = 'Success';
        }
    }
}
# ==================================================
# DB2 DIAG + DB2SUPPORT (FIXED PERMISSIONS)
# ==================================================
#------------------------------
# Collect db2diag.log
#------------------------------
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
sub collect_db2support {

    my ($outdir) = @_;

    my $info = env::get_sp_instance_info();
    return unless $info && $info->{instance} && $info->{directory};

    my $inst = $info->{instance};
    my $home = $info->{directory};

    my $support_dir = File::Spec->catdir($outdir, 'db2support');
    make_path($support_dir) unless -d $support_dir;

    # -------- FIX: ownership for instance user --------
    if ($^O !~ /MSWin32/i) {
        system("chown -R $inst $support_dir");
        system("chmod -R 755 $support_dir");
    }

    my $support_out = File::Spec->catfile($outdir, "${inst}_db2support.out");
    my $target_zip  = File::Spec->catfile($outdir, "${inst}_db2support.zip");

    if ($^O =~ /MSWin32/i) {

        my $rc = run_cmd(
            qq{db2cmd /i /w /c db2support "$support_dir" -d TSMDB1 -c -s},
            $support_out
        );

        my $zip = File::Spec->catfile($support_dir, 'db2support.zip');
        if (-e $zip && -s $zip) {
            copy($zip, $target_zip);
            $collected_files{"$inst:db2support.zip"} = 'Success';
        } else {
            $collected_files{"$inst:db2support.zip"} = ($rc == 0 ? 'ATTEMPTED' : 'Failed');
        }

    } else {

        my $cmd = qq{
            . ~$inst/sqllib/db2profile &&
            cd "$support_dir" &&
            db2support . -d TSMDB1 -c -s
        };

        my $rc = run_cmd(qq{su - $inst -c '$cmd'}, $support_out);

        my $zip = File::Spec->catfile($support_dir, 'db2support.zip');
        if (-e $zip && -s $zip) {
            copy($zip, $target_zip);
            $collected_files{"$inst:db2support.zip"} = 'Success';
        } else {
            $collected_files{"$inst:db2support.zip"} = ($rc == 0 ? 'ATTEMPTED' : 'Failed');
        }
    }
}

collect_db2support($output_dir);

# ==================================================
# Final summary (framework compatible)
# ==================================================
close($errfh);

if ($verbose) {
    print "\n=== Crash MustGather Summary ===\n";
    foreach my $k (sort keys %collected_files) {
        printf " %-30s : %s\n", $k, $collected_files{$k};
    }
    print "\nOutput directory: $output_dir\n";
    print "Log file       : $error_log\n";
}

my ($ok, $fail) = (0, 0);
my $total = scalar keys %collected_files;

foreach my $v (values %collected_files) {
    $ok++   if $v =~ /^Success$/i;
    $fail++ if $v =~ /^Failed$/i;
}

my $status = 'Partial';
$status = 'Success' if $ok == $total;
$status = 'Failed'  if $fail == $total;

exit($status eq 'Success' ? 0 : $status eq 'Partial' ? 2 : 1);
