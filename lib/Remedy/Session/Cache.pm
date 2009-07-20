package Remedy::Session::Cache;
our $VERSION = '0.03';
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Cache - manage the caching for Remedy objects

=head1 VERSION

Version 0.03

=head1 SYNOPSIS

    use Remedy::Cache;
    my $cache = Remedy::Cache->new (
        'expiration' => '14 days', 
        'namespace'  => 'my_namespace');  

=head1 DESCRIPTION

Typically, the operation that takes the most time to complete is the
execution of a large SELECT query.  In particular, the population of a
B<Remedy::FormData> object (which contains the structure of a Remedy form) can
take a long time to complete.

The function C<ars_GetFieldsForSchema> in Remedy::Session::FormData does the
querying and returns the results.  As a Remedy form's structures changes only
infrequently, it makes sense to do employ caching.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

=head1 GLOBAL DEFAULTS

=over 4

=item C<$CACHING>

C<$CACHING> controls whether caching is turned on or off (globally) for Remedy
data reads.  By default, global caching is turned ON; if you want to disable
caching globally, use C<turn_global_caching_off()>.  If you want to disable
caching globally, set this value to 0 as follows:

    $Remedy::Cache::CACHING = 0;

Similarly, you can turn it back on: 

    $Remedy::Cache::CACHING = 1;

=cut

our $CACHING = 1; 

=item C<$DEFAULT_EXPIRATION_TIME>

Interpreted by B<Cache::FileCache> to decide how long cached data is stored
before we need to re-load it.  Defaults to C<'14 days'>; can be overridden with
the 'expiration' option at object creation.

=cut

our $DEFAULT_EXPIRATION_TIME = '14 days';

=item C<$DEFAULT_NAME_SPACE>

Sets a default name space for caching.  Defaults to 'Remedy_Cache'; this can be
overridden with the 'namespace' option at object creation, or by setting a new
default namespace with C<set_default_namespace()>. For example,

    my $cache = Remedy::Cache ('namespace' => 'my_namespace'); 

=cut

our $DEFAULT_NAME_SPACE = 'Remedy_Cache';

=item C<$DEFAULT_CACHE_ROOT>

Sets the default directory for storing the cache files. We set it to
C<undef> so that the caching module picks its own default, but we want the
user to be able to override this setting.  The user does this with the
C<set_default_cache_root ()> method.

=cut

our $DEFAULT_CACHE_ROOT = undef; 

## If set, display caching results on STDERR.
my $DEBUG = 0; 

=back

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Cache::FileCache;
use Class::Struct;
use Remedy::Log;
use Remedy::Utility qw/or_die/;

our @ISA = qw/Remedy::Session::Cache::Struct/;

struct 'Remedy::Session::Cache::Struct' => {
    'cache_object' => 'Cache::FileCache',
    'debug'        => '$',
    'expiration'   => '$',
    'logger'       => 'Log::Log4perl::Logger',
    'namespace'    => '$',
};

##############################################################################
### Methods ##################################################################
##############################################################################

=head1 METHODS

=head2 Creation and Object Variables

=over 4

=item new (ARGHASH)

Creates and returns a B<Remedy::Cache> object. 
Throws an exception on failure.
C<ARGHASH> allows
overrides of the system defaults, specifically:

=over 4

=item expiration I<expiration time>

Defaults to C<$DEFAULT_EXPIRATION_TIME>. This can be any value that
Cache::Cache expiration times recognize. In particular, if set to an
integer, then it is understood to be in seconds. 

=item namespace I<namespace>

Defaults to C<$DEFAULT_NAME_SPACE>.

=item cache_object C<Cache::FileCache>

The actual cache object.  Defaults to a new object created based on the
information from I<expiration time> and I<namespace>.

=back

=cut

sub new {
    my ($proto, %args) = @_;
    my $class = ref ($proto) || $proto;

    $args{'namespace'}  ||= $DEFAULT_NAME_SPACE;
    $args{'expiration'} ||= $DEFAULT_EXPIRATION_TIME;
    my $self = Remedy::Session::Cache::Struct->new (%args);

    $self->cache_object ($args{'cache_object'} || 
        Cache::FileCache->new ({'namespace'          => $self->namespace, 
                                'default_expires_in' => $self->expiration}));

    my $log = $self->logger || Remedy::Log->get_logger;
    my $logger = $self->logger ($log);

    bless $self, $class;

    # If $DEFAULT_CACHE_ROOT is not empty set the cache root on the
    # Cache::FileCache object.  
    if ($DEFAULT_CACHE_ROOT) {
        my $filecache = $self->get_cache_object ();
        $filecache->set_cache_root ($DEFAULT_CACHE_ROOT); 
    }

    return $self;
}

=item get_cache_object ()

=item set_cache_object (VALUE)

Gets or sets the B<Cache::FileCache> object associated with the object.  

=cut

sub get_cache_object { shift->cache_object () }
sub set_cache_object { shift->cache_object (@_) }
# cache_object () comes from Class::Struct

=item get_expiration ()

=item set_expiration (VALUE)

Gets or sets the initially-set expiration time for cache.  Note that this does
not set a new value in an existing cache object!

=cut

sub get_expiration   { shift->expiration () }
sub set_expiration   { shift->expiration (@_) }
# expiration () comes from Class::Struct

=item get_namespace ()

=item set_namespace (VALUE)

Gets or set the namespace for the cache.  Note that this does not set a new
value in an existing cache object!

(Why would you want to change the default namespace? If you are connecting
to different Remedy instances, it makes sense to have the caching for the
two different connections separated in case the two instances had forms with
different schemas.)

=cut

sub get_namespace    { shift->namespace }
sub set_namespace    { shift->namespace (@_) }
# namespace () comes from Class::Struct

=back

=head2 Global Variable Management

These functions manage the global variables for this object.

=over 4

=item turn_global_caching_off ()

=item turn_global_caching_on ()

As described above, turns caching off or on globally.

=cut

sub turn_global_caching_off {
    $CACHING = 0;
    shift->logger_or_die->info ("turning global caching OFF");
    return $CACHING;
}

sub turn_global_caching_on {
    $CACHING = 1;
    shift->logger_or_die->info ("turning global caching ON");
    return $CACHING;
}


=item set_default_cache_root (DIR)

Sets I<$DEFAULT_CACHE_ROOT>.  For example, to set it to I</var/cache/remedy/>:

    Remedy::Cache::set_default_cache_root ('/var/cache/remedy/');

This function does I<not> verify that the supplied argument is writable or even
is a valid directory; that is up to the caller.  Note that for this setting to
have any effect, it is important that it is used I<before> any Stanford::Form
objects (such as Incidents, WorkLogs, Associations, etc.) are instantiated.

The function returns C<$DEFAULT_CACHE_ROOT>.

=cut

sub set_default_cache_root {
    my ($directory) = @_; 
    $DEFAULT_CACHE_ROOT = $directory;
    return $DEFAULT_CACHE_ROOT;
}

=item set_default_namespace (NAME)

Sets the default namespace to I<NAME> for for all subsequent Remedy::Cache
objects.

    Remedy::Cache->set_default_namespace('my_namespace');
    # From now on, all new Remedy::Cache objects created 
    # will use 'my_namespace' as their namepsace.

Why would you want to change the default namespace? If you are connecting
to different Remedy instances, it makes sense to have the caching for
the two different connections separated in case the two instances had
forms with different schemas.

=cut

sub set_default_namespace {
    my ($namespace) = @_;
    my $fn = 'set_default_namespace';
    die "namespace is invalid" if $namespace =~ m/^\s*$/;
    $DEFAULT_NAME_SPACE = $namespace;
    return $DEFAULT_NAME_SPACE;
}

=back

=head2 Caching Functions

=over 4

=item set_value (KEY, VALUE)

Sets the cached value of I<KEY> to I<VALUE> (if caching is enabled).  Returns
1.  

=cut

sub set_value {
    my ($self, $cache_key, $results_ref) = @_;
    my $logger = $self->logger_or_die;

    if (!$CACHING) {
        $logger->debug ("not CACHING (globally disabled)");
        return 1;
    }

    my $rv = $self->cache_object->set ($cache_key, $results_ref);

    return 1;
}


=item get_value (KEY)

Returns the value for I<KEY> out of the cache, or undef if not set (or if
caching is disabled).

If debugging is turned on, writes 'CACHE HIT' or 'CACHE MISS' to STDERR as
appropriate.

=cut

sub get_value {
    my ($self, $cache_key) = @_;
    my $logger = $self->logger_or_die;
    
    my $fn = (caller (0))[3];

    if (!$CACHING) {
        $logger->debug ("not CACHING (globally disabled)");
        return;
    }

    if (!defined $cache_key) {
        die "[$fn] cannot get a cache value without a cache key";
    }

    my $results_ref  = $self->cache_object->get ($cache_key);
    $logger->debug (defined $results_ref ? "CACHE HIT" : "CACHE MISS");
    return $results_ref;
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub logger_or_die   { $_[0]->or_die (shift->logger,  "no logger",  @_) }

1;

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 THE CAUSE OF MOST OF YOUR PROBLEMS

Caching can be tricky and when not carefully used can lead to very strange
errors that are difficult to diagnose.

The most common cause of errors when using caching is when you have a cached
value that is out-of-date with its source. If you are every in doubt, clear the
cache.

To do this, call the function C<clear_cache> described below.  Note that this
clears the cache on the server you run it on. If you are accessing Remedy via
a remctl service on another server, you will have to tell the administrator of
that server to clear the cache there.

=head1 REQUIREMENTS

B<Cache::FileCache>

=head1 SEE ALSO

B<Remedy>

=head1 TODO

Write the C<clear_cache> function.

Open release (need a license).

Have the Class::Struct functions actually override the current value 
in the B<Cache::FileCache> object?

Make some of the global variables less-global?

=head1 AUTHOR

Adam Lewenberg, <adamhl at stanford.edu>

Reformatted somewhat by Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University.

All rights reserved.

=cut
