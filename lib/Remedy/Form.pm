package Remedy::Form;
our $VERSION = "0.50.01";
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
system.  It consis

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
use Remedy::FormData::Entry;
use Remedy::Utility qw/or_die/;

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

=item entry (B<Remedy::FormData::Entry>)

Manages the object used to get/set database values.  Set with B<new ()> or
B<new_from_form ()>.

=item table ($)

Manages the database table name for each object; contains values like
I<CTM:Person>.  Note that most B<Remedy::Form::*> sub-modules override this
function, making it read-only.

=item (per-object B<Class::Struct> accessors) ($)

Adds one accessor of type '$' for each key from the B<field_map ()> function.
This data will be directly accessed with B<get> and B<set>, amongst other
functions.  

Together, these are known as the Key Fields.

=item (extras) (various)

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
    struct $new => {'entry'  => 'Remedy::FormData::Entry',
                    'parent' => 'Remedy',
                    'table'  => '$', %extra, %fields};

    ## Register the class names
    __PACKAGE__->register ($class, $class);
    __PACKAGE__->register ($human, $class);
    if (my $table = $class->table) { __PACKAGE__->register ($table, $class) }

    return (__PACKAGE__, $new);
}

=item key_field (NAME)

If there is a Key Field matching field name I<NAME>, then return the matching
accessor name.  Otherwise, return undef.

=cut

sub key_field { 
    my ($self, $field) = @_;
    my %map = reverse $self->field_map;
    return $map{$field} if defined $map{$field};
    return;
}

=item register ([KEY[, CLASS]])

Manages a global cache of "registered forms".  Whenever a form is initialized
with B<init_struct>, its class (e.g. B<Remedy::Form::User>) gets registered
with the global cache.  This function is used to both read and add to the
cache.  Possible argument paths:

=over 2

=item I<KEY> and I<CLASS> are defined

Registers the class I<CLASS> as I<KEY>.

=item I<KEY> is defined

Returns the underlying class for I<KEY>.

=item (no arguments)

Returns a hash containing the complete registration cache.

=back

=cut

sub register {
    my ($self, $key, $class) = @_;
    return %REGISTER unless defined $key;
    return $REGISTER{lc $key} unless defined $class;
    $REGISTER{lc $key} = ref $class ? $class : [$class];
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
            last if wantarray;
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
    return unless scalar @return;
    return @return if wantarray;
    $logger->debug ("returning first item");
    return $return[0];
}

=item form_names ()

Gets a list of registered form names 

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

=item formdata ()



=cut

sub formdata { shift->entry_or_die->formdata_or_die }

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

=item related_by_id (TABLE, FIELD, ID, ARGHASH)

=cut

sub related_by_id {
    my ($self, $table, $field, $id, %args) = @_;
    my $parent = $self->parent_or_die;
    my $logger = $self->logger_or_die;
    unless ($table) {
        $logger->debug ('related_by_id - no table offered');
        return;
    }
    unless ($id) {
        $logger->debug ('related_by_id - no ID offered');
        return;
    }
    $logger->debug (sprintf ("read (%s, %s => %s)", $table, $field, $id));
    return $parent->read ($table, {$field => $id}, %args);
}

=item remedy_to_key ()

=cut

sub remedy_to_key {
    my ($self, $init) = @_;

    my $entry = $self->entry;
    # Set the per-object accessors
    my %map = $self->field_map;
    foreach my $key (keys %map) {
        my $field = $map{$key};
        my $value = $entry->data_to_human ($field, $entry->value ($field));
        if (defined $value) { 
            $self->logger_or_die->all ("setting key '$key' to '$value'");
            $self->$key ($value);
        } else {
            $self->logger_or_die->all ("setting key '$key' to '(undef)'");
            $self->$key (undef);
        }
    }

    return $self;
}

=item key_to_remedy ()

=cut

sub key_to_remedy {
    my ($self) = @_;
    $self->logger_or_die->all ("pushing key values into remedy form");

    # Set the per-object accessors
    my %map = $self->field_map;
    foreach my $key (keys %map) {
        my $field = $map{$key};
        my $value = $self->$key;
        $self->set ($field, $self->$key);
    }
    return $self;
}

=item get (FIELD)

[...]

=cut

sub get {
    my ($self, $field) = @_;
    my $entry = $self->entry_or_die;

    unless ($entry->validate ($field)) {
        $self->logger_or_die->info ("invalid field: $field");
        return;
    }

    if (my $key = $self->key_field ($field)) {
        return $self->$key;
    } else {
        return $entry->data_to_human ($field, $entry->value ($field));
    }
}

=item set (FIELD, VALUE [, FIELD, VALUE [, FIELD, VALUE [...]]])

Takes a number of I<FIELD>/I<VALUE> pairs 

=cut

sub set {
    my ($self, %fields) = @_;
    my $entry  = $self->entry_or_die;
    my $logger = $self->logger_or_die;
    my $table  = $self->table;

    my %todo;

    foreach my $field (keys %fields) {
        return "no such field '$field'" unless $entry->validate ($field);

        my $value = $fields{$field};
        if (defined $value) { 
            my $data = $entry->human_to_data ($field, $value);
            return "invalid value '$value' for '$field'" unless defined $data;
            $todo{$field} = $data;
        } else { 
            $todo{$field} = undef
        }
    }

    return unless scalar keys %todo;

    $logger->debug (sprintf ("setting fields: %s", join (', ', keys %todo)));

    my %map = $self->field_map;
    foreach my $f (keys %todo) {
        my $human = defined $todo{$f} ? $todo{$f} : '(BLANK)';
        $logger->all ("setting value of  '$f' to '$human'");
        $entry->value ($f, $todo{$f});
        if (my $key = $self->key_field ($f)) {
            $logger->all ("setting key_field '$f' to '$human'");
            $self->$key ($todo{$f});
        }
    }
    
    return;
}

=back

=cut

##############################################################################
### Database Functions #######################################################
##############################################################################

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

=item limit (ARGHASH)

Gathers the components of a I<limit_ref> for B<read()>. Looks at each
field listed in B<fields ()>, and creates an array of limit components.  

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

=cut

sub limit {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die;
    my $logger = $parent->logger_or_die;
    my $entry  = $self->entry_or_die;

    if (my $id = $args{'ID'}) { return "'1' == \"$id\"" }
    if ($args{'all'}) { return '1=1' }

    _args_trace ($logger, 'before limit_pre ()', %args);
    %args = $self->limit_pre (%args);
    _args_trace ($logger, 'after  limit_pre ()', %args);

    my @limit;
    if (my $extra = $args{'extra'}) { 
        push @limit, ref $extra ? @$extra : $extra;  
        delete $args{'extra'};
    }

    my %fields = $entry->fields (%args);
    foreach my $field (keys %fields) {
        next unless exists $args{$field};

        ## Create the limit string
        my @args = ($field, $args{$field});
        my $limit = $entry->limit_string (@args);
        next unless defined $limit;

        push @limit, $limit;
        $logger->all ("adding limit: $limit");
    }

    $logger->all ('limit_post ()');
    $self->limit_post (@limit);

    $logger->debug ("limit: ", join (', ', @limit));
    @limit;
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
    my $logger = $self->logger_or_die;

    ## Make sure all data is reflected in the form
    my $entry = $self->entry or return 'no entry';
    my $class = $self->table;

    ## Load key data into main remedy form
    $self->key_to_remedy;

    $logger->debug ("saving data in $class");
    my $return = eval { $entry->save };
    unless ($return) { 
        $logger->error ("could not save: $@");
        return "could not save: $@";
    }

    ## Once again make sure the data is consistent
    $self->remedy_to_key;

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

=item create (TABLE, ARGHASH)

[...]

=cut

sub create {
    my ($self, $table, %args) = @_;
    return unless $table;

    my $parent = $self->parent_or_die (%args);
    my $logger = $self->logger_or_die ();

    $logger->debug ("pulling form information about '$table'");
    my $form = $self->form ($table);

    $logger->debug ("getting remedy entry for " . $form->table);
    my $entry = $self->new_entry ($form->table);

    $logger->debug ("new_from_form ()");
    return $form->new_from_form ($entry, 'table'  => $form->table, 
                                         'parent' => $parent);
}

=back

=cut

##############################################################################
### Helper Functions #########################################################
##############################################################################

=head2 Helper Functions

=over 4

=item new_entry (TABLE_NAME, ARGHASH)

Creates and returns a B<Remedy::FormData::Entry> object associated with the
table name I<TABLE_NAME> safely - meaning that the whole block is run as an
'eval'.  Returns the object on success, or undef on failure; if there is an
error message, it is returned as '$@'.

TODO: when we move these classes into the same library set and rename it to
B<Remedy::Form::Raw> or somesuch, we'll access that module here.

=cut

sub new_entry {
    my ($self, $table_name, %args) = @_;
    my $session = $self->session_or_die (%args);
    my $logger  = $self->logger_or_die (%args);
    my $cache   = $self->config_or_die (%args)->cache;

    return unless (defined $session && defined $table_name);

    my $data = eval { Remedy::FormData::Entry->new ('session' => $session,
        'name' => $table_name, 'cache' => $cache) };
    if ($@) { 
        $logger->debug ("no such form '$table_name' ($@)");
        return;
    } 
    return $data;
}

=item read (TABLE, WHERE, ARGHASH)

Reads from the database in the B<Remedy> object I<PARENT>.  

The selection is determined by I<WHERE>.  If I<WHERE> is a hashref, then we will 
pass its contents to B<limit ()> to create the selection limit.  Otherwise, we
will use the string I<WHERE> as the limitation itself.  For example, either of
these are valid:

    $form->read ('User', 1=1)
    $form->read ('User', { 'Full Name' => $name });

I<ARGHASH> is used to determine other information about the eventual selection.
Specifically:

=over 4

=item first (INT)

Which entry should we start counting from (for I<max>).  No default.

=item max (INT)

How many entries to return.  No default.

=back

Returns an array of objects, created with B<new_from_form ()>. Please see
Remedy::Database(8) for more details on the B<select ()> call used
to gather the data.

If invoked in a scalar context, only returns the first item.

=cut

sub read {
    my ($self, $table, $where, %args) = @_;
    my $parent = $self->parent_or_die ('need parent to read', 0, %args);
    my $session = $parent->session_or_die;
    my $logger  = $parent->logger_or_die;
    return unless $table;

    my (%extra, @debug);
    foreach (qw/max sort_id sort_dir first limit/) {
        next unless defined $args{$_};
        $extra{$_} = $args{$_};
        push @debug, "$_ => $args{$_}";
    }
    my @return;

    my @forms = $self->form ($table);
    unless (scalar @forms) { 
        $logger->warn ("no matching tables for '$table'");
        return;
    }

    foreach my $form (@forms) { 
        ## Figure out how we're limiting our search
        my $limit = ref $where ? join (" AND ", $form->limit (%$where))
                               : $where;
        unless ($limit) { 
            $logger->debug ("no search limits, skipping");
            next;
        }

        my $schema = $form->table;
        my $entry = $self->new_entry ($schema);

        ## Perform the search
        $logger->debug (sprintf ("read (%s)", 
            join (", ", $schema, $limit, @debug)));
        my @entries = $entry->read ($limit, %extra);
        $logger->debug (sprintf ("%d entr%s returned", scalar @entries, 
            scalar @entries == 1 ? 'y' : 'ies'));

        foreach my $entry (@entries) {
            push @return, $form->new_from_form ($entry, 
                'table' => $self->table, 'parent' => $parent);
        }
    }
    if (wantarray) { 
        $logger->all ("returning all " . scalar @return . " object(s)");
        return @return;
    } else {
        $logger->all ("returning first object of " . scalar @return);
        return $return[0];
    }
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

=item pull_formdata ()

=cut

sub pull_formdata {
    my ($self) = @_;
    my $parent = $self->parent_or_die;

    unless ($parent->formdata ($self->table)) {
        my $form = $self->new_entry ($self->table) || return;
        my $formdata = $form->formdata;
        $parent->formdata ($self->table, $formdata);
    }

    return $parent->formdata ($self->table);
}

=back

=cut

##############################################################################
### Functions To Override ####################################################
##############################################################################

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

Defaults to use B<as_string ()> on the underlying entry.

=cut

sub print { shift->entry->as_string (@_) }

=back

=cut

##############################################################################
### Helper Functions #########################################################
##############################################################################

=head2 Helper Functions

These functions are helpful either interally to this module, or might be useful
for any additional functions offered by any sub-modules.

=over 4

=item diff (OBJECT)

Finds the differences between the parent object and the passed-in object
I<OBJECT>.  Looks at each field from B<field_map ()> in I<OBJECT>; if it is both
defined in the new object and different from the related value of the old
object, then we consider that a difference.

Returns a hash of field/value pairs, where the keys are the changed fields and
the values are the values are from I<OBJECT>.

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

=item fields ()

Invokes B<fields> on the B<Remedy::Session::Entry> object.

=cut

sub fields { shift->entry_or_die->fields (@_) }

=item parent_or_die (ARGHASH)

Takes an arguemnt hash I<ARGHASH> from a parent function.  If the 'parent'
argument is in the argument hash, or if B<parent ()> is set, then return that;
otherwise, die.

[...]

'count'

=cut

sub parent_or_die  { 
    my ($self, %args) = @_;
    return $args{'parent'} if defined $args{'parent'};

    my $count = $args{'count'} || 0;
    my $text  = $args{'text'};

    if (ref $self) { 
        return $self->parent if defined $self->parent;
        $self->or_die ($self->parent, "no parent in object", $text, 
            $count + 1);
    } else { 
        return $self->or_die ($self->parent, "no 'parent' offered", $text, 
            $count + 1);
    }
}

=item validate ()

=cut

sub validate { shift->entry_or_die->validate (@_) }

=item session_or_die (ARGHASH)

=item logger_or_die  (ARGHASH)

=item config_or_die  (ARGHASH)

=item cache_or_die   (ARGHASH)

Pulls the session, logger, config, and cache data (respectively) from the parent
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

sub cache_or_die { 
    my ($self, %args) = @_;
    $args{'count'}++;
    $self->parent_or_die (%args)->cache_or_die;
}

=item entry_or_die ()

=cut

sub entry_or_die { $_[0]->or_die (shift->entry, 'no entry', @_) }

=item formdata_or_die () 

=cut

sub formdata_or_die { 
    $_[0]->or_die (shift->entry_or_die->formdata, 'no formdata', @_) 
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
        $form = $class->new_entry ($table, 'parent' => $parent);
        if ($@) {
            $@ =~ s/ at .*$//;
            $@ =~ s/(\(ARERR\s*\S+?\)).*$/$1/m;
            $logger->info ("no remedy form for '$table': $@");
            return;
        } elsif (!$form) { 
            $logger->info ("no remedy form for '$table': (NO ERROR)");
            return;
        }
    }
    $form->session ($session);

    ## Build and populate the object
    my $obj = {};
    bless $obj, $class;
    $obj->parent ($parent);
    $obj->table  ($table);
    $obj->entry  ($form);

    ## Reload the object, so as to fill in the key values, and return it
    return $obj->remedy_to_key;
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Remedy::Form::Utility>, B<Remedy::FormData::Entry>

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
