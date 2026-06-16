#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy;
use File::Basename;
use File::Spec;
use FindBin;
use lib "$FindBin::Bin/../../common/modules";
use env;
use utils;
use Getopt::Long;

# ===============================================================
# Script Name : sap-oracle.pl
# Description : Collects SAP Oracle specific diagnostic data
# ===============================================================

# -----------------------------
# Parse command-line arguments
# -----------------------------
my ($output_dir, $verbose, $oracle_user);
GetOptions(
    "output-dir|o=s" => \$output_dir,
    "verbose|v"      => \$verbose,
    "oracle-user=s"  => \$oracle_user,
) or die "Invalid arguments.\n";

die "Error: --output-dir is required\n" unless $output_dir;

# -----------------------------
# Prepare output directory
# -----------------------------
$output_dir = "$output_dir/sap-oracle";
make_path($output_dir) unless -d $output_dir;

# -----------------------------
# Setup
# -----------------------------
my $os = env::_os();
my %collected_files;
my $error_log = "$output_dir/script.log";
open(my $errfh, '>', $error_log) or die "Cannot open $error_log: $!";

print "\n=== Starting SAP Oracle Data Collection ===\n" if $verbose;
print $errfh "Detected OS: $os\n";

# -----------------------------
# Helper Functions
# -----------------------------
sub collect_file {
    my ($src, $name) = @_;
    my $dest = "$output_dir/$name";

    if (-e $src) {
        if (copy($src, $dest)) {
            print $errfh "Collected: $src\n";
            $collected_files{$name} = "Success";
        }
        else {
            print $errfh "Failed to copy $src: $!\n";
            $collected_files{$name} = "Failed";
        }
    }
    else {
        print $errfh "Warning: $src not found\n";
        $collected_files{$name} = "NOT FOUND";
    }
}

sub run_command {
    my ($cmd, $output_file, $item_name) = @_;
    
    my $status = system($cmd);
    $status >>= 8;
    
    if (-s $output_file) {
        $collected_files{$item_name} = "Success";
        print $errfh "Collected $item_name\n" if $verbose;
    } else {
        print $errfh "Warning: $item_name - no data\n";
        $collected_files{$item_name} = "NOT FOUND";
    }
}

sub collect_latest_file {
    my ($dir, $sid) = @_;

    return unless -d $dir;

    opendir(my $dh, $dir) or return;

    my @files = grep {
        -f "$dir/$_"
        && $_ !~ /\.log$/i
    } readdir($dh);

    closedir($dh);

    return unless @files;

    my @sorted =
        sort {
            (stat("$dir/$b"))[9] <=>
            (stat("$dir/$a"))[9]
        } @files;

    my $latest = "$dir/$sorted[0]";
    my $original_filename = "$sorted[0]_$sid";

    collect_file($latest, $original_filename);
}

sub collect_if_exists {
    my ($src, $dest) = @_;

    if (-f $src) {
        collect_file($src, $dest);
        return 1;
    }

    return 0;
}

# =============================
# SECTION 1: Detect SAP SID
# =============================
print $errfh "\n=== Detecting SAP SID ===\n" if $verbose;
my @sids;

if (-d "/usr/sap") {
    opendir(my $dh, "/usr/sap") or warn "Cannot open /usr/sap: $!";
    while (my $entry = readdir($dh)) {
        next if $entry =~ /^\.\.?$/;
        next if $entry eq "hostctrl";
        if (-d "/usr/sap/$entry" && $entry =~ /^[A-Z0-9]{3}$/) {
            push @sids, $entry;
        }
    }
    closedir($dh);
}

if (!@sids) {
    my $ps_output = `ps -ef | grep -i ora_pmon | grep -v grep 2>/dev/null`;
    if ($ps_output =~ m{ora_pmon_(\w+)}) {
        my $sid = uc($1);
        push @sids, $sid unless grep { $_ eq $sid } @sids;
    }
}

if (@sids) {
    print $errfh "Detected SAP SID(s): " . join(", ", @sids) . "\n";
} else {
    print $errfh "Warning: No SAP SID detected\n";
    @sids = ("XXX");
}

# =============================
# SECTION 2: dsm.sys from DSMI_DIR (UNIX only)
# =============================
if ($os !~ /MSWin32/i) {
    print $errfh "\n=== Collecting dsm.sys from DSMI_DIR ===\n" if $verbose;
    
    if ($ENV{DSMI_DIR} && -e "$ENV{DSMI_DIR}/dsm.sys") {
        collect_file("$ENV{DSMI_DIR}/dsm.sys", "dsm.sys_from_DSMI_DIR");
    } else {
        $collected_files{"dsm.sys_from_DSMI_DIR"} = "NOT FOUND";
    }
}

# =============================
# SECTION 3: dsm.sys from API directory (UNIX only)
# =============================
if ($os !~ /MSWin32/i) {
    print $errfh "\n=== Collecting dsm.sys from API directory ===\n" if $verbose;
    
    my @api_dsm_sys_paths = (
        "/opt/tivoli/tsm/client/api/bin64/dsm.sys",
        "/opt/tivoli/tsm/client/api/bin/dsm.sys",
        "/usr/tivoli/tsm/client/api/bin64/dsm.sys",
        "/usr/tivoli/tsm/client/api/bin/dsm.sys",
    );
    
    my $found = 0;
    foreach my $path (@api_dsm_sys_paths) {
        if (-e $path) {
            collect_file($path, "dsm.sys_from_api");
            $found = 1;
            last;
        }
    }
    
    $collected_files{"dsm.sys_from_api"} = "NOT FOUND" unless $found;
}

# =============================
# SECTION 4: Log Files (dsmerror.log, dsierror.log, dsmsched.log)
# =============================
print $errfh "\n=== Collecting Log Files ===\n" if $verbose;


# Collect dsierror.log from API directories
my @dsierror_paths = (
    "/opt/tivoli/tsm/client/api/bin64/dsierror.log",
    "/opt/tivoli/tsm/client/api/bin/dsierror.log",
    "/usr/tivoli/tsm/client/api/bin64/dsierror.log",
    "/usr/tivoli/tsm/client/api/bin/dsierror.log",
);

if ($ENV{DSMI_DIR} && -e "$ENV{DSMI_DIR}/dsierror.log") {
    collect_file("$ENV{DSMI_DIR}/dsierror.log", "dsierror.log");
} else {
    my $found = 0;
    foreach my $log_path (@dsierror_paths) {
        if (-e $log_path) {
            collect_file($log_path, "dsierror.log");
            $found = 1;
            last;
        }
    }
    $collected_files{"dsierror.log"} = "NOT FOUND" unless $found;
}

# =============================
# SECTION 5: DSMI_CONFIG file
# =============================
print $errfh "\n=== Collecting DSMI_CONFIG file ===\n" if $verbose;

if ($ENV{DSMI_CONFIG} && -e $ENV{DSMI_CONFIG}) {
    collect_file($ENV{DSMI_CONFIG}, "dsmi_config_" . basename($ENV{DSMI_CONFIG}));
} else {
    $collected_files{"DSMI_CONFIG"} = "NOT FOUND";
}

# =============================
# SECTION 6: Windows {server}.opt files
# =============================
if ($os =~ /MSWin32/i) {
    print $errfh "\n=== Collecting {server}.opt files ===\n" if $verbose;
    
    if ($ENV{DSMI_CONFIG}) {
        my $opt_dir = dirname($ENV{DSMI_CONFIG});
        # Quote the path to handle spaces in directory names
        my @opt_files = glob(qq{"$opt_dir/*.opt"});
        foreach my $opt_file (@opt_files) {
            collect_file($opt_file, basename($opt_file));
        }
    }
}

# =============================
# SECTION 7: SAP Oracle Files
# =============================
print $errfh "\n=== Collecting SAP Oracle Files ===\n" if $verbose;

foreach my $sid (@sids) {

    next if $sid eq "XXX";

    my (@init_sap_paths, @init_utl_paths, @init_ora_paths);

    if ($os =~ /MSWin32/i) {

        @init_sap_paths = (
            glob("C:/oracle/$sid/*/database/init${sid}.sap"),
            "C:/oracle/$sid/init${sid}.sap",
        );

        @init_ora_paths = (
            glob("C:/oracle/$sid/*/database/init${sid}.ora"),
            "C:/oracle/$sid/init${sid}.ora",
        );

        @init_utl_paths = (
            "C:/usr/sap/$sid/sys/exe/run/init${sid}.utl",
            "C:/oracle/$sid/sapbackup/init${sid}.utl",
            "C:/oracle/$sid/init${sid}.utl",
        );

    } else {

        @init_sap_paths = (
            glob("/oracle/$sid/*/database/init${sid}.sap"),
            "/oracle/$sid/dbs/init${sid}.sap",
            "/oracle/$sid/init${sid}.sap",
        );

        @init_ora_paths = (
            glob("/oracle/$sid/*/database/init${sid}.ora"),
            "/oracle/$sid/dbs/init${sid}.ora",
            "/oracle/$sid/init${sid}.ora",
        );

        @init_utl_paths = (
            "/usr/sap/$sid/SYS/exe/run/init${sid}.utl",
            "/usr/sap/$sid/sys/exe/run/init${sid}.utl",
            "/oracle/$sid/sapbackup/init${sid}.utl",
            "/oracle/$sid/init${sid}.utl",
            "/oracle/$sid/dbs/init${sid}.utl",
        );
    }

    foreach my $file (@init_sap_paths) {
        if (-e $file) {
            collect_file($file, "init${sid}.sap");
            last;
        }
    }

    foreach my $file (@init_ora_paths) {
        if (-e $file) {
            collect_file($file, "init${sid}.ora");
            last;
        }
    }

    foreach my $file (@init_utl_paths) {
        if (-e $file) {
            collect_file($file, "init${sid}.utl");
            last;
        }
    }

    my @init_bki_paths = (
        "/oracle/$sid/sapbackup/init${sid}.bki",
        "/oracle/$sid/init${sid}.bki",
        "/oracle/$sid/dbs/init${sid}.bki",
    );

    foreach my $file (@init_bki_paths) {
        if (-e $file) {
            collect_file($file, "init${sid}.bki");
            last;
        }
    }
}
# =============================
# SECTION 8: sbtio.log
# =============================
print $errfh "\n=== Collecting sbtio.log ===\n" if $verbose;

foreach my $sid (@sids) {

    next if $sid eq "XXX";

    my $sid_lc = lc($sid);

    my @sbtio_paths = (

        "/oracle/$sid/saptrace/diag/rdbms/$sid_lc/$sid/trace/sbtio.log",

        "/oracle/$sid/saptrace/diag/rdbms/$sid_lc/${sid}_DB/trace/sbtio.log",

        "/oracle/$sid/sapbackup/sbtio.log",

        "/oracle/$sid/saparch/sbtio.log",

        "/oracle/$sid/sbtio.log",
    );

    my $found = 0;

    foreach my $log_path (@sbtio_paths) {

        if (-e $log_path) {

            collect_file(
                $log_path,
                "sbtio_${sid}.log"
            );

            $found = 1;
            last;
        }
    }

    $collected_files{"sbtio_${sid}.log"} = "NOT FOUND"
        unless $found;
}

# =============================
# SECTION 9: SAP BRTOOLS Logs
# =============================
print $errfh "\n=== Collecting SAP BRTOOLS Logs ===\n" if $verbose;

make_path("$output_dir/sapbackup");
make_path("$output_dir/saparch");
make_path("$output_dir/sapreorg");

foreach my $sid (@sids) {

    next if $sid eq "XXX";

    my ($sapbackup, $saparch, $sapreorg);

    if ($os =~ /MSWin32/i) {

        $sapbackup = "C:/oracle/$sid/sapbackup";
        $saparch   = "C:/oracle/$sid/saparch";
        $sapreorg  = "C:/oracle/$sid/sapreorg";

    } else {

        $sapbackup = "/oracle/$sid/sapbackup";
        $saparch   = "/oracle/$sid/saparch";
        $sapreorg  = "/oracle/$sid/sapreorg";
    }

    # ----------------------------------
    # Standard SAP logs
    # ----------------------------------

    collect_if_exists(
        "$sapbackup/back${sid}.log",
        "sapbackup/back${sid}.log"
    );

    collect_if_exists(
        "$sapbackup/recov${sid}.log",
        "sapbackup/recov${sid}.log"
    );

    collect_if_exists(
        "$sapbackup/rest${sid}.log",
        "sapbackup/rest${sid}.log"
    );

    collect_if_exists(
        "$saparch/arch${sid}.log",
        "saparch/arch${sid}.log"
    );

    collect_if_exists(
        "$sapreorg/space${sid}.log",
        "sapreorg/space${sid}.log"
    );

    collect_if_exists(
        "$sapreorg/CNTRL${sid}.DBF",
        "sapreorg/CNTRL${sid}.DBF"
    );

    # ----------------------------------
    # Latest generated file from sapbackup
    # (.fnr .crv .rsb etc)
    # ----------------------------------

    if (-d $sapbackup) {

        opendir(my $dh, $sapbackup);

        my @files = grep {
            -f "$sapbackup/$_"
            && $_ !~ /\.log$/i
        } readdir($dh);

        closedir($dh);

        if (@files) {

            my @sorted = sort {
                (stat("$sapbackup/$b"))[9] <=>
                (stat("$sapbackup/$a"))[9]
            } @files;

            collect_file(
                "$sapbackup/$sorted[0]",
                "sapbackup/$sorted[0]"
            );
        }
    }

    # ----------------------------------
    # Latest generated file from saparch
    # (.svd etc)
    # ----------------------------------

    if (-d $saparch) {

        opendir(my $dh, $saparch);

        my @files = grep {
            -f "$saparch/$_"
            && $_ !~ /\.log$/i
        } readdir($dh);

        closedir($dh);

        if (@files) {

            my @sorted = sort {
                (stat("$saparch/$b"))[9] <=>
                (stat("$saparch/$a"))[9]
            } @files;

            collect_file(
                "$saparch/$sorted[0]",
                "saparch/$sorted[0]"
            );
        }
    }

    # ----------------------------------
    # backint.log
    # ----------------------------------

    collect_if_exists(
        "$sapbackup/backint.log",
        "sapbackup/backint.log"
    );

    collect_if_exists(
        "$saparch/backint.log",
        "saparch/backint.log"
    );
}

# =============================
# SECTION 10: Environment (set command output)
# =============================
print $errfh "\n=== Collecting Environment ===\n" if $verbose;

run_command(
    ($os =~ /MSWin32/i ? "set" : "env") . " > \"$output_dir/environment.txt\" 2>&1",
    "$output_dir/environment.txt",
    "environment.txt"
);

# Remove sensitive data
my $env_file = "$output_dir/environment.txt";
if (-e $env_file) {
    open(my $in, '<', $env_file);
    my @lines = <$in>;
    close($in);
    
    @lines = grep { $_ !~ /MUSTGATHER_PASSWORD/i } @lines;
    
    open(my $out, '>', $env_file);
    print $out @lines;
    close($out);
}

# =============================
# SECTION 11: Oracle Version
# =============================
print $errfh "\n=== Collecting Oracle Version ===\n" if $verbose;

foreach my $sid (@sids) {
    next if $sid eq "XXX";
    
    my $version_file = "$output_dir/oracle_version_${sid}.txt";
    
    if ($os !~ /MSWin32/i) {
        my $cmd = "su - oracle -c 'sqlplus -version' 2>/dev/null > \"$version_file\"";
        system($cmd);
        
        if (-s $version_file) {
            $collected_files{"oracle_version_${sid}.txt"} = "Success";
        } else {
            $collected_files{"oracle_version_${sid}.txt"} = "NOT FOUND";
        }
    }
}

# =============================
# SECTION 12: Platform-Specific Data
# =============================
print $errfh "\n=== Collecting Platform-Specific Data ===\n" if $verbose;

if ($os =~ /aix/i) {
    print $errfh "Collecting AIX-specific information...\n" if $verbose;
    run_command("lslpp -l tivoli.tsm.* >\"$output_dir/lslpp_tivoli_tsm.txt\" 2>&1",
                "$output_dir/lslpp_tivoli_tsm.txt", "lslpp_tivoli_tsm.txt");
    run_command("find / -name 'libtdp_r3*' -exec ls -al {} \\; 2>/dev/null >\"$output_dir/libtdp_r3_search.txt\"",
                "$output_dir/libtdp_r3_search.txt", "libtdp_r3_search.txt");

} elsif ($os =~ /linux/i) {
    print $errfh "Collecting Linux-specific information...\n" if $verbose;
    run_command("rpm -qai TIV* TDP* >\"$output_dir/rpm_TIV_TDP.txt\" 2>&1",
                "$output_dir/rpm_TIV_TDP.txt", "rpm_TIV_TDP.txt");
    run_command("find / -name 'libtdp_r3*' -exec ls -al {} \\; 2>/dev/null >\"$output_dir/libtdp_r3_search.txt\"",
                "$output_dir/libtdp_r3_search.txt", "libtdp_r3_search.txt");

} elsif ($os =~ /MSWin32/i) {
    print $errfh "Collecting Windows-specific information...\n" if $verbose;
    
    # Collect orasbt.dll version and location
    run_command("dir /a /s /b c:\\ 2>nul | findstr /i orasbt.dll >\"$output_dir/orasbt_dll_search.txt\" 2>&1",
                "$output_dir/orasbt_dll_search.txt", "orasbt_dll_search.txt");
    
    # Get API version from registry
    my @api_reg_keys = (
        "HKLM\\SOFTWARE\\IBM\\ADSM\\CurrentVersion\\Api",
        "HKLM\\SOFTWARE\\WOW6432Node\\IBM\\ADSM\\CurrentVersion\\Api"
    );
    
    foreach my $key (@api_reg_keys) {
        my $cmd = qq{reg query "$key" /v Path 2>NUL};
        my $out = `$cmd`;
        if ($out =~ /Path\s+REG_\w+\s+([^\r\n]+)/i) {
            my $api_path = $1;
            $api_path =~ s/^\s+|\s+$//g;
            
            my $api_info_file = "$output_dir/api_version_info.txt";
            open(my $fh, '>>', $api_info_file);
            print $fh "API Path from registry: $api_path\n";
            
            if (-e "$api_path\\tsmapi.dll") {
                print $fh "tsmapi.dll found at: $api_path\\tsmapi.dll\n";
                print $fh "Note: Right-click on tsmapi.dll and select Properties > Version tab for version details\n";
            }
            close($fh);
            $collected_files{"api_version_info.txt"} = "Success";
            last;
        }
    }
}

# -----------------------------
# Summary
# -----------------------------
if ($verbose) {
    print "\n=== SAP Oracle Module Summary ===\n";
    foreach my $file (sort keys %collected_files) {
        printf "  %-40s : %s\n", $file, $collected_files{$file};
    }
    print "\nCollected data saved in: $output_dir\n";
}

# -----------------------------
# Exit code
# -----------------------------
my $success_count = grep { $collected_files{$_} eq "Success" } keys %collected_files;
my $total = scalar keys %collected_files;

my $exit_code;
if ($success_count == 0) {
    $exit_code = 1;
}
elsif ($success_count == $total) {
    $exit_code = 0;
}
else {
    $exit_code = 2;
}

close($errfh);
exit($exit_code);

# Made with Bob
