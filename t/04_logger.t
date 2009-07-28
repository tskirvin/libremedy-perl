##############################################################################
### Declarations #############################################################
##############################################################################
use Test::More tests => 70;

use strict;
use warnings;

use Log::Log4perl qw/:levels/;
use File::Temp qw/tempfile/;
use Remedy::Log;

# $Remedy::Log::FORMAT = '';  # do not write to stdout
# $Remedy::Log::FORMAT_FILE = '[%d] %p %F{1} %m%n';

##############################################################################
### Default Checks ###########################################################
##############################################################################
# 1 check

ok ($Remedy::Log::VERSION);

##############################################################################
### /dev/null Logging ########################################################
##############################################################################
# 9x7 = 63 checks

our @checks = qw/ALL DEBUG INFO WARN ERROR FATAL OFF/;
our %checks = (
    'ALL'   => [qw/1 1 1 1 1 1/],
    'DEBUG' => [qw/1 1 1 1 1 0/],
    'INFO'  => [qw/1 1 1 1 0 0/],
    'WARN'  => [qw/1 1 1 0 0 0/],
    'ERROR' => [qw/1 1 0 0 0 0/],
    'FATAL' => [qw/1 0 0 0 0 0/],
    'OFF'   => [qw/0 0 0 0 0 0/],
);
our %levels = (
    'ALL'   => $ALL,
    'DEBUG' => $DEBUG,
    'INFO'  => $INFO,
    'WARN'  => $WARN,
    'ERROR' => $ERROR,
    'FATAL' => $FATAL,
    'OFF'   => $OFF,
);

foreach my $check (@checks) {
    my @to_check = @{$checks{$check}};
    my $level    = $levels{$check};
    my $log = Remedy::Log->new (
        'file'       => '/dev/null',
        'level'      => $ALL,
        'level_file' => $level,
    );
    ok ($log,         "object for $check exists");
    ok ($log->init,   "object for $check initializes");
    ok ($log->logger, "logger for $check exists");
    ok (loglevel_ok ($log, $check, 'fatal', $to_check[0]));
    ok (loglevel_ok ($log, $check, 'error', $to_check[1]));
    ok (loglevel_ok ($log, $check, 'warn',  $to_check[2]));
    ok (loglevel_ok ($log, $check, 'info',  $to_check[3]));
    ok (loglevel_ok ($log, $check, 'debug', $to_check[4]));
    ok (loglevel_ok ($log, $check, 'all',   $to_check[5]));
}

##############################################################################
### Real File Logging ########################################################
##############################################################################
# 6 checks

my ($fh, $filename) = tempfile;
my $log = Remedy::Log->new (
    'file'       => $filename,
    'level'      => $Log::Log4perl::ERROR,
    'level_file' => $Log::Log4perl::INFO,
);
ok ($log->init, "initializing file log");
ok ($log->file eq $filename, "logging to $filename");
ok ($log->logger, 'logger initialized');

$log->logger->info ('testing');

$log->logger->warn ('testing warn');
$log->logger->info ('testing info');

my $msg = "Log to file: " . $$;
ok ($log->logger->warn ($msg), "writing a warning to a real file"); 

# The log file should exist.
ok (-e $filename, "file is created"); 

# Look at the last line and make sure you find our message.
my $last_line = `tail -n1 $filename`; 
    warn "L: $filename $last_line\n";
    warn "reading $filename\n";
system ("cat $filename");
    warn "done reading $filename\n";
chomp $last_line;
my $location = index ($last_line, $msg); 
ok ($location >= 0, "read back a log message");

##############################################################################
### Subroutines ##############################################################
##############################################################################

sub loglevel_ok {
    my ($log, $level, $func, $expect) = @_;
    my $text = sprintf ("%-14s against %6s - expecting %d",
        "\$logger->$func", $level, $expect);
    my $ret = $log->logger->$func ($text) || 0;
    return 1 if $ret && $expect;
    return 1 if ! $ret && ! $expect;
    return 0;
}
