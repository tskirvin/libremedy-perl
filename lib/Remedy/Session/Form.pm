package Remedy::Session::Form;
our $VERSION = "0.01";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Session

=head1 SYNOPSIS

    use Remedy::Session::Form;

=head1 DESCRIPTION

Currently just a wrapper for B<Stanford::Remedy::Form>; please see that man
page for details.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

## Used with get_formdata
our %FORM_CACHE = ();

##############################################################################
### Declarations #############################################################
##############################################################################

use warnings;
use strict;

use Class::Struct;
use Date::Parse qw/str2time/;
use Remedy::Log;
use Remedy::Session::Cache;
use Remedy::Session::Form::Data;
use Remedy::Utility qw/or_die/;
use Stanford::Remedy::Form;         # hoping to kill this off shortly

# our @ISA = qw/Remedy::Form::Struct/;
our @ISA = qw/Remedy::Session::Form::Struct Stanford::Remedy::Form/;

struct 'Remedy::Session::Form::Struct' => {
    'cache'       => 'Remedy::Session::Cache',
    'fields_only' => '%',
    'formdata'    => 'Remedy::Session::Form::Data',
    'logger'      => 'Log::Log4perl::Logger',
    'name'        => '$',
    'populated'   => '$',
    'session'     => 'Remedy::Session',
    'select_qry'  => '$',
    'select_res'  => '@',
    'values'      => '%',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head2 Subroutines

This module overrides several subroutines, and adds several others.

=over 4

=item new (ARGHASH)


=cut

sub new {
    my ($proto, %args) = @_;
    my $class = ref $proto || $proto;
    my $self = Remedy::Session::Form::Struct->new (%args);
    bless $self, $class;

    return unless $self->name;
    return unless $self->session;

    ## Get the logger
    my $log = $self->logger || Remedy::Log->get_logger;
    my $logger = $self->logger ($log);

    my $values = $args{'values_href'} || {};
    $self->values ($values);

    my $only   = $args{'only_these_fieldNames_href'} || {};
    $self->fields_only (%$only);

    $self->select_qry ($args{'select_qry'} || undef);

    my $results = $args{'select_qry_results'} || [];
    $self->select_res (@$results);

    # if ($args{'caching_enabled'}) {
        $self->cache (Remedy::Session::Cache->new);
    # }

    $self->populate if $self->session;

    return $self;
}


sub get_formdata {
    my ($self) = @_;
    my $name    = $self->name_or_die;
    my $session = $self->get_session;

    if (!(exists $FORM_CACHE{$name}) && $session) {
        # my $formdata = Stanford::Remedy::FormData->new (
        my $formdata = Remedy::Session::Form::Data->new (
            'name'    => $name,
            'session' => $session,
            'cache'   => $self->cache,
            'logger'  => $self->logger_or_die,
        );
        $FORM_CACHE{$name} = $formdata;
    }
    return $FORM_CACHE{$name};
}

=item insert ()

=cut

sub insert {
    my ($self) = @_;
    my $logger = $self->logger_or_die;

    # The Remedy Perl API wants all the fields to be saved in an array in
    # (field_id, value) pairs. So, we need to traverse all the nonempty
    # fields and populate an array.
    my $formdata = $self->formdata_or_die;
    my $values   = $self->get_values_href;

    my @fields = ();
    foreach my $name (keys %{$values}) {
        my $id = $self->name_to_id ($name);
        my $value = $$values{$name};
        next unless $id;
        push @fields, $id, $value;
    }
    return unless scalar @fields;

    my $req_id = eval { $self->CreateEntry (\@fields) };
    $logger->logdie ("failed to create a new request: $@") unless $req_id;

    # Now _read_ the incident from the Remedy system. Why?  Workflow has set
    # many values in the object that we didn't set on our own.
    $self->set_request_id ($req_id);
    unless (my $rid = $self->read_into) {
        $logger->logdie ("could not re-read object into self: $@");
    }

    # Return the request id.
    return $req_id;
}

sub update {
    my ($self) = @_;
    my $logger = $self->logger_or_die;

    my $req_id = $self->get_request_id;
    $logger->logdie ('cannot insert without request ID') unless $req_id;

    my $formdata = $self->formdata_or_die;
    my $values   = $self->get_values_href;

    my @fields = ();
    foreach my $name ($self->fields_to_match) {
        my $id = $self->name_to_id ($name);
        next unless $id;
        push (@fields, $id, $values->{$name});
    }
    return unless scalar @fields;

    my $rv = eval { $self->SetEntry ($req_id, \@fields) };
    $logger->logdie ("failed to update existing entry: $@") unless $rv;

    # Re-read to make sure all of the workflow has fired.
    unless (my $rid = $self->read_into) {
        $logger->logdie ("could not re-read object into self: $@");
    }

    return $rv;
}

=item save ()

Saves out the item.  This is basically a wrapper function - if we have a set
request ID, then we'll use B<update (), if we don't then we'll use B<insert
()>.

=cut

sub save {
    my ($self, @args) = @_;
    return $self->get_request_id ? $self->update (@args)
                                 : $self->insert (@args);
}

=cut

TODO

    sub CreateEntry
    sub SetEntry
sub as_string
sub clone
sub convert_fieldIds_to_fieldNames
sub convert_fieldName_to_fieldId
sub execute_select_qry
sub find_where
sub from_xml
    sub get_cache
sub get_caching_enabled
sub get_ctrl
sub get_enum_value
sub get_formdata
    sub get_name
sub get_nowarn
sub get_only_these_fieldNames_href
sub get_populated
sub get_request_id
sub get_select_qry
sub get_select_qry_results
sub get_session
sub get_value
sub get_values_href
        sub initialize
    sub insert
    sub new
    sub populate
sub populate_with_hash
sub read
    sub read_into
    sub read_where
    sub save
    sub set_cache
sub set_caching_enabled
sub set_enum_value
    sub set_name
sub set_only_these_fieldNames_href
sub set_populated
sub set_request_id
sub set_select_qry
sub set_select_qry_results
sub set_session
sub set_value
sub set_values_href
sub to_xml
sub trim
    sub update

=cut

sub populate {
    my ($self) = @_;
    my $name    = $self->name_or_die ("cannot populate without a name");
    my $session = $self->session_or_die;

    # Now that we have a name, see if the global hash %FORM_CACHE has the data
    # for this schema yet. If not, populate it now.
    if (!$FORM_CACHE{$name}) {
        warn "S: $session\n";
        my $formdata = Remedy::Session::Form::Data->new (
            'name'    => $name,
            'session' => $session,
            'cache'   => $self->cache || {},
            'logger'  => $self->logger_or_die,
        );
        $FORM_CACHE{$name} = $formdata;
    }

    return $self->populated (1);
}

=item read_into ([QUERY])

Populates the existing object based on a B<read (QUERY)>.

If no I<QUERY> is offered, then we will take the default search (which is just
searching based on the Request ID, Field 1).

Dies if we get more than one result, or if we get no results.  Otherwise,
returns the Request ID.

=cut

sub read_into {
    my ($self, @rest) = @_;
    my $logger  = $self->logger_or_die;
    my $session = $self->session;

    my @results = $self->read (@rest);

    my $number_of_results = scalar @results;
    if ($number_of_results > 1) {
        $logger->logdie ("more than one result found\n");
    } elsif ($number_of_results < 1) {
        if (my $error = $ARS::ars_errstr) {
            $logger->logdie ($error);
        } else {
            $logger->debug ('no matches on read_into ()');
            return;
            # We do nothing.
        }
    } else {
        $logger->debug ('one match on read_into ()');
        my $first_result = $results[0];

        # Copy this result into $self
        $self->clone ($first_result);
    }

    # Add back the session
    $self->session ($session);

    return $self->get_request_id;
}

=item read_where (WHERE_CLAUSE)

=cut

sub read_where {
    my ($self, @rest) = @_;
    my $session = $self->session_or_die ('testing');
    if    ($session->get_remctl) { $self->read_where_remctl  (@rest) }
    elsif ($session->get_ctrl)   { $self->read_where_session (@rest) }
    else                         { die "invalid session object\n"    }
}

=item read_where_remctl (WHERE_CLAUSE)

Should really be moved into a Remedy::Session::Form::Remctl class.

=cut

sub read_where_remctl {
    my ($self, $where_clause) = @_;
    my $logger   = $self->logger_or_die;
    $logger->logdie ("missing where_clause argument\n") unless $where_clause;

    my $name     = $self->name_or_die;
    my $session  = $self->session_or_die;

    # We need a stripped-down object of the same type as $self to pass
    # to the remctl function.
    my $form = $self->new (session => $session);

    # Be careful to undefine the session object before sending via remctl
    $form->set_session (undef);

    # We only need the fields in the 'only_these_fieldNames_href' hash to
    # be populated by the read, so be sure to copy that from $self.
    $form->set_only_these_fieldNames_href
            ($self->get_only_these_fieldNames_href);

    $logger->all ('read_where via remctl ($form, $where_clause)');
    my $results_aref = remctl_call (SESSION  => $session,
                                    ACTION   => 'read_where',
                                    ARG_LIST => [$form, $where_clause]);

    # Reset the session object
    $form->set_session ($session);
    return @$results_aref;
}

=item read_where_session ()

=cut

sub read_where_session {
    my ($self, $where_clause) = @_;
    my $logger = $self->logger_or_die;
    $logger->logdie ("missing where_clause argument\n") unless $where_clause;

    my $ctrl     = $self->ctrl_or_die;
    my $formdata = $self->formdata_or_die;
    my $name     = $self->name_or_die;
    my $session  = $self->session_or_die;

    ## Create the "qualifier string" from the where clause.
    $logger->all ("ARS::ars_LoadQualifier ($name, $where_clause)");
    my $qualifier = ARS::ars_LoadQualifier ($ctrl, $name, $where_clause);
    if (! defined $qualifier) {
        $logger->logdie ("ars_LoadQualifier: $ARS::ars_errstr\n");
    }

    ## Get the list of fields we want returned
    my @ids_to_return = $self->fields_to_match;

    ## Do the query (sort according to entryID)
    $logger->all ("ARS::ars_GetListEntryWithFields ($name, [...])");
    my @results = ARS::ars_GetListEntryWithFields ($ctrl, $name,
        $qualifier, 0, 0, \@ids_to_return, 1, 1);

    ## If we got no results, see if there's an error
    if (!@results && $ARS::ars_errstr) {
        $logger->logdie ("$ARS::ars_errstr\n")
    }

    ## The array @results contains an array of (request_id, values) pairs,
    ## one for each row that matches. The "values" is a hash reference
    ## mapping fieldids (as specified in the array @fields_to_match) to
    ## values.  We need to populate the objects from the returned results.

    my @objects;
    while (@results) {
        my $request_id   = shift @results;
        my $results_href = shift @results;
        next unless $results_href && ref $results_href;

        ## Make the new object, and save it.
        my $new = $self->new ('session' => $session, 'name' => $name);
        $new->populate_with_hash ($results_href);
        $new->set_session (undef);

        push (@objects, $new);
    }

    return @objects;
}

sub cache_or_die    { _or_die (shift->cache,    "no cache",    @_) }
sub logger_or_die   { _or_die (shift->logger,   "no logger",   @_) }
sub session_or_die  { _or_die (shift->session,  "no session",  @_) }
sub ctrl_or_die     { _or_die (shift->ctrl,     "no ctrl",     @_) }
sub name_or_die     { _or_die (shift->name,     "no name",     @_) }
sub formdata_or_die { _or_die (shift->formdata, "no formdata", @_) }

=item fields_to_match ()

Returns an array of field IDs that the current object wants to search for,
based on the names contained in B<get_only_these_fieldNames_href ()>.

=cut

sub fields_to_match {
    my ($self) = @_;
    my $formdata = $self->get_formdata;

    # If the only_these_fieldNames_href property is not empty,
    # we read just those fields (along with field id '1').
    my $only_href = $self->get_only_these_fieldNames_href;
    my %only = %$only_href;

    my $id_to_name = $formdata->get_fieldId_to_fieldName_href;

    my @ids;
    if (! scalar %only) {
        @ids = keys %{$id_to_name};
    } else {
        # Add the fieldName corresponding to fieldId.
        my $req_id_name = $id_to_name->{'1'};
        $only{$req_id_name} = 1;

        # Convert the list to an array and get the fieldIds.
        @ids = $self->convert_fieldIds_to_fieldNames ([keys %only]);
    }
    return wantarray ? @ids : \@ids;
}

=item SetEntry (REQUEST_ID, FIELDS_AREF)

=cut

sub SetEntry {
    my ($self, $request_id, $fields_aref) = @_;
    my $logger = $self->logger_or_die;

    my $session = $self->session_or_die;
    my $name    = $self->name_or_die;

    # If this is a remctl call, go through remctl_call; not tested well.
    if ($session->get_remctl) {
        my @args = ($name, $request_id, $fields_aref);
        $logger->debug ('SetEntry start (remctl)');
        my $return = remctl_call ('SESSION'  => $session,
                                  'ACTION'   => 'SetEntry',
                                  'ARG_LIST' => \@args);
        $logger->debug ('SetEntry end   (remctl)');
        return $return;
    }

    my $ctrl = $self->ctrl_or_die;

    my @fields = @$fields_aref;

    $logger->debug ('SetEntry start (direct)');
    unless (ARS::ars_SetEntry ($ctrl, $name, $request_id, 0, @fields)) {
        $logger->logdie ("ars_SetEntry failed: $ARS::ars_errstr\n");
    }
    $logger->debug ('SetEntry end   (direct)');

    return 1;
}

=item CreateEntry (FIELDS_AREF)

=cut

sub CreateEntry {
    my ($self, $fields_aref) = @_;
    my $logger = $self->logger_or_die;

    my $session = $self->get_session;
    my $name    = $self->get_name;

    # If this is a remctl call, go through remctl_call; not tested well.
    if ($session->get_remctl) {
        my @args = ($name, $fields_aref);
        $logger->debug ('CreateEntry start (remctl)');
        my $request_id = remctl_call ('SESSION'  => $session,
                                      'ACTION'   => 'CreateEntry',
                                      'ARG_LIST' => \@args);
        $logger->debug ('CreateEntry end   (remctl)');
        return $request_id;
    }

    # This is not a remctl call, so call directly.
    my $ctrl = $session->get_ctrl;

    my @fields = @$fields_aref;

    $logger->debug ('CreateEntry start (direct)');
    my $request_id = ARS::ars_CreateEntry ($ctrl, $name, @fields);
    if (! defined $request_id) {
        $logger->logdie ("ars_CreateEntry failed: $ARS::ars_errstr\n");
    } elsif (! $request_id) {
        $logger->warn ("item was created but we don't know where");

        my $new = $self->new ('session' => $session, 'name' => $name);
        my $where_clause = $self->create_where_clause (@fields);
        my @forms = $new->read_where ($where_clause);
        my $count = scalar @forms;
        $logger->logdie ("no entries found after creation\n") unless $count;
        $logger->logdie ("too many entries found ($count) after creation\n")
            if ($count > 1);

        $request_id = $forms[0]->get_request_id;

        die "still no ID after search" unless $request_id;
    }

    $logger->debug ('CreateEntry end   (direct)');
    return $request_id;
}

sub fields { my %schema = shift->schema (@_);  return reverse %schema; }

sub schema {
    my ($self) = @_;
    my $href = $self->formdata_or_die->get_fieldName_to_fieldId_href;
    return reverse %{$href};
}

=item create_where_clause ()

=cut

sub create_where_clause {
    my ($self, @items) = @_;
    my %items = @items;

    my %classes = $self->schema;

    # Construct the where clause.
    my @terms = ();
    while (@items) {
        my $field_id = shift @items;
        my $value    = shift @items;
        my $field    = $classes{$field_id} || next;

        next unless defined $value;
        push @terms, $self->limit_string ($field_id, $field, $value);
    }

    # Put the terms together.
    my $where_clause = join (" AND ", @terms);

    return $where_clause;
}


=item id_to_name (ID)

=item ids_to_names (ID [, ID [, ID [...]]])

=cut

sub id_to_name { @{ids_to_names(@_)}[0]; }
sub ids_to_names {
    my ($self, @ids) = @_;
    my $formdata = $self->formdata_or_die;

    my @names;
    my $id_to_name_href = $formdata->get_fieldId_to_fieldName_href;
    foreach my $id (@ids) {
        my $name = $id_to_name_href->{$id} || $self->logger_or_die->logdie
            ("no field name corresponding to '$id'\n");
        push @names, $name;
    }
    return wantarray ? @names : \@names;
}

=item name_to_id (NAME)

=item names_to_ids (NAME [, NAME [, NAME [...]]])

=cut

sub name_to_id { @{names_to_ids(@_)}[0]; }
sub names_to_ids {
    my ($self, @names) = @_;
    my $formdata = $self->formdata_or_die;

    my @ids = ();
    my $name_to_id_href = $formdata->get_fieldName_to_fieldId_href;
    foreach my $name (@names) {
        my $id = $name_to_id_href->{$name} || $self->logger_or_die->logdie
            ("no field ID corresponding to '$name'\n");
        push @ids, $id;
    }
    return wantarray ? @ids : \@ids;
}

## compatibility functions

sub get_name    { shift->name }
sub set_name    { shift->name (shift) }

sub get_cache   { shift->cache }
sub set_cache   { shift->cache (shift) }

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub field_to_values {
    my ($self, $field) = @_;
    my $formdata = $self->get_formdata or return;
    my $href = $formdata->get_fieldName_to_enumvalues_href or return;
    my $values = $href->{$field};
    return unless defined $values && ref $values;
    return %{$values};
}

sub field_type {
    my ($self, $field, %args) = @_;
    my $href = $self->get_formdata->get_fieldName_to_datatype_href () or return;
    return lc $href->{$field};
}

sub field_is {
    my ($self, $type, $field) = @_;
    return 1 if $self->field_type ($field) eq lc $type;
    return 0;
}

## we probably want to take out the _gt bits here, actually
sub limit_string {
    my ($self, $id, $field, $value) = @_;
    return unless $id;
    return "'$id' == NULL" unless defined $value;

    ## 'enum' fields
    if ($self->field_is ('enum', $field)) {
        my ($mod, $human) = ($value =~ /^([+-]?=?)?(.*)$/);
        my %hash = reverse $self->field_to_values ($field);

        my $data;
        if    ($human =~ /^\d+/)      { $data = $human        }
        elsif (defined $hash{$human}) { $data = $hash{$human} }
        else                          { return '1=3'          }

        return $self->limit_gt ($id, $mod, $data);

    ## 'time' fields
    } elsif ($self->field_is ('time', $field)) {
        my ($mod, $timestamp) = ($value =~ /^([+-]?=?)?(.*)$/);

        my $data;
        if ($timestamp =~ /^\d+/)                { $data= $timestamp }
        elsif (my $time = str2time ($timestamp)) { $data = $time     }
        else                                     { return '1=2'      }

        return $self->limit_gt ($id, $mod, $data);

    ## all other field types
    } else {
        return if $value eq '%';
        $value =~ s/"/\\\"/g;
        return "'$id' = \"$value\"" if defined $value;
    }
}

### limit_gt (ID, MOD, TEXT)
# Makes a LIMIT string for integer comparisons.  ID should be the numeric field
# ID, TEXT should be an integer as well, and MOD is the type of comparison
# we're doing.
sub limit_gt {
    my ($self, $id, $mod, $text) = @_;
    return "'$id' <= $text" if $mod eq '-=';
    return "'$id' >= $text" if $mod eq '+=';
    return "'$id' < $text"  if $mod eq '-';
    return "'$id' > $text"  if $mod eq '+';
    return "'$id' = $text";
}

### _or_die (TYPE, ERROR, EXTRATEXT, COUNT)
# Helper function for Class::Struct accessors.  If the value is not defined -
# that is, it wasn't set - then we will immediately die with an error message
# based on a the calling function (can go back extra levels by offering
# COUNT), a generic error message ERROR, and a developer-provided, optional
# error message EXTRATEXT.
sub _or_die {
    my ($value, $error, $extra, $count) = @_;
    return $value if defined $value;
    $count ||= 0;

    my $func = (caller ($count + 2))[3];    # default two levels back

    chomp ($extra) if defined $extra;
    my $fulltext = sprintf ("%s: %s", $func, $extra ? "$error ($extra)"
                                                    : $error);
    die "$fulltext\n";
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 TODO

Move B<Stanford::Remedy::Form> into here.

=head1 REQUIREMENTS

B<Stanford::Remedy::Form>

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
