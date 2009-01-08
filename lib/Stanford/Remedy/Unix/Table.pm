package Stanford::Remedy::Table;
our $VERSION = "0.50";
our $ID = q$Id: Table.pm 4689 2008-09-11 22:41:37Z tskirvin $;
# Copyright and license are in the documentation below.

=head1 NAME

Stanford::Remedy::Table - shared functions for all database tables

=head1 SYNOPSIS

    use Stanford::Remedy::Table;

This is meant to be used as a template for other modules; please see the 
man pages listed under SEE ALSO for more usage information.

=head1 DESCRIPTION

Stanford::Remedy::Table implements a consistent set of shared functions used
by the 'table' modules under B<Stanford::Remedy> - System, Package,
SystemPackage, and History.  These functions include interfaces to 
B<Stanford::Remedy::Database>, functions that store table-specific
information such as field names and default sorting, and basic debugging tools.

=cut

##############################################################################
### Configuration 
##############################################################################

##############################################################################
### Declarations
##############################################################################

use strict;

use Class::Struct;
use POSIX qw/strftime/;
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
    my ($class) = @_;

    my %fields;
    my %map = $class->field_map;
    foreach (keys %map) { $fields{$_} = '$' }

    our $new = $class . "::Struct";

    struct $new => {
        'parent'    => '$',
        'map'       => '%',
        %fields
    };

    return $new;
}  

=back

=head2 Database Functions

These functions wrap B<Stanford::Remedy::Database> with the per-table
information available from the rest of the class' functions.

All functions in this class that take the argument hash I<ARGHASH> honor 
the option '':

=over 4

=over 4

=item ars I<object>

I<object> is a parent B<Stanford::Remedy> object that contains a connection to
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
on B<limit_string ()> in B<Stanford::Remedy::Database>.  Follows these
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
    my $parent = $self->parent_or_die ('limit_basic', %args);
    my $db = $parent->db or return $parent->err_undef ("no connection");

    my @limit;
    my %fields = $self->fields;
    foreach my $field (keys %fields) {
        next unless defined $args{$field};
        my $limit = $db->limit_string ($fields{$field}, $field, $args{$field});
        push @limit, $limit if $limit;
    }
    if (my $extra = $args{'extra'}) { push @limit, @$extra }
    @limit;
}

=item insert (ARGHASH)

Attempts to insert the contents of this object into the database.  If
successful, returns the newly-created item (selected with B<select_uniq ()>);
on failure, sets an error in the parent object and returns an error.

Note: this only inserts items, it doesn't update existing items.  You 
probably want to use B<register ()>!

=cut

sub insert {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die ('insert', %args);
    my $db = $parent->db or return $parent->err_undef ("no db connection");

    my %hash;
    my %map = $self->field_map;
    foreach my $func (keys %map) {
        my $field = $map{$func};
        my $value = $self->$func;
        $hash{$field} = $value if defined $value;
    }

    my $err = $db->insert ($self->table, %hash);
    return $err ? $self->select_uniq ('db' => $parent)
                : $parent->err_undef ($db->error);
}

=item new_from_template (ENTRY, ARGHASH)

Takes information from I<ENTRY> - the output of a single item from a
B<Stanford::Remedy::Database::select ()> call - and creates a new object in
the appropriate class.

Uses two functions - B<field_map ()>, to map fields to function names so we can
actually move the information over, and B<field_required ()>, which lists the
required fields so we know when we should fail for lack of enough information.

Returns the object on success, or undef on failure.

=cut

sub new_from_template {
    my ($class, $item, %args) = @_;
    my $parent = $class->parent_or_die ('new_from_template', %args);
    return unless ($item && ref $item);

    # Create the object, and set the parent class
    my $obj = $class->new;
    $obj->parent ($parent);

    $obj->map ($item);

    my %map = $class->field_map;
    foreach my $key (keys %map) {
        $obj->$key ($item->{ $map{$key} });
    }
    foreach my $field ($class->field_required) {
        return unless defined $obj->$field;
    }

    return $obj;
}

=item register (ARGHASH)

Registers the object with the database - if the object already exists in the
database, we will update it (with B<update ()>), and if it doesn't already
exist, then we will insert it (with B<insert ()>).

Returns a two-item array - a new object of the same class that is populated 
from the database, and a a summary of the changes, suitable for parsing with 
B<parse_register ()>.

=cut

sub register {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die ('register', %args);

    if (my $entry = $self->select_uniq ('db' => $parent, 'select' => '*')) {
        my ($item, $changes) = $entry->update ($self, 'db' => $parent, %args);
        return ($item, $changes);

    } else {
        my $entry = $self->insert ('db' => $parent, %args);
        return ($entry, 'new entry');
    }
}


=item select (PARENT, ARGHASH)

Searches the database in the B<Stanford::Remedy> object I<PARENT>, based on
the arguments in the argument hash I<ARGHASH>:

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

Returns an array of objects, created with B<new_from_template ()>. Please see
Stanford::Remedy::Database(8) for more details on the B<select ()> call used
to gather the data.

If invoked in a scalar context, only returns the first item.

=cut

sub select {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die ('select', %args);
    my $class = ref $self || $self;

    my @entries = $parent->db->select (
        $class->table,
        [ $args{'select'} || $self->default_select ],
        [ $args{'limit'}  || $self->limit (%args) ],
        [ $args{'sort'}   || $self->default_sort ],
        [ $args{'count'}  || () ],
                              );

    my @return;
    foreach my $entry (@entries) {
        push @return, $class->new_from_template ($entry, 'db' => $parent);
    }
    return wantarray ? @return : $return[0];
}

=item select_uniq (ARGHASH)

As with B<select ()>, except we pass it a I<limit_ref> to select one (and only
one) entry, based on the fields listed in B<field_uniq ()>. Returns the entry on
success, an empty list if no entries match, or undef if more than one entry
matches.

=cut

sub select_uniq {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die ('select_uniq', %args);

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
    my $parent = $self->parent_or_die ('update', %args);
    my $db = $parent->db or return $parent->err_undef ("no db connection");

    my %update = $self->diff ($new);
    unless (scalar keys %update) { return wantarray ? ($self => {}) : $self }

    my %uniq;
    my %map = $self->field_map;
    foreach my $func ($self->field_uniq) {
        my $field = $map{$func};
        $uniq{$field} = $self->$func;
    }

    unless (my $err = $db->update ($self->table, \%uniq, \%update)) {
        return wantarray ? (undef => 'error' . $db->error) : undef;
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
    my ($self, $args, $date) = @_;  
    return "(unknown time)" unless $date;
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
B<new_from_template ()> - basically, this equates to the 'required' fields in the SQL
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

sub fields { my %schema = shift->schema (@_) || (); return reverse %schema; }

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

sub schema { () }

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

=cut

sub debug_text {
    my ($self) = @_;
    my %schema = $self->schema;
    my $map = $self->map;

    my (@entries, @return, %max);
    my ($maxid, $maxfield, $maxvalue);
    foreach my $id (sort {$a<=>$b} keys %schema) {
        next unless defined $map->{$id};
        my $field = $schema{$id} || "*unknown*";
        my $value = $map->{$id};
        
        push @entries, [$id, $field, $value];
        $max{'id'}    = length ($id)    if length ($id)    > $max{'id'};
        $max{'field'} = length ($field) if length ($field) > $max{'field'};
    }

    foreach my $entry (@entries) {
        my $id    = '%' . $max{'id'} . 'd';
        my $field = '%-' . $max{'field'} . 's';
        my $size  = $max{'id'} + $max{'field'} + 3;
        my $form = "$id  $field  %s";
        push @return, wrap('', ' ' x ($size + 2), sprintf ($form, @{$entry})); 
    } 

    wantarray ? @return : join ("\n", @return, '');
}

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
    my ($self, $field) = @_;
    my %id = reverse $self->schema; 
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

=item parent_or_die (TEXT, ARGHASH)

Takes an arguemnt hash I<ARGHASH> from a parent function, along with some text
summarizing the function that invoked this method.  If the 'db' argument is in
the argument hash, or if B<parent ()> is set, then return that; otherwise, die.

=cut

sub parent_or_die {
    my ($self, $func, %args) = @_;
    my $db = $args{'db'} || $self->parent;
    die __PACKAGE__ . ": no db connection in $func ()\n" unless $db;
    return $db;
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
### Final Documentation
##############################################################################

=head1 SEE ALSO

Stanford::Remedy::Ticket(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
