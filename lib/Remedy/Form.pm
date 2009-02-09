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
use Remedy::Form::Generic;  
use Remedy::Form::Utility;
use Stanford::Remedy::Form;

our @EXPORT    = qw//;
our @EXPORT_OK = qw/init_struct/;
our @ISA       = qw/Exporter Remedy::Form::Utility/;

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

=item remedy_form (B<Stanford::Remedy::Form>)

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
    struct $new => {'remedy_form' => 'Stanford::Remedy::Form',
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
    if (my $class = $REGISTER{$name}) {
        my @classes = ref $class ? @$class : $class;
        $logger->debug (sprintf ("%d %s associated with '%s'", 
            scalar @classes, scalar @classes == 1 ? 'class' 
                                                  : 'classes', $name));
        foreach (@classes) {
            my $table = $_->table;
            $logger->debug ("form for '$name' is '$_' (table '$table')");
            push @return, $_->new ('table' => $table, 'parent' => $parent);
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
    $logger->all (_plural (scalar @return, 'form', 'forms') . ' returned');
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
    my $logger = $parent->logger_or_die;
    my $session = $parent->session_or_die;

    my $logger = $parent->config->logger;

    # Create the object
    my $table = $args{'table'} || $class->error ('no table offered');

    my $obj = _init ($class, $parent, $table);

    ## Generate the Remedy form
    local $@;
    my $form = $class->get_form ($session, $table);
    if ($@) {
        $@ =~ s/ at .*$//;
        $@ =~ s/(\(ARERR\s*\S+?\)).*$/$1/m;
        $logger->info ("no formdata for '$table': $@");
        return;
    }

    $obj->remedy_form ($form);
    return $obj;
}

sub registered { grep { lc $_ ne 'generic' } keys %REGISTER }

=back

=cut

##############################################################################
### Accessors ################################################################
##############################################################################


=head2 Accessors

=over 4

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

=cut

sub set {
    my ($self, %fields) = @_;
    my $form = $self->remedy_form;
    foreach my $field (keys %fields) {
        my $value = $self->human_to_data ($field, $fields{$field});
        if (my $key = $self->key_field ($field)) {
            $self->$key ($value);
        }
        $self->remedy_form->set_value ($field, $value);
    }
    return $self;
}

=item human_to_data (FIELD, VALUE)

=cut

sub human_to_data {
    my ($self, $field, $value, %args) = @_;
    if      ($self->field_is ('enum', $field, %args)) {
        my %hash = reverse $self->field_to_values ($field, %args);
        return defined $hash{$value} ? $hash{$value} 
                                     : undef; 
                                     # : '-1';            # will never match
    } elsif ($self->field_is ('time', $field, %args)) {
        return str2time ($value) || $value;
    } else {
        return $value;
    }
}

=item data_to_human (FIELD, VALUE)

=cut

sub data_to_human {
    my ($self, $field, $value) = @_;
    return unless defined $value;
    if      ($self->field_is ('enum', $field)) {
        my %hash = $self->field_to_values ($field);
        return defined $hash{$value} ? $hash{$value} 
                                     : '*BAD VALUE*';   # will be noticable
    } elsif ($self->field_is ('time', $field)) {
        return $self->format_date ($value);
    } else {
        return $value;
    }
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

=over 4

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

    _args_trace ($logger, 'before limit_pre()', %args) if $logger->is_all;
    %args = $self->limit_pre (%args);
    _args_trace ($logger, 'after  limit_pre()', %args) if $logger->is_all;

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
    $self->remedy_form ($form) if defined $form;

    # Set the per-object accessors
    my %map = $self->field_map;
    foreach my $key (keys %map) {
        my $field = $map{$key};
        my $value = $self->data_to_human ($field, 
            $self->remedy_form->get_value ($field));
        $self->$key ($value);
    }

    # Make sure that any required fields are set at this point
    foreach my $field ($self->field_required ()) {
        return unless defined $self->$field;
    }

    return $self;
}

=item save (ARGHASH)

Attempts to save the contents of this object into the database.

If
successful, reloads the newly-created item and returns it; on failure, sets an
error in the parent object and returns an error.

Note: this only inserts items, it doesn't update existing items.  You probably
want to use B<save ()>!

=cut

sub save {
    my ($self, %args) = @_;

    ## Make sure all data is reflected in the form
    my $form = $self->remedy_form or $self->error ('no form');

    ## Go through the key fields, and move data if necessary
    my $keyhash = $self->key_field;
    foreach my $key (keys %{$keyhash}) {
        my $func = $$keyhash{$key};
        my $value = $self->$func;
        next unless defined $value;
        $self->set ($key, $self->$func);
    }

    ## Write the data out
    my $return = $form->save or return;

    ## Reload the data
    $self->reload () or return;
    return $return;
}

=item new_from_form (ENTRY, ARGHASH)

Takes information from I<ENTRY> - the output of a single item from a
B<Remedy::select ()> call - and creates a new object in the appropriate class.

Uses two functions - B<field_map ()>, to map fields to function names so we can
actually move the information over, and B<field_required ()>, which lists the
required fields so we know when we should fail for lack of enough information.

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

    my $obj = _init ($class, $self->parent_or_die (%args), $table) || return;
    return $obj->reload ($form);
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


sub create {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die (%args);
    my $form = $self->get_form ($parent->session_or_die, $self->table);
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

=item get_form (SESSION, TABLE_NAME)

Given a working B<Remedy::Session> and the table name I<TABLE_NAME>, safely
creates a B<Stanford::Remedy::Form> object safely - meaning that warnings are
turned off temporarily and the whole block is run as an 'eval'.  Returns the
object on success, or undef on failure; if there is an error message, it is
returned as '$@'.

TODO: when we move these classes into the same library set and rename it to
B<Remedy::Form::Raw> or somesuch, we'll access that module here.

=cut

sub get_form {
    my ($self, $session, $table) = @_;
    return unless (defined $session && defined $table);
    no warnings;
    my $form = eval { Stanford::Remedy::Form->new ('session' => $session,
        'name' => $table) };
    if ($@) { return }
    return $form;
}

=item read ([...])


=cut

sub read {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die ('need parent to read', 0, %args);
    my $session = $parent->session_or_die;
    my $logger  = $parent->logger_or_die;

    my $form = $self->get_form ($session, $self->table) || return;

    ## Figure out how we're limiting our search
    my $limit = join (" AND ", $self->limit (%args));
    return unless $limit;

    my $logger = $parent->config->logger;

    ## Perform the search
    $logger->debug (sprintf ("read_where (%s, %s)", $self->table, $limit));
    my @entries = $form->read_where ($limit);
    $logger->debug (sprintf ("%d entr%s returned", scalar @entries, 
        scalar @entries == 1 ? 'y' : 'ies'));

    my @return;
    foreach my $entry (@entries) {
        $logger->debug (sprintf ("new_from_form (%s)", $self->table));
        push @return, $self->new_from_form ($entry, 
            'table' => $self->table, 'parent' => $parent);
    }

    return wantarray ? @return : $return[0];
}

sub insert { shift->save (@_) }
sub update { shift->save (@_) }
sub delete { return }       # not yet written

=item update (NEWOBJ, ARGHASH)

Attempts to update the database values for current object with the contents the
new object I<NEWOBJ>.  First, runs the item through

Returns a two-item array: the updated item (the old item if no changes were
necessary, or undef if there was an error), and a hashref listing all changes
that were made (or the string 'error' if there was an error).  In a scalar
context, only returns the first item.

Note: this only updates items, it doesn't insert new items.  You probably want
to use B<register ()>!

=cut

sub update_old_check {
    my ($self, $new, %args) = @_;
    my $parent = $self->parent_or_die (%args);

    my %update = $self->diff ($new);
    unless (scalar keys %update) { return wantarray ? ($self => {}) : $self }

    my %uniq;
    my %map = $self->field_map;
    foreach my $func ($self->field_uniq) {
        my $field = $map{$func};
        $uniq{$field} = $self->$func;
    }

    unless (my $err = $self->update ($self->table, \%uniq, \%update)) {
        return wantarray ? (undef => 'error' . $self->error) : undef;
    } else {
        return wantarray ? ($self => \%update) : $self;
    }
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

=item field_required ()

Returns an array of field accessors that must be filled in order to continue on
B<new_from_form ()> - basically, this equates to the 'required' fields in the SQL
databases.

The default is an empty array.

=cut

sub field_required   { qw// }

=item field_uniq ()

Returns an array of field accessors that should be enough to select a "unique"
entry, where nothing else should match it.

The default is 'id'.

=cut

sub field_uniq       { qw/id/ }

=item fields ()

Returns a hash containing field-name to field-content pairs - that is, 'ID' to
'int', 'Status' to 'text', and 'CreateTime' to 'time'.  Used for B<select ()>.
If you just want to get the field names, use B<keys $obj->fields>.

The default is a reverse of the schema () hash.

=cut

sub fields { my %schema = shift->schema (@_);  return reverse %schema; }

=item limit (ARGHASH)

Returns a string that is used in B<select ()> functions and the like to limit
the number of affected entries.  This can be over-ridden to allow for more
complicated queries.

The default is to call B<limit_basic ()> with the same arguments as we were
passed.

=cut

sub limit_pre  { shift; @_ }
sub limit_post { shift; @_ }

=item print_text ()

Creates a printable string summarizing information about the object.  Based
on invocation type, returns either an array of lines that you can print, or a
single newline-delimited string.

Defaults to use B<debug_text ()>.

=cut

sub print_text { shift->debug_text (@_) }

=item schema ()

Returns a hash of field IDs and their human-readable names.  This is used by
B<debug_text ()> to make a human-readable debug field, as well as by
B<field_to_id ()> and B<id_to_field ()>.

Defaults to ().

=cut

sub schema {
    my ($self, %args) = @_;
    my $formdata = $self->pull_formdata (%args);
    my $href = $formdata->get_fieldName_to_fieldId_href ();
    return reverse %{$href};
}

sub field_to_values {
    my ($self, $field, %args) = @_;
    my $formdata = $self->pull_formdata (%args);
    my $href = $formdata->get_fieldName_to_enumvalues_href () or return;
    my $values = $href->{$field};
    return unless defined $values && ref $values;
    return %{$values};
}

# sub field_is_enum { shift->field_is ('enum', @_) }
# sub field_is_time { shift->field_is ('time', @_) }

=item field_is (TYPE, FIELD, ARGS)

=cut

sub field_is {
    my ($self, $type, $field, %args) = @_;
    return 1 if $self->field_type ($field, %args) eq lc $type;
    return 0;
}

=item field_hash (FIELD, ARGS)

=cut

sub field_type {
    my ($self, $field, %args) = @_;
    my $formdata = $self->pull_formdata (%args);
    my $href = $formdata->get_fieldName_to_datatype_href () or return;
    return lc $href->{$field};
}

=item pull_formdata ()

=cut

sub pull_formdata {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die (%args);

    unless ($parent->formdata ($self->table)) {
        my $form = $self->get_form ($parent->session_or_die, $self->table) || return;
        my $formdata = $form->get_formdata;
        $parent->formdata ($self->table, $formdata);
    }

    return $parent->formdata ($self->table);
}

=item table_human

=cut

sub table_human {
    my ($class) = @_;
    my $table = $class;
    $table =~ s/^Remedy::Form:://;
    return $table;
}

=back

=head2 Helper Functions

These functions are helpful either interally to this module, or might be useful
for any additional functions offered by any sub-modules.

=over 4


sub fields_text {}

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

=item field_map_reverse ()

Inverts B<field_map ()>.

=cut

sub field_map_reverse {
    my %entries = reverse shift->field_map ();
    return %entries;
}

=item field_to_id (FIELD)

Converts the human-readable I<FIELD> to the numeric field ID, with B<schema ()>.

=cut

sub field_to_id { shift->fields->{shift} }

=item id_to_field (ID)

Converts a numeric I<ID> to the human-readable field name, with B<schema ()>.

=cut

sub id_to_field { shift->schema->{shift} }

=item parent_or_die (TEXT, COUNT, ARGHASH)

=item session_or_die (ARGHASH)

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

=back

=cut

##############################################################################
### Internal Subroutines
##############################################################################

### _args_trace (TEXT, ARGHASH)
# [...]
sub _args_trace {
    my ($logger, $text, %args) = @_;
    if ($logger->is_all) { 
        $logger->all ($text);
        foreach (keys %args) { $logger->all ("  $_: $args{$_}"); }
    }
}


### _init (PARENT, 
# Creates and initializes a new object, setting its parent and table fields
# appropriately and going through field_map () to set the key_field entries.
# Returns the object; failure cases generally lead to death.  
#
# Used with new () and new_from_form ().

sub _init {
    my ($class, $parent, $table) = @_;

    my $obj = {};
    bless $obj, $class;

    my %map = $class->field_map ();
    foreach my $key (keys %map) {
        $obj->key_field ($map{$key}, $key)
    }

    $obj->parent ($parent);
    $obj->table  ($table);

    return $obj;
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
        my ($mod, $human) = ($value =~ /^([+-]?=?)(.*)$/);
        my %hash = reverse $self->field_to_values ($field);
        my $data = $hash{$human};
        return '1=2' unless defined $data;
        return _limit_gt ($self, $id, $mod, $data);

    ## 'time' fields 
    } elsif ($self->field_is ('time', $field)) {
        my ($mod, $timestamp) = ($value =~ /^([+-]?=?)(.*)$/);
        my $time = str2time ($timestamp) || return '1=2';
        return _limit_gt ($self, $id, $mod, $time);

    ## all other field types
    } else {
        return if $value eq '%';
        return "'$id' = \"$value\"" if defined $value;
    }
}

### _limit_gt (ID, MOD, TEXT)
# Escape TEXT first.
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

sub _plural {
    my ($count, $singular, $plural) = @_;
    sprintf ("%d %s", $count, $count == 1 ? $singular : $plural);
}

##############################################################################
### Final Documentation
##############################################################################

=head1 REQUIREMENTS

B<Remedy::Form::Utility>

=head1 SEE ALSO

Remedy::Ticket(8), Stanford::Remedy(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
