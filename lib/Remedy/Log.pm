package Remedy::Log;
our $VERSION = '0.10';

=head1 NAME

Remedy::Log - Remedy logging functions

=head1 SYNOPSIS

    use Remedy::Log;

    my $logger = Remedy::Log->get_logger ();
    $logger->debug ('If this shows anywhere, we have a problem.');

    my $log = Remedy::Log->new (
        'file'       => '/tmp/remedy-log.txt',
        'level'      => $Log::Log4perl::ERROR,
        'level_file' => $Log::Log4perl::INFO,
    );
    $log->init ();

    $logger->warn ('You should see this on STDERR and in the logfile.');
    $logger->info ('This should only appear in the logfile.');
    $log->more_logging (1);
    $logger->info ('Now this should also appear on STDERR.');

=head1 DESCRIPTION

Remedy::Log manages the logging functions for B<Remedy>, using two root-level
loggers implemented using B<Log::Log4perl>:

=over 4

=item screen

Output is logged to STDERR using a I<ScreenColoredLevels> appender.

=item file

Output is appended to a defined, central log file.

=back

Once configured, scripts and modules should send copious debugging information
to the root logger, and B<Log::Log4perl> will take care of deciding what to do
with it.

Remedy::Log is implemented as a B<Class::Struct> object, and is initialized via
B<Remedy::Config>.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

=head1 Configuration

The following default options are used to

=over 4

=item $FILE

Location of a log file to which we will append logs.  You will have to make
sure that ownerships are acceptable.  No default.

=cut

our $FILE = '';

=item $FORMAT

Defines the format of the messages we will print on B<STDERR>.  Defaults
to '%F{1}: %m%n', which indicates that we will have the last component of
the filename running the function, the message itself, and a newline.  See
B<Log::Log4perl> for more details.

There is no accessor override for this function.

=cut

our $FORMAT = '%F{1}: %m%n';

=item $FORMAT_FILE

Defines the format of the messages that we will print to I<$FILE>, above.
Defaults to '[%d] %p ' prepended to B<$FORMAT>, which adds the timedate and
debug level to the above format.

There is no accessor override for this function.

=cut

our $FORMAT_FILE = '[%d] %p ' . $FORMAT;

=item $LOGLEVEL

Default loglevel for output to STDERR.  Set to I<$Log::Log4perl::ERROR> by
default, indicating that we want to record levels I<error> and I<fatal>.

=cut

our $LOGLEVEL = $Log::Log4perl::ERROR;

=item $LOGLEVEL_FILE

Default loglevel for output to the logfile; anything up to AND NOT EXCEEDING
this level is saved.  Set to I<$Log::Log4perl::INFO>, indicating that we want
to record levels I<info>, I<warn>, I<error>, and I<fatal>.

=cut

our $LOGLEVEL_FILE = $Log::Log4perl::INFO;

=back

=cut

## Global Configuration
$Log::Log4perl::one_message_per_appender = 1;

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Log::Log4perl qw/:nowarn/;
use Log::Log4perl::Level;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 Subroutines

=head2 B<Class::Struct> Accessors

These fields can be initialized via B<new ()> or per-function.

=over 4

=item new ()

Creates a new object.  

=item file ($)

Filename for file output.  Corresponds to I<$FILE>.

=item level ($)

Loglevel for STDERR output.  Corresponds to I<$LOGLEVEL>.

=item level_file ($)

Loglevel for file output.  Corresponds to I<$LOGLEVEL_FILE>.

=item logger (Log::Log4perl::Logger)

The actual B<Log::Log4perl::Logger> object.

=back

=cut

struct 'Remedy::Log' => {
    'file'       => '$',
    'level'      => '$',
    'level_file' => '$',
    'logger'     => 'Log::Log4perl::Logger',
};

=head2 Additional Functions

=over 4

=item get_logger ()

If invoked on a configured object, returns the value of B<logger ()>.  If
invoked from the module itself or from an uninitialized object, then we will
return the root-level logger.

=cut

sub get_logger {
    my ($self) = @_;
    return $self->logger if (ref $self && $self->logger);
    return Log::Log4perl::get_logger ('');
}

=item init ()

(Re)initializes the B<Remedy::Log> object.  This follows the general path of:

    Pull in default values, if not already set
    Get default logger object (defaults to root-level)
    Blow away existing appenders, if any
    Initialize screen appender, add to our logger object
    Initialize file appender (if applicable), add to our logger object
    Set logger level to the higher of the two log levels
    Save logger with logger () accessor, and return

In order to set up basic logging immediately, this is invoked on module load
with default options.

=cut

sub init {
    my ($self, %args) = @_;
    $self = $self->new unless ref $self;

    $self->level      ($LOGLEVEL)      unless defined $self->level;
    $self->level_file ($LOGLEVEL_FILE) unless defined $self->level_file;
    $self->file       ($FILE)          unless defined $self->file;

    ## Get the Log::Log4perl::Logger object we'll use consistently
    my $logger = $self->get_logger;

    ## Clear the old appenders
    foreach my $old (qw/screen file/) { $logger->eradicate_appender ($old) }

    ## Create the screen appender
    $logger->all ('adding screen appender');
    my $appender =  Log::Log4perl::Appender->new (
        "Log::Log4perl::Appender::ScreenColoredLevels",
        'name' => "screen", stderr => 1);
    my $layout = Log::Log4perl::Layout::PatternLayout->new ($FORMAT);
    $appender->layout ($layout);
    $logger->all ("set screen appender threshold to " .  $self->level);
    $appender->threshold ($self->level);
    $logger->add_appender ($appender);
    binmode (STDERR, ":utf8");

    if (my $name = $self->file) {
        $logger->all ("adding file appender to $name");
        my $appender = Log::Log4perl::Appender->new (
            "Log::Log4perl::Appender::File",
            'name' => 'file', 'filename' => $name, 'utf8' => 1);
        my $layout = Log::Log4perl::Layout::PatternLayout->new
            ($FORMAT_FILE);
        $appender->layout ($layout);

        $logger->all ("set file appender threshold to " .  $self->level_file);
        $appender->threshold ($self->level_file);
        $logger->add_appender ($appender);
    }

    my $level = $self->level_file >= $self->level ? $self->level_file
                                                  : $self->level;
    $logger->all ('set global appender level to ' . $level);
    $logger->level ($level);
    $self->logger ($logger);
}

## Initialize default logging
__PACKAGE__->init ();

=item more_logging (COUNT [, APPENDERS])

Increases the amount of logging by I<COUNT> levels.  This increases the
loglevel with B<Log::Log4perl::more_logging ()>, and decreases the appender
thresholds with B<Log::Log4perl::appender_thresholds_adjust ()>.

If an arrayref I<APPENDERS> is offered, then this latter part we will adjust
the thresholds of the appenders named after the array's contents; if not, we
will just adjust the threshold for 'screen'.

=cut

sub more_logging {
    my ($self, $count, $appender) = @_;
    my $logger = $self->logger || return;

    return unless $count > 0;
    if ($appender && ! ref $appender) {
        $logger->debug ('appender must be an arrayref');
        $appender = [$appender];
    } else { $appender ||= ['screen']; }

    $logger->all ("increasing global loglevel by $count");
    $logger->more_logging (int $count);

    $logger->all (sprintf ("adjusting appender thresholds by %d for %s",
        int $count, join (', ', @$appender)));
    Log::Log4perl->appender_thresholds_adjust (- int $count, $appender);

    $logger->debug (sprintf ('increased loglevel by %d for %s',
        int $count, join (', ', @$appender)));
    return 1;
}

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 Log::Log4perl Overview

While I have no desire to reproduce the B<Log::Log4perl> man page, a short
introduction to using the module might be helpful.  (Parts of this are cribbed
from the B<Log::Log4perl> manual page.)

The main object that you will interact with is a B<Log::Log4perl::Logger>
object (B<$logger>).  This object offers a variety of priority logging functions:

    $logger->all   ()    # incorrectly listed as 'trace' in the man page
    $logger->debug ()
    $logger->info  ()
    $logger->warn  ()
    $logger->error ()
    $logger->fatal ()

Each of these functions corresponds to a priority.  When the function is
called, we compare this priority to the loglevel set within $logger; if the
loglevel at least matches the priority, then we'll print the message.  So, if
the loglevel is set to, say, B<$Log::Log4level::WARN>, then we will print
messages whenever we call B<warn ()>, B<error ()>, or B<fatal ()>.

There are two ways to look at this state of affairs:

=over 4

=item loglevel perspective

Your program should probably be set to look at the loglevel
B<$Log::Log4perl::ERROR> most of the time, so the user can avoid worrying
about things that he/she doesn't care about.  But it should be fairly easy
for the user to adjust this, in case more information would be helpful.  Use
B<more_logging ()> to adjust the thresholds.

=item code-writing perspective

If there's even a slight chance that we can use information at a logging level,
print it at some level - generally at B<all ()> or B<debug ()>.  B<info ()> is
used for situations where we want to watch the general flow of the program, but
not the details; B<warn ()> is for situations where something weird happened,
but the user doesn't necessarily need to know that; B<error ()> is for when
something bad has happened and the user really ought to know; and B<fatal ()>
is for when we're going to die anyway.

=back

Some efficiency can be gained by using the B<is_level ()> functions, such as:

    $logger->is_warn ();     # True if warning messages would go through

Additionally, B<Log::Log4perl::Logger> offers functions that will log a message
at the appropriate level and then warn/die/carp/whatever:

    $logger->logwarn    ()
    $logger->logdie     ()
    $logger->logcarp    ()
    $logger->logcroak   ()
    $logger->logcluck   ()
    $logger->logconfess ()
    $logger->error_warn ()
    $logger->error_warn ()

Behind the scenes, B<Log::Log4perl> uses B<Log::Log4perl::Appender> objects to
actually output the data from the B<Log::Log4perl::Logger> object.  We define
two: a 'screen' appender, which logs to STDERR (colored by loglevel), and a
'file' appender, which writes to a central logfile (no colors).  There are many
more appender types than this, and we may take advantage of them in the future.

At the appender level, there is a concept of thresholds - that is, we won't
actually print the output to the appender if the message is above a certain
priority.  Otherwise, the loglevel is set globally for the logger.  This is
useful for the case where the user wants more debugging information on STDERR,
but we don't want that extra information filling the logfile.

You may note that B<Log::Log4perl>'s docs are very much centered on the
"configuration file" initialization schemes.  I have attempted to ignore this
where possible, and handle everything in a fairly object-oriented manner; but
the default methods may be more appropriate, and are certainly more powerful.
So this decision may be revisited later.

You may also note that there are all sorts of other issues to worry about,
such as whether to print duplicate copies of a 'die' call at the script-level,
or what the actual format of the log messages is.  I've tried to set sensible
defaults and leave it at that; please refer to the man pages for more details.

=head1 REQUIREMENTS

B<Log::Log4perl>

=head1 SEE ALSO

Remedy::Config(8), Log::Log4perl::FAQ(8)

=head1 HOMEPAGE

TBD.

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
