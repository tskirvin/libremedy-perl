package Stanford::Remedy::Unix::Config;
our $VERSION = '0.50';
our $ID = q$Id: Config.pm 4666 2008-09-09 22:57:25Z tskirvin $;

=head1 NAME

Stanford::Remedy::Unix::Config - Configuration for Stanford::Remedy

=head1 SYNOPSIS

    use Stanford::Remedy::Unix::Config;

    my $file = '/etc/remedy/remedy.conf';
    my $config = Stanford::Remedy::Unix::Config->load ($file);
    
=head1 DESCRIPTION

Stanford::Remedy::Unix::Config encapsulates all of the configuration information
for B<Stanford::Remedy>.  

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

This ensures that Perl doesn't think there is an error when loading the
file.

=cut

##############################################################################
### Declarations 
##############################################################################

use strict;
use warnings;

use Class::Struct;

struct 'Stanford::Remedy::Unix::Config' => {
    'company'     => '$',
    'config'      => '$',
    'count'       => '$',
    'debug'       => '$',
    'remedy_host' => '$',
    'remedy_port' => '$',
    'remedy_user' => '$',
    'remedy_pass' => '$',
    'logfile'     => '$',
    'loglevel'    => '$',
    'sub_org'     => '$', 
    'username'    => '$',
    'workgroup'   => '$',
    'wrap'        => '$'
};
    
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

=item $COMPANY, $SUB_ORG, $WORKGROUP, $USERNAME

The name of the company and its sub-organization that we will be working with
in Remedy - ie, "Stanford University", "IT Services", "ITS Unix Services", "Tim
Skirvin".  

Matches the B<company>, B<sub_org>, B<workgroup>, and B<username> accessors.

=cut

our ($COMPANY, $SUB_ORG, $WORKGROUP, $USERNAME);

=item $LOGFILE, $LOGLEVEL

Defines how much information to log, and where.  $LOGFILE sets a file where
the logs are archived; defaults to F</var/log/remedy-api.txt>.  $LOGLEVEL sets
an integer value to how much information to store, where 0 is no logging and 9
is maximum logging; defaults to 5.

Matches the B<logfile> and B<loglevel> accessors.

=cut

our $LOGFILE  = "/var/log/remedy-api.txt";
our $LOGLEVEL = 5;

=item $CONFIG

The location of the configuration file we're going to load to get defaults.  
Defaults to F</etc/out-of-date/server.conf>; can be overridden either by
passing a different file name to B<load ()>, or by setting the environment 
variable I<REMEDY_CONFIG>.

Matches the B<config> accessor.

=cut

our $CONFIG = '/etc/remedy/config';

=item $DEBUG

If set, then items created from this configuration object will have their
'debug' mode set.  Defaults to 0.

=cut

our $DEBUG = 0;

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

As noted above, most subroutines are handled by B<Struct::Class>; please see
its man page for more details about the various sub-functions.

=over 4

=item load ([FILE])

Creates a new B<Stanford::Remedy::Unix::Config> object and loads F<FILE> (or the 
value of the environment variable B<OOD_CONFIG>, or the value of $CONFIG) to
generate its default values.  Returns the new object.

=cut

sub load {
    my ($class, $file) = @_;
    $file ||= $ENV{'REMEDY_CONFIG'} || $CONFIG;
    do $file or die ("Couldn't load '$file': " . ($@ || $!) . "\n");

    my $self = $class->new ();

    $self->count       ($SEARCH_COUNT);
    $self->company     ($COMPANY);
    $self->logfile     ($LOGFILE);
    $self->loglevel    ($LOGLEVEL);
    $self->remedy_host ($REMEDY_HOST);
    $self->remedy_pass ($REMEDY_PASS);
    $self->remedy_port ($REMEDY_PORT);
    $self->remedy_user ($REMEDY_USER);
    $self->sub_org     ($SUB_ORG);
    $self->username    ($USERNAME);
    $self->workgroup   ($WORKGROUP);
    $self->wrap        ($TEXT_WRAP);

    $self->config ($file);

    $self;
}

=back

=cut

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

Class::Struct(8), Stanford::Remedy::Unix(8)

=head1 HOMEPAGE

[...]

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
