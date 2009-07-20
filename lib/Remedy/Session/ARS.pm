package Remedy::Session::ARS;
our $VERSION = "0.01";  
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Session::ARS 

=head1 SYNOPSIS

    use Remedy::Session;

    my $session = Remedy::Session->new (
        'server'   => 'r7-app1-dev.stanford.edu',
        'username' => $user,
        'password' => $pass) or die "couldn't create remedy session: $@\n";
    
    eval { $session->connect } or die "error on connect: $@\n";

=head1 DESCRIPTION

Currently (mostly) a wrapper for B<Stanford::Remedy::Session>; please see that
man page for details.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our %DEFAULT = ('tcpport' => 7150 );
            
##############################################################################
### Declarations #############################################################
##############################################################################

use ARS;
use Class::Struct;
use File::Temp;
use Remedy::Utility qw/logger or_die/;

our @ISA = qw/Remedy::Session::ARS::Struct Remedy::Session/;

struct 'Remedy::Session::ARS::Struct' => {
    'authString' => '$',
    'ctrl'       => 'ARS',
    'lang'       => '$',
    'logger'     => 'Log::Log4perl::Logger',
    'password'   => '$',
    'tcpport'    => '$',
    'rpcnumber'  => '$',
    'username'   => '$',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

sub type { 'ARS' }
sub new { 
    my ($proto, %args) = @_;
    my $class = ref ($proto) || $proto;
    my $self = Remedy::Session::ARS::Struct->new (%args, %DEFAULT);
    bless $self, $class;
    return $self;
}

sub connect {
    my ($self) = @_;
    
    my $ctrl = ARS::ars_Login ($self->server, $self->username, $self->password,
        $self->lang, $self->authString, $self->tcpport, $self->rpcnumber)
        or die $self->error;
    return $self->ctrl ($ctrl);
}

sub disconnect {
    my ($self) = @_;
    return 1 unless my $ctrl = $self->ctrl;
    $self->ctrl (undef);
    my $rv = eval { ARS::ars_Logoff ($ctrl) };
    if ($@) { die "error logging off of ARS session: $@\n" }
    $self->ctrl (undef);
    return 1;
}
sub as_string {}

=head2 ARS Wrappers

These functions are meant to offer wrappers for various ARS functions that can
benefit from the local caching.  Instead of the standard I<CTRL> control
object, they take our B<Remedy::Session::Form::Data> object as their first
argument (or, for the clever, you can just invoke it 

=over 4

=item ars_GetField (NAME, FIELDID [, CACHE])

A wrapper around the ARS function ars_GetField. Uses caching to improve
performance. Returns the Field Properties Structure (see the ARS Perl manual
for details).

=cut

sub ars_GetField($$$) {
    my ($session, $name, $fieldId, $cache) = @_;
    $session->or_die ($name, "missing schema name");
    $session->or_die ($fieldId, "missing field ID");
    $session->or_die (ref $session, "missing session");
    $cache ||= Remedy::Session::Cache->new;

    my $fn = (caller(0))[3];

    my $server = $session->get_server_or_die ($fn);
    my $cache_key = $fn . ';' . $name
                        . ';' . $fieldId
                        . ';' . $server;

    if ($cache) {
        my $cache_results_href = $cache->get_value($cache_key);
        if (defined($cache_results_href)) {
            # A cache HIT! We can return the reference
            return $cache_results_href;
        }
    }

    my $ctrl = $session->ctrl;
    $field_properties_ref = ARS::ars_GetField ($ctrl, $name, $fieldId);

    # We extract just those parts we want
    my %results = ();
    $results{'dataType'}   = $field_properties_ref->{'dataType'};
    $results{'fieldId'}    = $field_properties_ref->{'fieldId'};
    $results{'defaultVal'} = $field_properties_ref->{'defaultVal'};
    $results{'option'}     = $field_properties_ref->{'option'};
    $results{'limit'}      = $field_properties_ref->{'limit'};

    # Save to cache.
    $cache->set_value($cache_key, \%results);

    my $end_time = time();
    my $elapsed_time = ($end_time - $start_time);
    
    return \%results;
}

=item ars_GetFieldTable ([CTRL], SCHEMA)

A wrapper around the ARS function ars_GetFieldTable. Uses caching
to improve performance.  Returns a hash mapping field name to field id.

=cut

sub ars_GetFieldTable {
    my ($session, $name, $cache) = @_;
    $session->or_die ($name, "missing schema name");
    $session->or_die (ref $session, "missing session");
    $cache ||= Remedy::Session::Cache->new;

    my $fn = (caller(0))[3];
    my $server = $session->get_server_or_die ($fn);
    my $cache_key = $fn . ';' . $name . ';' . $server;

    my %fieldName_to_fieldId = ();

    if ($cache) {
        my $cache_results_href = $cache->get_value ($cache_key);
        if (defined $cache_results_href) {
            # A cache HIT! We can return the hash.
            %fieldName_to_fieldId = %{ $cache_results_href };
    
            # log_info("Cache hit for schema '$name'");
            return %fieldName_to_fieldId;
        }
    }

    # If we get here, it was a cache miss.
    # Let's time how long it takes to get the value.
    my $start_time = time();

    my $ctrl = $session->get_ctrl();
    (%fieldName_to_fieldId = ARS::ars_GetFieldTable ($ctrl, $name))
        || die "ars_GetFieldTable: " . ($ARS::ars_errstr || '(unknown error)')
                                     . " ($ctrl, $name)";

    # Save to cache.
    $cache->set_value ($cache_key, \%fieldName_to_fieldId) if $cache;

    return %fieldName_to_fieldId;
}

=item ars_GetFieldsForSchema (NAME [, CACHE])

Call ars_GetField for all the fields in a form. Should help performance

Returns a hash mapping fieldId to Field Properties Structure for each
field in the supplied form.

=cut

sub ars_GetFieldsForSchema {
    my ($session, $name, $cache) = @_;
    $session->or_die ($name, "missing schema name");
    $session->or_die (ref $session, "missing session");
    $cache ||= Remedy::Session::Cache->new;

    my $fn = (caller(0))[3];

    my $server = $session->get_server_or_die($fn);
    my $cache_key = join (';', $fn, $name, $server);

    if ($cache) {
        my $cache_results_href = $cache->get_value ($cache_key);
        if (defined ($cache_results_href)) {
            return %$cache_results_href;
        }
    }

    my %fieldId_to_field_property = ();

    my $ctrl = $session->get_ctrl;

    # First get all the fieldIds.
    my %fieldName_to_fieldId = $session->ars_GetFieldTable ($name, $cache);

    # Loop through all the field ids getting their properties
    foreach my $fieldId (values %fieldName_to_fieldId) {
        my $properties = $session->ars_GetField ($name, $fieldId, $cache);
        $fieldId_to_field_property{$fieldId} = $properties;
    }

    # Save to cache.
    $cache->set_value ($cache_key, \%fieldId_to_field_property);

    return %fieldId_to_field_property;
}

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 TODO

Move B<Stanford::Remedy::Session> into here.

=head1 REQUIREMENTS

B<Stanford::Remedy::Session>

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
