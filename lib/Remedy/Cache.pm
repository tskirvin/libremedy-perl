package Remedy::Cache;
our $VERSION = '0.91';
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Cache - manage the caching for Remedy objects

=head1 SYNOPSIS

    use Remedy::Cache;
    my $cache = Remedy::Cache->new ('expiration' => '14 days', 
        'namespace'  => 'my_namespace', 'rootdir' => '/tmp');  

    my $key  = "a key";
    my @data = [1, 2, {3, 4}];
    $cache->set_value ($key, \@data);

    my $results = $cache->get_value ($key);
    # @$results should be the same as @data

=head1 DESCRIPTION

Remedy::Cache is a wrapper for B<Cache::FileCache> that allows for the
storage and retrieval of (semi-)arbitrary data sets.  It is used in several
B<Remedy> modules to store the results of queries.

=cut

##############################################################################
### Public Variables #########################################################
##############################################################################

=head1 PUBLIC VARIABLES

=over 4

=item C<$CACHING>

C<$CACHING> controls whether caching is turned on or off (globally) for Remedy
data reads.  By default, global caching is turned ON; if you want to disable
caching globally, set the value to 0 as follows:

    $Remedy::Cache::CACHING = 0;

Similarly, you can turn it back on by setting the value to 1.

=cut

our $CACHING = 1; 

=item C<$DEFAULT_EXPIRATION_TIME>

Interpreted by B<Cache::FileCache> to decide how long cached data is stored
before we need to re-load it.  Defaults to I<'7 days'>; can be overridden with
the 'expiration' option at object creation.

=cut

our $DEFAULT_EXPIRATION_TIME = '7 days';

=item C<$DEFAULT_NAME_SPACE>

Sets a default name space for caching.  Defaults to 'Remedy_Cache'; this can be
overridden with the 'namespace' option at object creation.

    my $cache = Remedy::Cache ('namespace' => 'my_namespace'); 

=cut

our $DEFAULT_NAME_SPACE = 'Remedy_Cache';

=item C<$DEFAULT_CACHE_ROOT>

Defines the default directory for storing the cache files.  Defaults to
F</tmp>.

Note that we do I<not> verify that the supplied argument is writable or even is
a valid directory; that is up to the caller.  Also note that for this setting
to have any effect, it is important that it is updated I<before> any Remedy
objects are instantiated.

=cut

our $DEFAULT_CACHE_ROOT = "/tmp";

=back

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

## Default values for the constructor.  
our %DEFAULT = (
    'expiration' => $DEFAULT_EXPIRATION_TIME,
    'namespace'  => $DEFAULT_NAME_SPACE,
    'rootdir'    => $DEFAULT_CACHE_ROOT,
);

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Cache::FileCache;
use Class::Struct;
use Remedy::Log;
use Remedy::Utility qw/or_die logger_or_die/;

our @ISA = qw/Remedy::Cache::Struct/;

struct 'Remedy::Cache::Struct' => {
    'cache_object' => 'Cache::FileCache',
    'rootdir'      => '$',
    'expiration'   => '$',
    'logger'       => 'Log::Log4perl::Logger',
    'namespace'    => '$',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

Remedy::Cache is a sub-classed B<Class::Struct> object - that is, it has many
functions that ar ecreated by B<Class::Struct>, but overrides the B<new ()>
function for more fine-grained control.

=head2 Basic Object and B<Class::Struct> Accessors

=over 4

=item new (ARGHASH)

Creates and returns a B<Remedy::Cache> object.  Throws an exception on failure.
Argument hash I<ARGHASH> is used to initialize the underlying B<Class::Struct>
object.

=cut

sub new {
    my ($proto, @rest) = @_;
    my %args = (%DEFAULT, @rest);
    my $class = ref ($proto) || $proto;
    my $self = Remedy::Cache::Struct->new (%args);
    bless $self, $class;

    my $log = $self->logger || Remedy::Log->get_logger;
    my $logger = $self->logger ($log);

    unless ($self->cache_object) {
        my $namespace = $self->namespace;
        my $rootdir   = $self->rootdir;
        my $expire    = $self->expiration;

        $logger->all ("connecting to cache at $rootdir/$namespace");
        my $cache = Cache::FileCache->new ({'namespace' => $namespace,
            'cache_root' => $rootdir, 'default_expires_in' => $expire}) 
            || $logger->logdie ("could not create cache: $@");
        $self->cache_object ($cache)
    }

    return $self;
}

=item cache_object (Cache::FileCache)

Manages the actual B<Cache::FileCache> object.  Defaults to a new object
created based on the information from B<expiration ()> and B<namespace ()>.

=item expiration ($)

Manage the default expiration time for the created cache.  Defaults to
I<$DEFAULT_EXPIRATION_TIME>.  Note that this does not set a new value in an
existing cache object!

Note that this can be any value that Cache::Cache expiration times
recognize. In particular, if set to an integer, then it is understood to be in
seconds.

=item logger (Log::Log4perl::Logger)

Stores a logger, to which we can print status and debugging messages. See
B<Remedy::Log> for details.

=item namespace ($)

Manages the namespace for the cache.  Defaults to C<$DEFAULT_NAME_SPACE>.  Note
that this does not set a new value in an existing cache object!

(Why would you want to change the default namespace? If you are connecting
to different Remedy instances, it makes sense to have the caching for the
two different connections separated in case the two instances had forms with
different schemas.)

=item rootdir ($)

Manages the top-level directory for the cache.  Defaults to
C<$DEFAULT_CACHE_ROOT>.

=back

=cut

##############################################################################
### Global Variable Management ###############################################
##############################################################################

=head2 Global Variable Management

These functions manage the global variables for this object.

=over 4

=item set_default_namespace (NAME)

Sets the default namespace to I<NAME> for for all subsequent Remedy::Cache
objects.

    Remedy::Cache->set_default_namespace ('my_namespace');

=cut

sub set_default_namespace {
    my ($namespace) = @_;
    die "namespace is invalid" if $namespace =~ m/^\s*$/;
    $DEFAULT_NAME_SPACE = $namespace;
    $DEFAULT{'namespace'} = $namespace;
    return $DEFAULT_NAME_SPACE;
}

=back

=cut

##############################################################################
### Caching Functions ########################################################
##############################################################################

=head2 Caching Functions

=over 4

=item get_value (KEY)

Returns the value for I<KEY> out of the cache, or undef if not set (or if
caching is disabled).

=cut

sub get_value {
    my ($self, $cache_key) = @_;
    my $logger = $self->logger_or_die;
    if (!$CACHING) {
        $logger->all ("not CACHING (globally disabled)");
        return;
    }
    if (! defined $cache_key) {
        $logger->logdie ("cannot get a cache value without a cache key");
    }
    my $results_ref  = $self->cache_object->get ($cache_key);
    $logger->all (defined $results_ref ? "cache HIT  ($cache_key)" 
                                       : "cache MISS ($cache_key)");
    return $results_ref;
}

=item set_value (KEY, VALUE)

Sets the cached value of I<KEY> to I<VALUE> (if caching is enabled).  Returns
undef.

=cut

sub set_value {
    my ($self, $cache_key, $results_ref) = @_;
    my $logger = $self->logger_or_die;
    if (!$CACHING) {
        $logger->all ("cache globally disabled");
        return;
    } 
    $logger->all ("setting $cache_key to $results_ref");
    my $rv = $self->cache_object->set ($cache_key, $results_ref);
    return;
}

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 THE CAUSE OF MOST OF YOUR PROBLEMS

Caching can be tricky and when not carefully used can lead to very strange
errors that are difficult to diagnose.

The most common cause of errors when using caching is when you have a cached
value that is out-of-date with its source. If you are every in doubt, clear the
cache.

To do this, you will need to clear the cache periodically.  This will probably
involve asking your sysadmin for help.

=head1 REQUIREMENTS

B<Cache::FileCache>

=head1 SEE ALSO

B<Remedy>

=head1 TODO

B<clear_cache ()> would sure be helpful.

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

Based on B<Stanford::Remedy::Cache> by Adam Lewenberg <adamhl@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University.

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
