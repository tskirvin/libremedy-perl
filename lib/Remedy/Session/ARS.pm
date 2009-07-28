package Remedy::Session::ARS;
our $VERSION = "0.90";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Session::ARS - direct API connection to the Remedy database

=head1 SYNOPSIS

    use Remedy::Session::ARS;

    my $session = Remedy::Session::ARS->new (
        'server'   => 'r7-app1-dev.stanford.edu',
        'username' => $user,
        'password' => $pass) or die "couldn't create remedy session: $@\n";

    eval { $session->connect } or die "error on connect: $@\n";

    my @return = $session->read ('CTM:Support Group', '1=1', [1,2,3,4,5]);
    while (@return) {
        my ($id, $value) = (shift @return, shift @return);
        # these then get converted into objects within Remedy::Form
    }

=head1 DESCRIPTION

Remedy::Session::ARS is a sub-class of B<Remedy::Session> that connects the 
B<Remedy> and B<ARS> modules.  It provides a number of query functions that
wrap the core B<ARS::ars_*> family of functions.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our %DEFAULT = (
    'authstring' => '',
    'lang'       => '',
    'rpcnumber'  => 0,
    'tcpport'    => 7150,
);

our %DEFAULT_READ = (
    'max'       => 0,
    'first'     => 0,
    'match'     => [],
    'sort_ID'    => 1,
    'sort_dir'  => 1,
);

##############################################################################
### Declarations #############################################################
##############################################################################

use ARS;
use Class::Struct;
use Remedy::Utility qw/logger_or_die or_die/;

use strict;
use warnings;

our @ISA = qw/Remedy::Session::ARS::Struct Remedy::Session/;

struct 'Remedy::Session::ARS::Struct' => {
    'authstring' => '$',
    'ctrl'       => '$',
    'lang'       => '$',
    'logger'     => 'Log::Log4perl::Logger',
    'password'   => '$',
    'server'     => '$',
    'rpcnumber'  => '$',
    'tcpport'    => '$',
    'username'   => '$',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

Remedy::Session::ARS is a sub-classed B<Class::Struct> object - that is, it has
many functions that ar ecreated by B<Class::Struct>, but overrides the B<new
()> function for more fine-grained control.

=head2 Basic Object and B<Class::Struct> Accessors

=over 4

=item new (ARGHASH)

Creates and returns the new object.  I<ARGHASH> is used to initialize the
underlying B<Class::Struct> object.  

Returns the object on success, dies on failure.

=cut

sub new {
    my ($proto, @rest) = @_;
    my %args = (%DEFAULT, @rest);
    my $self = Remedy::Session::ARS::Struct->new (%args);
    bless $self, ref $proto || $proto;
    return $self;
}

=item authstring ($)

Something to do with the Windows Domain.  No default.

=item ctrl (ARControlStructPtr)

The actual connection to the ARS database.  Created and populated by
B<connect ()>, closed by B<disconnect ()>.

=item lang ($)

Language for the ARS connection.  No default.

=item logger (Log::Log4perl::Logger)

Used for debugging and status messages.  If not offered at initialization, we
will try to pull the logger using B<Remedy::Log-E<gt>logger>.

=item password ($)

Password for the user account.  No default.

=item server ($)

Name of the Remedy server.  No default.  Required.

=item rpcnumber ($)

RPC number for the connection.  Defaults to 0.

=item tcpport ($)

Port that the Remedy server is listening on.  Defaults to 7150.

=item username ($)

Username for the connection.  No default.  Required.

=back

=cut

##############################################################################
### ARS Wrappers #############################################################
##############################################################################

=head2 ARS Wrappers

These functions are meant to offer wrappers for various ARS functions that
can benefit from the local caching.  Instead of the standard I<CTRL> control
object, they take our B<Remedy::Session::ARS> object as their first argument.

=over 4

=item connect ()

Creates the ARS connection and saves a reference to it B<ctrl>.  Returns the
connection reference on success, dies on failure.  Just returns the existing
connection if we are already connected.

Wraps B<ARS::ars_Login ()>.  

=cut

sub connect {
    my ($self) = @_;
    return $self->ctrl if $self->ctrl;
    die "no server\n"   unless my $server = $self->server;
    die "no username\n" unless my $user = $self->username;

    $self->logger_or_die->debug ("ARS::ars_Login ($server, $user, [...])");
    my $ctrl = ARS::ars_Login ($server, $user, $self->password, $self->lang,
        $self->authstring, $self->tcpport, $self->rpcnumber);
    die $self->error unless $ctrl;

    return $self->ctrl ($ctrl);
}

=item CreateEntry (NAME, FIELDS_AREF)

Creates a new entry in the database.  I<NAME> is the name of the form/table
that we're working with; and I<FIELDS_AREF> is an array reference that contains
(ID, VALUE) pairs corresponding to the numeric field ID/value pairs that should
be saved in the database.

Wraps B<ARS::ars_CreateEntry ()>.

=cut

sub CreateEntry ($$) {
    my ($self, $name, $fields_aref) = @_;
    my $logger = $self->logger_or_die;
    my $ctrl   = $self->ctrl_or_die;
    
    $logger->logdie ("FIELDS_AREF is not a reference") unless ref $fields_aref;
    my @fields = @$fields_aref;

    $logger->all ("ARS::ars_CreateEntry ($name, @fields [...])");
    my $request_id = ARS::ars_CreateEntry ($ctrl, $name, @fields);
    if (! defined $request_id) {
        $logger->logdie ("ars_CreateEntry failed: " . $self->error . "\n");
    } elsif (! $request_id) {
        $logger->warn ("item was created but we don't know where");
        return '';
    }

    return $request_id;
}

=item disconnect ()

Disconnects the ARS connection, and deletes the value saved in B<ctrl>.
Returns 1 on success.  If we're already disconnected, we just return 1.

Wraps B<ARS::ars_Logoff ()>.

=cut

sub disconnect {
    my ($self) = @_;
    return 1 unless my $ctrl = $self->ctrl;
    my $rv = eval { ARS::ars_Logoff ($ctrl) };
    if ($@) { die "error logging off of ARS session: $@\n" }
    $self->ctrl (undef);
    return 1;
}

=item error ()

Pulls the value of B<$ARS::ars_errstr>, and returns it (if it is defined) or
the string 'no ars error'.

=cut

sub error {
    return defined $ARS::ars_errstr ? $ARS::ars_errstr : '(no ars error)';
}

=item GetField (NAME, FIELDID [, CACHE])

A wrapper around the ARS function ars_GetField. Uses caching to improve
performance. Returns the Field Properties Structure (see the ARS Perl manual
for details).

Wraps B<ARS::ars_getField ()>.

=cut

sub GetField ($$$) {
    my ($session, $name, $fieldId, $cache) = @_;
    my $logger = $session->logger_or_die;
    $session->or_die ($name, "missing schema name");
    $session->or_die ($fieldId, "missing field ID");
    $session->or_die (ref $session, "missing session");

    my $cache_key = $session->cache_key ($name, $fieldId) if $cache;
    if ($cache_key) {
        my $results = $cache->get_value ($cache_key);
        return %$results if defined $results && ref $results;
    }

    ## Actually do the ARS work
    my $ctrl = $session->ctrl_or_die;
    $logger->all ("ARS::ars_GetField (CTRL, $name, $fieldId)");
    my $properties = ARS::ars_GetField ($ctrl, $name, $fieldId);

    # We extract just those parts we want
    my %results = (
        'dataType'   => $properties->{'dataType'},
        'fieldId'    => $properties->{'fieldId'},
        'defaultVal' => $properties->{'defaultVal'},
        'option'     => $properties->{'option'},
        'limit'      => $properties->{'limit'},
    );

    ## Update the cache, if possible
    $cache->set_value ($cache_key, \%results) if $cache_key;

    return \%results;
}

=item GetFieldsForSchema (NAME [, CACHE])

Call GetField for all the fields in a form. Should help performance

Returns a hash mapping fieldId to Field Properties Structure for each
field in the supplied form.

=cut

sub GetFieldsForSchema {
    my ($session, $name, $cache) = @_;
    $session->or_die ($name, "missing schema name");
    $session->or_die (ref $session, "missing session");

    ## Check the cache, if offered
    my $cache_key = $session->cache_key ($name, 'gffs') if $cache;
    if ($cache_key) {
        my $results = $cache->get_value ($cache_key);
        return %$results if defined $results && ref $results;
    }

    ## Get the fieldIds
    my %name_to_id = $session->GetFieldTable ($name, $cache);

    # Loop through all the field ids getting their properties
    my %id_to_prop = ();
    foreach my $fieldId (values %name_to_id) {
        my $properties = $session->GetField ($name, $fieldId, $cache);
        $id_to_prop{$fieldId} = $properties;
    }

    $cache->set_value ($cache_key, \%id_to_prop) if $cache_key;

    return %id_to_prop;
}

=item GetFieldTable (NAME [, CACHE])

A wrapper around the ARS function ars_GetFieldTable. Uses caching
to improve performance.  Returns a hash mapping field name to field id.

Wraps B<ARS::ars_GetFieldTable ()>.

=cut

sub GetFieldTable ($$) {
    my ($session, $name, $cache) = @_;
    my $logger = $session->logger_or_die;
    $session->or_die ($name, "missing schema name");
    $session->or_die (ref $session, "missing session");

    ## Check the cache, if offered
    my $cache_key = $session->cache_key ($name, 'gft') if $cache;
    if ($cache_key) {
        my $results = $cache->get_value ($cache_key);
        return %$results if defined $results && ref $results;
    }

    ## Actually do the ARS work
    my $ctrl = $session->ctrl_or_die;
    $logger->all ("ARS::ars_GetFieldTable (CTRL, $name)");
    my %fieldName_to_fieldId = ARS::ars_GetFieldTable ($ctrl, $name);
    $logger->logdie (sprintf ("%s: %s (%s, %s)", "ars_GetFieldTable",
        $session->error, $ctrl, $name)) unless scalar %fieldName_to_fieldId;

    ## Update the cache, if possible
    $cache->set_value ($cache_key, \%fieldName_to_fieldId) if $cache;

    return %fieldName_to_fieldId;
}

=item read (ARGHASH)

Read entries from the Remedy database.  Takes the following arguments through
I<ARGHASH>:

=over 2

=item first (INT)

The first entry to retrieve.  Defaults to 0, which means "the first one".

=item limit (ARRAYREF)

Limits which fields we want to retrieve.  If not offered, we offer an empty
array (which means that the database decides how much information to give us).

=item max (INT)

The maximum number of entries to return.  Defaults to 0, which means "all".

=item schema (STRING)

The name of the form/table that we're working with.  Required.

=item sort_dir (0|1)

The direction of the sorting.

=item sort_ID (ID)

The field ID by which the entries will be sorted.  Defaults to field 1 (the
reuqest ID field)

=item where (STRING)

A pre-formatted query (roughly equivalent to the "WHERE" field of a SQL query).
Required.

=back

Returns an array of I<ID>, I<FIELD_VALUE_HASH> pairs, which together correspond
to a item returned.  If there are no results, we'll check for an error; and if
there is an error, we will die.

Wraps B<ARS::ars_LoadQualifier ()> and B<ARS::ars_GetListEntryWithFields ()>.

=cut

sub read {
    my ($self, @rest) = @_;
    my %args = (%DEFAULT_READ, @rest);
    my $logger = $self->logger_or_die;
    my $ctrl   = $self->ctrl_or_die;

    my $name  = $args{'schema'} || $logger->logdie ('no schema offered');
    my $where = $args{'where'}  || $logger->logdie ('no where offered');
    my $limit = $args{'limit'}  || [];

    ## Create the "qualifier string" from the where clause.
    $logger->all ("ARS::ars_LoadQualifier ($name, $where)");
    my $qualifier = ARS::ars_LoadQualifier ($ctrl, $name, $where);
    if (! defined $qualifier) {
        $logger->logdie ("ars_LoadQualifier error: " . $self->error);
    }

    my $debug = join (', ', $name, "{LQ}", $args{'max'}, $args{'first'}, 
        '[' . scalar @$limit . ' IDs]', $args{'sort_ID'}, $args{'sort_dir'});

    ## Do the query (sort according to entryID)
    $logger->all ("ARS::ars_GLEWF ($debug)");
    my @results = ARS::ars_GetListEntryWithFields ($ctrl, $name,
        $qualifier, $args{'max'}, $args{'first'}, $limit, $args{'sort_ID'}, 
        $args{'sort_dir'});

    ## If we got no results, see if there's an error
    if (!@results && $ARS::ars_errstr) {
        $logger->logdie ("no matches; error " . $self->error);
    }

    return @results;
}

=item SetEntry (NAME, REQUEST_ID, FIELDS_AREF)

Modifies an existing entry in the database.  I<NAME> is the name of the
form/table that we're working with; I<REQUEST_ID> is the value of Field 1 that
corresponds to an existing entry in that form; and I<FIELDS_AREF> is an array
reference that contains pairs of entries corresponding to the field/value pairs
that should be saved in the database.

Wraps B<ARS::ars_SetEntry ()>.
    
=cut

sub SetEntry ($$$) {
    my ($self, $name, $request_id, $fields_aref) = @_;
    my $logger = $self->logger_or_die;
    my $ctrl   = $self->ctrl_or_die;
    
    my @fields = @$fields_aref; 

    $logger->debug ("ARS::ars_SetEntry ($name, $request_id, [...])");
    unless (ARS::ars_SetEntry ($ctrl, $name, $request_id, 0, @fields)) {
        $logger->logdie ("ARS::ars_SetEntry failed: $ARS::ars_errstr\n");
    }   
    $logger->debug ('SetEntry end');
            
    return 1;
}       

=back

=cut

##############################################################################
### Miscellaneous ############################################################
##############################################################################

=head2 Miscellaneous Functions

=over 4

=item as_string ()

Returns a string that contains all of the basic information about the object.

=cut

sub as_string {
    my ($self) = @_;
    my $connected = $self->ctrl ? "connected" : "not connected";

    my $format = "%-25s %s";

    my @return;
    push @return, sprintf ($format, "Connection Type", "ARS ($connected)");
    push @return, sprintf ($format, "Server",     $self->server     || '??');
    push @return, sprintf ($format, "TCP Port",   $self->tcpport    || '??');
    push @return, sprintf ($format, "Username",   $self->username   || '??');
    push @return, sprintf ($format, "Password",   "(not shown)");
    push @return, sprintf ($format, "RPC Number", $self->rpcnumber  || '??');
    push @return, sprintf ($format, "Language",   $self->lang       || '??');
    push @return, sprintf ($format, "AuthString", $self->authstring || '??');
    
    return join ("\n", @return, '');
}

=item cache_key (FORM, KEY)

Creates a key to the B<Remedy::Cache> cache for use with the various functions
that take advantage of caching.  This key takes the form of:

    FUNCTION:FORM:KEY:SERVER

=cut

sub cache_key ($$) { 
    my ($self, $form, $key) = @_;
    return join (';', (caller (1))[3], $form, $key, $self->server_or_die);
}

=item ctrl_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<ctrl ()>.

=cut

sub ctrl_or_die { $_[0]->or_die (shift->ctrl, "no ctrl", @_) }

=item server_or_die  ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<server ()>.

=cut

sub server_or_die { $_[0]->or_die (shift->server, "no server", @_) }

=item type ()

Just returns 'ARS'.

=cut

sub type { 'ARS' }

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 TODO

B<ctrl ()> actually just contains a scalar, and we don't check what's put into
it.  This is because there's no way to delete an object out of the item as it
stands.  This is annoying, and will probably involve abandoning
B<Class::Struct> to fix.

=head1 REQUIREMENTS

B<ARS>, B<Remedy::Session>

=head1 SEE ALSO

Remedy(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
