package Remedy::Session::Remctl;
our $VERSION = "0.01";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Session::Remctl

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

our $KSTART = "/usr/bin/k5start";

our %DEFAULT = (
    'port' => 0,
);
## What port should we connect to via Net::Remctl?
our $PORT = 0;

##############################################################################
### Declarations #############################################################
##############################################################################

use Remedy::Utility qw/or_die/;

use Class::Struct;
use File::Temp;
use Net::Remctl;

our @ISA = qw/Remedy::Session::Remctl::Struct Remedy::Session/;

struct 'Remedy::Session::Remctl::Struct' => {
    'ctrl'      => 'Net::Remctl',
    'logger'    => 'Log::Log4perl::Logger',
    'port'      => '$',
    'principal' => '$',
    'server'    => '$',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

sub type { 'remctl' }
sub new {
    my ($proto, %args) = @_;
    my $class = ref ($proto) || $proto;
    $args{'port'} ||= $PORT;
    my $self = Remedy::Session::Remctl::Struct->new (%args);
    bless $self, $class;
    return $self;
}

sub connect {
    my ($self) = @_;

    my $remctl = Net::Remctl->new;
    my $server = $self->server;
    my $port   = $self->port;
    my $princ  = $self->principal;
    $remctl->open ($server, $port, $princ)
        or die sprintf ("failed to connect %s to %s: %s\n",
            $princ, "$server:$port", $remctl->error);
    return $self->ctrl ($remctl);
}
sub disconnect {
    my ($self) = @_;
    return $self->ctrl (undef);
}
sub as_string {}

sub make_kerberos_ticket {
    my ($self, %args) = @_;
    my $fn = (caller(0))[3];

  ## ## #   ## ## #   ## ## #   ## ## #   ## ## #   ## ## #
  my $check_existence_of_fref = sub
  {
    my ($parameter) = @_ ;
    if (!$args{$parameter})
    {
      die "[$fn] parameter '$parameter' missing" ;
    }
  } ;
  ## ## #   ## ## #   ## ## #   ## ## #   ## ## #   ## ## #
  $check_existence_of_fref->('PRINCIPAL_PRIMARY') ;
  $check_existence_of_fref->('PRINCIPAL_INSTANCE') ;
  $check_existence_of_fref->('PRINCIPAL_REALM') ;
  $check_existence_of_fref->('KEYTAB_FILE') ;

  my $principal_primary  = $args{PRINCIPAL_PRIMARY} ;
  my $principal_instance = $args{PRINCIPAL_INSTANCE} ;
  my $principal_realm    = $args{PRINCIPAL_REALM} ;
  my $keytab_file        = $args{KEYTAB_FILE} ;

  if (!(-e $keytab_file))
  {
    die "[$fn] keytab file '$keytab_file' not found" ;
  }

  my ($tmp_f, $ticket_location) = File::Temp::tempfile() ;

  $ENV{'KRB5CCNAME'} = "FILE:$ticket_location" ;

    my $cmd = "$KSART -u $principal_primary -i $principal_instance -r $principal_realm "
          . "-f $keytab_file -k $ticket_location" ;
    my $rv = `$cmd`;

    return $ticket_location ;
}


=head2 Subroutines

=over 4

=item error ()

Pulls the value of B<$ARS::ars_errstr>, and returns it (if it is defined) or
the string 'no ars error'.

=back

=cut

sub error {
    return defined $ARS::ars_errstr ? $ARS::ars_errstr : '(no ars error)';
}

=back

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

sub CreateEntry {
    my ($self, $name, $request_id, $fields_aref) = @_;
    my $logger = $self->logger_or_die;
    $logger->debug ("remctl::ars_CreateEntry ($name, $request_id, [...])");
    return remctl_call ('SESSION'  => $self, 'ACTION' => 'CreateEntry',
        'ARG_LIST' => [$name, $request_id, $fields_aref]);
}

sub GetField {
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

    # If we get here, it was a cache miss.
    # Let's time how long it takes to get the value.
    my $start_time = time();
    my $field_properties_ref;

    my $remctl = $session->get_ctrl;
    my $action = 'ars_GetField';

    $field_properties_ref = remctl_call (
        SESSION  => $session,
        ACTION   => $action,
        ARG_LIST => [$name, $fieldId],
    );

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

    # log_info("cache miss ($cache_key) elapsed time ($name): $elapsed_time seconds");

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

    # CASE 1. This is a remctl session.
    if ($session->get_remctl()) {
        my $remctl = $session->get_remctl();
        my $action = 'ars_GetFieldTable';

        my $ars_GetFieldTable_results_href = remctl_call(
                 SESSION  => $session,
                 ACTION   => $action,
                 ARG_LIST => [$name,],
                  );

        %fieldName_to_fieldId = %{ $ars_GetFieldTable_results_href };

    } else {
  # CASE 2. This is a direct session.
        my $ctrl = $session->get_ctrl();
        (%fieldName_to_fieldId = ARS::ars_GetFieldTable ($ctrl, $name))
            || die "ars_GetFieldTable: " . ($ARS::ars_errstr || '(unknown error)')
                                   . " ($ctrl, $name)";
  }

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

    if ($session->get_remctl) {
        my $remctl = $session->get_remctl();
        my $action = 'ars_GetFieldsForSchema';
        my $remctl_results_ref = remctl_call ('SESSION'  => $session,
                                              'ACTION'   => $action,
                                              'ARG_LIST' => [$name]);
        %fieldId_to_field_property = %$remctl_results_ref;
    } else {
        my $ctrl = $session->get_ctrl;

        # First get all the fieldIds.
        my %fieldName_to_fieldId = $session->ars_GetFieldTable ($name, $cache);

        # Loop through all the field ids getting their properties
        foreach my $fieldId (values %fieldName_to_fieldId) {
            my $properties = $session->ars_GetField ($name, $fieldId, $cache);
            $fieldId_to_field_property{$fieldId} = $properties;
        }
    }

    # Save to cache.
    $cache->set_value ($cache_key, \%fieldId_to_field_property);

    return %fieldId_to_field_property;
}

sub SetEntry {
    my ($self, $name, $request_id, $fields_aref) = @_;
    my $logger = $self->logger_or_die;
    $logger->debug ("remctl::ars_SetEntry ($name, $request_id, [...])");
    return remctl_call ('SESSION'  => $self, 'ACTION' => 'SetEntry',
        'ARG_LIST' => [$name, $request_id, $fields_aref]);
}

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Net::Remctl>, B<Remedy::Session>

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
