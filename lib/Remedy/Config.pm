package Remedy::Config;
our $VERSION = '0.57';

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
### Configuration ############################################################
##############################################################################

our %FUNCTIONS;

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
$FUNCTIONS{'remedy_host'} = \$REMEDY_HOST;
$FUNCTIONS{'remedy_port'} = \$REMEDY_PORT;
$FUNCTIONS{'remedy_user'} = \$REMEDY_USER;
$FUNCTIONS{'remedy_pass'} = \$REMEDY_PASS;

=item $COMPANY, $SUB_ORG, $WORKGROUP

The name of the company and its sub-organization that we will be working with
in Remedy - ie, "Stanford University", "IT Services", "ITS Unix Services"

Matches the B<company>, B<sub_org>, and B<workgroup> accessors.

=cut

our ($COMPANY, $SUB_ORG, $WORKGROUP);
$FUNCTIONS{'company'}   = \$COMPANY;
$FUNCTIONS{'sub_org'}   = \$SUB_ORG;
$FUNCTIONS{'workgroup'} = \$WORKGROUP;

=item $DOMAIN

If set, we will append this to usernames in order to make working email
addresses.

Matches the I<domain> accessor.

=cut

our $DOMAIN;
$FUNCTIONS{'domain'} = \$DOMAIN;

=item $HELPDESK

Sets a queue name for where tickets should go when they are "unassigned".  
No default.  Matches the 'helpdesk' accessor.

=cut

our $HELPDESK;
$FUNCTIONS{'helpdesk'} = \$HELPDESK;

=item $REPORT_SOURCE

The value we'll enter into 'Reported Source' when asked.  Defaults to 'Other'.
Matches the 'report_source' accessor.

=cut

our $REPORT_SOURCE = "Other";
$FUNCTION{'report_source'} = \$REPORT_SOURCE;

=item $CONFIG

The location of the configuration file we're going to load to get defaults.
Defaults to F</etc/remedy/config>; can be overridden either by passing a
different file name to B<load ()>, or by setting the environment variable
I<REMEDY_CONFIG>.

Matches the B<config> accessor.

=cut

our $CONFIG = '/etc/remedy/config';
$FUNCTIONS{'config'} = \$CONFIG;

=item $DEBUG_LEVEL

Defines how much debugging information to print on user interaction.  Set to
a string, defaults to I<$Log::Log4perl::ERROR>.  See B<Remedy::Log>.

Matches the I<loglevel> accessor.

=cut

our $DEBUG_LEVEL = $Log::Log4perl::ERROR;
$FUNCTIONS{'loglevel'} = \$DEBUG_LEVEL;

=item $LOGFILE

If set, we will append logs to this file.  See B<Remedy::Log>.

Matches the I<file> accessor.

=cut

our $LOGFILE = "";
$FUNCTIONS{'logfile'} = \$LOGFILE;

=item $LOGFILE_LEVEL

Like I<$DEBUG_LEVEL>, but defines the level of log messages we'll print to
I<$LOGFILE>.  Defaults to I<$Log::Log4perl::INFO>.  See B<Remedy::Log>.

Matches the B<logfile_level> accessor.

=cut

our $LOGFILE_LEVEL = $Log::Log4perl::INFO;
$FUNCTIONS{'loglevel_file'} = \$LOGFILE_LEVEL;

=item $SEARCH_COUNT

How many entries should we return on a search?  Defaults to 50.

Matches the B<count> accessor.

=cut

our $SEARCH_COUNT = 50;
$FUNCTIONS{'count'} = \$SEARCH_COUNT;

=item $TEXT_WRAP

When we're printing text, how many characters should we wrap at?  Set to 0 to
not wrap at all.  Default is 80.

Matches the B<wrap> accessor.

=cut

our $TEXT_WRAP = 80;
$FUNCTIONS{'wrap'} = \$TEXT_WRAP;

=item $CACHE_EXPIRE

How long do we want B<Remedy::Cache> to cache its entries?  
Defaults to I<14 days>.

Matches the B<cache_expire> accessor.

=cut

our $CACHE_EXPIRE    = "14 days";
$FUNCTIONS{'cache_expire'} = \$CACHE_EXPIRE;

=item $CACHE_NAMESPACE

What namespace should we store our cache in?  Defaults to I<cache>.

Matches the B<cache_namespace> accessor.

=cut

our $CACHE_NAMESPACE = "cache";
$FUNCTIONS{'cache_namespace'} = \$CACHE_NAMESPACE;

=item $CACHE_ROOT

What is the top-level of our cache?  Defaults to F</tmp>.  

Matches the B<cache_root> accessor.

=cut

our $CACHE_ROOT = "/var/lib/remedy";
$FUNCTIONS{'cache_root'} = \$CACHE_ROOT;

=back

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Remedy::Log;
use Remedy::Cache;

my %opts;
foreach (keys %FUNCTIONS) { $opts{$_} = '$' }

struct 'Remedy::Config' => { 
    'log'   => 'Remedy::Log',
    'cache' => 'Remedy::Cache',
    %opts, 
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 Subroutines

=head2 B<Class::Struct> Accessors

The accessors listed in CONFIGURATION can be initialized via B<new ()> or
per-function.

=over 4

=item cache (Remedy::Cache)

=item cache_namespace ($)

=item cache_expire ($)

=item cache_root ($)

=item company ($)

=item config ($)

=item count ($)

=item domain ($)

=item helpdesk ($)

=item log (Remedy::Log)

=item logfile ($)

=item loglevel ($)

=item loglevel_file ($)

=item remedy_host ($)

=item remedy_pass ($)

=item remedy_port ($)

=item remedy_user ($)

=item sub_org ($)

=item workgroup ($)

=item wrap ($)

=back

=head2 Additional Functions

=over 4

=item load ([FILE])

Creates a new B<Remedy::Config> object, loads F<FILE> to update defaults, (if
not offered, the value of the environment variable I<REMEDY_CONFIG> or the value
of I<$CONFIG>), and initalizes the object from the defaults.  This includes
creating the B<Remedy::Log> object.

Returns the new object.

=cut

sub load {
    my ($class, $file) = @_;
    $file ||= $ENV{'REMEDY_CONFIG'} || $CONFIG;
    do $file or die "Couldn't load '$file': " . ($@ || $!) . "\n";
    my $self = $class->new ();

    $self->config ($file);
    _init_functions ($self);

    my $log = Remedy::Log->new (
        'file'       => $self->logfile,
        'level'      => $self->loglevel,
        'level_file' => $self->loglevel_file,
    );
    $log->init;
    $self->log ($log);

    my $cache = Remedy::Cache->new (
        'expiration' => $self->cache_expire,
        'namespace'  => $self->cache_namespace,
        'rootdir'    => $self->cache_root,
    );
    $self->cache ($cache);

    $self;
}

=item debug ()

Return a string with all valid keys and values listed.

=cut

sub debug {
    my ($self) = @_;
    my @return;
    foreach my $key (keys %FUNCTIONS) { 
        my $value = $self->$key;
        push @return, sprintf ("%s: %s", $key, defined $value ? $value 
                                                              : '*undef*');
    }
    wantarray ? @return : join ("\n", @return, '');
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

### _init_functions ()
# Takes care of setting the various options.  
sub _init_functions {
    my ($self) = @_;
    foreach my $key (keys %FUNCTIONS) { 
        my $value = $FUNCTIONS{$key};
        $self->$key ($$value) 
    }
    $self;
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 ENVIRONMENT

=over 4

=item REMEDY_CONFIG

If this environment variable is set, it is taken to be the path to the remedy
configuration file to load instead of F</etc/remedy/config>.

=back

=cut

=head1 REQUIREMENTS

B<Remedy::Log>, B<Remedy::Cache>

=head1 SEE ALSO

Class::Struct(8), Remedy(8)

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
