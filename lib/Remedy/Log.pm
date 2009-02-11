package Remedy::Log;
our $VERSION = '0.10';

=head1 NAME

Remedy::Log - Remedy logging functions

=head1 SYNOPSIS

    use Remedy::Config;
    use Log::Log4perl qw/:easy/;

    my $logger = get_logger ('');   # get the root level logger
    $logger->debug ('If this shows anywhere, we have a problem.');

    my $file = '/etc/remedy/remedy.conf';
    my $config = Remedy::Config->load ($file);

    ## NOT NECESSARY, but helpful to illustrate what's going on
    # $logger = $config->logger;  

    $logger->warn ('You should see this on STDERR and in the logfile.');
    $logger->info ('This should only appear in the logfile.');
    $logger->more_logging (1);
    $logger->info ('Now this should also appear on STDERR.');

=head1 DESCRIPTION

Remedy::Log manages the logging functions for B<Remedy>, using several
root-level loggers implemented using B<Log::Log4perl>.  This controls the
status and error messages sent to both STDERR, and (optionally) to a central
log file.

Remedy::Log is implemented as a B<Class::Struct> object, and is initialized 
via B<Remedy::Config>.

=cut

##############################################################################
### Configuration
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

our $LOGLEVEL_FILE = $INFO;

=item $NAME

necessary?

=cut

our $NAME = "Remedy";

=back

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Log::Log4perl qw/:easy/;
use Log::Log4perl::Level;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 Subroutines 

=head2 B<Class::Struct> Accessors

As noted above, most subroutines are handled by B<Class::Struct>; please see
its man page for more details about the various sub-functions.

=over 4

=item file ($)

=item level ($)

=item level_file ($)

=item logger (Log::Log4perl::Logger)

=back

=cut

struct 'Remedy::Log' => {
    'file'       => '$',
    'level'      => '$',
    'level_file' => '$',
    'logger'     => 'Log::Log4perl::Logger',
    'name'       => '$',
};

=back

=head2 Additional Functions

=over 4

=item init ()

=cut

sub init {
    warn "INIT: @_\n";
    my ($self, %args) = @_;

    $self->name       ($self->name       || $NAME);
    $self->level      ($self->level      || $LOGLEVEL);
    $self->level_file ($self->level_file || $LOGLEVEL_FILE);
    $self->file       ($self->file       || $FILE);

    foreach (qw/name level level_file file/) {
        warn "F: $_ " . $self->$_ . "\n";
    }
    my (%appenders, %layouts);

    # Define a category logger
    my $logger = Log::Log4perl->get_logger ('');
    $Log::Log4perl::one_message_per_appender = 1;

    my $appender =  Log::Log4perl::Appender->new (  
        "Log::Log4perl::Appender::ScreenColoredLevels", 
        'name' => "$0", stderr => 1);
    my $layout = Log::Log4perl::Layout::PatternLayout->new ($FORMAT);
    $appender->layout ($layout);

    $logger->add_appender ($appender);

    if (my $name = $self->file) {
        my $appender = Log::Log4perl::Appender->new (
            "Log::Log4perl::Appender::File",
            filename  => $self->file);
        my $layout = Log::Log4perl::Layout::PatternLayout->new 
            ($FORMAT_FILE . $FORMAT);
        $appender->layout ($layout);

        $appender->threshold ($self->level_file);
        $logger->add_appender ($appender);
    }

    $logger->level ($self->level);
    $self->logger ($logger);
}

=item more_logging (COUNT)

=cut

sub more_logging {
    my ($self, $count) = @_;
    return unless $count > 0;
    $self->logger->more_logging (int $count);
}

=back

=cut

##############################################################################
### Final Documentation
##############################################################################

=head1 SEE ALSO

Remedy::Config(8)

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
