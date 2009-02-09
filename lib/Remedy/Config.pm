package Remedy::Config;
our $VERSION = '0.52';

=head1 NAME

Remedy::Config - Remedy configuration files and logging

=head1 SYNOPSIS

    use Remedy::Config;

    my $file = '/etc/remedy/remedy.conf';
    my $config = Remedy::Config->load ($file);
    
=head1 DESCRIPTION

Remedy::Config encapsulates all of the configuration information for B<Remedy>.

It is implemented as a Perl class that declares and sets the defaults for
various configuration variables and then loads (in order of preference) the
offered filename, the one specified by the REMEDY_CONFIG environment variable,
or F</etc/remedy/config>.  That file should contain any site-specific overrides
to the defaults, and at least some parameters must be set.

This file must be valid Perl.  To set a variable, use the syntax:

    $VARIABLE = <value>;

where VARIABLE is the variable name (always in all-capital letters) and <value>
is the value.  If setting a variable to a string and not a number, you should
normally enclose <value> in C<''>.  For example, to set the variable COMPANY to
C<Stanford>, use:

    $COMPANY = 'Stanford';

Always remember the initial dollar sign (C<$>) and ending semicolon (C<;>).
Those familiar with Perl syntax can of course use the full range of Perl
expressions.

This configuration file should end with the line:

    1;

This ensures that Perl doesn't think there is an error when loading the file.

=cut

##############################################################################
### Declarations 
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Remedy::Log;

my %options = (
    'company'       => '$',
    'config'        => '$',
    'count'         => '$',
    'debug_level'   => '$',
    'domain'        => '$',
    'logfile'       => '$',
    'logfile_level' => '$',
    'log'           => 'Remedy::Log',
    'remedy_host'   => '$',
    'remedy_port'   => '$',
    'remedy_user'   => '$',
    'remedy_pass'   => '$',
    'sub_org'       => '$',
    'username'      => '$',
    'workgroup'     => '$',
    'wrap'          => '$',
);

struct 'Remedy::Config' => {%options};

##############################################################################
### Configuration
##############################################################################

=head1 Configuration

All of the configuration options below have a related B<Class::Struct> accessor
(of type '$' unless noted).

=over 4

=item $REMEDY_HOST, $REMEDY_PORT, $REMEDY_USER, $REMEDY_PASS

Connection details for the primary Remedy server.

Matches the B<remedy_host>, B<remedy_port>, B<remedy_user>, and B<remedy_pass>
accessors.

=cut

our ($REMEDY_HOST, $REMEDY_PORT, $REMEDY_USER, $REMEDY_PASS);

=item $COMPANY, $SUB_ORG, $WORKGROUP

The name of the company and its sub-organization that we will be working with
in Remedy - ie, "Stanford University", "IT Services", "ITS Unix Services"

Matches the B<company>, B<sub_org>, and B<workgroup> accessors.

=cut

our ($COMPANY, $SUB_ORG, $WORKGROUP);

=item $DOMAIN

If set, we will append this to usernames in order to make working email
addresses.

Matches the I<domain> accessor.

=cut

our ($DOMAIN);

=item $CONFIG

The location of the configuration file we're going to load to get defaults.  
Defaults to F</etc/out-of-date/server.conf>; can be overridden either by
passing a different file name to B<load ()>, or by setting the environment 
variable I<REMEDY_CONFIG>.

Matches the B<config> accessor.

=cut

our $CONFIG = '/etc/remedy/config';

=item $DEBUG_LEVEL

Defines how much debugging information to print on user interaction.  Set to
a string, defaults to 'ERROR'.  See B<Remedy::Log> for more details.

=cut

our $DEBUG_LEVEL = $Log::Log4perl::ERROR;

=item $LOGFILE

If set, we will also save additional logs to this file using B<Log::Log4perl>.  

=cut

our $LOGFILE = "";

=item $LOGFILE_LEVEL

Like $DEBUG_LEVEL, but defines the level of log messages we'll print to
I<$LOGFILE>.  Defaults to 3.

=cut

our $LOGFILE_LEVEL = $Log::Log4perl::INFO;

=item $SEARCH_COUNT 

How many entries should we return on a search?  Defaults to 50.

Matches the B<count> accessor.

=cut

our $SEARCH_COUNT = 50;

=item $TEXT_WRAP

When we're printing text, how many characters should we wrap at?  Set to 0 to
not wrap at all.  Default is 80.

Matches the B<wrap> accessor.

=cut

our $TEXT_WRAP = 80;

=back

=cut

##############################################################################
### Subroutines 
##############################################################################

=head1 SUBROUTINES 

As noted above, most subroutines are handled by B<Class::Struct>; please see
its man page for more details about the various sub-functions.

=over 4

=item load ([FILE])

Creates a new B<Remedy::Config> object and loads F<FILE> (or the 
value of the environment variable B<OOD_CONFIG>, or the value of $CONFIG) to
generate its default values.  Returns the new object.

=cut

sub load {
    my ($class, $file) = @_;
    $file ||= $ENV{'REMEDY_CONFIG'} || $CONFIG;
    do $file or LOGDIE ("Couldn't load '$file': " . ($@ || $!) . "\n");
    my $self = $class->new ();

    $self->config ($file);
    _init_options ($self);

    my $log = Remedy::Log->new (
        'name'       => 'Remedy',
        'file'       => $self->logfile,
        'level_file' => $self->logfile_level,
        'level'      => $self->debug_level
    );
    $log->init;

    $self->log ($log);

    $self;
}

sub logger {
    my ($self, $category) = @_;
    return unless $self->log;
    return $self->log->logger ();
}

=back

=cut

##############################################################################
### Internal Subroutines
##############################################################################

### _init_options ()
# takes care of setting the various options.
sub _init_options {
    my ($self) = @_;
    $self->count         ($SEARCH_COUNT);
    $self->company       ($COMPANY);
    $self->debug_level   ($DEBUG_LEVEL);
    $self->domain        ($DOMAIN);
    $self->logfile       ($LOGFILE);
    $self->logfile_level ($LOGFILE_LEVEL);
    $self->remedy_host   ($REMEDY_HOST);
    $self->remedy_pass   ($REMEDY_PASS);
    $self->remedy_port   ($REMEDY_PORT);
    $self->remedy_user   ($REMEDY_USER);
    $self->sub_org       ($SUB_ORG);
    $self->workgroup     ($WORKGROUP);
    $self->wrap          ($TEXT_WRAP);
    $self;
}


##############################################################################
### Final Documentation 
##############################################################################

=head1 ENVIRONMENT

=over 4

=item REMEDY_CONFIG

If this environment variable is set, it is taken to be the path to the remedy
configuration file to load instead of F</etc/remedy/config>.

=back

=cut

=head1 SEE ALSO

Class::Struct(8), Remedy(8), Remedy::Log(8)

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
