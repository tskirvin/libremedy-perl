package Remedy::Form;
our $VERSION = "0.50";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form - get, parse, and save data from Remedy forms

=head1 SYNOPSIS

    use Remedy::Form;
    [...]

This is meant to be used as a template for other modules; please see the
man pages listed under SEE ALSO for more usage information.

=head1 DESCRIPTION

Remedy::Form implements a consistent set of shared functions used by the
sub-form modules (eg B<Remedy::Form::People>, B<Remedy::Form::SupportGroup>,
B<Remedy::Form::Generic>), so that they can tie into the central B<Remedy>
system.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;

use Class::Struct;
use Date::Parse;
use Exporter;
use Lingua::EN::Inflect qw/inflect/;
use Remedy::Form::Generic;  
use Remedy::Form::Utility;
use Remedy::Session::Form;

our @EXPORT    = qw//;
our @EXPORT_OK = qw/init_struct/;
our @ISA       = qw/Remedy::Form::Utility Exporter/;

## Registered table names - why yes, it's global
use vars qw/%REGISTER/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=head2 B<Remedy::Form::*> Sub-Classes

The interesting work of B<Remedy::Form> is performed by its sub-classes, such
as B<Remedy::Form::People> or B<Remedy::Form::Generic>.  These functions are
used to initialize and access those sub-classes from a consistent location.

=over 4

=item init_struct (CLASS [, SHORTNAME [, EXTRAHASH]])

Registers a new B<Remedy::Form::*> sub-class, and initializes its inheritance
with a number of B<Class::Struct> accessors.  I<CLASS> is the name of the
class; it is accessed using B<form ()> and B<registered ()> using the name
I<SHORTNAME> (defaults to the class name if not offered).

The new sub-class is based around a B<Class::Struct> object, with the following
accessors:

=over 4

=item parent (B<Remedy>)

Manages the parent B<Remedy> object, which contains configuration information,
the actual database connection, and so forth.  Set with B<init ()>.  Most
functions require an active database connection.

=item remedy_form (B<Remedy::Session::Form>)

Manages the object used to get/set database values.  Set with B<new ()> or
B<new_from_form ()>.

=item table ($)

Manages the database table name for each object; contains values like
I<CTM:Person>.  Note that most B<Remedy::Form::*> sub-modules override this
function, making it read-only.

=item key_field (%)

A map of function names to fields, pulled from the per-module B<field_map ()>
function.  This is used to convert data back and forth between the per-object
B<Class::Struct> accessors (see below) and their database representations.

=item (per-object B<Class::Struct> accessors) ($)

Adds one accessor of type '$' for each key from the B<field_map ()> function.
This data will be converted back and forth with the B<key_field ()> hash (see
above) at read/write.

=item (extras)

We can add extra accesors through I<EXTRAHASH>, which is passed into the struct
initialization directly.  That is, if you wanted to add an additional 'debug'
field, you might pass in:

    init_struct (__PACKAGE__, 'shortname', 'debug' => '$');

=back

Returns a two element array: the class B<Remedy::Form>, and the newly generated
struct.  Thus, it is used to set the object inheritance at module load, as so:

    use Remedy::Form qw/init_struct/;
    our @ISA = init_struct (__PACKAGE__, 'shortname');

This function is exportable, but not exported by default.

=cut

sub init_struct {
    my ($class, %extra) = @_;
    our $new = $class . "::Struct";

    my ($human) = ($class =~ /^Remedy::Form::(.*)$/);

    my %fields;
    my %map = $class->field_map;
    foreach (keys %map) { $fields{$_} = '$' }
    struct $new => {'remedy_form' => 'Remedy::Session::Form',
                    'parent'      => 'Remedy',
                    'table'       => '$',
                    'key_field'   => '%', %extra, %fields};

    ## Register the class names
    __PACKAGE__->register ($class, $class);
    __PACKAGE__->register ($human, $class);
    if (my $table = $class->table) { __PACKAGE__->register ($table, $class) }

    return (__PACKAGE__, $new);
}

=item register ()

=cut

sub register {
    my ($self, $human, $class) = @_;
    return %REGISTER unless defined $human;
    return $REGISTER{lc $human} unless defined $class;
    $REGISTER{lc $human} = ref $class ? $class : [$class];
    return $class;
}

=item registered ()

Returns an array of registered classes.

=cut

sub registered { grep { lc $_ ne 'generic' } keys %REGISTER }

=item form (FORM_NAME, ARGHASH)

Finds the appropriate sub-class to manage the sub-form I<FORM_NAME>.
If this name has been registered with B<init_struct ()> - ie, it's a
human-usable alias - then we will use that class name; if not, we will use
B<Stanford::Form::Generic>, and set the form name appropriately.

Once found, we create and return an empty object using B<new ()> with
appropriate options.  Returns undef on failure.

Must either have an existing parent connection (if invoked from an existing
object), or the 'db' argument pointing at a valid B<Remedy> object in
I<ARGHASH>.

=cut

sub form {
    my ($self, $name, %args) = @_;
    my $parent = $self->parent_or_die (%args, 
        'text' => 'need a Remedy parent object');
    my $logger = $parent->logger_or_die;

    my @return;
    if (my $class = $REGISTER{lc $name}) {
        my @classes = ref $class ? @$class : $class;
        $logger->debug (inflect (sprintf 
            ("NUM(%d) associated PL_N(class) PL_V(was) found for '%s'", 
            scalar @classes, $name)));
        foreach my $class (@classes) {
            my $table = $class->table;
            $logger->debug ("form for '$name' is '$class' (table '$table')");
            push @return, $class->new ('table' => $table, 'parent' => $parent);
        }
    } else {
        $logger->debug ("creating a generic form for '$name'");
        my $form = Remedy::Form::Generic->new ('table' => $name, 
            'parent' => $parent);
        return unless $form;
        $logger->debug ("setting table name for generic form");
        $form->table ($name);
        push @return, $form;
    }
    $logger->all (inflect (sprintf 
        ("NUM(%d) PL_N(form) returned", scalar @return)));
    return @return;
}

=item form_names ()

=cut

sub form_names {
    my ($self, $name) = @_;
    my @return;
    if (my $array = $REGISTER{lc $name}) { 
        foreach (@$array) { push @return, $_->table }
    } else { 
        push @return, $name 
    }
    return @return;
}

=item new (ARGHASH)

Creates and returns a new B<Remedy::Form> object.  Requires two arguments from 
the hash I<ARGHASH>:

=over 4

=item db => B<REMEDY>

Use the B<Remedy> object I<REMEDY> as a parent connection (see B<parent ()>).
Note that this object must already be connected and active.

=item table => B<TABLE_NAME>

The table name on the Remedy server.

=back

Returns the new object, or undef on failure (after sending some warnings with
<warn_level ()>.

=cut

sub new {
    my ($class, %args) = @_;
    my $parent = $class->parent_or_die (%args, 
        'text' => 'need a Remedy parent object');
    my $logger  = $parent->logger_or_die;

    # Create the object
    my $table = $args{'table'} || $logger->logdie ('no table offered');

    return _init ($class, undef, $parent, $table);
}

=back

=cut

##############################################################################
### Accessors ################################################################
##############################################################################


=head2 Accessors

=over 4

=item related_by_id (TABLE, ID, ARGHASH)

=cut

sub related_by_id {
    my ($self, $table, $field, $id, %args) = @_;
    my $parent = $self->parent_or_die;
    my $logger = $self->logger_or_die;
    unless ($table) {
        $logger->debug ('relate_by_id - no table offered');
        return;
    }
    unless ($id) {
        $logger->debug ('relate_by_id - no ID offered');
        return;
    }
    $logger->debug (sprintf ("read (%s, %s => %s)", $table, $field, $id));
    return $parent->read ($table, $field => $id, %args);
}

=item get (FIELD)

=cut

sub get {
    my ($self, $field) = @_;
    my $form = $self->remedy_form || $self->error ('no form');
    if (my $key = $self->key_field ($field)) {
        return $self->$key;
    } else {
        return $self->data_to_human ($field, $form->get_value ($field));
    }
}

=item set (FIELD, VALUE [, FIELD, VALUE [, FIELD, VALUE [...]]])

Takes a number of I<FIELD>/I<VALUE> pairs 

=cut

sub set {
    my ($self, %fields) = @_;
    my $form   = $self->remedy_form;
    my $logger = $self->logger_or_die;
    my $table  = $self->table;

    my %todo;

    my %href = $self->fields;

    foreach my $field (keys %fields) {
        unless (exists $href{$field}) {
            return "no such field '$field' in '$table'";
        }

        my $value = $fields{$field};
        if (defined $value) { 
            my $data = $self->human_to_data ($field, $value);
            return "invalid value '$value' for '$field'" unless $data;
            $todo{$field} = $data;
        } else { 
            $todo{$field} = undef
        }
    }

    
    $logger->debug (sprintf ("setting fields: %s", join (', ', keys %todo)))
        if scalar keys %todo;

    foreach my $f (keys %todo) {
        my $human = defined $todo{$f} ? $todo{$f} : 'INVALID';
        $self->remedy_form->set_value ($f, $todo{$f});
        if (my $key = $self->key_field ($f)) {
            $self->$key ($todo{$f});
        }
    }
    
    return;
}

=item data_to_human (FIELD, VALUE)

Converts data stored in the database into a human-readable version.  

=over 4

=item enum

Converts the integer value to the human-readable one stored in the database.

=item time

Converts the integer timedate value from the database into a human-readable
date string, using B<format_date ()> (see B<Remedy::Form::Utility>).

=item (all others)

=back

=cut

sub data_to_human {
    my ($self, $field, $value) = @_;
    return unless (defined $value && defined $field);
    my $logger = $self->logger_or_die;

    my $human = undef;
    if      ($self->field_is ('enum', $field)) {
        my %hash = $self->field_to_values ($field);
        $human = defined $hash{$value} ? $hash{$value} 
                                       : '*BAD VALUE*';

    } elsif ($self->field_is ('time', $field)) {
        $human = $self->format_date ($value);
    } else {
        $human = $value;
    }

    if ($value != $human) { 
        $logger->all (sprintf ("d2h %s to %s", 
            _printable ($value, 20), _printable ($human, 30)));
    }
    return $human;
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
    if      ($self->field_is ('enum', $field)) {
        my %hash = reverse $self->field_to_values ($field);
        if      (exists $hash{$human}) { 
            $value = $hash{$human} 
        } elsif (exists {reverse %hash}->{$human}) {
            $value = $human;
        } else { 
            $logger->debug ("invalid value for '$field': $human");
            return;
        }
        $value = exists $hash{$human} ? $hash{$human} : $human;

    } elsif ($self->field_is ('time', $field)) {
        if      ($human =~ /^\d+/) {    # this is a 'time' string already
            $value = $human;
        } elsif (my $time = str2time ($human)) {
            $value = $time;
        } else {
            $logger->debug ("could not parse date string: '$human'");
            return;
        }

    } else { $value = $human }

    if ($value != $human) { 
        $logger->all (sprintf ("h2d %s to %s", 
            _printable ($human, 30), _printable ($value, 20)));
    }
    return $value;
}

=back

=head2 Database Functions

All functions in this class that take the argument hash I<ARGHASH> honor
the option '':

=over 4

=item parent I<object>

I<object> is a parent B<Remedy> object that contains a connection to
the remedy database.  If the option is not offered, then we will use the value
of B<parent ()> from the offered object as the parent.

=back

For all of these functions, if no parent is set then we will throw an
exception.

=over 4

=item limit_basic (ARGHASH)

Gathers the components of a I<limit_ref> for B<read()>. Looks at each
field listed in B<fields ()>, and creates an array of limit components

Follows these arguments in the hash I<ARGHASH>:

=over 4

=item all I <anything>

=item ID I<number>

If this is offered, then we will only search for this item - that is, a search
of "'1' == \"I<number>\"".  

=item extra I<arrayref>

Adds the components of I<arrayref> into the array of limit components.  This
makes it easy to 

=back

=item enum

=over 4

=item +

'ID' > VALUE

=item -

'ID' < VALUE

=item +=

'ID' >= VALUE

=item -=

'ID' <= VALUE

=item (normal)

'ID' = VALUE

=back

=item time I<STRING>

Parses I<STRING> with B<Date::Parse::str2time ()> to get a valid Unix
timestamp.  

Understands the concept of the '+/-' prefix.  

=over 4

=item +

'ID' >= TIMESTAMP

=item -

'ID' < TIMESTAMP

=item (normal)

'ID' == TIMESTAMP

=back

=item other 

All other 

Returns an array of limiting components

=cut

sub limit {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die;
    my $logger = $parent->logger_or_die;

    if (my $id = $args{'ID'}) { return "'1' == \"$id\"" }
    if ($args{'all'}) { return '1=1' }

    _args_trace ($logger, 'before limit_pre()', %args);
    %args = $self->limit_pre (%args);
    _args_trace ($logger, 'after  limit_pre()', %args);

    my @limit;
    if (my $extra = $args{'extra'}) { 
        push @limit, ref $extra ? @$extra : $extra;  
        delete $args{'extra'};
    }

    my %fields = $self->fields (%args);
    foreach my $field (keys %fields) {
        next unless exists $args{$field};

        ## Create the limit string
        my @args = ($fields{$field}, $field, $args{$field});
        my $limit = _limit_string ($self, @args);
        next unless defined $limit;

        push @limit, $limit;
        $logger->all ("adding limit: $limit");
    }

    $logger->all ('limit_post ()');
    %args = $self->limit_post (@limit);

    $logger->debug ("limit: ", join (', ', @limit));
    @limit;
}

=item reload ([FORM])

=cut

sub reload {
    my ($self, $form) = @_;

    # Set the per-object accessors
    my %map = $self->field_map;
    foreach my $key (keys %map) {
        my $field = $map{$key};
        my $value = defined $form ? $form->get_value ($field)
                                  : $self->remedy_form->get_value ($field);
        $self->$key ($self->data_to_human ($field, $value));
    }

    return $self;
}

=item save (ARGHASH)

Attempts to save the contents of this object into the database.

If
successful, reloads the newly-created item and returns it; on failure, sets an
error in the parent object and returns an error.

Returns an error message on failure, or undef on success.

=cut

sub save {
    my ($self, %args) = @_;
    my $logger = $self->parent_or_die->logger_or_die;

    ## Make sure all data is reflected in the form
    my $form = $self->remedy_form or return 'no form';

    ## Make sure the data is consistent
    $self->reload;

    $logger->debug ("saving data from $form");

    { 
        local $@;
        my $return = eval { $form->save };
        unless ($return) { 
            $logger->error ("could not save: $@");
            return "could not save: $@";
        }
    }

    ## Once again make sure the data is consstent
    $self->reload;

    return;
}

=item new_from_form (ENTRY, ARGHASH)

Takes information from I<ENTRY> - the output of a single item from a
B<Remedy::select ()> call - and creates a new object in the appropriate class.

Uses B<field_map ()> to map fields to function names so we can actually move
the information over.

=over 4

=item table

=item db

=back

Returns the object on success, or undef on failure.

=cut

sub new_from_form {
    my ($self, $form, %args) = @_;
    my $class = ref $self || $self;

    return unless ($form && ref $form);
    return unless (my $table = $args{'table'} || $self->table);

    return _init ($class, $form, $self->parent_or_die (%args), $table);
}

=item read (PARENT, ARGHASH)

Reads from the database in the B<Remedy> object I<PARENT>, based on the
arguments in the argument hash I<ARGHASH>:

=over 4

=item count I<count_ref>

How many entries to return.  No default.

=item limit I<limit_ref>

Which entries to select.  If I<limit_ref> is offered, it is used; otherwise,
all items in the argument hash are passed to B<limit ()> to make an appropriate
array.

=back

Returns an array of objects, created with B<new_from_form ()>. Please see
Remedy::Database(8) for more details on the B<select ()> call used
to gather the data.

If invoked in a scalar context, only returns the first item.

=cut

=item create (ARGHASH)

[...]

=cut

sub create {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die (%args);
    my $form = $self->remedy_session_form ($self->table);
    return $self->new_from_form ($form, 'table'  => $self->table, 
                                        'parent' => $parent);
}

=back

=cut

##############################################################################
### Helper Functions #########################################################
##############################################################################

=head2 Helper Functions

=over 4

=item fields ()

Returns an inverted version of B<schema ()> - that is, a hash with keys
corresponding to the field names in this form, and values corresponding to
their internal reference IDs.

=cut

sub fields { my %schema = shift->schema (@_);  return reverse %schema; }

=item remedy_session_form (TABLE_NAME, ARGHASH)

Creates and returns a B<Remedy::Session::Form> object associated with the table
name I<TABLE_NAME>.

safely - meaning that warnings are
turned off temporarily and the whole block is run as an 'eval'.  Returns the
object on success, or undef on failure; if there is an error message, it is
returned as '$@'.

TODO: when we move these classes into the same library set and rename it to
B<Remedy::Form::Raw> or somesuch, we'll access that module here.

=cut

sub remedy_session_form {
    my ($self, $table_name, %args) = @_;
    my $session = $self->session_or_die (%args);
    my $logger  = $self->logger_or_die  (%args);

    return unless (defined $session && defined $table_name);

    local $@;
    my $form = eval { Remedy::Session::Form->new ('session' => $session,
        'name' => $table_name) };
    if ($@) { 
        $logger->debug ("no such form '$table_name' ($@)");
        return;
    } 
    return $form;
}

=item read (TABLE, ARGHASH)


=cut

sub read {
    my ($self, $table, %args) = @_;
    my $parent = $self->parent_or_die ('need parent to read', 0, %args);
    my $session = $parent->session_or_die;
    my $logger  = $parent->logger_or_die;
    return unless $table;

    my @return;

    my @forms = $self->form ($table);
    unless (scalar @forms) { 
        $logger->warn ("no matching tables for '$table'");
        return;
    }

    foreach my $form (@forms) { 
        ## Figure out how we're limiting our search
        my $limit = join (" AND ", $form->limit (%args));
        unless ($limit) { 
            $logger->debug ("no search limits, skipping");
            next;
        }

        my $table_name = $form->table;
        my $remedy_form = $self->remedy_session_form ($table_name);

        ## Perform the search
        $logger->debug ("read_where ($table_name, $limit)");
        my @entries = $remedy_form->read_where ($limit);
        $logger->debug (sprintf ("%d entr%s returned", scalar @entries, 
            scalar @entries == 1 ? 'y' : 'ies'));

        foreach my $entry (@entries) {
            $logger->debug (sprintf ("new_from_form (%s)", $table));
            push @return, $form->new_from_form ($entry, 
                'table' => $self->table, 'parent' => $parent);
        }
    }
    return wantarray ? @return : $return[0];
}

=item insert ()

Just calls B<save ()>

=cut

sub insert { shift->save (@_) } # FIXME: check to make sure it's not already there

=item update ()

Just calls B<save ()>

=cut

sub update { shift->save (@_) } # FIXME: check to make sure it is already there

=item delete ()

Not yet written.

=cut

sub delete { return }       # not yet written

=item schema ()

Returns a hash of field IDs and their human-readable names.  This is used by
B<debug_text ()> to make a human-readable debug field, as well as by
B<field_to_id ()> and B<id_to_field ()>.

=cut

sub schema {
    my ($self) = @_;
    my $formdata = $self->pull_formdata ();
    my $href = $formdata->get_fieldName_to_fieldId_href ();
    return reverse %{$href};
}

=back

=head2 Functions to Override

While these may functions have vaguely-sensible defaults, they are meant to be
over-ridden by sub-classes, and are documented here primarily to show the
intent.

=over 4

=item field_map ()

Returns a hash containing field-name to accessor-function-name pairs - that
is, it maps the 'ID' field to the 'id' accessor.

The default is an empty hash.

=cut

sub field_map        { () }


=item limit_pre (ARGHASH)

=item limit_post (ARGHASH)

Returns a string that is used in B<select ()> functions and the like to limit
the number of affected entries.  This can be over-ridden to allow for more
complicated queries.

The default is to call B<limit_basic ()> with the same arguments as we were
passed.

=cut

sub limit_pre  { shift; @_ }
sub limit_post { shift; @_ }

=item print ()

Creates a printable string summarizing information about the object.  Based
on invocation type, returns either an array of lines that you can print, or a
single newline-delimited string.

Defaults to use B<debug_pretty ()>.

=cut

sub print { shift->debug_pretty (@_) }

=item field_to_values ()

=cut

sub field_to_values {
    my ($self, $field) = @_;
    my $formdata = $self->pull_formdata ();
    my $href = $formdata->get_fieldName_to_enumvalues_href () or return;
    my $values = $href->{$field};
    return unless defined $values && ref $values;
    return %{$values};
}

=item field_is (TYPE, FIELD)

Check to see if field I<FIELD> is of the type I<TYPE> (enum, time, char, etc).  
Returns 1 if yes, 0 if no.

=cut

sub field_is {
    my ($self, $type, $field) = @_;
    return 1 if $self->field_type ($field) eq lc $type;
    return 0;
}

=item field_type (FIELD)

Returns the 

=cut

sub field_type {
    my ($self, $field, %args) = @_;
    my $formdata = $self->pull_formdata ();
    my $href = $formdata->get_fieldName_to_datatype_href () or return;
    return lc $href->{$field};
}

=item pull_formdata ()

=cut

sub pull_formdata {
    my ($self) = @_;
    my $parent = $self->parent_or_die;

    unless ($parent->formdata ($self->table)) {
        my $form = $self->remedy_session_form ($self->table) || return;
        my $formdata = $form->get_formdata;
        $parent->formdata ($self->table, $formdata);
    }

    return $parent->formdata ($self->table);
}

=back

=head2 Helper Functions

These functions are helpful either interally to this module, or might be useful
for any additional functions offered by any sub-modules.

=over 4

=item diff (OBJECT)

Finds the differences between the parent object and the passed-in object
I<OBJECT>.  Looks at each field from B<field_map ()> in I<OBJECT>; if it is both
defined in the new object and different from the related value of the old
object, then we consider that a difference.

Returns a hash of field/value pairs, where the values are from I<OBJECT>.

=cut

sub diff {
    my ($self, $other) = @_;
    my %map = $self->field_map;

    my %update;
    foreach my $func (keys %map) {
        my $field = $map{$func};
        my $newval = $other->$func;
        my $oldval = $self->$func;
        next unless defined $newval;
        $update{$field} = $newval unless ($newval eq $oldval);
    }

    %update;
}

=item field_to_id (FIELD)

Converts the human-readable I<FIELD> to its numeric field ID, with B<schema ()>.

=cut

sub field_to_id { shift->fields->{shift} }

=item id_to_field (ID)

Converts a numeric I<ID> to its human-readable field name, with B<schema ()>.

=cut

sub id_to_field { shift->schema->{shift} }

=item parent_or_die (TEXT, COUNT, ARGHASH)

Takes an arguemnt hash I<ARGHASH> from a parent function.  If the 'parent'
argument is in the argument hash, or if B<parent ()> is set, then return that;
otherwise, die.

'count'

=cut

sub parent_or_die  { 
    my ($self, %args) = @_;
    return $args{'parent'} if defined $args{'parent'};

    my $count = $args{'count'} || 0;
    my $text  = $args{'text'};

    if (ref $self) { 
        return $self->parent if defined $self->parent;
        $self->_or_die ('parent', "no parent in object", $text, 
            $count + 1);
    } else { 
        return $self->_or_die ('parent', "no 'parent' offered", $text, 
            $count + 1);
    }
}

=item session_or_die (ARGHASH)

=item logger_or_die  (ARGHASH)

=item config_or_die  (ARGHASH)

Pulls the sessin, logger, and config data (respectively) from the parent
session.  Actually calls B<parent_or_die ()> to do it.

=cut

sub session_or_die { 
    my ($self, %args) = @_;
    $args{'count'}++;
    $self->parent_or_die (%args)->session_or_die;
}
sub logger_or_die  { 
    my ($self, %args) = @_;
    $args{'count'}++;
    $self->parent_or_die (%args)->logger_or_die;
}

sub config_or_die {
    my ($self, %args) = @_;
    $args{'count'}++;
    $self->parent_or_die (%args)->config_or_die;
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

### _args_trace (TEXT, ARGHASH)
# If we're printing 'trace' level messages (really 'all'), then print off 
# a nice version of the keys/values in ARGHASH, with a prequel TEXT.
sub _args_trace {
    my ($logger, $text, %args) = @_;
    if ($logger->is_all) { 
        $logger->all ($text);
        foreach (keys %args) { 
            $logger->all ("  $_: $args{$_}"); 
        }
    }
}

### _init (CLASS, FORM, PARENT, TABLE)
# Creates and initializes a new object, setting its parent and table fields
# appropriately and going through the (optional).  FORM is either an object 
# we just pulled from a read () call (which called new_from_form ()), or undef,
# in which case we'll build a new one.  In either case, we'll set the session 
# data of FORM to the session of the current PARENT.
#
# Used with new () and new_from_form ().

sub _init {
    my ($class, $form, $parent, $table) = @_;
    my $logger  = $parent->logger_or_die  ('count' => 1);
    my $session = $parent->session_or_die ('count' => 1);

    ## Define the form, and set the session appropriately
    unless ($form) {
        $logger->all ("initializing new '$class' object");
        $form = $class->remedy_session_form ($table, 'parent' => $parent);
        if ($@) {
            $@ =~ s/ at .*$//;
            $@ =~ s/(\(ARERR\s*\S+?\)).*$/$1/m;
            $logger->info ("no formdata for '$table': $@");
            return;
        }
    }
    $form->set_session ($session);

    ## Build and populate the object
    my $obj = {};
    bless $obj, $class;
    $obj->parent      ($parent);
    $obj->table       ($table);
    $obj->remedy_form ($form);

    ## Reload the object, so as to fill in the key values, and return it
    return $obj->reload;
}

### _limit_string (ID, FIELD, VALUE)
# Like human_to_data (), but creates limit strings and therefore must
# understand the concept of '+' and '-', as described under limit_basic ().
# Could probably just stay in limit_basic (), but it's easier to have it split
# off for now.  

sub _limit_string {
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

        return _limit_gt ($self, $id, $mod, $data);

    ## 'time' fields 
    } elsif ($self->field_is ('time', $field)) {
        my ($mod, $timestamp) = ($value =~ /^([+-]?=?)?(.*)$/);

        my $data ;
        if ($timestamp =~ /^\d+/)                { $data= $timestamp }
        elsif (my $time = str2time ($timestamp)) { $data = $time     }
        else                                     { return '1=2'      }

        return _limit_gt ($self, $id, $mod, $data);

    ## all other field types
    } else {
        return if $value eq '%';
        return "'$id' = \"$value\"" if defined $value;
    }
}

### _limit_gt (ID, MOD, TEXT)
# Makes a LIMIT string for integer comparisons.  ID should be the numeric field
# ID, TEXT should be an integer as well, and MOD is the type of comparison
# we're doing.
sub _limit_gt {
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
    my ($self, $type, $error, $extra, $count) = @_;
    # return $self->$type if defined $self->$type;
    $count ||= 0;

    my $func = (caller ($count + 2))[3];    # default two levels back

    chomp ($extra);
    my $fulltext = sprintf ("%s: %s", $func, $extra ? "$error ($extra)"
                                                    : $error);
    die "$fulltext\n";
}


### _printable (STRING, LENGTH)
# Make a nicelty printable version of a string, for debugging purposes.
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

=head1 REQUIREMENTS

B<Remedy::Form::Utility>, B<Remedy::Session::Form>

=head1 SEE ALSO

Remedy::Ticket(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
