#!/usr/bin/perl
#*************************************************************************************
#
# IBM Storage Protect
#
# name: sp_config.pl
#
# desc: This program is a tool that is intended to facilitate the process of
#       configuring a IBM Storage Protect server on AIX, Linux x86, Linux on Power, or Windows.
#       Appropriate user input is collected and validated, and assuming the validation
#       was successful, the configuration process proceeds up to the point of configuring
#       storage policies, maintenance scripts and schedules, as well as an assortment of client
#       schedules;  At the end of a successful run of this tool, the IBM Storage Protect server is started
#       and ready for immediate use.  The tool is able to collect the necessary user input
#       in an interactive mode, or, non-interactively, from a response file. This script
#       expects that your machine be prepared in the manner described in Chapter 4
#       of the document "IBM Storage Protect Blueprint and Server Automated Configuration for Linux x86",
#       "IBM Storage Protect Blueprint and Server Automated Configuration for AIX",
#       or the document "IBM Storage Protect Blueprint and Server Automated Configuration for Windows",
#       as appropriate for your platform.
#
# usage: perl sp_config.pl [response file path] [-ignoresystemreqs] [-compression]
#
# -ignoresystemreqs  This flag bypasses checking for various requirements such as CPU cores,
#                    memory, and available disk space.
# -compression       Set this flag to have TSM use compression for archive logs and database
#                    backups.  This should only be set with V7 and newer servers.
#
# Notice: This program is provided as a tool intended for use by IBM Internal,
#         IBM Business Partners, and IBM Customers. This program is provided as is,
#         without support, and without warranty of any kind expressed or implied.
#
# (C) Copyright International Business Machines Corp. 2013, 2022.
#*************************************************************************************

use Cwd;
use Sys::Hostname;
use Socket;

$versionString = "Program version 5.1";

my %stateHash
  ; # hash used to store the user's selections and other pertinent information as the script proceeds
    # this will be referred to as the state hash in subsequent comments

my %inputHash = ();

$takeinputfromfile            = 0;
$ignoreSystemRequirementsFlag = 0;
$vAppFlag                     = 0;
$compressFlag                 = 0;
$skipmountFlag                = 0;
$locklistFlag                 = 0;
$kernelFlag                   = 0;
$preallocFlag                 = 0;
$preallocpct                  = 0;
$legacyFlag                   = 0;
$totalargs                    = @ARGV;    # total number command line arguments

$argnum = 0;
while ( $argnum < $totalargs ) {
    $arg = shift(@ARGV);

    if ( $arg eq "-ignoresystemreqs" ) {
        $ignoreSystemRequirementsFlag = 1;
    }
    elsif ( $arg eq "-vapp" ) {
        $vAppFlag = 1;
    }
    elsif ( $arg eq "-compression" ) {
        $compressFlag = 1;
    }
    elsif ( $arg eq "-skipmount" ) {
        $skipmountFlag = 1;
    }
    elsif ( $arg eq "-locklist" ) {
        $locklistFlag = 1;
    }
    elsif ( $arg eq "-kernel" ) {
        $kernelFlag = 1;
    }
    elsif ( $arg eq "-legacy" ) {
        $legacyFlag = 1;
    }
    elsif ( $arg =~ m/-prealloc=(\d+)/ ) {
        $preallocpct = $1;
        if (   ( ( length($preallocpct) == 1 ) && ( $preallocpct =~ m/\d/ ) )
            || ( ( length($preallocpct) == 2 ) && ( $preallocpct =~ m/\d\d/ ) )
            || (   ( length($preallocpct) == 3 )
                && ( $preallocpct =~ m/\d\d\d/ ) ) )
        {
            if ( ( $preallocpct < 0 ) || ( $preallocpct > 100 ) ) {
                die "Invalid preallocation percentage\n";
            }
        }
        else {
            die "Invalid preallocation percentage\n";
        }
        $preallocFlag = 1;
    }
    else {
        $inputfile = $arg;
    }
    $argnum++;
}

if (   ( $preallocFlag == 1 )
    && ( $legacyFlag != 1 )
  )    # Pre-allocation is not possible with a container storage pool
{
    print
      "ERROR: pre-allocation is not allowed with a container storage pool\n";
    die "The -prealloc option must be combined with the -legacy option\n";
}

if ( ( $inputfile ne "" ) && ( !-f $inputfile ) ) {
    die "The input file $inputfile is not found!\n";
}
elsif ( $inputfile ne "" ) {
    $takeinputfromfile = 1;
}

$statefile =
  "serversetupstatefile.txt"; # file used for saving the current state, that is,
    # which setup parameters have already been set and their values,
    # as well as other pertinent information; this is needed
    # to preserve the contents of the state hash (above),
    # in case the user quits with the intent of resuming from the
    # same step that he was on when he quit.  This file will be
    # referred to as the state file in subsequent comments

$cleanupstatefile = "serversetupstatefileforcleanup.txt";

$serversetupLogBase = "setupLog"
  ;  # base part of the name of the script log. Date stamp is added by initLog()
     # subroutine later

$doneflag =
  0;    # this flag will be set to 1 after last step, or if user choices to
        # exit, or quits with intention to resume later

$completionflag =
  0;    # this flag set to one at the end of the last step (if successful)

$SCREENWIDTH  = 80;
$SCREENLENGTH = 20;
$COLUMNWIDTH  = 30;

$currentline = 0;    # to keep track of the current line number on the screen
$substep     = 1;    # to keep track of substep indices

$platform = getPlatform();
if ( $platfrom eq "UNKNOWN" ) {
    die "The platform type UNKNOWN is not supported\n";
}

if ( $platform eq "WIN32" ) {
    $NUMBEROFSTEPS = 17;
}
else {
    $NUMBEROFSTEPS = 18;
}

$SS = getpathdelimiter($platform);

if ( $platform eq "WIN32" ) {
    $systemdrive = $ENV{SYSTEMDRIVE};
    system("chcp 437")
      ;    # Avoid problems parsing command output in non-English environments
}

#
# For Unix, check that the user is root; if not, then die
#

if (   ( $platform eq "LINUX86" )
    || ( $platform eq "AIX" )
    || ( $platform =~ m/LINUXPPC/ ) )
{
    if ($<) {
        die "\n     This script must be run as root!\n\n";
    }
}

$| = 1;

if ( $platform eq "WIN32" ) {
    @stepDescArray = (
        "",
        "",
        "Scale selection",
        "Checking system prerequisites",
        "Server instance owner and group",
        "Server instance directory",
        "Database directories",
        "Active log directory",
        "Archive log directory",
        "Database backup directories",
        "Storage directories",
        "DB2 instance configuration",
        "Formatting the IBM Storage Protect server database",
        "Server name and password",
        "IBM Storage Protect system administrator name and password",
        "Schedule start time",
        "IBM Storage Protect server configuration",
        "Configuration complete"
    );
}
else {
    @stepDescArray = (
        "",
        "",
        "Scale selection",
        "Checking system prerequisites",
        "Server instance owner and group",
        "Server instance directory",
        "Database directories",
        "Active log directory",
        "Archive log directory",
        "Database backup directories",
        "Storage directories",
        "DB2 instance configuration",
        "Formatting the IBM Storage Protect server database",
        "Server name and password",
        "IBM Storage Protect system administrator name and password",
        "Schedule start time",
        "IBM Storage Protect server configuration",
        "Setting up the IBM Storage Protect server service",
        "Configuration complete"
    );
}

# Get the hostname

$thehostname      = hostname();
@thehostnameParts = split( '\.', $thehostname );
$thehostnameFull  = $thehostname;
$thehostname      = $thehostnameParts[0];
$thehostname_uc   = uc($thehostname);

@mountedfs = ();    # to save the list of mounted filesystems

@mountedgpfs = ();  # to save the list of mounted GPFS filesystems

# Default paths for the various IBM Storage Protect server scales (xsmall, small, medium, large)

$defaultserverdrive = "c:";    # for Windows

@defaultdbdirs_xsmall = ("${SS}TSMdbspace00");

@defaultdbbkupdirs_xsmall = ("${SS}TSMbkup00");

@defaultstgdirs_xsmall = ( "${SS}TSMfile00", "${SS}TSMfile01" );

@defaultdbdirs_small = (
    "${SS}TSMdbspace00", "${SS}TSMdbspace01",
    "${SS}TSMdbspace02", "${SS}TSMdbspace03"
);

@defaultdbbkupdirs_small = ( "${SS}TSMbkup00", "${SS}TSMbkup01" );

@defaultstgdirs_small = (
    "${SS}TSMfile00", "${SS}TSMfile01", "${SS}TSMfile02", "${SS}TSMfile03",
    "${SS}TSMfile04", "${SS}TSMfile05", "${SS}TSMfile06", "${SS}TSMfile07",
    "${SS}TSMfile08", "${SS}TSMfile09", "${SS}TSMfile10", "${SS}TSMfile11",
    "${SS}TSMfile12", "${SS}TSMfile13", "${SS}TSMfile14", "${SS}TSMfile15",
    "${SS}TSMfile16", "${SS}TSMfile17", "${SS}TSMfile18", "${SS}TSMfile19"
);

@defaultdbdirs_medium =
  ( "${SS}TSMdbspace00", "${SS}TSMdbspace01", "${SS}TSMdbspace02" );

@defaultdbbkupdirs_medium =
  ( "${SS}TSMbkup00", "${SS}TSMbkup01", "${SS}TSMbkup02", "${SS}TSMbkup03" );

@defaultstgdirs_medium = (
    "${SS}TSMfile00", "${SS}TSMfile01", "${SS}TSMfile02", "${SS}TSMfile03",
    "${SS}TSMfile04", "${SS}TSMfile05", "${SS}TSMfile06", "${SS}TSMfile07",
    "${SS}TSMfile08", "${SS}TSMfile09", "${SS}TSMfile10", "${SS}TSMfile11",
    "${SS}TSMfile12", "${SS}TSMfile13", "${SS}TSMfile14", "${SS}TSMfile15",
    "${SS}TSMfile16", "${SS}TSMfile17", "${SS}TSMfile18", "${SS}TSMfile19",
    "${SS}TSMfile20", "${SS}TSMfile21", "${SS}TSMfile22", "${SS}TSMfile23",
    "${SS}TSMfile24", "${SS}TSMfile25", "${SS}TSMfile26", "${SS}TSMfile27",
    "${SS}TSMfile28", "${SS}TSMfile29", "${SS}TSMfile30", "${SS}TSMfile31",
    "${SS}TSMfile32", "${SS}TSMfile33", "${SS}TSMfile34", "${SS}TSMfile35",
    "${SS}TSMfile36", "${SS}TSMfile37", "${SS}TSMfile38", "${SS}TSMfile39"
);

@defaultdbdirs_large = (
    "${SS}TSMdbspace00", "${SS}TSMdbspace01",
    "${SS}TSMdbspace02", "${SS}TSMdbspace03",
    "${SS}TSMdbspace04", "${SS}TSMdbspace05",
    "${SS}TSMdbspace06", "${SS}TSMdbspace07"
);

@defaultdbbkupdirs_large =
  ( "${SS}TSMbkup00", "${SS}TSMbkup01", "${SS}TSMbkup02", "${SS}TSMbkup03" );

if ( $platform eq "AIX" ) {
    @defaultstgdirs_large = (
        "${SS}TSMfile00", "${SS}TSMfile01",
        "${SS}TSMfile02", "${SS}TSMfile03",
        "${SS}TSMfile04", "${SS}TSMfile05",
        "${SS}TSMfile06", "${SS}TSMfile07",
        "${SS}TSMfile08", "${SS}TSMfile09",
        "${SS}TSMfile10", "${SS}TSMfile11",
        "${SS}TSMfile12", "${SS}TSMfile13",
        "${SS}TSMfile14", "${SS}TSMfile15",
        "${SS}TSMfile16", "${SS}TSMfile17",
        "${SS}TSMfile18", "${SS}TSMfile19",
        "${SS}TSMfile20", "${SS}TSMfile21",
        "${SS}TSMfile22", "${SS}TSMfile23",
        "${SS}TSMfile24", "${SS}TSMfile25",
        "${SS}TSMfile26", "${SS}TSMfile27",
        "${SS}TSMfile28", "${SS}TSMfile29",
        "${SS}TSMfile30", "${SS}TSMfile31",
        "${SS}TSMfile32", "${SS}TSMfile33",
        "${SS}TSMfile34", "${SS}TSMfile35"
    );
}
else {
    @defaultstgdirs_large = (
        "${SS}TSMfile00", "${SS}TSMfile01",
        "${SS}TSMfile02", "${SS}TSMfile03",
        "${SS}TSMfile04", "${SS}TSMfile05",
        "${SS}TSMfile06", "${SS}TSMfile07",
        "${SS}TSMfile08", "${SS}TSMfile09",
        "${SS}TSMfile10", "${SS}TSMfile11",
        "${SS}TSMfile12", "${SS}TSMfile13",
        "${SS}TSMfile14", "${SS}TSMfile15",
        "${SS}TSMfile16", "${SS}TSMfile17",
        "${SS}TSMfile18", "${SS}TSMfile19",
        "${SS}TSMfile20", "${SS}TSMfile21",
        "${SS}TSMfile22", "${SS}TSMfile23",
        "${SS}TSMfile24", "${SS}TSMfile25",
        "${SS}TSMfile26", "${SS}TSMfile27",
        "${SS}TSMfile28", "${SS}TSMfile29",
        "${SS}TSMfile30", "${SS}TSMfile31",
        "${SS}TSMfile32", "${SS}TSMfile33",
        "${SS}TSMfile34", "${SS}TSMfile35",
        "${SS}TSMfile36", "${SS}TSMfile37",
        "${SS}TSMfile38", "${SS}TSMfile39"
    );
}

# Default paths for the GPFS environment

@defaultdbdirs_gpfs     = ("${SS}database${SS}db01");
@defaultstgdirs_gpfs    = ("${SS}deduppool");
@defaultdbbkupdirs_gpfs = ("${SS}dbback");

# Define checks for insecure passwords

my $minPWlength = 15;
my $basicPW = join('', (1..$minPWlength));
my $defaultPW = "<passwordrequired>";     # Do not allow the default string in sample response files
my @insecurePWlist = ("password", "passw0rd", "password1", "password123", "qwerty123", "qwertyiop", "admin", $basicPW);

#
# Some strings (or string sets) that need to be displayed on the screen at various points during the script
#

@promptStringArray =
  ( "\'E\' to exit", "\'Q\' to quit and resume later", "Enter to continue" );

@promptStringArraynoQ = ( "\'E\' to exit", "Enter to continue" );

@promptStringArrayJustContinue =
  ("Press enter to exit the IBM Storage Protect server configuration script");

@promptStringArrayNoContinue =
  ( "\'E\' to exit", "\'Q\' to quit and resume later" );

@promptStringArrayNoContinuenoQ = ("\'E\' to exit");

@promptStringArrayExtNoContinue = (
    "\'E\' to exit",
    "\'Q\' to quit and resume later",
    "\'R\' to repeat this step"
);

@promptStringArrayExtNoContinuenoQ =
  ( "\'E\' to exit", "\'R\' to repeat this step" );

@WelcomeStringArray =
  ("Welcome to the IBM Storage Protect server configuration tool");
@CongratulationsStringArray1 = ("Congratulations!");
@CongratulationsStringArray2 =
  ("Your IBM Storage Protect server is started and ready for use.");

@serverScaleStringArray =
  ("Select the size of your IBM Storage Protect server:");
@serverScaleChoiceStringArray =
  ( "X for extra small", "S for small", "M for medium", "L for large" );

$db2instdirString2 =
  "Or, enter a directory for the IBM Storage Protect instance: ";

$schedStartTimeString1 =
"Press enter to accept the default start time for client backup schedules [22:00].";
$schedStartTimeString2 =
  "Or, enter a start time for backup schedules to begin [HH:MM]: ";

$db2dbbackString1 = "Enter the directories for database backups";
$db2dbbackString2 = "Press enter to accept the defaults, which are:";

$servernameString1 =
  "Press enter to accept the default server name [${thehostname_uc}].";
$servernameString2 = "Or, enter a name for the server: ";

$tcpportString1 = "Press enter to accept the default server tcpport [1500].";
$tcpportString2 = "Or, enter a server tcpport: ";

$serverpasswordString1 =
  "A password is required for the server that is a minimum of $minPWlength characters.";
$serverpasswordString2 = "Enter a password for the server: ";

$db2dbdirString1 = "Enter the database directory paths";
$db2dbdirString2 = "Press enter to accept the defaults, which are:";

$db2actlogString2 = "Or, enter a path for the database active log: ";

$db2archlogString2 = "Or, enter a path for the database archive log: ";

$tsmStgString1 = "Enter the storage paths";
$tsmStgString2 = "Press enter to accept the defaults, which are:";

$db2UserString1 = "Press enter to accept the default owner [tsminst1]";
$db2UserString2 = "Or, enter a user ID for the server instance owner: ";

$db2UserPwString1 = 
  "A password is required for the server instance owner that is a minimum of $minPWlength characters.";

$db2UserHomeDirString2 =
  "Or, enter a home directory for the server instance owner: ";

$db2UserPwString2 = "Enter a password for the server instance owner: ";
$db2UserPwString2_preexistinguser =
  "Enter the password for the server instance owner: ";

$db2GroupString1 = "Press enter to accept the default [tsmsrvrs]";
$db2GroupString2 =
  "Or, enter a name for the primary group of the server instance owner: ";

$chowndb2pathsString =
  "Ownership of all paths was assigned to the server instance owner";

$createDB2instString = "Creating the DB2 instance";

$prepareUserProfsString = "Preparing option files and auxiliary files";

$prepareClientOptString = "Preparing client option files";
$updateDsmservOptString =
  "Updating the IBM Storage Protect server option file";

$setDB2InstParametersString = "Setting the DB2 instance parameters";

$formatServerString = "Database formatting.  Please be patient.";

$createWinServiceString =
  "Creating the Windows service to run IBM Storage Protect";

$adjustLockListString = "Adjusting the DB2 locklist parameter";

$setreorgattribString =
  "Setting IBM Storage Protect global attribute for reorg options";

$initServerString1 = "Applying the configuration macro. Please be patient.";
$initServerString2 = "Continuing with server configuration";
$initServerString3 = "Creating preallocated volumes. Please be patient.";

$setupServertoStartAtRebootString =
  "Setting up the IBM Storage Protect server to start at reboot";

$startingServerString = "Starting the IBM Storage Protect server";

$sysadminidString1 =
"Press enter to accept the default IBM Storage Protect system administrator ID [admin].";
$sysadminidString2 =
  "Or, enter a IBM Storage Protect system administrator ID: ";

$sysadminpwString1 =
"A password is required for the default IBM Storage Protect system administrator.";
$sysadminpwString2 =
  "Enter a IBM Storage Protect system administrator password that is a minimum of $minPWlength characters: ";

$generateRunfileString = "Generating the configuration macros";

$checkSystemParamsString  = "Overall Result";
$updateKernelParamsString = "Updating Kernel Parameters";

$validateShmString   = "Check permissions for /dev/shm";
$errorShmPermissions = "/dev/shm incorrect permissions or not mounted";

@warningStringArray_mem                = ();
@warningStringArray_kernelparams       = ();
@warningStringArray_memandkernelparams = ();

$warningString_mem1 =
  "WARNING: The memory and/or CPU core count on this machine does not";
$warningString_mem2 = "meet the requirements for the specified server scale";

$warningString_kernelparams1 =
  "WARNING: The kernel parameter settings on this machine do";
$warningString_kernelparams2 =
  "not meet the requirements for the specified server scale";

$warningString_memandkernelparams1 =
  "WARNING: The memory and/or CPU core count and the kernel parameter";
$warningString_memandkernelparams2 =
  "settings on this machine do not meet the requirements for the";
$warningString_memandkernelparams3 = "specified server scale";

push( @warningStringArray_mem, $warningString_mem1 );
push( @warningStringArray_mem, $warningString_mem2 );

if ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) ) {
    push( @warningStringArray_kernelparams, $warningString_kernelparams1 );
    push( @warningStringArray_kernelparams, $warningString_kernelparams2 );

    push( @warningStringArray_memandkernelparams,
        $warningString_memandkernelparams1 );
    push( @warningStringArray_memandkernelparams,
        $warningString_memandkernelparams2 );
    push( @warningStringArray_memandkernelparams,
        $warningString_memandkernelparams3 );
}

# Populate array containing valid characters for IBM Storage Protect Server objects

@validCharArray        = ();    # for SP object names
@validCharArraySPpw    = ();    # for SP passwords
@validCharArray_db2unx = ();    # for DB2 user and group names in unix
@validCharArray_db2win = ();    # for DB2 user and group names in Windows

for ( $k = 48 ; $k <= 57 ; $k++ )    # digits
{
    push( @validCharArray,        chr($k) );
    push( @validCharArraySPpw,    chr($k) );
    push( @validCharArray_db2unx, chr($k) );
    push( @validCharArray_db2win, chr($k) );
}

for ( $k = 65 ; $k <= 90 ; $k++ )    # upper case letters
{
    push( @validCharArray,        chr($k) );
    push( @validCharArraySPpw,    chr($k) );
    push( @validCharArray_db2win, chr($k) );
}

for ( $k = 97 ; $k <= 122 ; $k++ )    # lower case letters
{
    push( @validCharArray,        chr($k) );
    push( @validCharArraySPpw,    chr($k) );
    push( @validCharArray_db2unx, chr($k) );
    push( @validCharArray_db2win, chr($k) );
}

push( @validCharArray,        '_' );    # underscore
push( @validCharArraySPpw,    '_' );
push( @validCharArray_db2unx, '_' );
push( @validCharArray_db2win, '_' );
push( @validCharArraySPpw,    '@' );
push( @validCharArray_db2unx, '@' );
push( @validCharArray_db2win, '@' );
push( @validCharArraySPpw,    '#' );
push( @validCharArray_db2unx, '#' );
push( @validCharArray_db2win, '#' );
push( @validCharArraySPpw,    '$' );
push( @validCharArray_db2unx, '$' );
push( @validCharArray_db2win, '$' );
push( @validCharArray,        '.' );    # period
push( @validCharArraySPpw,    '.' );    # period
push( @validCharArray,        '-' );    # hyphen
push( @validCharArraySPpw,    '-' );    # hyphen
push( @validCharArray,        '+' );    # plus sign
push( @validCharArraySPpw,    '+' );    # plus sign
push( @validCharArray,        '&' );    # ampersand
push( @validCharArraySPpw,    '&' );    # ampersand
push( @validCharArraySPpw,    '!' );    # exclamation
push( @validCharArraySPpw,    '%' );    # percent
push( @validCharArraySPpw,    '^' );    # carat
push( @validCharArraySPpw,    '*' );    # asterisk
push( @validCharArraySPpw,    '=' );    # equal sign
push( @validCharArraySPpw,    '`' );    # back tick
push( @validCharArraySPpw,    '(' );    # left paren
push( @validCharArraySPpw,    ')' );    # right paren
push( @validCharArraySPpw,    '|' );    # pipe
push( @validCharArraySPpw,    '{' );    # left brace
push( @validCharArraySPpw,    '}' );    # right brace
push( @validCharArraySPpw,    '[' );    # left bracket
push( @validCharArraySPpw,    ']' );    # right bracket
push( @validCharArraySPpw,    ':' );    # colon
push( @validCharArraySPpw,    ';' );    # semicolon
push( @validCharArraySPpw,    '<' );    # less
push( @validCharArraySPpw,    '>' );    # greater
push( @validCharArraySPpw,    ',' );    # comma
push( @validCharArraySPpw,    '?' );    # question
push( @validCharArraySPpw,    '/' );    # slash
push( @validCharArraySPpw,    '~' );    # tilda


# Define strings for evaluation that may need to be processed in other languages
$db2setidirOK_enu = "successfully";
$db2setidirOK_jpn = "CONFIGURATION\\s+ƒRƒ}ƒ"ƒh‚ª³í‚ÉŠ®—¹‚µ‚Ü‚µ‚½B";

my $yes       = "yes";                  #Same for JP, KO
my $yes_fr    = "oui";
my $yes_de    = "ja";
my $yes_es    = "si";                   #Same for IT
my $yes_pt_BR = "sim";
my $yes_ru    = "Ð´Ð°";
my $yes_zh    = "æ˜¯";                  #Same for zh_CN and zh_TW

#####################################################################################
#
# System Requirements Hash (according to the scale: xsmall, small, medium or large)
#
#####################################################################################

%sysRegs = ();

$sysReqs{xsmall} = {};
$sysReqs{small}  = {};
$sysReqs{medium} = {};
$sysReqs{large}  = {};

#New add for xsmall
$sysReqs{xsmall}->{dbfscount}                = 1;
$sysReqs{xsmall}->{stgfscount}               = 2;
$sysReqs{xsmall}->{dbbackfscount}            = 1;
$sysReqs{xsmall}->{sessionLimit}             = 75;
$sysReqs{xsmall}->{instdirfreespacemin}      = 25000000;
$sysReqs{xsmall}->{dbdirsfreespacemin}       = 200000000;
$sysReqs{xsmall}->{stgdirsfreespacemin}      = 1000000000;
$sysReqs{xsmall}->{dbactlogfreespacemin}     = 26000000;
$sysReqs{xsmall}->{dbarchlogfreespacemin}    = 100000000;
$sysReqs{xsmall}->{dbbackupdirsfreespacemin} = 900000000;
$sysReqs{xsmall}->{initactlogsize}           = "4096";
$sysReqs{xsmall}->{actlogsize}               = "24576";
$sysReqs{xsmall}->{maxcap}                   = "50G";
$sysReqs{xsmall}->{numIdentProc}             = 1;
$sysReqs{xsmall}->{expireResource}           = 4;
$sysReqs{xsmall}->{replSessions}             = 8;
$sysReqs{xsmall}->{dbbkstreams}              = 2;
$sysReqs{xsmall}->{memorymin}                = 22000000;

if ( $platform eq "AIX" || $platform =~ m/LINUXPPC/ ) {
    $sysReqs{xsmall}->{cpucoremin} = 2;
}
else {
    $sysReqs{xsmall}->{cpucoremin} = 4;
}
$sysReqs{xsmall}->{locklist}    = 499712;
$sysReqs{xsmall}->{reclaimProc} = 2;
$sysReqs{xsmall}->{derefProc}   = 2;

$sysReqs{small}->{dbfscount}                = 4;
$sysReqs{small}->{stgfscount}               = 2;
$sysReqs{small}->{dbbackfscount}            = 2;
$sysReqs{small}->{sessionLimit}             = 250;
$sysReqs{small}->{instdirfreespacemin}      = 25000000;
$sysReqs{small}->{dbdirsfreespacemin}       = 600000000;
$sysReqs{small}->{stgdirsfreespacemin}      = 8000000000;
$sysReqs{small}->{dbactlogfreespacemin}     = 96000000;
$sysReqs{small}->{dbarchlogfreespacemin}    = 400000000;
$sysReqs{small}->{dbbackupdirsfreespacemin} = 1200000000;
$sysReqs{small}->{initactlogsize}           = "4096";
$sysReqs{small}->{actlogsize}               = "131072";
$sysReqs{small}->{maxcap}                   = "50G";
$sysReqs{small}->{numIdentProc}             = 12;
$sysReqs{small}->{expireResource}           = 10;
$sysReqs{small}->{replSessions}             = 20;
$sysReqs{small}->{dbbkstreams}              = 2;
$sysReqs{small}->{memorymin}                = 63000000;

if ( $platform eq "AIX" || $platform =~ m/LINUXPPC/ ) {
    $sysReqs{small}->{cpucoremin} = 6;
}
else {
    $sysReqs{small}->{cpucoremin} = 12;
}
$sysReqs{small}->{locklist}                  = 1500160;
$sysReqs{small}->{reclaimProc}               = 10;
$sysReqs{small}->{derefProc}                 = 8;
$sysReqs{medium}->{dbfscount}                = 4;
$sysReqs{medium}->{stgfscount}               = 10;
$sysReqs{medium}->{dbbackfscount}            = 3;
$sysReqs{medium}->{sessionLimit}             = 500;
$sysReqs{medium}->{instdirfreespacemin}      = 25000000;
$sysReqs{medium}->{dbdirsfreespacemin}       = 1900000000;
$sysReqs{medium}->{stgdirsfreespacemin}      = 38000000000;
$sysReqs{medium}->{dbactlogfreespacemin}     = 130000000;
$sysReqs{medium}->{dbarchlogfreespacemin}    = 1500000000;
$sysReqs{medium}->{dbbackupdirsfreespacemin} = 8000000000;
$sysReqs{medium}->{initactlogsize}           = "4096";
$sysReqs{medium}->{actlogsize}               = "131072";
$sysReqs{medium}->{maxcap}                   = "50G";
$sysReqs{medium}->{numIdentProc}             = 16;
$sysReqs{medium}->{expireResource}           = 30;
$sysReqs{medium}->{replSessions}             = 40;
$sysReqs{medium}->{dbbkstreams}              = 4;
$sysReqs{medium}->{memorymin}                = 130000000;

if ( $platform eq "AIX" || $platform =~ m/LINUXPPC/ ) {
    $sysReqs{medium}->{cpucoremin} = 8;
}
else {
    $sysReqs{medium}->{cpucoremin} = 16;
}
$sysReqs{medium}->{locklist}                = 3000320;
$sysReqs{medium}->{reclaimProc}             = 20;
$sysReqs{medium}->{derefProc}               = 8;
$sysReqs{large}->{dbfscount}                = 8;
$sysReqs{large}->{stgfscount}               = 30;
$sysReqs{large}->{dbbackfscount}            = 3;
$sysReqs{large}->{sessionLimit}             = 1000;
$sysReqs{large}->{instdirfreespacemin}      = 25000000;
$sysReqs{large}->{dbdirsfreespacemin}       = 3500000000;
$sysReqs{large}->{stgdirsfreespacemin}      = 78000000000;
$sysReqs{large}->{dbactlogfreespacemin}     = 540000000;
$sysReqs{large}->{dbarchlogfreespacemin}    = 1500000000;
$sysReqs{large}->{dbbackupdirsfreespacemin} = 14000000000;
$sysReqs{large}->{initactlogsize}           = "4096";
$sysReqs{large}->{actlogsize}               = "524032";
$sysReqs{large}->{maxcap}                   = "50G";
$sysReqs{large}->{numIdentProc}             = 32;
$sysReqs{large}->{expireResource}           = 40;
$sysReqs{large}->{replSessions}             = 60;
$sysReqs{large}->{dbbkstreams}              = 12;
$sysReqs{large}->{memorymin}                = 197000000;

if ( $platform eq "AIX" || $platform =~ m/LINUXPPC/ ) {
    $sysReqs{large}->{cpucoremin} = 16;
}
else {
    $sysReqs{large}->{cpucoremin} = 32;
}
$sysReqs{large}->{locklist}    = 5000192;
$sysReqs{large}->{reclaimProc} = 32;
$sysReqs{large}->{derefProc}   = 12;

# Values specific to building a virtual appliance
if ( $vAppFlag == 1 ) {
    $sysReqs{small}->{dbfscount}                = 1;
    $sysReqs{small}->{stgfscount}               = 2;
    $sysReqs{small}->{dbbackfscount}            = 1;
    $sysReqs{small}->{instdirfreespacemin}      = 1;
    $sysReqs{small}->{dbdirsfreespacemin}       = 1;
    $sysReqs{small}->{stgdirsfreespacemin}      = 1;
    $sysReqs{small}->{dbactlogfreespacemin}     = 1;
    $sysReqs{small}->{dbarchlogfreespacemin}    = 1;
    $sysReqs{small}->{dbbackupdirsfreespacemin} = 1;
    $sysReqs{small}->{memorymin}                = 15360;
    $sysReqs{small}->{cpucoremin}               = 4;
}

# Lower expire resource for legacy
if ( $legacyFlag == 1 ) {
    $sysReqs{small}->{expireResource}  = 6;
    $sysReqs{medium}->{expireResource} = 8;
    $sysReqs{large}->{expireResource}  = 10;
}

%tempfreeSpaceHash = ()
  ; # for temporarily saving the freespace as it was at the beginning of eash step (needed for steps 5 - 10)

#####################################################################################
#
# Get the current directory. The templates from which to generate the runfile macro
# are kept in the "resources" subdirectory, under the current directory
#
#####################################################################################

$currentdir = Cwd::cwd();

if ( $platform eq "WIN32" ) {
    $currentdir =~ s#/#\\#g;
}

# If Linux, flag which distro
$isSLES   = 0;
$isRHEL   = 0;
$isUbuntu = 0;
if ( $platform =~ m/LINUX/ ) {
    if ( -f "/etc/SuSE-release" ) {
        $isSLES = 1;
    }
    elsif ( -f "/etc/redhat-release" ) {
        $isRHEL = 1;
    }
    else {
        $uName = `uname -a`;
        if ( $uName =~ m/Ubuntu/ ) {
            $isUbuntu = 1;
        }
    }
}

$resourcesdir = "$currentdir" . "${SS}" . "resources";
$runfilename  = "$currentdir" . "${SS}"
  . "runfile.mac";    # path of the runfile macro to be created
$tsmconfigmacroname = "$currentdir" . "${SS}"
  . "tsmconfig.mac";    # path of the server configuration macro to be created
$createpreallocvolumesmacroname = "$currentdir" . "${SS}"
  . "createvolumes.mac"
  ; # path of the server macro to define preallocated volumes (to be created if needed)

# List of templates from which the runfile macro will be generated

@templateArray = (
    "step1_basics",          "step2_stgpool",
    "step2_cntrpool",        "step3_maintenance",
    "step3_cntrmaintenance", "step4_policy",
    "step5_schedules"
);
@templateArray1 = ("step1_basics");
@templateArray2 =
  ( "step2_stgpool", "step3_maintenance", "step4_policy", "step5_schedules" );

# Verify that all required templates are present

if ( !-d $resourcesdir ) {
    print
"Prepare a directory called \"resources\" under your current directory, containing\n";
    print "the following macro templates:\n";

    $templateString = "";
    $firsttemplate  = 1;

    foreach $templ (@templateArray) {
        $templateshortname = "$templ" . ".template";

        if ( $firsttemplate == 1 ) {
            $templateString = "$templateshortname";
            $firsttemplate  = 0;
        }
        else {
            $templateString = "$templateString" . ", $templateshortname";
        }
    }

    print "$templateString\n";
    die;
}

$alltemplatesfound = 1;

foreach $templ (@templateArray) {
    $templatename      = "$resourcesdir" . "${SS}" . "$templ" . ".template";
    $templateshortname = "$templ" . ".template";

    if ( !-f $templatename ) {
        print "Template $templateshortname was not found in ${resourcesdir}!\n";
        $alltemplatesfound = 0;
    }
}

if ( $alltemplatesfound == 0 ) {
    die
"Some macro templates are missing from $resourcesdir. See the above for details\n";
}

# initialize step number from the information in the state file, if it exists.  If it does not exist,
# start at step 1

if ( -f $statefile ) {
    initializeHash();
    populateHash()
      ;    # reset the hash contents from the information in the state file

    if ( $totalargs > 0 ) {
        if (
            ( $inputfile ne $stateHash{inputfile} )
            || ( $ignoreSystemRequirementsFlag !=
                $stateHash{ignoresystemrequirements} )
            || ( $vAppFlag != $stateHash{vappflag} )
            || ( $compressFlag != $stateHash{compressflag} )
            || ( $skipmountFlag != $stateHash{skipmountflag} )
            || ( $preallocFlag != $stateHash{preallocflag} )
            || ( $preallocpct != $stateHash{preallocpct} )
          )
        {
            die
"The configuration script has been restarted with different command line arguments than initially started with\n. Please resubmit the command with the correct arguments or do not specify any arguments\n";
        }
    }

    $stepnumber = $stateHash{laststep};    # start where we last left off

    $serversetupLog = $stateHash{logname}
      ; # stay with the same log, and also the same command line parameters, if any

    $takeinputfromfile            = $stateHash{takeinputfromfile};
    $inputfile                    = $stateHash{inputfile};
    $ignoreSystemRequirementsFlag = $stateHash{ignoresystemrequirements};
    $vAppFlag                     = $stateHash{vappflag};
    $compressFlag                 = $stateHash{compressflag};
    $skipmountFlag                = $stateHash{skipmountflag};
    $preallocFlag                 = $stateHash{preallocflag};
    $preallocpct                  = $stateHash{preallocpct};

    $parameterstring = "";

    if ( $takeinputfromfile == 1 ) {
        $parameterstring .= " $inputfile";
    }
    if ( $ignoreSystemRequirementsFlag == 1 ) {
        $parameterstring .= " -ignoresystemreqs";
    }
    if ( $vAppFlag == 1 ) {
        $parameterstring .= " -vapp";
    }
    if ( $compressFlag == 1 ) {
        $parameterstring .= " -compression";
    }
    if ( $skipmountFlag == 1 ) {
        $parameterstring .= " -skipmount";
    }
    if ( $preallocFlag == 1 ) {
        $parameterstring .= " -prealloc=${preallocpct}";
    }

    if ( length($parameterstring) > 0 ) {
        logentry(
"        Resuming configuration script from the beginning of step $stepnumber with the following parameters:\n"
        );
        logentry("        $parameterstring\n");
    }
    else {
        logentry(
"        Resuming configuration script from the beginning of step $stepnumber\n"
        );
    }

    if ( $stepnumber > 2 ) {

        # we need to get the list of mounted filesystems again

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            @mountOut = `mount`;
        }
        elsif ( $platform eq "WIN32" ) {
            @mountVolOut = `mountvol`;
        }

        logentry("        Mounted filesystems are:\n");

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            foreach $mntpnt (@mountOut) {
                if (
                    (
                           ( $platform eq "LINUX86" )
                        || ( $platform =~ m/LINUXPPC/ )
                    )
                    && (
                        (
                            $mntpnt =~
                            m#^/dev\S+\s+on\s+(\S+)\s+type\s+ext3\s+\((\S+)\)#
                        )
                        || ( $mntpnt =~
                            m#^/dev\S+\s+on\s+(\S+)\s+type\s+ext4\s+\((\S+)\)# )
                        || ( $mntpnt =~
                            m#^/dev\S+\s+on\s+(\S+)\s+type\s+xfs\s+\((\S+)\)# )
                    )
                  )
                {
                    $mpt           = $1;
                    $attributeStr  = $2;
                    @attributeList = split( ',', $attributeStr );
                    $has_rw_attrib = 0;
                    foreach $attrib (@attributeList) {
                        if ( $attrib eq "rw" ) {
                            $has_rw_attrib = 1;
                        }
                    }
                    if ( $has_rw_attrib == 1 ) {
                        push( @mountedfs, $mpt );
                        logentry("        $mpt\n");
                    }
                }
                elsif (
                    (
                           ( $platform eq "LINUX86" )
                        || ( $platform =~ m/LINUXPPC/ )
                        || ( $platform eq "AIX" )
                    )
                    && ( $mntpnt =~
                        m#^\S+\s+on\s+(\S+)\s+type\s+gpfs\s+\((\S+)\)# )
                    || ( $mntpnt =~
                        m#/dev\S+\s+(\S+)\s+mmfs\s+.*\s+(\S+dev\S+)# )
                  )
                {
                    $mpt           = $1;
                    $attributeStr  = $2;
                    @attributeList = split( ',', $attributeStr );
                    $has_rw_attrib = 0;
                    foreach $attrib (@attributeList) {
                        if ( $attrib eq "rw" ) {
                            $has_rw_attrib = 1;
                        }
                    }
                    if ( $has_rw_attrib == 1 ) {
                        push( @mountedgpfs, $mpt );
                        logentry("        $mpt\n");
                    }
                }
                elsif (( $platform eq "AIX" )
                    && ( $mntpnt =~ m#^\s*/dev\S+\s+(\S+)\s+jfs2# ) )
                {
                    push( @mountedfs, $1 );
                    logentry("        $1\n");
                }
            }
        }

        if ( $platform eq "WIN32" ) {
            foreach $mntvolline (@mountVolOut) {
                if (   ( $mntvolline !~ m/\\\\/ )
                    && ( $mntvolline =~ m/\s+(\w\:\S*)\\$/ ) )
                {
                    push( @mountedfs, $1 );
                    logentry("        $1\n");
                }
            }
        }
    }
}
else    # if the state file does not exist we are starting from the beginning
{
    $stepnumber = 1;
    initializeHash();
    $serversetupLog = initLog();
    $stateHash{logname} = $serversetupLog;

    # save the values of command line parameters, if any

    $stateHash{takeinputfromfile} = $takeinputfromfile;
    if ( $takeinputfromfile == 1 ) {
        $stateHash{inputfile} = $inputfile;

        # Confirm the specified passwords are at least 15 characters in length to match the new 8.1.16 default
        # and confirm there are no insecure passwords in the input file
        my @pwList = ("db2userpw", "tsmsysadminpw", "serverpassword");
        foreach $pwSource (@pwList) {
            if (getinputfromfile($pwSource) == 1) {
                my $pwToValidate = $inputHash{$pwSource};
                if (validatePassword($pwToValidate) == 1) {
                    print "\n               ERROR: Insecure $pwSource password specified in response file.\n\n";
                    exit 1;
                }
            }
        }

    }
    else {
        $stateHash{inputfile} = "";
    }
    $stateHash{ignoresystemrequirements} = $ignoreSystemRequirementsFlag;
    $stateHash{vappflag}                 = $vAppFlag;
    $stateHash{compressflag}             = $compressFlag;
    $stateHash{skipmountflag}            = $skipmountFlag;
    $stateHash{preallocflag}             = $preallocFlag;
    $stateHash{preallocpct}              = $preallocpct;
}

verifyPrereqs();    # check that server and BA client are installed

#
# Main Loop
#

while ( ( $doneflag == 0 ) && ( $stepnumber <= $NUMBEROFSTEPS ) ) {
    clearscreen();

    processStep($stepnumber);

    $stepnumber++;
}

if ( $stepnumber > $NUMBEROFSTEPS ) {
    $completionflag = 1;
}

dumpHashtoLog();

if ( $completionflag == 1 ) {
    resetState();
}

############################################################
#      sub: displayPrompt
#     desc: For displaying a prompt on the screen and
#           await user's response: to either continue,
#           exit altogether, or quit with intent to
#           resume later from this step
#
#   params: 1. the number of the step from which this subroutine
#              was called
#           2. a flag, which, if not null, means not to offer the
#              Q (quit) option
#
#  returns: none
#
############################################################

sub displayPrompt {
    my $stp     = shift(@_);
    my $noqflag = shift(@_);

    do {
        $repeatprompt = 0;

        my $numlinesdown = $SCREENLENGTH - $currentline + 1;

        if ( $numlinesdown < 1 ) {
            $numlinesdown = 1;
        }

        if ( $noqflag eq "" ) {
            displayCenteredStrings( $numlinesdown, \@promptStringArray, 1 );
        }
        else {
            displayCenteredStrings( $numlinesdown, \@promptStringArraynoQ, 1 );
        }
        displayCenteredPromptingString( 1, "TSM CONFIG> ", 2, 1 );

        $response = <STDIN>;

        chomp($response);

        if ( ( $response eq "E" ) || ( $response eq "e" ) ) {
            resetState();
            $doneflag = 1;
        }
        elsif (( $noqflag eq "" )
            && ( ( $response eq "Q" ) || ( $response eq "q" ) ) )
        {
            $stateHash{laststep} = $stepnumber;
            $doneflag = 1;
            dumpHash();
        }
        elsif ( $response eq "" ) {
            $stateHash{laststep} = $stepnumber;
        }
        else    # for invalid options
        {
            $repeatprompt = 1;
            $errorstring =
              "The option $response is invalid.  Please try again:";
            displayString( 10, 12, $errorstring, 1, $stp );
        }
    } while ( $repeatprompt != 0 );
}

############################################################
#      sub: displayPromptContinueWithWarning
#     desc: For displaying a prompt on the screen and
#           await user's response: to either continue,
#           exit altogether, or quit with intent to
#           resume later from this step.  However, this
#           prompt also includes a warning, and is used only
#           when the system does not meet the recommended
#           memory or (in the case of Linux) the kernel settings
#           for the specified server scale, only if the script
#           was originally invoked using the "-ignoresystemreqs"
#           flag
#
#   params: 1. the number of the step from which this subroutine
#              was called
#           2. an array of warning strings to display
#
#  returns: none
#
############################################################

sub displayPromptContinueWithWarning {
    my $stp                   = shift(@_);
    my $warningStringArrayRef = shift(@_);

    $numberofwarningstrings = @{$warningStringArrayRef};

    do {
        $repeatprompt = 0;

        my $numlinesdownforWarning =
          int( ( $SCREENLENGTH - $currentline ) / 2 );

        if ( $numlinesdownforWarning < 1 ) {
            $numlinesdownforWarning = 1;
        }

        my $numlinesdown =
          ( $SCREENLENGTH - $currentline + 1 ) -
          $numlinesdownforWarning -
          $numberofwarningstrings;

        if ( $numlinesdown < 1 ) {
            $numlinesdown = 1;
        }

        displayString( 10, $numlinesdownforWarning,
            $warningStringArrayRef->[0] );

        for ( $i = 1 ; $i <= ( $numberofwarningstrings - 1 ) ; $i++ ) {
            displayString( 10, 1, $warningStringArrayRef->[$i] );
        }

        displayCenteredStrings( $numlinesdown, \@promptStringArray, 1 );
        displayCenteredPromptingString( 1, "TSM CONFIG> ", 2, 1 );

        $response = <STDIN>;

        chomp($response);

        if ( ( $response eq "E" ) || ( $response eq "e" ) ) {
            resetState();
            $doneflag = 1;
        }
        elsif ( ( $response eq "Q" ) || ( $response eq "q" ) ) {
            $stateHash{laststep} = $stepnumber;
            $doneflag = 1;
            dumpHash();
        }
        elsif ( $response eq "" ) {
            $stateHash{laststep} = $stepnumber;
        }
        else    # for invalid options
        {
            $repeatprompt = 1;
            $errorstring =
              "The option $response is invalid.  Please try again:";
            displayString( 10, 12, $errorstring, 1, $stp );
        }
    } while ( $repeatprompt != 0 );
}

############################################################
#      sub: displayPromptJustContinue
#     desc: Like displayPrompt, but for this one simply the
#           prompt to enter to continue, and is used on the
#           final screen
#
#   params: none
#  returns: none
#
############################################################

sub displayPromptJustContinue {
    my $numlinesdown = $SCREENLENGTH - $currentline + 1;

    if ( $numlinesdown < 1 ) {
        $numlinesdown = 1;
    }

    displayCenteredStrings( $numlinesdown, \@promptStringArrayJustContinue, 1 );
    displayCenteredPromptingString( 1, "TSM CONFIG> ", 2, 1 );

    $response = <STDIN>;
}

############################################################
#      sub: displayPromptNoContinue
#     desc: Like displayPrompt, but for this one there is no
#           option to continue. It is called if there was a
#           problem encountered that the user must fix
#           before going on
#
#   params: 1. the number of the step from which this subroutine
#              was called
#           2. a flag, which, if not null, means not to offer the
#              Q (quit) option
#  returns: none
#
############################################################

sub displayPromptNoContinue {
    my $stp     = shift(@_);
    my $noqflag = shift(@_);

    do {
        $repeatprompt = 0;
        my $numlinesdown = $SCREENLENGTH - $currentline + 1;

        if ( $numlinesdown < 1 ) {
            $numlinesdown = 1;
        }

        if ( $noqflag eq "" ) {
            displayCenteredStrings( $numlinesdown,
                \@promptStringArrayNoContinue, 1 );
        }
        else {
            displayCenteredStrings( $numlinesdown,
                \@promptStringArrayNoContinuenoQ, 1 );
        }
        displayCenteredPromptingString( 1, "TSM CONFIG> ", 2, 1 );

        $response = <STDIN>;

        chomp($response);

        if ( ( $response eq "E" ) || ( $response eq "e" ) ) {
            resetState();
            $doneflag = 1;
        }
        elsif (( $noqflag eq "" )
            && ( ( $response eq "Q" ) || ( $response eq "q" ) ) )
        {
            $stateHash{laststep} = $stepnumber;
            $doneflag = 1;
            dumpHash();
        }
        else    # for invalid options
        {
            $repeatprompt = 1;
            $errorstring =
              "The option $response is invalid.  Please try again:";
            displayString( 10, 12, $errorstring, 1, $stp );
        }
    } while ( $repeatprompt != 0 );
}

############################################################
#      sub: displayPromptExtNoContinue
#     desc: Like displayPromptNoContinue, but for this one there is
#           also the option to repeat the last step. This subroutine
#           is used to prompt the user on repeatable steps
#
#   params: 1. the number of the step from which this subroutine
#              was called
#           2. an optional flag which, if not null, indicates
#              that the screen should be cleared right after
#              selecting the repeat option (R)
#           3. a flag, which, if not null, means not to offer the
#              Q (quit) option
#  returns: none
#
############################################################

sub displayPromptExtNoContinue {
    my $stp     = shift(@_);
    my $clsflag = shift(@_);
    my $noqflag = shift(@_);

    do {
        $repeatprompt = 0;

        my $numlinesdown = $SCREENLENGTH - $currentline + 1;

        if ( $numlinesdown < 1 ) {
            $numlinesdown = 1;
        }

        if ( $noqflag eq "" ) {
            displayCenteredStrings( $numlinesdown,
                \@promptStringArrayExtNoContinue, 1 );
        }
        else {
            displayCenteredStrings( $numlinesdown,
                \@promptStringArrayExtNoContinuenoQ, 1 );
        }
        displayCenteredPromptingString( 1, "TSM CONFIG> ", 2, 1 );

        $response = <STDIN>;

        chomp($response);

        if ( ( $response eq "E" ) || ( $response eq "e" ) ) {
            resetState();
            $doneflag = 1;
            return 0;
        }
        elsif (( $noqflag eq "" )
            && ( ( $response eq "Q" ) || ( $response eq "q" ) ) )
        {
            $stateHash{laststep} = $stepnumber;
            $doneflag = 1;
            dumpHash();
            return 0;
        }
        elsif ( ( $response eq "R" ) || ( $response eq "r" ) ) {
            if ( $clsflag ne "" ) {
                clearscreen();
            }
            return 1;
        }
        else    # for invalid options
        {
            $repeatprompt = 1;
            $errorstring =
              "The option $response is invalid.  Please try again:";
            displayString( 10, 12, $errorstring, 1, $stp );
        }
    } while ( $repeatprompt != 0 );
}

############################################################
#      sub: resetState
#     desc: Deletes the state file; this is called if the user
#           elects to exit out without the intent to continue from
#           where he left off, or when the last step of the script
#           completes successfully
#
#   params: none
#  returns: none
#
############################################################

sub resetState {
    dumpHashforCleanup();

    if ( -f $statefile ) {
        unlink($statefile);
    }
    cleanup();
}

############################################################
#      sub: dumpHash
#     desc: Dumps the contents of the state hash to the
#           state file
#
#   params: none
#  returns: none
#
############################################################

sub dumpHash {
    open( STATEFH, ">$statefile" ) or die "Unable to open $statefile\n";
    while ( my ( $key, $value ) = each(%stateHash) ) {
        if ( $key eq "dbdirpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                print STATEFH "dbdirpath --- $pth\n";
            }
        }
        elsif ( $key eq "tsmstgpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                print STATEFH "tsmstgpath --- $pth\n";
            }
        }
        elsif ( $key eq "dbbackdirpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                print STATEFH "dbbackdirpath --- $pth\n";
            }
        }
        elsif ( $key eq "createddirs"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                print STATEFH "createddir --- $pth\n";
            }
        }
        elsif ( $key eq "createdusers"
          )    # this is an array reference, so need to extract the members
        {
            foreach $usr ( @{$value} ) {
                print STATEFH "createduser --- $usr\n";
            }
        }
        elsif ( $key eq "createdgroups"
          )    # this is an array reference, so need to extract the members
        {
            foreach $grp ( @{$value} ) {
                print STATEFH "createdgroup --- $grp\n";
            }
        }
        elsif ( $key eq "numpreallocvols"
          )    # this is an array reference, so need to extract the members
        {
            foreach $stgi ( @{$value} ) {
                $stgp    = $stgi->{stgdir};
                $numvols = $stgi->{numvols};
                print STATEFH "numvolumes --- $stgp - $numvols\n";
            }
        }
        elsif ( $key ne "freespacehash" ) {
            print STATEFH "$key --- $value\n";
        }
    }

# save the contents of the temporary freespace hash, because upon resuming, the freespace hash must have
# the values that were in place at the BEGINNING of the step where the user quit (Q)

    while ( my ( $mpt, $frspc ) = each(%tempfreeSpaceHash) ) {
        print STATEFH "freespace --- $mpt - $frspc\n";
    }
    close STATEFH;
}

############################################################
#      sub: dumpHashforCleanup
#     desc: Dumps the contents of the state hash to a file
#           that can subsequently be used by another script
#           for cleaning up the server configuration (i.e., for
#           undoing everything done by the configuration script)
#
#   params: none
#  returns: none
#
############################################################

sub dumpHashforCleanup {
    open( STATEFH, ">$cleanupstatefile" )
      or die "Unable to open $cleanupstatefile\n";
    while ( my ( $key, $value ) = each(%stateHash) ) {
        if ( $key eq "dbdirpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                print STATEFH "dbdirpath --- $pth\n";
            }
        }
        elsif ( $key eq "tsmstgpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                print STATEFH "tsmstgpath --- $pth\n";
            }
        }
        elsif ( $key eq "dbbackdirpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                print STATEFH "dbbackdirpath --- $pth\n";
            }
        }
        elsif ( $key eq "createddirs"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                print STATEFH "createddir --- $pth\n";
            }
        }
        elsif ( $key eq "createdusers"
          )    # this is an array reference, so need to extract the members
        {
            foreach $usr ( @{$value} ) {
                print STATEFH "createduser --- $usr\n";
            }
        }
        elsif ( $key eq "createdgroups"
          )    # this is an array reference, so need to extract the members
        {
            foreach $grp ( @{$value} ) {
                print STATEFH "createdgroup --- $grp\n";
            }
        }
        elsif ( $key eq "freespacehash"
          )    # this is an hash reference, so need to extract the members
        {
            while ( my ( $mpt, $frspc ) = each( %{$value} ) ) {
                print STATEFH "freespace --- $mpt - $frspc\n";
            }
        }
        elsif ( $key eq "numpreallocvols"
          )    # this is an array reference, so need to extract the members
        {
            foreach $stgi ( @{$value} ) {
                $stgp    = $stgi->{stgdir};
                $numvols = $stgi->{numvols};
                print STATEFH "numvolumes --- $stgp - $numvols\n";
            }
        }
        elsif ( $key eq "db2userpw" ) {
            print STATEFH "$key --- ********\n";
        }
        elsif ( $key eq "adminPW" ) {
            print STATEFH "$key --- ********\n";
        }
        else {
            print STATEFH "$key --- $value\n";
        }
    }
    close STATEFH;
}

############################################################
#      sub: dumpHashtoLog
#     desc: Dumps the contents of the state hash to the
#           script log
#
#   params: none
#  returns: none
#
############################################################

sub dumpHashtoLog {
    open( LOGH, ">>$serversetupLog" ) or die "Unable to open $serversetupLog\n";

    print LOGH "\n\n*****************************************************\n";
    print LOGH "\n\nDumping state parameter values to the log:\n\n";

    while ( my ( $key, $value ) = each(%stateHash) ) {
        if ( $key eq "dbdirpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                for ( $k = 0 ; $k < 5 ; $k++ ) {
                    print LOGH " ";
                }
                print LOGH "dbdirpath";
                for (
                    $k = 0 ;
                    $k < ( $COLUMNWIDTH - length("dbdirpath") ) ;
                    $k++
                  )
                {
                    print LOGH " ";
                }
                print LOGH "$pth\n";
            }
        }
        elsif ( $key eq "tsmstgpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                for ( $k = 0 ; $k < 5 ; $k++ ) {
                    print LOGH " ";
                }
                print LOGH "tsmstgpath";
                for (
                    $k = 0 ;
                    $k < ( $COLUMNWIDTH - length("tsmstgpath") ) ;
                    $k++
                  )
                {
                    print LOGH " ";
                }
                print LOGH "$pth\n";
            }
        }
        elsif ( $key eq "dbbackdirpaths"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                for ( $k = 0 ; $k < 5 ; $k++ ) {
                    print LOGH " ";
                }
                print LOGH "dbbackdirpath";
                for (
                    $k = 0 ;
                    $k < ( $COLUMNWIDTH - length("dbbackdirpath") ) ;
                    $k++
                  )
                {
                    print LOGH " ";
                }
                print LOGH "$pth\n";
            }
        }
        elsif ( $key eq "createddirs"
          )    # this is an array reference, so need to extract the members
        {
            foreach $pth ( @{$value} ) {
                for ( $k = 0 ; $k < 5 ; $k++ ) {
                    print LOGH " ";
                }
                print LOGH "createddir";
                for (
                    $k = 0 ;
                    $k < ( $COLUMNWIDTH - length("createddir") ) ;
                    $k++
                  )
                {
                    print LOGH " ";
                }
                print LOGH "$pth\n";
            }
        }
        elsif ( $key eq "createdusers"
          )    # this is an array reference, so need to extract the members
        {
            foreach $usr ( @{$value} ) {
                for ( $k = 0 ; $k < 5 ; $k++ ) {
                    print LOGH " ";
                }
                print LOGH "createduser";
                for (
                    $k = 0 ;
                    $k < ( $COLUMNWIDTH - length("createduser") ) ;
                    $k++
                  )
                {
                    print LOGH " ";
                }
                print LOGH "$usr\n";
            }
        }
        elsif ( $key eq "createdgroups"
          )    # this is an array reference, so need to extract the members
        {
            foreach $grp ( @{$value} ) {
                for ( $k = 0 ; $k < 5 ; $k++ ) {
                    print LOGH " ";
                }
                print LOGH "createdgroup";
                for (
                    $k = 0 ;
                    $k < ( $COLUMNWIDTH - length("createdgroup") ) ;
                    $k++
                  )
                {
                    print LOGH " ";
                }
                print LOGH "$grp\n";
            }
        }
        elsif ( $key eq "freespacehash"
          )    # this is an hash reference, so need to extract the members
        {
            while ( my ( $mpt, $frspc ) = each( %{$value} ) ) {
                for ( $k = 0 ; $k < 5 ; $k++ ) {
                    print LOGH " ";
                }
                print LOGH "freespace";
                for (
                    $k = 0 ;
                    $k < ( $COLUMNWIDTH - length("freespace") ) ;
                    $k++
                  )
                {
                    print LOGH " ";
                }
                print LOGH "$mpt $frspc\n";
            }
        }
        elsif ( $key eq "numpreallocvols"
          )    # this is an array reference, so need to extract the members
        {
            foreach $stgi ( @{$value} ) {
                $stgp    = $stgi->{stgdir};
                $numvols = $stgi->{numvols};
                for ( $k = 0 ; $k < 5 ; $k++ ) {
                    print LOGH " ";
                }
                print LOGH "numvolumes";
                for (
                    $k = 0 ;
                    $k < ( $COLUMNWIDTH - length("numvolumes") ) ;
                    $k++
                  )
                {
                    print LOGH " ";
                }
                print LOGH "$stgp $numvols\n";
            }
        }
        else {
            for ( $k = 0 ; $k < 5 ; $k++ ) {
                print LOGH " ";
            }
            print LOGH "$key";
            for ( $k = 0 ; $k < ( $COLUMNWIDTH - length("$key") ) ; $k++ ) {
                print LOGH " ";
            }
            if ( $key eq "db2userpw" ) {
                print LOGH "********\n";
            }
            elsif ( $key eq "adminPW" ) {
                print LOGH "********\n";
            }
            else {
                print LOGH "$value\n";
            }
        }
    }
    close LOGH;
}

############################################################
#      sub: saveFreeSpace
#     desc: Used to temporarily save the contents of the
#           freespace hash at the beginning of steps 5 - 10
#           This is needed in case the user wants to quit
#           (option Q) at the end of one of those steps, with
#           the intention of resuming later.
#
#   params: none
#  returns: none
#
############################################################

sub saveFreeSpace {
    %tempfreeSpaceHash = ();

    while ( my ( $mpt, $frspc ) = each( %{ $stateHash{freespacehash} } ) ) {
        $tempfreeSpaceHash{$mpt} = $frspc;
    }
}

############################################################
#      sub: initializeHash
#     desc: Initializes the state hash, including initializing
#           the arrays that will contain the list of db directories
#           and TSM storage directories to empty arrays
#
#   params: none
#  returns: none
#
############################################################

sub initializeHash {
    %stateHash = ();

    my $dbdirpathArrayRef =
      [];    # initialize reference to empty arrays for the db directories

    my $tsmstgpathArrayRef =
      []; # initialize reference to empty arrays for the tsm storage directories

    my $dbbackdirpathArrayRef =
      [];   # initialize reference to empty arrays for the db backup directories

    my $dirscreatedbyconfigArrayRef =
      [];   # initialize reference to directories that are created by the script
     # useful when script is run with the -skipmount option or in GPFS environment

    my $userscreatedbyconfigArrayRef =
      [];    # initialize reference to users that are created by the script

    my $groupscreatedbyconfigArrayRef =
      [];    # initialize reference to groups that are created by the script

    # Hash to keep track of freespace left in various filesystems used for the
    # server setup. It will have entries for various filesystems, and entry
    # for a given filesystem being the "remaining" free space in that filesystem

    my $freeSpaceHashRef = {};    # initialize reference to the freespace hash

    my $preAllocationArrayRef =
      [];    # initialize reference to the pre-allocation array

    $stateHash{dbdirpaths}      = $dbdirpathArrayRef;
    $stateHash{tsmstgpaths}     = $tsmstgpathArrayRef;
    $stateHash{dbbackdirpaths}  = $dbbackdirpathArrayRef;
    $stateHash{createddirs}     = $dirscreatedbyconfigArrayRef;
    $stateHash{createdusers}    = $userscreatedbyconfigArrayRef;
    $stateHash{createdgroups}   = $groupscreatedbyconfigArrayRef;
    $stateHash{freespacehash}   = $freeSpaceHashRef;
    $stateHash{numpreallocvols} = $preAllocationArrayRef;
    $stateHash{runfile}         = $runfilename;
    $stateHash{tsmconfigmacro}  = $tsmconfigmacroname;
    $stateHash{createpreallocatedvolumesmacro} =
      $createpreallocvolumesmacroname;
    $stateHash{GPFS} = "no";

    if ( $compressFlag == 1 ) {
        $stateHash{dbbkcompress} = "compress=yes";
    }
    else {
        $stateHash{dbbkcompress} = "";
    }
}

############################################################
#      sub: populateHash
#     desc: Repopulates the state hash, from the state file contents;
#           this is called when the user restarts the script after
#           having quit with the intent to continue from
#           where he left off
#
#   params: none
#  returns: none
#
############################################################

sub populateHash {
    $dbdirpthcnt      = 0;
    $tsmstgpthcnt     = 0;
    $dbbackdirpthcnt  = 0;
    $createddirscnt   = 0;
    $createduserscnt  = 0;
    $createdgroupscnt = 0;
    $preallocvolscnt  = 0;

    $dbdirpathArrayRef             = $stateHash{dbdirpaths};
    $tsmstgpathArrayRef            = $stateHash{tsmstgpaths};
    $dbbackdirpathArrayRef         = $stateHash{dbbackdirpaths};
    $dirscreatedbyconfigArrayRef   = $stateHash{createddirs};
    $userscreatedbyconfigArrayRef  = $stateHash{createdusers};
    $groupscreatedbyconfigArrayRef = $stateHash{createdgroups};
    $freeSpaceHashRef              = $stateHash{freespacehash};
    $preAllocationArrayRef         = $stateHash{numpreallocvols};

    open( STATEFH, "<$statefile" ) or die "Unable to open $statefile\n";
    while (<STATEFH>) {
        if ( $_ =~ m/(\w+)\s+---\s+(\S+)\s+-\s+(\S+)/ ) {
            $thekey    = $1;
            $thesubkey = $2;
            $thevalue  = $3;

            if ( $thekey eq "freespace" ) {
                $freeSpaceHashRef->{$thesubkey} = $thevalue;
            }
            elsif ( $thekey eq "numvolumes" ) {
                my $stginfo = {};
                $mptinfo->{stgdir}                         = $thesubkey;
                $mptinfo->{numvols}                        = $thevalue;
                $preAllocationArrayRef->[$preallocvolscnt] = $stginfo;
                $preallocvolscnt++;
            }
        }
        elsif ( $_ =~ m/(\w+)\s+---\s+(\S+)/ ) {
            $thekey   = $1;
            $thevalue = $2;

            if (   ( $thekey ne "dbdirpath" )
                && ( $thekey ne "tsmstgpath" )
                && ( $thekey ne "dbbackdirpath" )
                && ( $thekey ne "createddir" )
                && ( $thekey ne "createduser" )
                && ( $thekey ne "createdgroup" ) )
            {
                $stateHash{$thekey} = $thevalue;
            }
            elsif ( $thekey eq "dbdirpath"
              )    # add the db directory paths to the db directory array
            {
                $dbdirpathArrayRef->[$dbdirpthcnt] = $thevalue;
                $dbdirpthcnt++;
            }
            elsif ( $thekey eq "tsmstgpath"
              ) # add the tsm storage directory paths to the tsm storage directory array
            {
                $tsmstgpathArrayRef->[$tsmstgpthcnt] = $thevalue;
                $tsmstgpthcnt++;
            }
            elsif ( $thekey eq "dbbackdirpath"
              ) # add the db backup directory paths to the db backup directory array
            {
                $dbbackdirpathArrayRef->[$dbbackdirpthcnt] = $thevalue;
                $dbbackdirpthcnt++;
            }
            elsif ( $thekey eq "createddir"
              ) # add the created directory paths to the created directories array
            {
                $dirscreatedbyconfigArrayRef->[$createddirscnt] = $thevalue;
                $createddirscnt++;
            }
            elsif ( $thekey eq "createduser"
              )    # add the created users to the created users array
            {
                $userscreatedbyconfigArrayRef->[$createduserscnt] = $thevalue;
                $createduserscnt++;
            }
            elsif ( $thekey eq "createdgroup"
              )   # add the created directory groups to the created groups array
            {
                $groupscreatedbyconfigArrayRef->[$createdgroupscnt] = $thevalue;
                $createdgroupscnt++;
            }
        }
    }
    close STATEFH;
}

############################################################
#      sub: processStep
#     desc: Calls, via a switch statement, the appropriate
#           subroutine to handle processing associated with
#           the step number passed in as the argument
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub processStep {
    $stpnum = shift(@_);

    if    ( $stpnum == 1 )  { $substep = 1; showWelcome($stpnum); }
    elsif ( $stpnum == 2 )  { $substep = 1; getServerScale($stpnum); }
    elsif ( $stpnum == 3 )  { $substep = 1; checkSystemParams($stpnum); }
    elsif ( $stpnum == 4 )  { $substep = 1; getDbUserandGroup($stpnum); }
    elsif ( $stpnum == 5 )  { $substep = 1; getInstanceDirectory($stpnum); }
    elsif ( $stpnum == 6 )  { $substep = 1; getDbDirectories($stpnum); }
    elsif ( $stpnum == 7 )  { $substep = 1; getDbactLog($stpnum); }
    elsif ( $stpnum == 8 )  { $substep = 1; getDbarchLog($stpnum); }
    elsif ( $stpnum == 9 )  { $substep = 1; getDbBackupDirectories($stpnum); }
    elsif ( $stpnum == 10 ) { $substep = 1; getTsmStoragePaths($stpnum); }
    elsif ( $stpnum == 11 ) { $substep = 1; createDB2instance($stpnum); }
    elsif ( $stpnum == 12 ) { $substep = 1; formatserver($stpnum); }
    elsif ( $stpnum == 13 ) { $substep = 1; getserverNameandPassword($stpnum); }
    elsif ( $stpnum == 14 ) { $substep = 1; getsysadminCredentials($stpnum); }
    elsif ( $stpnum == 15 ) { $substep = 1; getBackupStartTime($stpnum); }
    elsif ( $stpnum == 16 ) { $substep = 1; initializeServer($stpnum); }
    elsif ( ( $stpnum == 17 ) && ( $platform eq "WIN32" ) ) {
        $substep = 1;
        showCongratulations($stpnum);
    }
    elsif ( $stpnum == 17 ) { $substep = 1; setupforstartatreboot($stpnum); }
    elsif ( $stpnum == 18 ) { $substep = 1; showCongratulations($stpnum); }
}

############################################################
#      sub: showWelcome
#     desc: Displays a welcome screen at the beginning of
#           script execution
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub showWelcome {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Display welcome screen\n");

    displayStepNumAndDesc($stpn);

    displayCenteredStrings( 3, \@WelcomeStringArray );

    if ( $takeinputfromfile == 1 ) {
        sleep 2;
    }
    else {
        displayPrompt($stpn);
    }
}

############################################################
#      sub: showCongratulations
#     desc: Displays congratulations screen at the end of a
#           successful run of this configuration script
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub showCongratulations {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Display congratulations screen\n");

    displayStepNumAndDesc($stpn);

    displayCenteredStrings( 3, \@CongratulationsStringArray1 );
    displayCenteredStrings( 3, \@CongratulationsStringArray2 );

    if ( $takeinputfromfile == 1 ) {
        sleep 2;
        print "\n\n";
    }
    else {
        displayPromptJustContinue();
    }
}

############################################################
#      sub: getServerScale
#     desc: Prompts for, and obtains the server scale from
#           the user. The server scale is either small, medium
#           or large. After determining the server scale, the
#           key/value pairs in the sysReqs hash pertaining to that
#           scale are added to the state hash. This is a repeatable
#           step (i.e., the R option is available in case of invalid
#           input)
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getServerScale {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the server scale: small, medium, or large\n");

    do {

        displayStepNumAndDesc($stpn);

        $repeatflag = 0;

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("serverscale");
        }

        if ( $foundinputinfile == 1 ) {
            $scale = $inputHash{serverscale};
        }
        else {
            displayCenteredStrings( 3, \@serverScaleStringArray );
            displayCenteredStrings( 2, \@serverScaleChoiceStringArray );
            displayCenteredPromptingString( 1, "--> ", 2 );

            $scale = <STDIN>;

            chomp($scale);
        }

        #New add for xsmall
        if ( ( $scale eq "X" ) || ( $scale eq "x" ) ) {
            $stateHash{serverscale} = "xsmall";
        }
        elsif ( ( $scale eq "S" ) || ( $scale eq "s" ) ) {
            $stateHash{serverscale} = "small";
        }
        elsif ( ( $scale eq "M" ) || ( $scale eq "m" ) ) {
            $stateHash{serverscale} = "medium";
        }
        elsif ( ( $scale eq "L" ) || ( $scale eq "l" ) ) {
            $stateHash{serverscale} = "large";
        }
        else {
            $errorstring = genresultString( "Server Scale> $scale",
                40, "[ERROR]", "Invalid scale" );
            displayString( 10, 3, $errorstring, 1, $stpn );
            $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
        }

    } while ( ( $doneflag == 0 ) && ( $repeatflag != 0 ) );

    if ( $doneflag == 0 ) {
        $okstring = genresultString( "Server Scale> $scale", 40, "[OK]" );
        displayString( 10, 3, $okstring, 1, $stpn );

        logentry(
            "        User response: server scale: $stateHash{serverscale}\n");

        # augment the hash with the sysReqs values for the specified scale

        $selectedsysReqsRef = $sysReqs{ $stateHash{serverscale} };

        while ( my ( $k, $v ) = each %{$selectedsysReqsRef} ) {
            $stateHash{$k} = $v;
        }

        # Before going on, we needed the mounted filesystems (or volumes)

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            @mountOut = `mount`;
        }
        elsif ( $platform eq "WIN32" ) {
            @mountVolOut = `mountvol`;
        }

        logentry("        Mounted filesystems (volumes) are:\n");

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            foreach $mntpnt (@mountOut) {
                if (
                    (
                           ( $platform eq "LINUX86" )
                        || ( $platform =~ m/LINUXPPC/ )
                    )
                    && (
                        (
                            $mntpnt =~
                            m#^/dev\S+\s+on\s+(\S+)\s+type\s+ext3\s+\((\S+)\)#
                        )
                        || ( $mntpnt =~
                            m#^/dev\S+\s+on\s+(\S+)\s+type\s+ext4\s+\((\S+)\)# )
                        || ( $mntpnt =~
                            m#^/dev\S+\s+on\s+(\S+)\s+type\s+xfs\s+\((\S+)\)# )
                    )
                  )
                {
                    $mpt           = $1;
                    $attributeStr  = $2;
                    @attributeList = split( ',', $attributeStr );
                    $has_rw_attrib = 0;
                    foreach $attrib (@attributeList) {
                        if ( $attrib eq "rw" ) {
                            $has_rw_attrib = 1;
                        }
                    }
                    if ( $has_rw_attrib == 1 ) {
                        push( @mountedfs, $mpt );
                        logentry("        $mpt\n");
                    }
                }
                elsif (
                    (
                           ( $platform eq "LINUX86" )
                        || ( $platform =~ m/LINUXPPC/ )
                        || ( $platform eq "AIX" )
                    )
                    && ( $mntpnt =~
                        m#^\S+\s+on\s+(\S+)\s+type\s+gpfs\s+\((\S+)\)# )
                    || ( $mntpnt =~
                        m#/dev\S+\s+(\S+)\s+mmfs\s+.*\s+(\S+dev\S+)# )
                  )
                {
                    $mpt           = $1;
                    $attributeStr  = $2;
                    @attributeList = split( ',', $attributeStr );
                    $has_rw_attrib = 0;
                    foreach $attrib (@attributeList) {
                        if ( $attrib eq "rw" ) {
                            $has_rw_attrib = 1;
                        }
                    }
                    if ( $has_rw_attrib == 1 ) {
                        push( @mountedgpfs, $mpt );
                        logentry("        $mpt\n");
                    }
                }
                elsif (( $platform eq "AIX" )
                    && ( $mntpnt =~ m#^\s*/dev\S+\s+(\S+)\s+jfs2# ) )
                {
                    push( @mountedfs, $1 );
                    logentry("        $1\n");
                }
            }
        }

        if ( $platform eq "WIN32" ) {
            foreach $mntvolline (@mountVolOut) {
                if (   ( $mntvolline !~ m/\\\\/ )
                    && ( $mntvolline =~ m/\s+(\w\:\S*)\\$/ ) )
                {
                    push( @mountedfs, $1 );
                    logentry("        $1\n");
                }
            }
        }

        if ( $foundinputinfile == 1 ) {
            sleep 2;
        }
        else {
            displayPrompt($stpn);
        }
    }
}

############################################################
#      sub: isGPFS
#     desc: Determines whether the instance directory mount
#           point is under a GPFS filesystem.
#
#   params: none
#  returns: 1 if the instance directory is under a GPFS filesystem
#           0 if the instance directory is not under a GPFS filesystem
#
############################################################

sub isGPFS {
    return isunderGPFS( $stateHash{instdirmountpoint} );
}

############################################################
#      sub: isunderGPFS
#     desc: Determines whether the directory specified by the
#           argument is under a GPFS filesystem.
#
#   params: 1. the directory to check
#  returns: 1 if the directory is under a GPFS filesystem
#           0 if the directory is not under a GPFS filesystem
#
############################################################

sub isunderGPFS {
    $dpth = shift(@_);

    $isGPFSdir = 0;

    $dpthfs = getencompassingmountpoint($dpth);
    foreach $gpfsmntpt (@mountedgpfs) {
        if ( $dpthfs eq $gpfsmntpt ) {
            $isGPFSdir = 1;
        }
    }

    return $isGPFSdir;
}

############################################################
#      sub: getInstanceDirectory
#     desc: Prompts for, and obtains the IBM Storage Protect server instance directory
#           from the user. If the instance directory specified by the
#           user resides under a GPFS filesystem, then this is considered
#           to be a GPFS environment, and the home directory of the DB2 instance
#           owner is then moved to a subdirectory of the instance directory with
#           the same name as the DB2 user. An attempt is then made to validate
#           the instance directory. This is a repeatable step, unless there
#           is an error moving the home directory of the DB2 user
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getInstanceDirectory {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the IBM Storage Protect instance directory\n");

    $db2usr     = $stateHash{db2user};
    $db2homedir = $stateHash{db2home};

    saveFreeSpace();

    do {
        displayStepNumAndDesc($stpn);

        $repeatflag = 0;

        $stateHash{instdirmountpoint} = "";
        $instdirtotalfreespace = 0;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            $db2instdirString1 =
"Press enter to accept the default [${db2homedir}${SS}${db2usr}].";
        }
        elsif ( $platform eq "WIN32" ) {
            $db2instdirString1 =
"Press enter to accept the default [${defaultserverdrive}${SS}${db2usr}].";
        }

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("instdirmountpoint");
        }

        if ( $foundinputinfile == 1 ) {
            $instdirmountpoint = $inputHash{instdirmountpoint};
        }
        else {
            displayString( 10, 3, $db2instdirString1 );
            displayString( 10, 3, $db2instdirString2 );

            $instdirmountpoint = <STDIN>;

            chomp($instdirmountpoint);

            if ( $instdirmountpoint eq "" ) {
                if (   ( $platform eq "LINUX86" )
                    || ( $platform eq "AIX" )
                    || ( $platform =~ m/LINUXPPC/ ) )
                {
                    $instdirmountpoint = "${db2homedir}${SS}${db2usr}";
                }
                elsif ( $platform eq "WIN32" ) {
                    $instdirmountpoint = "${defaultserverdrive}${SS}${db2usr}";
                }
            }
        }

        $InsufficentSpaceInstdirErrorString =
          "There is insufficient space for the server instance directory";
        $enclmntpnt = getencompassingmountpoint($instdirmountpoint);
        $noSuidInstdirErrorString =
          "$enclmntpnt is mounted with the nosuid option";

        logentry(
            "        User response: instance directory: $instdirmountpoint\n");

        ( $rc, $msgstring ) = createsubdirsundermntpnt($instdirmountpoint);

        if ( $rc == 0 ) {
            ( $rc, $msgstring ) = validateMountPoint( $instdirmountpoint, 0, 1 )
              ;    # the instance directory need not be a mount point
        }

        if ( $rc == 0 ) {

            # check for nosuid option on the mount point

            if (   $platform eq "LINUX86"
                || $platform =~ m/LINUXPPC/
                || $platform =~ m/AIX/ )
            {
                foreach $mntpnt (@mountOut) {
                    if ( $mntpnt =~ m/\s+$enclmntpnt\s+.*nosuid/ ) {
                        $rc = 1;
                        logentry("        ERROR: $noSuidInstdirErrorString\n");
                        $msgstring = $noSuidInstdirErrorString;
                    }
                }
            }
        }

        if ( $rc == 0 ) {

            # check if total size is sufficient for this scale

            if (
                sufficientspaceexists(
                    $instdirmountpoint, $stateHash{instdirfreespacemin},
                    \$instdirtotalfreespace
                ) == 0
              )
            {
                logentry(
"        Free space in $instdirmountpoint is $instdirtotalfreespace\n"
                );
                logentry(
"        The amount of free space for the server instance directory is not sufficient for $stateHash{serverscale} server\n"
                );
                displayString( 10, 2, $InsufficentSpaceInstdirErrorString );
                $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
            }
            else {

                logentry(
"        The free space required for the instance directory is $stateHash{instdirfreespacemin}"
                );
                logentry(
"        Free space in $instdirmountpoint is $instdirtotalfreespace\n"
                );
                logentry(
"        The amount of free space left in $enclmntpnt after taking into account the space for the instance directory is $stateHash{freespacehash}->{$enclmntpnt}\n"
                );

                $stateHash{instdirmountpoint} = "$instdirmountpoint";

                if ( isGPFS() == 1 ) {
                    logentry("        GPFS environment has been detected\n");

                    if ( isunderGPFS( $stateHash{db2home} ) == 0 ) {

                        $newdb2home =
                          "$stateHash{instdirmountpoint}" . "${SS}" . "$db2usr";

                        displayString( 10, 3, "GPFS environment detected." );

                        displayString( 10, 3,
                            "Moving DB2 home directory to $newdb2home" );

                        if (   ( $platform eq "LINUX86" )
                            || ( $platform eq "AIX" )
                            || ( $platform =~ m/LINUXPPC/ ) )
                        {
                            if ( ispreexistinguser($db2usr) == 0 ) {
                                $change_db2user_home_cmd =
"usermod -m -d $newdb2home $db2usr 2>/dev/null";

                                $chguserhomerc =
                                  system("$change_db2user_home_cmd");
                                logentry(
"        Issuing command: $change_db2user_home_cmd\n"
                                );
                                if ( $chguserhomerc != 0 ) {
                                    logentry(
"        There was an error when trying to change the home directory of instance owner $db2usr to $newdb2home\n"
                                    );
                                    $okstring = genresultString(
"Instance directory> $instdirmountpoint",
                                        65, "[OK]"
                                    );
                                    displayString( 10, 3, $okstring, 1, $stpn );
                                    displayString( 10, 3,
                                        "GPFS environment detected." );
                                    $errorstring_gpfs = genresultString(
"Moving DB2 home directory to $newdb2home",
                                        65, "[ERROR]"
                                    );
                                    displayString( 10, 3, $errorstring_gpfs );
                                    $repeatflag =
                                      displayPromptNoContinue($stpn);
                                }
                                else {
                                    logentry(
"        The home directory of instance owner $db2usr changed to $newdb2home\n"
                                    );
                                    $stateHash{db2home} = "$newdb2home";
                                    $stateHash{GPFS}    = "yes";
                                    $okstring           = genresultString(
"Instance directory> $instdirmountpoint",
                                        65, "[OK]"
                                    );
                                    displayString( 10, 3, $okstring, 1, $stpn );
                                    displayString( 10, 3,
                                        "GPFS environment detected." );
                                    $okstring_gpfs = genresultString(
"Moving DB2 home directory to $newdb2home",
                                        65, "[OK]"
                                    );
                                    displayString( 10, 3, $okstring_gpfs );

                                    if ( $foundinputinfile == 1 ) {
                                        sleep 2;
                                    }
                                    else {
                                        displayPrompt($stpn);
                                    }
                                }
                            }
                            else {
                                logentry(
"        The instance owner $db2usr already existed at configuration time. The home directory of $db2usr will not be moved\n"
                                );
                                $okstring = genresultString(
                                    "Instance directory> $instdirmountpoint",
                                    65, "[OK]" );
                                displayString( 10, 3, $okstring, 1, $stpn );
                                displayString( 10, 3,
                                    "GPFS environment detected." );
                                $errorstring_gpfs = genresultString(
                                    "Moving DB2 home directory to $newdb2home",
                                    65, "[ERROR]", "pre-existing user"
                                );
                                displayString( 10, 3, $errorstring_gpfs );
                                $repeatflag = displayPromptNoContinue($stpn);
                            }
                        }
                    }
                    else {
                        $stateHash{GPFS} = "yes";
                        $okstring = genresultString(
                            "Instance directory> $instdirmountpoint",
                            65, "[OK]" );
                        displayString( 10, 3, $okstring, 1, $stpn );
                        displayString( 10, 3, "GPFS environment detected." );

                        if ( $foundinputinfile == 1 ) {
                            sleep 2;
                        }
                        else {
                            displayPrompt($stpn);
                        }
                    }
                }
                else {
                    $okstring =
                      genresultString( "Instance directory> $instdirmountpoint",
                        40, "[OK]" );
                    displayString( 10, 3, $okstring, 1, $stpn );

                    if ( $foundinputinfile == 1 ) {
                        sleep 2;
                    }
                    else {
                        displayPrompt($stpn);
                    }
                }
            }
        }
        else {
            $errorstring =
              genresultString( "Instance directory> $instdirmountpoint",
                40, "[ERROR]", $msgstring );
            displayString( 10, 3, $errorstring, 1, $stpn );
            $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
        }
    } while ( $repeatflag != 0 );
}

############################################################
#      sub: prepareReorgOpts
#     desc: Prepares the IBM Storage Protect server reorg related options
#           depending on which IBM Storage Protect server level is being
#           used.  For servers older than 635 and 711, both
#           table and index reorg are disabled.  For newer
#           server, reorg is enabled for both table and index
#           with large tables being disabled.
#
############################################################
sub prepareReorgOpts {
    $sVersionLong = $stateHash{serverVersionLong};

    if ( $sVersionLong >= 713 )    # Unrestricted index reorganization
    {
        $stateHash{reorgTable} = "YES";
        $stateHash{reorgIndex} = "YES";
        $stateHash{reorgDisableTable} =
"DISABLEREORGTABLE BF_AGGREGATED_BITFILES,BF_BITFILE_EXTENTS,ARCHIVE_OBJECTS,BACKUP_OBJECTS";
        $stateHash{reorgDisableIndex} = "";
    }
    elsif (
        ( $serverVersion >= 7 && $sVersionLong >= 711 )
        ||                         # Allow reorg of some tables and indexes
        ( $serverVersion == 6 && $sVersionLong >= 635 )
      )
    {
        $stateHash{reorgTable} = "YES";
        $stateHash{reorgIndex} = "YES";
        $stateHash{reorgDisableTable} =
"DISABLEREORGTABLE BF_AGGREGATED_BITFILES,BF_BITFILE_EXTENTS,ARCHIVE_OBJECTS,BACKUP_OBJECTS";
        $stateHash{reorgDisableIndex} =
"DISABLEREORGINDEX BF_AGGREGATED_BITFILES,BF_BITFILE_EXTENTS,ARCHIVE_OBJECTS,BACKUP_OBJECTS";
    }
    else                           # Disable all on-line reorgs
    {
        $stateHash{reorgTable}        = "NO";
        $stateHash{reorgIndex}        = "NO";
        $stateHash{reorgDisableTable} = "";
        $stateHash{reorgDisableIndex} = "";
    }
}

############################################################
#      sub: getServerNameandPassword
#     desc: Prompts for, and obtains the server name and server
#           password and server tcpport from the user. The server
#           dsmserv.opt is then updated and client option files
#           created.  Also obtains and sets TCPPORT, and sets
#           disablereorg options.
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getserverNameandPassword {
    $stpn = shift(@_);

    logentry( "Step ${stpn}_${substep}: Get the server name\n", 1 );

    do {
        displayStepNumAndDesc($stpn);

        $repeatflag = 0;

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("servername");
        }

        if ( $foundinputinfile == 1 ) {
            $servername = $inputHash{servername};
        }
        else {
            displayString( 10, 2, $servernameString1 );
            displayString( 10, 2, $servernameString2 );

            $servername = <STDIN>;

            chomp($servername);

            if ( $servername eq "" ) {
                $servername = $thehostname_uc;
            }
        }

        ( $rc, $msgstring ) = validateServerObjectName( $servername, 64 );

        if ( $rc == 0 ) {
            if ( $foundinputinfile == 1 ) {
                displayString( 10, 3, "Server name> $servername" );
                sleep 2;
            }
        }
        else {
            $errorstring = genresultString( "Server name> $servername",
                40, "[ERROR]", $msgstring );
            displayString( 10, 4, $errorstring, 1, $stpn );
            $repeatflag = displayPromptExtNoContinue( $stpn, 1, "noq" );
        }
    } while ( ( $doneflag == 0 ) && ( $repeatflag != 0 ) );

    if ( $doneflag == 0 ) {
        $stateHash{serverName} = "$servername";

        logentry("        User response: server name: $servername\n");

        logentry( "Step ${stpn}_${substep}: Get the server password\n", 1 );

        do {
            $repeatflag = 0;

            $foundinputinfile = 0;

            if ( $takeinputfromfile == 1 ) {
                $foundinputinfile = getinputfromfile("serverpassword");
            }

            if ( $foundinputinfile == 1 ) {
                $serverpassword = $inputHash{serverpassword};
                if ( validatePassword($serverpassword) == 1 ) {
                    sleep 5;
                    $errorstring = genresultString(
                      "Invalid password specified.",
                      40, "[ERROR]", "serverpassword");
                    displayString( 10, 4, $errorstring, 1, $stpn );
                    $repeatstep = displayPromptNoContinue( $stpn, 1 );
                }
            }
            else {
                my $validPW = 0;
                while (! $validPW) {
                    displayString( 10, 2, $serverpasswordString1 );
                    displayString( 10, 2, $serverpasswordString2 );

                    $serverpassword = <STDIN>;

                    chomp($serverpassword);
                    if ( validatePassword($serverpassword) == 0 ) {
                       $validPW = 1;
                    }
                }
            }

            # Password validation is now handled in validatePassword()
            #( $rc, $msgstring ) =
            #  validateServerObjectName( $serverpassword, 64 );

            if ( $foundinputinfile == 1 ) {
               displayString( 10, 3, "Server password> ********" );
               sleep 2;
            }

        } while ( ( $doneflag == 0 ) && ( $repeatflag != 0 ) );

        if ( $doneflag == 0 ) {
            $stateHash{serverPassword} = "$serverpassword";

            logentry("        User response: server password: ********\n");

            logentry( "Step ${stpn}_${substep}: Get the server tcpport\n", 1 );

            do {
                $repeatflag = 0;

                $foundinputinfile = 0;

                if ( $takeinputfromfile == 1 ) {
                    $foundinputinfile = getinputfromfile("tcpport");
                }

                if ( $foundinputinfile == 1 ) {
                    $tcpport = $inputHash{tcpport};
                }
                else {
                    displayString( 10, 2, $tcpportString1 );
                    displayString( 10, 2, $tcpportString2 );

                    $tcpport = <STDIN>;

                    chomp($tcpport);

                    if ( $tcpport eq "" ) {
                        $tcpport = "1500";
                    }
                }

                ( $rc, $msgstring ) = validateTcpport($tcpport);

                if ( $rc == 0 ) {
                    if ( $foundinputinfile == 1 ) {
                        displayString( 10, 3, "Server tcpport> $tcpport" );
                        sleep 2;
                    }
                }
                else {
                    $errorstring = genresultString( "Server tcpport> $tcpport",
                        40, "[ERROR]", $msgstring );
                    displayString( 10, 4, $errorstring, 1, $stpn );
                    $repeatflag = displayPromptExtNoContinue( $stpn, 1, "noq" );
                    if ( $doneflag == 0 ) {
                        displayStepNumAndDesc($stpn);
                    }
                }
            } while ( ( $doneflag == 0 ) && ( $repeatflag != 0 ) );

            if ( $doneflag == 0 ) {
                $stateHash{tcpport} = $tcpport;

                logentry("        User response: tcpport: $tcpport\n");

              # update the dsmserv.opt with the tcpport and disable reorg values

                prepareReorgOpts();

                logentry(
"Step ${stpn}_${substep}: Update dsmserv.opt with the tcpport value\n",
                    1
                );
                $disableReorg = 0;
                if ( $stateHash{reorgDisableTable} ne "" ) {
                    logentry(
"Step ${stpn}_${substep}: Update dsmserv.opt with the disablereorg values\n",
                        1
                    );
                    $disableReorg = 1;
                }

                $instdirmntpnt = $stateHash{instdirmountpoint};

                $updatedsmservrc = 1;

                $dsmservoptfile = "${instdirmntpnt}${SS}dsmserv.opt";

                if ( open( DSMSERVOPTH, "<${dsmservoptfile}" ) ) {
                    @dsmservoptcontents = <DSMSERVOPTH>;
                    close DSMSERVOPTH;
                    $updatedsmservrc = 0;
                }

                if ( $updatedsmservrc == 1 ) {
                    logentry(
"        There was an error opening the dsmserv.opt file\n"
                    );

                    $errorstring =
                      genresultString( $updateDsmservOptString, 50, "[ERROR]",
                        "error opening dsmserv.opt" );
                    displayString( 10, 2, $errorstring );
                    displayPromptNoContinue( $stpn, "noq" );
                }

                sleep 1;

                $updatedsmservrc = 1;

                if ( open( DSMSERVOPTH, ">${dsmservoptfile}" ) ) {
                    $tcppadded = 0;

                    foreach $optln (@dsmservoptcontents) {
                        if (   ( $tcppadded == 0 )
                            && ( $optln =~ m/^\s*TCPport\s+\d+/i ) )
                        {
                            print DSMSERVOPTH "TCPport $tcpport\n";
                            $tcppadded = 1;
                        }
                        elsif (( $tcppadded == 0 )
                            && ( $optln =~ m/^\*\s*TCPport\s+\d+/i ) )
                        {
                            print DSMSERVOPTH "TCPport $tcpport\n";
                            $tcppadded = 1;
                        }
                        elsif ( $optln !~ m/^\*/ ) {
                            print DSMSERVOPTH "$optln";
                        }
                    }
                    if ( $disableReorg == 1 ) {
                        print DSMSERVOPTH "\n$stateHash{reorgDisableTable}\n";
                        if ( $stateHash{reorgDisableIndex} ne "" ) {
                            print DSMSERVOPTH "$stateHash{reorgDisableIndex}\n";
                        }
                    }
                    close DSMSERVOPTH;
                    $updatedsmservrc = 0;
                }

                if ( $updatedsmservrc == 1 ) {
                    logentry(
"        There was an error updating the dsmserv.opt file\n"
                    );

                    $errorstring =
                      genresultString( $updateDsmservOptString, 50, "[ERROR]",
                        "error updating dsmserv.opt" );
                    displayString( 10, 2, $errorstring );
                    displayPromptNoContinue( $stpn, "noq" );
                }
                else {
                    $okstring =
                      genresultString( $updateDsmservOptString, 50, "[OK]" );
                    displayString( 10, 2, $okstring );
                }

                # preparing client option files

                ( $prepclientoptrc, $msgstring ) =
                  prepareclientoptfiles( $stpn, $tcpport );

                if ( $prepclientoptrc == 1 ) {
                    $errorstring =
                      genresultString( $prepareClientOptString, 50, "[ERROR]",
                        "$msgstring" );
                    displayString( 10, 2, $errorstring );
                    displayPromptNoContinue( $stpn, "noq" );
                }
                else {
                    $okstring =
                      genresultString( $prepareClientOptString, 50, "[OK]" );
                    displayString( 10, 2, $okstring );
                    if ( $foundinputinfile == 1 ) {
                        sleep 2;
                    }
                    else {
                        displayPrompt( $stpn, "noq" );
                    }
                }
            }
        }
    }
}

############################################################
#      sub: getsysadminCredentials
#     desc: Prompts for, and obtains the name and password
#           of the IBM Storage Protect system administrator
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getsysadminCredentials {
    $stpn = shift(@_);

    logentry(
"Step ${stpn}: Get the IBM Storage Protect system administrator credentials\n"
    );

    logentry( "Step ${stpn}_${substep}: Get the system administrator ID\n", 1 );

    do {
        displayStepNumAndDesc($stpn);

        $repeatflag = 0;

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("tsmsysadminid");
        }

        if ( $foundinputinfile == 1 ) {
            $sysadminid = $inputHash{tsmsysadminid};
        }
        else {
            displayString( 10, 3, $sysadminidString1 );
            displayString( 10, 3, $sysadminidString2 );

            $sysadminid = <STDIN>;

            chomp($sysadminid);

            if ( $sysadminid eq "" ) {
                $sysadminid = "admin";
            }
        }

        ( $rc, $msgstring ) = validateServerObjectName( $sysadminid, 64 );

        if ( $rc == 0 ) {
            if ( $foundinputinfile == 1 ) {
                displayString( 10, 3,
                    "IBM Storage Protect system administrator ID> $sysadminid"
                );
                sleep 2;
            }
        }
        else {
            $errorstring = genresultString(
                "IBM Storage Protect system administrator ID> $sysadminid",
                40, "[ERROR]", $msgstring );
            displayString( 10, 4, $errorstring, 1, $stpn );
            $repeatflag = displayPromptExtNoContinue( $stpn, 1, "noq" );
        }
    } while ( ( $doneflag == 0 ) && ( $repeatflag != 0 ) );

    if ( $doneflag == 0 ) {
        $stateHash{adminID} = "$sysadminid";

        logentry(
            "        User response: IBM Storage Protect system administrator id: $sysadminid\n"
        );

        logentry(
            "Step ${stpn}_${substep}: Get the system administrator password\n",
            1
        );

        do {
            $repeatflag = 0;

            $foundinputinfile = 0;

            if ( $takeinputfromfile == 1 ) {
                $foundinputinfile = getinputfromfile("tsmsysadminpw");
            }

            if ( $foundinputinfile == 1 ) {
                $sysadminpw = $inputHash{tsmsysadminpw};
                if ( validatePassword($sysadminpw) == 1 ) {
                    sleep 5;
                    $errorstring = genresultString(
                      "Invalid password specified.",
                      40, "[ERROR]", "tsmsysadminpw");
                    displayString( 10, 4, $errorstring, 1, $stpn );
                    $repeatstep = displayPromptNoContinue( $stpn, 1 );
                }
            }
            else {
                my $validPW = 0;
                while (! $validPW) {
                    displayString( 10, 3, $sysadminpwString1 );
                    displayString( 10, 3, $sysadminpwString2 );

                    $sysadminpw = <STDIN>;

                    chomp($sysadminpw);
                    if ( validatePassword($sysadminpw) == 0 ) {
                       $validPW = 1;
                    }

                }
            }

            # ( $rc, $msgstring ) = validateServerObjectName( $sysadminpw, 64 );

            if ( $foundinputinfile == 1 ) {
                displayString( 10, 3, "IBM Storage Protect system administrator password> ********");
                sleep 2;
            }

        } while ( ( $doneflag == 0 ) && ( $repeatflag != 0 ) );

        if ( $doneflag == 0 ) {
            $stateHash{adminPW} = "$sysadminpw";

            logentry(
"        User response: IBM Storage Protect system administrator password ********\n"
            );

            if ( $foundinputinfile == 0 ) {
                displayPrompt( $stpn, "noq" );
            }
        }
    }
}

############################################################
#      sub: getDbDirectories
#     desc: Prompts for, and obtains the db directories from
#           the user. These instance directories are then
#           checked to make sure they are all file system mount
#           points, and that together they have sufficient free space
#           and are empty. This is a repeatable step
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getDbDirectories {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the database directory paths\n");

    $db2usr        = $stateHash{db2user};
    $instdirmntpnt = $stateHash{instdirmountpoint};

    saveFreeSpace();

    do {
        displayStepNumAndDesc($stpn);

        $repeatstep           = 0;
        $takedefaults         = 0;
        $dbdirstotalfreespace = 0;
        my $refresheddbdirArrayRef = [];
        $stateHash{dbdirpaths} = $refresheddbdirArrayRef;

        $entrynum = 1;

        if ( isGPFS() == 1 ) {
            $expected_number_of_dirs = 1;
        }
        else {
            $expected_number_of_dirs = $stateHash{dbfscount};
        }

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("dbdirpaths");
        }

        if ( $foundinputinfile == 0 ) {
            displayString( 5, 3, $db2dbdirString2 );

            if ( ( isGPFS() == 1 ) || ( $skipmountFlag == 1 ) ) {
                $db2dbdirString3 =
"Or, provide at least $expected_number_of_dirs directories for the database directory paths";
            }
            else {
                $db2dbdirString3 =
"Or, provide at least $expected_number_of_dirs filesystems for the database directory paths";
            }

            $db2dbdirString4 = "Press enter on the last prompt to submit";

            if ( isGPFS() == 1 ) {
                displayList( \@defaultdbdirs_gpfs, 5, 1, 1 );
                displayString( 5, 3, $db2dbdirString3 );
                displayString( 5, 3, $db2dbdirString4 );
            }
            else {
                #New add for xsmall
                if ( $stateHash{serverscale} eq "xsmall" ) {
                    displayList( \@defaultdbdirs_xsmall, 5, 1, 1 );
                    displayString( 5, 3, $db2dbdirString3 );
                    displayString( 5, 3, $db2dbdirString4 );
                }
                elsif ( $stateHash{serverscale} eq "small" ) {
                    displayList( \@defaultdbdirs_small, 5, 1, 1 );
                    displayString( 5, 3, $db2dbdirString3 );
                    displayString( 5, 3, $db2dbdirString4 );
                }
                elsif ( $stateHash{serverscale} eq "medium" ) {
                    displayList( \@defaultdbdirs_medium, 5, 1, 1 );
                    displayString( 5, 3, $db2dbdirString3 );
                    displayString( 5, 3, $db2dbdirString4 );
                }
                elsif ( $stateHash{serverscale} eq "large" ) {
                    displayList( \@defaultdbdirs_large, 5, 1, 1 );
                    displayString( 5, 3, $db2dbdirString3 );
                    displayString( 5, 3, $db2dbdirString4 );
                }
            }
            displayCenteredPromptingString( 2, "${entrynum}> ", 2 );

            $dbdirpathArrayRef = $stateHash{dbdirpaths};

            $dbdirpth = <STDIN>;

            chomp($dbdirpth);

            if ( $dbdirpth eq "" ) {
                $takedefaults = 1;

                if ( isGPFS() == 1 ) {
                    $dbdirpth = $defaultdbdirs_gpfs[0];

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $dbdirpth = "$instdirmntpnt" . "$dbdirpth";
                    }
                }
                else {
                    #New add for xsmall
                    if ( $stateHash{serverscale} eq "xsmall" ) {
                        $dbdirpth = $defaultdbdirs_xsmall[0];
                    }
                    elsif ( $stateHash{serverscale} eq "small" ) {
                        $dbdirpth = $defaultdbdirs_small[0];
                    }
                    elsif ( $stateHash{serverscale} eq "medium" ) {
                        $dbdirpth = $defaultdbdirs_medium[0];
                    }
                    elsif ( $stateHash{serverscale} eq "large" ) {
                        $dbdirpth = $defaultdbdirs_large[0];
                    }
                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $dbdirpth = "${SS}${db2usr}" . "$dbdirpth";
                    }
                    elsif ( $platform eq "WIN32" ) {
                        $dbdirpth =
                          "${defaultserverdrive}${SS}${db2usr}" . "$dbdirpth";
                    }
                }
            }
        }
        else {
            $dbdirpathArrayRef = $stateHash{dbdirpaths};
            $dbdirpth          = $inputHash{dbdirpaths}->[0];
        }

        $p = 0;

        while (( $doneflag == 0 )
            && ( $dbdirpth ne "" )
            && ( $repeatstep == 0 ) )
        {
            do {
                $repeatflag = 0;

                if (   ( ( isGPFS() == 1 ) && ( isunderGPFS($dbdirpth) == 1 ) )
                    || ( $skipmountFlag == 1 ) )
                {
                    ( $rc, $msgstring ) = createsubdirsundermntpnt($dbdirpth);

                    if ( $rc == 0 ) {
                        ( $rc, $msgstring ) =
                          validateMountPoint( $dbdirpth, 1, 1 );
                    }
                }
                else {
                    ( $rc, $msgstring ) = validateMountPoint( $dbdirpth, 1 );
                }

                repaint( $p, $dbdirpathArrayRef, $stpn );
                if ( $rc == 0 ) {
                    $okstring =
                      genresultString( "${entrynum}> $dbdirpth", 40, "[OK]" );
                    displayString( 10, 1, $okstring );
                    $dbdirpathArrayRef->[$p] = $dbdirpth;
                    $entrynum++;
                    $p++;
                }
                else {
                    $errorstring = genresultString( "${entrynum}> $dbdirpth",
                        40, "[ERROR]", $msgstring );
                    displayString( 10, 1, $errorstring );
                    if ( ( $takedefaults == 0 ) && ( $foundinputinfile == 0 ) )
                    {
                        $repeatflag = displayPromptExtNoContinue($stpn);
                        repaint( $p, $dbdirpathArrayRef, $stpn );
                    }
                    else {
                        $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
                    }
                }

                if (   ( $doneflag == 0 )
                    && ( $takedefaults == 1 )
                    && ( $rc == 0 ) )
                {
                    if ( isGPFS() == 1 ) {
                        $dbdirpth = $defaultdbdirs_gpfs[$p];

                        if ( $dbdirpth ne "" ) {
                            if (   ( $platform eq "LINUX86" )
                                || ( $platform eq "AIX" )
                                || ( $platform =~ m/LINUXPPC/ ) )
                            {
                                $dbdirpth = "$instdirmntpnt" . "$dbdirpth";
                            }
                        }
                    }
                    else {
                        #New add for xsmall
                        if ( $stateHash{serverscale} eq "xsmall" ) {
                            $dbdirpth = $defaultdbdirs_xsmall[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "small" ) {
                            $dbdirpth = $defaultdbdirs_small[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "medium" ) {
                            $dbdirpth = $defaultdbdirs_medium[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "large" ) {
                            $dbdirpth = $defaultdbdirs_large[$p];
                        }
                        if ( $dbdirpth ne "" ) {
                            if (   ( $platform eq "LINUX86" )
                                || ( $platform eq "AIX" )
                                || ( $platform =~ m/LINUXPPC/ ) )
                            {
                                $dbdirpth = "${SS}${db2usr}" . "$dbdirpth";
                            }
                            elsif ( $platform eq "WIN32" ) {
                                $dbdirpth =
                                    "${defaultserverdrive}${SS}${db2usr}"
                                  . "$dbdirpth";
                            }
                        }
                    }
                }
                elsif (( $doneflag == 0 )
                    && ( $foundinputinfile == 1 )
                    && ( $rc == 0 ) )
                {
                    $dbdirpth = $inputHash{dbdirpaths}->[$p];
                }
                elsif (( $doneflag == 0 )
                    && ( ( $takedefaults == 1 ) || ( $foundinputinfile == 1 ) )
                  )
                {
                    $repeatflag = 0;
                    $repeatstep = 1;
                }
                elsif ( $doneflag == 0 ) {
                    displayString( 10, 1, "${entrynum}> " );
                    $dbdirpth = <STDIN>;
                    chomp($dbdirpth);
                }
            } while ( ( $doneflag == 0 )
                && ( $dbdirpth ne "" )
                && ( $repeatflag != 0 ) );
        }

        if ( ( $doneflag == 0 ) && ( $repeatstep == 0 ) ) {
            $userresponseList = "";

            $firstpath = 1;

            foreach $p ( @{$dbdirpathArrayRef} ) {
                if ( $firstpath == 1 ) {
                    $userresponseList = "$userresponseList" . "$p";
                    $firstpath        = 0;
                }
                else {
                    $userresponseList = "$userresponseList" . "," . "$p";
                }
            }

            logentry(
"        User response: database directories: $userresponseList\n"
            );

            $NumDirectoryErrorString =
              "There should be at least $expected_number_of_dirs directories";

            $InsufficentSpaceDbDirsErrorString =
              "There is insufficient space for the database directories";

            $validEntryString =
              "The following database directory paths were validated:";

            $numberofpaths = @{$dbdirpathArrayRef};

            if ( $numberofpaths >= $expected_number_of_dirs ) {
                if (
                    sufficientspaceexistsExt(
                        $dbdirpathArrayRef, $stateHash{dbdirsfreespacemin},
                        "",                 \$dbdirstotalfreespace
                    ) == 0
                  )
                {
                    logentry(
"        Total free space in the database directories is $dbdirstotalfreespace, expected is $stateHash{dbdirsfreespacemin}\n"
                    );
                    logentry(
"        The amount of free space for the database directories is not sufficient for $stateHash{serverscale} server\n"
                    );
                    displayString( 10, 2, $InsufficentSpaceDbDirsErrorString );
                    $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
                }
                else {
                    logentry(
"        The free space required for the database directories is $stateHash{dbdirsfreespacemin}"
                    );
                    logentry(
"        Total free space in the database directories is $dbdirstotalfreespace\n"
                    );
                    foreach $dbdirpth ( @{$dbdirpathArrayRef} ) {
                        $enclmntpnt = getencompassingmountpoint($dbdirpth);
                        logentry(
"        The amount of free space left in $enclmntpnt after taking into account the space for the database directories is $stateHash{freespacehash}->{$enclmntpnt}\n"
                        );
                    }

                    displayString( 10, 2, $validEntryString );
                    displayListNoPrefix( $dbdirpathArrayRef, 10, 1 );
                    if ( $foundinputinfile == 1 ) {
                        sleep 2;
                    }
                    else {
                        displayPrompt($stpn);
                    }
                }
            }
            else {
                logentry(
"        There should be at least $expected_number_of_dirs database directories specified\n"
                );
                displayString( 10, 3, $NumDirectoryErrorString );
                $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
            }
        }
    } while ( ( $doneflag == 0 ) && ( $repeatstep != 0 ) );
}

############################################################
#      sub: getDbactLog
#     desc: Prompts for, and obtains the database active log path
#           from the user. It is then checked to make sure
#           it is a file system mount point and has sufficient
#           free space, and is empty. This is a repeatable step
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getDbactLog {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the active log path\n");

    $db2usr        = $stateHash{db2user};
    $instdirmntpnt = $stateHash{instdirmountpoint};

    saveFreeSpace();

    do {
        displayStepNumAndDesc($stpn);

        $repeatflag = 0;

        $stateHash{actlogpath} = "";
        $dbactlogtotalfreespace = 0;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            if ( isGPFS() == 1 ) {
                $db2actlogString1 =
"Press enter to accept the default [${instdirmntpnt}${SS}database${SS}alog].";
            }
            else {
                $db2actlogString1 =
"Press enter to accept the default [${SS}${db2usr}${SS}TSMalog].";
            }
        }
        elsif ( $platform eq "WIN32" ) {
            $db2actlogString1 =
"Press enter to accept the default [${defaultserverdrive}${SS}${db2usr}${SS}TSMalog].";
        }

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("actlogpath");
        }

        if ( $foundinputinfile == 1 ) {
            $dbactlogpth = $inputHash{actlogpath};
        }
        else {
            displayString( 10, 3, $db2actlogString1 );
            displayString( 10, 3, $db2actlogString2 );

            $dbactlogpth = <STDIN>;

            chomp($dbactlogpth);

            if ( $dbactlogpth eq "" ) {
                if (   ( $platform eq "LINUX86" )
                    || ( $platform eq "AIX" )
                    || ( $platform =~ m/LINUXPPC/ ) )
                {
                    if ( isGPFS() == 1 ) {
                        $dbactlogpth = "${instdirmntpnt}${SS}database${SS}alog";
                    }
                    else {
                        $dbactlogpth = "${SS}${db2usr}${SS}TSMalog";
                    }
                }
                elsif ( $platform eq "WIN32" ) {
                    $dbactlogpth =
                      "${defaultserverdrive}${SS}${db2usr}${SS}TSMalog";
                }
            }
        }

        $InsufficentSpaceActLogErrorString =
          "There is insufficient space for the server active log directory";

        logentry("        User response: active log path: $dbactlogpth\n");

        if (   ( ( isGPFS() == 1 ) && ( isunderGPFS($dbactlogpth) == 1 ) )
            || ( $skipmountFlag == 1 ) )
        {
            ( $rc, $msgstring ) = createsubdirsundermntpnt($dbactlogpth);

            if ( $rc == 0 ) {
                ( $rc, $msgstring ) = validateMountPoint( $dbactlogpth, 1, 1 );
            }
        }
        else {
            ( $rc, $msgstring ) = validateMountPoint( $dbactlogpth, 1 );
        }

        if ( $rc == 0 ) {

            # check if total size is sufficient for this scale

            if (
                sufficientspaceexists(
                    $dbactlogpth,
                    $stateHash{dbactlogfreespacemin},
                    \$dbactlogtotalfreespace
                ) == 0
              )
            {
                logentry(
"        Free space in $dbactlogpth is $dbactlogtotalfreespace, expected is $stateHash{dbactlogfreespacemin}\n"
                );
                logentry(
"        The amount of free space for the server active log is not sufficient for $stateHash{serverscale} server\n"
                );
                displayString( 10, 2, $InsufficentSpaceActLogErrorString );
                $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
            }
            else {
                if ( $platform eq "WIN32" ) {
                    $stateHash{activelogfreespace} = $dbactlogtotalfreespace
                      ;    # for Windows we need this for later use
                }
                $enclmntpnt = getencompassingmountpoint($dbactlogpth);
                logentry(
"        The free space required for the active log is $stateHash{dbactlogfreespacemin}"
                );
                logentry(
"        Free space in $dbactlogpth is $dbactlogtotalfreespace\n"
                );
                logentry(
"        The amount of free space left in $enclmntpnt after taking into account the space for the active log is $stateHash{freespacehash}->{$enclmntpnt}\n"
                );

                $stateHash{actlogpath} = "$dbactlogpth";
                $okstring =
                  genresultString( "Active log directory> $dbactlogpth",
                    40, "[OK]" );
                displayString( 10, 3, $okstring, 1, $stpn );
                if ( $foundinputinfile == 1 ) {
                    sleep 2;
                }
                else {
                    displayPrompt($stpn);
                }
            }
        }
        else {
            $errorstring =
              genresultString( "Active log directory> $dbactlogpth",
                40, "[ERROR]", $msgstring );
            displayString( 10, 3, $errorstring, 1, $stpn );
            $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
        }
    } while ( $repeatflag != 0 );
}

############################################################
#      sub: getDbarchLog
#     desc: Prompts for, and obtains the database archive log path
#           from the user. It is then checked to make sure
#           it is a file system mount point and has sufficient
#           free space, and is empty. This is a repeatable step
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getDbarchLog {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the archive log path\n");

    $db2usr        = $stateHash{db2user};
    $instdirmntpnt = $stateHash{instdirmountpoint};

    saveFreeSpace();

    do {
        displayStepNumAndDesc($stpn);

        $repeatflag = 0;

        $stateHash{archlogpath} = "";
        $dbarchlogtotalfreespace = 0;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            if ( isGPFS() == 1 ) {
                $db2archlogString1 =
"Press enter to accept the default [${instdirmntpnt}${SS}database${SS}archlog].";
            }
            else {
                $db2archlogString1 =
"Press enter to accept the default [${SS}${db2usr}${SS}TSMarchlog].";
            }
        }
        elsif ( $platform eq "WIN32" ) {
            $db2archlogString1 =
"Press enter to accept the default [${defaultserverdrive}${SS}${db2usr}${SS}TSMarchlog].";
        }

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("archlogpath");
        }

        if ( $foundinputinfile == 1 ) {
            $dbarchlogpth = $inputHash{archlogpath};
        }
        else {
            displayString( 10, 3, $db2archlogString1 );
            displayString( 10, 3, $db2archlogString2 );

            $dbarchlogpth = <STDIN>;

            chomp($dbarchlogpth);

            if ( $dbarchlogpth eq "" ) {
                if (   ( $platform eq "LINUX86" )
                    || ( $platform eq "AIX" )
                    || ( $platform =~ m/LINUXPPC/ ) )
                {
                    if ( isGPFS() == 1 ) {
                        $dbarchlogpth =
                          "${instdirmntpnt}${SS}database${SS}archlog";
                    }
                    else {
                        $dbarchlogpth = "${SS}${db2usr}${SS}TSMarchlog";
                    }
                }
                elsif ( $platform eq "WIN32" ) {
                    $dbarchlogpth =
                      "${defaultserverdrive}${SS}${db2usr}${SS}TSMarchlog";
                }
            }
        }

        $InsufficentSpaceArchLogErrorString =
          "There is insufficient space for the server archive log directory";

        logentry("        User response: archive log path: $dbarchlogpth\n");

        if (   ( ( isGPFS() == 1 ) && ( isunderGPFS($dbarchlogpth) == 1 ) )
            || ( $skipmountFlag == 1 ) )
        {
            ( $rc, $msgstring ) = createsubdirsundermntpnt($dbarchlogpth);

            if ( $rc == 0 ) {
                ( $rc, $msgstring ) = validateMountPoint( $dbarchlogpth, 1, 1 );
            }
        }
        else {
            ( $rc, $msgstring ) = validateMountPoint( $dbarchlogpth, 1 );
        }

        if ( $rc == 0 ) {

            # check if total size is sufficient for this scale

            if (
                sufficientspaceexists(
                    $dbarchlogpth,
                    $stateHash{dbarchlogfreespacemin},
                    \$dbarchlogtotalfreespace
                ) == 0
              )
            {
                logentry(
"        Free space in $dbarchlogpth is $dbarchlogtotalfreespace, expected is $stateHash{dbarchlogfreespacemin}\n"
                );
                logentry(
"        The amount of free space for the server archive log is not sufficient for $stateHash{serverscale} server\n"
                );
                displayString( 10, 2, $InsufficentSpaceArchLogErrorString );
                $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
            }
            else {
                $enclmntpnt = getencompassingmountpoint($dbarchlogpth);
                logentry(
"        The free space required for the archive log is $stateHash{dbarchlogfreespacemin}"
                );
                logentry(
"        Free space in $dbarchlogpth is $dbarchlogtotalfreespace\n"
                );
                logentry(
"        The amount of free space left in $enclmntpnt after taking into account the space for the archive log is $stateHash{freespacehash}->{$enclmntpnt}\n"
                );

                $stateHash{archlogpath} = "$dbarchlogpth";
                $okstring =
                  genresultString( "Archive log directory> $dbarchlogpth",
                    40, "[OK]" );
                displayString( 10, 3, $okstring, 1, $stpn );
                if ( $foundinputinfile == 1 ) {
                    sleep 2;
                }
                else {
                    displayPrompt($stpn);
                }
            }
        }
        else {
            $errorstring =
              genresultString( "Archive log directory> $dbarchlogpth",
                40, "[ERROR]", $msgstring );
            displayString( 10, 3, $errorstring, 1, $stpn );
            $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
        }
    } while ( $repeatflag != 0 );
}

############################################################
#      sub: getTsmStoragePaths
#     desc: Prompts for, and obtains the directories that will be used
#           for IBM Storage Protect storage from the user. These directories are then
#           checked to make sure they are all file system mount points,
#           and that together they have sufficient free space and are empty.
#           This is a repeatable step
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getTsmStoragePaths {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the IBM Storage Protect storage paths\n");

    $db2usr        = $stateHash{db2user};
    $instdirmntpnt = $stateHash{instdirmountpoint};

    @stgmntpntsallocatedvolumesArray = ();

    saveFreeSpace();

    do {
        displayStepNumAndDesc($stpn);

        $repeatstep   = 0;
        $takedefaults = 0;

        $stgdirstotalfreespace = 0;

       # for the storage mountpoints, need to save the freespace values in array

        @stgmntpntsfreespaceArray = ();

        my $refreshedstgdirArrayRef = [];
        $stateHash{tsmstgpaths} = $refreshedstgdirArrayRef;
        my $refreshedpreAllocationarrayRef = [];
        $stateHash{numpreallocvols} = $refreshedpreAllocationarrayRef;

        $entrynum = 1;

        if ( isGPFS() == 1 ) {
            $expected_number_of_dirs = 1;
        }
        else {
            $expected_number_of_dirs = $stateHash{stgfscount};
        }

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("tsmstgpaths");
        }

        if ( $foundinputinfile == 0 ) {
            displayString( 5, 3, $tsmStgString2 );

            if ( ( isGPFS() == 1 ) || ( $skipmountFlag == 1 ) ) {
                $tsmStgString3 =
"Or, provide at least $expected_number_of_dirs directories for the storage directories";
            }
            else {
                $tsmStgString3 =
"Or, provide at least $expected_number_of_dirs filesystems for the storage directories";
            }

            $tsmStgString4 = "Press enter on the last prompt to submit";

            if ( isGPFS() == 1 ) {
                displayList( \@defaultstgdirs_gpfs, 5, 1, 1 );
                displayString( 5, 3, $tsmStgString3 );
                displayString( 5, 3, $tsmStgString4 );
            }
            else {
                #New add for xsmall
                if ( $stateHash{serverscale} eq "xsmall" ) {
                    displayList( \@defaultstgdirs_xsmall, 5, 1, 1 );
                    displayString( 5, 3, $tsmStgString3 );
                    displayString( 5, 3, $tsmStgString4 );
                }
                elsif ( $stateHash{serverscale} eq "small" ) {
                    displayList( \@defaultstgdirs_small, 5, 1, 1 );
                    displayString( 5, 3, $tsmStgString3 );
                    displayString( 5, 3, $tsmStgString4 );
                }
                elsif ( $stateHash{serverscale} eq "medium" ) {
                    displayList( \@defaultstgdirs_medium, 5, 1, 1 );
                    displayString( 5, 3, $tsmStgString3 );
                    displayString( 5, 3, $tsmStgString4 );
                }
                elsif ( $stateHash{serverscale} eq "large" ) {
                    displayList( \@defaultstgdirs_large, 5, 1, 1 );
                    displayString( 5, 3, $tsmStgString3 );
                    displayString( 5, 3, $tsmStgString4 );
                }
            }
            displayCenteredPromptingString( 2, "${entrynum}> ", 2 );

            $tsmstgpathArrayRef = $stateHash{tsmstgpaths};

            $tsmstgpth = <STDIN>;

            chomp($tsmstgpth);

            if ( $tsmstgpth eq "" ) {
                $takedefaults = 1;

                if ( isGPFS() == 1 ) {
                    $tsmstgpth = $defaultstgdirs_gpfs[0];

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $tsmstgpth = "$instdirmntpnt" . "$tsmstgpth";
                    }
                }
                else {
                    #New add for xsmall
                    if ( $stateHash{serverscale} eq "xsmall" ) {
                        $tsmstgpth = $defaultstgdirs_xsmall[0];
                    }
                    elsif ( $stateHash{serverscale} eq "small" ) {
                        $tsmstgpth = $defaultstgdirs_small[0];
                    }
                    elsif ( $stateHash{serverscale} eq "medium" ) {
                        $tsmstgpth = $defaultstgdirs_medium[0];
                    }
                    elsif ( $stateHash{serverscale} eq "large" ) {
                        $tsmstgpth = $defaultstgdirs_large[0];
                    }
                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $tsmstgpth = "${SS}${db2usr}" . "$tsmstgpth";
                    }
                    elsif ( $platform eq "WIN32" ) {
                        $tsmstgpth =
                          "${defaultserverdrive}${SS}${db2usr}" . "$tsmstgpth";
                    }
                }
            }
        }
        else {
            $tsmstgpathArrayRef = $stateHash{tsmstgpaths};
            $tsmstgpth          = $inputHash{tsmstgpaths}->[0];
        }

        $p = 0;

        while (( $doneflag == 0 )
            && ( $tsmstgpth ne "" )
            && ( $repeatstep == 0 ) )
        {
            do {
                $repeatflag = 0;

                if (   ( ( isGPFS() == 1 ) && ( isunderGPFS($tsmstgpth) == 1 ) )
                    || ( $skipmountFlag == 1 ) )
                {
                    ( $rc, $msgstring ) = createsubdirsundermntpnt($tsmstgpth);

                    if ( $rc == 0 ) {
                        ( $rc, $msgstring ) =
                          validateMountPoint( $tsmstgpth, 1, 1 );
                    }
                }
                else {
                    ( $rc, $msgstring ) = validateMountPoint( $tsmstgpth, 1 );
                }

                repaint( $p, $tsmstgpathArrayRef, $stpn );
                if ( $rc == 0 ) {
                    $okstring =
                      genresultString( "${entrynum}> $tsmstgpth", 40, "[OK]" );
                    displayString( 10, 1, $okstring );
                    $tsmstgpathArrayRef->[$p] = $tsmstgpth;
                    $entrynum++;
                    $p++;
                }
                else {
                    $errorstring = genresultString( "${entrynum}> $tsmstgpth",
                        40, "[ERROR]", $msgstring );
                    displayString( 10, 1, $errorstring );
                    if ( ( $takedefaults == 0 ) && ( $foundinputinfile == 0 ) )
                    {
                        $repeatflag = displayPromptExtNoContinue($stpn);
                        repaint( $p, $tsmstgpathArrayRef, $stpn );
                    }
                    else {
                        $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
                    }
                }

                if (   ( $doneflag == 0 )
                    && ( $takedefaults == 1 )
                    && ( $rc == 0 ) )
                {
                    if ( isGPFS() == 1 ) {
                        $tsmstgpth = $defaultstgdirs_gpfs[$p];

                        if ( $tsmstgpth ne "" ) {
                            if (   ( $platform eq "LINUX86" )
                                || ( $platform eq "AIX" )
                                || ( $platform =~ m/LINUXPPC/ ) )
                            {
                                $tsmstgpth = "$instdirmntpnt" . "$tsmstgpth";
                            }
                        }
                    }
                    else {
                        #New add for xsmall
                        if ( $stateHash{serverscale} eq "xsmall" ) {
                            $tsmstgpth = $defaultstgdirs_xsmall[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "small" ) {
                            $tsmstgpth = $defaultstgdirs_small[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "medium" ) {
                            $tsmstgpth = $defaultstgdirs_medium[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "large" ) {
                            $tsmstgpth = $defaultstgdirs_large[$p];
                        }
                        if ( $tsmstgpth ne "" ) {
                            if (   ( $platform eq "LINUX86" )
                                || ( $platform eq "AIX" )
                                || ( $platform =~ m/LINUXPPC/ ) )
                            {
                                $tsmstgpth = "${SS}${db2usr}" . "$tsmstgpth";
                            }
                            elsif ( $platform eq "WIN32" ) {
                                $tsmstgpth =
                                    "${defaultserverdrive}${SS}${db2usr}"
                                  . "$tsmstgpth";
                            }
                        }
                    }
                }
                elsif (( $doneflag == 0 )
                    && ( $foundinputinfile == 1 )
                    && ( $rc == 0 ) )
                {
                    $tsmstgpth = $inputHash{tsmstgpaths}->[$p];
                }
                elsif (( $doneflag == 0 )
                    && ( ( $takedefaults == 1 ) || ( $foundinputinfile == 1 ) )
                  )
                {
                    $repeatflag = 0;
                    $repeatstep = 1;
                }
                elsif ( $doneflag == 0 ) {
                    displayString( 10, 1, "${entrynum}> " );
                    $tsmstgpth = <STDIN>;
                    chomp($tsmstgpth);
                }
            } while ( ( $doneflag == 0 )
                && ( $tsmstgpth ne "" )
                && ( $repeatflag != 0 ) );
        }

        if ( ( $doneflag == 0 ) && ( $repeatstep == 0 ) ) {
            $userresponseList = "";

            $firstpath = 1;

            foreach $p ( @{$tsmstgpathArrayRef} ) {
                if ( $firstpath == 1 ) {
                    $userresponseList = "$userresponseList" . "$p";
                    $firstpath        = 0;
                }
                else {
                    $userresponseList = "$userresponseList" . "," . "$p";
                }
            }

            logentry(
"        User response: IBM Storage Protect storage directories: $userresponseList\n"
            );

            $NumDirectoryErrorString =
              "There should be at least $expected_number_of_dirs directories";

            $InsufficentSpaceStgDirsErrorString =
              "There is insufficient space for the storage directories";

            $validEntryString =
              "The following storage directory paths were validated:";

            $numberofpaths = @{$tsmstgpathArrayRef};

            $preAllocationarrayRef = $stateHash{numpreallocvols};

            if ( $numberofpaths >= $expected_number_of_dirs ) {

                # check if total size is sufficient for this scale

                if (
                    sufficientspaceexistsExt(
                        $tsmstgpathArrayRef,
                        $stateHash{stgdirsfreespacemin},
                        \@stgmntpntsfreespaceArray,
                        \$stgdirstotalfreespace
                    ) == 0
                  )
                {
                    logentry(
"        Total free space in the IBM Storage Protect storage directories is $stgdirstotalfreespace, expected is $stateHash{stgdirsfreespacemin}\n"
                    );
                    logentry(
"        The amount of free space for the IBM Storage Protect storage directories is not sufficient for $stateHash{serverscale} server\n"
                    );
                    displayString( 10, 2, $InsufficentSpaceStgDirsErrorString );
                    $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
                }
                else {
                    $enclmntpnt = getencompassingmountpoint($instdirmountpoint);
                    logentry(
"        The free space required for the IBM Storage Protect storage directories is $stateHash{stgdirsfreespacemin}"
                    );
                    logentry(
"        Total free space in the IBM Storage Protect storage directories is $stgdirstotalfreespace\n"
                    );
                    foreach $stgdirpth ( @{$tsmstgpathArrayRef} ) {
                        $enclmntpnt = getencompassingmountpoint($stgdirpth);
                        logentry(
"        The amount of free space left in $enclmntpnt after taking into account the space for the storage directories is $stateHash{freespacehash}->{$enclmntpnt}\n"
                        );
                    }

                    $maxscratch = 0;
                    $maxcap     = $stateHash{maxcap};

                    $maxcap_without_unit =
                      substr( $maxcap, 0, length($maxcap) - 1 );

                    $totalPreallocatedVolumes = 0;

                    foreach $mptinfo (@stgmntpntsfreespaceArray) {
                        $mpt     = $mptinfo->{mountpoint};
                        $fspcval = $mptinfo->{freespace};

                        $fspcinGB = int( $fspcval / ( 1024 * 1024 ) )
                          ;    # convert from KB to GB

                        if ( $fspcinGB >= 1
                          ) # can have at least one volume under this mountpoint
                        {
                            $maxnumberofpreallocvolumesundermpt =
                              int( ( $fspcinGB - 1 ) / $maxcap_without_unit )
                              ; # maximum possible number of preallocated volumes under this mount point

                            logentry(
"        The maximum number of storage volumes possible under $mpt is $maxnumberofpreallocvolumesundermpt\n"
                            );
                            $maxscratch += $maxnumberofpreallocvolumesundermpt;

                            $numberofpreallocvolumesundermpt = int(
                                (
                                    $maxnumberofpreallocvolumesundermpt *
                                      $preallocpct
                                ) / 100
                              )
                              ; # number of preallocated volumes under this mount point

                            my $mpti = {};
                            $mpti->{mountpoint} = $mpt;
                            $mpti->{numvols} = $numberofpreallocvolumesundermpt;
                            $mpti->{maxnumvols} =
                              $maxnumberofpreallocvolumesundermpt;
                            push( @stgmntpntsallocatedvolumesArray, $mpti );

                            $totalPreallocatedVolumes +=
                              $numberofpreallocvolumesundermpt
                              ; # total number of pre-allocated volumes to be created (so far)
                        }
                        else {
                            my $mpti = {};
                            $mpti->{mountpoint} = $mpt;
                            $mpti->{numvols}    = 0;
                            $mpti->{maxnumvols} = 0;
                            push( @stgmntpntsallocatedvolumesArray, $mpti );
                        }
                    }

                    # take care of roundoff error (as far as possible)

                    $requestedNumberPreallocatedVolumes =
                      int( ( $maxscratch * $preallocpct ) / 100 );

                    logentry(
"        The maxscratch is initially computed to be $maxscratch\n"
                    );
                    logentry(
"        The requested number of pre-allocated volumes is $requestedNumberPreallocatedVolumes\n"
                    );

                    $additionalPreallocatedVolumesNeeded =
                      $requestedNumberPreallocatedVolumes -
                      $totalPreallocatedVolumes;

                    $additionalvolumeslefttoadd =
                      $additionalPreallocatedVolumesNeeded;

                    do {
                        $stillspacetoaddvolumes = 0;

                        foreach $mptinfo (@stgmntpntsallocatedvolumesArray) {
                            if (
                                ( $additionalvolumeslefttoadd > 0 )
                                && ( $mptinfo->{maxnumvols} >
                                    $mptinfo->{numvols} )
                              )
                            {
                                $mptinfo->{numvols} += 1;
                                $totalPreallocatedVolumes += 1;
                                $stillspacetoaddvolumes = 1;
                                $additionalvolumeslefttoadd--;
                            }
                        }
                    } while ( ( $stillspacetoaddvolumes == 1 )
                        && ( $additionalvolumeslefttoadd > 0 ) );

# distribute the volumes as evenly as possible among the storage directories under a given mountpoint $mpt
# (usually there will be just one directory for each storage mount point)

                    foreach $mptinfo (@stgmntpntsallocatedvolumesArray) {
                        $dircnt         = 0;
                        $mpt            = $mptinfo->{mountpoint};
                        $numvolundermpt = $mptinfo->{numvols};

                        foreach $stgp ( @{$tsmstgpathArrayRef} ) {
                            $enclosingmpt = getencompassingmountpoint($stgp);

                            if ( $enclosingmpt eq "$mpt" ) {
                                $dircnt++;
                            }
                        }

                        if ( $dircnt > 0 ) {

# compute the number of volumes in each dir under the mountpoint $mpt, so that they are balanced among the dirs under this $mpt (and then take care of roundoff error)

                            $numbervolumesperpath =
                              int( $numvolundermpt / $dircnt );
                            $extravolumes = $numvolundermpt -
                              ( $dircnt * $numbervolumesperpath )
                              ; # this value must be less than $dircnt (in particular, if $dircnt is 1, as in the usual case, then this is 0;
                                # it is positive if $dircnt does not evenly divide $numvolundermpt)
                            foreach $stgp ( @{$tsmstgpathArrayRef} ) {
                                $enclosingmpt =
                                  getencompassingmountpoint($stgp);

                                if ( $enclosingmpt eq "$mpt" ) {
                                    my $stginfo = {};
                                    $stginfo->{stgdir}  = $stgp;
                                    $stginfo->{numvols} = $numbervolumesperpath;
                                    push( @{$preAllocationarrayRef}, $stginfo );

                                    if ( $extravolumes > 0 ) {
                                        $stginfo->{numvols} += 1;
                                        $extravolumes--;
                                    }
                                }
                            }
                        }
                    }

                    $maxscratch -= $totalPreallocatedVolumes
                      ; # reduce the maxscratch by the number of volumes that will be preallocated

                    $stateHash{computedScratch} = $maxscratch;
                    $stateHash{totalpreallocatedvolumes} =
                      $totalPreallocatedVolumes;

                    logentry(
"        The maximum number of scratch volumes is $maxscratch\n"
                    );    # after taking into account the pre-allocated volumes
                    logentry(
"        The number of preallocated volumes is $totalPreallocatedVolumes\n"
                    );

                    if ( $totalPreallocatedVolumes > 0 ) {
                        foreach $stginfo ( @{$preAllocationarrayRef} ) {
                            $stgp                   = $stginfo->{stgdir};
                            $numberpreallocatedvols = $stginfo->{numvols};

                            logentry(
"        $numberpreallocatedvols pre-allocated storage volumes will be created under $stgp\n"
                            );
                        }
                    }

                    displayString( 10, 2, $validEntryString );
                    displayListNoPrefix( $tsmstgpathArrayRef, 10, 1 );

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $chnpthrc = chownPaths($stpn);
                    }
                    if ( ( $chnpthrc == 0 ) || ( $platform eq "WIN32" ) ) {
                        if ( $foundinputinfile == 1 ) {
                            sleep 2;
                        }
                        else {
                            displayPrompt($stpn);
                        }
                    }
                    else {
                        displayPromptNoContinue($stpn);
                    }
                }
            }
            else {
                logentry(
"        There should be at least $expected_number_of_dirs storage directories specified\n"
                );
                displayString( 10, 3, $NumDirectoryErrorString );
                $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
            }
        }
    } while ( ( $doneflag == 0 ) && ( $repeatstep != 0 ) );
}

############################################################
#      sub: getDBbackupDirectory
#     desc: Prompts for, and obtains the directories used for database
#           backups from the user. These directories are then checked
#           to make sure they are file system mount points, and
#           that together they have sufficient free space. This
#           is a repeatable step
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getDbBackupDirectories {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the database backup directory paths\n");

    $db2usr        = $stateHash{db2user};
    $instdirmntpnt = $stateHash{instdirmountpoint};

    saveFreeSpace();

    do {
        displayStepNumAndDesc($stpn);

        $repeatstep   = 0;
        $takedefaults = 0;

        $dbbackdirstotalfreespace = 0;

        my $refreshedbackupdirArrayRef = [];
        $stateHash{dbbackdirpaths} = $refreshedbackupdirArrayRef;

        $entrynum = 1;

        if ( isGPFS() == 1 ) {
            $expected_number_of_dirs = 1;
        }
        else {
            $expected_number_of_dirs = $stateHash{dbbackfscount};
        }

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("dbbackdirpaths");
        }

        if ( $foundinputinfile == 0 ) {
            displayString( 5, 3, $db2dbbackString2 );

            if ( ( isGPFS() == 1 ) || ( $skipmountFlag == 1 ) ) {
                $db2dbbackString3 =
"Or, provide at least $expected_number_of_dirs directories for the database backup directories";
            }
            else {
                $db2dbbackString3 =
"Or, provide at least $expected_number_of_dirs filesystems for the database backup directories";
            }

            $db2dbbackString4 = "Press enter on the last prompt to submit";

            if ( isGPFS() == 1 ) {
                displayList( \@defaultdbbkupdirs_gpfs, 5, 1, 1 );
                displayString( 5, 3, $db2dbbackString3 );
                displayString( 5, 3, $db2dbbackString4 );
            }
            else {
                #New add for xsmall
                if ( $stateHash{serverscale} eq "xsmall" ) {
                    displayList( \@defaultdbbkupdirs_xsmall, 5, 1, 1 );
                    displayString( 5, 3, $db2dbbackString3 );
                    displayString( 5, 3, $db2dbbackString4 );
                }
                elsif ( $stateHash{serverscale} eq "small" ) {
                    displayList( \@defaultdbbkupdirs_small, 5, 1, 1 );
                    displayString( 5, 3, $db2dbbackString3 );
                    displayString( 5, 3, $db2dbbackString4 );
                }
                elsif ( $stateHash{serverscale} eq "medium" ) {
                    displayList( \@defaultdbbkupdirs_medium, 5, 1, 1 );
                    displayString( 5, 3, $db2dbbackString3 );
                    displayString( 5, 1, $db2dbbackString4 );
                }
                elsif ( $stateHash{serverscale} eq "large" ) {
                    displayList( \@defaultdbbkupdirs_large, 5, 1, 1 );
                    displayString( 5, 3, $db2dbbackString3 );
                    displayString( 5, 3, $db2dbbackString4 );
                }
            }
            displayCenteredPromptingString( 2, "${entrynum}> ", 2 );

            $dbbackdirpathArrayRef = $stateHash{dbbackdirpaths};

            $dbbackdirpth = <STDIN>;

            chomp($dbbackdirpth);

            if ( $dbbackdirpth eq "" ) {
                $takedefaults = 1;

                if ( isGPFS() == 1 ) {
                    $dbbackdirpth = $defaultdbbkupdirs_gpfs[0];

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $dbbackdirpth = "$instdirmntpnt" . "$dbbackdirpth";
                    }
                }
                else {
                    #New add for xsmall
                    if ( $stateHash{serverscale} eq "xsmall" ) {
                        $dbbackdirpth = $defaultdbbkupdirs_xsmall[0];
                    }
                    elsif ( $stateHash{serverscale} eq "small" ) {
                        $dbbackdirpth = $defaultdbbkupdirs_small[0];
                    }
                    elsif ( $stateHash{serverscale} eq "medium" ) {
                        $dbbackdirpth = $defaultdbbkupdirs_medium[0];
                    }
                    elsif ( $stateHash{serverscale} eq "large" ) {
                        $dbbackdirpth = $defaultdbbkupdirs_large[0];
                    }
                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $dbbackdirpth = "${SS}${db2usr}" . "$dbbackdirpth";
                    }
                    elsif ( $platform eq "WIN32" ) {
                        $dbbackdirpth = "${defaultserverdrive}${SS}${db2usr}"
                          . "$dbbackdirpth";
                    }
                }
            }
        }
        else {
            $dbbackdirpathArrayRef = $stateHash{dbbackdirpaths};
            $dbbackdirpth          = $inputHash{dbbackdirpaths}->[0];
        }

        $p = 0;

        while (( $doneflag == 0 )
            && ( $dbbackdirpth ne "" )
            && ( $repeatstep == 0 ) )
        {
            do {
                $repeatflag = 0;

                if (
                    (
                        ( isGPFS() == 1 ) && ( isunderGPFS($dbbackdirpth) == 1 )
                    )
                    || ( $skipmountFlag == 1 )
                  )
                {
                    ( $rc, $msgstring ) =
                      createsubdirsundermntpnt($dbbackdirpth);

                    if ( $rc == 0 ) {
                        ( $rc, $msgstring ) =
                          validateMountPoint( $dbbackdirpth, 1, 1 );
                    }
                }
                else {
                    ( $rc, $msgstring ) =
                      validateMountPoint( $dbbackdirpth, 1 );
                }

                repaint( $p, $dbbackdirpathArrayRef, $stpn );
                if ( $rc == 0 ) {
                    $okstring = genresultString( "${entrynum}> $dbbackdirpth",
                        40, "[OK]" );
                    displayString( 10, 1, $okstring );
                    $dbbackdirpathArrayRef->[$p] = $dbbackdirpth;
                    $entrynum++;
                    $p++;
                }
                else {
                    $errorstring =
                      genresultString( "${entrynum}> $dbbackdirpth",
                        40, "[ERROR]", $msgstring );
                    displayString( 10, 1, $errorstring );
                    if ( ( $takedefaults == 0 ) && ( $foundinputinfile == 0 ) )
                    {
                        $repeatflag = displayPromptExtNoContinue($stpn);
                        repaint( $p, $dbbackdirpathArrayRef, $stpn );
                    }
                    else {
                        $repeatflag = displayPromptExtNoContinue( $stpn, 1 );
                    }
                }

                if (   ( $doneflag == 0 )
                    && ( $takedefaults == 1 )
                    && ( $rc == 0 ) )
                {
                    if ( isGPFS() == 1 ) {
                        $dbbackdirpth = $defaultdbbkupdirs_gpfs[$p];

                        if ( $dbbackdirpth ne "" ) {
                            if (   ( $platform eq "LINUX86" )
                                || ( $platform eq "AIX" )
                                || ( $platform =~ m/LINUXPPC/ ) )
                            {
                                $dbbackdirpth =
                                  "$instdirmntpnt" . "$dbbackdirpth";
                            }
                        }
                    }
                    else {
                        #New add for xsmall
                        if ( $stateHash{serverscale} eq "xsmall" ) {
                            $dbbackdirpth = $defaultdbbkupdirs_xsmall[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "small" ) {
                            $dbbackdirpth = $defaultdbbkupdirs_small[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "medium" ) {
                            $dbbackdirpth = $defaultdbbkupdirs_medium[$p];
                        }
                        elsif ( $stateHash{serverscale} eq "large" ) {
                            $dbbackdirpth = $defaultdbbkupdirs_large[$p];
                        }
                        if ( $dbbackdirpth ne "" ) {
                            if (   ( $platform eq "LINUX86" )
                                || ( $platform eq "AIX" )
                                || ( $platform =~ m/LINUXPPC/ ) )
                            {
                                $dbbackdirpth =
                                  "${SS}${db2usr}" . "$dbbackdirpth";
                            }
                            elsif ( $platform eq "WIN32" ) {
                                $dbbackdirpth =
                                    "${defaultserverdrive}${SS}${db2usr}"
                                  . "$dbbackdirpth";
                            }
                        }
                    }
                }
                elsif (( $doneflag == 0 )
                    && ( $foundinputinfile == 1 )
                    && ( $rc == 0 ) )
                {
                    $dbbackdirpth = $inputHash{dbbackdirpaths}->[$p];
                }
                elsif (( $doneflag == 0 )
                    && ( ( $takedefaults == 1 ) || ( $foundinputinfile == 1 ) )
                  )
                {
                    $repeatflag = 0;
                    $repeatstep = 1;
                }
                elsif ( $doneflag == 0 ) {
                    displayString( 10, 1, "${entrynum}> " );
                    $dbbackdirpth = <STDIN>;
                    chomp($dbbackdirpth);
                }
            } while ( ( $doneflag == 0 )
                && ( $dbbackdirpth ne "" )
                && ( $repeatflag != 0 ) );
        }

        if ( ( $doneflag == 0 ) && ( $repeatstep == 0 ) ) {
            $userresponseList = "";

            $firstpath = 1;

            foreach $p ( @{$dbbackdirpathArrayRef} ) {
                if ( $firstpath == 1 ) {
                    $userresponseList = "$userresponseList" . "$p";
                    $firstpath        = 0;
                }
                else {
                    $userresponseList = "$userresponseList" . "," . "$p";
                }
            }

            logentry(
"        User response: database backup directories: $userresponseList\n"
            );

            $NumDirectoryErrorString =
              "There should be at least $expected_number_of_dirs directories";

            $InsufficentSpaceDbBackDirsErrorString =
              "There is insufficient space for the database backup directories";

            $validEntryString =
              "The following database backup directory paths were validated:";

            $numberofpaths = @{$dbbackdirpathArrayRef};

            if ( $numberofpaths >= $expected_number_of_dirs ) {

                # check if total size is sufficient for this scale

                if (
                    sufficientspaceexistsExt(
                        $dbbackdirpathArrayRef,
                        $stateHash{dbbackupdirsfreespacemin},
                        "",
                        \$dbbackdirstotalfreespace
                    ) == 0
                  )
                {
                    logentry(
"        Total free space in the database backup directories is $dbbackdirstotalfreespace, expected is $stateHash{dbbackupdirsfreespacemin}\n"
                    );
                    logentry(
"        The amount of free space for the database backup directories is not sufficient for $stateHash{serverscale} server\n"
                    );
                    displayString( 10, 2,
                        $InsufficentSpaceDbBackDirsErrorString );
                    $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
                }
                else {
                    $enclmntpnt = getencompassingmountpoint($instdirmountpoint);
                    logentry(
"        The free space required for the database backup directories is $stateHash{dbbackupdirsfreespacemin}"
                    );
                    logentry(
"        Total free space in the database backup directories is $dbbackdirstotalfreespace\n"
                    );
                    foreach $dbbackdirpth ( @{$dbbackdirpathArrayRef} ) {
                        $enclmntpnt = getencompassingmountpoint($dbbackdirpth);
                        logentry(
"        The amount of free space left in $enclmntpnt after taking into account the space for the database backup directories is $stateHash{freespacehash}->{$enclmntpnt}\n"
                        );
                    }

                    displayString( 10, 2, $validEntryString );
                    displayListNoPrefix( $dbbackdirpathArrayRef, 10, 1 );
                    displayString( 0, 2, "" );

                    if ( $foundinputinfile == 1 ) {
                        sleep 2;
                    }
                    else {
                        displayPrompt($stpn);
                    }
                }
            }
            else {
                logentry(
"        There should be at least $expected_number_of_dirs database backup directories specified\n"
                );
                displayString( 10, 3, $NumDirectoryErrorString );
                $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
            }
        }
    } while ( ( $doneflag == 0 ) && ( $repeatstep != 0 ) );
}

############################################################
#      sub: getDbUserandGroup
#     desc: Prompts for, and obtains the user account name and
#           password (and the primary group of that user account)
#           which will own the DB2 instance. If necessary, the group
#           and user account are created. This is a repeatable step
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getDbUserandGroup {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the DB2 instance owner password and group\n");

    logentry( "Step ${stpn}_${substep}: Get the DB2 instance owner\n", 1 );

    do {
        displayStepNumAndDesc($stpn);

        $repeatstep = 0;

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("db2user");
        }

        if ( $foundinputinfile == 1 ) {
            $db2user = $inputHash{db2user};
        }
        else {
            displayString( 10, 3, $db2UserString1 );
            displayString( 10, 1, $db2UserString2 );

            $db2user = <STDIN>;

            chomp($db2user);

            if ( $db2user eq "" ) {
                $db2user = "tsminst1";
            }
        }

        logentry("        User response: DB2 instance owner: $db2user\n");

        ( $rc, $useralreadyexists, $db2userinfo, $msgstring ) =
          validatedb2username($db2user);

        if ( $rc != 0 ) {
            $errorstring = genresultString( "Server Instance Owner> $db2user",
                40, "[ERROR]", $msgstring );
            displayString( 10, 4, $errorstring, 1, $stpn );
            $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
        }

        if ( ( $doneflag == 0 ) && ( $repeatstep == 0 ) ) {

            if ( $useralreadyexists == 1 ) {
                logentry("        DB2 instance owner $db2user exists\n");
            }
            else {
                logentry(
                    "        DB2 instance owner $db2user does not exist\n");
            }

            logentry(
                "Step ${stpn}_${substep}: Get the DB2 instance owner password\n",
                1
            );

            $foundinputinfile = 0;

            if ( $takeinputfromfile == 1 ) {
                $foundinputinfile = getinputfromfile("db2userpw");
            }

            if ( $foundinputinfile == 1 ) {
                $db2userpw = $inputHash{db2userpw};
                if ( validatePassword($db2userpw) == 1 ) {
                    sleep 5;
                    $errorstring = genresultString(
                      "Invalid password specified.",
                      40, "[ERROR]", "db2userpw");
                    displayString( 10, 4, $errorstring, 1, $stpn );
                    $repeatstep = displayPromptNoContinue( $stpn, 1 );
                }
            }
            else {     # prompt for the password
                my $validPW = 0;
                while (! $validPW) {
                    if ( $useralreadyexists == 0 ) {
                        displayString( 10, 3, $db2UserPwString1 );
                        displayString( 10, 1, $db2UserPwString2 );
                    }
                    else {
                        displayString( 10, 3, $db2UserPwString2_preexistinguser );
                    }

                    $db2userpw = <STDIN>;

                    chomp($db2userpw);

                    if ( validatePassword($db2userpw) == 0 ) {
                       $validPW = 1;
                    }
                }
            }  # end prompted password input

            logentry(
                "        User response: DB2 instance owner password: ********\n"
            );

            if ( $useralreadyexists == 0
              ) # only ask for the home directory if the user does not already exist
            {

                if (   ( $platform eq "LINUX86" )
                    || ( $platform eq "AIX" )
                    || ( $platform =~ m/LINUXPPC/ ) )
                {
                    logentry(
"Step ${stpn}_${substep}: Get the DB2 instance owner home directory\n",
                        1
                    );

                    $foundinputinfile = 0;

                    if ( $takeinputfromfile == 1 ) {
                        $foundinputinfile = getinputfromfile("db2userhomedir");
                    }

                    if ( $foundinputinfile == 1 ) {
                        $db2userhomedir = $inputHash{db2userhomedir};
                    }
                    elsif ( $takeinputfromfile == 1
                      ) # if a response file is being used, and the DB2 home directory is not specified
                    { # in the response file (e.g., a legacy response file is in use) the DB2 home directory should
                        $db2userhomedir = "/home/${db2user}"
                          ; # default to /home/<DB2 user name> so that the user will not be (unexpectedly perhaps) prompted
                    }
                    else {
                        displayString( 10, 3,
"Press enter to accept the default home directory [/home/${db2user}]"
                        );
                        displayString( 10, 1, $db2UserHomeDirString2 );

                        $db2userhomedir = <STDIN>;

                        chomp($db2userhomedir);

                        if ( $db2userhomedir eq "" ) {
                            $db2userhomedir = "/home/${db2user}";
                        }
                    }

                    logentry(
"        User response: DB2 instance owner home directory: $db2userhomedir\n"
                    );

                    if ( -d $db2userhomedir ) {
                        logentry(
"        The home directory $db2userhomedir of $db2usr already exists\n"
                        );
                        $errorstring = genresultString(
"Server Instance Owner home directory> $db2userhomedir",
                            50, "[ERROR]", "directory exists"
                        );
                        displayString( 10, 4, $errorstring, 1, $stpn );
                        $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
                    }
                }
                elsif ( $platform eq "WIN32" ) {
                    $db2userhomedir = "";
                }

                if ( ( $doneflag == 0 ) && ( $repeatstep == 0 ) ) {

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        logentry(
                            "Step ${stpn}_${substep}: Get the DB2 group\n", 1 );

                        $foundinputinfile = 0;

                        if ( $takeinputfromfile == 1 ) {
                            $foundinputinfile = getinputfromfile("db2group");
                        }

                        if ( $foundinputinfile == 1 ) {
                            $db2group = $inputHash{db2group};
                        }
                        else {
                            displayString( 10, 3, $db2GroupString1 );
                            displayString( 10, 1, $db2GroupString2 );

                            $db2group = <STDIN>;

                            chomp($db2group);

                            if ( $db2group eq "" ) {
                                $db2group = "tsmsrvrs";
                            }
                        }

                        logentry(
                            "        User response: DB2 group: $db2group\n");

                        ( $rc, $groupalreadyexists, $db2groupid, $msgstring ) =
                          validatedb2groupname($db2group);

                        if ( $rc != 0 ) {
                            $errorstring = genresultString(
"Server Instance Owner Primary Group> $db2group",
                                40, "[ERROR]", $msgstring
                            );
                            displayString( 10, 4, $errorstring, 1, $stpn );
                            $repeatstep =
                              displayPromptExtNoContinue( $stpn, 1 );
                        }

                        if ( $groupalreadyexists == 1 ) {
                            logentry("        DB2 group $db2group exists\n");
                        }
                        else {
                            logentry(
                                "        DB2 group $db2group does not exist\n");
                        }
                    }
                    elsif ( $platform eq "WIN32" ) {
                        $db2group           = "";
                        $groupalreadyexists = 1;
                    }
                }    # end of last if (($doneflag == 0) && ($repeatstep == 0))
            }    # end of if ($useralreadyexists == 0)
            else {
                if (   ( $platform eq "LINUX86" )
                    || ( $platform eq "AIX" )
                    || ( $platform =~ m/LINUXPPC/ ) )
                {
                    $db2userhomedir = $db2userinfo->{homedir};
                    $db2group       = $db2userinfo->{prgrp};

                    # Still need to validate the primary group

                    ( $rc, $groupalreadyexists, $db2groupid, $msgstring ) =
                      validatedb2groupname($db2group);

                    if ( $rc != 0 ) {
                        $errorstring = genresultString(
                            "Server Instance Owner Primary Group> $db2group",
                            40, "[ERROR]", $msgstring );
                        displayString( 10, 4, $errorstring, 1, $stpn );
                        $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
                    }

                    if ( $groupalreadyexists == 1 ) {
                        logentry("        DB2 group $db2group exists\n");
                    }
                    else {
                        logentry(
                            "        DB2 group $db2group does not exist\n");
                    }
                }
                elsif ( $platform eq "WIN32" ) {
                    $groupalreadyexists = 1;
                }
            }

            if ( ( $doneflag == 0 ) && ( $repeatstep == 0 ) ) {

                ( $rcgroup, $rcuser, $msgstring ) = validateUserandGroup(
                    $stpn,             "$db2user",
                    "$db2userpw",      "$db2group",
                    "$db2userhomedir", $useralreadyexists,
                    $db2userinfo,      $groupalreadyexists,
                    $db2groupid
                );

                if ( ( $rcgroup == 0 ) && ( $rcuser == 0 ) ) {
                    $stateHash{db2user}   = "$db2user";
                    $stateHash{db2group}  = "$db2group";
                    $stateHash{db2userpw} = "$db2userpw";
                    $stateHash{db2home}   = "$db2userhomedir";
                    $okstring1 =
                      genresultString( "Server Instance Owner> $db2user",
                        65, "[OK]" );
                    $okstring2 = genresultString(
                        "Server Instance Owner Password> ********",
                        65, "[OK]" );

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $okstring3 = genresultString(
                            "Server Instance Owner home directory> $db2userhomedir",
                            65, "[OK]", $msgstring
                        );
                        $okstring4 = genresultString(
                            "Server Instance Owner Primary Group> $db2group",
                            65, "[OK]" );
                    }

                    displayString( 10, 3, $okstring1, 1, $stpn );
                    displayString( 10, 3, $okstring2 );

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        displayString( 10, 3, $okstring3 );
                        displayString( 10, 3, $okstring4 );
                    }
                    if ( $foundinputinfile == 1 ) {
                        sleep 2;
                    }
                    else {
                        displayPrompt($stpn);
                    }
                }
                elsif ( $rcgroup == 0 ) {
                    $errorstring1 =
                      genresultString( "Server Instance Owner> $db2user",
                        65, "[ERROR]", $msgstring );
                    $errorstring2 = genresultString(
                        "Server Instance Owner Password> ********",
                        65, "[ERROR]", $msgstring );

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $errorstring3 = genresultString(
"Server Instance Owner home directory> $db2userhomedir",
                            65, "[ERROR]", $msgstring
                        );
                        $okstring = genresultString(
                            "Server Instance Owner Primary Group> $db2group",
                            65, "[OK]" );
                    }

                    displayString( 10, 3, $errorstring1, 1, $stpn );
                    displayString( 10, 3, $errorstring2 );

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        displayString( 10, 3, $errorstring3 );
                        displayString( 10, 3, $okstring );
                    }
                    $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
                }
                else {
                    $errorstring1 =
                      genresultString( "Server Instance Owner> $db2user",
                        65, "[ERROR]", $msgstring );
                    $errorstring2 = genresultString(
                        "Server Instance Owner Password> ********",
                        65, "[ERROR]", $msgstring );

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        $errorstring3 = genresultString(
"Server Instance Owner home directory> $db2userhomedir",
                            65, "[ERROR]", $msgstring
                        );
                        $errorstring4 = genresultString(
                            "Server Instance Owner Primary Group> $db2group",
                            65, "[ERROR]", $msgstring );
                    }

                    displayString( 10, 3, $errorstring1, 1, $stpn );
                    displayString( 10, 3, $errorstring2 );

                    if (   ( $platform eq "LINUX86" )
                        || ( $platform eq "AIX" )
                        || ( $platform =~ m/LINUXPPC/ ) )
                    {
                        displayString( 10, 3, $errorstring3 );
                        displayString( 10, 3, $errorstring4 );
                    }
                    $repeatstep = displayPromptExtNoContinue( $stpn, 1 );
                }
            }
        }
    } while ( ( $doneflag == 0 ) && ( $repeatstep != 0 ) );
}

############################################################
#      sub: setulimits
#     desc: Prepares the limits configuration file, /etc/security/limits.conf
#           as pertaining to the user account which will own the DB2 instance
#           by first recreating the limits.conf file minus any lines already
#           pertaining to the db2 user (if any), and then adding suitable lines
#           pertaining to the db2 user account
#
#   params: 1. the step number
#           2. the ordinal of the step letter that will be used for logging purposes
#           3. the db2 account name
#
#  returns: an array consisting of two return codes (the first for the
#           group, the second for the user), and in the case of failure,
#           a suitable message
#
############################################################

sub setulimits {
    $stpn     = shift(@_);
    $username = shift(@_);

    logentry(
        "Step ${stpn}_${substep}: Set appropriate ulimits for user $username\n",
        1
    );

    $setUlimitsErrorString = "An error occurred trying to set ulimits";

    if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
        $limitsconffile = "${SS}etc${SS}security${SS}limits.conf";
    }
    elsif ( $platform eq "AIX" ) {
        $limitsconffile = "${SS}etc${SS}security${SS}limits";
    }

    @limitsconfilecontentsfiltered = ()
      ; # array of lines from the limits file minus any pertaining to the db2 account

    if ( open( LIMITSH, "<$limitsconffile" ) ) {
        @limitsconfilecontents = <LIMITSH>;
        close LIMITSH;
    }
    else {
        logentry(
"        An error occurred when attempting to open $limitsconffile\n"
        );
        displayString( 10, 3, $setUlimitsErrorString );
        my @rcArray = ( 0, 1, "failed to open $limitsconffile" );
        return @rcArray;
    }

    if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
        foreach $limitsfileline (@limitsconfilecontents
          )    # take out any lines pertaining to the db2 account, if any
        {
            if (   ( $limitsfileline !~ m/\s*$username/ )
                && ( $limitsfileline !~ m/^#\s+End\s+of\s+file/i ) )
            {
                push( @limitsconfilecontentsfiltered, $limitsfileline );
            }
        }

        unlink($limitsconffile);    # remove the original limits config file

        if (
            open( LIMITSH, ">$limitsconffile" )
          ) # recreate the limits config file and then add more lines for the db2 owner
        {
            foreach $limitsfileline (@limitsconfilecontentsfiltered) {
                print LIMITSH "$limitsfileline";
            }

            print LIMITSH "\n$username    -   core    unlimited\n";
            print LIMITSH "$username    -   data    unlimited\n";
            print LIMITSH "$username    -   fsize   unlimited\n";
            print LIMITSH "$username    -   nofile  65536\n";
            print LIMITSH "$username    -   cpu     unlimited\n";
            print LIMITSH "$username    -   nproc   16384\n";
            print LIMITSH "\n# End of file\n";
            close LIMITSH;

            $nprocconffile =
              "${SS}etc${SS}security${SS}limits.d${SS}90-nproc.conf";

            if ( -f $nprocconffile ) {
                system("mv $nprocconffile renamed-90-nproc.conf");
            }
        }
        else {
            logentry(
"        An error occurred when attempting to set the ulimits for user $username\n"
            );
            displayString( 10, 3, $setUlimitsErrorString );
            my @rcArray = ( 0, 1, "failed to set ulimits" )
              ; # it is a "user" error if this fails, hence the second argument is 1
            return @rcArray;
        }
    }
    if ( $platform eq "AIX" ) {
        $indb2usersection = 0;

        foreach $limitsfileline (@limitsconfilecontents
          )     # take out any lines pertaining to the db2 account, if any
        {
            if ( $limitsfileline =~ m/^(\w+):/ ) {
                if ( $username eq "$1" ) {
                    $indb2usersection = 1;
                }
                else {
                    $indb2usersection = 0;
                    push( @limitsconfilecontentsfiltered, $limitsfileline );
                }
            }
            elsif ( $indb2usersection == 0 ) {
                push( @limitsconfilecontentsfiltered, $limitsfileline );
            }
        }

        unlink($limitsconffile);    # remove the original limits config file

        if (
            open( LIMITSH, ">$limitsconffile" )
          ) # recreate the limits config file and then add more lines for the db2 owner
        {
            foreach $limitsfileline (@limitsconfilecontentsfiltered) {
                print LIMITSH "$limitsfileline";
            }

            print LIMITSH "\n${username}:\n";
            print LIMITSH "        core = -1\n";
            print LIMITSH "        core_hard = -1\n";
            print LIMITSH "        data = -1\n";
            print LIMITSH "        data_hard = -1\n";
            print LIMITSH "        fsize = -1\n";
            print LIMITSH "        fsize_hard = -1\n";
            print LIMITSH "        nofiles = 65536\n";
            print LIMITSH "        nofiles_hard = 65536\n";
            print LIMITSH "        cpu = -1\n";
            print LIMITSH "        cpu_hard = -1\n";
            print LIMITSH "        nproc = 16384\n";
            print LIMITSH "        nproc_hard = 16384\n";
            close LIMITSH;
        }
        else {
            logentry(
"        An error occurred when attempting to set the ulimits for user $username\n"
            );
            displayString( 10, 3, $setUlimitsErrorString );
            my @rcArray = ( 0, 1, "failed to set ulimits" )
              ; # it is a "user" error if this fails, hence the second argument is 1
            return @rcArray;
        }
    }
    my @rcArray = ( 0, 0, "" );
    return @rcArray;
}

############################################################
#      sub: displayString
#     desc: Prints a string to the screen.
#
#   params: 1. number of spaces in the left margin on the
#              line on which the string is displayed
#           2. number of lines down from the current cursor
#              position to display the string
#           3. the string to be displayed
#           4. an optional argument which, if not null, indicates
#              that the screen should be cleared prior to displaying
#              the string
#
#  returns: none
#
############################################################

sub displayString {
    my $numberspacestoleft = shift(@_);
    my $numbernewlines     = shift(@_);
    my $theString          = shift(@_);
    my $clsflag            = shift(@_);

    if ( $clsflag ne "" ) {
        $stp = shift(@_);

        clearscreen();
        displayStepNumAndDesc($stp);
    }

    for ( my $j = 0 ; $j < $numbernewlines ; $j++ ) {
        print "\n";
    }

    for ( my $k = 0 ; $k < $numberspacestoleft ; $k++ ) {
        print " ";
    }
    print "$theString";
    $currentline += $numbernewlines;
}

############################################################
#      sub: displayCenteredStrings
#     desc: Prints an array of strings to the screen on one
#           line so that they are fairly well spaced across
#           that line.
#
#   params: 1. number of lines down from the current cursor
#              position to display the strings
#           2. reference to the array of strings to display
#
#  returns: none
#
############################################################

sub displayCenteredStrings {
    my $numbernewlines = shift(@_);
    my $stringArrayRef = shift(@_);

    $numberofStrings = @{$stringArrayRef};

    $totalstringlength = 0;

    for ( $strcnt = 0 ; $strcnt < $numberofStrings ; $strcnt++ ) {
        $currentstring = $stringArrayRef->[$strcnt];
        $totalstringlength += length($currentstring);
    }

    $numspaces =
      int( $SCREENWIDTH - $totalstringlength ) / ( $numberofStrings + 1 );

    for ( $j = 0 ; $j < $numbernewlines ; $j++ ) {
        print "\n";
    }

    for ( $strcnt = 0 ; $strcnt < $numberofStrings ; $strcnt++ ) {
        $currentstring = $stringArrayRef->[$strcnt];

        for ( $k = 0 ; $k < $numspaces ; $k++ ) {
            print " ";
        }
        print "$currentstring";
    }
    $currentline += $numbernewlines;
}

############################################################
#      sub: displayList
#     desc: Prints the elements of an array to the screen,
#           four items per line, prefixing each of the items
#           with /<db2 account name>. It is used to display default
#           directory paths to the screen
#
#   params: 1. reference to the array containing the items to
#              be displayed, prefixed by /<db2 account name>,
#              (where <db2 account name> is the DB2 user name
#              specified in step 4), three items per line
#           2. the number of spaces to the left of the leftmost
#              member of each line
#           3. number of new lines between consecutive lines
#              being displayed, if there are multiple lines
#           4. an optional flag which, if not null, indicates
#              that the whole displayed list should be enclosed
#              by brackets ([ . . . ])
#
#  returns: none
#
############################################################

sub displayList {
    my $arrRef             = shift(@_);
    my $numberspacestoleft = shift(@_);
    my $numbernewlines     = shift(@_);
    my $bracketflag        = shift(@_);
    my $db2usr             = $stateHash{db2user};
    my $instdirmntpnt      = $stateHash{instdirmountpoint};

    if ( $bracketflag eq "" ) {
        $outstrg = "";
    }
    else {
        $outstrg = "[";
    }

    $numelements = @{$arrRef};

    my $j = 0;

    displayString( 0, 1, "" );

    while ( $j < $numelements ) {
        do {
            $currelement = $arrRef->[$j];
            if (   ( $platform eq "LINUX86" )
                || ( $platform eq "AIX" )
                || ( $platform =~ m/LINUXPPC/ ) )
            {
                if ( isGPFS() == 1 ) {
                    $currelementfull = "$instdirmntpnt"
                      . "$currelement"
                      ;    # prefix it with the instance directory mountpoint
                }
                else {
                    $currelementfull = "${SS}${db2usr}"
                      . "$currelement";    # prefix it with /<db2user>
                }
            }
            elsif ( $platform eq "WIN32" ) {
                $currelementfull = "${defaultserverdrive}${SS}${db2usr}"
                  . "$currelement";        # prefix it with c:\<db2user>
            }
            if ( ( $j == ( $numelements - 1 ) ) && ( $bracketflag eq "" ) ) {
                $outstrg = "$outstrg" . "$currelementfull";
            }
            elsif ( $j == ( $numelements - 1 ) ) {
                $outstrg = "$outstrg" . "$currelementfull" . "]";
            }
            else {
                $outstrg = "$outstrg" . "$currelementfull" . ",";
            }
            $j++;
        } while ( ( $j < $numelements ) && ( ( $j % 3 ) != 0 ) );

        displayString( $numberspacestoleft, $numbernewlines, $outstrg );
        $outstrg = "";
    }
}

############################################################
#      sub: displayListNoPrefix
#     desc: Like displayList except that the items are not
#           prefixed by anything
#
#   params: 1. reference to the array containing the items to
#              be displayed three items per line
#           2. the number of spaces to the left of the leftmost
#              member of each line
#           3. number of new lines between consecutive lines
#              being displayed, if there are multiple lines
#           4. an optional flag which, if not null, indicates
#              that the whole displayed list should be enclosed
#              by brackets ([ . . . ])
#
#  returns: none
#
############################################################

sub displayListNoPrefix {
    my $arrRef             = shift(@_);
    my $numberspacestoleft = shift(@_);
    my $numbernewlines     = shift(@_);
    my $bracketflag        = shift(@_);

    if ( $bracketflag eq "" ) {
        $outstrg = "";
    }
    else {
        $outstrg = "[";
    }

    $numelements = @{$arrRef};

    my $j = 0;

    displayString( 0, 1, "" );

    while ( $j < $numelements ) {
        do {
            $currelement = $arrRef->[$j];
            if ( ( $j == ( $numelements - 1 ) ) && ( $bracketflag eq "" ) ) {
                $outstrg = "$outstrg" . "$currelement";
            }
            elsif ( $j == ( $numelements - 1 ) ) {
                $outstrg = "$outstrg" . "$currelement" . "]";
            }
            else {
                $outstrg = "$outstrg" . "$currelement" . ",";
            }
            $j++;
        } while ( ( $j < $numelements ) && ( ( $j % 3 ) != 0 ) );

        displayString( $numberspacestoleft, $numbernewlines, $outstrg );
        $outstrg = "";
    }
}

############################################################
#      sub: displayCenteredPromptingString
#     desc: Prints a prompting string (e.g., -->) to the
#           screen so that it appears close to the center of
#           of the line on which it appears.
#
#   params: 1. number of lines down from the current cursor
#           2. the prompting string, such as "-->"
#           3. how many spaces to the right of the prompting
#              to allow for user input at the prompt
#
#  returns: none
#
############################################################

sub displayCenteredPromptingString {
    my $numbernewlines    = shift(@_);
    my $promptingString   = shift(@_);
    my $extraforuserinput = shift(@_);

    $totalstringlength = length($promptingString);

    $totalstringlength += $extraforuserinput
      ;    # extra room to the right of the prompting string for user input

    $numspaces = int( $SCREENWIDTH - $totalstringlength ) / 2;

    for ( $j = 0 ; $j < $numbernewlines ; $j++ ) {
        print "\n";
    }

    for ( $k = 0 ; $k < $numspaces ; $k++ ) {
        print " ";
    }
    print "$promptingString";
    $currentline += $numbernewlines;
}

############################################################
#      sub: clearscreen
#     desc: Clears the screen
#
#   params: none
#  returns: none
#
############################################################

sub clearscreen {
    if ( $platform eq "WIN32" ) {
        system("cls");
    }
    else {
        system("clear");
    }
    $currentline = 1;
}

############################################################
#      sub: validateHostsFile
#     desc: Checks the /etc/hosts file for an entry for the
#           hostname (short or fully qualified form)
#
#   params: none
#  returns: 1, if an entry is found for the hostname
#           0, if no entry is found for the hostname
#
############################################################

sub validateHostsFile {
    $hostsfile                = "/etc/hosts";
    $hostnamefoundinhostsfile = 0;

    if ( open( HOSTSH, "<$hostsfile" ) ) {
        while (<HOSTSH>) {
            if ( $_ =~ /^\s*\d+.\d+.\d+.\d+\s+(.*)$/ ) {
                $namesafterip = $1;
            }

            @name_entries = split( ' ', $namesafterip );

            foreach $nm (@name_entries) {
                if ( length($nm) > 0 ) {
                    if (   ( $nm eq "$thehostname" )
                        || ( $nm eq "$thehostnameFull" ) )
                    {
                        $hostnamefoundinhostsfile = 1;
                    }
                }
            }
        }
        close HOSTSH;
    }
    return $hostnamefoundinhostsfile;
}

############################################################
#      sub: validateUserandGroup
#     desc: validates the user account and group specified
#           by the second and fourth arguments, respectively,
#           creating them as necessary, and making the specified
#           group the primary group of the specified user, if the
#           user did not already exist on the system. If the
#           user already existed on the system, and is not
#           already a member of the group, then the user is
#           simply added as a member of that group. For Unix/Linux
#           systems, the ulimits file is prepared for the user
#
#   params: 1. the step number
#           2. the user account
#           3. the user account password
#           4. the group account
#           5. the user home directory (used if the user does not already exist)
#           6. a variable indicating whether the user in argument 2. already
#              exists
#           7. a reference to a variable that contains information
#              about the user (used if the user already exists)
#           8. a variable indicating whether the group in argument 4.
#              already exists
#           9. if the group in argument 4 already exists, the group id
#
#  returns: an array consisting of two return codes (the first for the
#           group, the second for the user), and in the case of failure,
#           a suitable message
#
############################################################

sub validateUserandGroup {
    $stpn        = shift(@_);
    $username    = shift(@_);
    $userpw      = shift(@_);
    $groupname   = shift(@_);
    $userhomedir = shift(@_);
    $userfound   = shift(@_);
    $userinfoRef = shift(@_);
    $groupfound  = shift(@_);
    $groupid     = shift(@_);

    $userisingroup = 0;

# various commands that will be needed: to create the user account, create the group account,
# and to make the group account the primary group of the user account, as necessary

    if ( $platform eq "LINUX86" || $platform =~ m/LINUXPPC/ ) {

        my $salt = getsalt();
        $salt = "\$6\$" . "${salt}";    # Add $6$ to produce sha-512
        my $hashedpw = crypt( $userpw, $salt );

        $create_group_cmd = "groupadd $groupname";
        if ( $isSLES == 1 ) {
            $create_user_cmd =
"useradd -d $userhomedir -m -s ${SS}bin${SS}bash -p \'$hashedpw\' $username";
            $create_user_cmd_with_masked_pw =
"useradd -d $userhomedir -s ${SS}bin${SS}bash -p \'********\' $username";
        }
        else # The -N flag on RHEL and Ubuntu prevents automatic creation of a group named after the user
        {
            $create_user_cmd =
"useradd -d $userhomedir -m -s ${SS}bin${SS}bash -N -p \'$hashedpw\' $username";
            $create_user_cmd_with_masked_pw =
"useradd -d $userhomedir -s ${SS}bin${SS}bash -N -p \'********\' $username";
        }
        $make_group_primary_group_of_user_cmd =
          "usermod -g $groupname $username";
    }
    elsif ( $platform eq "AIX" ) {
        $create_group_cmd = "mkgroup $groupname";
        $create_user_cmd =
          "mkuser pgrp=${groupname} home=${userhomedir} $username";
        $set_user_pw_cmd =
          "echo \"$username:`openssl passwd $userpw`\" | chpasswd -e -c";
        $set_user_pw_cmd_with_masked_pw =
          "echo \"$username:`openssl passwd ********`\" | chpasswd -e -c";
        $make_group_primary_group_of_user_cmd =
          "usermod -g $groupname $username";
    }
    elsif ( $platform eq "WIN32" ) {
        $create_user_cmd = "net user $username \\\"$userpw\\\" /add /Y 2>nul";
        $create_user_cmd_with_masked_pw =
          "net user $username \\\"********\\\" /add 2>nul";
        $make_user_admin_cmd =
          "net localgroup Administrators $username /add 2>nul";
        $make_user_db2admin_cmd =
          "net localgroup DB2ADMNS $username /add 2>nul";
        $make_user_db2user_cmd = "net localgroup DB2USERS $username /add 2>nul";
    }

    if ( ( $userfound == 1 ) && ( $groupfound == 1 ) ) {
        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            if ( "$userprimarygroupid" eq "$groupid" ) {
                $userisingroup = 1;
            }
        }
        elsif ( $platform eq "WIN32" ) {
            if (   ( $userinfoRef->{inadmns} eq "yes" )
                && ( $userinfoRef->{indb2admns} eq "yes" )
                && ( $userinfoRef->{indb2users} eq "yes" ) )
            {
                $userisingroup = 1;
            }
        }
    }

    if ( ( $userfound == 0 ) || ( $groupfound == 0 ) ) {
        if (   ( $userfound == 0 )
            && ( $groupfound == 0 ) )    # neither the user nor the group exists
        {
            logentry( "Step ${stpn}_${substep}: Create the DB2 group\n", 1 );
            logentry("        Issuing command: $create_group_cmd\n");

            if (   ( $platform eq "LINUX86" )
                || ( $platform eq "AIX" )
                || ( $platform =~ m/LINUXPPC/ ) )
            {
                $crgrprc = system("$create_group_cmd");
            }

            if ( $crgrprc != 0 ) {
                logentry(
"        There was an error when attempting to create the group $groupname\n"
                );
                my @rcArray = ( 1, 1, "error creating group" )
                  ;    # error involves the group, hence the first
                return @rcArray;    # element of rcArray is 1 in this case
            }
            else {
                push( @{ $stateHash{createdgroups} }, $groupname );
            }

            logentry(
                "Step ${stpn}_${substep}: Create the DB2 instance owner\n", 1 );

            # make sure the parent directory of the home directory exists before
            # creating the user

            $lastdelimiterindxofhomedir = rindex( $userhomedir, "$SS" );
            $userhomedirparent =
              substr( $userhomedir, 0, $lastdelimiterindxofhomedir );
            ( $createhomedirparentrc, $createhomedirmsg ) =
              createsubdirsundermntpnt($userhomedirparent);

            if ( $createhomedirparentrc != 0 ) {
                my @rcArray = ( 0, 1, "$createhomedirmsg" );
                return @rcArray;
            }

            if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
                logentry(
                    "        Issuing command: $create_user_cmd_with_masked_pw\n"
                );
            }
            elsif ( $platform eq "AIX" ) {
                logentry("        Issuing command: $create_user_cmd\n");
                logentry(
                    "        Issuing command: $set_user_pw_cmd_with_masked_pw\n"
                );
            }

            if (   ( $platform eq "LINUX86" )
                || ( $platform eq "AIX" )
                || ( $platform =~ m/LINUXPPC/ ) )
            {
                $crusrrc = system("$create_user_cmd");
                if ( ( $platform eq "AIX" ) && ( $crusrrc == 0 ) ) {
                    $setusrpwrc = system("$set_user_pw_cmd");
                }
            }

            if (   ( $crusrrc != 0 )
                || ( ( $platform eq "AIX" ) && ( $setusrpwrc != 0 ) ) )
            {
                logentry(
"        There was an error when attempting to create the user $username\n"
                );
                my @rcArray = ( 0, 1, "error creating user" );
                return @rcArray;
            }
            else {
                push( @{ $stateHash{createdusers} }, $username );
            }

            if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
                logentry(
"Step ${stpn}_${substep}: Make DB2 group the primary group of the DB2 instance owner\n",
                    1
                );
                logentry(
"        Issuing command: $make_group_primary_group_of_user_cmd\n"
                );

                $assprimgrprc = system("$make_group_primary_group_of_user_cmd");
                if ( $assprimgrprc != 0 ) {
                    logentry(
"        There was an error when attempting to make $groupname the primary group of $username\n"
                    );
                    my @rcArray = ( 0, 1, "error assigning primary group" );
                    return @rcArray;
                }
            }
        }
        elsif (( $userfound == 0 )
            && ( $groupfound == 1 )
          )    # the user does not exist but the group does
        {
            logentry(
                "Step ${stpn}_${substep}: Create the DB2 instance owner\n", 1 );

            # make sure the parent directory of the home directory exists before
            # creating the user

            $lastdelimiterindxofhomedir = rindex( $userhomedir, "$SS" );
            $userhomedirparent =
              substr( $userhomedir, 0, $lastdelimiterindxofhomedir );
            ( $createhomedirparentrc, $createhomedirmsg ) =
              createsubdirsundermntpnt($userhomedirparent);

            if ( $createhomedirparentrc != 0 ) {
                my @rcArray = ( 0, 1, "$createhomedirmsg" );
                return @rcArray;
            }

            if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
                logentry(
                    "        Issuing command: $create_user_cmd_with_masked_pw\n"
                );
            }
            elsif ( $platform eq "AIX" ) {
                logentry("        Issuing command: $create_user_cmd\n");
                logentry(
                    "        Issuing command: $set_user_pw_cmd_with_masked_pw\n"
                );
            }
            elsif ( $platform eq "WIN32" ) {
                logentry(
                    "        Issuing command: $create_user_cmd_with_masked_pw\n"
                );
            }

            if (   ( $platform eq "LINUX86" )
                || ( $platform eq "AIX" )
                || ( $platform =~ m/LINUXPPC/ ) )
            {
                $crusrrc = system("$create_user_cmd");
                if ( ( $platform eq "AIX" ) && ( $crusrrc == 0 ) ) {
                    $setusrpwrc = system("$set_user_pw_cmd");
                }
            }
            elsif ( $platform eq "WIN32" ) {
                $crusrrc = 1;

                @crusrOut = `$create_user_cmd`;
                $crusrrc  = $?;

            }

            if (   ( $crusrrc != 0 )
                || ( ( $platform eq "AIX" ) && ( $setusrpwrc != 0 ) ) )
            {
                logentry(
"        There was an error when attempting to create the user $username\n"
                );
                my @rcArray = ( 0, 1, "error creating user" );
                return @rcArray;
            }
            else {
                push( @{ $stateHash{createdusers} }, $username );
            }

            if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
                logentry(
"Step ${stpn}_${substep}: Make DB2 group the primary group of the DB2 instance owner\n",
                    1
                );
                logentry(
"        Issuing command: $make_group_primary_group_of_user_cmd\n"
                );

                $assprimgrprc = system("$make_group_primary_group_of_user_cmd");
                if ( $assprimgrprc != 0 ) {
                    logentry(
"        There was an error when attempting to make $groupname the primary group of $username\n"
                    );
                    my @rcArray = ( 0, 1, "error assigning primary group" );
                    return @rcArray;
                }
            }
            elsif ( $platform eq "WIN32" ) {
                logentry(
"Step ${stpn}_${substep}: Make DB2 instance owner a member of administrators and DB2 administrators groups\n",
                    1
                );
                logentry("        Issuing command: $make_user_admin_cmd\n");

                $mkuseradmincmdrc    = 1;
                $mkuserdb2admincmdrc = 1;
                $mkuserdb2usercmdrc  = 1;

                @mkuseradminOut   = `$make_user_admin_cmd`;
                $mkuseradmincmdrc = $?;

                if ( $mkuseradmincmdrc != 0 ) {
                    logentry(
"        There was an error when attempting to add $username to the administrators group\n"
                    );
                    my @rcArray =
                      ( 0, 1, "error adding to administrators group" );
                    return @rcArray;
                }

                logentry("        Issuing command: $make_user_db2admin_cmd\n");

                @mkuserdb2adminOut   = `$make_user_db2admin_cmd`;
                $mkuserdb2admincmdrc = $?;

                if ( $mkuserdb2admincmdrc != 0 ) {
                    logentry(
"        There was an error when attempting to add $username to the DB2 administrators group\n"
                    );
                    my @rcArray =
                      ( 0, 1, "error adding to DB2 administrators group" );
                    return @rcArray;
                }

                logentry("        Issuing command: $make_user_db2user_cmd\n");

                @mkuserdb2userOut   = `$make_user_db2user_cmd`;
                $mkuserdb2usercmdrc = $?;

                if ( $mkuserdb2usercmdrc != 0 ) {
                    logentry(
"        There was an error when attempting to add $username to the DB2 users group\n"
                    );
                    my @rcArray = ( 0, 1, "error adding to DB2 users group" );
                    return @rcArray;
                }
            }
        }
    }
    elsif (( $userfound == 1 )
        && ( $groupfound == 1 )
        && ( $userisingroup == 0 ) )    # the user and the group both exist
    {
        if ( $platform eq "WIN32" ) {
            logentry(
"Step ${stpn}_${substep}: Make DB2 instance owner a member of administrators and DB2 administrators groups\n",
                1
            );

            $mkuseradmincmdrc    = 1;
            $mkuserdb2admincmdrc = 1;
            $mkuserdb2usercmdrc  = 1;

            if ( $userinfoRef->{inadmns} eq "no" ) {
                logentry("        Issuing command: $make_user_admin_cmd\n");

                @mkuseradminOut   = `$make_user_admin_cmd`;
                $mkuseradmincmdrc = $?;
            }
            else {
                $mkuseradmincmdrc = 0;
            }

            if ( $mkuseradmincmdrc != 0 ) {
                logentry(
"        There was an error when attempting to add $username to the administrators group\n"
                );
                my @rcArray = ( 0, 1, "error adding to administrators group" );
                return @rcArray;
            }

            if ( $userinfoRef->{indb2admns} eq "no" ) {
                logentry("        Issuing command: $make_user_db2admin_cmd\n");

                @mkuserdb2adminOut   = `$make_user_db2admin_cmd`;
                $mkuserdb2admincmdrc = $?;
            }
            else {
                $mkuserdb2admincmdrc = 0;
            }

            if ( $mkuserdb2admincmdrc != 0 ) {
                logentry(
"        There was an error when attempting to add $username to the DB2 administrators group\n"
                );
                my @rcArray =
                  ( 0, 1, "error adding to DB2 administrators group" );
                return @rcArray;
            }

            if ( $userinfoRef->{indb2users} eq "no" ) {
                logentry("        Issuing command: $make_user_db2user_cmd\n");

                @mkuserdb2userOut   = `$make_user_db2user_cmd`;
                $mkuserdb2usercmdrc = $?;
            }
            else {
                $mkuserdb2usercmdrc = 0;
            }

            if ( $mkuserdb2usercmdrc != 0 ) {
                logentry(
"        There was an error when attempting to add $username to the DB2 users group\n"
                );
                my @rcArray = ( 0, 1, "error adding to DB2 users group" );
                return @rcArray;
            }
        }
    }

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        @ulimitrcArray = setulimits( $stpn, $username );
    }
    else {
        @ulimitrcArray = ( 0, 0, "" );
    }
    return @ulimitrcArray;
}

############################################################
#      sub: getsalt
#     desc: Generates a salt from /dev/random to be used
#           for generating a SHA-512 hashed password
#
#   params: None
#  returns: Returns a 16 character random salt string
#
############################################################

sub getsalt {
    my @saltchars = ( '.', '/', 0 .. 9, 'A' .. 'Z', 'a' .. 'z' );
    my $salt      = "";
    my ( @randombytes, $rndbytes, $l );
    open my $rndh, "<", "/dev/random" or die "Unable to open /dev/random\n";
    read $rndh, $rndbytes, 16;    # get 16 bytes
    close $rndh;
    my @randombytes = unpack( "C*", $rndbytes )
      ;    # unpack into an array of 16 bytes (each between 0 and 255)
    for ( $l = 0 ; $l < 16 ; $l++ ) {
        $salt = "$salt" . "$saltchars[$randombytes[$l] % 64]";
    }
    return $salt;
}

############################################################
#      sub: getunxuserproperties
#     desc: Obtains information about a specified user on a
#           Unix/Linux system
#
#   params: user about which information is needed
#  returns: an array of 2 entries, the first entry indicating
#           whether the user exists (0 if it does not exist,
#           1 if it does) and if it does exist, the second is a
#           reference to a structure with 3 fields, specifying
#           the user's primary group, primary group id, and
#           home directory, respectively
#
############################################################

sub getunxuserproperties {
    my $usrnm = shift(@_);

    my $usrfound = 0;

    my $usrinfo = {};

    $usrinfo->{prgrp}   = "";
    $usrinfo->{prgrpid} = "";
    $usrinfo->{homedir} = "";

    $qusercmd    = "cat ${SS}etc${SS}passwd | grep $usrnm";
    @qusercmdOut = `$qusercmd`;

    foreach $item (@qusercmdOut)    # Check if user exists
    {
        @ucomponents = split( ':', $item );
        if ( $ucomponents[0] eq "$usrnm" ) {
            $usrinfo->{prgrpid} = $ucomponents[3];
            $usrinfo->{homedir} = $ucomponents[5];
            $usrfound           = 1;
        }
    }

    if ( $usrfound == 1 ) {
        $usrinfo->{prgrp} = getunxgroupnamefromid( $usrinfo->{prgrpid} );
    }

    return ( $usrfound, $usrinfo );
}

############################################################
#      sub: getwinuserproperties
#     desc: Obtains information about a specified user on a
#           Windows system
#
#   params: user about which information is needed
#  returns: an array of 2 entries, the first entry indicating
#           whether the user exists (0 if it does not exist,
#           1 if it does) and if it exists, the second is a
#           reference to a structure with 3 fields, indicating
#           whether the user belongs to Administrators group,
#           the DB2ADMNS group, and DB2USERS group, respectively
#
############################################################

sub getwinuserproperties {
    $usrnm = shift(@_);

    $usrfound = 0;

    my $usrinfo = {};

    $usrinfo->{inadmns}    = "no";
    $usrinfo->{indb2admns} = "no";
    $usrinfo->{indb2users} = "no";

    $qusercmd    = "net user $usrnm 2>nul";
    @qusercmdOut = `$qusercmd`;

    foreach $quserline (@qusercmdOut)    # Check if user exists
    {
        if ( $quserline =~ m/^User\s+name\s+$usrnm/ ) {
            $usrfound = 1;
        }
    }

    if ( $usrfound == 1 ) {
        $qadminscmd    = "net localgroup Administrators 2>nul";
        $qdb2adminscmd = "net localgroup DB2ADMNS 2>nul";
        $qdb2userscmd  = "net localgroup DB2USERS 2>nul";

        @qadminscmdOut = `$qadminscmd`;

        foreach $qadminsline (@qadminscmdOut) {
            if ( $qadminsline =~ m/^$usrnm/ ) {
                $usrinfo->{inadmns} = "yes";
            }
        }

        @qdb2adminscmdOut = `$qdb2adminscmd`;

        foreach $qdb2adminsline (@qdb2adminscmdOut) {
            if ( $qdb2adminsline =~ m/^$usrnm/ ) {
                $usrinfo->{indb2admns} = "yes";
            }
        }

        @qdb2userscmdOut = `$qdb2userscmd`;

        foreach $qdb2usersline (@qdb2userscmdOut) {
            if ( $qdb2usersline =~ m/^$usrnm/ ) {
                $usrinfo->{indb2users} = "yes";
            }
        }
    }

    return ( $usrfound, $usrinfo );
}

############################################################
#      sub: getunxgroupproperties
#     desc: Obtains information about a specified group on a
#           Unix/Linux system
#
#   params: group about which information is needed
#  returns: an array of 2 entries, the first entry indicating
#           whether the group exists (0 if it does not exist,
#           1 if it does) and if does exist, the second
#           entry is the group's group id
#
############################################################

sub getunxgroupproperties {
    $grpnm = shift(@_);

    $grpfound = 0;
    $grpid    = "";

    $qgroupcmd    = "cat ${SS}etc${SS}group | grep $grpnm";
    @qgroupcmdOut = `$qgroupcmd`;

    foreach $item (@qgroupcmdOut)    # Check if group exists
    {
        @gcomponents = split( ':', $item );
        if ( $gcomponents[0] eq "$grpnm" ) {
            $grpid    = $gcomponents[2];
            $grpfound = 1;
        }
    }

    return ( $grpfound, $grpid );
}

############################################################
#      sub: getunxgroupnamefromid
#     desc: Determines the group name corresponding to the
#           specified group id
#
#   params: group id for which the corresponding name is
#           needed
#  returns: the name of the group with the id specified
#
############################################################

sub getunxgroupnamefromid {
    $grpid = shift(@_);

    $grpnm = "";

    $qgroupidcmd    = "cat ${SS}etc${SS}group | grep $grpid";
    @qgroupidcmdOut = `$qgroupidcmd`;

    foreach $item (@qgroupidcmdOut) {
        @gcomponents = split( ':', $item );
        if ( $gcomponents[2] == $grpid ) {
            $grpnm = $gcomponents[0];
        }
    }

    return $grpnm;
}

############################################################
#      sub: ispreexistinguser
#     desc: Determines the specified user already existed
#           prior to running the configuration script,
#           by checking if it is or is not in the array
#           of created users
#
#   params: user the pre-existence of which is to be
#           determined
#
#  returns: 1, if the user already existed
#           0, if the user did not already exist
############################################################

sub ispreexistinguser {
    my $usrnm = shift(@_);

    my $ispreexisting = 1;

    foreach $usr ( @{ $stateHash{createdusers} } ) {
        if ( $usr eq "$usrnm" ) {
            $ispreexisting = 0;
        }
    }
    return $ispreexisting;
}

############################################################
#      sub: validateMountPoint
#     desc: determines if the directory path specified by the first argument
#           exists and if so, determines if it is the mount point of a mounted
#           filesystem of type ext3 or ext4 and that has read/write access
#           If the third argument is 1, then this subroutine also checks
#           if the path specified by the first argument is empty. If the
#           preceding criteria are all met, the free space contained under the
#           specified mount point is obtained, and the variable referenced by
#           the second argument is set to the amount of free space (in KB)
#
#   params: 1. the directory path to check
#           2. flag to check if the directory is empty (if it is 1, check if it is empty, if 0 then don't)
#           3. optional flag which, if it is not null, then disregard whether the path is a filesystem mount point
#           4. optional flag which, if it is not null, then disregard whether the path has already been selected
#
#  returns: an array consisting of a return code (0 for success, 1 for failure)
#           and in the case of failure, a suitable message indicating the
#           reason for the failure (e.g., "is not empty")
#
############################################################

sub validateMountPoint {
    $dirpth = shift(@_);
    $checkifempty =
      shift(@_);    # if 0, then skip empty check, otherwise check if empty
    $checkifmountpoint    = shift(@_);    # for testing only
    $alreadyselectedcheck = shift(@_);

    logentry("        Attempting to validate directory $dirpth\n");

    if ( !-d $dirpth ) {
        logentry("        $dirpth does not exist\n");
        my @rcArray = ( 1, "does not exist" );
        return @rcArray;
    }
    elsif ( ( index( $dirpth, " " ) >= 0 ) || ( index( $dirpth, "	" ) >= 0 ) ) {
        logentry("        $dirpth has a space\n");
        my @rcArray = ( 1, "has space" );
        return @rcArray;
    }
    elsif ( $dirpth eq "${SS}" ) {
        logentry("        The root filesystem may not be selected\n");
        my @rcArray = ( 1, "root filesystem cannot be selected" );
        return @rcArray;
    }
    elsif (( $alreadyselectedcheck eq "" )
        && ( isalreadySelected($dirpth) == 1 ) )
    {
        logentry("        $dirpth has already been selected\n");
        my @rcArray = ( 1, "is already selected" );
        return @rcArray;
    }
    else {
        $founddirasmntpnt = 0;

        if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
            foreach $mntpnt (@mountOut) {
                if (
                    (
                        $mntpnt =~
                        m#^/dev\S+\s+on\s+$dirpth\s+type\s+ext3\s+\(rw\S*\)#
                    )
                    || ( $mntpnt =~
                        m#^/dev\S+\s+on\s+$dirpth\s+type\s+ext4\s+\(rw\S*\)# )
                    || ( $mntpnt =~
                        m#^/dev\S+\s+on\s+(\S+)\s+type\s+xfs\s+\(rw\S*\)# )
                  )
                {
                    $founddirasmntpnt = 1;
                }
            }
        }
        elsif ( $platform eq "AIX" ) {
            foreach $mntpnt (@mountOut) {
                if ( $mntpnt =~ m#^\s*/dev\S+\s+$dirpth\s+jfs2# ) {
                    $founddirasmntpnt = 1;

                }
            }
        }
        elsif ( $platform eq "WIN32" ) {
            foreach $mntpnt (@mountVolOut) {
                if (   ( $mntpnt !~ m/\\\\/ )
                    && ( $mntpnt =~ m/\s+(\w:\S*)\\$/i ) )
                {
                    $founddirasmntpnt = 1;
                }
            }
        }

        if ( ( $checkifmountpoint eq "" ) && ( $founddirasmntpnt == 0 ) ) {
            logentry("        $dirpth is not a mount point\n");
            my @rcArray = ( 1, "not a mount point" );
            return @rcArray;
        }
        else {
            if ( $checkifempty == 1 ) {
                logentry("        Verify that $dirpth is empty\n");
            }

            if (   ( $checkifempty == 1 )
                && ( isEmptyDir($dirpth) == 0 )
              ) # if it is required to be empty, but is not, then log the contents in the script log
            {
                logentry(
"        The following items were found under ${dirpth}:\n\n"
                );
                logcontents($dirpth);
                logentry(
"        \nPlease remove them before continuing with server setup\n"
                );
                my @rcArray = ( 1, "is not empty" );
                return @rcArray;
            }
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
    }
}

############################################################
#      sub: chownPaths
#     desc: chowns the db instance directory, the db directories, the IBM Storage Protect storage
#           directories, the db log paths, and the db backup directory, to the DB2
#           instance owner and group
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 (or nonzero) if there was a failure
#
############################################################

sub chownPaths {
    $stpn = shift(@_);

    logentry(
"Step ${stpn}: Make the DB2 instance owner the owner of the db instance directory, db directories, log, db backup directories, db log directories, and storage directories\n"
    );

    $db2usr = $stateHash{db2user};
    $db2grp = $stateHash{db2group};

    @chownedpaths = ()
      ; # needed to keep track of paths already chowned, to avoid redundant chowns

    $instdirmntpnt = $stateHash{instdirmountpoint};
    $actlogpth     = $stateHash{actlogpath};
    $archlogpth    = $stateHash{archlogpath};
    $dbbackdir     = $stateHash{dbbackDir};
    $dbdirpths     = $stateHash{dbdirpaths};
    $tsmstgpths    = $stateHash{tsmstgpaths};
    $dbbackdirpths = $stateHash{dbbackdirpaths};

    $chowncmd = "chown -R ${db2usr}:${db2grp} $instdirmntpnt";
    push( @chownedpaths, $instdirmntpnt );

    logentry("        Issuing command: $chowncmd\n");
    $chownrc = system("$chowncmd");
    if ( $chownrc != 0 ) {
        logentry(
"        There was an error when attempting to the command $chowncmd\n"
        );
    }

    if ( ( $chownrc == 0 ) && ( issubpath( $actlogpth, $instdirmntpnt ) == 0 ) )
    {
        $chowncmd = "chown -R ${db2usr}:${db2grp} $actlogpth";
        push( @chownedpaths, $actlogpth );

        logentry("        Issuing command: $chowncmd\n");
        $chownrc = system("$chowncmd");
        if ( $chownrc != 0 ) {
            logentry(
"        There was an error when attempting to the command $chowncmd\n"
            );
        }
    }

    if (   ( $chownrc == 0 )
        && ( issubpath( $archlogpth, $instdirmntpnt ) == 0 )
        && ( issubpath( $archlogpth, $actlogpth ) == 0 ) )
    {
        $chowncmd = "chown -R ${db2usr}:${db2grp} $archlogpth";
        push( @chownedpaths, $archlogpth );

        logentry("        Issuing command: $chowncmd\n");
        $chownrc = system("$chowncmd");
        if ( $chownrc != 0 ) {
            logentry(
"        There was an error when attempting to the command $chowncmd\n"
            );
        }
    }

    foreach $pth ( @{$dbdirpths} ) {
        $isalreadychowned = 0;

        foreach $p (@chownedpaths) {
            if ( issubpath( $pth, $p ) == 1 ) {
                $isalreadychowned = 1;
            }
        }

        if ( ( $chownrc == 0 ) && ( $isalreadychowned == 0 ) ) {
            $chowncmd = "chown -R ${db2usr}:${db2grp} $pth";
            push( @chownedpaths, $pth );

            logentry("        Issuing command: $chowncmd\n");
            $chownrc = system("$chowncmd");
            if ( $chownrc != 0 ) {
                logentry(
"        There was an error when attempting to the command $chowncmd\n"
                );
            }
        }
    }

    foreach $pth ( @{$tsmstgpths} ) {
        $isalreadychowned = 0;

        foreach $p (@chownedpaths) {
            if ( issubpath( $pth, $p ) == 1 ) {
                $isalreadychowned = 1;
            }
        }

        if ( ( $chownrc == 0 ) && ( $isalreadychowned == 0 ) ) {
            $chowncmd = "chown -R ${db2usr}:${db2grp} $pth";
            push( @chownedpaths, $pth );

            logentry("        Issuing command: $chowncmd\n");
            $chownrc = system("$chowncmd");
            if ( $chownrc != 0 ) {
                logentry(
"        There was an error when attempting to the command $chowncmd\n"
                );
            }
        }
    }

    foreach $pth ( @{$dbbackdirpths} ) {
        $isalreadychowned = 0;

        foreach $p (@chownedpaths) {
            if ( issubpath( $pth, $p ) == 1 ) {
                $isalreadychowned = 1;
            }
        }

        if ( ( $chownrc == 0 ) && ( $isalreadychowned == 0 ) ) {
            $chowncmd = "chown -R ${db2usr}:${db2grp} $pth";
            push( @chownedpaths, $pth );

            logentry("        Issuing command: $chowncmd\n");
            $chownrc = system("$chowncmd");
            if ( $chownrc != 0 ) {
                logentry(
"        There was an error when attempting to the command $chowncmd\n"
                );
            }
        }
    }

    if ( $chownrc == 0 ) {
        $okstring = genresultString( $chowndb2pathsString, 50, "[OK]" );
        displayString( 10, 3, $okstring );
    }
    else {
        $errorstring = genresultString( $chowndb2pathsString, 50, "[ERROR]",
            "see log $stateHash{logname}" );
        displayString( 10, 3, $errorstring );
    }
    return $chownrc;
}

############################################################
#      sub: createDB2instance
#     desc: creates the DB2 instance associated with the user
#           account previously specified, first making sure
#           that the instance does not already exist.  If it does
#           already exist, or, if the attempt to create the instance
#           fails, the user is prompted to either exit, or quit with
#           intent to continue from this step later, after correcting
#           the problem
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub createDB2instance {
    $stpn = shift(@_);

    displayStepNumAndDesc($stpn);

    displayString( 10, 3, $createDB2instString );

    $db2usr   = $stateHash{db2user};
    $db2usrpw = $stateHash{db2userpw};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $listInstCmd   = $db2Path . "${SS}instance${SS}db2ilist";
        $createInstCmd = $db2Path
          . "${SS}instance${SS}db2icrt -a server -s ese -u $db2usr $db2usr";
    }
    elsif ( $platform eq "WIN32" ) {
        $listInstCmd   = $db2Path . "${SS}bin${SS}db2ilist";
        $createInstCmd = $db2Path
          . "${SS}bin${SS}db2icrt -s ese -u ${db2usr},\\\"${db2usrpw}\\\" $db2usr";
        $createInstCmd_with_masked_pw = $db2Path
          . "${SS}bin${SS}db2icrt -s ese -u ${db2usr},\\\"********\\\" $db2usr";
    }

    $listinstrc = 0;

    $crinstancerc = 1;

    # Make sure the instance does not already exist

    logentry(
"Step ${stpn}_${substep}: Verify that the DB2 instance does not already exist\n",
        1
    );
    logentry("        Issuing command: $listInstCmd\n");

    @listInstCmdOut = `$listInstCmd`;

    foreach $outln (@listInstCmdOut) {
        if ( $outln =~ m/$db2usr/ ) {
            $listinstrc = 1;
        }
    }

    if ( $listinstrc == 0 ) {
        logentry( "Step ${stpn}_${substep}: Create the DB2 instance\n", 1 );

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            logentry("        Issuing command: $createInstCmd\n");
        }
        elsif ( $platform eq "WIN32" ) {
            logentry(
                "        Issuing command: $createInstCmd_with_masked_pw\n");
        }

        @createInstCmdOut = `$createInstCmd`;

        open( LOGH, ">>$serversetupLog" );

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            foreach $outln (@createInstCmdOut) {
                print LOGH "$outln";
                if ( $outln =~ m/DBI1070I/i ) {
                    $crinstancerc = 0;
                }
            }
        }
        elsif ( $platform eq "WIN32" ) {
            foreach $outln (@createInstCmdOut) {
                print LOGH "$outln";
                if ( $outln =~ m/DB20000I/i )    #check for DB2ICRT
                {
                    $crinstancerc = 0;
                }
            }
        }
        close LOGH;

        if ( $crinstancerc == 0 ) {
            $okstring = genresultString( $createDB2instString, 50, "[OK]" );
            displayString( 10, 3, $okstring, 1, $stpn );
            displayString( 0, 2, "" );
            $prepuserprofrc = prepareUserProfiles($stpn);

            if ( $prepuserprofrc == 0 ) {
                displayString( 0, 2, "" );
                $setdb2instparamsrc = setdb2InstParameters($stpn);
                if ( $setdb2instparamsrc == 0 ) {
                    if ( $takeinputfromfile == 1 ) {
                        sleep 2;
                    }
                    else {
                        displayPrompt( $stpn, "noq" );
                    }
                }
                else {
                    displayPromptNoContinue( $stpn, "noq" );
                }
            }
            else {
                displayPromptNoContinue( $stpn, "noq" );
            }
        }
        else {
            logentry(
"        There was an error occurred when attempting to create the DB2 instance $db2usr\n"
            );
            $errorstring = genresultString( $createDB2instString, 50, "[ERROR]",
                "see log $stateHash{logname}" );
            displayString( 10, 3, $errorstring, 1, $stpn );
            displayPromptNoContinue( $stpn, "noq" );
        }
    }
    else {
        logentry("        The instance $db2usr already exists\n");
        $errorstring = genresultString( $createDB2instString, 50, "[ERROR]",
            "instance already exists" );
        displayString( 10, 3, $errorstring, 1, $stpn );
        displayPromptNoContinue( $stpn, "noq" );
    }
}

############################################################
#      sub: prepareUserProfiles
#     desc: prepares the user DB2 instance owner "profiles" that will be
#           needed later.  The profiles prepared are as follows: the
#           .profile file under the home directory of the DB2 user,
#           usercshrc file under the sqllib subdirectory of the DB2 user's
#           home directory, and the userprofile file under that same
#           subdirectory. Also the dsmserv.opt file in initially set up,
#           as well as a set of command files that will be need subsequently
#           for DB2 instance configuration.
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is a failure
#
############################################################

sub prepareUserProfiles {
    $stpn = shift(@_);

    $db2usr = $stateHash{db2user};
    $db2grp = $stateHash{db2group};

    $crprofilerc         = 0;
    $updusercshrcrc      = 0;
    $updateuserprofilerc = 0;

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        ( $crprofilerc, $msgstring ) = createProfile($stpn);
    }

    if ( $crprofilerc == 1 ) {
        $errorstring = genresultString( $prepareUserProfsString, 50, "[ERROR]",
            "$msgstring" );
        displayString( 10, 3, $errorstring );
        return 1;
    }
    else {
        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            ( $updusercshrcrc, $msgstring ) = updateusercshrc($stpn);
        }

        if ( $updusercshrcrc == 1 ) {
            $errorstring =
              genresultString( $prepareUserProfsString, 50, "[ERROR]",
                "$msgstring" );
            displayString( 10, 3, $errorstring );
            return 1;
        }
        else {
            if (   ( $platform eq "LINUX86" )
                || ( $platform eq "AIX" )
                || ( $platform =~ m/LINUXPPC/ ) )
            {
                ( $updateuserprofilerc, $msgstring ) = updateuserprofile($stpn);
            }

            if ( $updateuserprofilerc == 1 ) {
                $errorstring =
                  genresultString( $prepareUserProfsString, 50, "[ERROR]",
                    "$msgstring" );
                displayString( 10, 3, $errorstring );
                return 1;
            }
            else {
                ( $prepdsmservoptrc, $msgstring ) =
                  preparedsmservoptfile($stpn);

                if ( $prepdsmservoptrc == 1 ) {
                    $errorstring =
                      genresultString( $prepareUserProfsString, 50, "[ERROR]",
                        "$msgstring" );
                    displayString( 10, 3, $errorstring );
                    return 1;
                }
                else {

                    ( $prepdb2cmdfilesrc, $msgstring ) =
                      preparedb2commandfiles($stpn);

                    if ( $prepdb2cmdfilesrc == 1 ) {
                        $errorstring =
                          genresultString( $prepareUserProfsString, 50,
                            "[ERROR]", "$msgstring" );
                        displayString( 10, 3, $errorstring );
                        return 1;
                    }
                    else {
                        $okstring =
                          genresultString( $prepareUserProfsString, 50,
                            "[OK]" );
                        displayString( 10, 3, $okstring );
                        return 0;
                    }
                }
            }
        }
    }
}

############################################################
#      sub: preparedsmservoptfile
#     desc: prepares the server option file dsmserv.opt, under the
#           DB2 instance directory.
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub preparedsmservoptfile {
    $stpn = shift(@_);

    logentry( "Step ${stpn}_${substep}: Prepare dsmserv.opt file\n", 1 );

    $db2usr                           = $stateHash{db2user};
    $db2grp                           = $stateHash{db2group};
    $instdirmntpnt                    = $stateHash{instdirmountpoint};
    $dsmservopt_after_copy            = "${instdirmntpnt}${SS}dsmserv.opt.smp";
    $dsmservopt_after_copy_and_rename = "${instdirmntpnt}${SS}dsmserv.opt";
    $dsmservopt_after_copy_and_rename_base = "dsmserv.opt";
    $derefProc                             = $stateHash{derefProc};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        system("cp ${serverPath}${SS}dsmserv.opt.smp $instdirmntpnt");
        system("mv $dsmservopt_after_copy $dsmservopt_after_copy_and_rename");
        system("chown ${db2usr}:${db2grp} $dsmservopt_after_copy_and_rename");
    }
    elsif ( $platform eq "WIN32" ) {
        system("copy ${serverPath}${SS}dsmserv.opt.smp $instdirmntpnt >nul");
        system(
            "ren $dsmservopt_after_copy $dsmservopt_after_copy_and_rename_base"
        );
    }

    # Add volume history, device configuration, and numderefproc options

    sleep 1;

    if ( open( DSMSERVOPTH, ">>${dsmservopt_after_copy_and_rename}" ) ) {
        print DSMSERVOPTH "\nDEVCONFIG devconf.dat\n";
        print DSMSERVOPTH "\nDEVCONFIG "
          . $stateHash{dbbackdirpaths}->[0]
          . $SS
          . "devconf.dat\n";
        print DSMSERVOPTH "VOLUMEHISTORY volhist.dat\n";
        print DSMSERVOPTH "VOLUMEHISTORY "
          . $stateHash{dbbackdirpaths}->[0]
          . $SS
          . "volhist.dat\n";
        print DSMSERVOPTH "DEDUPDELETIONTHREADS $derefProc\n";
        if ( $compressFlag == 1 ) {
            print DSMSERVOPTH "\nARCHLOGCOMPRESS Yes\n";
        }

        if ( isGPFS() == 1 ) {
            print DSMSERVOPTH "DIRECTIO NO\n";
            if ( !$legacyFlag ) {
                print DSMSERVOPTH "DIOENABLED NO\n";
            }
            print DSMSERVOPTH "ARCHLOGUSEDTHRESHOLD 99\n";
        }

        close DSMSERVOPTH;
    }
    else {
        logentry(
"        An error occurred when attempting to update the dsmserv.opt file\n"
        );
        my @rcArray = ( 1, "error setting up the dsmserv.opt" );
        return @rcArray;
    }

    my @rcArray = ( 0, "" );
    return @rcArray;
}

############################################################
#      sub: prepareclientoptfiles
#     desc: prepares the IBM Storage Protect API client option files that will
#           be needed for backing up the server database. Also, for
#           server version below 7, the password file (TSM.PWD) is
#           generated using the dsmputil utility. The IBM Storage Protect BA client
#           option files are prepared by this subroutine, for later use
#           when connecting to the IBM Storage Protect server by way of the admin
#           client
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message indicating what failed
#
############################################################

sub prepareclientoptfiles {
    $stpn = shift(@_);
    $tcpp = shift(@_);

    logentry(
"Step ${stpn}_${substep}: Prepare client option files needed for DB backup\n",
        1
    );

    $db2usr                   = $stateHash{db2user};
    $db2grp                   = $stateHash{db2group};
    $instdirmntpnt            = $stateHash{instdirmountpoint};
    $baserverstanzanameprefix = "$stateHash{serverName}" . "_for_Config";

    $pwGenerate = 1;
    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        if ( $serverVersion >= 7 ) {
            $dsm_api_sys = $serverPath . "${SS}dbbkapi${SS}dsm.sys";

# On UNIX platforms beginning with V7, passwordaccess generate should no longer be used for DB backups
            $pwGenerate = 0;
        }
        elsif ( $serverVersion == 6 ) {
            if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
                $dsm_api_sys =
"${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}api${SS}bin64${SS}dsm.sys";
            }
            elsif ( $platform eq "AIX" ) {
                $dsm_api_sys =
"${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}api${SS}bin64${SS}dsm.sys";
            }
        }
        else {
            logentry("        An error occurred locating API dsm.sys file.\n");
            my @rcArray = ( 1, "error local API dsm.sys file" );
            return @rcArray;
        }
    }

    if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
        $dsm_ba_sys =
          "${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin${SS}dsm.sys";
        $dsm_ba_opt_for_config =
"${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin${SS}dsmforconfig.opt";
        $dsm_ba_opt_default =
          "${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin${SS}dsm.opt";
    }
    elsif ( $platform eq "AIX" ) {
        $dsm_ba_sys =
          "${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin64${SS}dsm.sys";
        $dsm_ba_opt_for_config =
"${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin64${SS}dsmforconfig.opt";
        $dsm_ba_opt_default =
          "${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin64${SS}dsm.opt";
    }
    elsif ( $platform eq "WIN32" ) {
        $dsm_ba_opt_for_config = "${baclientPath}${SS}dsmforconfig.opt";
        $dsm_ba_opt_default    = "${baclientPath}${SS}dsm.opt";
    }

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $stateHash{dsmsys}          = $dsm_ba_sys;
        $stateHash{dsmoptforconfig} = $dsm_ba_opt_for_config;
        $stateHash{dsmoptdefault}   = $dsm_ba_opt_default;
    }
    elsif ( $platform eq "WIN32" ) {
        $stateHash{dsmoptforconfig} = $dsm_ba_opt_for_config;
        $stateHash{dsmoptdefault}   = $dsm_ba_opt_default;
    }

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        logentry(
"Step ${stpn}_${substep}: Prepare the API dsm.sys stanza used for DB backup\n",
            1
        );

        if ( open( DSMSYSH, ">>${dsm_api_sys}" ) ) {
            print DSMSYSH "servername TSMDBMGR_${db2usr}\n";
            print DSMSYSH "commmethod tcpip\n";
            print DSMSYSH "tcpserveraddr localhost\n";
            print DSMSYSH "tcpport $tcpp\n";
            if ( $pwGenerate == 1 )    # Only required for V6 servers
            {
                print DSMSYSH "passwordaccess generate\n";
            }
            print DSMSYSH "passworddir $instdirmntpnt\n";
            print DSMSYSH "errorlogname ${instdirmntpnt}${SS}tsmdbmgr.log\n";
            print DSMSYSH "nodename \$\$_TSMDBMGR_\$\$\n";
            close DSMSYSH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the stanza in the API dsm.sys file\n"
            );
            my @rcArray = ( 1, "error creating API dsm.sys stanza" );
            return @rcArray;
        }

        $tsmdbmgr_opt = "${instdirmntpnt}${SS}tsmdbmgr.opt";

        logentry(
"Step ${stpn}_${substep}: Prepare the option file, tsmdbmgr.opt, used for DB backup\n",
            1
        );

        if ( open( TSMDBMGRH, ">${tsmdbmgr_opt}" ) ) {
            print TSMDBMGRH "servername TSMDBMGR_${db2usr}\n";
            close TSMDBMGRH;

            system("chown ${db2usr}:${db2grp} $tsmdbmgr_opt");
        }
        else {
            logentry(
"        An error occurred when attempting to create the tsmdbmgr.opt file\n"
            );
            my @rcArray = ( 1, "error creating tsmdbmgr.opt" );
            return @rcArray;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $tsmdbmgr_opt = "";

# Beginning with SP 818, the db backup option file is stored under the db2instprof un programdata
        if ( $sVersionLong >= 818 ) {
            $db2getinstprofcmd =
              "$db2cmdPath /c /w /i $db2setPath -i $db2usr db2instprof";
            @db2getinstrprofcmdOut = `$db2getinstprofcmd`;

            open( LOGH, ">>$serversetupLog" );
            foreach $outln (@db2getinstrprofcmdOut) {
                chomp($outln);
                while ( $outln !~ m/^\w\:/ ) {
                    $outln = substr( $outln, 1 );
                }
                print LOGH "$outln";

                $tsmdbmgr_opt =
                  $outln . ${SS} . $stateHash{db2user} . ${SS} . "dsm.opt";
            }
            close LOGH;
        }
        else {
            $tsmdbmgr_opt = "${instdirmntpnt}${SS}tsmdbmgr.opt";
        }

        logentry(
"Step ${stpn}_${substep}: Prepare the $tsmdbmgr_opt stanza used for DB backup\n",
            1
        );

        if ( open( TSMDBMGROPTH, ">$tsmdbmgr_opt" ) ) {
            print TSMDBMGROPTH "nodename \$\$_TSMDBMGR_\$\$\n";
            print TSMDBMGROPTH "commmethod tcpip\n";
            print TSMDBMGROPTH "tcpserveraddr localhost\n";
            print TSMDBMGROPTH "tcpport $tcpp\n";
            print TSMDBMGROPTH "passwordaccess generate\n";
            print TSMDBMGROPTH
              "errorlogname ${instdirmntpnt}${SS}tsmdbmgr.log\n";
            close TSMDBMGROPTH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the stanza in $tsmdbmgr_opt\n"
            );
            my @rcArray = ( 1, "error creating tsmdbmgr.opt stanza" );
            return @rcArray;
        }

        $tsmdbmgr_env = "${instdirmntpnt}${SS}tsmdbmgr.env";

        logentry(
"Step ${stpn}_${substep}: Prepare the env file, tsmdbmgr.env, used for DB backup\n",
            1
        );

        if ( open( TSMDBMGRENVH, ">${tsmdbmgr_env}" ) ) {
            print TSMDBMGRENVH
              "DSMI_CONFIG=${instdirmntpnt}${SS}tsmdbmgr.opt\n";
            print TSMDBMGRENVH "DSMI_LOG=${instdirmntpnt}\n";
            close TSMDBMGRENVH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the tsmdbmgr.env file\n"
            );
            my @rcArray = ( 1, "error creating tsmdbmgr.env" );
            return @rcArray;
        }

        $db2setvendorcmd =
"$db2cmdPath /c /w /i $db2setPath -i $db2usr DB2_VENDOR_INI=${tsmdbmgr_env}";
        @db2setvendorcmdOut = `$db2setvendorcmd`;

        open( LOGH, ">>$serversetupLog" );
        foreach $outln (@db2setvendorcmdOut) {
            print LOGH "$outln";
        }
        close LOGH;
    }

    # Generate the API password file

    if (
        ( $pwGenerate == 1 )
        && (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
      )
    {
        logentry(
"Step ${stpn}_${substep}: Generate the API password file used for DB backup\n",
            1
        );

        chdir $instdirmntpnt;

        $dsmputilcmd = "${serverPath}${SS}dsmputil TSMDBMGR_${db2usr}";

        @dsmputilOut = `$dsmputilcmd`;

        chdir $currentdir;
    }
    elsif ( $platform eq "WIN32" ) {
        $db2stopstartcmdfile = "${instdirmntpnt}${SS}db2stopstart.bat";
        $stateHash{db2stopstartcmdfile} = $db2stopstartcmdfile;

        if ( open( DB2STOPSTARTH, ">$db2stopstartcmdfile" ) ) {
            print DB2STOPSTARTH "\@echo off\n";
            print DB2STOPSTARTH "set db2instance=${db2usr}\n";
            print DB2STOPSTARTH "$db2cmdPath /c /w /i $db2stopPath\n";
            print DB2STOPSTARTH "$db2cmdPath /c /w /i $db2startPath\n";
            close DB2STOPSTARTH;
        }

        @db2stopstartcmdfileOut = `$db2stopstartcmdfile`;

        open( LOGH, ">>$serversetupLog" );
        foreach $outln (@db2stopstartcmdfileOut) {
            print LOGH "$outln";
        }
        close LOGH;

        sleep 2;

# Beginning with IBM Storage Protect 812, we no longer need to use dsmsutil.exe to store a DB backup password
        if ( $stateHash{serverVersionLong} < 812 ) {
            $updatepwcommand =
"${serverPath}${SS}dsmsutil.exe UPDATEPW /NODE:\$\$_TSMDBMGR_\$\$ /PASSWORD:TSMDBMGR /VALIDATE:NO /OPTFILE:$tsmdbmgr_opt";
            @updatepwcommandOut = `$updatepwcommand`;
        }

        open( LOGH, ">>$serversetupLog" );
        foreach $outln (@updatepwcommandOut) {
            print LOGH "$outln";
        }
        close LOGH;
    }

   # Generate the BA client dsm.sys file so as to be able to connect via DSMADMC

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        logentry(
"Step ${stpn}_${substep}: Prepare the BA dsm.sys stanza used for connecting to the server by way of the admin client\n",
            1
        );

        if ( -f $dsm_ba_sys ) {
            if ( open( DSMSYSH, "<${dsm_ba_sys}" ) ) {
                @dsmsysbacontents = <DSMSYSH>;
                close DSMSYSH;
            }
            else {
                logentry(
"        An error occurred when attempting to prepare the stanza in the BA dsm.sys file to use for dsmadmc\n"
                );
                my @rcArray = ( 1, "error preparing BA dsm.sys stanza" );
                return @rcArray;
            }

            # Find a stanza name not already in use

            $configstanzanum = 1;

            do {
                $configstanzafound = 0;

                $configstanzaname =
                  "$baserverstanzanameprefix" . "_" . "$configstanzanum";

                foreach $dsmbasysline (@dsmsysbacontents) {
                    if ( $dsmbasysline =~
                        m/^\s*servername\s+$configstanzaname/i )
                    {
                        $configstanzafound = 1;
                    }
                }
                $configstanzanum++;
            } while ( $configstanzafound == 1 );

            $baserverstanzaname = $configstanzaname
              ; # this is the stanza name to be used for connecting to the server using DSMADMC

        }
        else {
            $baserverstanzaname = "$baserverstanzanameprefix" . "_1"
              ; # this is the stanza name to be used for connecting to the server using DSMADMC
        }

        if ( open( DSMSYSH, ">>${dsm_ba_sys}" ) ) {
            print DSMSYSH "\n\nservername $baserverstanzaname\n";
            print DSMSYSH "commmethod tcpip\n";
            print DSMSYSH "tcpserveraddr localhost\n";
            print DSMSYSH "tcpport $tcpp\n";
            close DSMSYSH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the stanza in the BA dsm.sys file\n"
            );
            my @rcArray = ( 1, "error creating BA dsm.sys stanza" );
            return @rcArray;
        }

        logentry(
"Step ${stpn}_${substep}: Prepare the BA dsm.opt file used for connecting to the server by way of the admin client\n",
            1
        );

        if ( open( DSMOPTH, ">>${dsm_ba_opt_for_config}" ) ) {
            print DSMOPTH "servername $baserverstanzaname\n";
            close DSMOPTH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the dsm.opt file\n"
            );
            my @rcArray = ( 1, "error creating dsm.opt file" );
            return @rcArray;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        logentry(
"Step ${stpn}_${substep}: Prepare the BA dsm.opt file used for connecting to the server by way of the admin client\n",
            1
        );

        if ( open( DSMOPTH, ">>${dsm_ba_opt_for_config}" ) ) {
            print DSMOPTH "commmethod tcpip\n";
            print DSMOPTH "tcpserveraddr localhost\n";
            print DSMOPTH "tcpport $tcpp\n";
            close DSMOPTH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the dsm.opt file\n"
            );
            my @rcArray = ( 1, "error creating dsm.opt file" );
            return @rcArray;
        }
    }
    my @rcArray = ( 0, "" );
    return @rcArray;
}

############################################################
#      sub: preparedb2commandfiles
#     desc: prepares some command files that later will need to be
#           run as the DB2 owner account. These include the following
#           commands: the command to set the DB2 instance directory, the
#           command to set the DB2 code page, the command to list
#           db directory, and to create the commands that will be
#           needed for formatting the server, adjusting the DB2 locklist
#           parameter and starting the server for initial configuration
#           by way of a runfile argument
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message pointing to the script log
#
############################################################

sub preparedb2commandfiles {
    $stpn = shift(@_);

    $crsetinstdircmdfilerc = preparesetdb2instdircmdfile($stpn);

    if ( $crsetinstdircmdfilerc == 1 ) {
        my @rcArray = ( 1, "see log $stateHash{logname}" );
        return @rcArray;
    }
    else {
        $crsetdb2codepgcmdfilerc = preparesetdb2codepagecmdfile($stpn);
        if ( $crsetdb2codepgcmdfilerc == 1 ) {
            my @rcArray = ( 1, "see log $stateHash{logname}" );
            return @rcArray;
        }
        else {
            $crlistdbdircmdfilerc = preparedb2listdbdircmdfile($stpn);
            if ( $crlistdbdircmdfilerc == 1 ) {
                my @rcArray = ( 1, "see log $stateHash{logname}" );
                return @rcArray;
            }
            else {
                $prepareformatscriptrc = prepareformatscript($stpn);
                if ( $prepareformatscriptrc == 1 ) {
                    my @rcArray = ( 1, "see log $stateHash{logname}" );
                    return @rcArray;
                }
                else {
                    $crsetlocklistcmdfilerc = preparesetlocklistcmdfile($stpn);
                    if ( $crsetlocklistcmdfilerc == 1 ) {
                        my @rcArray = ( 1, "see log $stateHash{logname}" );
                        return @rcArray;
                    }
                    else {
                        $preparestartscriptrc = prepareserverstartscript($stpn);
                        if ( $preparestartscriptrc == 1 ) {
                            my @rcArray = ( 1, "see log $stateHash{logname}" );
                            return @rcArray;
                        }
                        else {
                            my @rcArray = ( 0, "" );
                            return @rcArray;
                        }
                    }
                }
            }
        }
    }
}

############################################################
#      sub: preparesetdb2instdircmdfile
#     desc: prepares the command file that will be later used
#           set the DB2 instance directory
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is an error creating the command file
#
############################################################

sub preparesetdb2instdircmdfile {
    $stpn = shift(@_);

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        logentry(
"Step ${stpn}_${substep}: Prepare command file to set the server instance directory\n",
            1
        );
    }
    elsif ( $platform eq "WIN32" ) {
        logentry(
"Step ${stpn}_${substep}: Prepare command file to set the server instance location\n",
            1
        );
    }

    $db2usr        = $stateHash{db2user};
    $db2grp        = $stateHash{db2group};
    $instdirmntpnt = $stateHash{instdirmountpoint};
    $db2homedir    = $stateHash{db2home};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $setinstdircmdfile = "${db2homedir}${SS}setinstdircmdfile";
        $stateHash{setinstdircmdfile} = $setinstdircmdfile;

        $setinstdircmd = "db2 update dbm cfg using dftdbpath $instdirmntpnt";

        if ( open( SETINSTDIRH, ">$setinstdircmdfile" ) ) {
            print SETINSTDIRH "$setinstdircmd\n";
            close SETINSTDIRH;

            system("chown ${db2usr}:${db2grp} $setinstdircmdfile");
            system("chmod u+x $setinstdircmdfile");
        }
        else {
            logentry(
"        An error occurred when attempting to create the command file to set the server instance directory\n"
            );
            return 1;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $setinstdircmdfile = "${instdirmntpnt}${SS}setinstdircmdfile.bat";
        $stateHash{setinstdircmdfile} = $setinstdircmdfile;

        # extract the drive letter from the server instance directory

        $instdirfirstdelimiterpos = index( $instdirmntpnt, "$SS" );
        $instdirlocation =
          substr( $instdirmntpnt, 0, $instdirfirstdelimiterpos );

        $setinstdircmd =
          "$db2exePath update dbm cfg using dftdbpath $instdirlocation";

        if ( open( SETINSTDIRH, ">$setinstdircmdfile" ) ) {
            print SETINSTDIRH "\@echo off\n";
            print SETINSTDIRH "set db2instance=${db2usr}\n";
            print SETINSTDIRH "$db2cmdPath /c /w /i $setinstdircmd\n";
            close SETINSTDIRH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the command file to set the server instance location\n"
            );
            return 1;
        }

    }

    return 0;
}

############################################################
#      sub: preparesetdb2codepagecmdfile
#     desc: prepares the command file that will be later used
#           set the DB2 code page (to 819)
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is an error creating the command file
#
############################################################

sub preparesetdb2codepagecmdfile {
    $stpn = shift(@_);

    logentry(
        "Step ${stpn}_${substep}: Prepare command file to set db2 code page\n",
        1
    );

    $db2usr        = $stateHash{db2user};
    $db2grp        = $stateHash{db2group};
    $instdirmntpnt = $stateHash{instdirmountpoint};
    $db2homedir    = $stateHash{db2home};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $setdb2codepagecmdfile = "${db2homedir}${SS}setdb2codepagecmdfile";
        $stateHash{setdb2codepagecmdfile} = $setdb2codepagecmdfile;

        $setdb2codepagecmd = "db2set -i $db2usr DB2CODEPAGE=819";

        if ( open( SETDB2CPGH, ">$setdb2codepagecmdfile" ) ) {
            print SETDB2CPGH "$setdb2codepagecmd\n";
            close SETDB2CPGH;

            system("chown ${db2usr}:${db2grp} $setdb2codepagecmdfile");
            system("chmod u+x $setdb2codepagecmdfile");
        }
        else {
            logentry(
"        An error occurred when attempting to create the command file to set the DB2 codepage\n"
            );
            return 1;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $setdb2codepagecmdfile =
          "${instdirmntpnt}${SS}setdb2codepagecmdfile.bat";
        $stateHash{setdb2codepagecmdfile} = $setdb2codepagecmdfile;

        $setdb2codepagecmd =
          "$db2cmdPath /c /w /i $db2setPath -i $db2usr DB2CODEPAGE=819";

        if ( open( SETDB2CPGH, ">$setdb2codepagecmdfile" ) ) {
            print SETDB2CPGH "\@echo off\n";
            print SETDB2CPGH "$setdb2codepagecmd\n";
            close SETDB2CPGH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the command file to set the DB2 codepage\n"
            );
            return 1;
        }
    }
    return 0;
}

############################################################
#      sub: preparedb2listdbdircmdfile
#     desc: prepares the command file that will be later used
#           to list db directory (needed later, just
#           before kicking off the command to format the server
#           to make sure the TSMDB1 database does not already exist)
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is an error creating the command file
#
############################################################

sub preparedb2listdbdircmdfile {
    $stpn = shift(@_);

    logentry(
        "Step ${stpn}_${substep}: Prepare command file to list db directory\n",
        1
    );

    $db2usr        = $stateHash{db2user};
    $db2grp        = $stateHash{db2group};
    $instdirmntpnt = $stateHash{instdirmountpoint};
    $db2homedir    = $stateHash{db2home};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $listdbdircmdfile = "${db2homedir}${SS}listdbdircmdfile";
        $stateHash{listdbdircmdfile} = $listdbdircmdfile;

        $listdbdircmd = "db2 list db directory";

        if ( open( LISTDBDIRH, ">$listdbdircmdfile" ) ) {
            print LISTDBDIRH "$listdbdircmd\n";
            close LISTDBDIRH;

            system("chown ${db2usr}:${db2grp} $listdbdircmdfile");
            system("chmod u+x $listdbdircmdfile");
        }
        else {
            logentry(
"        An error occurred when attempting to create the command file to list db directory\n"
            );
            return 1;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $listdbdircmdfile = "${instdirmntpnt}${SS}listdbdircmdfile.bat";
        $stateHash{listdbdircmdfile} = $listdbdircmdfile;

        $listdbdircmd = "$db2exePath list db directory";

        if ( open( LISTDBDIRH, ">$listdbdircmdfile" ) ) {
            print LISTDBDIRH "\@echo off\n";
            print LISTDBDIRH "set db2instance=${db2usr}\n";
            print LISTDBDIRH "$db2cmdPath /c /w /i $listdbdircmd\n"
              ;    # not sure about this, but need to see the output
            close LISTDBDIRH;
        }
        else {
            logentry(
"        An error occurred when attempting to create the command file to list db directory\n"
            );
            return 1;
        }
    }
    return 0;
}

############################################################
#      sub: prepareformatscript
#     desc: prepares the command file (script) that will be used
#           to format the server
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is an error creating the command file
#
############################################################

sub prepareformatscript {
    $stpn = shift(@_);

    logentry( "Step ${stpn}_${substep}: Prepare dsmserv format command file\n",
        1 );

    $db2usr            = $stateHash{db2user};
    $db2grp            = $stateHash{db2group};
    $instdirmntpnt     = $stateHash{instdirmountpoint};
    $actlogpth         = $stateHash{actlogpath};
    $archlogpth        = $stateHash{archlogpath};
    $archlogfailpth    = $stateHash{dbbackdirpaths}->[0];
    $dbdirpths         = $stateHash{dbdirpaths};
    $actlogsize        = $stateHash{actlogsize};
    $initialactlogsize = $stateHash{initactlogsize};
    @mntPntDB          = qw();

    $dsmservopt = "${instdirmntpnt}${SS}dsmserv.opt";
    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $dsmformatcmdfile = "${instdirmntpnt}${SS}dsmformatcmd";
    }
    elsif ( $platform eq "WIN32" ) {
        $dsmformatcmdfile = "${instdirmntpnt}${SS}dsmformatcmd.bat";
    }
    $stateHash{dsmformatcmdfile} = $dsmformatcmdfile;

    $firstpath = 1;

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $formatcmd =
"${serverPath}${SS}dsmserv -o $dsmservopt -i $instdirmntpnt format dbdir=";
    }
    elsif ( $platform eq "WIN32" ) {
        $donefile = "${instdirmntpnt}${SS}donefile.txt";

        $formatcmd =
          "${serverPath}${SS}dsmserv -k $db2usr -o $dsmservopt format dbdir=";
    }
    foreach $p ( @{$dbdirpths} ) {
        if ( $firstpath == 1 ) {
            $formatcmd = "$formatcmd" . "$p";
            $firstpath = 0;
        }
        else {
            $formatcmd = "$formatcmd" . ",${p}";
        }
        push( @mntPntDB, $p );
    }
    if ( ( $platform eq "WIN32" ) || ( $serverVersion >= 7 ) ) {
        $formatcmd = "$formatcmd"
          . " activelogsize=${initialactlogsize} activelogdir=$actlogpth archlogdir=$archlogpth archfailoverlogdir=$archlogfailpth";
    }
    else {
        $formatcmd = "$formatcmd"
          . " activelogsize=${actlogsize} activelogdir=$actlogpth archlogdir=$archlogpth archfailoverlogdir=$archlogfailpth";
    }

    if ( $platform eq "WIN32" ) {
        $serversetupLogfull = "$currentdir" . "${SS}" . "$serversetupLog";
        $formatcmd          = "$formatcmd" . " >> \"$serversetupLogfull\"";
    }

    if ( open( FRMTH, ">$dsmformatcmdfile" ) ) {
        if ( $platform eq "WIN32" ) {
            print FRMTH "\@echo off\n";

   # On Windows, there is an error formatting newly defined mountpoints
   # Creating a dummy file in the DB/LOG directories prior to format avoids this
   # Commenting out due to deletion not always taking effect before format
   #foreach $mPnt (@mntPntDB,$actlogpth,$archlogfailpth)
   #{
   #print FRMTH "echo dummy > $mPnt${SS}TSMbp_dummyfile\n";
   #print FRMTH "del $mPnt${SS}TSMbp_dummyfile\n";
   #}
   #print FRMTH "echo dummy > $archlogpth${SS}TSMbp_dummyfile\n";

            print FRMTH "set PATH=%PATH%;$db2Path${SS}bin\n"
              ;    # add db2 path in case it is not in the environment
        }
        print FRMTH "$formatcmd\n";
        if ( $platform eq "WIN32" ) {

            # clean up the dummy files
            #print FRMTH "del $archlogpth${SS}TSMbp_dummyfile\n";

            print FRMTH "echo formatcomplete > ${donefile}\n";
        }
        close FRMTH;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            system("chown ${db2usr}:${db2grp} $dsmformatcmdfile");
            system("chmod u+x $dsmformatcmdfile");
        }
    }
    else {
        logentry(
"        An error occurred when attempting to create the dsmserv format script\n"
        );
        return 1;
    }
    return 0;
}

############################################################
#      sub: preparesetlocklistcmdfile
#     desc: prepares the command file (script) that will be used
#           to set the db2 locklist parameter to a value appropriate
#           to the server scale
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is an error creating the command file
#
############################################################

sub preparesetlocklistcmdfile {
    $stpn = shift(@_);

    logentry(
"Step ${stpn}_${substep}: Prepare command file issue DB2 configuration commands\n",
        1
    );

    $db2usr        = $stateHash{db2user};
    $db2grp        = $stateHash{db2group};
    $instdirmntpnt = $stateHash{instdirmountpoint};
    $db2homedir    = $stateHash{db2home};
    $sVersionLong  = $stateHash{serverVersionLong};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $setdb2locklistcmdfile = "${db2homedir}${SS}setdb2locklistcmdfile";
    }
    elsif ( $platform eq "WIN32" ) {
        $setdb2locklistcmdfile =
          "${instdirmntpnt}${SS}setdb2locklistcmdfile.bat";
    }
    $setdb2locklistsqlfile = "${instdirmntpnt}${SS}setdb2locklist.sql";
    $stateHash{setdb2locklistcmdfile} = $setdb2locklistcmdfile;
    $stateHash{setdb2locklistsqlfile} = $setdb2locklistsqlfile;

    # Set manual DB/2 locklist settings if the -locklist option was specified
    if ( $locklistFlag == 1 || $legacyFlag == 1 ) {
        logentry("        Manually setting DB2 locklist values\n");
        $locklistvalue = $stateHash{locklist};
        $setdb2locklistcmd =
          "update db cfg for TSMDB1 using locklist $locklistvalue immediate";
    }
    else {
        logentry("        Using automatic DB2 locklist management\n");
        $setdb2locklistcmd = "";
    }

    if ( open( SETDB2LLSQLH, ">$setdb2locklistsqlfile" ) ) {
        print SETDB2LLSQLH "connect to TSMDB1;\n";

        if ( $platform eq "WIN32" ) {
            logentry(
"        Granting access to Windows system account for service to interact with DB2\n"
            );
            print SETDB2LLSQLH
"grant dbadm with dataaccess with accessctrl on database to user system;\n";
            print SETDB2LLSQLH "grant secadm on database to user system;\n";
        }

        print SETDB2LLSQLH "${setdb2locklistcmd};\n";

        print SETDB2LLSQLH "terminate;\n";
        close SETDB2LLSQLH;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            system("chown ${db2usr}:${db2grp} $setdb2locklistsqlfile");
        }
    }
    else {
        logentry(
"        An error occurred when attempting to create the sql file to set the DB2 locklist\n"
        );
        return 1;
    }

    if ( open( SETDB2LLCMDH, ">$setdb2locklistcmdfile" ) ) {

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            print SETDB2LLCMDH "db2start\n";
            print SETDB2LLCMDH "db2 -tf $setdb2locklistsqlfile\n";
            print SETDB2LLCMDH "db2stop\n";
        }
        elsif ( $platform eq "WIN32" ) {
            print SETDB2LLCMDH "\@echo off\n";
            print SETDB2LLCMDH "set db2instance=${db2usr}\n";
            print SETDB2LLCMDH "$db2cmdPath /c /w /i $db2startPath\n";
            print SETDB2LLCMDH
              "$db2cmdPath /c /w /i $db2exePath -tf $setdb2locklistsqlfile\n";
            print SETDB2LLCMDH "$db2cmdPath /c /w /i $db2stopPath\n";
        }

        close SETDB2LLCMDH;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            system("chown ${db2usr}:${db2grp} $setdb2locklistcmdfile");
            system("chmod u+x $setdb2locklistcmdfile");
        }
    }
    else {
        logentry(
"       An error occurred when attempting to create the command file to set the DB2 locklist\n"
        );
        return 1;
    }

    return 0;
}

############################################################
#      sub: setreorgflag
#     desc: Runs a DB2 command file (script) that is used to
#           set a global attribute preventing automatic
#           updating of reorg options introduced by APAR IC95301.
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is an error creating the command file
#
############################################################

sub setreorgflag {
    $stpn = shift(@_);

    logentry(
"Step ${stpn}_${substep}: Prepare command file to set IBM Storage Protect reorg attribute\n",
        1
    );

    $db2usr        = $stateHash{db2user};
    $db2grp        = $stateHash{db2group};
    $instdirmntpnt = $stateHash{instdirmountpoint};
    $db2homedir    = $stateHash{db2home};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $setdb2attribcmdfile = "${db2homedir}${SS}setdb2attribcmdfile";
    }
    elsif ( $platform eq "WIN32" ) {
        $setdb2attribcmdfile = "${instdirmntpnt}${SS}setdb2attribcmdfile.bat";
    }
    $setdb2attribsqlfile            = "${instdirmntpnt}${SS}setdb2attrib.sql";
    $stateHash{setdb2attribcmdfile} = $setdb2attribcmdfile;
    $stateHash{setdb2attribsqlfile} = $setdb2attribsqlfile;

    if ( open( SETDB2LLSQLH, ">$setdb2attribsqlfile" ) ) {
        print SETDB2LLSQLH "connect to TSMDB1;\n";

# Block the automatic dsmserv.opt update for reorg options introduced by APAR IC95301
        $setreorgattribcmd =
"insert into TSMDB1.global_attributes (owner,name,type,length,int32) values('RDB','REORG_ONETIME_AUTO_INIT',3,0,2)";
        print SETDB2LLSQLH "${setreorgattribcmd};\n";

        print SETDB2LLSQLH "terminate;\n";
        close SETDB2LLSQLH;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            system("chown ${db2usr}:${db2grp} $setdb2attribsqlfile");
        }
    }
    else {
        logentry(
"        An error occurred when attempting to create the sql file to set the IBM Storage Protect reorg attrib\n"
        );
        return 1;
    }

    if ( open( SETDB2LLCMDH, ">$setdb2attribcmdfile" ) ) {

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            print SETDB2LLCMDH "db2start\n";
            print SETDB2LLCMDH "db2 -tf $setdb2attribsqlfile\n";
            print SETDB2LLCMDH "db2stop\n";
        }
        elsif ( $platform eq "WIN32" ) {
            print SETDB2LLCMDH "\@echo off\n";
            print SETDB2LLCMDH "set db2instance=${db2usr}\n";
            print SETDB2LLCMDH "$db2cmdPath /c /w /i $db2startPath\n";
            print SETDB2LLCMDH
              "$db2cmdPath /c /w /i $db2exePath -tf $setdb2attribsqlfile\n";
            print SETDB2LLCMDH "$db2cmdPath /c /w /i $db2stopPath\n";
        }

        close SETDB2LLCMDH;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            system("chown ${db2usr}:${db2grp} $setdb2attribcmdfile");
            system("chmod u+x $setdb2attribcmdfile");
        }
    }
    else {
        logentry(
"       An error occurred when attempting to create the command file to set the IBM Storage Protect reorg attrib\n"
        );
        return 1;
    }

    logentry(
"Step ${stpn}_${substep}: Set the IBM Storage Protect flag to avoid automatic setting of reorg options\n",
        1
    );

    logentry(
        "        As DB2 instance owner, issuing command: $setreorgattribcmd\n");

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $setdb2attribcmd = "su - $db2usr $setdb2attribcmdfile";
    }
    elsif ( $platform eq "WIN32" ) {
        $setdb2attribcmd = $setdb2attribcmdfile;
    }

    @setdb2attribcmdOut = `$setdb2attribcmd`;
    $setdb2attribrc     = $?;

    if ( $setdb2attribrc == 0 ) {
        my @rcArray = ( 0, "" );
        return @rcArray;
    }
    else {
        logentry(
"        An error occurred when attempting to set the IBM Storage Protect global reorg attrib\n"
        );
        my @rcArray =
          ( 1, "error setting the IBM Storage Protect global reorg attrib" );
        return @rcArray;
    }
}

############################################################
#      sub: prepareserverstartscript
#     desc: prepares the command file (script) that will be used
#           to startup the server with a runfile argument to set
#           fundamental server parameters
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is an error creating the command file
#
############################################################

sub prepareserverstartscript {
    $stpn = shift(@_);

    logentry(
        "Step ${stpn}_${substep}: Prepare command file to start the server\n",
        1 );

    $db2usr        = $stateHash{db2user};
    $db2grp        = $stateHash{db2group};
    $instdirmntpnt = $stateHash{instdirmountpoint};

    $dsmservopt = "${instdirmntpnt}${SS}dsmserv.opt";

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $startservercmdfile = "${instdirmntpnt}${SS}startservercmd";
    }
    elsif ( $platform eq "WIN32" ) {
        $startservercmdfile = "${instdirmntpnt}${SS}startservercmd.bat";
    }
    $stateHash{startservercmdfile} = $startservercmdfile;

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $startcmd =
"${serverPath}${SS}dsmserv -o $dsmservopt -i $instdirmntpnt runfile \"$runfilename\"";
    }
    elsif ( $platform eq "WIN32" ) {
        $startcmd =
"${serverPath}${SS}dsmserv -k $db2usr -o $dsmservopt runfile \"$runfilename\"";
    }

    if ( open( STRTH, ">$startservercmdfile" ) ) {
        if ( $platform eq "WIN32" ) {
            print STRTH "\@echo off\n";
            print STRTH "set PATH=%PATH%;$db2Path${SS}bin\n"
              ;    # add the db2 environment in case it is not there
        }
        print STRTH "$startcmd\n";
        close STRTH;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            system("chown ${db2usr}:${db2grp} $startservercmdfile");
            system("chmod u+x $startservercmdfile");
        }
    }
    else {
        logentry(
"        An error occurred when attempting to create the script to start the server\n"
        );
        return 1;
    }

    return 0;
}

############################################################
#      sub: setdb2InstParameters
#     desc: Invokes a series of subroutines which, using previously
#           created command files or scripts, perform the following
#           tasks: set the DB2 instance directory, set the DB2 code
#           page, and list db directory
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if there is a failure
#
############################################################

sub setdb2InstParameters {
    $stpn = shift(@_);

    ( $setinstdirrc, $msgstring ) = setdb2instdir($stpn);

    if ( $setinstdirrc == 1 ) {
        $errorstring =
          genresultString( $setDB2InstParametersString, 50, "[ERROR]",
            "$msgstring" );
        displayString( 10, 3, $errorstring );
        return 1;
    }
    else {
        ( $setcodepagerc, $msgstring ) = setdb2codepage($stpn);

        if ( $setcodepagerc == 1 ) {
            $errorstring =
              genresultString( $setDB2InstParametersString, 50, "[ERROR]",
                "$msgstring" );
            displayString( 10, 3, $errorstring );
            return 1;
        }
        else {
            ( $listdbdirrc, $msgstring ) = listdbdirectory($stpn);

            if ( $listdbdirrc == 1 ) {
                $errorstring =
                  genresultString( $setDB2InstParametersString, 50, "[ERROR]",
                    "$msgstring" );
                displayString( 10, 3, $errorstring );
                return 1;
            }
            else {
                $okstring =
                  genresultString( $setDB2InstParametersString, 50, "[OK]" );
                displayString( 10, 3, $okstring );
                return 0;
            }
        }
    }
}

############################################################
#      sub: setdb2instdir
#     desc: As the DB2 user, issues (using the already prepared
#           command file to set the db2 instance directory) the
#           command to set the db2 instance directory.
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub setdb2instdir {
    $stpn = shift(@_);

    logentry( "Step ${stpn}_${substep}: Set the DB2 instance directory\n", 1 );

    $db2usr = $stateHash{db2user};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $setinstdircmdfile = "setinstdircmdfile";

        logentry(
            "        As DB2 instance owner, issuing command: $setinstdircmd\n");

        $setinstdircmd = "su - $db2usr $setinstdircmdfile";

        $setinstdirrc = 1;

        @setinstdircmdOut = `$setinstdircmd`;

        foreach $outln (@setinstdircmdOut) {
            if ( $outln =~ m/DB20000I/i )    #success
            {
                $setinstdirrc = 0;
            }
        }

        if ( $setinstdirrc == 0 ) {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
        else {
            logentry(
"        An error occurred when attempting to set the DB2 instance directory\n"
            );
            my @rcArray = ( 1, "error setting the DB2 instance directory" );
            return @rcArray;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $setinstdircmdfile = $stateHash{setinstdircmdfile};

        logentry("        Issuing command: $setinstdircmd\n");

        $setinstdirrc = 1;

        @setinstdirOut = `$setinstdircmdfile`;

        open( LOGH, ">>$serversetupLog" );
        foreach $outln (@setinstdirOut) {
            print LOGH "$outln";
            if ( $outln =~ m/DB20000I/i )    # success
            {
                $setinstdirrc = 0;
            }
        }
        close LOGH;

        if ( $setinstdirrc == 0 ) {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
        else {
            logentry(
"        An error occurred when attempting to set the DB2 instance directory\n"
            );
            my @rcArray = ( 1, "error setting the DB2 instance directory" );
            return @rcArray;
        }
    }
}

############################################################
#      sub: createWinService
#     desc: Creates the Windows service to run the IBM Storage Protect server
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub createWinService {
    $stpn = shift(@_);

    logentry(
"Step ${stpn}_${substep}: Create the Windows service to run the IBM Storage Protect server\n",
        1
    );

    $db2usr     = $stateHash{db2user};
    $dsmservopt = "${instdirmntpnt}${SS}dsmserv.opt";

    $installTSMserviceCmd =
"sc create \"TSM server_${db2usr}\" binPath= \"${serverPath}${SS}dsmsvc.exe -k $db2usr -o $dsmservopt\" start= auto";

    logentry("        Issuing command: $installTSMserviceCmd\n");

    $createTSMservicerc = 1;

    @installTSMserviceOut = `$installTSMserviceCmd`;
    $createTSMservicerc   = $?;

    if ( $createTSMservicerc == 0 ) {
        $descriptionTSMserviceCmd =
"sc description \"TSM server_${db2usr}\" \"IBM Storage Protect Server\"";
        `$descriptionTSMserviceCmd`;

        my @rcArray = ( 0, "" );
        return @rcArray;
    }
    else {
        logentry(
"        An error occurred when attempting to create the Windows service to run the IBM Storage Protect server\n"
        );
        my @rcArray = ( 1, "error creating Windows service" );
        return @rcArray;
    }
}

############################################################
#      sub: setdb2locklist
#     desc: As the DB2 user, issues (using the already prepared
#           command file) the DB2 lock list parameter appropriate
#           for the specified server scale
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub setdb2locklist {
    $stpn = shift(@_);

    logentry( "Step ${stpn}_${substep}: Set the DB2 locklist parameter\n", 1 );

    $db2usr = $stateHash{db2user};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $setdb2locklistcmdfile = "setdb2locklistcmdfile";

        logentry(
"        As DB2 instance owner, issuing command: $setdb2locklistcmd\n"
        );

        $setdb2locklistcmd = "su - $db2usr $setdb2locklistcmdfile";

        $setdb2locklistrc = 1;

        @setdb2locklistcmdOut = `$setdb2locklistcmd`;

        foreach $outln (@setdb2locklistcmdOut) {
            if ( $outln =~ m#\"MAXLOCKS\"\s+has\s+been\s+set\s+to\s+\"MANUAL\"#i
                || $outln =~
m#The UPDATE DATABASE CONFIGURATION command completed successfully.#i
              )
            {
                $setdb2locklistrc = 0;
            }
        }

        if ( $setdb2locklistrc == 0
            || ( $locklistFlag == 0 && $legacyFlag == 0 ) )
        {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
        else {
            logentry(
"        An error occurred when attempting to set the DB2 locklist parameter for TSMDB1\n"
            );
            my @rcArray = ( 1, "error setting the DB2 locklist" );
            return @rcArray;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $setdb2locklistcmdfile = $stateHash{setdb2locklistcmdfile};

        logentry(
"        Issuing command: db2 grant dbadm with dataaccess with accessctrl on database to user system\n"
        );
        logentry(
"        Issuing command: db2 grant secadm on database to user system\n"
        );
        logentry("        Issuing command: db2 $setdb2locklistcmd\n");

        $setdb2locklistrc = 1;

        @setdb2locklistcmdOut = `$setdb2locklistcmdfile`;

        open( LOGH, ">>$serversetupLog" );

        $numsuccessfulSQLcmds = 0;

        foreach $outln (@setdb2locklistcmdOut) {
            print LOGH "$outln";
            if ( $outln =~ m#\"MAXLOCKS\"\s+has\s+been\s+set\s+to\s+\"MANUAL\"#i
                || $outln =~ m#DB20000I#i )    #success
            {
                $setdb2locklistrc = 0;
                $numsuccessfulSQLcmds++;
            }
        }

        close LOGH;

        if (
            ( $numsuccessfulSQLcmds >= 2 && $setdb2locklistrc == 0 )
            || (   $numsuccessfulSQLcmds >= 2
                && $locklistFlag == 0
                && $legacyFlag == 0 )
          )
        {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
        elsif ( $numsuccessfulSQLcmds < 2 ) {
            logentry(
"        An error occurred when attempting to enable the local system account\n"
            );
            my @rcArray = ( 1, "error enabling system account" );
            return @rcArray;
        }
        else {
            logentry(
"        An error occurred when attempting to set the DB2 locklist parameter for TSMDB1\n"
            );
            my @rcArray = ( 1, "error setting the DB2 locklist" );
            return @rcArray;
        }
    }
}

############################################################
#      sub: setdb2codepage
#     desc: As the DB2 user, issues (using the already prepared
#           command file to set the db2 code page) the
#           command to set the db2 code page.
#
#   params: 1. the step number
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub setdb2codepage {
    $stpn = shift(@_);

    logentry( "Step ${stpn}_${substep}: Set the DB2 code page\n", 1 );

    $db2usr = $stateHash{db2user};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $setdb2codepagecmdfile = "setdb2codepagecmdfile";

        logentry(
"        As DB2 instance owner, issuing command: $setdb2codepagecmd\n"
        );

        $setdb2codepagecmd = "su - $db2usr $setdb2codepagecmdfile";

        @setdb2codepagecmdOut = `$setdb2codepagecmd`;

        my @rcArray = ( 0, "" );
        return @rcArray;
    }
    elsif ( $platform eq "WIN32" ) {
        $setdb2codepagecmdfile = $stateHash{setdb2codepagecmdfile};

        logentry("        Issuing command: $setdb2codepagecmd\n");

        @setdb2codepageOut = `$setdb2codepagecmdfile`;

        open( LOGH, ">>$serversetupLog" );
        foreach $outln (@setdb2codepageOut) {
            print LOGH "$outln";
        }
        close LOGH;

        my @rcArray = ( 0, "" );
        return @rcArray;
    }
}

############################################################
#      sub: listdbdirectory
#     desc: As the DB2 user, issues (using the already prepared
#           command file to list db directory) the command to
#           list the db directory.
#
#   params: 1. the step number
#  returns: an array consisting of a return code (0 if TSMDB1 does
#           not already exist, 1 if it does) along with a suitable
#           message in the latter case
#
############################################################

sub listdbdirectory {
    $stpn = shift(@_);

    logentry(
"Step ${stpn}_${substep}: Make sure that TSMDB1 does not already exist\n",
        1
    );

    $foundpreexistingTSMDB1 = 0;

    $db2usr = $stateHash{db2user};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $listdbdircmdfile = "listdbdircmdfile";

        logentry(
            "        As DB2 instance owner, issuing command: $listdbdircmd\n");

        $listdbdircmd = "su - $db2usr $listdbdircmdfile";

        @listdbdircmdOut = `$listdbdircmd`;

        foreach $listdbdirlne (@listdbdircmdOut) {
            if ( $listdbdirlne =~ m/Database\s+name\s+=\s+TSMDB1/ ) {
                $foundpreexistingTSMDB1 = 1;
            }
        }

        if ( $foundpreexistingTSMDB1 == 0 ) {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
        else {
            logentry("        TSMDB1 already exists\n");
            my @rcArray = ( 1, "TSMDB1 already exists" );
            return @rcArray;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $listdbdircmdfile = $stateHash{listdbdircmdfile};

        logentry("        Issuing command: $listdbdircmd\n");

        @listdbdircmdOut = `$listdbdircmdfile`;

        foreach $listdbdirlne (@listdbdircmdOut) {
            if ( $listdbdirlne =~ m/Database\s+name\s+=\s+TSMDB1/ ) {
                $foundpreexistingTSMDB1 = 1;
            }
        }

        if ( $foundpreexistingTSMDB1 == 0 ) {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
        else {
            logentry("        TSMDB1 already exists\n");
            my @rcArray = ( 1, "TSMDB1 already exists" );
            return @rcArray;
        }
    }
}

############################################################
#      sub: getBackupStartTime
#     desc: Prompts for, and obtains from the user the start time
#           for client schedules in 24 hour HH:MM format. This is
#           a repeatable step
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub getBackupStartTime {
    $stpn = shift(@_);

    logentry("Step ${stpn}: Get the start time for backup schedules\n");

    do {
        displayStepNumAndDesc($stpn);

        $repeatflag = 0;

        $foundinputinfile = 0;

        if ( $takeinputfromfile == 1 ) {
            $foundinputinfile = getinputfromfile("backupstarttime");
        }

        if ( $foundinputinfile == 1 ) {
            $backupstartt = $inputHash{backupstarttime};
        }
        else {
            displayString( 10, 3, $schedStartTimeString1 );
            displayString( 10, 1, $schedStartTimeString2 );

            $backupstartt = <STDIN>;

            chomp($backupstartt);

            if ( $backupstartt eq "" ) {
                $backupstartt = "22:00";
            }
        }

        logentry("        User response: Backup start time: $backupstartt\n");

        ( $rc, $msgstring ) = validateBackupStartTime($backupstartt);

        $backupstarttfull = "$backupstartt" . ":" . "00";

        if ( $rc == 0 ) {
            $stateHash{backupStartTime} = "$backupstarttfull";
            $stateHash{backupStartPlusTen} =
              getBackupStartPlusTen($backupstarttfull);
            $stateHash{backupStartPlusThirteen} =
              getBackupStartPlusThirteen($backupstarttfull);
            $stateHash{backupStartPlusFourteen} =
              getBackupStartPlusFourteen($backupstarttfull);
            $stateHash{backupStartPlusSeventeen} =
              getBackupStartPlusSeventeen($backupstarttfull);
            $stateHash{backupStartString} =
              getBackupStartString($backupstarttfull);
            $okstring =
              genresultString( "Backup Start Time> $backupstartt", 40, "[OK]" );
            displayString( 10, 4, $okstring, 1, $stpn );

            if ( $foundinputinfile == 1 ) {
                sleep 2;
            }
            else {
                displayPrompt( $stpn, "noq" );
            }
        }
        else {
            $errorstring = genresultString( "Backup Start Time> $backupstartt",
                40, "[ERROR]", $msgstring );
            displayString( 10, 4, $errorstring, 1, $stpn );
            $repeatflag = displayPromptExtNoContinue( $stpn, 1, "noq" );
        }
    } while ( $repeatflag != 0 );
}

############################################################
#      sub: formatserver
#     desc: As the DB2 user, issues (using the already prepared
#           command file to format the server) the command to
#           format the server. If a problem occurs when issuing
#           this command, the user is prompted to either exit, or
#           quit with intent to continue from this step later,
#           after correcting the problem
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub formatserver {
    $stpn = shift(@_);

    displayStepNumAndDesc($stpn);

    logentry(
        "Step ${stpn}_${substep}: Format the IBM Storage Protect server\n",
        1 );

    displayString( 10, 3, $formatServerString );

    $db2usr        = $stateHash{db2user};
    $db2usrpw      = $stateHash{db2userpw};
    $instdirmntpnt = $stateHash{instdirmountpoint};
    $dsmservopt    = "${instdirmntpnt}${SS}dsmserv.opt";
    $dbidfile      = "$instdirmntpnt${SS}dsmserv.dbid";

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $dsmformatcmdfile = "${instdirmntpnt}${SS}dsmformatcmd";

        logentry(
            "        As DB2 instance owner, issuing command: $formatcmd\n");

        $serversetupLogfull = "$currentdir" . "${SS}" . "$serversetupLog";

        $donefile = "$currentdir" . "${SS}" . "donefile.txt";
        if ( -f $donefile ) {
            unlink($donefile);
        }
        $formatservercmd =
          "su - $db2usr $dsmformatcmdfile >> \"$serversetupLogfull\"";
        $formatservercmd =
          "$formatservercmd" . ";" . "echo formatcomplete > \"$donefile\"";

        $formatserverrc = 1;

        if ( $formatpid = fork() ) {
            my $numIterations = 0;
            my $numH          = 0;

            $initialKb = getactivelogKbUsed();

            sleep 1;

            $numH = refreshProgress( $stpn, $initialKb, $numH, $numIterations );
            $numIterations++;

            do {
                sleep 10;
                $numH =
                  refreshProgress( $stpn, $initialKb, $numH, $numIterations );
                $numIterations++;

            } while ( !-f $donefile );
        }
        else {
            exec("$formatservercmd");
        }

        sleep 1;
        unlink($donefile);

    }
    elsif ( $platform eq "WIN32" ) {
        $actlogpth      = $stateHash{actlogpath};
        $archlogpth     = $stateHash{archlogpath};
        $dbdirpths      = $stateHash{dbdirpaths};
        $archlogfailpth = $stateHash{dbbackdirpaths}->[0];

        $recyclebinpath  = "$actlogpth" . "${SS}" . "\$RECYCLE.BIN";
        $rmrecyclebincmd = "rd /S /Q $recyclebinpath 2>nul";

        system("$rmrecyclebincmd");
        sleep 1;

        $recyclebinpath  = "$archlogpth" . "${SS}" . "\$RECYCLE.BIN";
        $rmrecyclebincmd = "rd /S /Q $recyclebinpath 2>nul";

        system("$rmrecyclebincmd");
        sleep 1;

        $recyclebinpath  = "$archlogfailpth" . "${SS}" . "\$RECYCLE.BIN";
        $rmrecyclebincmd = "rd /S /Q $recyclebinpath 2>nul";

        system("$rmrecyclebincmd");
        sleep 1;

        foreach $p ( @{$dbdirpths} ) {
            $recyclebinpath  = "$p" . "${SS}" . "\$RECYCLE.BIN";
            $rmrecyclebincmd = "rd /S /Q $recyclebinpath 2>nul";

            system("$rmrecyclebincmd");
            sleep 1;
        }

        sleep 2;

        require Win32::Process;
        require Win32;

        $dsmformatcmdfile = $stateHash{dsmformatcmdfile};

        logentry("        Issuing command: $formatcmd\n");

        $serversetupLogfull = "$currentdir" . "${SS}" . "$serversetupLog";

        $donefile = "$instdirmntpnt" . "${SS}" . "donefile.txt";
        if ( -f $donefile ) {
            unlink($donefile);
        }

        $formatprocrc = Win32::Process::Create( $ProcObj, "$dsmformatcmdfile",
            "dsmformatcmd", 1, NORMAL_PRIORITY_CLASS, "$instdirmntpnt" );

        if ( !($formatprocrc) ) {
            print "Failed to start process\n";
        }
        else {

            my $numIterations = 0;
            my $numH          = 0;

            $initialKb = getactivelogKbUsed();

            sleep 1;

            $numH = refreshProgress( $stpn, $initialKb, $numH, $numIterations );
            $numIterations++;

            do {
                sleep 10;
                $numH =
                  refreshProgress( $stpn, $initialKb, $numH, $numIterations );
                $numIterations++;

            } while ( !-f $donefile );
        }
        sleep 2;
        unlink($donefile);
    }

    $formatserverrc = 1;
    $stateHash{serverVersionLong} = "UNKNOWN";

    if ( open( LOGH, "<$serversetupLog" ) ) {
        while (<LOGH>) {
            my $ln = $_;

            # Look for evidence of successful format
            if ( $ln =~
m/Offline\s+DB\s+backup\s+for\s+database\s+TSMDB1\s+completed\s+successfully/i
              )
            {
                $formatserverrc = 0;
            }

            # Capture the long server version
            if ( $ln =~
                m/Version\s+(\d+),\s+Release\s+(\d+),\s+Level\s+(\d+)\.\d+/ )
            {
                $stateHash{serverVersionLong} = $1 . $2 . $3;
            }
        }
        close LOGH;
    }

    sleep 5;

# Check for the presence of the dsmserv.dbid file if the successful offline backup message was not found

    if ( $formatserverrc == 1 ) {
        if ( -f $dbidfile ) {
            logentry(
"        While the successful offline backup message was not found, the file $dbidfile exists\n"
            );
            logentry(
"        For now, this will be considered sufficient evidence that the IBM Storage Protect server format was successful\n"
            );
            $formatserverrc = 0;
        }
    }

    if ( $stateHash{serverVersionLong} eq "UNKNOWN" ) {
        logentry("        ERROR: unable to determine server version.\n");
        $formatserverrc = 1;
    }
    else {
        logentry(
            "        Detected server version $stateHash{serverVersionLong}\n");
    }

    if ( $formatserverrc == 0 ) {
        $sVersionLong = $stateHash{serverVersionLong};

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            $okstring1 = genresultString( $formatServerString, 50, "[OK]" );
            displayString( 10, 3, $okstring1, 1, $stpn );
            displayString( 10, 3, $adjustLockListString );

            logentry("        Setting DB2 locklist settings\n");
            ( $rc, $msgstring ) = setdb2locklist($stpn);

            if ( $rc == 0 ) {
                $okstring2 =
                  genresultString( $adjustLockListString, 50, "[OK]" );
                displayString( 10, 3, $okstring1, 1, $stpn );
                displayString( 10, 3, $okstring2 );
            }
            else {
                $errorstring =
                  genresultString( $adjustLockListString, 50, "[ERROR]",
                    "$msgstring" );
                displayString( 10, 3, $okstring1, 1, $stpn );
                displayString( 10, 3, $errorstring );
                displayPromptNoContinue( $stpn, "noq" );
            }

            if (   ( $serverVersion >= 7 && $sVersionLong >= 711 )
                || ( $serverVersion == 6 && $sVersionLong >= 635 ) )
            {
                displayString( 10, 3, $setreorgattribString );

                ( $rc, $msgstring ) = setreorgflag($stpn);

                if ( $rc == 0 ) {
                    $okstring3 =
                      genresultString( $setreorgattribString, 50, "[OK]" );
                    displayString( 10, 3, $okstring1, 1, $stpn );
                    displayString( 10, 3, $okstring2 );
                    displayString( 10, 3, $okstring3 );
                }
                else {
                    $errorstring =
                      genresultString( $setreorgattribString, 50, "[ERROR]",
                        "$msgstring" );
                    displayString( 10, 3, $okstring1, 1, $stpn );
                    displayString( 10, 3, $okstring2, 1, $stpn );
                    displayString( 10, 3, $errorstring );
                    displayPromptNoContinue( $stpn, "noq" );
                }
            }
            if ( $rc == 0 ) {
                if ( $takeinputfromfile == 1 ) {
                    sleep 2;
                }
                else {
                    displayPrompt( $stpn, "noq" );
                }
            }
        }
        elsif ( $platform eq "WIN32" ) {
            $okstring1 = genresultString( $formatServerString, 50, "[OK]" );
            displayString( 10, 3, $okstring1, 1, $stpn );
            displayString( 10, 3, $createWinServiceString );

            ( $rc, $msgstring ) = createWinService($stpn);

            if ( $rc == 0 ) {
                $okstring2 =
                  genresultString( $createWinServiceString, 50, "[OK]" );
                displayString( 10, 3, $okstring1, 1, $stpn );
                displayString( 10, 3, $okstring2 );
                displayString( 10, 3, $adjustLockListString );
            }
            else {
                $errorstring =
                  genresultString( $createWinServiceString, 50, "[ERROR]",
                    "$msgstring" );
                displayString( 10, 3, $okstring1, 1, $stpn );
                displayString( 10, 3, $errorstring );
                displayPromptNoContinue( $stpn, "noq" );
            }

            logentry(
"        Adjusting DB2 settings for locklist, system account access, and reorg attribute\n"
            );
            ( $rc, $msgstring ) = setdb2locklist($stpn);

            if ( $rc == 0 ) {
                $okstring3 =
                  genresultString( $adjustLockListString, 50, "[OK]" );
                displayString( 10, 3, $okstring1, 1, $stpn );
                displayString( 10, 3, $okstring2 );
                displayString( 10, 3, $okstring3 );
            }
            else {
                $errorstring =
                  genresultString( $adjustLockListString, 50, "[ERROR]",
                    "$msgstring" );
                displayString( 10, 3, $okstring1, 1, $stpn );
                displayString( 10, 3, $okstring2 );
                displayString( 10, 3, $errorstring );
                displayPromptNoContinue( $stpn, "noq" );
            }

            $sVersionLong = $stateHash{serverVersionLong};
            if (   ( $serverVersion >= 7 && $sVersionLong >= 711 )
                || ( $serverVersion == 6 && $sVersionLong >= 635 ) )
            {
                displayString( 10, 3, $setreorgattribString );

                ( $rc, $msgstring ) = setreorgflag($stpn);

                if ( $rc == 0 ) {
                    $okstring4 =
                      genresultString( $setreorgattribString, 50, "[OK]" );
                    displayString( 10, 3, $okstring1, 1, $stpn );
                    displayString( 10, 3, $okstring2 );
                    displayString( 10, 3, $okstring3 );
                    displayString( 10, 3, $okstring4 );
                }
                else {
                    $errorstring =
                      genresultString( $setreorgattribString, 50, "[ERROR]",
                        "$msgstring" );
                    displayString( 10, 3, $okstring1, 1, $stpn );
                    displayString( 10, 3, $okstring2 );
                    displayString( 10, 3, $okstring3 );
                    displayString( 10, 3, $errorstring );
                    displayPromptNoContinue( $stpn, "noq" );
                }
            }
            if ( $rc == 0 ) {
                if ( $takeinputfromfile == 1 ) {
                    sleep 2;
                }
                else {
                    displayPrompt( $stpn, "noq" );
                }
            }
        }
    }
    else {
        logentry(
"        An error occurred when attempting to format the IBM Storage Protect server\n"
        );
        $errorstring = genresultString( $formatServerString, 50, "[ERROR]",
            "see log $stateHash{logname}" );
        displayString( 10, 3, $errorstring, 1, $stpn );
        displayPromptNoContinue( $stpn, "noq" );
    }
}

############################################################
#      sub: initializeServer
#     desc: As the DB2 user, issues (using the already prepared
#           command file to start the server) the command to
#           start the server with a runfile argument. Then the
#           server is started up, and after a connection with the
#           server by way of dsmadmc is established, and server
#           configuration is completed using a macro. If an error
#           occurs on one of the initialization steps, the user is prompted
#           to either exit, or quit with intent to continue from this
#           step later, after correcting the problem
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub initializeServer {
    $stpn = shift(@_);

    displayStepNumAndDesc($stpn);

    $macrosGenerated   = 0;
    $serverInitialized = 0;
    $serverStarted     = 0;
    $updateactlogsize  = 0;

    $totalPreallocatedVolumes = $stateHash{totalpreallocatedvolumes};

    $genrunfilerc        = generateRunfile($stpn);
    $gentsmconfigmacrorc = generatetsmconfigmacro($stpn);

    if ( ( $genrunfilerc == 0 ) && ( $gentsmconfigmacrorc == 0 ) ) {

        $macrosGenerated = 1;
        $okstring = genresultString( $generateRunfileString, 55, "[OK]" );
        displayString( 10, 3, $okstring );

        sleep 2;

        logentry(
"Step ${stpn}_${substep}: Initialize the IBM Storage Protect server\n",
            1
        );

        displayString( 10, 3, $initServerString1 );

        $db2usr        = $stateHash{db2user};
        $instdirmntpnt = $stateHash{instdirmountpoint};

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            $startservercmdfile = "${instdirmntpnt}${SS}startservercmd";

            logentry(
                "        As DB2 instance owner, issuing command: $startcmd\n");

            $startservercmd = "su - $db2usr $startservercmdfile";

            @startservercmdOut = `$startservercmd`;
        }
        elsif ( $platform eq "WIN32" ) {
            $startservercmdfile = $stateHash{startservercmdfile};

            logentry("        Issuing command: $startcmd\n");

            @startservercmdOut = `$startservercmdfile`;
        }

        $startserverrc = 1;

        open( LOGH, ">>$serversetupLog" )
          or die "Unable to open $serversetupLog\n";

        foreach $outln (@startservercmdOut) {
            print LOGH "$outln";
            if ( $outln =~ m/System\s+privilege\s+granted\s+to\s+administrator/i
              ) # check for this message because granting system privilege to admin is last essential thing done in runfile.mac
            {
                $startserverrc = 0;
            }
        }
        close LOGH;

        if ( $startserverrc == 0 ) {
            $serverInitialized = 1;
            $okstring1 = genresultString( $generateRunfileString, 55, "[OK]" );
            displayString( 10, 3, $okstring1, 1, $stpn );
            $okstring2 = genresultString( $initServerString1, 55, "[OK]" );
            displayString( 10, 3, $okstring2 );
        }
        else {
            logentry(
"        An error occurred when attempting to initialize IBM Storage Protect server\n"
            );
            $okstring = genresultString( $generateRunfileString, 55, "[OK]" );
            displayString( 10, 3, $okstring, 1, $stpn );
            $errorstring = genresultString( $initServerString1, 55, "[ERROR]",
                "see log $stateHash{logname}" );
            displayString( 10, 3, $errorstring );
            displayPromptNoContinue( $stpn, "noq" );
        }
    }    # end of if (($genrunfilerc == 0) && ($gentsmconfigmacrorc == 0))
    else {
        $errorstring = genresultString( $generateRunfileString, 55, "[ERROR]",
            "Error generating macros" );
        displayString( 10, 3, $errorstring, 1, $stpn );
        displayPromptNoContinue( $stpn, "noq" );
    }

    sleep 1;

    # start the server, provided the server was initialized successfully

    if ( ( $macrosGenerated == 1 ) && ( $serverInitialized == 1 ) ) {
        if (   ( $platform eq "WIN32" )
            || ( $serverVersion >= 7 )
          )  # first update the dsmserv.opt with the appropriate active log size
        { # for the specified server scale if the platform is Windows or the server
             # version is at least 7
            logentry(
"Step ${stpn}_${substep}: Update the server option file with the appropriate activelogsize\n",
                1
            );

            $dsmservoptfile = "${instdirmntpnt}${SS}dsmserv.opt";
            $actlogsize     = $stateHash{actlogsize};

            if ( open( DSMSERVOPTH, "<${dsmservoptfile}" ) ) {
                @dsmservoptcontents = <DSMSERVOPTH>;
                close DSMSERVOPTH;
                $updateactlogsize = 1;
            }

            sleep 1;

            if ( $updateactlogsize == 1 ) {
                $updateactlogsize = 0;

                if ( open( DSMSERVOPTH, ">${dsmservoptfile}" ) ) {
                    foreach $optln (@dsmservoptcontents) {
                        if ( $optln =~ m/^\s*ACTIVELOGSize\s+\d+/i ) {
                            print DSMSERVOPTH "ACTIVELOGSize $actlogsize\n";
                        }
                        else {
                            print DSMSERVOPTH "$optln";
                        }
                    }
                    close DSMSERVOPTH;
                    $updateactlogsize = 1;
                }
            }
        }
        else {
            $updateactlogsize = 1;
        }

        if ( $updateactlogsize == 1 ) {
            logentry(
"Step ${stpn}_${substep}: Start up the IBM Storage Protect server\n",
                1
            );

            displayString( 10, 3, $startingServerString );

            $db2usr        = $stateHash{db2user};
            $instdirmntpnt = $stateHash{instdirmountpoint};

            if (   ( $platform eq "LINUX86" )
                || ( $platform eq "AIX" )
                || ( $platform =~ m/LINUXPPC/ ) )
            {
                $startservercmd =
"${serverPath}${SS}rc.dsmserv -u $db2usr -i $instdirmntpnt -q &";

                logentry("        Issuing command: $startservercmd\n");

                system("$startservercmd");

                sleep 2;

                $psdsmservCommand = "ps -ef | grep dsmserv";

                @psdsmservOut = `$psdsmservCommand`;

                foreach $psline (@psdsmservOut) {
                    if ( $psline =~ m#\Q${serverPath}${SS}dsmserv\E# ) {
                        $serverStarted = 1;
                    }
                }
            }
            elsif ( $platform eq "WIN32" ) {
                $startservercmd = "net start \"TSM server_${db2usr}\"";
                logentry("        Issuing command: $startservercmd\n");
                @startserverOut = `$startservercmd`;
                my $ret = $? >> 8;
                if ( $ret == 0 ) {
                    $serviceStartedSuccessfully = 1;
                }

                open( LOGH, ">>$serversetupLog" );
                foreach $outln (@startserverOut) {
                    print LOGH "$outln";
                    if ( $serviceStartedSuccessfully == 1 ) {
                        $serverStarted = 1;
                    }
                }
                close LOGH;

                sleep 2;

            }
        }

        if ( $serverStarted == 1 ) {
            logentry(
                "        The IBM Storage Protect server started successfully\n"
            );
            $okstring1 = genresultString( $generateRunfileString, 55, "[OK]" );
            displayString( 10, 3, $okstring1, 1, $stpn );
            $okstring2 = genresultString( $initServerString1, 55, "[OK]" );
            displayString( 10, 3, $okstring2 );
            $okstring3 = genresultString( $startingServerString, 55, "[OK]" );
            displayString( 10, 3, $okstring3 );
        }
        else {
            logentry(
"        An error occurred when attempting to start the IBM Storage Protect server\n"
            );
            $okstring1 = genresultString( $generateRunfileString, 55, "[OK]" );
            displayString( 10, 3, $okstring1, 1, $stpn );
            $okstring2 = genresultString( $initServerString1, 55, "[OK]" );
            displayString( 10, 3, $okstring2 );
            $errorstring =
              genresultString( $startingServerString, 55, "[ERROR]",
                "error starting server" );
            displayString( 10, 3, $errorstring );
            displayPromptNoContinue( $stpn, "noq" );
        }
    }    # end  if (($macrosGenerated == 1) && ($serverInitialized == 1))

    if ( $serverStarted == 1 ) {
        displayString( 10, 3, $initServerString2 );

        sleep 30;

        # Using DSMADMC, complete the rest of the configuration

        logentry(
"Step ${stpn}_${substep}: Connect to IBM Storage Protect server and complete the server configuration\n",
            1
        );

        $serverlogonfailed             = 0;
        $serverconfigcomplete          = 0;
        $createpreallocvolumescomplete = 0;

        if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
            $dsmconfig =
"${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin${SS}dsmforconfig.opt"
              ; # option file pointing to the server stanza used to connect to server
        }
        elsif ( $platform eq "AIX" ) {
            $dsmconfig =
"${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin64${SS}dsmforconfig.opt"
              ; # option file pointing to the server stanza used to connect to server
        }
        elsif ( $platform eq "WIN32" ) {
            $dsmconfig = "${baclientPath}${SS}dsmforconfig.opt";
        }

        $adminid = $stateHash{adminID};
        $adminpw = $stateHash{adminPW};

        if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
            $dsmadmcCmd =
"export DSM_CONFIG=${dsmconfig};${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin${SS}dsmadmc -id=${adminid} -pass=${adminpw} -itemcommit macro \"$tsmconfigmacroname\"";
        }
        elsif ( $platform eq "AIX" ) {
            $dsmadmcCmd =
"export DSM_CONFIG=${dsmconfig};${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin64${SS}dsmadmc -id=${adminid} -pass=${adminpw} -itemcommit macro \"$tsmconfigmacroname\"";
        }
        elsif ( $platform eq "WIN32" ) {
            $dsmadmcCmd = "${instdirmntpnt}${SS}dsmadmcforconfig.bat";
            $stateHash{dsmadmccmdfile} = $dsmadmcCmd;

            if ( open( DSMADMCCMDFH, ">$dsmadmcCmd" ) ) {
                print DSMADMCCMDFH "\@echo off\n";
                print DSMADMCCMDFH "set DSM_CONFIG=${dsmconfig}\n";
                print DSMADMCCMDFH
"${baclientPath}${SS}dsmadmc -id=${adminid} -pass=${adminpw} -itemcommit macro \"$tsmconfigmacroname\"";
                close DSMADMCCMDFH;
            }
            else {
                $errorstring = genresultString(
                    $initServerString2,
                    55,
                    "[ERROR]",
"error trying to prepare batch file to connect to the server"
                );
                displayString( 10, 3, $errorstring );
                displayPromptNoContinue( $stpn, "noq" );
            }
        }

        do {
            $serverlogonfailed = 0;
            sleep 30;

            @dsmadmcCmdOut = `$dsmadmcCmd`;

            open( LOGH, ">>$serversetupLog" )
              or die "Unable to open $serversetupLog\n";

            foreach $dsmadmcoutln (@dsmadmcCmdOut) {

                # Do not print database backup password in the log
                if ( $dsmadmcoutln =~ m/password=(\S+)/ ) {
                    $dsmadmcoutln =~ s/password=\S+/password=\*\*\*\*\*\*\'\./;
                }

                print LOGH "$dsmadmcoutln";
                if ( $dsmadmcoutln =~
                    m#ANS1017E# )   #Session rejected: TCP/IP connection failure
                {
                    $serverlogonfailed = 1;
                }
                elsif ( $dsmadmcoutln =~ m/ANS8002I/ )    #Highest return code
                {
                    $serverconfigcomplete = 1;
                }
            }
            close LOGH;
        } while ( $serverlogonfailed == 1 );

        if ( $serverconfigcomplete == 1 ) {
            logentry(
"        IBM Storage Protect server configuration completed successfully\n"
            );
            $okstring1 = genresultString( $generateRunfileString, 55, "[OK]" );
            displayString( 10, 3, $okstring1, 1, $stpn );
            $okstring2 = genresultString( $initServerString1, 55, "[OK]" );
            displayString( 10, 3, $okstring2 );
            $okstring3 = genresultString( $startingServerString, 55, "[OK]" );
            displayString( 10, 3, $okstring3 );
            $okstring4 = genresultString( $initServerString2, 55, "[OK]" );
            displayString( 10, 3, $okstring4 );

            # run macro to create preallocated volumes

            if ( $totalPreallocatedVolumes > 0 ) {
                sleep 2;

                displayString( 10, 3, $initServerString3 );

                $definevolumesrc = definepreallocatedvolumes($stpn);

                if ( $definevolumesrc == 0 ) {
                    $createpreallocvolumescomplete = 1;
                }

                if ( $createpreallocvolumescomplete == 1 ) {
                    logentry(
"        Creation of pre-allocated volumes completed successfully\n"
                    );
                    $okstring1 =
                      genresultString( $generateRunfileString, 55, "[OK]" );
                    displayString( 10, 3, $okstring1, 1, $stpn );
                    $okstring2 =
                      genresultString( $initServerString1, 55, "[OK]" );
                    displayString( 10, 3, $okstring2 );
                    $okstring3 =
                      genresultString( $startingServerString, 55, "[OK]" );
                    displayString( 10, 3, $okstring3 );
                    $okstring4 =
                      genresultString( $initServerString2, 55, "[OK]" );
                    displayString( 10, 3, $okstring4 );
                    $okstring5 =
                      genresultString( $initServerString3, 55, "[OK]" );
                    displayString( 10, 3, $okstring5 );

                    if ( $takeinputfromfile == 1 ) {
                        sleep 2;
                    }
                    else {
                        displayPrompt( $stpn, "noq" );
                    }
                }
                else {
                    logentry(
"        An error occurred when attempting to create pre-allocated volumes\n"
                    );
                    $okstring1 =
                      genresultString( $generateRunfileString, 55, "[OK]" );
                    displayString( 10, 3, $okstring1, 1, $stpn );
                    $okstring2 =
                      genresultString( $initServerString1, 55, "[OK]" );
                    displayString( 10, 3, $okstring2 );
                    $okstring3 =
                      genresultString( $startingServerString, 55, "[OK]" );
                    displayString( 10, 3, $okstring3 );
                    $okstring4 =
                      genresultString( $initServerString2, 55, "[OK]" );
                    displayString( 10, 3, $okstring4 );
                    $errorstring =
                      genresultString( $initServerString3, 55, "[ERROR]" );
                    displayString( 10, 3, $errorstring );
                    displayPromptNoContinue( $stpn, "noq" );
                }
            }
            else {
                if ( $takeinputfromfile == 1 ) {
                    sleep 2;
                }
                else {
                    displayPrompt( $stpn, "noq" );
                }
            }
        }
        else {
            logentry(
"        An error occurred when attempting to configure the IBM Storage Protect server\n"
            );
            $okstring1 = genresultString( $generateRunfileString, 55, "[OK]" );
            displayString( 10, 3, $okstring1, 1, $stpn );
            $okstring2 = genresultString( $initServerString1, 55, "[OK]" );
            displayString( 10, 3, $okstring2 );
            $okstring3 = genresultString( $startingServerString, 55, "[OK]" );
            displayString( 10, 3, $okstring3 );
            $errorstring = genresultString( $initServerString2, 55, "[ERROR]",
                "see log $stateHash{logname}" );
            displayString( 10, 3, $errorstring );
            displayPromptNoContinue( $stpn, "noq" );
        }
    }
}

############################################################
#      sub: setupforstartatreboot
#     desc: Updates the dsmserv.rc and puts it in the proper
#           location, and registers the IBM Storage Protect server as a service
#           to have the server start at reboot. If an error occurs
#           attempting to perform either of those steps, the user
#           is prompted to either exit, or quit with intent to
#           continue from this step later, after correcting the
#           problem
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub setupforstartatreboot {
    $stpn = shift(@_);

    $db2usr        = $stateHash{db2user};
    $instdirmntpnt = $stateHash{instdirmountpoint};

    displayStepNumAndDesc($stpn);

    logentry(
"Step ${stpn}: Set up IBM Storage Protect server to start up at reboot\n"
    );

    displayString( 10, 3, $setupServertoStartAtRebootString );

    if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
        $prepdsmservrc = preparedsmservrc($stpn);

        if ( $prepdsmservrc == 1 ) {
            $errorstring = genresultString( $setupServertoStartAtRebootString,
                50, "[ERROR]", "dsmserv.rc setup failed" );
            displayString( 10, 3, $errorstring, 1, $stpn );
            displayPromptNoContinue( $stpn, "noq" );
        }
        else {
            $chkconfigrc = configservice($stpn);
            if ( $chkconfigrc == 1 ) {
                $errorstring =
                  genresultString( $setupServertoStartAtRebootString,
                    50, "[ERROR]", "chkconfig or update-rc.d error" );
                displayString( 10, 3, $errorstring, 1, $stpn );
                displayPromptNoContinue( $stpn, "noq" );
            }
            else {
                $okstring = genresultString( $setupServertoStartAtRebootString,
                    50, "[OK]" );
                displayString( 10, 3, $okstring, 1, $stpn );
                if ( $takeinputfromfile == 1 ) {
                    sleep 2;
                }
                else {
                    displayPrompt( $stpn, "noq" );
                }
            }
        }
    }
    elsif ( $platform eq "AIX" ) {
        $inittabfile = "/etc/inittab";
        if ( open( INITTABH, ">>$inittabfile" ) ) {
            print INITTABH
"tsm1:2:once:/opt/tivoli/tsm/server/bin/rc.dsmserv -u $db2usr -i $instdirmntpnt -q >/dev/console 2>&1\n";
            close INITTABH;

            $okstring =
              genresultString( $setupServertoStartAtRebootString, 50, "[OK]" );
            displayString( 10, 3, $okstring, 1, $stpn );
            if ( $takeinputfromfile == 1 ) {
                sleep 2;
            }
            else {
                displayPrompt( $stpn, "noq" );
            }
        }
        else {
            $errorstring = genresultString( $setupServertoStartAtRebootString,
                50, "[ERROR]", "error updating /etc/inittab" );
            displayString( 10, 3, $errorstring, 1, $stpn );
            displayPromptNoContinue( $stpn, "noq" );
        }
    }
}

############################################################
#      sub: createProfile
#     desc: Creates the .profile file located in the home
#           directory of the DB2 user account.
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub createProfile {
    $stpn = shift(@_);

    logentry(
        "Step ${stpn}_${substep}: Prepare db2 instance owner .profile file\n",
        1 );

    $db2usr     = $stateHash{db2user};
    $db2grp     = $stateHash{db2group};
    $db2homedir = $stateHash{db2home};

    $profilePath = "${db2homedir}${SS}.profile";

    if ( open( PROFH, ">>$profilePath" ) ) {
        print PROFH "if [ -f ${db2homedir}${SS}sqllib${SS}db2profile ]; then\n";
        print PROFH ". ${db2homedir}${SS}sqllib${SS}db2profile\n";
        print PROFH "fi\n";
        close PROFH;

        system("chown ${db2usr}:${db2grp} $profilePath");
    }
    else {
        logentry(
"        An error occurred when attempting to create the instance owner's .profile file\n"
        );
        my @rcArray = ( 1, "error creating .profile" );
        return @rcArray;
    }
    my @rcArray = ( 0, "" );
    return @rcArray;
}

############################################################
#      sub: updateusercshrc
#     desc: Updates the usercshrc file located in the sqllib
#           subdirectory of the home directory of the DB2 user account
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub updateusercshrc {
    $stpn = shift(@_);

    logentry(
        "Step ${stpn}_${substep}: Prepare instance owner usercshrc file\n", 1 );

    $db2usr     = $stateHash{db2user};
    $db2homedir = $stateHash{db2home};

    $usercshrcPath = "${db2homedir}${SS}sqllib${SS}usercshrc";

    if ( open( USERCSHRCH, ">>$usercshrcPath" ) ) {
        if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
            print USERCSHRCH
"setenv LD_LIBRARY_PATH ${serverPath}${SS}dbbkapi:${SS}usr${SS}local${SS}ibm${SS}gsk8_64${SS}lib64:\$LD_LIBRARY_PATH\n";
        }
        elsif ( $platform eq "AIX" ) {
            print USERCSHRCH
"setenv LIBPATH ${serverPath}${SS}dbbkapi:${SS}usr${SS}opt${SS}ibm${SS}gsk8_64${SS}lib64:\$LIBPATH\n";
        }
        close USERCSHRCH;
    }
    else {
        logentry(
"        An error occurred when attempting to update the instance owner's usercshrc file\n"
        );
        my @rcArray = ( 1, "error updating usercshrc" );
        return @rcArray;
    }
    my @rcArray = ( 0, "" );
    return @rcArray;
}

############################################################
#      sub: updateuserprofile
#     desc: Updates the userprofile file located in the sqllib
#           subdirectory of the home directory of the DB2 user account
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub updateuserprofile {
    $stpn = shift(@_);

    logentry(
        "Step ${stpn}_${substep}: Prepare instance owner userprofile file\n",
        1 );

    $db2usr        = $stateHash{db2user};
    $instdirmntpnt = $stateHash{instdirmountpoint};
    $db2homedir    = $stateHash{db2home};

    $userprofilePath = "${db2homedir}${SS}sqllib${SS}userprofile";

    if ( open( USERPROFH, ">>$userprofilePath" ) ) {
        if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
            print USERPROFH
"LD_LIBRARY_PATH=${serverPath}${SS}dbbkapi:${SS}usr${SS}local${SS}ibm${SS}gsk8_64${SS}lib64:\$LD_LIBRARY_PATH\n";
            print USERPROFH "export LD_LIBRARY_PATH\n";
            print USERPROFH
              "export DSMI_CONFIG=${instdirmntpnt}${SS}tsmdbmgr.opt\n";
            if ( $serverVersion >= 7 ) {
                print USERPROFH "export DSMI_DIR=${serverPath}${SS}dbbkapi\n";
            }
            else {
                print USERPROFH
"export DSMI_DIR=${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}api${SS}bin64\n";
            }
            print USERPROFH "export DSMI_LOG=${instdirmntpnt}\n";
        }
        elsif ( $platform eq "AIX" ) {
            print USERPROFH
"LIBPATH=${serverPath}${SS}dbbkapi:${SS}usr${SS}opt${SS}ibm${SS}gsk8_64${SS}lib64:\$LIBPATH\n";
            print USERPROFH "export LIBPATH\n";
            print USERPROFH
              "export DSMI_CONFIG=${instdirmntpnt}${SS}tsmdbmgr.opt\n";
            if ( $serverVersion >= 7 ) {
                print USERPROFH "export DSMI_DIR=${serverPath}${SS}dbbkapi\n";
            }
            else {
                print USERPROFH
"export DSMI_DIR=${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}api${SS}bin64\n";
            }
            print USERPROFH "export DSMI_LOG=${instdirmntpnt}\n";
        }
        close USERPROFH;
    }
    else {
        logentry(
"        An error occurred when attempting to update the instance owner's userprofile file\n"
        );
        my @rcArray = ( 1, "error updating userprofile" );
        return @rcArray;
    }
    my @rcArray = ( 0, "" );
    return @rcArray;
}

############################################################
#      sub: initLog
#     desc: Initialize the script log, by adding the date stamp
#           and if log(s) with the same date already exist
#           append the first unused index to the end of the
#           name starting from 1 (e.g., the log will be
#           setupLog_130515_2.log if setupLog_130515_1.log already
#           exists, but setupLog_130515_2.log does not already
#           exist)
#
#   params: none
#  returns: the name of the script log
#
############################################################

sub initLog {
    @currenttime = localtime();
    $day = $currenttime[4] + 1;       # Adjust month 0..11 range to 1..12 range
    $day = "0" . $day if ( $day < 10 );               # Adjust month 0 as 00
    $currenttime[5] = $currenttime[5] - 100
      if ( $currenttime[5] > 99 );                    # Adjust year 2000 as 00
    $currenttime[5] = "0" . $currenttime[5]
      if ( $currenttime[5] < 10 );                    # Adjust year 0 as 00
    $currenttime[3] = "0" . $currenttime[3]
      if ( $currenttime[3] < 10 );                    # Adjust day 0 as 00
    $date = $currenttime[5] . $day . $currenttime[3];

    $setuplogname_base = "$serversetupLogBase" . "_" . "${date}";
    $setuplogname      = "$setuplogname_base" . ".log";

    $cnt = 1;

    if ( -f $setuplogname ) {
        $setuplogname = "$setuplogname_base" . "_" . "$cnt" . ".log";
    }

    while ( -f $setuplogname ) {
        $cnt++;
        $setuplogname = "$setuplogname_base" . "_" . "$cnt" . ".log";
    }

# need to validate hosts file first, otherwise the functions to obtain the machine information
# may yield strange output

    if ( $platform ne "WIN32" ) {
        if ( validateHostsFile() == 0 ) {
            die
"\nPlease verify there is an entry for the hostname in the /etc/hosts file, in accordance with IBM Storage Protect Blueprint instructions\n\n";
        }
    }

    $logHead = getlogHeader();    # write the log header information

    open( LOGH, ">$setuplogname" ) or die "Unable to open $setuplogname\n";

    print LOGH "$logHead\n";
    print LOGH "\n$versionString\n";

    close LOGH;

    return $setuplogname;
}

############################################################
#      sub: checkSystemParams
#     desc: Checks that various system parameters meet the
#           criteria appropriate to the specified server scale
#           If some criteria are not met when issuing the user
#           is prompted to either exit, or quit with intent to
#           continue from this step later, after correcting the
#           problem
#
#   params: 1. the step number
#  returns: none
#
############################################################

sub checkSystemParams {
    $stpn = shift(@_);

    displayStepNumAndDesc($stpn);

    logentry("Step ${stpn}: Check system parameters\n");

    displayString( 10, 3, $checkSystemParamsString );

    # On Linux platforms, validate the correct 777 permissions for /dev/shm
    if ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) ) {
        logentry(
"Step ${stpn}: Checking that /dev/shm is mounted and the directory has 777 permissions\n"
        );
        $shmPerm = 0;

        @mountOut = `mount`;
        if ( !grep { m/\/dev\/shm/ } @mountOut ) {
            $shmPerm = 1;
            logentry("        Error: /dev/shm not detected in mount output\n");
        }
        else {
            logentry("        Found /dev/shm in mount output\n");
        }

        @shmOut = `ls -ld /dev/shm`;
        if ( !grep { m/drwxrwxrwt/ } @shmOut ) {
            $shmPerm = 1;
            logentry(
"        Error: Incorrect /dev/shm permissions (expected drwxrwxrwt)\n"
            );
            logentry("        @shmOut\n");
        }
        else {
            logentry("        Found expected permissions for /dev/shm\n");
            logentry("        @shmOut\n");
        }
    }

    ( $memcorerc, $msgstringmemcore, $parammsgsMemCoreRef ) =
      validateMemoryandCoreCount($stpn);

    if ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) ) {
        $updkernparamsrc == 0;
        ( $kernelrc, $msgstringkernel, $parammsgsKernelRef, $nkParamsRef ) =
          validateKernelParams($stpn);
    }

    if ( ( $memcorerc == 1 ) && ( $ignoreSystemRequirementsFlag == 0 ) ) {
        $errorstring = genresultString( $checkSystemParamsString, 50, "[ERROR]",
            "$msgstringmemcore" );
        displayString( 10, 3, $errorstring, 1, $stpn );
    }
    elsif ( $shmPerm == 1 ) {
        $errorstring = genresultString( $validateShmString, 50, "[ERROR]",
            "$errorShmPermissions" );
        displayString( 10, 3, $errorstring, 1, $stpn );
    }
    elsif ( ( $memcorerc == 1 ) && ( $ignoreSystemRequirementsFlag == 1 ) ) {
        $errorstring =
          genresultString( $checkSystemParamsString, 50, "[WARNING]",
            "$msgstringmemcore" );
        displayString( 10, 3, $errorstring, 1, $stpn );
    }
    elsif (( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) )
        && ( $kernelrc == 1 )
        && ( $ignoreSystemRequirementsFlag == 0 ) )
    {
        $errorstring = genresultString( $checkSystemParamsString, 50, "[ERROR]",
            $msgstringkernel );
        displayString( 10, 3, $errorstring, 1, $stpn );

        displayString( 10, 3, $updateKernelParamsString );

        ( $updkernparamsrc, $updkernparamsmsg ) =
          updateKernelParams($nkParamsRef);

        if ( $updkernparamsrc == 1 ) {
            $errorstring1 =
              genresultString( $checkSystemParamsString, 50, "[ERROR]",
                $msgstringkernel );
            displayString( 10, 3, $errorstring1, 1, $stpn );
            $errorstring2 =
              genresultString( $updateKernelParamsString, 50, "[ERROR]",
                $updkernparamsmsg );
            displayString( 10, 3, $errorstring2 );
        }
        else {
            $okstring1 =
              genresultString( $checkSystemParamsString, 50, "[OK]" );
            displayString( 10, 3, $okstring1, 1, $stpn );
            $okstring2 =
              genresultString( $updateKernelParamsString, 50, "[OK]" );
            displayString( 10, 3, $okstring2 );

            (
                $kernelrc2, $msgstringkernel2, $parammsgsKernelRef2,
                $nkParamsRef2
            ) = validateKernelParams($stpn);    # check the parameters again

            if ( $kernelrc2 == 1 ) {
                $errorstring1 =
                  genresultString( $checkSystemParamsString, 50, "[ERROR]",
                    $msgstringkernel2 );
                displayString( 10, 3, $errorstring1, 1, $stpn );
                $errorstring2 =
                  genresultString( $updateKernelParamsString, 50, "[ERROR]",
                    "error updating kernel parameters" );
                displayString( 10, 3, $errorstring2 );
            }
        }
    }
    elsif (( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) )
        && ( $kernelrc == 1 )
        && ( $ignoreSystemRequirementsFlag == 1 ) )
    {
        $errorstring =
          genresultString( $checkSystemParamsString, 50, "[WARNING]",
            $msgstringkernel );
        displayString( 10, 3, $errorstring, 1, $stpn );
    }
    else {
        $okstring = genresultString( $checkSystemParamsString, 50, "[OK]" );
        displayString( 10, 3, $okstring, 1, $stpn );
    }

    displayString( 0, 1, "" );

    foreach $msg ( @{$parammsgsMemCoreRef} ) {
        displayString( 13, 1, $msg );
    }

    if ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) ) {
        if ( $shmPerm == 0 ) {
            $msg = genresultString( $validateShmString, 50, "PASS" );
        }
        else {
            $msg = genresultString( $validateShmString, 50, "FAIL" );
        }
        displayString( 13, 1, $msg );
        if ( ( $updkernparamsrc == 0 ) && ( $kernelrc == 0 ) ) {
            foreach $msg ( @{$parammsgsKernelRef} ) {
                displayString( 13, 1, $msg );
            }
        }
        elsif ( $updkernparamsrc == 0 ) {
            foreach $msg ( @{$parammsgsKernelRef2} ) {
                displayString( 13, 1, $msg );
            }
        }
    }

    if (
        ( $ignoreSystemRequirementsFlag == 0 )
        && (
            ( $memcorerc == 1 )
            || ( ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) )
                && ( ( $updkernparamsrc == 1 ) || ( $kernelrc2 == 1 ) ) )
        )
      )
    {
        displayPromptNoContinue($stpn);
    }
    elsif ( $shmPerm == 1
        && ( $platform eq "LINUX86" || $platform =~ m/LINUXPPC/ ) )
    {
        displayPromptNoContinue($stpn);
    }
    elsif (
        ( $ignoreSystemRequirementsFlag == 1 )
        && (   ( $memcorerc == 1 )
            && ( $platform ne "LINUX86" )
            && ( $platform !~ m/LINUXPPC/ ) )
      )
    {
        if ( $takeinputfromfile == 1 ) {
            sleep 2;
        }
        else {
            displayPromptContinueWithWarning( $stpn, \@warningStringArray_mem );
        }
    }
    elsif (
        ( $ignoreSystemRequirementsFlag == 1 )
        && (   ( $memcorerc == 1 )
            && ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) )
            && ( $kernelrc == 0 ) )
      )
    {
        if ( $takeinputfromfile == 1 ) {
            sleep 2;
        }
        else {
            displayPromptContinueWithWarning( $stpn, \@warningStringArray_mem );
        }
    }
    elsif (
        ( $ignoreSystemRequirementsFlag == 1 )
        && (   ( $memcorerc == 0 )
            && ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) )
            && ( $kernelrc == 1 ) )
      )
    {
        if ( $takeinputfromfile == 1 ) {
            sleep 2;
        }
        else {
            displayPromptContinueWithWarning( $stpn,
                \@warningStringArray_kernelparams );
        }
    }
    elsif (
        ( $ignoreSystemRequirementsFlag == 1 )
        && (   ( $memcorerc == 1 )
            && ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) )
            && ( $kernelrc == 1 ) )
      )
    {
        if ( $takeinputfromfile == 1 ) {
            sleep 2;
        }
        else {
            displayPromptContinueWithWarning( $stpn,
                \@warningStringArray_memandkernelparams );
        }
    }
    else {
        if ( $takeinputfromfile == 1 ) {
            sleep 2;
        }
        else {
            displayPrompt($stpn);
        }
    }
}

############################################################
#      sub: generateMacro
#     desc: Adds commands to the macro file specified by the
#           second argument, based on the template specified
#           specified by the first argument, by substituting
#           each "key" enclosed by angle braces in the template
#           by the actual value from the state hash for that
#           "key"
#
#   params: 1. template name (located in resources subdirectory)
#           2. name of macro file to write to (with actual values
#              replacing the items in angle brackets from the
#              template file) For the purposes of this script
#              this macro file will be the runfile macro
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure) and in the case of failure, a suitable
#           message
#
############################################################

sub generateMacro {
    $templatename = shift(@_);
    $macroname    = shift(@_);

# generate an actual macro from a template, using values taken from the master hash
# to substitute actual values for the place holders

    if ( open( TEMPLH, "<$templatename" ) ) {
        @templatecontents = <TEMPLH>;
        close TEMPLH;
    }
    else {
        my @rcArray = ( 1, "failed to open templates" );
        return @rcArray;
    }

    if ( open( MACROH, ">>$macroname" ) ) {

        foreach $tmpline (@templatecontents) {
            $macroline = "";

            $currline = $tmpline;

            $firstleftanglebracketpos = index( $currline, "<" );

            while ( $firstleftanglebracketpos >= 0 ) {
                $preleftbracket =
                  substr( $currline, 0, $firstleftanglebracketpos );
                $postleftbracket =
                  substr( $currline, $firstleftanglebracketpos );
                $firstrightanglebracketpos = index( $postleftbracket, ">" );
                $thekey =
                  substr( $postleftbracket, 1, $firstrightanglebracketpos - 1 );

                $macroline = "$macroline" . "$preleftbracket";

                if ( $thekey eq "tsmstgpaths" ) {
                    $dirArrRef = $stateHash{$thekey};

                    $firstdir = 1;

                    $numberofdirs = @{$dirArrRef};
                    $dircount     = 0;

# To avoid a define stgpooldir command which is to long, break into multiple commands
# that do not exceed 500 characters each
                    while (
                        ( $dircount < $numberofdirs )
                        && (
                            length($macroline) +
                            length( $dirArrRef->[$dircount] ) < 500 )
                      )
                    {
                        if ( $firstdir == 1 ) {
                            $macroline =
                              "$macroline" . "$dirArrRef->[$dircount]";
                            $firstdir = 0;
                        }
                        else {
                            $macroline =
                              "$macroline" . ",$dirArrRef->[$dircount]";
                        }
                        $dircount++;
                    }
                }
                elsif ( $thekey eq "dbbackdirpaths" ) {
                    $dirArrRef = $stateHash{$thekey};

                    $firstdir = 1;

                    foreach $d ( @{$dirArrRef} ) {
                        if ( $firstdir == 1 ) {
                            $macroline = "$macroline" . "$d";
                            $firstdir  = 0;
                        }
                        else {
                            $macroline = "$macroline" . ",$d";
                        }
                    }
                }
                else {
                    $macroline = "$macroline" . "$stateHash{$thekey}";
                }
                $currline =
                  substr( $postleftbracket, $firstrightanglebracketpos + 1 );

                $firstleftanglebracketpos = index( $currline, "<" );
            }

            if ( ( $thekey eq "tsmstgpaths" ) && ( $dircount < $numberofdirs ) )
            {
                while ( $dircount < $numberofdirs ) {
                    print MACROH "$macroline\n";
                    $macroline = "$preleftbracket";

                    $firstdir = 1;

                    while (
                        ( $dircount < $numberofdirs )
                        && (
                            length($macroline) +
                            length( $dirArrRef->[$dircount] ) < 500 )
                      )
                    {
                        if ( $firstdir == 1 ) {
                            $macroline =
                              "$macroline" . "$dirArrRef->[$dircount]";
                            $firstdir = 0;
                        }
                        else {
                            $macroline =
                              "$macroline" . ",$dirArrRef->[$dircount]";
                        }
                        $dircount++;
                    }
                }
            }

            $macroline = "$macroline" . "$currline";

            print MACROH "$macroline";
        }

        print MACROH "\n";

        close MACROH;

# Set permissions on the macro file so that non-root users are able to read from it
        chmod( 0644, $macroname );

        my $rcArray = ( 0, "" );
        return @rcArray;
    }
    else {
        my @rcArray = ( 1, "failed to open runfile" );
        return @rcArray;
    }
}

############################################################
#      sub: generateRunfile
#     desc: creates the run file macro that will be used when
#           first starting up the server for the sake of setting
#           basic server parameters
#
#   params: 1. step number
#
#  returns: 0 for success
#           1 for failure
#
############################################################

sub generateRunfile {
    $stpn = shift(@_);

    # take the first template and generate macro from it for use in the runfile

    logentry( "Step ${stpn}_${substep}: Generate the runfile $runfilename\n",
        1 );

    if ( -f $runfilename ) {
        unlink($runfilename);
    }

    $rc = 0;

    foreach $tmpl (@templateArray1) {
        $templatepth = "$resourcesdir" . "${SS}" . "$tmpl" . ".template";

        if ( $rc == 0 ) {
            ( $rc, $msgstring ) = generateMacro( $templatepth, $runfilename );
        }
    }

    return $rc;
}

############################################################
#      sub: generatetsmconfigmacro
#     desc: creates the macro that will be used, after connecting
#           to the server by means of dsmadmc, in order to complete
#           server configuration: defining certain structures
#           and other objects (e.g., storage pools, policies, maintenance and
#           client schedules)
#
#   params: 1. step number
#
#  returns: 0 for success
#           1 for failure
#
############################################################

sub generatetsmconfigmacro {
    $stpn = shift(@_);

    # take all the templates after the first and merge them into one macro

    logentry(
        "Step ${stpn}_${substep}: Generate the macro $tsmconfigmacroname\n",
        1 );

    if ( -f $tsmconfigmacroname ) {
        unlink($tsmconfigmacroname);
    }

    $rc = 0;

    foreach $tmpl (@templateArray2) {

# Beginning with IBM Storage Protect 812, we need to password protect the database backups.
        if ( $stateHash{serverVersionLong} >= 812 && $tmpl =~ m/maintenance/ ) {
            $stateHash{dbbkpassword} = "password=" . $stateHash{serverPassword};
        }
        else {
            $stateHash{dbbkpassword} = "";
        }

    # Beginning with IBM Storage Protect 713, we will build a container stgpool
        if (   $stateHash{serverVersionLong} >= 713
            && $tmpl =~ m/stgpool/
            && ( !$legacyFlag ) )
        {
            logentry(
"Step ${stpn}_${substep}: Updating stgpool macro to create a container storage pool\n",
                1
            );
            $templatepth =
              "$resourcesdir" . "${SS}" . "step2_cntrpool" . ".template";
        }
        elsif ($stateHash{serverVersionLong} >= 713
            && $tmpl =~ m/maintenance/
            && ( !$legacyFlag ) )
        {
            logentry(
"Step ${stpn}_${substep}: Updating maintenance macro for a container storage pool\n",
                1
            );
            $templatepth =
              "$resourcesdir" . "${SS}" . "step3_cntrmaintenance" . ".template";
        }
        else {
            $templatepth = "$resourcesdir" . "${SS}" . "$tmpl" . ".template";
        }

        if ( $rc == 0 ) {
            ( $rc, $msgstring ) =
              generateMacro( $templatepth, $tsmconfigmacroname );
        }
    }

    return $rc;
}

############################################################
#      sub: definepreallocatedvolumes
#     desc: creates and calls the macros used to define the preallocated
#           volumes, the number of volumes being determined by the
#           preallocation percentage specified by the -prealloc
#           parameter when the configuration script is invoked
#           The volumes are created in round-robin fashion across
#           the filesystems used for storage
#
#   params: 1. step number
#
#  returns: 0 for success
#           1 for failure
#
############################################################

sub definepreallocatedvolumes {
    $stpn = shift(@_);

    $maxcap                   = $stateHash{maxcap};
    $maxcap_without_unit      = substr( $maxcap, 0, length($maxcap) - 1 );
    $maxcapinMB               = $maxcap_without_unit * 1024;
    $tsmstgpths               = $stateHash{tsmstgpaths};
    $numpreAllocatedvols      = $stateHash{numpreallocvols};
    $totalPreallocatedVolumes = $stateHash{totalpreallocatedvolumes};
    $progressbarwidth         = 50;
    $numHashes                = 0;
    @stgmntpntsallocatedvolumesArray = ();
    $maxGPFSbatchsize                = 40;

    if ( $platform eq "WIN32" ) {
        $secondsperbatch = 20;
    }
    else {
        $secondsperbatch = 5;
    }

    $instdirmntpnt = $stateHash{instdirmountpoint};

    if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
        $dsmconfig =
"${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin${SS}dsmforconfig.opt";
    }
    elsif ( $platform eq "AIX" ) {
        $dsmconfig =
"${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin64${SS}dsmforconfig.opt";
    }
    elsif ( $platform eq "WIN32" ) {
        $dsmconfig = "${baclientPath}${SS}dsmforconfig.opt";
    }

    $adminid = $stateHash{adminID};
    $adminpw = $stateHash{adminPW};

    if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
        $qprocessCmd =
"export DSM_CONFIG=${dsmconfig};${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin${SS}dsmadmc -id=${adminid} -pass=${adminpw} q pr";
        $createvolCmd =
"export DSM_CONFIG=${dsmconfig};${SS}opt${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin${SS}dsmadmc -id=${adminid} -pass=${adminpw} macro \"$createpreallocvolumesmacroname\"";
    }
    elsif ( $platform eq "AIX" ) {
        $qprocessCmd =
"export DSM_CONFIG=${dsmconfig};${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin64${SS}dsmadmc -id=${adminid} -pass=${adminpw} q pr";
        $createvolCmd =
"export DSM_CONFIG=${dsmconfig};${SS}usr${SS}tivoli${SS}tsm${SS}client${SS}ba${SS}bin64${SS}dsmadmc -id=${adminid} -pass=${adminpw} macro \"$createpreallocvolumesmacroname\"";
    }
    elsif ( $platform eq "WIN32" ) {
        $qprocessCmd  = "${instdirmntpnt}${SS}queryprocess.bat";
        $createvolCmd = "${instdirmntpnt}${SS}createvolumes.bat";

        $stateHash{qprocesscmdfile}  = $qprocessCmd;
        $stateHash{createvolcmdfile} = $createvolCmd;

        if ( open( QPROCCMDFH, ">$qprocessCmd" ) ) {
            print QPROCCMDFH "\@echo off\n";
            print QPROCCMDFH "set DSM_CONFIG=${dsmconfig}\n";
            print QPROCCMDFH
"${baclientPath}${SS}dsmadmc -id=${adminid} -pass=${adminpw} q pr";
            close QPROCCMDFH;
        }

        if ( open( CREATEVOLCMDFH, ">$createvolCmd" ) ) {
            print CREATEVOLCMDFH "\@echo off\n";
            print CREATEVOLCMDFH "set DSM_CONFIG=${dsmconfig}\n";
            print CREATEVOLCMDFH
"${baclientPath}${SS}dsmadmc -id=${adminid} -pass=${adminpw} macro \"$createpreallocvolumesmacroname\"";
            close CREATEVOLCMDFH;
        }
    }

    foreach $stginfo ( @{$numpreAllocatedvols} ) {
        if ( $stginfo->{numvols} > 0 ) {
            $pth          = $stginfo->{stgdir};
            $enclosingmpt = getencompassingmountpoint($pth);
            my $mptfound = 0;

            foreach $mptinfo (@stgmntpntsallocatedvolumesArray) {
                $mpt = $mptinfo->{mountpoint};

                if ( $enclosingmpt eq "$mpt" ) {
                    $mptinfo->{numvols} += $stginfo->{numvols};
                    $mptfound = 1;
                }
            }

            if ( $mptfound == 0 ) {
                my $mptinfo = {};

                $mptinfo->{mountpoint} = $enclosingmpt;
                $mptinfo->{numvols}    = $stginfo->{numvols};

                push( @stgmntpntsallocatedvolumesArray, $mptinfo );
            }
        }
    }

    # compute the number of batches in which the volumes will be created

    $numbervolumebatches              = 0;
    $numbermntpntswithpreallocvolumes = 0;

    foreach $mptinfo (@stgmntpntsallocatedvolumesArray) {
        if ( $mptinfo->{numvols} > $numbervolumebatches ) {
            $numbervolumebatches = $mptinfo->{numvols};
        }
        $numbermntpntswithpreallocvolumes++;
    }

# if all preallocated volumes are under one mount point, create them in batches where there
# are $maxGPFSbatchsize volumes (at most) in each batch

    if ( $numbermntpntswithpreallocvolumes == 1 ) {
        if ( $totalPreallocatedVolumes % $maxGPFSbatchsize > 0 ) {
            $numbervolumebatches =
              1 + int( $totalPreallocatedVolumes / $maxGPFSbatchsize );
        }
        else {
            $numbervolumebatches =
              int( $totalPreallocatedVolumes / $maxGPFSbatchsize );
        }
    }

    $volcnt = 0;

    logentry(
"        The pre-allocated volumes will be created in $numbervolumebatches batches\n\n"
    );

    for ( $batchcnt = 0 ; $batchcnt < $numbervolumebatches ; $batchcnt++ ) {

        # create macro to define this batch of volumes

        if ( -f $createpreallocvolumesmacroname ) {
            unlink($createpreallocvolumesmacroname);
        }

        $initialvolcnt    = $volcnt;
        $initialvolcnthex = sprintf( "%08x", $initialvolcnt );

        # Draw progress bar

        refreshVolumeCreationProgress($numHashes);

        if ( $numbermntpntswithpreallocvolumes > 1
          ) # there are at least 2 different mount points with storage volumes to be allocated under them
        {
            if ( open( CRVOLH, ">$createpreallocvolumesmacroname" ) ) {
                foreach $mptinfo (@stgmntpntsallocatedvolumesArray) {
                    $mpt                          = $mptinfo->{mountpoint};
                    $volumecreatedundercurrentmpt = 0;

                    foreach $stginfo ( @{$numpreAllocatedvols} ) {
                        $pth = $stginfo->{stgdir};
                        if ( $volumecreatedundercurrentmpt == 0 ) {
                            $enclosingmpt = getencompassingmountpoint($pth);

                            if (   ( $enclosingmpt eq "$mpt" )
                                && ( $stginfo->{numvols} > 0 ) )
                            {
                                $volnamehex = sprintf( "%08x", $volcnt );
                                $preallocatedvolname =
                                    "$pth" . "${SS}"
                                  . "$volnamehex"
                                  . ".BFS";    # will be size maxcap
                                $preallocationcmd =
"def vol deduppool $preallocatedvolname formatsize=${maxcapinMB}";
                                print CRVOLH "$preallocationcmd\n";
                                $stginfo->{numvols} -= 1;
                                $volumecreatedundercurrentmpt = 1;
                                $volcnt++;
                            }
                        }
                    }
                }
                close CRVOLH;
            }
            else {
                return 1;
            }
        }
        elsif ( $numbermntpntswithpreallocvolumes == 1
          ) # there is just one mount points with storage volumes to be allocated under it
        {
            if ( open( CRVOLH, ">$createpreallocvolumesmacroname" ) ) {
                for ( $v = 0 ; $v < $maxGPFSbatchsize ; $v++ ) {
                    foreach $stginfo ( @{$numpreAllocatedvols} ) {
                        $pth = $stginfo->{stgdir};

                        if ( $stginfo->{numvols} > 0 ) {
                            $volnamehex = sprintf( "%08x", $volcnt );
                            $preallocatedvolname =
                                "$pth" . "${SS}"
                              . "$volnamehex"
                              . ".BFS";    # will be size maxcap
                            $preallocationcmd =
"def vol deduppool $preallocatedvolname formatsize=${maxcapinMB}";
                            print CRVOLH "$preallocationcmd\n";
                            $stginfo->{numvols} -= 1;
                            $volcnt++;
                        }
                    }
                }
                close CRVOLH;
            }
            else {
                return 1;
            }
        }

        $finalvolcnt    = $volcnt - 1;
        $finalvolcnthex = sprintf( "%08x", $finalvolcnt );

# now run the macro and then issue periodic "query process" commands until volumes in this batch are created

        $currenttime = localtime();

        logentry(
"Step ${stpn}_${substep}: Starting macro to generate volumes $initialvolcnthex to $finalvolcnthex at time $currenttime\n\n",
            1
        );

        @createvolCmdOut = `$createvolCmd`;

        $progincrm = 0;

        do {
            $progadvanced = 0;

            while ( $progincrm < $secondsperbatch
              ) # taking about 5 seconds per batch here (can adjust according to server scale, type of filesystem, and so on)
            { # works best if $secondsperbatch is maybe slightly larger than the actual number of seconds the server
                sleep 1;    # needs to create a batch of volumes
                $progadvanced = 1;
                $progdelta    = int( ( $progincrm * $progressbarwidth ) /
                      ( $secondsperbatch * $numbervolumebatches ) );
                refreshVolumeCreationProgress( $numHashes + $progdelta );
                $progincrm++;
            }

            if ( $progadvanced == 0
              ) # if we get here the server is still working on the current batch, so just wait a bit without advancing the progress bar
            {
                sleep 5;
            }

            $definevolprocessescomplete = 1;

            @qprocessCmdOut = `$qprocessCmd`;

            foreach $qprocessoutln (@qprocessCmdOut) {
                if ( $qprocessoutln =~ m#DEFINE\s+VOLUME#i ) {
                    $definevolprocessescomplete = 0;
                }
            }
        } while ( $definevolprocessescomplete == 0 );

        $numHashes = int(
            ( ( $batchcnt + 1 ) * $progressbarwidth ) / $numbervolumebatches );

    }

    return 0;
}

############################################################
#      sub: refreshVolumeCreationProgress
#     desc: displays a progress bar to indicate the amount of
#           progress in preallocated volume creation
#
#   params: 1. number of hashes (#) to show in the progress bar
#
#  returns: none
#
############################################################

sub refreshVolumeCreationProgress {
    $nH = shift(@_);

    $progressbarwidth = 50;

    $okstring1 = genresultString( $generateRunfileString, 55, "[OK]" );
    displayString( 10, 3, $okstring1, 1, $stpn );
    $okstring2 = genresultString( $initServerString1, 55, "[OK]" );
    displayString( 10, 3, $okstring2 );
    $okstring3 = genresultString( $startingServerString, 55, "[OK]" );
    displayString( 10, 3, $okstring3 );
    $okstring4 = genresultString( $initServerString2, 55, "[OK]" );
    displayString( 10, 3, $okstring4 );
    displayString( 10, 3, $initServerString3 );

    $progressLine = "Progress  [";

    for ( $j = 0 ; $j < $nH ; $j++ ) {
        $progressLine = "$progressLine" . "#";
    }

    for ( $j = 0 ; $j < ( $progressbarwidth - $nH ) ; $j++ ) {
        $progressLine = "$progressLine" . " ";
    }

    $progressLine = "$progressLine" . "]";

    displayString( 10, 3, $progressLine );
}

############################################################
#      sub: logentry
#     desc: appends an entry to the script log
#
#   params: 1. string to append to the script log
#           2. optional parameter which, if not null, means
#              increment the substep number
#
#  returns: none
#
############################################################

sub logentry {
    $info            = shift(@_);
    $incrsubstepflag = shift(@_);

    open( LOGH, ">>$serversetupLog" ) or die "Unable to open $serversetupLog\n";

    print LOGH "$info";

    close LOGH;

    if ( $incrsubstepflag ne "" ) {
        $substep++;
    }
}

############################################################
#      sub: sufficientspaceexists
#     desc: determines if the remaining freespace of the
#           filesystem containing the first argument is
#           at least the value of the second argument, and
#           if so, adjusts the value freeSpaceHash for that
#           filesystem accordingly
#
#   params: 1. directory path
#           2. amount of remaining freespace required
#           3. optional reference argument so that, if not
#              null, then the variable it references is set to
#              the remaining free space
#
#  returns: 1 if the remaining free space in the filesystem
#             of which the first argument is a subdirectory is
#             at least the value specified by the second parameter
#           0 otherwise
############################################################

sub sufficientspaceexists {
    my $pth           = shift(@_);
    my $spacerequired = shift(@_);
    my $freespaceref  = shift(@_);

    my $enclosingmpt = getencompassingmountpoint($pth);

    $freeSpaceHash = $stateHash{freespacehash};

    if ( !( exists( $freeSpaceHash->{$enclosingmpt} ) )
      )    # if there is no entry yet for this filesystem in the
    {      # freeSpaceHash, then create the entry, specifying
        my $freespce = getFreeSpace($pth)
          ;    # for the value the value returned by the getFreeSpace
        $freeSpaceHash->{$enclosingmpt} = $freespce;    # subroutine
    }

    if ( $freeSpaceHash->{$enclosingmpt} >=
        $spacerequired )    # if the remaining amount of freespace is at
    {                       # least the space required, set the variable
        if ( $freespaceref ne "" )   # referenced by the third argument to that
        {                            # amount, if it is not null; also decrement
            $$freespaceref = $freeSpaceHash->{$enclosingmpt}
              ;                      # the freeSpaceHash entry by the required
        }    # amount of free space, which is the new
        $freeSpaceHash->{$enclosingmpt} -=
          $spacerequired;    # value for the "remaining" free space for
        return 1;            # filesystem containing the first argument, and
    }    # return 1
    else {
        if ( $freespaceref ne "" ) {
            $$freespaceref = $freeSpaceHash->{$enclosingmpt};
        }
        return 0;
    }
}

############################################################
#      sub: sufficientspaceexistsExt
#     desc: like sufficientspaceexists but takes as its first
#           argument a reference to an array of paths
#
#   params: 1. reference to array of directory paths
#           2. amount of total remaining freespace required
#              (taking into account all the paths in the array
#              referenced by the first argument)
#           3. optional reference argument so that, if not
#              null, then entries in the array it references are set to
#              the remaining free space for the distinct filesystems
#              containing the directory paths in the array referenced
#              by the first argument
#           4. optional reference argument so that, if not
#              null, then the variable it references is set to
#              the overall total amount of remaining free space
#              for the distinct filesystems containing the directory
#              paths in the array referenced by the first argument
#
#  returns: 1 if the total remaining free space in the filesystems
#             containing the paths in the array referenced by the
#             first argument is at least the value specified
#             by the second argument
#           0 otherwise
############################################################

sub sufficientspaceexistsExt {
    my $pthArrayRef        = shift(@_);
    my $totalspacerequired = shift(@_);
    my $freespacearrref    = shift(@_);
    my $freespacetotalref  = shift(@_);

    my $totalspaceavailable = 0;
    my $totalspacelefttodeduct;

    my @distinctmountpntsfromthiscall =
      ();    # distinct mount points encountered just for the paths in
             # the array referenced by pthArrayRef (so, for example, if they
             # are all under the same filesystem, then this array will end up
             # having only one member)

    $freeSpaceHash = $stateHash{freespacehash};

    # get the list of distinct filesystems that appear among the
    # filesystems containing the various paths in the first argument, creating
    # new entries in the freeSpaceHash for the ones that do not yet have
    # entries

    foreach $pth ( @{$pthArrayRef} ) {
        $enclosingmpt = getencompassingmountpoint($pth);

        if ( !( exists( $freeSpaceHash->{$enclosingmpt} ) ) ) {
            my $freespce = getFreeSpace($pth);
            $freeSpaceHash->{$enclosingmpt} = $freespce;
        }

        my $mptfound = 0;

        foreach $mpt (@distinctmountpntsfromthiscall) {
            if ( "$enclosingmpt" eq "$mpt" ) {
                $mptfound = 1;
            }
        }

        if ( $mptfound == 0 ) {
            push( @distinctmountpntsfromthiscall, $enclosingmpt )
              ;    # add the mountpoint if not already there
        }
    }

    # get the total available remaining free space for the filesystems
    # containing the paths in array referenced by pthArrayRef
    # that is, the total available remaining free space in the
    # filesystems now included in the distinctmountpntsfromthiscall
    # array

    foreach $mntpnt (@distinctmountpntsfromthiscall) {
        $totalspaceavailable += $freeSpaceHash->{$mntpnt};
    }

    # if the total remaining free space is at least the required
    # total amount, adjust the freeSpaceHash entries accordingly, and
    # return 1

    if ( $totalspaceavailable >= $totalspacerequired ) {
        $totalspacelefttodeduct = $totalspacerequired;

        foreach $mntpnt (@distinctmountpntsfromthiscall) {
            if ( $freespacearrref ne "" ) {
                my $mntpntinfo = {};
                $mntpntinfo->{mountpoint} = $mntpnt;
                $mntpntinfo->{freespace}  = $freeSpaceHash->{$mntpnt};
                push( @{$freespacearrref}, $mntpntinfo );
            }
            if ( $freespacetotalref ne "" ) {
                $$freespacetotalref += $freeSpaceHash->{$mntpnt};
            }

            if ( $totalspacelefttodeduct > $freeSpaceHash->{$mntpnt} ) {
                $totalspacelefttodeduct -= $freeSpaceHash->{$mntpnt};
                $freeSpaceHash->{$mntpnt} = 0;
            }
            else {
                $freeSpaceHash->{$mntpnt} =
                  $freeSpaceHash->{$mntpnt} - $totalspacelefttodeduct;
                $totalspacelefttodeduct = 0;
            }
        }

        return 1;
    }
    else {
        $$freespacetotalref += $totalspaceavailable;
        return 0;
    }
}

############################################################
#      sub: getFreeSpace
#     desc: gets the amount of free space (in KB) in the filesystem
#           encompassing the specified directory
#
#   params: 1. The mount point of the filesystem whose free space is
#              to be needed
#
#  returns: the amount of free space in KB
#
############################################################

sub getFreeSpace {
    $pth = shift(@_);

    $enclosingmntpnt = getencompassingmountpoint($pth);

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $dfcmd = "df -k $enclosingmntpnt";
        logentry("        Issuing command: $dfcmd\n");
        @dfOut = `$dfcmd`;

    }
    elsif ( $platform eq "WIN32" ) {
        `echo 12345abcde > ${enclosingmntpnt}${SS}file01`
          ; # need a file there in order to get information about the amount of free space
        $dircmd = "cmd /c dir $enclosingmntpnt";
        logentry("        Issuing command: $dircmd\n");
        @dirOut = `$dircmd`;
        unlink "${enclosingmntpnt}${SS}file01";
    }

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        foreach $dfoutlne (@dfOut) {
            logentry("        $dfoutlne\n");
            if (
                ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) )
                && ( $dfoutlne =~
                    m/\d+\s+\d+\s+(\d+)\s+\d+\%\s+$enclosingmntpnt/ )
              )
            {
                $freespc = $1;
            }
            elsif (
                ( $platform eq "AIX" )
                && ( $dfoutlne =~
m/\S+\s+\d+\s+(\d+)\s+\d+\%\s+\d+\s+\d+\%\s+$enclosingmntpnt/
                )
              )
            {
                $freespc = $1;
            }
        }
    }
    elsif ( $platform eq "WIN32" ) {
        foreach $diroutlne (@dirOut) {
            if ( $diroutlne =~ m/\d+\s+\w+\(\w+\)\,*\s+(\S+)\s+bytes\s+\w+/i ) {
                $freespcwithcommas = $1;
                $freespcwithcommas =~ s/\,//g;
                $freespcnocommas = $freespcwithcommas;
                $freespcnocommas =~
                  s/\.//g;    # non-English may use a different separator

                #       @freespcparts = split(/,/, $freespcwithcommas);
                #        $freespcnocommas = join('', @freespcparts);
                $freespc = int( $freespcnocommas / 1024 );
                logentry("        $diroutlne\n");
            }
        }
    }
    return $freespc;
}

############################################################
#      sub: isEmptyDir
#     desc: determine if a filesystem mount point is empty
#           (disregarding subdirectories of that mount point
#           which form an initial sub path of the mount point of
#           a different filesystem)
#
#   params: 1. The mount point
#
#  returns: 1 if the mount point is empty
#           0 if it is not empty
#
############################################################

sub isEmptyDir {
    $dpth = shift(@_);

    $isempty = 1;

    opendir( DIRH, $dpth );
    local @objList = readdir(DIRH);
    closedir(DIRH);

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        foreach $item (@objList) {
            unless ( ( "$item" eq "." )
                or ( "$item" eq ".." )
                or ( "$item" eq "lost+found" ) )
            {
                local $fullPath = $dpth . "$SS" . $item;
                if ( isprefixofmountpoint($fullPath) ==
                    0 )   # $fullPath only is considered if it is not an initial
                {         # sub path of another filesystem mount point
                    $isempty = 0;
                }
            }
        }
    }
    elsif ( $platform eq "WIN32" ) {
        foreach $item (@objList)
        { # for this check we tolerate the presence of $RECYCLE.BIN, but is will be removed later
            unless ( ( "$item" eq "." )
                or ( "$item" eq ".." )
                or ( "$item" eq "System Volume Information" )
                or ( $item eq "\$RECYCLE.BIN" ) )
            {
                $isempty = 0;
            }
        }
    }

    return $isempty;
}

############################################################
#      sub: isprefixofmountpoint
#     desc: determine if the path specified by the first argument
#           is an initial sub path of a mounted file system mount
#           point (or GPFS mountpoint)
#
#   params: 1. The path to check
#
#  returns: 1 if the path is an initial sub path of a mounted
#             filesystem mount point
#           0 if it is not an initial sub path of a mounted
#             filesystem mount point
#
############################################################

sub isprefixofmountpoint {
    $pth = shift(@_);

    local $isprefix = 0;

    foreach $mntpnt (@mountedfs) {
        local $currprefix = $mntpnt;

        if ( $platform eq "WIN32" ) {
            if ( uc($currprefix) eq uc($pth) ) {
                $isprefix = 1;
            }
        }
        else {
            if ( "$currprefix" eq "$pth" ) {
                $isprefix = 1;
            }
        }

        $lastdelimiterindex = rindex( $currprefix, "$SS" );

        while ( ( $lastdelimiterindex >= 0 ) && ( $isprefix == 0 ) ) {
            $currprefix = substr( $currprefix, 0, $lastdelimiterindex );

            if ( $platform eq "WIN32" ) {
                if ( uc($currprefix) eq uc($pth) ) {
                    $isprefix = 1;
                }
            }
            else {
                if ( "$currprefix" eq "$pth" ) {
                    $isprefix = 1;
                }
            }
            $lastdelimiterindex = rindex( $currprefix, "$SS" );
        }
    }

    foreach $mntpnt (@mountedgpfs) {
        local $currprefix = $mntpnt;

        if ( $platform eq "WIN32" ) {
            if ( uc($currprefix) eq uc($pth) ) {
                $isprefix = 1;
            }
        }
        else {
            if ( "$currprefix" eq "$pth" ) {
                $isprefix = 1;
            }
        }

        $lastdelimiterindex = rindex( $currprefix, "$SS" );

        while ( ( $lastdelimiterindex >= 0 ) && ( $isprefix == 0 ) ) {
            $currprefix = substr( $currprefix, 0, $lastdelimiterindex );

            if ( $platform eq "WIN32" ) {
                if ( uc($currprefix) eq uc($pth) ) {
                    $isprefix = 1;
                }
            }
            else {
                if ( "$currprefix" eq "$pth" ) {
                    $isprefix = 1;
                }
            }
            $lastdelimiterindex = rindex( $currprefix, "$SS" );
        }
    }
    return $isprefix;
}

############################################################
#      sub: createsubdirsundermntpnt
#     desc: creates specified subdirectory (and intermediate dirs
#           if need be) of a mount point if is does not already exist,
#           and if a subdirectory is created, it is recorded under the
#           "createddirs" key in the stateHash (used in GPFS environments,
#           or if -skipmount is specfied)
#
#   params: 1. The path to create if not already existing
#
#  returns: an array consisting of a return code (0 if no mkdir
#           failed, and 1 if a mkdir attempt failed), and a suitable
#           message in case of failure
#
############################################################

sub createsubdirsundermntpnt {
    $pth = shift(@_);

    my $mkdirrc = 0;

    if ( ( index( $pth, " " ) < 0 ) && ( index( $pth, "	" ) < 0 ) ) {

        $enclosingmntpnt = getencompassingmountpoint($pth);

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            if ( $enclosingmntpnt eq "/" ) {
                $enclosingmntpnt = "";
            }
        }

        $pathaftermntpnt = substr( $pth, length($enclosingmntpnt) + 1 );

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            @subdirstoverify = split( '/', $pathaftermntpnt );
        }
        elsif ( $platform eq "WIN32" ) {
            @subdirstoverify = split( /\\/, $pathaftermntpnt );
        }

        $numofsubdirs = @subdirstoverify;
        $subdirnum    = 0;

        $parentpath = $enclosingmntpnt;

        while (( $mkdirrc == 0 )
            && ( $subdirnum < $numofsubdirs )
          ) # keep making subdirs as needed as long as there is no error from mkdir
        {
            $subdir     = $subdirstoverify[$subdirnum];
            $subdirpath = "$parentpath" . "${SS}" . "$subdir";

            if ( !-d $subdirpath ) {
                logentry("        Issuing commmand: mkdir $subdirpath\n");
                $mkdirrc = system("mkdir $subdirpath");
                if ( $mkdirrc == 0 ) {
                    push( @{ $stateHash{createddirs} }, $subdirpath );
                }
                else {
                    logentry(
"        There was an error attempting to create subdirectory $subdirpath\n"
                    );
                }
            }
            $parentpath = $subdirpath;
            $subdirnum++;
        }

        if ( $mkdirrc != 0 ) {
            my @rcArray = ( 1, "see log $stateHash{logname}" );
            return @rcArray;
        }
        else {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }

    }
    else {
        logentry("        $pth has a space\n");
        my @rcArray = ( 1, "has space" );
        return @rcArray;
    }
}

############################################################
#      sub: getencompassingmountpoint
#     desc: determines the mountpoint of the filesystem
#           containing the path specified by the argument
#
#   params: 1. The path whose mount point is to be determined
#
#  returns: the mount point of the filesystem containing the
#           path specified by the first argument
#
############################################################

sub getencompassingmountpoint {
    $pth = shift(@_);

    local $currpath        = $pth;
    local $mountpointfound = 0;

    foreach $mntpnt (@mountedfs) {
        if ( $platform eq "WIN32" ) {
            if ( uc($mntpnt) eq uc($currpath) ) {
                $mountpointfound = 1;
            }
        }
        else {
            if ( "$mntpnt" eq "$currpath" ) {
                $mountpointfound = 1;
            }
        }
    }

    foreach $mntpnt (@mountedgpfs) {
        if ( $platform eq "WIN32" ) {
            if ( uc($mntpnt) eq uc($currpath) ) {
                $mountpointfound = 1;
            }
        }
        else {
            if ( "$mntpnt" eq "$currpath" ) {
                $mountpointfound = 1;
            }
        }
    }

    $lastdelimiterindex = rindex( $currpath, "$SS" );

    while ( ( $lastdelimiterindex >= 0 ) && ( $mountpointfound == 0 ) ) {
        $currpath = substr( $currpath, 0, $lastdelimiterindex );

        foreach $mntpnt (@mountedfs) {
            if ( $platform eq "WIN32" ) {
                if ( uc($mntpnt) eq uc($currpath) ) {
                    $mountpointfound = 1;
                }
            }
            else {
                if ( "$mntpnt" eq "$currpath" ) {
                    $mountpointfound = 1;
                }
            }
        }

        foreach $mntpnt (@mountedgpfs) {
            if ( $platform eq "WIN32" ) {
                if ( uc($mntpnt) eq uc($currpath) ) {
                    $mountpointfound = 1;
                }
            }
            else {
                if ( "$mntpnt" eq "$currpath" ) {
                    $mountpointfound = 1;
                }
            }
        }

        $lastdelimiterindex = rindex( $currpath, "$SS" );
    }

    if ( length($currpath) == 0 ) {
        return "$SS";
    }
    else {
        return $currpath;
    }
}

############################################################
#      sub: logcontents
#     desc: logs the contents of the path specified by the
#           first argument to the script log (disregarding
#           subdirectories of that path which form
#           an initial sub path of the mount point of
#           another filesystem). It is called in those cases
#           where a file system mount point specified by
#           the user is not empty but should be empty
#
#   params: 1. The path whose contents are to be logged
#
#  returns: none
#
############################################################

sub logcontents {
    local $dpth = shift(@_);

    opendir( DIRH, $dpth );
    local @objList = readdir(DIRH);
    closedir(DIRH);

    foreach $item (@objList) {
        unless ( ( "$item" eq "." )
            or ( "$item" eq ".." )
            or ( "$item" eq "lost+found" ) )
        {
            local $newPath = $dpth . "${SS}" . $item;

            if ( isprefixofmountpoint($newPath) == 0 ) {
                if ( -f $newPath ) {
                    logentry("        $newPath\n");
                }
                elsif ( -d $newPath ) {
                    logentry("        $newPath\n");
                    logcontents($newPath);
                }
            }
        }
    }
}

############################################################
#      sub: issubpath
#     desc: determines if the second argument is an initial sub
#           path of the first argument
#
#   params: 1. The first path
#           2. The second path
#
#  returns: 1 if the second path is an initial sub path of the
#             first path
#           0 if the second path is not an initial sub path of
#             the first path
#
############################################################

sub issubpath {
    $pth1 = shift(@_);
    $pth2 = shift(@_);

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        @pth1subdirs = split( '/', "$pth1" );
        @pth2subdirs = split( '/', "$pth2" );
    }
    elsif ( $platform eq "WIN32" ) {
        @pth1subdirs = split( /\\/, "$pth1" );
        @pth2subdirs = split( /\\/, "$pth2" );
    }

    $l1 = @pth1subdirs;
    $l2 = @pth2subdirs;

    $isasubpath = 1;
    $i          = 0;

    if ( $l1 < $l2 ) {
        return 0;
    }
    else {
        for ( $i = 0 ; $i < $l2 ; $i++ ) {
            if ( "$pth1subdirs[$i]" ne "$pth2subdirs[$i]" ) {
                $isasubpath = 0;
            }
        }
    }

    return $isasubpath;
}

############################################################
#      sub: getlogHeader
#     desc: constructs the log header string based on the current
#           time, hostname, IP address and other parameters of
#           the machine on which this script is being run
#
#   params: none
#
#  returns: the log header string
#
############################################################

sub getlogHeader {
    @cur    = localtime();
    $day    = $cur[4] + 1;    # Adjust month 0..11 range to 1..12 range
    $day    = "0" . $day    if ( $day < 10 );       # Adjust month 0 as 00
    $cur[5] = $cur[5] - 100 if ( $cur[5] > 99 );    # Adjust year 2000 as 00
    $cur[5] = "0" . $cur[5] if ( $cur[5] < 10 );    # Adjust year 0 as 00
    $cur[3] = "0" . $cur[3] if ( $cur[3] < 10 );    # Adjust day 0 as 00

    $hostIP = getIPAddress($thehostname);

    $osname = getOSname();
    if ( $platform eq "LINUX86" || $platform eq "WIN32" ) {
        $arch = "Intel x86_64";
    }
    elsif ( $platform eq "AIX" || $platform eq "LINUXPPC" ) {
        $arch = "PowerPC64 big endian";
    }
    elsif ( $platform eq "LINUXPPCLE" ) {
        $arch = "PowerPC64 little endian";
    }
    else {
        $arch = "Unknown";
    }

    $memoryByMB = getSystemMemoryByKB() / 1024;
    %cpu        = getCPUinfo();

    $line =
"********************************************************************************\n";
    my $longtestcase = "**  IBM Storage Protect server setup script log\n";
    my $date =
      sprintf( "**  Date:  %2.2d/%2.2d/%2.2d", $cur[5], $day, $cur[3] );
    my $time     = sprintf( " %2.2d:%2.2d:%2.2d\n", $cur[2], $cur[1], $cur[0] );
    my $p_host   = "**  host:  $thehostname \/ $hostIP\n";
    my $p_osname = "**    OS:  $osname\n";
    my $p_arch   = "**  arch:  $arch\n";
    my $p_mem    = sprintf( "**   Mem:  %d MB\n", $memoryByMB );
    my $p_cpu;

    if ( $platform eq "AIX" ) {
        $p_cpu = "**   CPU:  $cpu{totalcores} total cores $cpu{cpuMHz}MHz\n";
    }
    else {
        $p_cpu =
"**   CPU:  $cpu{socketcount} sockets, $cpu{corespersocket} cores per socket, $cpu{totalcores} total cores $cpu{cpuMHz}MHz\n";
    }
    $banner =
        $line
      . $longtestcase
      . $date
      . $time
      . $p_host
      . $p_osname
      . $p_arch
      . $p_mem
      . $p_cpu
      . $line;
    return $banner;
}

############################################################
#      sub: getIPAddress
#     desc: gets the IP address from the hostname of the
#           machine on which the script is being run
#
#   params: 1. hostname
#  returns: the IP address
#
############################################################

sub getIPAddress {
    $hostn = shift(@_);
    $ip    = gethostbyname($hostn);
    return inet_ntoa($ip);
}

############################################################
#      sub: getOSname
#     desc: gets operating system information for the
#           machine on which the script is being run, from
#           the /etc/issue file
#
#   params: none
#
#  returns: the operation system information
#
############################################################

sub getOSname {
    if ( $platform eq "LINUX86" || ( $platform =~ m/LINUXPPC/ ) ) {
        $osFile = "";
        if ( -f "/etc/SuSE-release" ) {
            $osFile = "/etc/SuSE-release";
        }
        elsif ( -f "/etc/redhat-release" ) {
            $osFile = "/etc/redhat-release";
        }
        elsif ( -f "/etc/lsb-release" ) {
            $osFile = "/etc/lsb-release";
        }
        else {
            $osnm = "Unrecognized Linux";
        }

        if ( $osFile ne "" ) {
            open( OSFILE, "<$osFile" ) or die "Can not open the File: $!";
            my @oscontents = <OSFILE>;
            close(OSFILE);

            $osnm = "";
            foreach $ln (@oscontents) {
                if ( $ln =~ m/.*(Red Hat Enterprise Linux Server.*)\s*/ ) {
                    $osnm = $1;
                }
                elsif ( $ln =~ m/.*(SUSE Linux Enterprise Server.*)\s*/ ) {
                    $osnm = $1;
                }
                elsif ( $ln =~ m/.*(Ubuntu\s.*)\s*/ ) {
                    $osnm = $1;
                }
                elsif ( $ln =~ m/PATCHLEVEL/ ) {
                    $osnm = $osnm . " " . $ln;
                }
            }
        }
    }
    elsif ( $platform eq "AIX" ) {
        $getosnamecmd = "uname -sv";

        @getosnamecmdOut = `$getosnamecmd`;

        foreach $ln (@getosnamecmdOut) {
            if ( $ln =~ m/^(\w+)\s+(\d+)/ ) {
                $osname = $1;
                $osver  = $2;
            }
        }
        $osnm = "$osname" . " " . "$osver";
    }
    elsif ( $platform eq "WIN32" ) {
        $getosnamecmd = "wmic os get name,OSArchitecture";

        @getosnamecmdOut = `$getosnamecmd`;
        foreach $getosnamecmdline (@getosnamecmdOut) {
            if ( $getosnamecmdline =~ m/^Micro/ ) {
                $firstpipepos = index( $getosnamecmdline, '|' );
                $osname = substr( $getosnamecmdline, 0, $firstpipepos - 1 );
            }
            if ( $getosnamecmdline =~ m/(\d+)-bit/ ) {
                $osarch = $1;
                $osarch = "$osarch" . "-bit";
            }
        }
        $osnm = "$osname" . " " . "$osarch";
    }
    return $osnm;
}

############################################################
#      sub: getSystemMemoryByKB
#     desc: gets the total memory for the machine on which
#           the script is being run, from the /proc/meminfo
#           file
#
#   params: none
#
#  returns: the total memory in KB
#
############################################################

sub getSystemMemoryByKB {
    if ( $platform eq "LINUX86" || $platform =~ m/LINUXPPC/ ) {
        open MEMFH, "</proc/meminfo";
        @memOut = <MEMFH>;
        close MEMFH;
        foreach $ln (@memOut) {
            if ( $ln =~ m/MemTotal:\s+(\d+) \w+/ ) {
                $mem = $1;
            }
        }
    }
    elsif ( $platform eq "AIX" ) {
        $getmemorycmd = "bootinfo -r";

        @getmemorycmdOut = `$getmemorycmd`;
        foreach $getmemorycmdline (@getmemorycmdOut) {
            if ( $getmemorycmdline =~ m/^(\d+)/ ) {
                $mem = $1;
            }
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $getmemorycmd = "wmic memorychip get capacity";
        $totalmem     = 0;

        @getmemorycmdOut = `$getmemorycmd`;
        foreach $getmemorycmdline (@getmemorycmdOut) {
            if ( $getmemorycmdline =~ m/^(\d+)/ ) {
                $meminbytes = $1;
                $totalmem += $meminbytes;
            }
        }
        $mem = int( $totalmem / 1024 );
    }
    return $mem;
}

############################################################
#      sub: getCPUinfo
#     desc: gets CPU information for the machine on which
#           the script is being run, from the /proc/cpuinfo
#           file
#
#   params: none
#
#  returns: a hash consisting of the cpu MHz, the core count
#           the number of CPUs, and the socket count
#
############################################################

sub getCPUinfo {
    %cpu              = {};
    $cpu{countcpus}   = 0;
    $cpu{socketcount} = 0;
    @cpuids           = ();

    if ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) ) {
        if ( $platform eq "LINUX86" ) {
            open CPUFH, "</proc/cpuinfo";
            @cpuOut = <CPUFH>;
            close CPUFH;

            foreach $ln (@cpuOut) {
                if ( $ln =~ m/^cpu\s+MHz\s*:\s*(\d+)/ ) {
                    $cpu{cpuMHz} = $1;
                }
            }
        }
        elsif ( $platform =~ m/LINUXPPC/ ) {
            open CPUFH, "</proc/cpuinfo";
            @cpuOut = <CPUFH>;
            close CPUFH;

            foreach $ln (@cpuOut) {
                if ( $ln =~ m/^clock\s*:\s*(\d+)\.\d+MHz\s*/ ) {
                    $cpu{cpuMHz} = $1;
                }
            }
        }

        # this section is common to both LINUX86 and LINUXPPC

        my @uniqueCores   = ();
        my @uniqueSockets = ();

        @lscpuOut = `lscpu -e`;

        foreach $lscpulne (@lscpuOut) {
            if (   $lscpulne =~ m/\d+\s+\d+\s+(\d+)\s+(\d+)\s+\S+\s+$yes/
                || $lscpulne =~ m/\d+\s+\d+\s+(\d+)\s+(\d+)\s+\S+\s+$yes_de/
                || $lscpulne =~ m/\d+\s+\d+\s+(\d+)\s+(\d+)\s+\S+\s+$yes_es/
                || $lscpulne =~ m/\d+\s+\d+\s+(\d+)\s+(\d+)\s+\S+\s+$yes_fr/
                || $lscpulne =~ m/\d+\s+\d+\s+(\d+)\s+(\d+)\s+\S+\s+$yes_pt_BR/
                || $lscpulne =~ m/\d+\s+\d+\s+(\d+)\s+(\d+)\s+\S+\s+$yes_ru/
                || $lscpulne =~ m/\d+\s+\d+\s+(\d+)\s+(\d+)\s+\S+\s+$yes_zh/ )
            {
                my $socketnum = $1;
                my $corenum   = $2;

                my $socketalreadyfound = 0;
                my $corealreadyfound   = 0;

                foreach $sckn (@uniqueSockets) {
                    if ( $socketnum == $sckn ) {
                        $socketalreadyfound = 1;
                    }
                }

                if ( $socketalreadyfound == 0 ) {
                    push( @uniqueSockets, $socketnum );
                }

                foreach $coren (@uniqueCores) {
                    if ( $corenum == $coren ) {
                        $corealreadyfound = 1;
                    }
                }

                if ( $corealreadyfound == 0 ) {
                    push( @uniqueCores, $corenum );
                }
            }
        }

        $cpu{socketcount} = @uniqueSockets;
        $cpu{totalcores}  = @uniqueCores;

        if ( $cpu{socketcount} > 0 ) {
            $cpu{corespersocket} = int( $cpu{totalcores} / $cpu{socketcount} );
        }
    }
    elsif ( $platform eq "AIX" ) {
        @getprocspeedOut = `prtconf`;

        foreach $ln (@getprocspeedOut) {
            if ( $ln =~ m/^Processor\s+Clock\s+Speed:\s+(\d+)\s+MHz/ ) {
                $cpu{cpuMHz} = $1;
            }
            elsif ( $ln =~ m/^Number\s+Of\s+Processors:\s+(\d+)/ ) {
                $cpu{totalcores} = $1;
            }
        }
    }
    elsif ( $platform eq "WIN32" ) {
        $getnumcorescmd = "wmic cpu get name,NumberOfCores";

        @getnumcorescmdOut = `$getnumcorescmd`;

        foreach $getnumcoresline (@getnumcorescmdOut) {
            if ( $getnumcoresline =~ m/@\s+(\S+)\s+(\d+)/ ) {
                $cpuspeed = $1;
                $cpu{corespersocket} = $2;
                if ( $cpuspeed =~ m/MHz/ ) {
                    $cpu{cpuMHz} =
                      substr( $cpuspeed, 0, length($cpuspeed) - 3 );
                }
                elsif ( $cpuspeed =~ m/GHz/ ) {
                    $cpuspeedinGHz =
                      substr( $cpuspeed, 0, length($cpuspeed) - 3 );
                    $cpu{cpuMHz} = $cpuspeedinGHz * 1024;
                }
                $cpu{socketcount}++;
            }
        }
    }
    elsif ( $platform =~ m/LINUXPPC/ ) {
        open CPUFH, "</proc/cpuinfo";
        @cpuOut = <CPUFH>;
        close CPUFH;

        foreach $ln (@cpuOut) {
            if ( $ln =~ m/^processor\s*:\s*(\d+)/ ) {
                $cpu{socketcount}++;
            }
            if ( $ln =~ m/^clock\s*:\s*(\d+)MHz\s*/ ) {
                $cpu{cpuMHz} = $1;
            }
        }
        $cpu{corespersocket} = 1;
    }

    if ( $platform ne "AIX" ) {
        $cpu{totalcores} = $cpu{socketcount} * $cpu{corespersocket};
    }

    return %cpu;
}

############################################################
#      sub: validateMemoryandCoreCount
#     desc: Checks the system memory (RAM), and CPU core count
#           to determine if they are sufficient for the previously
#           specified server scale
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for failure), a overall error message if there was
#           an error, and a reference to an array consisting
#           of a PASS or FAIL message for each respective item that
#           was checked (memory or core count)
#
############################################################

sub validateMemoryandCoreCount {
    $stpn = shift(@_);

    $memok       = 1;
    $corecountok = 1;

    %cpuinfohash = {};

    my @paramMsgs = ();

    logentry( "Step ${stpn}_${substep}: Check system memory\n", 1 );

    $memoryByKB = getSystemMemoryByKB();

    if ( $memoryByKB < $stateHash{memorymin} ) {
        push( @paramMsgs, genresultString( "Memory", 50, "FAIL" ) );
        logentry(
"        There is not enough memory on this machine for $stateHash{serverscale} server\n"
        );
        logentry(
            "        There should be at least $stateHash{memorymin} KB of RAM\n"
        );
        $memok = 0;
    }
    else {
        push( @paramMsgs, genresultString( "Memory", 50, "PASS" ) );
        logentry("        Memory in KB: $memoryByKB\n");
    }

    logentry( "Step ${stpn}_${substep}: Check CPU core count\n", 1 );

    %cpuinfohash = getCPUinfo();

    if ( $cpuinfohash{totalcores} < $stateHash{cpucoremin} ) {
        push( @paramMsgs, genresultString( "CPU Core Count", 50, "FAIL" ) );
        logentry(
"        There is not a sufficient number of cpu cores for $stateHash{serverscale} server\n"
        );
        logentry(
"        There should be at least $stateHash{cpucoremin} cpu cores\n"
        );
        $corecountok = 0;
    }
    else {
        push( @paramMsgs, genresultString( "CPU Core Count", 50, "PASS" ) );
        logentry("        CPU core count: $cpuinfohash{totalcores}\n");
    }

    if ( ( $memok == 0 ) || ( $corecountok == 0 ) ) {
        my @rcArray = ( 1, "insufficient memory or core count", \@paramMsgs );
        return @rcArray;
    }
    else {
        my @rcArray = ( 0, "", \@paramMsgs );
        return @rcArray;
    }
}

############################################################
#      sub: validateBackupStartTime
#     desc: Verifies that the time specified by the first
#           argument is in the correct 24 hour format with
#           hours and minutes (HH:MM)
#
#   params: 1. the time to be validated
#
#  returns: an array consisting of a return code (0 for valid format
#           1 for invalid format) and in the case of invalid format,
#           a short message to that effect
#
############################################################

sub validateBackupStartTime {
    $starttime = shift(@_);

    if ( ( length($starttime) == 5 ) && ( $starttime =~ m/(\d\d):(\d\d)/ ) ) {
        $sthours   = int($1);
        $stminutes = int($2);
        $stseconds = int($3);

        if (   ( ( $sthours >= 0 ) && ( $sthours <= 23 ) )
            && ( ( $stminutes >= 0 ) && ( $stminutes <= 59 ) ) )
        {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
        else {
            my @rcArray = ( 1, "invalid start time" );
            return @rcArray;
        }
    }
    else {
        my @rcArray = ( 1, "invalid start time" );
        return @rcArray;
    }
}

############################################################
#      sub: getBackupStartString
#     desc: Returns a string representing the time specified
#           by the argument (which is 24 hour format with
#           hours, minutes and seconds) but with AM or PM,
#           and dropping the seconds, and with underscores
#           connecting the hours and minutes, if the minutes
#           is not "00"
#
#   params: 1. the time in HH:MM:SS format to be converted
#
#  returns: a string representing the time of the first parameter
#           but with AM or PM and dropping the seconds
#
############################################################

sub getBackupStartString {
    $starttime = shift(@_);

    if ( $starttime =~ m/(\d\d):(\d\d):(\d\d)/ ) {
        $sthrs = $1;
        $stmin = $2;
        $stsec = $3;

        if ( int($sthrs) >= 13 ) {
            $sthrspm = $sthrs % 12;
            if ( $stmin eq "00" ) {
                return "$sthrspm" . "PM";
            }
            else {
                return "$sthrspm" . "_" . "$stmin" . "PM";
            }
        }
        elsif ( int($sthrs) == 12 ) {
            $sthrspm = "12";
            if ( $stmin eq "00" ) {
                return "$sthrspm" . "PM";
            }
            else {
                return "$sthrspm" . "_" . "$stmin" . "PM";
            }
        }
        elsif ( int($sthrs) < 12 ) {
            $sthrsam = "$sthrs";
            if ( $stmin eq "00" ) {
                return "$sthrsam" . "AM";
            }
            else {
                return "$sthrsam" . "_" . "$stmin" . "AM";
            }
        }
    }
}

############################################################
#      sub: getBackupStartPlusTen
#     desc: Returns a string representing the time specified
#           by the argument, plus 10 hours
#
#   params: 1. the time to which to add the 10 hours
#
#  returns: a string representing the time of the first parameter
#           plus 10 hours
#
############################################################

sub getBackupStartPlusTen {
    $starttime = shift(@_);

    if ( $starttime =~ m/(\d\d):(\d\d):(\d\d)/ ) {
        $sthours   = int($1);
        $stminutes = int($2);
        $stseconds = int($3);

        $sthoursplusten = ( $sthours + 10 ) % 24;
        if ( $sthoursplusten < 10 ) {
            $sthoursplusten = "0" . "$sthoursplusten";
        }
        if ( $stminutes < 10 ) {
            $stminutes = "0" . "$stminutes";
        }
        if ( $stseconds < 10 ) {
            $stseconds = "0" . "$stseconds";
        }
        return "$sthoursplusten" . ":" . "$stminutes" . ":" . "$stseconds";
    }
}

############################################################
#      sub: getBackupStartPlusThirteen
#     desc: Returns a string representing the time specified
#           by the argument, plus 13 hours
#
#   params: 1. the time to which to add the 13 hours
#
#  returns: a string representing the time of the first parameter
#           plus 13 hours
#
############################################################

sub getBackupStartPlusThirteen {
    $starttime = shift(@_);

    if ( $starttime =~ m/(\d\d):(\d\d):(\d\d)/ ) {
        $sthours   = int($1);
        $stminutes = int($2);
        $stseconds = int($3);

        $sthoursplusthirteen = ( $sthours + 13 ) % 24;
        if ( $sthoursplusthirteen < 10 ) {
            $sthoursplusthirteen = "0" . "$sthoursplusthirteen";
        }
        if ( $stminutes < 10 ) {
            $stminutes = "0" . "$stminutes";
        }
        if ( $stseconds < 10 ) {
            $stseconds = "0" . "$stseconds";
        }
        return "$sthoursplusthirteen" . ":" . "$stminutes" . ":" . "$stseconds";
    }
}

############################################################
#      sub: getBackupStartPlusFourteen
#     desc: Returns a string representing the time specified
#           by the argument, plus 14 hours
#
#   params: 1. the time to which to add the 14 hours
#
#  returns: a string representing the time of the first parameter
#           plus 14 hours
#
############################################################

sub getBackupStartPlusFourteen {
    $starttime = shift(@_);

    if ( $starttime =~ m/(\d\d):(\d\d):(\d\d)/ ) {
        $sthours   = int($1);
        $stminutes = int($2);
        $stseconds = int($3);

        $sthoursplusfourteen = ( $sthours + 14 ) % 24;
        if ( $sthoursplusfourteen < 10 ) {
            $sthoursplusfourteen = "0" . "$sthoursplusfourteen";
        }
        if ( $stminutes < 10 ) {
            $stminutes = "0" . "$stminutes";
        }
        if ( $stseconds < 10 ) {
            $stseconds = "0" . "$stseconds";
        }
        return "$sthoursplusfourteen" . ":" . "$stminutes" . ":" . "$stseconds";
    }
}

############################################################
#      sub: getBackupStartPlusSeventeen
#     desc: Returns a string representing the time specified
#           by the argument, plus 17 hours
#
#   params: 1. the time to which to add the 17 hours
#
#  returns: a string representing the time of the first parameter
#           plus 17 hours
#
############################################################

sub getBackupStartPlusSeventeen {
    $starttime = shift(@_);

    if ( $starttime =~ m/(\d\d):(\d\d):(\d\d)/ ) {
        $sthours   = int($1);
        $stminutes = int($2);
        $stseconds = int($3);

        $sthoursplusseventeen = ( $sthours + 17 ) % 24;
        if ( $sthoursplusseventeen < 10 ) {
            $sthoursplusseventeen = "0" . "$sthoursplusseventeen";
        }
        if ( $stminutes < 10 ) {
            $stminutes = "0" . "$stminutes";
        }
        if ( $stseconds < 10 ) {
            $stseconds = "0" . "$stseconds";
        }
        return
            "$sthoursplusseventeen" . ":"
          . "$stminutes" . ":"
          . "$stseconds";
    }
}

############################################################
#      sub: validateKernelParams
#     desc: Checks the system kernel parameters, to determine
#           if they are set to the recommended minimums
#
#   params: 1. the step number
#
#  returns: an array consisting of a return code (0 for success,
#           1 for error), a overall error message if there was
#           an error, and a reference to an array consisting
#           of a PASS or FAIL message for each respective kernel
#           paramater that was checked, and a structure containing
#           information about which kernel parameters need
#           to be modified, if any, and if so, what values
#           they should be modified to be (used in a subsequent call
#           to updateKernelParams)
#
############################################################

sub validateKernelParams {
    $stpn = shift(@_);

    logentry( "Step ${stpn}_${substep}: Check kernel parameters\n", 1 );

    $memoryByKB = getSystemMemoryByKB();

    $sysctlcmd = "sysctl -a";

    @sysctlOut = `$sysctlcmd`;

    $newkernelparamsRef = {};

    $shmmaxok            = 1;
    $shmallok            = 1;
    $shmmniok            = 1;
    $semok               = 1;
    $msgmniok            = 1;
    $msgmaxok            = 1;
    $msgmnbok            = 1;
    $rand_va_spaceok     = 1;
    $vm_swappinessok     = 1;
    $vm_overcommit_memok = 1;

    my @paramMsgs = ();

    foreach $sysctlline (@sysctlOut) {
        if ( $kernelFlag && $sysctlline =~ m/\s*kernel.shmmax\s+=\s+(\d+)\s*/ )
        {
            $shmmax_val = $1;
            $shmmax_min = $memoryByKB * 1024;

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $shmmax_val < $shmmax_min ) {
                push( @paramMsgs,
                    genresultString( "kernel.shmmax", 50, "FAIL" ) );
                logentry(
"        kernel.shmmax is too small. It should be at least $shmmax_min\n"
                );
                $shmmaxok                   = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = $shmmax_min;
            }
            else {
                push( @paramMsgs,
                    genresultString( "kernel.shmmax", 50, "PASS" ) );
                logentry("        kernel.shmmax: $shmmax_val\n");
                $paraminfo->{val} = $shmmax_val;
            }
            $newkernelparamsRef->{shmmax} = $paraminfo;
        }
        elsif ($kernelFlag
            && $sysctlline =~ m/\s*kernel.shmall\s+=\s+(\d+)\s*/ )
        {
            $shmall_val = $1;
            $shmall_min = int( ( $memoryByKB * 1024 * 2 ) / 4096 );

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $shmall_val < $shmall_min ) {
                push( @paramMsgs,
                    genresultString( "kernel.shmall", 50, "FAIL" ) );
                logentry(
"        kernel.shmall is too small. It should be at least $shmall_min\n"
                );
                $shmallok                   = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = $shmall_min;
            }
            else {
                push( @paramMsgs,
                    genresultString( "kernel.shmall", 50, "PASS" ) );
                logentry("        kernel.shmall: $shmall_val\n");
                $paraminfo->{val} = $shmall_val;
            }
            $newkernelparamsRef->{shmall} = $paraminfo;
        }
        elsif ($kernelFlag
            && $sysctlline =~ m/\s*kernel.shmmni\s+=\s+(\d+)\s*/ )
        {
            $shmmni_val = $1;
            $shmmni_min = int( ( 256 * $memoryByKB ) / ( 1024 * 1024 ) );

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $shmmni_val < $shmmni_min ) {
                push( @paramMsgs,
                    genresultString( "kernel.shmmni", 50, "FAIL" ) );
                logentry(
"        kernel.shmmni is too small. It should be at least $shmmni_min\n"
                );
                $shmmniok                   = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = $shmmni_min;
            }
            else {
                push( @paramMsgs,
                    genresultString( "kernel.shmmni", 50, "PASS" ) );
                logentry("        kernel.shmmni: $shmmni_val\n");
                $paraminfo->{val} = $shmmni_val;
            }
            $newkernelparamsRef->{shmmni} = $paraminfo;
        }
        elsif ($kernelFlag
            && $sysctlline =~
            m/\s*kernel.sem\s+=\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*/ )
        {
            $maxsemperarray   = $1;
            $maxsempersys     = $2;
            $maxopspersemcall = $3;
            $maxnumofarrays   = $4;

            $maxnumofarraysmin = int( ( 256 * $memoryByKB ) / ( 1024 * 1024 ) );

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";
            $paraminfo->{val}               = "";

            if (   ( $maxsemperarray < 250 )
                || ( $maxopspersemcall < 32 )
                || ( $maxsempersys < 256000 )
                || ( $maxnumofarrays < $maxnumofarraysmin ) )
            {
                $semok = 0;

                push( @paramMsgs, genresultString( "kernel.sem", 50, "FAIL" ) );
                if ( $maxsemperarray < 250 ) {
                    logentry(
"        Maximum number of semaphores per array is too small. It should be at least 250\n"
                    );

                    $paraminfo->{willbeupdated} = "yes";
                    $paraminfo->{val}           = "$paraminfo->{val}" . "250 ";
                }
                else {
                    $paraminfo->{val} =
                      "$paraminfo->{val}" . "$maxsemperarray ";
                }

                if ( $maxsempersys < 256000 ) {
                    logentry(
"        Maximum number of semaphores per system is too small. It should be at least 256000\n"
                    );

                    $paraminfo->{willbeupdated} = "yes";
                    $paraminfo->{val} = "$paraminfo->{val}" . "256000 ";
                }
                else {
                    $paraminfo->{val} = "$paraminfo->{val}" . "$maxsempersys ";
                }

                if ( $maxopspersemcall < 32 ) {
                    logentry(
"        Maximum number of ops per semaphore call is too small. It should be at least 32\n"
                    );

                    $paraminfo->{willbeupdated} = "yes";
                    $paraminfo->{val}           = "$paraminfo->{val}" . "32 ";
                }
                else {
                    $paraminfo->{val} =
                      "$paraminfo->{val}" . "$maxopspersemcall ";
                }

                if ( $maxnumofarrays < $maxnumofarraysmin ) {
                    logentry(
"        Maximum number of semaphore arrays. It should be at least $maxnumofarraysmin\n"
                    );

                    $paraminfo->{willbeupdated} = "yes";
                    $paraminfo->{val} =
                      "$paraminfo->{val}" . "$maxnumofarraysmin";
                }
                else {
                    $paraminfo->{val} = "$paraminfo->{val}" . "$maxnumofarrays";
                }
            }
            else {
                push( @paramMsgs, genresultString( "kernel.sem", 50, "PASS" ) );
                logentry(
"        kernel.sem: $maxsemperarray $maxsempersys $maxopspersemcall $maxnumofarrays\n"
                );
                $paraminfo->{val} =
"$maxsemperarray $maxsempersys $maxopspersemcall $maxnumofarrays";
            }
            $newkernelparamsRef->{sem} = $paraminfo;
        }
        elsif ($kernelFlag
            && $sysctlline =~ m/\s*kernel.msgmni\s+=\s+(\d+)\s*/ )
        {
            $msgmni_val = $1;
            $msgmni_min = int( ( 1024 * $memoryByKB ) / ( 1024 * 1024 ) );

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $msgmni_val < $msgmni_min ) {
                push( @paramMsgs,
                    genresultString( "kernel.msgmni", 50, "FAIL" ) );
                logentry(
"        kernel.msgmni is too small. It should be at least $msgmni_min\n"
                );
                $msgmniok                   = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = $msgmni_min;
            }
            else {
                push( @paramMsgs,
                    genresultString( "kernel.msgmni", 50, "PASS" ) );
                logentry("        kernel.msgmni: $msgmni_val\n");
                $paraminfo->{val} = $msgmni_val;
            }
            $newkernelparamsRef->{msgmni} = $paraminfo;
        }
        elsif ($kernelFlag
            && $sysctlline =~ m/\s*kernel.msgmax\s+=\s+(\d+)\s*/ )
        {
            $msgmax_val = $1;

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $msgmax_val < 65536 ) {
                push( @paramMsgs,
                    genresultString( "kernel.msgmax", 50, "FAIL" ) );
                logentry(
"        kernel.msgmax is too small. It should be at least 65536\n"
                );
                $msgmaxok                   = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = 65536;
            }
            else {
                push( @paramMsgs,
                    genresultString( "kernel.msgmax", 50, "PASS" ) );
                logentry("        kernel.msgmax: $msgmax_val\n");
                $paraminfo->{val} = $msgmax_val;
            }
            $newkernelparamsRef->{msgmax} = $paraminfo;
        }
        elsif ($kernelFlag
            && $sysctlline =~ m/\s*kernel.msgmnb\s+=\s+(\d+)\s*/ )
        {
            $msgmnb_val = $1;

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $msgmnb_val < 65536 ) {
                push( @paramMsgs,
                    genresultString( "kernel.msgmnb", 50, "FAIL" ) );
                logentry(
"        kernel.msgmnb is too small. It should be at least 65536\n"
                );
                $msgmnbok                   = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = 65536;
            }
            else {
                push( @paramMsgs,
                    genresultString( "kernel.msgmnb", 50, "PASS" ) );
                logentry("        kernel.msgmnb: $msgmnb_val\n");
                $paraminfo->{val} = $msgmnb_val;
            }
            $newkernelparamsRef->{msgmnb} = $paraminfo;
        }
        elsif ($kernelFlag
            && $sysctlline =~ m/\s*kernel.randomize_va_space\s+=\s+(\d+)\s*/ )
        {
 # We will take the OS default of 2 unless the -kernel switch has been specified
            $rand_va_space_val = $1;

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $rand_va_space_val != 0 ) {
                push( @paramMsgs,
                    genresultString( "kernel.randomize_va_space", 50, "FAIL" )
                );
                logentry("        kernel.randomize_va_space should be 0\n");
                $rand_va_spaceok            = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = 0;
            }
            else {
                push( @paramMsgs,
                    genresultString( "kernel.randomize_va_space", 50, "PASS" )
                );
                logentry(
                    "        kernel.randomize_va_space: $rand_va_space_val\n");
                $paraminfo->{val} = $rand_va_space_val;
            }
            $newkernelparamsRef->{randomize_va_space} = $paraminfo;
        }
        elsif ( $sysctlline =~ m/\s*vm.swappiness\s+=\s+(\d+)\s*/ ) {
            my $vmswap = 0;
            if ( $serverVersion >=
                8 )    # vm.swapiness recommendation changed in DB/2 11.1
            {
                $vmswap = 5;
            }

            $vm_swappiness_val = $1;

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $vm_swappiness_val != $vmswap ) {
                push( @paramMsgs,
                    genresultString( "vm.swappiness", 50, "FAIL" ) );
                logentry("        vm.swappiness should be $vmswap\n");
                $vm_swappinessok            = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = $vmswap;
            }
            else {
                push( @paramMsgs,
                    genresultString( "vm.swappiness", 50, "PASS" ) );
                logentry("        vm.swappiness: $vm_swappiness_val\n");
                $paraminfo->{val} = $vm_swappiness_val;
            }
            $newkernelparamsRef->{swappiness} = $paraminfo;
        }
        elsif ( $sysctlline =~ m/\s*vm.overcommit_memory\s+=\s+(\d+)\s*/ ) {
            $vm_overcommit_mem_val = $1;

            my $paraminfo = {};

            $paraminfo->{addedtosysctlconf} = "no";
            $paraminfo->{willbeupdated}     = "no";

            if ( $vm_overcommit_mem_val != 0 ) {
                push( @paramMsgs,
                    genresultString( "vm.overcommit_memory", 50, "FAIL" ) );
                logentry("        vm_overcommit_memory should be 0\n");
                $vm_overcommit_memok        = 0;
                $paraminfo->{willbeupdated} = "yes";
                $paraminfo->{val}           = 0;
            }
            else {
                push( @paramMsgs,
                    genresultString( "vm.overcommit_memory", 50, "PASS" ) );
                logentry(
                    "        vm.overcommit_memory: $vm_overcommit_mem_val\n");
                $paraminfo->{val} = $vm_overcommit_mem_val;
            }
            $newkernelparamsRef->{overcommit_memory} = $paraminfo;
        }
    }

    if (   ( $shmmaxok == 0 )
        || ( $shmallok == 0 )
        || ( $semok == 0 )
        || ( $rand_va_spaceok == 0 )
        || ( $vm_swappinessok == 0 )
        || ( $vm_overcommit_memok == 0 )
        || ( $msgmniok == 0 )
        || ( $msgmaxok == 0 )
        || ( $msgmnbok == 0 ) )
    {
        my @rcArray = (
            1,           "kernel parameter need adjustment",
            \@paramMsgs, $newkernelparamsRef
        );
        return @rcArray;
    }
    else {
        my @rcArray = ( 0, "", \@paramMsgs, $newkernelparamsRef );
        return @rcArray;
    }
}

############################################################
#      sub: updateKernelParams
#     desc: Updates the system kernel parameters for Linux
#           systems, by updating the values of the for the
#           parameters to be updated in sysctl.conf and
#           making the system call sysctl -e -p
#
#   params: 1. a structure from the previous invocation of
#              validateKernelParams containing information
#              about which kernel parameters need to be updated
#              and with what values
#
#  returns: an array consisting of a return code (0 for success,
#           1 for error), a overall error message if there was
#           an error
#
############################################################

sub updateKernelParams {
    $nkRef = shift(@_);

    # create the new sysctl.conf

    $sysctlconfigfile = "/etc/sysctl.conf";

    if ( open( SYSCTLCFGH, "<${sysctlconfigfile}" ) ) {
        @sysctlcfgorigcontents = <SYSCTLCFGH>;
        close SYSCTLCFGH;

        sleep 1;

        if ( open( NEWSYSCTLCFGH, ">$sysctlconfigfile" ) ) {
            foreach $sysctlline (@sysctlcfgorigcontents) {
                if ( $sysctlline =~ m/\s*kernel.(\w+)\s+=\s+\d+\s*/ ) {
                    $currentparam = $1;
                    if ( exists $nkRef->{$currentparam} ) {
                        print NEWSYSCTLCFGH
"kernel.${currentparam} = $nkRef->{$currentparam}->{val}\n";
                        $nkRef->{$currentparam}->{addedtosysctlconf} = 1;
                        if ( $nkRef->{$currentparam}->{willbeupdated} eq "yes" )
                        {
                            logentry(
                                "        Updating kernel.${currentparam}\n");
                        }
                    }
                    else {
                        print NEWSYSCTLCFGH "$sysctlline";
                    }
                }
                elsif ( $sysctlline =~ m/\s*vm.(\w+)\s+=\s+\d+\s*/ ) {
                    $currentparam = $1;
                    if ( exists $nkRef->{$currentparam} ) {
                        print NEWSYSCTLCFGH
"vm.${currentparam} = $nkRef->{$currentparam}->{val}\n";
                        $nkRef->{$currentparam}->{addedtosysctlconf} = 1;
                        if ( $nkRef->{$currentparam}->{willbeupdated} eq "yes" )
                        {
                            logentry("        Updating vm.${currentparam}\n");
                        }
                    }
                    else {
                        print NEWSYSCTLCFGH "$sysctlline";
                    }
                }
                else {
                    print NEWSYSCTLCFGH "$sysctlline";
                }
            }

            foreach $key ( keys %{$nkRef} ) {
                if ( $nkRef->{$key}->{addedtosysctlconf} == 0 ) {
                    if (   ( $key ne "swappiness" )
                        && ( $key ne "overcommit_memory" ) )
                    {
                        print NEWSYSCTLCFGH
                          "kernel.${key} = $nkRef->{$key}->{val}\n";
                        if ( $nkRef->{$key}->{willbeupdated} eq "yes" ) {
                            logentry("        Updating kernel.${key}\n");
                        }
                    }
                    else {
                        print NEWSYSCTLCFGH
                          "vm.${key} = $nkRef->{$key}->{val}\n";
                        if ( $nkRef->{$key}->{willbeupdated} eq "yes" ) {
                            logentry("        Updating vm.${key}\n");
                        }
                    }
                }
            }
            close NEWSYSCTLCFGH;

        }
        else {
            logentry(
"        An error occurred opening $sysctlconfigfile for writing\n"
            );
            my @rcArray = ( 1, "error updating $sysctlconfigfile" );
            return @rcArray;
        }

        # call sysctl -e -p

        $sysctlpcmd = "sysctl -e -p > /dev/null 2>&1";

        $sysctlpcmdrc = system("$sysctlpcmd");

        if ( $sysctlpcmdrc != 0 ) {
            logentry(
"        An error occurred when issuing the sysctl -e -p command\n"
            );
            my @rcArray = ( 1, "error updating kernel parameters" );
            return @rcArray;
        }
        else {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
    }
    else {
        logentry(
            "        An error occurred opening $sysctlconfigfile for reading\n"
        );
        my @rcArray = ( 1, "error updating $sysctlconfigfile" );
        return @rcArray;
    }
}

############################################################
#      sub: preparedsmservrc
#     desc: Puts dsmserv.rc file, with appropriate modifications
#           in the proper location to subsequently configure the
#           IBM Storage Protect server as a service
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if not successful
#
############################################################

sub preparedsmservrc {
    $stpn = shift(@_);

    logentry( "Step ${stpn}_${substep}: Prepare the dsmserv.rc file\n", 1 );

    $db2usr        = $stateHash{db2user};
    $instdirmntpnt = $stateHash{instdirmountpoint};
    $systemctl_1   = '/usr/bin/systemctl';
    $systemctl_2   = '/bin/systemctl';
    $systemddir    = '/etc/systemd/system';
    $multiuserdir  = '/etc/systemd/systemmulti-user.target.wants';
    $systemdfile   = "${systemddir}/${db2user}.service";
    $multiuserfile = "${multiuserdir}/${db2user}.service";

    $dsmservrcfile = $serverPath . "${SS}dsmserv.rc";

    $preparedsmservrcErrorString =
      "An error occurred preparing the dsmserv.rc file";
    $preparedsmservrcErrorString1 =
      "An error occurred preparing the $systemdfile file";
    $dsmservrcfile = $serverPath . "${SS}dsmserv.rc";

    if ( $isSLES == 1 || $isUbuntu == 1 ) {
        if ( -e $systemctl_1 || -e $systemctl_2 ) {
            logentry( "systemctl found.  Using systemd autostart.\n", 1 );
            $dsmservrcfilefinal = $serverPath . "${SS}${db2user}";
            $issystemctl        = 1;
        }
        else {
            logentry( "systemctl Not found.  Using system V autostart.\n", 1 );
            $dsmservrcfilefinal = "${SS}etc${SS}init.d${SS}${db2usr}";
            $issystemctl        = 0;
        }
    }
    else {
        if ( -e $systemctl_1 || -e $systemctl_2 ) {
            logentry( "systemctl found.  Using systemd autostart.\n", 1 );
            $dsmservrcfilefinal = $serverPath . "${SS}${db2user}";
            $issystemctl        = 1;
        }
        else {
            logentry( "systemctl Not found.  Using system V autostart.\n", 1 );
            $dsmservrcfilefinal = "${SS}etc${SS}rc.d${SS}init.d${SS}${db2usr}";
            $issystemctl        = 0;
        }
    }

# Change the definition of the instance_dir variable and save the modified file
# under the same name as the instance owner under the /etc/rc.d/init.d directory

    if ( open( DSMSERVRC, "<$dsmservrcfile" ) ) {
        @dsmservrcfilecontents = <DSMSERVRC>;
        close DSMSERVRC;
    }
    else {
        logentry(
"        An error occurred when attempting to read the dsmserv.rc file\n"
        );
        displayString( 10, 3, $preparedsmservrcErrorString );
        return 1;
    }

    if ( open( DSMSERVRCFINAL, ">$dsmservrcfilefinal" ) ) {
        $foundstartfunction = 0;
        $nofilelimitadded   = 0;

        foreach $dsmservrcline (@dsmservrcfilecontents) {
            if ( $dsmservrcline =~ m/^start\(\)/ ) {
                print DSMSERVRCFINAL "$dsmservrcline";
                $foundstartfunction = 1;
            }
            elsif ( $dsmservrcline =~ m/^instance_dir=/ ) {
                print DSMSERVRCFINAL "instance_dir=\"${instdirmntpnt}\"\n";
            }
            elsif (( $foundstartfunction == 1 )
                && ( $nofilelimitadded == 0 )
                && ( $dsmservrcline =~ m/\s*ulimit\s+-c\s+unlimited/ ) )
            {
                print DSMSERVRCFINAL "$dsmservrcline";
                print DSMSERVRCFINAL
                  "        ulimit -n 8192\n";    # see apar IC95635
                $nofilelimitadded = 1;
            }
            else {
                print DSMSERVRCFINAL "$dsmservrcline";
            }
        }
        close DSMSERCRCFINAL;

        system("chmod 755 $dsmservrcfilefinal");
    }
    if ( $issystemctl == 1 ) {
        if ( open( FH, '>', $systemdfile ) ) {
            print FH "[Unit]\n";
            print FH
              "Description=IBM Storage Protect Server instance ${db2user}\n";
            print FH "\n";
            print FH "[Service]\n";
            print FH "TasksMax=infinity\n";
            print FH "Type=oneshot\n";
            print FH "RemainAfterExit=true\n";
            print FH "ExecStart=${dsmservrcfilefinal} start\n";
            print FH "ExecStop=${dsmservrcfilefinal} stop\n";
            print FH "ExecReload=${dsmservrcfilefinal} restart\n";
            print FH "\n";
            print FH "[Install]\n";
            print FH "WantedBy=multi-user.target\n";
            close(FH);
        }
        else {
            logentry(
"        An error occurred when attempting to perpare the write of ${systemdfile} file\n"
            );
            displayString( 10, 3, $preparedsmservrcErrorString1 );
            return 1;
        }
    }

    return 0;
}

############################################################
#      sub: configservice
#     desc: Invokes chkconfig to configure the IBM Storage Protect server to
#           start at boot
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if not successful
#
############################################################

sub configservice {
    $systemctl_1 = '/usr/bin/systemctl';
    $systemctl_2 = '/bin/systemctl';

    $stpn = shift(@_);
    if ( -e $systemctl_1 || -e systemctl_2 ) {
        logentry( "Running configservicesystemd\n", 1 );
        $rc = configservicesystemd($stpn);
    }
    else {
        logentry( "Running configservicesystemv\n", 1 );
        $rc = configservicesystemv($stpn);
    }
    return $rc;
}

############################################################
#      sub: configservicesystemv
#     desc: Invokes chkconfig to configure the IBM Storage Protect server to
#           start at boot
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if not successful
#
############################################################

sub configservicesystemv {
    $stpn = shift(@_);

    $db2usr = $stateHash{db2user};

    logentry(
        "Step ${stpn}_${substep}: Configure the $db2usr service (System V)\n",
        1 );

    $prepareserviceErrorString =
      "An error occurred preparing the $db2usr service";

    if ($isUbuntu) {
        logentry(
            "        Issuing command: udpate-rc.d $db2usr defaults 90 10\n");
        $chkconfigrc1 = system("update-rc.d $db2usr defaults 90 10");
    }
    else {
        logentry("        Issuing command: chkconfig --add $db2usr\n");
        $chkconfigrc1 = system("chkconfig --add $db2usr");
    }

    if ( $chkconfigrc1 != 0 ) {
        logentry(
"        An error occurred when attempting to configure the $db2usr service\n"
        );
        displayString( 10, 3, $prepareserviceErrorString );
        return 1;
    }
    else {
        if ($isUbuntu) {
            logentry(
                "        Issuing command: update-rc.d $db2usr start  10 3 4 5\n"
            );
            $chkconfigrc2 = system("update-rc.d $db2usr start  10 3 4 5 ");
        }
        else {
            logentry(
                "        Issuing command: chkconfig --level 345 $db2usr on\n");
            $chkconfigrc2 = system("chkconfig --level 345 $db2usr on");
        }

        if ( $chkconfigrc2 != 0 ) {
            logentry(
"        An error occurred when attempting to configure the $db2usr service\n"
            );
            displayString( 10, 3, $prepareserviceErrorString );
            return 1;
        }
        else {
            return 0;
        }
    }
}

############################################################
#      sub: configservicesystemd
#     desc: Invokes systemd to configure the IBM Storage Protect server to
#           start at boot
#
#   params: 1. the step number
#
#  returns: 0 if successful
#           1 if not successful
#
############################################################

sub configservicesystemd {
    $stpn = shift(@_);

    $db2usr        = $stateHash{db2user};
    $systemddir    = "/etc/systemd/system";
    $multiuserdir  = "/etc/systemd/system/multi-user.target.wants";
    $systemdfile   = "${systemddir}/$db2usr.service";
    $multiuserfile = "${multiuserdir}/$db2usr.service";

    logentry(
        "Step ${stpn}_${substep}: Configure the $db2usr service (Systemctl)\n",
        1
    );

    $prepareserviceErrorString =
      "An error occurred preparing the $db2usr service";

    logentry( "         Issuing command: systemctl daemon-reload\n", 1 );
    $systemctlrc = system("systemctl daemon-reload");

    if ( $systemctlrc != 0 ) {
        logentry(
"        An error occurred when attempting to configure the $db2usr service\n"
        );
        displayString( 10, 3, $prepareserviceErrorString );
        return 1;
    }

    logentry( "         Issuing command: ln -sf $systemdfile $multiuserfile\n",
        1 );
    $lnrc = system("ln -sf $systemdfile $multiuserfile");

    if ( $lnrc != 0 ) {
        logentry(
"        An error occurred when attempting to configure the $db2usr service\n"
        );
        displayString( 10, 3, $prepareserviceErrorString );
        return 1;
    }

    logentry( "         Issuing command: systemctl enable $db2user\n", 1 );
    $systemctlrc1 = system("systemctl enable $db2user");

    if ( $systemctlrc1 != 0 ) {
        logentry(
"        An error occurred when attempting to configure the $db2usr service\n"
        );
        displayString( 10, 3, $prepareserviceErrorString );
        return 1;
    }
    return 0;
}

############################################################
#      sub: isalreadySelected
#     desc: Checks if the path specified by the argument has
#           already been selected by the user for something else.
#           This is so that the user cannot give the same path for
#           both the DB2 archive log path and, for example, the database
#           backup directory
#
#   params: 1. the path to be checked
#
#  returns: 0 if the path was not previously specified for something else
#           1 if the path was previously specified
#
############################################################

sub isalreadySelected {
    $dirpth = shift(@_)
      ; # the path we are checking to see if it is has already been selected by the user

    my $isselected = 0;

    if (   ( exists $stateHash{instdirmountpoint} )
        && ( $dirpth eq $stateHash{instdirmountpoint} ) )
    {
        $isselected = 1;
    }
    elsif (( exists $stateHash{instdirmountpoint} )
        && ( issubpath( $stateHash{instdirmountpoint}, $dirpth ) == 1 ) )
    {
        $isselected = 1;
    }
    elsif (( exists $stateHash{actlogpath} )
        && ( $dirpth eq $stateHash{actlogpath} ) )
    {
        $isselected = 1;
    }
    elsif (( exists $stateHash{archlogpath} )
        && ( $dirpth eq $stateHash{archlogpath} ) )
    {
        $isselected = 1;
    }

    foreach $pth ( @{ $stateHash{dbbackdirpaths} } ) {
        if ( $dirpth eq $pth ) {
            $isselected = 1;
        }
    }

    foreach $pth ( @{ $stateHash{tsmstgpaths} } ) {
        if ( $dirpth eq $pth ) {
            $isselected = 1;
        }
    }

    foreach $pth ( @{ $stateHash{dbdirpaths} } ) {
        if ( $dirpth eq $pth ) {
            $isselected = 1;
        }
    }

    return $isselected;
}

############################################################
#      sub: repaint
#     desc: Redraws the screen when displaying the user's choices
#           for filesystems to be used for database directory paths, for
#           storage paths, and for database backup directory paths
#   params: 1. number indicating how many valid paths were already entered
#              by the user
#           2. reference to an array containing all the previous valid
#              entries
#           3. step number from which this subroutine was called
#
#  returns: none
#
############################################################

sub repaint {
    $m      = shift(@_);
    $arrRef = shift(@_);
    $stp    = shift(@_);

    clearscreen();

    displayStepNumAndDesc($stp);

    displayString( 0, 2, "" );

    for ( $l = 0 ; $l <= $m - 1 ; $l++ ) {
        $previousvalidselection = $arrRef->[$l];
        $previousentrynum       = $l + 1;
        $previousentrystring =
          genresultString( "${previousentrynum}> $previousvalidselection",
            40, "[OK]" );
        displayString( 10, 1, $previousentrystring );
    }
}

############################################################
#      sub: genresultString
#     desc: Constructs a string to be displayed on the screen
#           with information about what the result of some
#           procedure or operation, or, in some cases just
#           an acknowledgement of user input, and an indication
#           of whether that input is acceptable or not
#
#   params: 1. a description of the procedure just performed, or,
#              a description of the user input being acknowledged
#           2. the number of spaces that is to follow the description
#              from the first parameter, but before the verdict (3rd parameter)
#           3. the verdict (usually [OK] or [ERROR])
#           4. when there is an error, a short description of what
#              the problem was, or sometimes just a pointer to the
#              script log
#
#  returns: the string constructed from the parameters 1 to 4 above
#
############################################################

sub genresultString {
    $infostrg      = shift(@_);
    $numspincolumn = shift(@_);
    $verdictstrg   = shift(@_);
    $msgstrg       = shift(@_);

    $resultstrg = "$infostrg";

    if ( $numspincolumn > length($infostrg) ) {
        $numsp = $numspincolumn - length($infostrg);
        for ( $n = 0 ; $n < $numsp ; $n++ ) {
            $resultstrg = "$resultstrg" . " ";
        }
    }
    else {
        $resultstrg = "$resultstrg" . " ";
    }

    $resultstrg = "$resultstrg" . "$verdictstrg";

    if ( $msgstrg ne "" ) {
        $resultstrg = "$resultstrg" . "   $msgstrg";
    }
    return $resultstrg;
}

############################################################
#      sub: displayStepNumAndDesc
#     desc: Displays the step number and description at
#           the top of the screen when the screen has just
#           been refreshed (cleared)
#
#   params: 1. the step number from which this subroutine
#              was called
#
#  returns: none
#
############################################################

sub displayStepNumAndDesc {
    $stp = shift(@_);

    @stringArr = ();
    push( @stringArr, $stepDescArray[$stp] )
      ;    # get the description corresponding
           # to the current step from the array
           # step descriptions
    displayString( 0, 0, "Step $stp of $NUMBEROFSTEPS" );
    displayCenteredStrings( 2, \@stringArr );
}

############################################################
#      sub: cleanup
#     desc: At the end of a run, cleans up various files created
#           during the course of script execution and, if dsm.opt
#           in BA client install path does not already exist,
#           it renames the option file used during configuration
#           to dsm.opt
#
#   params: none
#
#  returns: none
#
############################################################

sub cleanup {
    if (   ( exists $stateHash{setinstdircmdfile} )
        && ( -f $stateHash{setinstdircmdfile} ) )
    {
        unlink( $stateHash{setinstdircmdfile} );
    }
    if (   ( exists $stateHash{setdb2codepagecmdfile} )
        && ( -f $stateHash{setdb2codepagecmdfile} ) )
    {
        unlink( $stateHash{setdb2codepagecmdfile} );
    }
    if (   ( exists $stateHash{listdbdircmdfile} )
        && ( -f $stateHash{listdbdircmdfile} ) )
    {
        unlink( $stateHash{listdbdircmdfile} );
    }
    if (   ( exists $stateHash{dsmformatcmdfile} )
        && ( -f $stateHash{dsmformatcmdfile} ) )
    {
        unlink( $stateHash{dsmformatcmdfile} );
    }
    if (   ( exists $stateHash{setdb2locklistcmdfile} )
        && ( -f $stateHash{setdb2locklistcmdfile} ) )
    {
        unlink( $stateHash{setdb2locklistcmdfile} );
    }
    if (   ( exists $stateHash{setdb2locklistsqlfile} )
        && ( -f $stateHash{setdb2locklistsqlfile} ) )
    {
        unlink( $stateHash{setdb2locklistsqlfile} );
    }
    if (   ( exists $stateHash{setdb2attribcmdfile} )
        && ( -f $stateHash{setdb2attribcmdfile} ) )
    {
        unlink( $stateHash{setdb2attribcmdfile} );
    }
    if (   ( exists $stateHash{setdb2attribsqlfile} )
        && ( -f $stateHash{setdb2attribsqlfile} ) )
    {
        unlink( $stateHash{setdb2attribsqlfile} );
    }
    if (   ( exists $stateHash{startservercmdfile} )
        && ( -f $stateHash{startservercmdfile} ) )
    {
        unlink( $stateHash{startservercmdfile} );
    }
    if ( ( exists $stateHash{runfile} ) && ( -f $stateHash{runfile} ) ) {
        unlink( $stateHash{runfile} );
    }
    if (   ( exists $stateHash{tsmconfigmacro} )
        && ( -f $stateHash{tsmconfigmacro} ) )
    {
        unlink( $stateHash{tsmconfigmacro} );
    }
    if (   ( exists $stateHash{createpreallocatedvolumesmacro} )
        && ( -f $stateHash{createpreallocatedvolumesmacro} ) )
    {
        unlink( $stateHash{createpreallocatedvolumesmacro} );
    }
    if (   ( $platform eq "WIN32" )
        && ( exists $stateHash{qprocesscmdfile} )
        && ( -f $stateHash{qprocesscmdfile} ) )
    {
        unlink( $stateHash{qprocesscmdfile} );
    }
    if (   ( $platform eq "WIN32" )
        && ( exists $stateHash{createvolcmdfile} )
        && ( -f $stateHash{createvolcmdfile} ) )
    {
        unlink( $stateHash{createvolcmdfile} );
    }
    if (   ( $platform eq "WIN32" )
        && ( exists $stateHash{db2stopstartcmdfile} )
        && ( -f $stateHash{db2stopstartcmdfile} ) )
    {
        unlink( $stateHash{db2stopstartcmdfile} );
    }
    if (   ( $platform eq "WIN32" )
        && ( exists $stateHash{dsmadmccmdfile} )
        && ( -f $stateHash{dsmadmccmdfile} ) )
    {
        unlink( $stateHash{dsmadmccmdfile} );
    }
    if (   ( exists $stateHash{dsmoptforconfig} )
        && ( -f $stateHash{dsmoptforconfig} ) )
    {
        if (
            (
                   ( $platform eq "LINUX86" )
                || ( $platform eq "AIX" )
                || ( $platform =~ m/LINUXPPC/ )
            )
            && ( !-f $stateHash{dsmoptdefault} )
          )
        {
            system("mv $stateHash{dsmoptforconfig} $stateHash{dsmoptdefault}");
        }
        elsif ( ( $platform eq "WIN32" ) && ( !-f $stateHash{dsmoptdefault} ) )
        {
            system("ren $stateHash{dsmoptforconfig} dsm.opt");
        }
        else {
            unlink( $stateHash{dsmoptforconfig} );
        }
    }
}

############################################################
#      sub: refreshProgress
#     desc: Refreshes the progress bar displayed while the
#           IBM Storage Protect server is being formatted
#
#   params: 1. the step number in which this subroutine is called
#           2. the initial amount of space used in the active log path
#           3. the number of hashes to be displayed for the purpose of
#              indicating progress before the active log actually starts to
#              grow
#           4. number of times this subroutine has been called so far
#
#  returns: the (possibly updated) value from second parameter, which
#           will be needed for subsequent calls to this subroutine
#
############################################################

sub refreshProgress {
    my $stp              = shift(@_);
    my $initialkbused    = shift(@_);
    my $currNumberHashes = shift(@_)
      ; # number of hashes written to progress bar so far before actual growth of active log
    my $numIters = shift(@_);    # number of times this subroutine was called

    if ( ( $platform eq "WIN32" ) || ( $serverVersion >= 7 ) ) {
        $actlogsizeinKB = $stateHash{initactlogsize} * 1024;
    }
    else {
        $actlogsizeinKB = $stateHash{actlogsize} * 1024;
    }

    $progressbarwidth = 50;

    $kbUsed = getactivelogKbUsed();

    # Constuct the beginning of the progress bar

    $progressLine = "Progress  [";

    if (
        ( ( $progressbarwidth - $currNumberHashes ) > 0 )
        && ( $kbUsed < $initialkbused +
            int( $actlogsizeinKB / ( $progressbarwidth - $currNumberHashes ) ) )
      )    # active log filesystem usage has not started to increase much yet
    {
        if ( ( $numIters > 0 ) && ( ( $numIters % 2 ) == 0 ) ) {
            $currNumberHashes++;
        }
        $numHashes = $currNumberHashes;
    }
    else {
        $numHashes = $currNumberHashes + int(
            (
                ( $kbUsed - $initialkbused ) *
                  ( $progressbarwidth - $currNumberHashes )
            ) / $actlogsizeinKB
        );
    }

    # construct the rest of the progress bar

    for ( $j = 0 ; $j < $numHashes ; $j++ ) {
        $progressLine = "$progressLine" . "#";
    }

    for ( $j = 0 ; $j < ( $progressbarwidth - $numHashes ) ; $j++ ) {
        $progressLine = "$progressLine" . " ";
    }

    $progressLine = "$progressLine" . "]";

    displayString( 10, 3, $formatServerString, 1, $stp );

    displayString( 10, 3, $progressLine );
    return $currNumberHashes;
}

############################################################
#      sub: getactivelogKbUsed
#     desc: Obtains the amount of used space in the
#           active log path
#
#   params: none
#
#  returns: the amount of used space in KB
#
############################################################

sub getactivelogKbUsed {
    $db2actlogpath = $stateHash{actlogpath};

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        $dfcommand    = "df -k $db2actlogpath";
        @dfcommandOut = `$dfcommand`;
    }
    elsif ( $platform eq "WIN32" ) {
        $originalactivelogfreespace = $stateHash{activelogfreespace};

        $dircommand    = "cmd /c dir $db2actlogpath 2>nul";
        @dircommandOut = `$dircommand`;
    }

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {

        foreach $dfoutln (@dfcommandOut) {
            if ( ( ( $platform eq "LINUX86" ) || ( $platform =~ m/LINUXPPC/ ) )
                && ( $dfoutln =~ m/\d+\s+(\d+)\s+\d+\s+\d+%\s+$db2actlogpath/ )
              )
            {
                $inikbUsed = $1;
            }
            elsif (
                ( $platform eq "AIX" )
                && ( $dfoutln =~
m/\S+\s+(\d+)\s+(\d+)\s+\d+\%\s+\d+\s+\d+\%\s+$db2actlogpath/
                )
              )
            {
                $inikbTotal = $1;
                $inikbFree  = $2;
                $inikbUsed  = $inikbTotal - $inikbFree;
            }
        }

    }
    elsif ( $platform eq "WIN32" ) {
        $foundbytesfree = 0;
        foreach $diroutlne (@dircommandOut) {
            if ( $diroutlne =~ m/\d+\s+Dir\(s\)\s+(\S+)\s+bytes\s+free/ ) {
                $foundbytesfree             = 1;
                $activelogfreespcwithcommas = $1;
                @activelogfreespcparts =
                  split( /,/, $activelogfreespcwithcommas );
                $activelogfreespcnocommas = join( '', @activelogfreespcparts );
                $activelogfreespc = int( $activelogfreespcnocommas / 1024 );
            }
        }

# subtract the current active log free space from the original active log free space
# to get the used space

        if ( $foundbytesfree == 1 ) {
            $inikbUsed = $originalactivelogfreespace - $activelogfreespc;
        }
        else {
            $inikbUsed = 0;
        }
    }

    return $inikbUsed;
}

############################################################
#      sub: getinputfromfile
#     desc: Extracts the value of the key specified by the
#           argument from the response file
#
#   params: 1. key whose value is to be extracted
#
#  returns: 0 if value of specified key is not in the response file
#           1 if value of specified key is in the response file
#
############################################################

sub getinputfromfile {
    $thekey = shift(@_);

    $valuefoundinfile = 0;

    @inputfilecontents = ();

    if ( open( INPUTFH, "<$inputfile" ) ) {
        @inputfilecontents = <INPUTFH>;
        close INPUTFH;
    }

    foreach $inputfileline (@inputfilecontents) {
        if ( $inputfileline =~ m/(\w+)\s+(\S+)/ ) {
            $currkey   = $1;
            $currvalue = $2;

            if (   ( $currkey eq "$thekey" )
                && ( $thekey ne "dbdirpaths" )
                && ( $thekey ne "tsmstgpaths" )
                && ( $thekey ne "dbbackdirpaths" ) )
            {
                $valuefoundinfile = 1;
                $inputHash{$thekey} = $currvalue;
            }
            elsif ( ( $currkey eq "$thekey" ) && ( $thekey eq "dbdirpaths" ) ) {
                $valuefoundinfile = 1;
                @dbdirsinputArray = split( /,/, $currvalue );
                push( @dbdirsinputArray, "" );
                $inputHash{dbdirpaths} = \@dbdirsinputArray;
            }
            elsif ( ( $currkey eq "$thekey" ) && ( $thekey eq "tsmstgpaths" ) )
            {
                $valuefoundinfile  = 1;
                @stgdirsinputArray = split( /,/, $currvalue );
                push( @stgdirsinputArray, "" );
                $inputHash{tsmstgpaths} = \@stgdirsinputArray;
            }
            elsif (( $currkey eq "$thekey" )
                && ( $thekey eq "dbbackdirpaths" ) )
            {
                $valuefoundinfile     = 1;
                @dbbackdirsinputArray = split( /,/, $currvalue );
                push( @dbbackdirsinputArray, "" );
                $inputHash{dbbackdirpaths} = \@dbbackdirsinputArray;
            }
        }
    }
    return $valuefoundinfile;
}

############################################################
#      sub: verifyPrereqs
#     desc: Checks if the server, server license,
#           BA client and API are installed
#
#   params: none
#
#  returns: dies on error
#
############################################################

sub verifyPrereqs {
    if ( $platform eq "LINUX86" || $platform =~ m/LINUXPPC/ ) {
        $tivrpmcmd = "rpm -qa | grep TIVsm";
        $imclcmd =
"${SS}opt${SS}IBM${SS}InstallationManager${SS}eclipse${SS}tools${SS}imcl";

        @tivrpmOut = `$tivrpmcmd`;

        $serverinstalled        = 0;
        $serverlicenseinstalled = 0;
        $apiclientinstalled     = 0;
        $baclientinstalled      = 0;
        $serverVersion          = 0;

        # For a 6.3.x server, the install will be reported by rpm

        foreach $rpmln (@tivrpmOut) {
            if ( $rpmln =~ m/^TIVsm-server/ ) {
                $serverinstalled = 1;
            }
            if ( $rpmln =~ m/^TIVsm-license/ ) {
                $serverlicenseinstalled = 1;
            }
            if ( $rpmln =~ m/^TIVsm-BA/ ) {
                $baclientinstalled = 1;
            }
            if ( $rpmln =~ m/^TIVsm-API64/ ) {
                $apiclientinstalled = 1;
            }
        }

        # If Ubuntu, need to look for client packages with pkg
        if ($isUbuntu) {
            $tivdpkgcmd = "dpkg -l | grep tivsm";
            @tivdpkgOut = `$tivdpkgcmd`;

            foreach $dpkgln (@tivdpkgOut) {
                if ( $dpkgln =~ m/tivsm-ba/ ) {
                    $baclientinstalled = 1;
                }
                if ( $dpkgln =~ m/tivsm-api64/ ) {
                    $apiclientinstalled = 1;
                }
            }
        }

# If server was reported by rpm, version is 6, otherwise check instmanager report for version 7
        if (   $serverinstalled == 1
            && $serverlicenseinstalled == 1
            && $apiclientinstalled == 1 )
        {
            $serverVersion = 6;
            $serverPath    = "${SS}opt${SS}tivoli${SS}tsm${SS}server${SS}bin";
            $db2Path       = "${SS}opt${SS}tivoli${SS}tsm${SS}db2";
        }
        else {
            $serverPath = "";
            $db2Path    = "";
            if ( -f $imclcmd ) {
                @imclOut = `$imclcmd listinstallationdirectories`;
                foreach $line (@imclOut) {
                    if ( $line =~ m/tsm/ ) {
                        chomp($line);
                        if ( -f $line . "${SS}server${SS}bin${SS}dsmserv" ) {
                            $serverPath = $line . "${SS}server${SS}bin";
                            $db2Path    = $line . "${SS}db2";
                        }
                    }
                }
            }
            elsif ( -l "${SS}usr${SS}bin${SS}dsmserv" ) {
                $lsout = `ls -l ${SS}usr${SS}bin${SS}dsmserv`;
                $lsout =~ s/.*->\s+(.*)\/dsmserv\s+/$1/;
                if ( -f $lsout . "${SS}dsmserv" ) {
                    $serverPath = $lsout;
                    $lsout =~ s/(.*)\/server\/bin/$1/;
                    $db2Path = $lsout . "${SS}db2";
                }
            }

            if ( $serverPath ne "" ) {
                $serverinstalled = 1;
                if ( -f $serverPath . "${SS}tsmbasic.lic" ) {
                    $serverlicenseinstalled = 1;
                }
                @imclOut = `$imclcmd listinstalledpackages`;
                foreach $line (@imclOut) {
                    if ( $line =~ m/com\.tivoli\.dsm\.server_(\S+)/ ) {
                        chomp($line);
                        if ( $line =~ m/8\.1\.\d/ ) {
                            $serverVersion = 8;
                        }
                        elsif ( $line =~ m/7\.1\.\d/ ) {
                            $serverVersion = 7;
                        }
                        else {
                            logentry("Unrecognized server version: $line\n");
                            $serverinstalled = 0;
                        }
                    }
                }
            }

        }    # end of v7 handling
    }
    elsif ( $platform eq "AIX" ) {
        $tivlslppcmd = "lslpp -l tivoli.tsm.*";
        $imclcmd =
"${SS}opt${SS}IBM${SS}InstallationManager${SS}eclipse${SS}tools${SS}imcl";

        @tivlslppOut = `$tivlslppcmd`;

        $serverinstalled        = 0;
        $serverlicenseinstalled = 0;
        $apiclientinstalled     = 0;
        $baclientinstalled      = 0;
        $serverVersion          = 0;

        # For a 6.3.x server, the install will be reported by lslpp

        foreach $lslppln (@tivlslppOut) {
            if ( $lslppln =~ m/^\s+tivoli.tsm.server\s+(\d+)/ ) {
                $serverinstalled = 1;
                $serverVersion   = $1;
            }
            if ( $lslppln =~ m/^\s+tivoli.tsm.server.license/ ) {
                $serverlicenseinstalled = 1;
            }
            if ( $lslppln =~ m/^\s+tivoli.tsm.client.ba.64bit/ ) {
                $baclientinstalled = 1;
            }
            if ( $lslppln =~ m/^\s+tivoli.tsm.client.api.64bit/ ) {
                $apiclientinstalled = 1;
            }
        }

# If server was reported by rpm, version is 6, otherwise check instmanager report for version 7
        if (   $serverinstalled == 1
            && $serverlicenseinstalled == 1
            && $apiclientinstalled == 1 )
        {
            if ( $serverVersion == 0 ) {
                $serverVersion = 6;
            }
            $serverPath = "${SS}opt${SS}tivoli${SS}tsm${SS}server${SS}bin";
            $db2Path    = "${SS}opt${SS}tivoli${SS}tsm${SS}db2";
        }
        else {
            $serverPath = "";
            $db2Path    = "";
            if ( -f $imclcmd ) {
                @imclOut = `$imclcmd listinstallationdirectories`;
                foreach $line (@imclOut) {
                    if ( $line =~ m/tsm/ ) {
                        chomp($line);
                        if ( -f $line . "${SS}server${SS}bin${SS}dsmserv" ) {
                            $serverPath = $line . "${SS}server${SS}bin";
                            $db2Path    = $line . "${SS}db2";
                        }
                    }
                }
            }
            elsif ( -l "${SS}usr${SS}bin${SS}dsmserv" ) {
                $lsout = `ls -l ${SS}usr${SS}bin${SS}dsmserv`;
                $lsout =~ s/.*->\s+(.*)\/dsmserv\s+/$1/;
                if ( -f $lsout . "${SS}dsmserv" ) {
                    $serverPath = $lsout;
                    $lsout =~ s/(.*)\/server\/bin/$1/;
                    $db2Path = $lsout . "${SS}db2";
                }
            }

            if ( $serverPath ne "" ) {
                $serverinstalled = 1;
                if ( -f $serverPath . "${SS}tsmbasic.lic" ) {
                    $serverlicenseinstalled = 1;
                }
                $serverVersion = 7;
            }

        }    # end of v7 handling
    }
    elsif ( $platform eq "WIN32" ) {
        $serverinstalled        = 0;
        $serverlicenseinstalled = 0;
        $apiclientinstalled     = 0;
        $baclientinstalled      = 0;
        $adminclientinstalled   = 0;
        $serverVersion          = 0;

        $queryserverkeycmd =
"reg query HKLM${SS}SOFTWARE${SS}IBM${SS}ADSM${SS}CurrentVersion${SS}Server";

        @queryserverkeycmdOut = `$queryserverkeycmd`;

        foreach $queryserverkeyOutln (@queryserverkeycmdOut) {
            if ( $queryserverkeyOutln =~ m/Path\s+\w+\s+(.*)$/ ) {
                $serverPath      = $1;
                $serverinstalled = 1;

                $serverPath =~ s#\\Program Files\\#\\Progra~1\\#g;
            }
            elsif ( $queryserverkeyOutln =~ m/PTFLevel\s+\w+\s+(\d+)./ ) {
                $serverVersion = $1;
            }
        }

        if ( $serverinstalled == 1 ) {
            $querydb2keycmd = "reg query HKLM${SS}SOFTWARE${SS}IBM${SS}DB2";

            @querydb2keycmdOut = `$querydb2keycmd`;

            foreach $querydb2keyOutln (@querydb2keycmdOut) {
                if ( $querydb2keyOutln =~ m/DB2\s+Path\s+Name\s+\w+\s+(.*)$/ ) {
                    $db2Path = $1;

                    $lastdelimiterpos = rindex( $db2Path, ${SS} );
                    if ( $lastdelimiterpos == ( length($db2Path) - 1 ) ) {
                        $db2Path = substr( $db2Path, 0, $lastdelimiterpos );
                    }
                    $db2Path =~ s#\\Program Files\\#\\Progra~1\\#g;
                }

                $db2cmdPath   = $db2Path . "${SS}bin${SS}db2cmd";
                $db2setPath   = $db2Path . "${SS}bin${SS}db2set";
                $db2exePath   = $db2Path . "${SS}bin${SS}db2";
                $db2startPath = $db2Path . "${SS}bin${SS}db2start";
                $db2stopPath  = $db2Path . "${SS}bin${SS}db2stop";
            }
        }

        $queryserverlicensekeycmd =
"reg query HKLM${SS}SOFTWARE${SS}IBM${SS}ADSM${SS}CurrentVersion${SS}license";

        @queryserverlicensekeycmdOut = `$queryserverlicensekeycmd`;

        foreach $queryserverlicensekeyOutln (@queryserverlicensekeycmdOut) {
            if ( $queryserverlicensekeyOutln =~ m/Path\s+\w+\s+(.*)$/ ) {
                $serverlicenseinstalled = 1;
            }
        }

        $querybaclientkeycmd =
"reg query HKLM${SS}SOFTWARE${SS}IBM${SS}ADSM${SS}CurrentVersion${SS}BackupClient";

        @querybaclientkeycmdOut = `$querybaclientkeycmd`;

        foreach $querybaclientkeyOutln (@querybaclientkeycmdOut) {
            if ( $querybaclientkeyOutln =~ m/Path\s+\w+\s+(.*)$/ ) {
                $baclientPath = $1;
                $baclientPath =~ s#\\Program Files\\#\\Progra~1\\#g;
                $dsmcPath = "$baclientPath" . "${SS}" . "dsmc.exe";

                if ( -f $dsmcPath ) {
                    $baclientinstalled = 1;
                }
            }
        }

        $queryapiclientkeycmd =
"reg query HKLM${SS}SOFTWARE${SS}IBM${SS}ADSM${SS}CurrentVersion${SS}Api64";

        @queryapiclientkeycmdOut = `$queryapiclientkeycmd`;

        foreach $queryapiclientkeyOutln (@queryapiclientkeycmdOut) {
            if ( $queryapiclientkeyOutln =~ m/Path\s+\w+\s+(.*)$/ ) {
                $apiclientPath      = $1;
                $apiclientinstalled = 1;

                $apiclientPath =~ s#\\Program Files\\#\\Progra~1\\#g;
            }
        }

# check that the admin client is installed with the BA client on Windows, since the admin client is optional in Windows

        $queryadminclientkeycmd =
"reg query HKLM${SS}SOFTWARE${SS}IBM${SS}ADSM${SS}CurrentVersion${SS}AdminClient";

        @queryadminclientkeycmdOut = `$queryadminclientkeycmd`;

        foreach $queryadminclientkeyOutln (@queryadminclientkeycmdOut) {
            if ( $queryadminclientkeyOutln =~ m/Path\s+\w+\s+(.*)$/ ) {
                $adminclientPath = $1;

                $adminclientPath =~ s#\\Program Files\\#\\Progra~1\\#g;
                $dsmadmcPath = "$adminclientPath" . "${SS}" . "dsmadmc.exe";

                if ( -f $dsmadmcPath ) {
                    $adminclientinstalled = 1;
                }
            }
        }
    }

    if ( $serverinstalled == 0 ) {
        logentry("Unexpected result from: $queryserverkeycmd\n");
        logentry(
"Exiting due to IBM Storage Protect server installation not detected\n"
        );
        die
"This configuration script requires that the IBM Storage Protect server be installed\n";
    }

    if ( $serverlicenseinstalled == 0 ) {
        logentry("Unexpected result from: $queryserverlicensekeycmd\n");
        logentry(
"Exiting due to IBM Storage Protect server license installation not detected\n"
        );

        die
"This configuration script requires that the IBM Storage Protect server license be installed\n";
    }

    if ( $apiclientinstalled == 0 ) {
        logentry("Unexpected result from: $queryapiclientkeycmd\n");
        logentry(
"Exiting due to IBM Storage Protect API client installation not detected\n"
        );

        die
"This configuration script requires that the IBM Storage Protect API client be installed\n";
    }

    if ( $baclientinstalled == 0 ) {
        logentry("Unexpected result from: $querybaclientkeycmd\n");
        logentry(
"Exiting due to IBM Storage Protect BA client installation not detected\n"
        );

        die
"This configuration script requires that the IBM Storage Protect BA client be installed\n";
    }

    if ( ( $platform eq "WIN32" ) && ( $adminclientinstalled == 0 ) ) {
        logentry("Unexpected result from: $queryadminclientkeycmd\n");
        logentry(
"Exiting due to IBM Storage Protect BA administrative client installation not detected\n"
        );

        die
"This configuration script requires that the IBM Storage Protect administrative client be installed\n";
    }

    if ( $serverVersion < 7 && $compressFlag == 1 ) {
        logentry(
"The -compression flag should only be used with V7 servers and newer\n"
        );

        die
"The -compression flag should only be used with V7 servers and newer\n";
    }

    if ( $platform eq "WIN32" ) {
        logentry(
"Successfully verified prerequisites: IBM Storage Protect server, server license, API client, BA client and administrative client\n"
        );
    }
    else {
        logentry(
"Successfully verified prerequisites: IBM Storage Protect server, server license, API client and BA client\n"
        );
    }

    logentry("Server path: $serverPath\n");
    logentry("Server version: $serverVersion\n");
    logentry("DB2 path: $db2Path\n");

    if ( $platform eq "WIN32" ) {
        logentry("BA client path: $baclientPath\n");
        logentry("API client path: $apiclientPath\n");
        logentry("Admin client path: $adminclientPath\n");
    }

    $stateHash{serverpath} = $serverPath;    # add these paths to the hash
    $stateHash{db2path}    = $db2Path;
    if ( $platform eq "WIN32" ) {
        $stateHash{db2cmdpath}   = $db2cmdPath;
        $stateHash{db2setpath}   = $db2setPath;
        $stateHash{db2exepath}   = $db2exePath;
        $stateHash{db2startpath} = $db2startPath;
        $stateHash{db2stoppath}  = $db2stopPath;
    }
}

############################################################
#      sub: getPlatform
#     desc: Returns the platform type.  The type returned
#           represent constants which are used throughout the test
#           automation.  The type is determined based on the Perl built-in
#           ^O variable.
#   params: None
#  returns: $string containing platform type constant
############################################################

sub getPlatform() {
    $platfrm = $^O;    # $^O is built-in variable containing osname
    if ( $platfrm =~ m#^aix# )     { return "AIX" }
    if ( $platfrm =~ m#^MSWin32# ) { return "WIN32" }

    if ( $platfrm =~ m#^linux# ) {
        my @uname = `uname -a`;

        foreach (@uname) {
            if ( $_ =~ m#x86_64# ) {
                return "LINUX86";
            }
            elsif ( $_ =~ m#ppc64le# ) {
                return "LINUXPPCLE";
            }
            elsif ( $_ =~ m#ppc64# ) {
                return "LINUXPPC";
            }
        }
    }

    # We haven't found a match yet, so return UNKNOWN
    return "UNKNOWN";
}

############################################################
#      sub: getpathdelimiter
#     desc: Returns the path delimiter appropriate to the platform
#           specified by the argument, e.g., forward slash for Unix
#           or Linux platform, backslash for Windows
#   params: 1. The platform
#  returns: the appropriate path delimiter
############################################################

sub getpathdelimiter {
    $pltfrm = shift(@_);

    if ( $pltfrm eq "WIN32" ) {
        return "\\";
    }
    else {
        return "/";
    }
}

############################################################
#      sub: validateServerObjectName
#     desc: Verifies that the name specified by the first argument
#           only has characters that are permitted for server object
#           names, and that it does not exceed the length specified
#           by the second argument.  The permissible characters are:
#           A-Z, a-z, 0-9, _, ., -, +, &
#
#   params: 1. the name to be validated
#           2. the maximum length that the name can have
#
#  returns: an array consisting of a return code (0 if the name
#           is valid, 1 if not valid) and in the case of an invalid
#           name, a suitable message
#############################################################

sub validateServerObjectName {
    $objname   = shift(@_);
    $maxlength = shift(@_);

    $objnamelength = length($objname);

    if ( $objnamelength < 1 ) {
        logentry("        object name does not meet length requirements\n");
        my @rcArray = ( 1, "name not valid" );
        return @rcArray;
    }
    elsif ( $objnamelength > $maxlength ) {
        logentry("        object name does not meet length requirements\n");
        my @rcArray = ( 1, "name too long" );
        return @rcArray;
    }

    my $tempstr        = $objname;
    my $validcharfound = 0;

    do {
        $firstch        = substr( $tempstr, 0, 1 );
        $validcharfound = 0;

        foreach $ch (@validCharArray) {
            if ( $firstch eq $ch ) {
                $validcharfound = 1;
            }
        }

        $tempstr = substr( $tempstr, 1 );

    } while ( ( length($tempstr) > 0 ) && ( $validcharfound == 1 ) );

    if ( $validcharfound == 1 ) {
        my @rcArray = ( 0, "" );
        return @rcArray;
    }
    else {
        logentry("        object name has an invalid character in it\n");
        my @rcArray = ( 1, "name not valid" );
        return @rcArray;
    }
}

############################################################
#      sub: validatedb2username
#     desc: Checks if the specified db2 username meets the
#           DB2 requirements for the user name (such as length
#           and characters used in the name)
#
#   params: user name to be validated
#  returns: an array of 4 entries, the first entry being a return
#           code, the second indicating whether the user exists
#           (0 if it does not exist, 1 if it does) and if it does exist,
#           the third is a reference to a structure with information
#           about the user, and the fourth is a message string
#
############################################################

sub validatedb2username {
    $uname = shift(@_);

    $unamelength = length($uname);

    my $tempusrstr     = $uname;
    my $validcharfound = 0;

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        if ( ( $unamelength < 1 ) || ( $unamelength > 8 ) ) {
            logentry(
"        user name does not meet length requirements; it should be between 1 and 8 characters long\n"
            );
            my @rcArray = ( 1, "", "", "username not valid" );
            return @rcArray;
        }
    }
    elsif ( $platform eq "WIN32" ) {
        if ( ( $unamelength < 1 ) || ( $unamelength > 30 ) ) {
            logentry(
"        user name does not meet length requirements; it should be between 1 and 30 characters long\n"
            );
            my @rcArray = ( 1, "", "", "username not valid" );
            return @rcArray;
        }
    }

    $uname_uc = uc($uname);

    if (   ( $uname_uc eq "USERS" )
        || ( $uname_uc eq "ADMINS" )
        || ( $uname_uc eq "GUESTS" )
        || ( $uname_uc eq "PUBLIC" )
        || ( $uname_uc eq "LOCAL" ) )
    {
        logentry(
"        user name may not be any of the following: USERS, ADMINS, GUESTS, PUBLIC, LOCAL\n"
        );
        my @rcArray = ( 1, "", "", "username not valid" );
        return @rcArray;
    }

    if (   ( $uname_uc =~ m/^\d+/ )
        || ( $uname_uc =~ m/^_/ )
        || ( $uname_uc =~ m/^IBM/ )
        || ( $uname_uc =~ m/^SYS/ )
        || ( $uname_uc =~ m/^SQL/ ) )
    {
        logentry(
"        user name may not start with any of the following: a number, underscore, IBM, SYS, SQL\n"
        );
        my @rcArray = ( 1, "", "", "username not valid" );
        return @rcArray;
    }

    do {
        $firstch        = substr( $tempusrstr, 0, 1 );
        $validcharfound = 0;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            foreach $ch (@validCharArray_db2unx) {
                if ( $firstch eq $ch ) {
                    $validcharfound = 1;
                }
            }
        }
        elsif ( $platform eq "WIN32" ) {
            foreach $ch (@validCharArray_db2win) {
                if ( $firstch eq $ch ) {
                    $validcharfound = 1;
                }
            }
        }
        $tempusrstr = substr( $tempusrstr, 1 );

    } while ( ( length($tempusrstr) > 0 ) && ( $validcharfound == 1 ) );

    if ( $validcharfound == 0 ) {
        logentry("        user name has an invalid character in it\n");
        logentry("        Name: $uname     Invalid character: $firstch\n");
        my @rcArray = ( 1, "", "", "username not valid" );
        return @rcArray;
    }

    if (   ( $platform eq "LINUX86" )
        || ( $platform eq "AIX" )
        || ( $platform =~ m/LINUXPPC/ ) )
    {
        ( $unamefound, $unameinfo ) = getunxuserproperties($uname);
    }
    elsif ( $platform eq "WIN32" ) {
        ( $unamefound, $unameinfo ) = getwinuserproperties($uname);
    }

    if (
        ( $unamefound == 1 )
        && (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
      )
    {
        if (   ( $unameinfo->{prgrp} eq "guests" )
            || ( $unameinfo->{prgrp} eq "admins" )
            || ( $unameinfo->{prgrp} eq "users" )
            || ( $unameinfo->{prgrp} eq "local" ) )
        {
            logentry(
"        user primary group may not be any of the following: guests, admins, users, local\n"
            );
            my @rcArray = ( 1, $unamefound, $unameinfo, "username not valid" );
            return @rcArray;
        }
        else {
            my @rcArray = ( 0, $unamefound, $unameinfo, "" );
            return @rcArray;
        }
    }
    else {
        my @rcArray = ( 0, $unamefound, $unameinfo, "" );
        return @rcArray;
    }
}

############################################################
#      sub: validatedb2groupname
#     desc: Checks if the specified db2 group name meets the
#           DB2 requirements for the primary group name (such as
#           length and characters used in the name)
#
#   params: group name to be validated
#  returns: an array of 4 entries, the first entry being a return
#           code, the second indicating whether the group exists
#           (0 if it does not exist, 1 if it does) and if it does exist,
#           the third is the group id, and the fourth is a
#           message string
#
############################################################

sub validatedb2groupname {
    $gname = shift(@_);

    $gnamelength = length($gname);

    my $tempgrpstr     = $gname;
    my $validcharfound = 0;

    if ( ( $gnamelength < 1 ) || ( $gnamelength > 8 ) ) {
        logentry(
"        group name does not meet length requirements; it should be between 1 and 8 characters long\n"
        );
        my @rcArray = ( 1, "", "", "groupname not valid" );
        return @rcArray;
    }

    $gname_uc = uc($gname);

    if (   ( $gname_uc eq "USERS" )
        || ( $gname_uc eq "ADMINS" )
        || ( $gname_uc eq "GUESTS" )
        || ( $gname_uc eq "PUBLIC" )
        || ( $gname_uc eq "LOCAL" ) )
    {
        logentry(
"        group name may not be any of the following: USERS, ADMINS, GUESTS, PUBLIC, LOCAL\n"
        );
        my @rcArray = ( 1, "", "", "groupname not valid" );
        return @rcArray;
    }

    if (   ( $gname_uc =~ m/^\d+/ )
        || ( $uname_uc =~ m/^_/ )
        || ( $gname_uc =~ m/^IBM/ )
        || ( $gname_uc =~ m/^SYS/ )
        || ( $gname_uc =~ m/^SQL/ ) )
    {
        logentry(
"        group name may not start with any of the following: a number, underscore, IBM, SYS, SQL\n"
        );
        my @rcArray = ( 1, "", "", "groupname not valid" );
        return @rcArray;
    }

    do {
        $firstch        = substr( $tempgrpstr, 0, 1 );
        $validcharfound = 0;

        if (   ( $platform eq "LINUX86" )
            || ( $platform eq "AIX" )
            || ( $platform =~ m/LINUXPPC/ ) )
        {
            foreach $ch (@validCharArray_db2unx) {
                if ( $firstch eq $ch ) {
                    $validcharfound = 1;
                }
            }
        }
        elsif ( $platform eq "WIN32" ) {
            foreach $ch (@validCharArray_db2win) {
                if ( $firstch eq $ch ) {
                    $validcharfound = 1;
                }
            }
        }
        $tempgrpstr = substr( $tempgrpstr, 1 );

    } while ( ( length($tempgrpstr) > 0 ) && ( $validcharfound == 1 ) );

    if ( $validcharfound == 0 ) {
        logentry("        group name has an invalid character in it\n");
        my @rcArray = ( 1, "", "", "groupname not valid" );
        return @rcArray;
    }

    ( $gnamefound, $gid ) = getunxgroupproperties($gname);

    my @rcArray = ( 0, $gnamefound, $gid, "" );
    return @rcArray;
}

############################################################
#      sub: validateTcpport
#     desc: Verifies that the port specified by the argument
#           has only digits, has length 4 or 5, and its
#           numerical value lies in the range 1024 to 32767
#
#   params: 1. the port to be validated
#
#  returns: an array consisting of a return code (0 if the port
#           is valid, 1 if not valid) and in the case of an invalid
#           port, a suitable message
#############################################################

sub validateTcpport {
    $tprt = shift(@_);

    $tprtlength = length($tprt);

    if (   ( ( $tprtlength == 4 ) && ( $tprt =~ m/\d\d\d\d/ ) )
        || ( ( $tprtlength == 5 ) && ( $tprt =~ m/\d\d\d\d\d/ ) ) )
    {
        $tprtval = int($tprt);

        if ( ( $tprtval >= 1024 ) && ( $tprtval <= 32767 ) ) {
            my @rcArray = ( 0, "" );
            return @rcArray;
        }
        else {
            my @rcArray = ( 1, "port not valid" );
            return @rcArray;
        }
    }
    else {
        my @rcArray = ( 1, "port not valid" );
        return @rcArray;
    }
}

############################################################
#      sub: validatePassword
#     desc: Validates a password against various checks to
#           prevent the use of highly insecure passwords.
#
#   params: 1. the password to be validated
#
#  returns: 0 if the password is acceptable, 1 otherwise
#############################################################

sub validatePassword {
    my $pswd = shift(@_);
    my $rc = 0;

    if (length($pswd) < $minPWlength) {
        logentry("ERROR: Password provided contains fewer than $minPWlength caracters.\n");
        displayString(15, 1, "ERROR: Password provided contains fewer than $minPWlength caracters.", "");
        $rc = 1;
    }
    if (length($pswd) > 64) {
        logentry("ERROR: Password provided contains more than 64 characters.\n");
        displayString(15, 1, "ERROR: Password provided contains more than 64 caracters.", "");
        $rc = 1;
    }
    if ($pswd eq $defaultPW) {
        logentry("ERROR: The sample password entry, $defaultPW, needs to be changed in the response file.\n");
        displayString(15, 1, "ERROR: The sample password entry, $defaultPW, needs to be changed in the response file.", "");
        $rc = 1;
    }
    else {
        foreach $curPW (@insecurePWlist) {
            if ($pswd eq $curPW) {
                logentry("ERROR: The common password, $curPW, is insecure and is not allowed.\n");
                displayString(15, 1, "ERROR: The common password, $curPW, is insecure and is not allowed.", "");
                $rc = 1;
            }
        }
    }

    # Make sure the password only contains characters acceptable to IBM Storage Protect
    my $tempstr        = $pswd;
    my $validcharfound = 0;

    do {
        $firstch        = substr( $tempstr, 0, 1 );
        $validcharfound = 0;

        foreach $ch (@validCharArraySPpw) {
            if ( $firstch eq $ch ) {
                $validcharfound = 1;
            }
        }

        $tempstr = substr( $tempstr, 1 );

    } while ( ( length($tempstr) > 0 ) && ( $validcharfound == 1 ) );  

    if ($validcharfound == 0) {
        logentry("ERROR: An invalid character $firstch was specified for a password.\n");
        displayString(15, 1, "ERROR: An invalid character $firstch was specified for a password.", "");
        $rc = 1;
    }

    return $rc;
}        