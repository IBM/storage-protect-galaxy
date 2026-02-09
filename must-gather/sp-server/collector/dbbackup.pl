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

# -----------------------------
# Parameters / CLI optfile
# -----------------------------
my ($output_dir, $verbose, $optfile);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "optfile=s"      => \$optfile,
) or die "Invalid arguments. Run with --help for usage.\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = File::Spec->catdir($output_dir, 'dbbackup');
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Error log
# -----------------------------
my $error_log = File::Spec->catfile($output_dir, 'script.log');
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

# -----------------------------
# Detect OS and base path
# -----------------------------
my $os = $^O;
print $errfh "Detected OS: $os\n" if $verbose;

my $base_path = env::get_ba_base_path();
unless ($base_path) {
    print $errfh "BA client base path not found.\n";
    close($errfh);
    die "BA client base path not found. Exiting.\n";
}

# -----------------------------
# Utilities
# -----------------------------
sub run_cmd {
    my ($cmd, $outfile) = @_;
    if ($outfile) {
        my $full = qq{$cmd > "$outfile" 2>&1};
        print $errfh "Running: $full\n" if $verbose;
        my $rc = system($full);
        $rc >>= 8;
        return $rc;
    } else {
        print $errfh "Running capture: $cmd\n" if $verbose;
        my $out = `$cmd 2>/dev/null`;
        chomp $out;
        return $out;
    }
}

sub run_cmd_capture {
    my ($cmd) = @_;
    print $errfh "Capture Running: $cmd\n" if $verbose;
    my $out = `$cmd 2>&1`;
    chomp $out;
    return $out;
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

# -----------------------------
# Locate dsmc binary
# -----------------------------
my $dsmc;
if ($os =~ /MSWin32/i) {
    $dsmc = `where dsmc.exe 2>nul`;
    chomp($dsmc);
    if (!$dsmc || $dsmc eq '') {
        my $cand = File::Spec->catfile($base_path, 'dsmc.exe');
        $dsmc = $cand if -e $cand;
    }
} else {
    $dsmc = `which dsmc 2>/dev/null`;
    chomp($dsmc);
    if (!$dsmc || $dsmc eq '') {
        my $cand = File::Spec->catfile($base_path, 'dsmc');
        $dsmc = $cand if -x $cand;
    }
}
if (!$dsmc || !-e $dsmc) {
    print $errfh "Error: dsmc not found on this system. Some steps will be skipped.\n";
    $dsmc = undef;
} else {
    print $errfh "Using dsmc: $dsmc\n" if $verbose;
}

# -----------------------------
# Prepare dsm.opt path
# -----------------------------
my $opt_file = $optfile ? $optfile : File::Spec->catfile($base_path, 'dsm.opt');

# -----------------------------
# Run DSM query for system info (use dsmc)
# -----------------------------
my $dsminfo_file = File::Spec->catfile($output_dir, 'dsminfo.txt');
my $console_out   = File::Spec->catfile($output_dir, 'systeminfo_console.txt');

if ($dsmc) {
    my $quoted_opt = $opt_file =~ / / ? qq{"$opt_file"} : $opt_file;
    my $cmd = "\"$dsmc\" query systeminfo -filename=\"$dsminfo_file\" -optfile=\"$opt_file\" >\"$console_out\" 2>&1";
    my $status = system($cmd);
    $status >>= 8;
    print $errfh "Error: Failed to run dsmc query systeminfo (exit code $status)\n" if $status != 0;   # capture into dsminfo_file (we used run_cmd with outfile)
    
}
# -----------------------------
# Collect basic files (dsm.opt/dsm.sys) from base_path when applicable
# -----------------------------
my %collected_files;
if ($os =~ /MSWin32/i) {
    # Try to copy dsm.opt if present under base_path or opt_file path
    if (save_file_if_exists($opt_file, $output_dir, 'dsm.opt')) {
        $collected_files{'dsm.opt'} = 'Success';
    } else {
        $collected_files{'dsm.opt'} = 'NOT FOUND';
    }
} else {
    # Unix/AIX: dsm.sys and optionally dsm.opt under base_path
    my $dsm_sys = File::Spec->catfile($base_path, 'dsm.sys');
    if (-e $dsm_sys) {
        save_file_if_exists($dsm_sys, $output_dir);
        $collected_files{'dsm.sys'} = 'Success';
    } else {
        $collected_files{'dsm.sys'} = 'NOT FOUND';
    }
    if (save_file_if_exists($opt_file, $output_dir, 'dsm.opt')) {
        $collected_files{'dsm.opt'} = 'Success';
    } else {
        $collected_files{'dsm.opt'} = 'NOT FOUND';
    }
}

sub collect_db2_instances {
    my ($outdir) = @_;
    my $info = env::get_sp_instance_info();   # <-- Use your simplified instance discovery

    unless ($info && $info->{instance} && $info->{directory}) {
        print $errfh "No SP/DB2 instance discovered.\n";
        return;
    }

    my $inst = $info->{instance};
    my $home = $info->{directory};
    my $os   = env::_os();

    print $errfh "Discovered instance: $inst at $home\n" if $verbose;
    # Destination files
    my $env_dump_file      = File::Spec->catfile($outdir, "${inst}_env.txt");
    my $userprofile_out    = File::Spec->catfile($outdir, "${inst}_userprofile.txt");
    my $usercshrc_out      = File::Spec->catfile($outdir, "${inst}_usercshrc.txt");
    my $lib64_listing      = File::Spec->catfile($outdir, "${inst}_lib64.txt");
    my $sqllib_recursive   = File::Spec->catfile($outdir, "${inst}_sqllib_ls.txt");
    my $db2sysc_pid_out    = File::Spec->catfile($outdir, "${inst}_db2sysc_pid.txt");
    my $db2sysc_env_out    = File::Spec->catfile($outdir, "${inst}_db2sysc_env.txt");

    # ---------------------------------------------
    # Windows Logic
    # ---------------------------------------------
    if ($os =~ /MSWin32/i) {
        my $prof = run_db2_cmd("db2set -i $inst db2instprof",'windows');
        $prof =~ s/^\s+|\s+$//g if defined $prof;
        unless ($prof && -d $prof) {
            print $errfh "db2set did not return a usable path for instance $inst: '$prof'\n" if $verbose;
            # try fallback: in some installs db2set prints like 'db2instprof = C:\ProgramData\IBM\DB2\DB2TSM1'
            if ($prof =~ /=\s*(.+)$/) {
                my $maybe = $1;
                $maybe =~ s/^\s+|\s+$//g;
                $prof = $maybe if -d $maybe;
            }
        }
        if ($prof && -d $prof)
        {
            my $api_dir = File::Spec->catdir($prof, $inst);
            # collect dsm.opt
            my $dsm_opt = File::Spec->catfile($api_dir, 'dsm.opt');
            if (-f $dsm_opt) {
                save_file_if_exists($dsm_opt, $outdir, "${inst}_dsm.opt");
                $collected_files{"$inst:dsm.opt"} = 'Success';
            } else {
                # try prof root as fallback
                my $alt = File::Spec->catfile($prof, 'dsm.opt');
                if (-f $alt) {
                    save_file_if_exists($alt, $outdir, "${inst}_dsm.opt");
                    $collected_files{"$inst:dsm.opt"} = 'Success';
                } else {
                    $collected_files{"$inst:dsm.opt"} = 'NOT FOUND';
                    print $errfh "dsm.opt not found for $inst under $api_dir or $prof\n";
                }
            }
            # collect tsmdbmgr.log under <db2instprof>/db2dump/tsmdbmgr.log
            my $logfile = File::Spec->catfile($prof, 'db2dump', 'tsmdbmgr.log');
            if (-f $logfile) {
                save_file_if_exists($logfile, $outdir, "${inst}_tsmdbmgr.log");
                $collected_files{"$inst:tsmdbmgr.log"} = 'Success';
            } else {
                $collected_files{"$inst:tsmdbmgr.log"} = 'NOT FOUND';
                print $errfh "tsmdbmgr.log not found for $inst under $prof/db2dump\n";
            }
        }
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
                $collected_files{"$inst:db2diag.log"} = "Success";
            } else {
                $collected_files{"$inst:db2diag.log"} = "No db2diag files found";
            }

        } else {
            $collected_files{"$inst:db2diag.log"} = "DB2 diag path not found";
            print $errfh "DB2 diagnostic directory could not be determined.\n";
        }

    }

    # ---------------------------------------------
    # Unix / Linux / AIX Logic
    # ---------------------------------------------
    if ($os !~ /MSWin32/i) {
        my $sqllib     = File::Spec->catdir($home, "sqllib");
        my $userprof   = File::Spec->catfile($sqllib, "userprofile");
        my ($dsmi_config, $dsmi_dir, $dsmi_log);

        # ------------- Read userprofile -------------
        if (-f $userprof) {
            open my $fh, "<", $userprof;
            
            while (<$fh>) {
                $dsmi_config = $1 if /^\s*(?:export\s+)?DSMI_CONFIG\s*=\s*(.+)/;
                $dsmi_dir    = $1 if /^\s*(?:export\s+)?DSMI_DIR\s*=\s*(.+)/;
                $dsmi_log    = $1 if /^\s*(?:export\s+)?DSMI_LOG\s*=\s*(.+)/;
            }

            close $fh;

            $collected_files{"$inst:userprofile"} = "FOUND";
        } else {
            print $errfh "userprofile missing at $userprof\n";
            $collected_files{"$inst:userprofile"} = "NOT FOUND";
        }

        # ------------ tsmdbmgr.opt (from DSMI_CONFIG or fallback) ------------
        if ($dsmi_config) {
            $dsmi_config =~ s/\s+$//;
            if (-f $dsmi_config) {
                save_file_if_exists($dsmi_config, $outdir, "${inst}_tsmdbmgr.opt");
                $collected_files{"$inst:tsmdbmgr.opt"} = "Success";
            } else {
                $collected_files{"$inst:tsmdbmgr.opt"} = "NOT FOUND";
            }
        } else {
            # fallback
            my $default_opt = File::Spec->catfile($sqllib, "tsmdbmgr.opt");
            if (-f $default_opt) {
                save_file_if_exists($default_opt, $outdir, "${inst}_tsmdbmgr.opt");
                $collected_files{"$inst:tsmdbmgr.opt"} = "Success";
            } else {
                $collected_files{"$inst:tsmdbmgr.opt"} = "NOT FOUND";
            }
        }

        # ------------ dsm.sys from DSMI_DIR ------------
        if ($dsmi_dir) {
            my $dsm_sys = File::Spec->catfile($dsmi_dir, "dsm.sys");
            if (-f $dsm_sys) {
                save_file_if_exists($dsm_sys, $outdir, "${inst}_dsm.sys");
                $collected_files{"$inst:dsm.sys"} = "Success";
            } else {
                $collected_files{"$inst:dsm.sys"} = "NOT FOUND";
            }
        }

        # ------------ tsmdbmgr.log from DSMI_LOG ------------
        if ($dsmi_log) {
            my $log = File::Spec->catfile($dsmi_log, "tsmdbmgr.log");
            if (-f $log) {
                save_file_if_exists($log, $outdir, "${inst}_tsmdbmgr.log");
                $collected_files{"$inst:tsmdbmgr.log"} = "Success";
            } else {
                $collected_files{"$inst:tsmdbmgr.log"} = "NOT FOUND";
            }
        }

        # 1) Capture set |grep DSM
        run_cmd("set | grep -i DSM", $env_dump_file);

        # 2) Capture environment of DB2 user
        run_cmd("env | grep -i DSM >> \"$env_dump_file\"");

        # 3) cat userprofile
        my $userprofile = File::Spec->catfile($home, "sqllib", "userprofile");
        run_cmd("cat \"$userprofile\"", $userprofile_out) if -f $userprofile;

        # 4) cat usercshrc
        my $usercshrc = File::Spec->catfile($home, "sqllib", "usercshrc");
        run_cmd("cat \"$usercshrc\"", $usercshrc_out) if -f $usercshrc;

        # 5) ls -laR sqllib/lib64
        run_cmd("ls -laR \"$home/sqllib/lib64\"", $lib64_listing);

        # 6) Full sqllib recursive listing for structure debugging
        run_cmd("ls -ltr \"$home/sqllib\" -R", $sqllib_recursive);

        # 7) Find db2sysc PID and capture its full environment
        my $pid = run_cmd_capture("ps -ef | grep db2sysc | grep -v grep | awk '{print \$2}'");

        if ($pid) {
            run_cmd("echo PID=$pid", $db2sysc_pid_out);

            # ps eww prints full command line environment
            run_cmd("ps eww $pid", $db2sysc_env_out);
            print $errfh "Collected environment for db2sysc PID: $pid\n";
        } else {
            print $errfh "db2sysc PID not found\n";
        }

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
                $collected_files{"$inst:db2diag.log"} = "Success";
            } else {
                $collected_files{"$inst:db2diag.log"} = "Not found";
            }
        } else {
            $collected_files{"$inst:db2diag.log"} = "Invalid diagpath";
        }



     }
     # -----------------------------
        # Attempt db2support
        # -----------------------------
        # Requested behavior:
        #  - Windows: run db2support . -d TSMDB1 -c -s (assumes proper privs)
        #  - Unix/AIX: run as instance owner: su - <instance_owner> -c "db2support . -d TSMDB1 -c -s"
        #
        # -----------------------------
        # Attempt db2support
        # -----------------------------

        my $db2support_dir = File::Spec->catdir($outdir, "db2support");

        # Ensure directory exists
        unless (-d $db2support_dir) {

            eval { make_path($db2support_dir) };
            if ($@) {
                print $errfh "Failed to create db2support directory $db2support_dir: $@\n";
            }
        }

        my $db2support_target = File::Spec->catfile($outdir, "${inst}_db2support.zip");
        my $db2support_out    = File::Spec->catfile($outdir, "${inst}_db2support_output.txt");

        # db2support syntax (first argument is output dir)
        my $db2support_cmd = qq{db2support "$db2support_dir" -d TSMDB1 -c -s};

        if ($os =~ /MSWin32/i) {

            # Use db2cmd so db2support runs inside DB2 Command Window
            my $win_cmd = qq{db2cmd /i /w /c $db2support_cmd};

            my $rc = run_cmd($win_cmd, $db2support_out);

            my $generated_zip = File::Spec->catfile($db2support_dir, "db2support.zip");

            if ($rc == 0 && -e $generated_zip) {
                copy($generated_zip, $db2support_target);
                $collected_files{"$inst:db2support.zip"} = 'Success';
            } else {
                $collected_files{"$inst:db2support.zip"} = ($rc == 0 ? 'ATTEMPTED' : 'Failed');
                print $errfh "db2support did not produce $generated_zip. Check $db2support_out\n";
            }

        } else {

            # Determine instance owner from sqllib
            my $instance_owner = getpwuid((stat("$home/sqllib"))[4]) || $inst;

            # Directory for db2support output (inside outputdir)
            my $local_db2_dir = File::Spec->catdir($db2support_dir, "${inst}_db2support");

            # ZIP file path inside that directory
            my $generated_zip = File::Spec->catfile($local_db2_dir, "db2support.zip");

            # Final target zip path (renamed to simple db2support.zip)
            my $target_zip = File::Spec->catfile($db2support_dir, "db2support.zip");

            # Ensure clean directory
            run_cmd("rm -rf $local_db2_dir");

            # Create directory and apply permissions
            run_cmd("mkdir -p $local_db2_dir");
            run_cmd("chmod 777 $local_db2_dir");

            # Build db2support command to run inside outputdir
            my $db2support_cmd = qq{. ~${instance_owner}/sqllib/db2profile; db2support $local_db2_dir -d TSMDB1 -c -s};

            # Run db2support as instance owner
            my $su_cmd = qq{su - $instance_owner -c '$db2support_cmd'};
            my $rc = run_cmd($su_cmd, $db2support_out);

            # Check and copy results
            if ($rc == 0 && -e $generated_zip) {

                # Copy zip to outputdir root
                copy($generated_zip, $target_zip);

                # Mark Success
                $collected_files{"$inst:db2support.zip"} = 'Success';

                # Cleanup only inner folder, keep main outputdir
                run_cmd("rm -rf $local_db2_dir");

            } else {

                $collected_files{"$inst:db2support.zip"} = ($rc == 0 ? 'ATTEMPTED' : 'Failed');
                print $errfh "db2support did not produce $generated_zip. Check $db2support_out\n";
            }

        }


}

# Run instance collection
collect_db2_instances($output_dir);


# -----------------------------
# Final summary
# -----------------------------
close($errfh);

if ($verbose) {
    print "\n=== Database Module Collection Summary ===\n";
    foreach my $k (sort keys %collected_files) {
        printf " %-15s : %s\n", $k, $collected_files{$k};
    }
    print "\nCollected artifacts are in: $output_dir\n";
    print "Detailed log: $error_log\n";
}

# Determine module status (Success / Partial / Failed)
my $Success_count = 0;
my $Fail_count    = 0;
my $Total         = scalar keys %collected_files;
foreach my $v (values %collected_files) {
    $Success_count++ if $v =~ /^Success$/i;
    $Fail_count++    if $v =~ /^Failed$/i;
}

my $module_status = 'Partial';
if ($Total == 0) {
    $module_status = 'Failed';
} elsif ($Success_count == $Total) {
    $module_status = 'Success';
} elsif ($Fail_count == $Total) {
    $module_status = 'Failed';
} else {
    $module_status = 'Partial';
}

# Exit code mapping (0=Success, 2=Partial, 1=Failed)
exit($module_status eq "Success" ? 0 : $module_status eq "Partial" ? 2 : 1);
