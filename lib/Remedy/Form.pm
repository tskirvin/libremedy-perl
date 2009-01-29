package Remedy::Form;
our $VERSION = "0.50";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form - access functions shared functions for all remedy forms

=head1 SYNOPSIS

    use Remedy::Form;

This is meant to be used as a template for other modules; please see the 
man pages listed under SEE ALSO for more usage information.

=head1 DESCRIPTION

Remedy::Form implements a consistent set of shared functions used by the
sub-form modules (eg B<Remedy::Form::People>, B<Remedy::Form::SupportGroup>,
B<Remedy::Form::Generic>), so that they can tie into the central B<Remedy>
system.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

## Debugging information level, for passing upstream
our $DEBUG = 7;

## Number of characters designated for the field name in the debug functions
our $DEBUG_CHARS = 30;

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;

use Class::Struct;
use Date::Parse;
use Exporter;
#use Remedy::Form::Generic;     # taken care of elsewhere for 
use Remedy::Form::Utility;
use Stanford::Remedy::Form;

our @EXPORT    = qw//;
our @EXPORT_OK = qw/init_struct/;
our @ISA       = qw/Exporter Remedy::Form::Utility/;

## Registered table names - why yes, it's global
our %REGISTER;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=head2 Class::Struct Functions

=over 4

=item init_struct (CLASS [, EXTRAHASH])

Initializes the structure of a Remedy table into the primary Remedy system.  
This is done by creating a B<Class::Struct> module, consisting of 

=over 4

=item remedy_form (B<Stanford::Remedy::Form>)

[...]

=item parent (B<Remedy>)

[...]

=item table ($)

[...]

Note that this function can be (and generally is) overridden by sub-classes,
which makes it essentially read-only at that point.

=item key_field (%)

[...]

=item (extras)

We can add extra accesors through I<EXTRAHASH>, which is passed into the struct
initialization directly.  That is, if you wanted to add an additional 'debug'
field, you might pass in:

  init_struct (__PACKAGE__, 'short', 'debug' => '$');

=item (key fields)

[...]

=back

Returns a two element array: the class B<Remedy::Form>, and the newly generated
struct.  This can be used to create a workable object inheritance at module
load time, as so:

    use Remedy::Form qw/init_struct/;
    our @ISA = init_struct (__PACKAGE__);

Not exported by default, but exportable.

=cut

sub init_struct {
    my ($class, $human, %extra) = @_;
    our $new = $class . "::Struct";
    $human ||= $class;

    my %fields;
    my %map = $class->field_map;
    foreach (keys %map) { $fields{$_} = '$' }
    struct $new => {'remedy_form' => 'Stanford::Remedy::Form', 
                    'parent'      => 'Remedy', 
                    'table'       => '$',
                    'key_field'   => '%', %extra, %fields};

    $REGISTER{$human} = $class;

    return (__PACKAGE__, $new);
}  

=item form (TABLE_NAME, EXTRA)

Finds the appropriate sub-class to manage the table named I<TABLE_NAME>.  If 
this name has been registered with B<init_struct ()> - ie, it's an alias - then
we will have a class name; if not, we will use B<Stanford::Form::Generic>, and
set the form name appropriately.

=cut

sub form {
    my ($self, $name, @extra) = @_;
    if (my $class = $REGISTER{$name}) { 
        return $class->new (@extra);
    } else {
        _load_table ($self, 'Remedy::Form::Generic');
        my $form = Remedy::Form::Generic->new ('table' => $name, @extra)
            || return;
        $form->table ($name);
        return $form;
    }
}

sub registered { grep { lc $_ ne 'generic' } keys %REGISTER }

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
    my ($self, $field, $value) = @_;
    if      ($self->field_is ('enum', $field)) { 
        my %hash = reverse $self->field_to_values ($field);
        return $hash{$value};
    } elsif ($self->field_is ('time', $field)) {
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
        return $hash{$value};
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

Gathers the components of a I<limit_ref> for B<select ()>. Looks at each
field listed in B<fields ()>, and creates an array of limit components based
on B<limit_string ()> in B<Remedy::Database>.  Follows these
arguments in the hash I<ARGHASH>:

=over 4

=item limit I<limit_ref>

Returns I<limit_ref> verbatim.

=item extra I<arrayref>

Adds the components of I<arrayref> into the array of limit components.

=item all I <anything>

=item ID I<number>

=back

Returns an array of limiting components

=cut

sub limit_basic {
    my ($self, %args) = @_;
    return $args{'limit'} if $args{'limit'};
    my $parent = $self->parent_or_die (%args);

    if (my $incnum = $args{'ID'}) { return "'1' == \"$incnum\"" }

    my @limit;
    my %fields = $self->fields (%args);
    foreach my $field (keys %fields) {
        next unless defined $args{$field};
        my $limit = $self->limit_string ($fields{$field}, $field, $args{$field});
        push @limit, $limit if $limit;
    }
    if (my $extra = $args{'extra'}) { push @limit, @$extra }
    push @limit, '1=1' if $args{'all'};
    
    @limit;
}

=item limit_string (TYPE, FIELD)

=cut

sub limit_string {
    my ($self, $type, $field, $text) = @_;
    return "" unless $type;
    return "" if $text eq '%';
    return "'$type' == NULL" unless defined $text;
    return "'$type' = \"$text\"" if defined $text;
}

=item reload ()

=cut

sub reload {
    my ($self) = @_;
    return $self->_init_from_object ($self->remedy_form);
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

Returns the object on success, or undef on failure.

=cut

=item init 

=over 4 

=item table (I<TABLE>)

=item db (I<Remedy>)

=back

=cut

sub init {
    my ($class, %args) = @_;
    my $parent = $class->parent_or_die (%args);

    ## Create the object, and set the parent class
    my $obj = {};
    bless $obj, $class;
    $obj->parent ($parent);

    ## Go through the field map, and get the key field infromation
    my %map = $class->field_map ();
    foreach my $key (keys %map) { 
        $obj->key_field ($map{$key}, $key)  
    }
    $obj->table ($args{'table'} || $class->table);
    
    return $obj;
}


sub new_from_form {
    my ($self, $form, $table, %args) = @_;
    my $class = ref $self ? ref $self : $self;
    return unless ($form && ref $form);
    my $obj = $class->init ('table' => $table, %args);
    $obj->remedy_form ($form);
    return $obj->_init_from_object ($form);
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

sub new {
    my ($class, %args) = @_;
    my ($parent, $session) = $class->parent_and_session (%args);

    # Create the object
    my $obj = $class->init ('db' => $parent, %args);

    my $table = $args{'table'} || $class->table;
    $class->error ('no table name set') unless $table;

    ## Generate the Remedy form
    local $@;
    my $form = $class->get_form ($session, $table);
    if ($@) { 
        $@ =~ s/ at .*$//;
        $@ =~ s/(\(ARERR\s*\S+?\)).*$/$1/m;
        $parent->warn_level ($DEBUG, "no formdata for '$table': $@");
        return;
    }

    $obj->remedy_form ($form);
    return $obj;
}

sub create {
    my ($self, %args) = @_;
    my ($parent, $session) = $self->parent_and_session (%args);
    my $form = $self->get_form ($session, $self->table);
    return $self->new_from_form ($form, $self->table, 'db' => $parent);
}

=item get_form (SESSION, TABLE)

Returns a B<Stanford::Remedy::Form> object safely - that is, turns off warnings
from the parent class and runs the whole block in an 'eval', since the module
only either returns the object or an error.  Returns the object on success, or
undef on failure; if there is an error message, it is returned as '$@'.

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
    my ($parent, $session) = $self->parent_and_session (%args);
    my $form = $self->get_form ($session, $self->table) || return;

    ## Figure out how we're limiting our search
    my $limit = join (" AND ", $self->limit (%args));
    return unless $limit;

    ## Perform the search
    $parent->warn_level ($DEBUG, sprintf ("read_where (%s, %s)", 
        $self->table, $limit));
    my @entries = $form->read_where ($limit);
    $parent->warn_level ($DEBUG, sprintf ("%d entr%s returned", 
        scalar @entries, scalar @entries == 1 ? 'y' : 'ies'));

    my @return;
    foreach my $entry (@entries) {
        $parent->warn_level ($DEBUG + 1, 
            sprintf ("new_from_form (%s)", $self->table));
        push @return, $self->new_from_form ($entry, $self->table, 
            'db' => $parent);
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
    my ($parent, $session) = $self->parent_and_session (%args);

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

These functions should probably be over-ridden by any sub-classes, and are
documented here for their intent; and in some cases they may be enough for the
sub-classes.

=over 4

=item field_map ()

Returns a hash containing field-name to accessor-function-name pairs - that
is, it maps the 'ID' field to the 'id' accessor.  

The default is an empty hash.

=cut

sub field_map        { () }

=item field_report ()

Returns an array of fields that we should track for changes when reporting to
the world - ie, it may not be interesting to track the 'LastUpdated' field in
most tables, but it may be interesting to track the installation status of a
package.  Used in B<parse_register ()>. 

The default is the keys of B<fields ()>.

=cut

sub field_report      { my %fields = shift->fields; keys %fields }

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

sub limit  { shift->limit_basic (@_) }

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

sub field_is {
    my ($self, $type, $field, %args) = @_;
    return 1 if $self->field_type ($field, %args) eq lc $type;
    return 0;
}   

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
        my $form = $self->get_form ($self->session_or_die (%args),
            $self->table) || return;     
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

=item debug_text ()

Like B<debug_html ()>, but creates a plaintext string instead, which looks
something like this:

    FIELD_ID1  FIELD_NAME1  VALUE
    FIELD_ID2  FIELD_NAME2  VALUE

This is all wrapped with B<Text::Wrap> in a vaguely logical manner. 

TODO: put some of the field numbers back in, at least if they're requested.
Also, re-create debug_html

=cut

sub debug_text {
    my ($self, %args) = @_;
    my %schema = $self->schema (%args);
    my $form = $self->remedy_form;

    my (@entries, @return, %max);
    my ($maxid, $maxfield, $maxvalue);
    foreach my $id (sort {$a<=>$b} keys %schema) {
        next unless defined $schema{$id};
        my $field = $schema{$id} || "*unknown*";

        my $value = $self->get ($schema{$id});
        next unless defined $value;
        $value =~ s/^\s+|\s+$//g;

        $max{'id'}    = length ($id)    if length ($id)    > $max{'id'};
        $max{'field'} = length ($field) if length ($field) > $max{'field'};

        push @entries, [$id, $field, $value];
    }

    $max{'field'} = $DEBUG_CHARS if $max{'field'} > $DEBUG_CHARS;

    foreach my $entry (@entries) {
        my ($id, $field, $value) = @{$entry};
        my $id_field    = '%'  . $max{'id'}    . 'd';
        my $field_field = '%-' . $max{'field'} . 's';
        my $size  = $max{'id'} + $max{'field'} + 2;
        my $form = "$id_field $field_field %s";
        push @return, wrap ('', ' ' x ($size), 
            sprintf ($form, $id, $field, $value));
    } 

    wantarray ? @return : join ("\n", @return, '');
}

sub debug_table {
    my ($self) = @_;
    return unless $self->remedy_form;
    return $self->remedy_form->as_string ('no_session' => 1);
}

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

=item parent_or_die (ARGHASH)

=item session_or_die (ARGHASH)

Takes an arguemnt hash I<ARGHASH> from a parent function.  If the 'db'
argument is in the argument hash, or if B<parent ()> is set, then return that;
otherwise, die.

'count'

=cut

sub parent_or_die {
    my ($self, %args) = @_;
    my $count = $args{'count'} || 2;
    return $args{'db'} if defined $args{'db'};
    $self->error ('no db connection', $count + 1)
        unless (ref $self && $self->parent);
    return $self->parent;
}

sub session_or_die {
    my ($self, %args) = @_;
    my $count = $args{'count'} || 2;
    my $parent = $self->parent_or_die (%args);
    $self->error ('no session connection', $count + 1)
        unless (defined $parent && ref $parent && $parent->session);
    return $parent->session;
}

sub parent_and_session {
    my ($self, %args) = @_;
    $args{'count'} ||= 3;
    return ($self->parent_or_die (%args), $self->session_or_die (%args));
}

sub error {
    my ($self, $text, $count) = @_;
    my $func = (caller ($count || 1))[3];
    $text = "unknown error" if (! defined $text);
    chomp $text;
    die "$func: $text\n";
}

=back

=cut

##############################################################################
### Internal Subroutines
##############################################################################

### _init_from_object (FORM) 
# Takes a Stanford::Remedy::Form object, uses it and the basic class 
# information to (re)populate the Class::Struct fields, and makes sure that 
# all required fields are set.  This is basically for use after an insert (),
# select (), or update () to make sure that we're working with viable data.
sub _init_from_object {
    my ($self, $form) = @_;
    my $class = ref $self;

    my %map = $class->field_map ();
    foreach my $key (keys %map) { 
        my $field = $map{$key};
        my $value = $self->data_to_human ($field, $form->get_value ($field));
        $self->$key ($value);
    }

    # Make sure that any required fields are set at this point
    foreach my $field ($class->field_required ()) {
        return unless defined $self->$field;
    }

    return $self;
}

sub _load_table {
    my ($self, $class) = @_;
    local $@;
    eval "use $class";
    $self->error ($@) if $@;
    return 1;
}

##############################################################################
### Final Documentation
##############################################################################

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
