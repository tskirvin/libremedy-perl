package Remedy::Session::Form::Data;
our $VERSION = '0.08';
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Session::Form::Data - stores a Remedy form's field information

=head1 SYNOPSIOS

    use Remedy::Session::Form::Data;
    [...]

=head1 DESCRIPTION

[...]

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

## How many characters should we save for the 'prefix' of a line when we're
## printing a single line of text?
our $LINE_PREFIX = 35;

our %DATATYPE_TEXT_TO_CODE = (
    'integer'         => 2,
    'real'            => 3,
    'character'       => 4,
    'enum'            => 6,
    'date'            => 7,
    'attachment'      => 11,
    'currency'        => 12,
    'text'            => 31,
    'button'          => 32,
    'table_field'     => 33,
    'column_title'    => 34,
    'page'            => 35,
    'page_holder'     => 36,
    'attachment_pool' => 37,
);

our %FIELDTYPE_TO_DESCRIPTION = (
    0 => 'no_store',
    1 => 'other',
    2 => 'join_form',
    3 => 'view_form',
    4 => 'vendor_form',
);

our %FOPTION_TO_DESCRIPTION = (
    1 => 'required',
    2 => 'optional',
    3 => 'system',
    4 => 'display_only',
);

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Data::Dumper;
use Remedy::Log;
use Remedy::Session::Form::Remctl qw ( remctl_call );
use Remedy::Session::Cache;
use Remedy::Utility qw/or_die/;

our @ISA = qw/Remedy::Session::Form::Data::Struct/;

struct 'Remedy::Session::Form::Data::Struct' => {
    'cache'        => 'Remedy::Session::Cache',
    'logger'       => 'Log::Log4perl::Logger',
    'name'         => '$',
    'name_default' => '%',
    'name_to_enum' => '%',
    'name_to_fopt' => '%',
    'name_to_id'   => '%',
    'name_to_type' => '%',
    'name_update'  => '%',
    'session'      => 'Remedy::Session',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head2 Subroutines

=over 4

=item new (ARGHASH)

=over 2

=item name I<NAME> (REQUIRED)

The name of the form (e.g. I<HPD:Help Desk>)

=item session I<Remedy::Session> (REQUIRED)

=item logger I<Log::Log4perl>

=item cache I<Remedy::Session::Cache>

=item [...]

=back

=cut

sub new {
    my ($proto, %args) = @_;
    my $class = ref ($proto) || $proto;
    my $self = Remedy::Session::Form::Data::Struct->new (%args);
    bless $self, $class;

    ## Get the logger.
    my $logger = $self->logger || $self->logger (Remedy::Log->logger);

    ## Most of the initilization happened with the Struct init, but we have 
    ## some backwards compatibility flags to support too.
    my %map = (
        'name_default'   => 'fieldName_to_defaultValue_href',
        'name_to_enum'   => 'fieldName_to_enumvalues_href',
        'name_to_fopt'   => 'fieldName_to_fOption_href',
        'name_to_id'     => 'fieldName_to_fieldId_href',
        'name_to_type'   => 'fieldName_to_datatype_href',
        'name_update'    => 'fieldName_to_fieldId_updateable_href',
    );
    foreach my $key (keys %map) { 
        my $arg = $map{$key};
        next unless $args{$arg};
        $self->$key ($args{$arg});
    }
    
    # Get the cached values, if possible.
    my $name    = $self->name_or_die ('cannot initialize without a name');
    my $session = $self->session_or_die;
    my $cache   = $self->cache || $self->cache (Remedy::Session::Cache->new);

    return $self->populate;
}

=item populate ()

Populates the object's 

=cut

sub populate {
    my ($self) = @_;
    my $logger  = $self->logger_or_die;
    my $name    = $self->name_or_die;
    my $session = $self->session_or_die;
    my $cache   = $self->cache_or_die;

    # Define the cache key (based on package, function, and schema).
    my $server = $session->get_server_or_die (__PACKAGE__);
    my ($package, $filename, $line) = caller;
    my $cache_key = join (';', $package, $filename, $server, $name);

    if (my $results = $cache->get_value ($cache_key)) { 
        $logger->debug ("information about $name retrieved from cache");
        return $self->populate_from_cache ($results);
    } else {
        $logger->debug ("data about $name not in cache");
        my $return = $self->populate_from_session;

        # Save to cache. Remember to undef the cache and session properties.
        $self->session (undef);
        $self->cache   (undef);
        $cache->set_value ($cache_key, $self);
        $self->session ($session);
        $self->cache   ($cache);
        return $return;
    }
}

=item populate_from_cache (RESULTS)

Takes I<RESULTS> - a value returned from B<Remedy::Session::Cache> - and
populates the I<name_*> fields with it.

=cut

sub populate_from_cache {
    my ($self, $results) = @_;
    foreach (qw/name_to_id name_to_type name_to_enum name_update
                name_default name_to_fopt/) { 
        $self->$_ ($results->$_)
    };
    # $self->name_to_id   ($results->{'fieldName_to_fieldId_href'});
    # $self->name_to_type ($results->{'fieldName_to_datatype_href'});
    # $self->name_to_enum ($results->{'fieldName_to_enumvalues_href'});
    # $self->name_update  ($results->{'fieldName_to_fieldId_updatable_href'});
    # $self->name_default ($results->{'fieldName_to_defaultValue_href'});
    # $self->name_to_fopt ($results->{'fieldName_to_fOption_href'});
    return 1;
}

# Populate the attribute hashes given the schema name.
sub populate_from_session {
    my ($self) = @_;
    my $session = $self->session_or_die ("cannot populate without session");
    my $logger  = $self->logger_or_die;

    my $fn = 'populate';

    ## Step 1. Get the form name.
    my $name = $self->name_or_die;

    ## Step 2. Initialize all the mappings to be empty.
    my %name_to_id   = ();
    my %name_to_type = ();
    my %name_default = ();
    my %name_to_fopt = ();
    my %name_update  = ();
    my %name_to_enum = ();
    my %id_to_enum   = ();

    ## Step 3.  Retrieve field <-> id mappings
    $logger->all ("ars_GetFieldTable ($name)");
    %name_to_id = $session->ars_GetFieldTable ($name);

    # Step 4. Get fieldname mapping to datatype, defaultValue,
    # and fOption.

    # Get the field properties for all the fields
    $logger->all ("ars_GetFieldsForSchema ($session, $name)");
    my %id_to_property = ars_GetFieldsForSchema ($session, $name);

    # Now populate the hashes.
    foreach my $name (keys %name_to_id) {
        my $id = $name_to_id{$name};
        my $properties = $id_to_property{$id};

        my $datatype = $properties->{'dataType'};
        my $default  = $properties->{'defaultVal'};
        my $option   = $properties->{'option'};

        $name_to_type{$name} = $datatype;
        $name_default{$name} = $default;
        $name_to_fopt{$name} = $option;

        # Is this field updatable?
        #   fOption = 1 --> required
        #   fOption = 2 --> option
        #   fOption = 3 --> system
        #   fOption = 4 --> display only
        if ($option <= 2) { # YES, updateable.
            $name_update{$name} = $id;
        }

        # Get the enumerated values
        if ($datatype eq 'enum') {
            my $limit = $properties->{'limit'};
            my $enumlimits = $limit->{'enumLimits'};

            ## CASE 1. Is this a custom list?
            if (exists ($enumlimits->{'customList'})) {
                my $customlist = $enumlimits->{'customList'};

                foreach my $enum (@$customlist) {
                    $id_to_enum{$id} ||= {};
                    $id_to_enum{$id}->{$enum->{'itemNumber'}} 
                        = $enum->{'itemName'};
                }
            }

            ## CASE 2. Is this a regular list?
            elsif (exists ($enumlimits->{'regularList'})) {
                my $regularlist = $enumlimits->{'regularList'};

                my $counter = 0;
                foreach my $value (@$regularlist) {
                    $id_to_enum{$id} ||= {};
                    $id_to_enum{$id}->{$counter} = $value;
                    $counter++;
                }
            } else {
                $logger->logdie ("don't know how to deal with limit ($id): "
                    . (Dumper $enumlimits));
            }
        }
    }

    my %id_to_name = reverse %name_to_id;

    # Loop through all the mappings and set $name_to_enum
    foreach my $id (keys %id_to_enum) {
        # Get the name for this id.
        my $name = $id_to_name{$id};
        if (!$name) {
            $logger->warn ("no name for id '$id' (name = $name)");
            next;
        }

        my $id_to_value = $id_to_enum{$id};
        $name_to_enum{$name} = $id_to_value;
    }


    $self->name_to_id   (\%name_to_id);
    $self->name_to_type (\%name_to_type);
    $self->name_default (\%name_default);
    $self->name_to_fopt (\%name_to_fopt);
    $self->name_update  (\%name_update);
    $self->name_to_enum (\%name_to_enum);

    ## Step 6. Status History (fieldId '15) is weird: it is not really a
    ##         field at all, so delete it.
    $self->delete_fieldId ('15');

    ## Step 7. Delete the session attribute (no longer needed).
    $self->session (undef);

    return;
}

# Delete a field from the populated fields
sub delete_fieldId
{
  my $self = shift;

  my ($fieldId) = @_;

  my $fieldName_to_fieldId_href = $self->get_fieldName_to_fieldId_href();
  my $fieldId_to_fieldName_href = $self->get_fieldId_to_fieldName_href();
  my $fieldName_to_datatype_href = $self->get_fieldName_to_datatype_href();
  my $fieldName_to_fieldId_updatable_href
    = $self->get_fieldName_to_fieldId_updatable_href();

  my $fieldName = $fieldId_to_fieldName_href->{$fieldId};
  if (!$fieldName)
  {
    warn "there is no fieldName associated with fieldId '$fieldId'";
    return;
  }

  delete $fieldName_to_fieldId_href->{$fieldName};
  delete $fieldId_to_fieldName_href->{$fieldId};
  delete $fieldName_to_datatype_href->{$fieldName};
  delete $fieldName_to_fieldId_updatable_href->{$fieldName};

  return;
}

=item get_name ()

=item set_name (NAME)

Compatibility functions.

=cut

sub get_name    { shift->name }
sub set_name    { shift->name (shift) }

sub get_session { shift->session }
sub set_session { shift->session (shift) }

sub get_cache   { shift->cache }
sub set_cache   { shift->set_cache (shift) }

sub get_fieldName_to_fieldId_href { shift->name_to_id }
sub set_fieldName_to_fieldId_href { shift->name_to_id (shift) }

sub get_fieldName_to_fOption_href { shift->name_to_fopt }
sub set_fieldName_to_fOption_href { shift->name_to_fopt (shift) }

sub get_fieldId_to_fieldName_href { 
    my $name_to_id = shift->name_to_id;
    my %reverse = reverse %$name_to_id;
    return \%reverse;
}

sub get_fieldName_to_datatype_href { shift->name_to_type }
sub set_fieldName_to_datatype_href { shift->name_to_type (shift) }

sub get_fieldName_to_enumvalues_href
{
  my $self = shift;
  return $self->{'fieldName_to_enumvalues_href'};
}

sub get_fieldName_to_fieldId_updatable_href
{
  my $self = shift;
  return $self->{'fieldName_to_fieldId_updatable_href'};
}

sub get_fieldName_to_defaultValue_href
{
  my $self = shift;
  return $self->{'fieldName_to_defaultValue_href'};
}

sub set_fieldId_to_fieldName_href
{
  my $self = shift;
  my ($fieldId_to_fieldName_href) = @_;
  $self->{'fieldId_to_fieldName_href'} = $fieldId_to_fieldName_href;
  return;
}

sub set_fieldName_to_enumvalues_href
{
  my $self = shift;
  my ($fieldName_to_enumvalues_href) = @_;
  $self->{'fieldName_to_enumvalues_href'} = $fieldName_to_enumvalues_href;
  return;
}

sub set_fieldName_to_fieldId_updatable_href
{
  my $self = shift;
  my ($fieldName_to_fieldId_updatable_href) = @_;
  $self->{'fieldName_to_fieldId_updatable_href'} = $fieldName_to_fieldId_updatable_href;
  return;
}

sub set_fieldName_to_defaultValue_href
{
  my $self = shift;
  my ($fieldName_to_defaultValue_href) = @_;
  $self->{'fieldName_to_defaultValue_href'} = $fieldName_to_defaultValue_href;
  return;
}


sub as_string {
    my ($self, $values_href, %opts) = @_;
    $values_href ||= {};

    my @attributes = ('name');

    my @return;
    foreach my $attribute (@attributes) {
        push @return, _display_one_line ($attribute, $self->{$attribute});
    }
    push @return, '';

    my %name_to_id   = %{ $self->name_to_id };
    my %name_to_type = %{ $self->name_to_type };
    my %name_default = %{ $self->name_default };
    my %name_to_fopt = %{ $self->name_to_fopt };
    my %name_to_enum = %{ $self->name_to_enum };

    my $session = $self->session;

    if (! $opts{'no_session'}) {
        my $session = $self->get_session();
        push @return, "[SESSION (start)]";
        if ($session) {
            push @return, $session->as_string ('  ');
        } else {
            push @return, "session undefined";
        }
        push @return, "[SESSION (end)]";
    }

    my %datatype_to_text = reverse %DATATYPE_TEXT_TO_CODE;

    # Sort according to value of key
    my $sort_fref = sub { (0 + $name_to_id{$a}) <=> (0 + $name_to_id{$b}) };

    foreach my $name (sort $sort_fref keys %name_to_id) {
        my $id = $name_to_id{$name};

        ## 1. Get the datatype
        my $datatype = $name_to_type{$name};

        my $datatype_text = $datatype;
        if (exists $datatype_to_text{$datatype}) {
            $datatype_text = $datatype_to_text{$datatype};
        }

        ## 2. Get the value
        my $value;
        if (exists $values_href->{$name}) {
            $value = $values_href->{$name};
        } else {
            # For missing values we skip (NOT!)
            #$value = '<NULL>';
        }

        if (!defined($value)) { $value = '<NULL>'; }

        ## 3. Is there a default value?
        my $defaultValue = q{};
        if ($name_default{$name}) {
            $defaultValue = " DEFAULT: " . $name_default{$name};
        }

        ## 4. Get the fOption value. If it is mandatory, we want to mark it
        ## as such.
        my $fopt = $name_to_fopt{$name};
        my $fopt_text = $FOPTION_TO_DESCRIPTION{$fopt};
        my $required_marker = '';
        if ($fopt_text =~ m{required}i) {
            $required_marker = '*';
        }

        push @return, _display_one_line ($name . $required_marker,
            sprintf ("%s [%10d %-8s]", $value, $id, $datatype_text));
        if ($defaultValue) { push @return, "$defaultValue"; }

        # Is this an enum?
        if ($name_to_enum{$name})  {
            my $enum_values = $name_to_enum{$name};
            push @return, _format_enum_values ($enum_values);
        }
    }

    return wantarray ? @return : join ("\n", @return, '');
}





# The query MUST be a select query that returns exactly two
# distinct fields that are bijective (that is, for each field1 there is
# exactly one field2 and vice-versa).
#
# get_hash_ref_mapping_from_sql(
#              SESSION  => $session,
#              QRY      => 'SELECT name, schemaID FROM arschema',
#                             )
# where $connect is a _connected_ Remedy::Session object.
#
# Returns the hash.

sub get_hash_ref_mapping_from_sql
{
  my (%args) = (
                @_,
               );

  my $session = $args{SESSION};
  my $qry     = $args{QRY};

  if (!$qry)
  {
    local_die("missing QRY parameter");
  }

  if (!$session)
  {
    local_die("missing SESSION parameter");
  }

  my @select_results = ();
  execute_query_return_results(
      SESSION      => $session,
      QRY          => $qry,
      RESULTS_AREF => \@select_results,
                               );

  # Convert results into a hash. Fetch results
  my %field1_to_field2 = ();
  foreach my $row_aref (@select_results)
  {
    my @row = @$row_aref;
    my $field1 = $row[0];
    my $field2 = $row[1];
    $field1_to_field2{$field1} = $field2;
  }


  # Return the number of rows read.
  return %field1_to_field2;
}

# Given an ARS::DBD object and a SELECT query, execute the query and populates
# the array reference passed as a paramter as an array of array references:
#  (
#   [1, 'dog', 4],
#   [2, 'cat', 8],
#   [9, 'bug', 3],
#  )
#
# Use:
#
# execute_query_return_results(
#      SESSION      => $session,
#      QRY          => "SELECT schemaId, name FROM arschema",
#      RESULTS_AREF => \@results,
# )
#
# Note that $session can be either a direct connected session or a remctl
# session.

sub execute_query_return_results
{
  my $fn = 'execute_query_return_results';

  my (%args) = (
                @_,
               );

  my $session      = $args{SESSION};
  my $qry          = $args{QRY};
  my $results_aref = $args{RESULTS_AREF};
  my $cache        = $args{CACHE};

  if (!$session)
  {
    local_die("no session object passed");
  }

  if (!$qry)
  {
    local_die("no query passed");
  }

  if (!$results_aref)
  {
    local_die("no results array reference passed");
  }

  # If $cache is undefined, make one now.
  if (!$cache)
  {
    $cache = Remedy::Session::Cache->new();
  }

  # Set up caching.
  my $server = $session->get_server_or_die($fn);
  my $cache_key = $fn . ';' . $qry . ';' . $server;
  if ($cache)
  {
    my $cache_results_aref = $cache->get_value($cache_key);
    if (defined($cache_results_aref))
    {
      # A cache HIT! We can return the hash.
      my @query_results = @{ $cache_results_aref };
      @$results_aref = @query_results;

      # log_info("Cache hit for query '$qry'");

      # Return the number of rows.
      return (0 + @query_results);
    }
  }

  # If we get here, it was a cache miss.
  # Let's time how long it takes to get the value.
  my $start_time = time();

  # Store the results here.
  my @select_results;
  my $number_rows_selected;

  # CASE 1. This is a remctl session.
  if ($session->get_remctl())
  {
    my $remctl = $session->get_remctl();
    my $action = 'select_qry';

    my $select_qry_results_aref =
      remctl_call(
                 SESSION  => $session,
                 ACTION   => $action,
                 ARG_LIST => [$qry,],
                  );

    @$results_aref = @$select_qry_results_aref;
  }
  # CASE 2. This is a direct session.
  else
  {
    my $dbh = $session->get_dbh();
    my $sth = $dbh->prepare($qry) or die $dbh->errstr();
    $sth->execute() or die $sth->errstr();

    my $row_number = 0;
    while (my @columns = $sth->fetchrow_array())
    {
      $results_aref->[$row_number] = \@columns;
      ++$row_number;
    }
    $sth->finish();
    $number_rows_selected = $row_number;
  }

  # Save to cache.
  if ($cache)
  {
    $cache->set_value($cache_key, $results_aref);
  }

  my $end_time = time();
  my $elapsed_time = ($end_time - $start_time);
  log_info("cache miss elapsed time ($qry): $elapsed_time seconds");

  return $number_rows_selected;
}

=item logger_or_die (TEXT)

=item name_or_die (TEXT)

=item session_or_die (TEXT)

=item cache_or_die (TEXT)

=cut

sub logger_or_die   { $_[0]->or_die (shift->logger,  "no logger",  @_) }
sub name_or_die     { $_[0]->or_die (shift->name,    "no name",    @_) }
sub session_or_die  { $_[0]->or_die (shift->session, "no session", @_) }
sub cache_or_die    { $_[0]->or_die (shift->cache,   "no cache",   @_) }

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

### _display_one_line (ATTRIBUTE, VALUE)
# Displays
# TODO: use sprintf, make sure there's at least one space
sub _display_one_line {
    my ($attribute, $value) = @_;
    my $prefix = qq/$attribute: /;
    my $length = $LINE_PREFIX - length ($prefix);
    my $spaces = ' ' x $length;
    $value = '' unless defined $value;
    return join ('', $prefix, $spaces, $value);
}

sub _format_enum_values {
    my ($enum_values_href) = @_;
    my %enum_values = %$enum_values_href;
    my $rv = '';
    foreach my $key (sort {$a<=>$b} keys %enum_values) {
        my $value = $enum_values{$key};
        $rv .= sprintf ("%8d: %s\n", $key, $value);
    }
    return $rv;
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 NAME

Remedy::Session::Form::Data - stores a Remedy form's field information

=head1 VERSION

Version 0.08

=head1 SYNOPSIS

    use Remedy::Session::Form::Data;

    # You will need a connected Remedy::Session
    # object.
    use Remedy::Session;
    my $session = Remedy::Session->new(
      server    => 'r7-app1-dev.stanford.edu',
      username  => 'joeuser',
      password  => 'secret',
    );
    $session->connect();

    my $formdata = Remedy::Session::Form::Data->new(
      schemaId => 1,
      session  => $session,
    );

Every Remedy form consists of a set of fields. These fields have several
attributes including field id, field name, and a datatype. The
Remedy::Session::Form::Data object stores this information.

For more details on these and other form attributes, see
the documentation module Remedy::Introduction.

The Remedy::Session::Form::Data object is tytpically not used by an end
user, rather, it's main purpose is to be used in the global datastructure
C<%REMEDY_FORM_DATA> in the Remedy::Form module.



=head1 METHODS

=head2 C<new>

The C<new> method creates a new Remedy::Session::Form::Data object.

=head3 session (set_session, get_session)

This attribute is MANDATORY. It should be a connected
Remedy::Session object. It is used to populate the object.

=head3 name

This attribute is MANDATORY. The Remedy schema (form) name.

=head3 fieldName_to_fieldId_href

This is a reference to a hash mapping field name to field id number.
For more information on field names and id numbers,
see Remedy::Introduction.
This attribute is filled in automatically.

    my $formdata = Remedy::Session::Form::Data->new(
                               name    => 'HPD:Help Desk',
                               session => $session,
                                          );

    my $fieldName_to_fieldId_href
      = $formdata->get_fieldName_to_fieldId_href();
    foreach my $fieldName (keys %{ $fieldName_to_fieldId_href })
    {
      my $fieldId = $fieldName_to_fieldId_href->{$fieldName};
      print "$fieldName has field id $fieldId\n";
    }

=head3 fieldId_to_fieldName_href

This is a reference to a hash mapping field id number to field name (i.e., the
reverse of C<fieldName_to_fieldId_href>).
This attribute is filled in automatically.

    my $formdata = Remedy::Session::Form::Data->new(
                               name    => 'HPD:Help Desk',
                               session => $session,
                                          );
    my $fieldId_to_fieldName_href
      = $form->get_fieldId_to_fieldName_href();

    # %$fieldId_to_fieldName_href is exactly the same as
    # reverse %{$fieldName_to_fieldId_href}

=head3 fieldName_to_datatype_href

This is a reference to a hash mapping field name to field datatype.
A list of all possible datatypes is in
C<%Remedy::Session::Form::Data::DATATYPE_TEXT_TO_CODE>.
For more information on field datatypes, see Remedy::Introduction.
This attribute is filled in automatically.

    my $form = Remedy::Form->new(
                               name    => 'HPD:Help Desk',
                               session => $session,
                                          );
    my $fieldName_to_datatype_href
      = $form->get_fieldName_to_datatype_href();

    foreach my $fieldName (keys %{ $fieldName_to_datatype_href })
    {
      my $datatype = $fieldName_to_fielddatatype_href->{$fieldName};

      # Note that $datatype is an integer. To get a text description
      # of the datatype we use %DATATYPE_TEXT_TO_CODE.
      my $text_to_datatype_code = %Remedy::Form::DATATYPE_TEXT_TO_CODE;
      my %datatype_to_text = reverse $text_to_datatype_code;
      my $datatype_text = $datatype_to_text{$datatype};
      print "$fieldName has datatype $datatype_text\n";
    }

=head3 fieldName_to_fOption_href

This is a reference to a hash mapping field name to field fOption.
These fOptions are integers that represent properties such as E<quot>optionalE<quot>,
E<quot>requiredE<quot>, etc.
A mapping from the fOption to a textual description is in
C<%Remedy::Session::Form::Data::FOPTION_TO_DESCRIPTION>.
For more information on field fOptions, see Remedy::Introduction.
This attribute is filled in automatically.

    my $form = Remedy::Form->new(
                               name    => 'HPD:Help Desk',
                               session => $session,
                                          );
    my $fieldName_to_fOption_href
      = $form->get_fieldName_to_fOption_href();

    foreach my $fieldName (keys %{ $fieldName_to_fOption_href })
    {
      my $fOption = $fieldName_to_fieldfOption_href->{$fieldName};

      # Note that $fOption is an integer. To get a text description
      # of the datatype we use %FOPTION_TO_DESCRIPTION.
      my $text_to_fOption_code = %Remedy::Form::FOPTION_TO_DESCRIPTION;
      my %fOption_to_text = reverse $text_to_fOption_code;
      my $fOption_text = $fOption_to_text{$fOption};
      print "$fieldName has fOption $fOption_text\n";
    }

=head3 fieldName_to_enumvalues_href

This is a reference to a hash mapping field name to the
enumerated values for that field.
The keys of this hash are not all the fieldNames but only the
fieldNames of fields with the enum datatype. The values of this hash
are hash references mapping integers to text descriptions of the
enumerated types.

For example, if C<$formdata> is a Remedy::Session::Form::Data object with form name
E<quot>HPD:Help DeskE<quot>, then the code

    my $fieldName_to_enumvalues_href =
      $formdata->get_fieldName_to_enumvalues_href();

    my $enum_values_href = $fieldName_to_enumvalues_href->{'Urgency'};

    # $enum_values_href now contains
    #  {
    #    '1000' =>  '1-Critical',
    #    '2000' =>  '2-High',
    #    '3000' =>  '3-Medium',
    #    '4000' =>  '4-Low',
    #  }

    foreach my $integer_key (keys %{ $enum_values_href })
    {
      my $text_value = $enum_values_href->{$key};
      print "$integer_key: $text_value\n";
    }

would produce the output

    1000: 1-Critical
    2000: 2-High
    3000: 3-Medium
    4000: 4-Low

=head3 fieldName_to_defaultValue_href

If a field has a default value its fieldName will appear as
key to this hash. The value of the hash is the field's default value.

    my $formdata = Remedy::Form->new(
                               name    => 'HPD:Help Desk',
                               session => $session,
                                          );
    my $fieldName_to_defaultValue_href
      = $formdata->get_fieldName_to_defaultValue_href();

    foreach my $fieldName (keys %{ $fieldName_to_defaultValue_href })
    {
      my $defaultValue = $fieldName_to_defaultValue_href->{$fieldName};
      print "field '$fieldName' has default value '$defaultValue'";
    }

=head3 fieldName_to_fieldId_updatable_href

This method returns a reference to a hash that is a sub-hash of
the hash returned by C<get_fieldName_to_fieldId>. The keys are only those
fields that can be updated. We use
C<get_fieldName_to_fieldId_updatable_href> to help us decide which fields
to update during an insert or update.

Note that this hash is derived from the fOption hash.

=head1 AUTHOR

Adam Lewenberg, C<< <adamhl at stanford.edu> >>

=head1 BUGS

Please report any bugs or feature requests
to C<adamhl at stanford.edu>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Remedy::Session::Form::Data

=head1 ACKNOWLEDGEMENTS

This code uses some code from the HelpSU application written by Tim Torgenrud.

=head1 COPYRIGHT & LICENSE

Copyright 2008 Stanford University, all rights reserved.

=cut

1;
