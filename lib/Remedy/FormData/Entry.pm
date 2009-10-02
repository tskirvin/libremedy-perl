package Remedy::FormData::Entry;
our $VERSION = "0.01";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::FormData::Entry -

=head1 SYNOPSIS

    use Remedy::FormData::Entry;

    my $table = "TABLE NAME";
    # $session is a pre-existing Remedy::Session object
    # $cache   is a pre-existing Remedy::Cache object

    my $data = eval { Remedy::FormData::Entry->new ('session' => $session,
        'name' => "TABLE NAME", 'cache' => $cache) };
    die "No such form: '$table' ($@)\n" if $@;


    [...]

=head1 DESCRIPTION

Remedy::FormData::Entry manages the mapping of the general form information
stored in B<Remedy::FormData> into individual form entries.  From there, we
move the data to and from the Remedy database using a B<Remedy::Session> and
a local B<Remedy::Cache> cache.

[...]

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

## Used to globally cache formdata information for the duration of the run.
our %FORMDATA = ();

## Fields that we will put into the Class::Struct object.
our %FIELDS = (
    'cache'       => 'Remedy::Cache',
    'fields_only' => '@',
    'formdata'    => 'Remedy::FormData',
    'name'        => '$',
    'session'     => 'Remedy::Session',
    'values'      => '%',
);

##############################################################################
### Declarations #############################################################
##############################################################################

use warnings;
use strict;

use Class::Struct;
use Date::Parse qw/str2time/;
use Remedy::Log;
use Remedy::Cache;
use Remedy::FormData;
use Remedy::FormData::Utility;
use Remedy::Utility qw/or_die/;

our @ISA = qw/Remedy::FormData::Entry::Struct/;

struct 'Remedy::FormData::Entry::Struct' => { %FIELDS };

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

Remedy::FormData::Entry is a sub-classed B<Class::Struct> object - that is, it
has many functions that are created by B<Class::Struct>, but overrides the
B<new ()> function for more fine-grained control.

=head2 Basic Object and B<Class::Struct> Accessors

=over 4

=item new (ARGHASH)

Creates and returns a Remedy::FormData::Entry object.  Throws an exception on
failure.  Argument hash I<ARGHASH> is used to initialize the underlying
B<Class::Struct> object.  We also take the following arguments:

=over

=item nocache (0|1)

If set, do not create a new B<Remedy::Cache> object if we aren't passed one
directly.

=item values_href (HASHREF)

Overrides I<values> if present.  (Compatibility.)

=back

=cut

sub new {
    my ($proto, %args) = @_;
    my %default = ('values' => $args{'values_href'});
    my $class = ref $proto || $proto;
    my $self = Remedy::FormData::Entry::Struct->new (%default, %args);
    bless $self, $class;

    ## Create a cache if necessary
    if (! $args{'nocache'} && ! $self->cache) {
        $self->cache (Remedy::Cache->new)
    }

    my $name   = $self->name_or_die;
    my $logger = $self->logger_or_die;

    ## Populate the formdata item, from the cache if possible
    my $formdata;
    if ($formdata = $FORMDATA{$name}) {
        # $logger->all ("pulling cached formdata for $name");
    } else {
        $logger->all ("retrieving formdata for $name");
        $formdata = Remedy::FormData->new ('logger'  => $logger,
                                           'name'    => $name,
                                           'cache'   => $self->cache,
                                           'session' => $self->session_or_die);
        $logger->logdie ("did not get form data: $@") unless $formdata;

        my $error = $formdata->populate;
        $logger->logdie ("could not populate formdata: $error") if $error;

        $FORMDATA{$name} = $formdata;
    }

    $self->formdata ($formdata);

    return $self;
}

=item cache (Remedy::Cache)

Connection to the primary cache.  We will create one on initialization if one
is not offered, unless we use the flag I<nocache>.

=item fields_only (@)

Used to restrict which fields we want to return.  Keys are the fields that we
want; values are currently reserved.  While there is no default, the function
that actually uses this
Lists which fields we want to
A hash containing a list of fields that we wish to retrieve
Contains

=item formdata (Remedy::FormData)

Stores general information about the form.  Automatically created based on
B<name> and B<session> upon object creation.

=item name ($)

Form name for accessing the database.  Required.

=item session (Remedy::Session)

The session by which we will actually interact with the database.  Required.

=item values (%)

Hash containing actual raw key/value pairs for the single item in the database.

=back

=cut

##############################################################################
### Data Manipulation ########################################################
##############################################################################

=head2 Data Manipulation

=over 4

=item clone (SOURCE)

Takes I<SOURCE>, an existing B<Remedy::FormData::Entry> object, and copies its
value into the parent object (or a new object, if necessary).  Primarily used
by B<read_into ()>.

=cut

sub clone {
    my ($self, $source) = @_;
    $self = $self->new ($source->name, $source->session) unless ref $self;
    foreach (keys %FIELDS) { $self->$_ ($source->$_) }
    return $self;
}

=item insert ()

Insert this entry into the Remedy database.  This generally means running
B<CreateEntry ()> through the B<session> object, and then re-reading the object
with B<read_into ()> in order to pick up any information that was added by
workflow on the server end.  Returns the request ID (field 1) of the new entry
on success, dies on failure.

Note that we do not check ahead of time to see if the item is already in the
database.  If this is a concern, use B<save ()>.

Also note that that there is an outstanding bug concerning writing entries to
join tables.  A workaround is implemented here, which is documented in the
code.

=cut

sub insert {
    my ($self) = @_;
    my $logger   = $self->logger_or_die;
    my $session  = $self->session_or_die;
    my $formdata = $self->formdata_or_die;
    my $name     = $self->name_or_die;
    my $values   = $self->values;

    my $id = $self->request_id;
    $logger->logdie ("item already exists (ID $id)") if $id;

    ## Populate an array of (field_id, value) pairs.
    my %fields = $self->fields_values ();
    return unless scalar %fields;

    delete $fields{1};      # never set the request ID on an insert

    ## Actually insert the entry.
    my $req_id = eval { $session->CreateEntry ($name, [%fields]) };
    $logger->logdie ($@) if $@;

    ## HACK: Work-around for existing Remedy bug.  Basically, if you write
    ## to a join table, then you will not get a request ID back (the writing
    ## happens in a different order on the back-end); but we need that request
    ## ID to continue, so we'd better keep looking).  So we'll try searching
    ## based on the rest of the information we offered, and if there's only
    ## one matching entry we're in good shape.  If there are more or less,
    ## then bomb and blame the bug.  
    ## TODO: reference the bug in the error msg

    unless ($req_id) {
        my $where = $self->create_where_clause ($self->fields_not_empty);
        my @forms = $self->read ($where, 'max' => 5);
        my $count = scalar @forms;
        $logger->logdie ("no entries found after creation\n") unless $count;
        $logger->logdie ("too many entries (at least $count) after creation\n")
            if ($count > 1);
        $req_id = $forms[0]->request_id;
        $logger->warn ("still no ID after search") unless $req_id;
    }

    $logger->logdie ("failed to create a new request: $@") unless $req_id;

    ## Re-read the entry from the database, in order to pull information
    ## that was set by the workflow.
    $self->request_id ($req_id);
    unless (my $rid = $self->read_into) {
        $logger->logdie ("could not re-read object into self: $@");
    }

    ## Return the request id.
    return $req_id;
}

=item read ([WHERE], ARGHASH)

Given a select clause I<WHERE>, pull all matching entries from the Remedy
database and create new entry objects as appropriate.  This uses B<read
(I<ARGHASH>)> through the B<session> object.  Returns an array of entries.

=cut

sub read {
    my ($self, $where, %args) = @_;
    my $logger  = $self->logger_or_die;
    my $name    = $self->name_or_die;
    my $session = $self->session_or_die;

    my @limit = $args{'limit'} ? @{$args{'limit'}}
                                 : $self->fields_to_match;
    $where ||= $self->create_where_clause;

    my %search = ('schema' => $name, 'where' => $where, 
        'limit' => \@limit, %args);
    $logger->all ("read ($name, $where, [...])");
    my @results = $session->read (%search);

    my $id_to_name = $self->formdata_or_die->id_to_name;

    my @objects = ();
    while (@results) {
        my $request_id   = shift @results;
        my $results_href = shift @results;
        next unless $results_href && ref $results_href;

        my $new = $self->new ('name' => $name, 'session' => $session,
            'cache' => $self->cache);
        foreach my $id (keys %$results_href) {
            my $value = $results_href->{$id};
            my $field = $id_to_name->{$id};
            next unless defined $value;
            $new->value ($field, $value);
        }
        push @objects, $new;
    }
    return @objects;
}

=item read_into ([WHERE_CLAUSE])

Re-populate the existing object based on a new query I<QUERY>.  Basically, we
run a new B<read ()> with the same arguments as before, and check the number of
results.  If we only get one entry, then we re-populate the current item based
on these results.  If we get multiple entries, or no entries, then we die.

Returns the request ID (field 1) of the new entry on success, dies on failure.

=cut

sub read_into {
    my ($self, $where, @rest) = @_;
    my $logger  = $self->logger_or_die;

    my @results = $self->read ($where, 'max' => 2);

    my $number_of_results = scalar @results;
    if ($number_of_results > 1) {
        $logger->logdie ("read_into: more than one result found");
    } elsif ($number_of_results < 1) {
        my $error = $self->session_or_die->error;
        $logger->logdie ("read_into: no matches found ($error)");
    } else {
        $logger->debug ('one match on read_into');
        $self->clone ($results[0]);
    }

    return $self->request_id;
}

=item save ()

Saves the item to the Remedy database.  This is basically a wrapper function
for B<insert ()> and B<update ()>; we decide which to use based on whether or
not we have a request ID (field 1) in the current object.

=cut

sub save {
    my ($self, @args) = @_;
    return defined $self->request_id ? $self->update (@args)
                                     : $self->insert (@args);
}

=item update ()

Updates an existing item in the Remedy database.  This generally means running
B<SetEntry ()> through the B<session> object, and then re-reading the object
with B<read_into ()> in order to pick up any information that was added by
workflow on the server end.  Returns 1 if successful, undef if there is nothing
to update, and dies on many forms of failure.

Again, note that we do not check ahead of time to see if the item is already in
the database.  If this is a concern, use B<save ()>.

=cut

sub update {
    my ($self) = @_;

    my $formdata = $self->formdata_or_die;
    my $logger   = $self->logger_or_die;
    my $name     = $self->name_or_die;
    my $session  = $self->session_or_die;
    my $values   = $self->values;

    my $req_id = $self->request_id;
    $logger->logdie ('cannot insert without request ID') unless $req_id;

    my @fields = $self->fields_values ();
    return unless scalar @fields;

    my $rv = eval { $session->SetEntry ($name, $req_id, \@fields) };
    $logger->logdie ("failed to update existing entry: $@") unless $rv;

    # Re-read to make sure all of the workflow has fired.
    ## Rre-read the entry from the database, in order to pull information
    ## that was set by the workflow.
    unless (my $rid = $self->read_into) {
        $logger->logdie ("could not re-read object into self: $@");
    }

    return $rv;
}

=back

=cut

##############################################################################
### Object Data Manipulation #################################################
##############################################################################

=head2 Object Data Manipulation

These items generally wrap B<Remedy::FormData> functions.

=over 4

=item data_to_human (FIELD, VALUE)

Converts data stored in the database into a human-readable version.

=over 4

=item enum

Converts the integer value to the human-readable one stored in the database.

=item time

Converts the integer timedate value from the database into a human-readable
date string, using B<format_date ()> (see B<Remedy::FormData::Utility>).

=item (all others)

No changes.

=back

=cut

sub data_to_human {
    my ($self, $field, $value) = @_;
    return unless (defined $value && defined $field);

    my $human = undef;
    if ($self->field_is ($field, 'enum')) {
        my %hash = $self->field_to_enum ($field);
        $human = defined $hash{$value} ? $hash{$value}
                                       : '*BAD VALUE*';

    } elsif ($self->field_is ($field, 'time')) {
        $human = $self->format_date ($value);
    } else {
        $human = $value;
    }

    if ($value ne $human) {
        $self->logger_or_die->all (sprintf ("d2h %s to %s",
            _printable ($value, 20), _printable ($human, 30)));
    }
    return $human;
}

=item enum_value (FIELD [, VALUE])

Get or set the underlying value for I<FIELD> in B<values>, where I<FIELD>
is an I<enumerated> field type, using the actual enumerated values rather than
the integers.  That is, instead of:

    $entry->value ('Status', 4);

We could instead say: say:

    $entry->enum_value ('Status', 'Resolved');

Returns the current value on success, dies on failure.

=cut

sub enum_value {
    my ($self, $field, $text) = @_;
    my $logger = $self->logger_or_die;

    my $name_to_enum = $self->formdata_or_die->name_to_enum;
    my $enum_to_text = $name_to_enum->{$text};

    my %enum_text_to_value = reverse %{ $enum_to_text };
    if (! defined $text) {
        my $value = $self->value ($field);
        return $enum_to_text->{$value};
    } else {
        my $value = $enum_text_to_value{$text};
        $logger->logdie ("no enum value match in '$field' for '$text'")
            unless defined $value;
        return $self->value ($field, $value);
    }
}

=item fields ()

Returns a hash mapping the field names to field IDs in the underlying form data.

=cut

sub fields { %{ shift->formdata_or_die->name_to_id } }

=item field_is (NAME, TYPE)

Checks if the field type for field name I<NAME> is I<TYPE>.  Returns 1 if it
matches, 0 otherwise.  Used as:

=cut

sub field_is {
    my ($self, $field, $type) = @_;
    return $self->field_type ($field) eq lc $type ? 1 : 0;
}

=item field_to_enum (NAME)

Returns a hash mapping the internal to human values of field name I<NAME>.
Based on B<name_to_enum>.  Returns undef if there is no mapping.

=cut

sub field_to_enum {
    my ($self, $field) = @_;
    my $href     = $self->formdata_or_die->name_to_enum;
    my $values   = $href->{$field};
    return unless defined $values && ref $values;
    return %{$values};
}

=item fields_not_empty ()

Returns a an array of field names that are not empty in the current object.

=cut

sub fields_not_empty {
    my ($self, %args) = @_;
    my $values = $self->values;

    my @fields = ();
    foreach my $name (keys %{$values}) {
        my $value = $$values{$name};
        # next unless exists $$values{$name};
        next unless defined $$values{$name};
        push @fields, $name;
    }
    return @fields;
}

=item fields_to_match ()

Based on the contents of B<fields_only>, figure out which field IDs we want to
call for on a read.  If the contents are empty, we will request all fields;
otherwise, we will request the fields listed in B<fields_only>, plus the
request ID field (field 1).

Returns an array (or arrayref, depending on context) containing

Returns an array of field IDs that the current object wants to search for,
based on the names contained in B<fields_only ()>.

=cut

sub fields_to_match {
    my ($self) = @_;
    my $only = $self->fields_only;
    my @ids = scalar @$only ? (1, $self->names_to_ids (@$only))
                            : keys %{$self->formdata_or_die->id_to_name};
    return wantarray ? @ids : \@ids;
}


=item field_type (NAME)

Returns the field type for the field name I<NAME>.  These types are documented
in B<Remedy::FormData>.  Returns undef if there is no type (which would
probably be a bad thing).

=cut

sub field_type {
    my ($self, $field) = @_;
    my $href = $self->formdata_or_die->name_to_type or return;
    return lc $href->{$field};
}

=item fields_values ()

Given the existing entry, return an array of (field name, field value) pairs
for everything in B<values>.  This is used by most of the database functions.

=cut

sub fields_values {
    my ($self, %args) = @_;
    my $values = $self->values;

    my @fields = ();
    foreach my $name (keys %{$values}) {
        my $id = $self->name_to_id ($name);
        my $value = $$values{$name};
        next unless exists $$values{$name};
        next unless $id;
        push @fields, $id, $value;
    }
    return @fields;
}

=item human_to_data (FIELD, VALUE)

Converts the human-readable version of I<VALUE> into the machine-parsable data
version, based on the field I<FIELD>.  This has different options depending on
the field type:

=over 4

=item enum

Looks to end up with an integer value, corresponding to the potential values
enumerated in the database, so we should look at those possible values for a
match.  First attempts to convert I<VALUE> to its numeric value; if that fails,
then we will see we already are a valid numeric value; and if *that* fails,
then there is no valid data and we we will return undef.

=item time

Looks to end up with an integer corresponding to seconds-since-epoch.  If we
are already an integer, we will just use that; otherwise, we will try to use
B<Date::Parse::str2time ()> to convert the string back to to the appropriate
integer.

=item (all others)

Just whatever we offered, there's no parsing to be done.

=back

Returns the parsed data, or undef on failure.

=cut

sub human_to_data {
    my ($self, $field, $human) = @_;
    return unless (defined $human && defined $field);
    my $logger = $self->logger_or_die;

    my $value = undef;
    if      ($self->field_is ($field, 'enum')) {
        my %hash = reverse $self->field_to_enum ($field);
        if      (exists $hash{$human}) {
            $value = $hash{$human}
        } elsif (exists {reverse %hash}->{$human}) {
            $value = $human;
        } else {
            $logger->debug ("invalid value for '$field': $human");
            return;
        }
        $value = exists $hash{$human} ? $hash{$human} : $human;

    } elsif ($self->field_is ($field, 'time')) {
        if      ($human =~ /^\d+/) {    # this is a 'time' string already
            $value = $human;
        } elsif (my $time = str2time ($human)) {
            $value = $time;
        } else {
            $logger->debug ("could not parse date string: '$human'");
            return;
        }

    } else { $value = $human }

    if ($value ne $human) {
        $logger->all (sprintf ("h2d %s to %s",
            _printable ($human, 30), _printable ($value, 20)));
    }
    return $value;
}

=item id_to_name (ID)

Converts the field ID I<ID> into its matching field name.  Uses B<ids_to_names>.

=cut

sub id_to_name { (ids_to_names (@_))[0] }

=item ids_to_names (ID [, ID [, ID [...]]])

Converts an array of field IDs I<ID> into field names.  Dies if any of the
IDs do not have a corresponding name.  Returns an array of field names.

=cut

sub ids_to_names {
    my ($self, @ids) = @_;
    my $id_to_name = $self->formdata_or_die->id_to_name;
    my @names;
    foreach my $id (@ids) {
        my $name = $id_to_name->{$id} || $self->logger_or_die->logdie
            ("no field name corresponding to '$id'\n");
        push @names, $name;
    }
    return @names;
}

=item name_to_id (NAME)

Converts the filed name I<NAME> into its matching field ID.  Uses
B<names_to_ids>.

=cut

sub name_to_id { (names_to_ids(@_))[0]; }

=item names_to_ids (NAME [, NAME [, NAME [...]]])

Converts an array of field names I<NAME> into field IDs.  Dies if any of the
names do not have a corresponding ID.  Returns an array of field IDs.

=cut

sub names_to_ids {
    my ($self, @names) = @_;
    my $formdata = $self->formdata_or_die;

    my @ids = ();
    my $name_to_id = $formdata->name_to_id;
    foreach my $name (@names) {
        my $id = $name_to_id->{$name} || $self->logger_or_die->logdie
            ("no field ID corresponding to '$name'\n");
        push @ids, $id;
    }
    return wantarray ? @ids : \@ids;
}

=item schema ()

Returns a hash mapping the field IDs to field names in the underlying form data.

=cut

sub schema { reverse shift->fields }

=item value (FIELD [, VALUE])

Get or set the underlying value for I<FIELD> in B<values>.  This is used as a
wrapper to ensure that we are only writing to valid fields.  Returns the
current value on success, dies on failure.

=cut

sub value {
    my ($self, $field, $value) = @_;
    my $logger   = $self->logger_or_die;
    my $name_to_id = $self->formdata_or_die->name_to_id;
    $logger->logdie (sprintf ("no such field '%s' in '%s'", $field,
        $self->name_or_die)) unless defined $name_to_id->{$field};

    if (exists $_[2]) { $self->values ($field, $value) }
    return $self->values ($field);
}

=item validate (NAME)

Confirms that field name I<NAME> exists.  Returns 0 on success, 1 otherwise.

=cut

sub validate {
    my ($self, $field) = @_;
    my %href = $self->fields;
    return exists $href{$field} ? 1 : 0;
}

=back

=cut

##############################################################################
### Miscellaneous ############################################################
##############################################################################

=head2 Miscellaneous Functions

=over 4

=item as_string ()

Imported from B<Remedy::FormData::Utility>.

=item create_where_clause (FIELDS_ARRAY)

Creates a WHERE clause.  I<FIELDS_ARRAY> specifies which fields we will be
searching through.  This is best explained through an example.  If the current
contents of B<values> looks like this:

    Request ID  4567          1     integer
    FIELD1      testing       5     character
    FIELD2      testing2      9     character
    FIELD3      testing3    421     character
    FIELD4      <NULL>      422     character

...and we pass in (I<FIELD1>, I<FIELD3>), then the function will return:

    'FIELD1' = "testing" AND FIELD2 = "testing2"

If we pass (I<FIELD4>), we will get:

    'FIELD4' == NULL

If I<FIELDS_ARRAY> is empty, then we will return a clause based solely
on the request ID (field 1):

    'Request ID' = "4567"

=cut

sub create_where_clause {
    my ($self, @select) = @_;
    my $formdata = $self->formdata_or_die;
    my $logger   = $self->logger_or_die;

    push @select, $self->id_to_name (1) unless scalar @select;

    my @terms;
    foreach my $field (@select) {
        my $id = $self->name_to_id ($field);
        $logger->logdie ("no ID for field name '$field'") unless $id;
        my $value = $self->value ($field);
        push @terms, $self->limit_string ($field, $value);
    }
    return join (" AND ", @terms);
}

=item format_date ()

Imported from B<Remedy::FormData::Utility>.

=item format_text ()

Imported from B<Remedy::FormData::Utility>.

=item format_text_field ()

Imported from B<Remedy::FormData::Utility>.

=item limit_integer_compare (ID, INT, MODIFIER)

Creates a limitation string (e.g. for B<limit_string>) for an integer value
I<INT>.  I<MODIFIER> is used to decide on the return value.  Possible values of
I<MODIFIER>:

    +           'ID' > INT
    -           'ID' < INT
    +=          'ID' >= INT
    -=          'ID' <= INT
    (default)   'ID' = INT

=cut

sub limit_integer_compare {
    my ($self, $id, $int, $mod) = @_;
    return "'$id' <= $int" if $mod eq '-=';
    return "'$id' >= $int" if $mod eq '+=';
    return "'$id' < $int"  if $mod eq '-';
    return "'$id' > $int"  if $mod eq '+';
    return "'$id' = $int";
}

=item limit_string (NAME, VALUE)

Creates a database 'limit string', used as a single component of a database
WHERE clause (for use e.g. with B<create_where_clause>).  I<NAME> is the field
name (which is converted to field ID I<ID>), and I<VALUE> is its value.

The return value depends the inputs:

=over 2

=item I<VALUE> is undefined

Return "'I<ID>' == NULL"

=item field type of I<FIELD> is 'enum'

First, we pull out the opening characters from I<VALUE>, for use with
B<limit_integer_compare>; this gives us I<MOD> and I<DATA>.  This table
summarizes how this works:

    VALUE             MOD     DATA
    Resolved    =>          Resolved
    +Resolved   =>     +    Resolved
    -=Resolved  =>    -=    Resolved

Then we choose what to return based on I<DATA>:

=over 2

=item I<DATA> is numeric

Return B<limit_integer_compare (I<ID>, I<DATA>, I<MOD>)>

=item I<DATA> matches a valid enumerated entry I<CONVERT> 

Return B<limit_integer_compare (I<ID>, I<CONVERT>, I<MOD>)>

=item neither

Return '1=2' (which will never match).

=back

=item field type of I<FIELD> is 'time'

As with the I<enum> type, convert I<VALUE> to I<MOD> and I<DATA>.  Then we
choose what to return based on I<DATA>:

=over 2

=item I<DATA> is numeric

Return B<limit_integer_compare (I<ID>, I<DATA>, I<MOD>)>

=item I<DATA> is a string parseable by B<Date::Parse> into I<CONVERT>

Return B<limit_integer_compare (I<ID>, I<CONVERT>, I<MOD>)>

=item neither

Return '1=3' (which will never match).

=back

=item default

If I<VALUE> is '%', then return nothing - we won't be restricting the search
based on this value.

Otherwise, escape I<VALUE> and return "'I<ID>' = \"I<VALUE>\".

=back

=cut

sub limit_string {
    my ($self, $field, $value, %args) = @_;
    my $id = $self->name_to_id ($field);
    return unless $id;
    return "'$id' == NULL" unless defined $value;

    ## 'enum' fields
    if ($self->field_is ($field, 'enum')) {
        my ($mod, $human) = ($value =~ /^([+-]?=?)?(.*)$/);
        my %hash = reverse $self->field_to_enum ($field);

        my $data;
        if    ($human =~ /^\d+/)      { $data = $human        }
        elsif (defined $hash{$human}) { $data = $hash{$human} }
        else                          { return '1=3'          }

        return $self->limit_integer_compare ($id, $data, $mod);

    ## 'time' fields
    } elsif ($self->field_is ($field, 'time')) {
        my ($mod, $timestamp) = ($value =~ /^([+-]?=?)?(.*)$/);

        my $data;
        if ($timestamp =~ /^\d+$/)               { $data= $timestamp }
        elsif (my $time = str2time ($timestamp)) { $data = $time     }
        else                                     { return '1=2'      }

        return $self->limit_integer_compare ($id, $data, $mod);

    ## all other field types
    } else {
        return if $value eq '%';
        $value =~ s/"/\\\"/g;
        return "'$id' = \"$value\"" if defined $value;
    }
}

=item request_id ([ID])

Manage the request ID (field 1) of the current entry.  If I<ID> is offered,
then set its value to that and return that value; otherwise, just return the
existing value.

=cut

sub request_id {
    my ($self, @rest) = @_;
    return $self->value ($self->id_to_name (1), @rest);
}

=back

=cut

##############################################################################
### Additional Accessors #####################################################
##############################################################################

=head2 Additional Accessors

=over 4

=item logger ()

Pulls the logger object from the parent B<session>.

=cut

sub logger { shift->session_or_die->logger }

=item cache_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<cache ()>.

=cut

sub cache_or_die { $_[0]->or_die (shift->cache, "no cache", @_) }

=item formdata_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<formdata ()>.

=cut

sub formdata_or_die { $_[0]->or_die (shift->formdata, "no formdata", @_) }

=item logger_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<logger ()>.

=cut

sub logger_or_die { $_[0]->or_die (shift->logger, "no logger", @_) }

=item name_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<name ()>.

=cut

sub name_or_die { $_[0]->or_die (shift->name, "no name", @_) }

=item session_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<session ()>.

=cut

sub session_or_die { $_[0]->or_die (shift->session, "no session", @_) }

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

### _printable (STRING, LENGTH)
# Make a nicely printable version of a string, for debugging purposes.
sub _printable {
    my ($string, $length) = @_;
    $string =~ s/\n/ /g;

    my $format = "%${length}.${length}s";
    if (length ($string) > $length) {
        my $shorter = $length - 3;
        $format = "%${shorter}.${shorter}s...";
    }
    return sprintf ($format, $string);
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 TODO

Move large portions of B<Remedy::Form> into this function, and/or
B<Remedy::FormData::Utility>.

=head1 REQUIREMENTS

B<Remedy::Session>, B<Remedy::FormData>, B<Remedy::FormData::Utility>

=head1 SEE ALSO

Remedy(8), Remedy::Form(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

Based on B<Stanford::Remedy::Form> by Adam Lewenberg <adamhl@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
