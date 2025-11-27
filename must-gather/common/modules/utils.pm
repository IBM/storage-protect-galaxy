package utils;
use strict;
use warnings;
use Exporter 'import';
use File::Path qw(make_path);

# Exported functions
our @EXPORT_OK = qw(
    run_to_file 
    write_to_file 
    timestamp 
    safe_mkdir
);

# -----------------------------
# Run a command and save output to a file
# -----------------------------
# Arguments:
#   $cmd  - command to execute
#   $file - file path to store output
# Behavior:
#   - Ensures the parent directory exists
#   - Executes the command and redirects stdout/stderr to file
#   - Returns a status message
sub run_to_file {
    my ($cmd, $file) = @_;

    # Ensure the directory exists before writing
    if ($file =~ m{^(.*)/}) {
        my $dir = $1;
        make_path($dir) unless -d $dir;
    }

    # Run the command and redirect output to the file
    my $status = system("$cmd > \"$file\" 2>&1");  # overwrite file safely

    if ($status != 0) {
        return "Warning: Command '$cmd' exited with code " . ($status >> 8) . "\n";
    }

    return "Saved output to $file\n";
}

# -----------------------------
# Write data directly to a file
# -----------------------------
# Arguments:
#   $file     - file path to write
#   $data_ref - string or hashref
# Behavior:
#   - Ensures the parent directory exists
#   - If hashref is given, writes key=value lines
#   - Else writes raw string content
sub write_to_file {
    my ($file, $data_ref) = @_;

    # Ensure the directory exists
    my ($dir) = $file =~ m{^(.*)/};
    make_path($dir) if defined $dir && ! -d $dir;

    open(my $fh, ">", $file) or die "Cannot open $file: $!";
    if (ref($data_ref) eq 'HASH') {
        foreach my $key (sort keys %$data_ref) {
            print $fh "$key=$data_ref->{$key}\n";
        }
    } else {
        print $fh $data_ref;
    }
    close $fh;
}

# -----------------------------
# Generate timestamp string
# -----------------------------
# Format: YYYYMMDD_HHMMSS
# Example: 20250929_114530
sub timestamp {
    my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
    $year  += 1900;
    $mon   += 1;
    return sprintf("%04d%02d%02d_%02d%02d%02d",
        $year, $mon, $mday, $hour, $min, $sec);
}

# -----------------------------
# Safely create a directory
# -----------------------------
# Arguments:
#   $dir - directory path
# Behavior:
#   - Creates the directory (and parents if needed)
#   - Returns 1 on success, 0 on failure
sub safe_mkdir {
    my ($dir) = @_;
    eval { make_path($dir); };
    return $@ ? 0 : 1;
}

1;
