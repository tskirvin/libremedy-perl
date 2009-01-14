package Remedy::Form;
our $VERSION = "0.50";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form - shared functions for all database tables

=head1 SYNOPSIS

    use Remedy::Form;

This is meant to be used as a template for other modules; please see the 
man pages listed under SEE ALSO for more usage information.

=head1 DESCRIPTION

Remedy::Form implements a consistent set of shared functions used by the
'table' modules under B<Remedy> - System, Package, SystemPackage, and History.
These functions include interfaces to B<Remedy::Database>, functions that store
table-specific information such as field names and default sorting, and basic
debugging tools.

=cut

##############################################################################
### Configuration 
##############################################################################

## Debugging information level, for passing upstream
our $DEBUG = 7;

## Number of characters designated for the field name in the debug functions
our $DEBUG_CHARS = 30;

our %REGISTER;

##############################################################################
### Declarations
##############################################################################

use strict;

use Class::Struct;
use Date::Parse;
use POSIX qw/strftime/;
use Stanford::Remedy::Form;
use Text::Wrap;

$Text::Wrap::columns = 80;
$Text::Wrap::huge    = 'overflow';

##############################################################################
### Subroutines
##############################################################################

=head1 FUNCTIONS

=head2 Class::Struct Functions

=over 4

=item init_struct

[...]

=cut

sub init_struct {
    my ($class, %extra) = @_;
    our $new = $class . "::Struct";

    my %fields;
    my %map = $class->field_map;
    foreach (keys %map) { $fields{$_} = '$' }
    struct $new => {'parent'    => '$', 
                    'key_field' => '%', 
                    'form'      => '$', 
                    %extra, %fields};

    $REGISTER{$class}++;

    return $new;
}  

sub registered_form {
    my ($self, $class) = @_;
    return unless defined $REGISTER{$class};
    return $class;
}

sub registered { keys %REGISTER }

sub get {
    my ($self, $field) = @_;
    my $form = $self->form || $self->error ('no form');
    if (my $key = $self->key_field ($field)) { 
        return $self->$key;
    } else { 
        return $self->data_to_human ($field, $form->get_value ($field));
    }
}


sub set {
    my ($self, %fields) = @_;
    my $form = $self->form;
    foreach my $field (keys %fields) { 
        my $value = $self->data_to_human ($field, $fields{$field});
        if (my $key = $self->key_field ($field)) { 
            $self->$key ($value);
        }
        $self->form->set_value ($field, $value);
    }
    return $self;
}

sub human_to_data { 
    my ($self, $field, $value) = @_;
    if      ($self->field_is ('enum', $field)) { 
        my %hash = reverse $self->field_to_values ($field);
        return $hash{$value};
    } elsif ($self->field_is ('time', $field)) {
        return str2time ($value);
    } else {
        return $value;
    }
}

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

These functions wrap B<Remedy::Database> with the per-table
information available from the rest of the class' functions.

All functions in this class that take the argument hash I<ARGHASH> honor 
the option '':

=over 4

=item ars I<object>

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

=back

Returns an array of limiting components

=cut

sub limit_basic {
    my ($self, %args) = @_;
    return $args{'limit'} if $args{'limit'};
    my $parent = $self->parent_or_die (%args);

    my @limit;
    my %fields = $self->fields (%args);
    foreach my $field (keys %fields) {
        next unless defined $args{$field};
        my $limit = $self->limit_string ($fields{$field}, $field, $args{$field});
        push @limit, $limit if $limit;
    }
    if (my $extra = $args{'extra'}) { push @limit, @$extra }
    
    @limit;
}

sub limit_string {
    my ($self, $type, $field, $text) = @_;
    return "" unless $type;
    return "" if $text eq '%';
    return "'$type' == NULL" unless defined $text;
    return "'$type' = \"$text\"" if defined $text;
}

=item insert (ARGHASH)

Attempts to insert the contents of this object into the database.  If
successful, returns the newly-created item (selected with B<select_uniq ()>);
on failure, sets an error in the parent object and returns an error.

Note: this only inserts items, it doesn't update existing items.  You probably
want to use B<save ()>!

=cut

sub insert {
    my ($self, %args) = @_;

    ## Make sure all data is reflected in the form
    my $form = $self->form or $self->error ('no form');
    
    my $keyhash = $self->key_field;
    foreach my $key (keys %{$keyhash}) {
        my $func = $$keyhash{$key};
        my $value = $self->$func;
        next unless defined $value;
        $self->set ($key, $self->$func);
        # $form->set_value ($key, $self->$func);
    }
    
    my $return = $form->save;
    $self->reload ();
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

sub init {
    my ($class, %args) = @_;
    my $parent = $class->parent_or_die (%args);

    # Create the object, and set the parent class
    my $obj = $class->new;
    $obj->parent    ($parent);

    my %map = $class->field_map ();
    foreach my $key (keys %map) { 
        $obj->key_field ($map{$key}, $key)  
    }
    
    return $obj;
}

sub new {

}

sub reload {
    my ($self) = @_;
    return $self->_init_from_form ($self->form);
}

sub new_from_form {
    my ($class, $form, %args) = @_;
    return unless ($form && ref $form);
    my $obj = $class->init (%args);
    $obj->form ($form);
    return $obj->_init_from_form ($form);
}

=item register (ARGHASH)

Registers the object with the database - if the object already exists in the
database, we will update it (with B<update ()>), and if it doesn't already
exist, then we will insert it (with B<insert ()>).

Returns a two-item array - a new object of the same class that is populated 
from the database, and a a summary of the changes, suitable for parsing with 
B<parse_register ()>.

=cut

sub save {
    my ($self, %args) = @_;
    if ($self->form && $self->form->get_request_id) { 
        return $self->update (%args) 
    } else { 
        return $self->insert (%args) 
    }
}

=item read (PARENT, ARGHASH)

Reads from the database in the B<Remedy> object I<PARENT>, based on the
arguments in the argument hash I<ARGHASH>:

=over 4

=item select I<select_ref>

Fields to fetch.  Defaults to B<default_select ()>. 

=item sort I<sort_ref>

How to sort the resulting data.  Defaults to B<default_sort ()>.

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
    my ($class, %args) = @_;
    my ($parent, $session) = $class->parent_and_session (%args);

    # Create the object
    my $obj = $class->init ('db' => $parent, %args);

    ## Generate the Remedy form
    my $form = Stanford::Remedy::Form->new 
        ('session' => $session, 'name' => $args{'table'} || $class->table) 
        or $class->error ("couldn't start new form: $@");

    $obj->form ($form);
    return $obj;
}

sub read {
    my ($self, %args) = @_;
    my ($parent, $session) = $self->parent_and_session (%args);

    ## Generate the Remedy form that we'll use to pull out data
    my $form = Stanford::Remedy::Form->new 
        ('session' => $session, 'name' => $self->table) 
        or $self->error ("couldn't start new form: $@");

    ## Figure out how we're limiting our search; most of the standard search
    ## methods don't currently work.
    my $limit = join(" AND ", $self->limit (%args));
    return unless $limit;

    $parent->warn_level ($DEBUG, sprintf ("read_where (%s, %s)", 
        $self->table, $limit));
    my @entries = $form->read_where ($limit);
    $parent->warn_level ($DEBUG, sprintf ("%d entr%s returned", 
        scalar @entries, scalar @entries == 1 ? 'y' : 'ies'));

    my @return;
    foreach my $entry (@entries) {
        $parent->warn_level ($DEBUG + 1, 
            sprintf ("new_from_form (%s)", $self->table));
        push @return, $self->new_from_form ($entry, 'db' => $parent);
    }
    return wantarray ? @return : $return[0];
}

sub update {}
sub delete {}

=item select_uniq (ARGHASH)

As with B<select ()>, except we pass it a I<limit_ref> to select one (and only
one) entry, based on the fields listed in B<field_uniq ()>. Returns the entry on
success, an empty list if no entries match, or undef if more than one entry
matches.

=cut

sub select_uniq {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die (%args);

    my %map = $self->field_map;
    my %limit;
    foreach my $func ($self->field_uniq) {
        my $field = $map{$func};
        $limit{$field} = $self->$func;
    }

    my @entries = $self->select ('limit' => \%limit, %args);
    return () unless scalar @entries;
    return if (scalar @entries > 1);
    return $entries[0];
}

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

sub update {
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

=head2 Text Functions

=over 4

=item format_text_field (ARGHASHREF, FIELD, TEXT [, FIELD2, TEXT2 [...]))

=cut

sub format_text_field {
    my ($self, $args, @print) = @_;
    $args ||= {};

    my $width = $$args{'minwidth'} || 0;
    my $prefix = $$args{'prefix'} || '';

    my (@return, @entries);

    while (@print) { 
        my ($field, $text) = splice (@print, 0, 2);
        $field = "$field:";
        push @entries, [$field, $text || "*unknown*"];
        $width = length ($field) if length ($field) > $width;
    }
    
    foreach my $entry (@entries) {
        my $field = '%-' . $width . 's';
        push @return, wrap ($prefix, $prefix . ' ' x ($width + 1), sprintf 
            ("$field %s", @{$entry})); 
    } 

    return wantarray ? @return : join ("\n", @return, '');   
}

sub format_text {
    my ($self, $args, @print) = @_;
    $args ||= {};

    my $width  = $$args{'minwidth'} || 0;
    my $prefix = $$args{'prefix'} || '';

    my @return = wrap ($prefix, $prefix, @print);
    
    return wantarray ? @return : join ("\n", @return, '');   
}

sub format_date {
    my ($self, $date) = @_;  
    return '(unknown time)' unless $date;
    return strftime ('%Y-%m-%d %H:%M:%S', localtime ($date));
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

sub fields { my %schema = shift->schema (@_); return reverse %schema; }

=item limit (ARGHASH)

Returns a string that is used in B<select ()> functions and the like to limit
the number of affected entries.  This can be over-ridden to allow for more
complicated queries.  

The default is to call B<limit_basic ()> with the same arguments as we were
passed.

=cut

sub limit  { shift->limit_basic (@_) }

=item print_html ()

Creates a printable string summarizing information about the object.  Based
on invocation type, returns either an array of lines that you can print, or a
single newline-delimited string.

Defaults to use B<debug_html ()>.

=cut

sub print_html { shift->debug_html (@_) }

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

sub field_is_enum { shift->field_is ('enum', @_) }
sub field_is_time { shift->field_is ('time', @_) }

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

sub pull_formdata {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die (%args);

    unless ($parent->formdata ($self->table)) { 
        my $session = $self->session_or_die (%args);
        my $form = Stanford::Remedy::Form->new 
            ('session' => $session, 'name' => $self->table);
        my $formdata = $form->get_formdata;
        $parent->formdata ($self->table, $formdata)
    }
    
    return $parent->formdata ($self->table);
}

=item table ()

Returns the name of the DBI table.  

Defaults to the string "TABLE NOT SET" (which will probably break most SQL
implementations in a very clear way).

=cut

sub table { "TABLE NOT SET" }

=item default_select ()

Returns an array of fields that we will use in B<select ()> to limit the
search, if no specific list is offered.  

Defaults to an empty array.

=cut

sub default_select { () }

=item default_sort ()

Returns an array of fields that we will use in B<select ()> to sort the search,
if no specific list is offered.  

Defaults to an empty array.

=cut

sub default_sort   { () }

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
    my $form = $self->form;

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
    return $self->form->as_string ('no_session' => 1);
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

sub field_to_id { 
    my ($self, $field, %args) = @_;
    my %id = reverse $self->schema (%args); 
    return $id{$field} ;
}

=item id_to_field (ID)

Converts a numeric I<ID> to the human-readable field name, with B<schema ()>.

=cut

sub id_to_field { 
    my ($self, $id) = @_;
    my %schema = $self->schema;
    return $schema{$id};
}

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
    die "$func: $text\n";
}

=item parse_register (CHANGE)

Parse I<CHANGE>, the second component of the output from B<register ()>, into
a human-readable form.  Returns an array where the first item is the type of
change, and additional items listing the specific changes:

=over 4

=item insert

The item was freshly inserted; just offer a string saying 'new item'.

=item update

Foreach field in B<field_report()>, list the name of the field and its new 
value as a single string.

=item (nothing)

There was no change, so don't list anything.

=back

=cut

sub parse_register {
    my ($self, $changes) = @_;
    return '' unless $changes;
    return ('insert', $changes) unless ref $changes;

    my @return;
    my %map = $self->field_map_reverse;
    foreach my $field ($self->field_report) {
        my $value = $changes->{ $field };
        my $name = $map{$field};
        push @return, "$name is $value" if defined $value;
    }
    return ('update', @return);
}

=back

=cut

##############################################################################
### Internal Subroutines
##############################################################################

### _init_from_form (FORM) 
# Takes a Stanford::Remedy::Form object, uses it and the basic class 
# information to (re)populate the Class::Struct fields, and makes sure that 
# all required fields are set.  This is basically for use after an insert (),
# select (), or update () to make sure that we're working with viable data.
sub _init_from_form {
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
