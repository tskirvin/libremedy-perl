package Remedy::Database;
our $VERSION = "0.50";
our $ID = q$Id: Database.pm 4710 2008-09-12 19:32:02Z tskirvin $;
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Database - database connection for Remedy

=head1 SYNOPSIS

    use Remedy::Database;

    # $config is a Remedy::Config object
    my $db = Remedy::Database->connect ($config);
    my @entries = $db->select ('System', 'Hostname, OS');
    
=head1 DESCRIPTION

Remedy::Database offers a just-above-DBI layer for database
transactions, along with a query long and a few other helper functions.  This
lets us abstract away certain aspects of the database work, such as the actual
type of underlying database, debugging information, rollback-on-failure, and
(to some extent) query creation.  It is designed for use with the out-of-date
database created by B<Remedy>, but is hopefully general-purpose
enough to be used for other projects.

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use ARS;
use Class::Struct;

struct 'Remedy::Database' => {
    'ars'     => '$',
    'host'    => '$',
    'pass'    => '$',
    'port'    => '$',
    'user'    => '$',
    'debug'   => '$',
    'error'   => '$',
    'queries' => '@'
};

##############################################################################
### Subroutines
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> accessors

Remedy::Database is a Class::Struct object. 

=over 4

=item ars ($)

Remedy connection handle.

=item host ($)

Database host.

=item pass ($)

Database password.

=item port ($)

Database port.

=item user ($)

Database user.

=item debug ($)

If set, we will print debugging information about queries and such.

=item error ($)

Text of the last error message.

=item queries (@)

Query log.

=back

=head2 Object Methods 

The following methods are unique to this class.

=over 4

=item connect (CONFIG)

Builds the database connection.  Information to do this comes from either the
existing object (if offered) or the B<Remedy::Config> object
I<CONFIG>.  The fields that are used are the 'remedy_*' fields listed above.

On success, returns the Remedy::Database object; throws an
exception on fail.

=cut

sub connect {
    my ($self, $config, %args) = @_;
    unless (ref $self) { $self = $self->new () }

    foreach (qw/host user pass port/) { 
        my $rem = "remedy_$_";
        $self->$_ ($args{$_} || $config->$rem);
    }
    foreach (qw/debug/) { $self->$_ ($args{$_} || $config->$_) }

    my $host = $self->host;
    $self->warn_debug ("connecting to $host");
    my $ars = ars_Login ($host, $self->user, $self->pass, 0, 0, $self->port) 
        or die "login error: $ars_errstr\n";
    $self->ars ($ars);

    return $self;
}

=item disconnect

Removes the database handle (which should take care of disconnection).
Disconnect from the database, if we're connected, and remove the database
handle.

=cut

sub disconnect { 
    my ($self) = @_;
    my $ars = $self->ars || return;
    ars_Logoff ($ars);
    $self->ars (undef) 
}

=item insert (TABLE, DATAHASH)

Inserts a new item into table I<TABLE>, based on the Field/Value pairs 
in the hash I<DATAHASH>.  Returns the return code of the DBI.

=cut

sub insert {
    my ($self, $table, %insert) = @_;
    return $self->_err_undef ("no table offered")  unless $table;
    return $self->_err_undef ("nothing to insert") unless scalar %insert;

    my $keys   = join (', ', keys %insert);
    my $values = join (', ', ('?') x (scalar values %insert));

    my $query = "INSERT INTO $table ($keys) VALUES ($values)";
    my ($return, $sth) = $self->invoke ($query, values %insert);
    unless ($return) {
        return $self->_err_undef ("couldn't insert into $table:", $self->error);
    }
    return $return;
}


=item invoke (SQL [, BINDARRAY])

Invokes the query I<SQL>, with the bound data I<BINDARRAY> if offered.  Each
query is logged in the query log, and the database is rolled back on failure.

Depending on context, on success, returns either array containing the DBI
return status and the statement handle, or just the return status.  Retuns
undef on failure.

=cut

sub invoke {
    my ($self, $query, $table, $count, @query) = @_;
    my $ars = $self->ars || return;
    return unless defined $query && $table;

    $self->warn_debug ("query: '$query'");
    my $q = ars_LoadQualifier ($ars, $table, $query);
    $q or (warn "error: $ars_errstr\n" and return);

    $count ||= 0;
    my %entries = ars_GetListEntry ($ars, $table, $q, $count, 0);
    $self->error ($ars_errstr) if $ars_errstr;
    $self->add_query ($query);  # Save query to DB list

    my @return;
    foreach my $eid (keys %entries) { 
        my %data = ars_GetEntry ($ars, $table, $eid);
        next unless scalar %data;
        push @return, \%data;
    }

    return @return;
}

=item select (TABLE, SELECT [, LIMIT [, ORDER [, COUNT [, EXTRA]]]])

Creates a SQL query to select entries from the database, and runs it through
B<entries ()>. This involves a lot of potential input, so let's go through it:

=over 4

=item I<TABLE>

Table name.  Used with 'FROM'.  No default, but required.

=item I<SELECT>

Selection critera - what fields do we want?  I<SELECT> can be one of:

=over 2

=item arrayref 

Each entry is a field name that we want to return.

=item string

Field names are comma- and/or white-space delimited within the string.

=back

Results in a string of comma-separated fields, used with 'SELECT'.  
Defaults to '*'.

=item I<LIMIT>

Limiting criteria - decide which entries to return.  I<LIMIT> can be one of:

=over 2

=item hashref

For each I<key>/I<value> pair in the referenced hash, we will generate
an entry like 'I<key> like I<quote>', where I<quote> is the DBI-quoted
I<value>.  

=item arrayref

Each entry of the array is a fully parsed/escaped limiting criterion.  Use 
with B<limit_string ()>.

=back

Results in a string of ' AND ' separated fields, used with 'WHERE'.  No
default.

=item I<ORDER>

Ordering criteria - how do we order the entries?  Uses the same input types as
I<SELECT>, and is used with 'ORDER BY'.  Optional, no default.

=item I<COUNT>

Counting critera - how many entries do we want (and which ones)?  I<COUNT> can
be one of:

=over 2

=item string

Assumed to be 1-2 comma-delimited numbers; the first one is the number of 
entries we want, the second is the offset.  So, if you want 40 entries, just 
use the string '40'; if you want entries 11-40, use '30, 10'.

=item arrayref

The first entry is the count, the second is the offset.

=back

Used with 'LIMIT'.  Optional, no default. 

=item I<EXTRA>

Anything else you want to toss on the end of the SQL query.  Optional, no
default.

=back

Runs the resulting SQL query through B<entries ()>.  

=cut

sub select {
    my ($self, $table, $select_ref, $limit_ref, $order_ref, $count_ref, 
        @extra) = @_;
    my $ars = $self->ars or return $self->_err_undef ("no db on select ()");
    return $self->_err_undef ("no table offered") unless $table;

    my $select = $self->_select_ref_to_remedy ($select_ref) || "*";
    my $order  = $self->_order_ref_to_remedy  ($order_ref) || "";
    my $limit  = $self->_limit_ref_to_remedy  ($limit_ref) || "";
    my $count  = $self->_count_ref_to_remedy  ($count_ref) || "";

    return $self->entries ($limit, $table, 'count' => $count, 
        'select' => $select);
}

=item update (TABLE, LIMIT, SET)

Updates (an) existing entry(s) in the table I<TABLE>.  

=over 4

=item I<TABLE>

Table name.  

=item I<LIMIT>

Same as the limit criteria under B<select ()>.

=item I<SET>

A hashref, where the keys are the database fields that we want to update,
and the values are the new values.  (We will take care of quoting them
appropriately).

=back

Returns the return value of the DBI call.

=cut

sub update {
    my ($self, $table, $limit_ref, $set_ref) = @_;
    return $self->_err_undef ("no table offered") unless $table;
    my $ars = $self->ars or return $self->_err_undef ("no db on update");

    my $limit  = $self->_limit_ref_to_remedy  ($limit_ref)
        or return $self->_err_undef ("no/bad limit criteria on update");
    my %set = $self->_set_ref_to_remedy ($set_ref);
    return $self->_err_undef ("nothing to update") unless scalar keys %set;

    my @keys;
    foreach (keys %set) { push @keys, "$_ = $set{$_}" }
    my $set = join (', ', @keys);

    my $query = "UPDATE $table SET $set WHERE $limit";
    my ($return, $sth) = $self->invoke ($query);
    unless ($return) {
        return $self->_err_undef ("couldn't update $table:", $self->error);
    }
    return $return;
}

=back

=head2 Query Log

A major part of the reason for this package is to keep a log of all of the
database queries that have taken place on this connection, so they can be 
viewed in a debugging environment (like, say, the bottom of a malfunctioning
web page).  This is mostly handled through the B<queries ()> accessor, but a
little more work is needed to make this tool more convenient.

=over 4

=item add_query (QUERY)

Adds the query I<QUERY> to the query array.

=cut

sub add_query  {
    my ($self, $query) = @_;
    my $count = scalar @{$self->queries};
    return $self->queries ($count) unless $query;
    $self->queries ($count, $query);
}

=back

=head2 Helper Functions

These functions are mostly used internally by this class, and don't directly
equate to SQL functions, but may be useful for other functions.

=over 4

=item entries (QUERY, TABLE [, ARGHASH])

Invokes the query I<SQL> with B<invoke ()>, and returns an array of hashrefs
that contain the information for each entry returned.

=cut

sub entries {
    my ($self, $query, $table, %args) = @_;
    return $self->invoke ($query, $table, $args{'count'}, %args);
}

=item limit_string (TYPE, FIELD, VALUE)

Helper function to create a SQL selection query.  Based on I<TYPE>,  
returns:

=over 4

=item int

"I<FIELD>=I<VALUE>"

=item time

"I<FIELD>=I<VALUE>"

=item text

"I<FIELD> LIKE 'I<VALUE>'"

=back

=cut

sub limit_string {
    my ($self, $type, $field, $text) = @_;
    return "" unless $type;
    return "" if $text eq '%';
    return "'$type' == NULL" unless defined $text;
    return "'$type' = \"$text\"" if defined $text;
}

sub warn_debug {
    if (shift->debug) { warn __PACKAGE__ . ': ' . join (" ", @_) . "\n" };
}

=back

=cut

##############################################################################
### Internal Subroutines 
##############################################################################

### _count_ref_to_remedy (INPUT)
# Creates a 'COUNT' field.  INPUT can be:
#
#   arrayref => first item is number of entries, second is offset
#   string   => same as above, but comma-delimited.

sub _count_ref_to_remedy {
    my ($self, $input) = @_;
    return unless $input;

    my ($count, $offset);
    if (ref $input eq 'ARRAY') { 
        ($count, $offset) = @$input;
    } elsif (!ref $input) { 
        ($count, $offset) = split (/\s*,\s*/, $input);
    }
    
    return unless $count;
    return $offset ? "$count OFFSET $offset" : $count;
}

### _err_undef (TEXT)
# Set the error string and return undef.

sub _err_undef { shift->error (join (" ", @_)); return; }

### _limit_ref_to_remedy (INPUT)
# Creates a 'LIMIT BY' field.  INPUT can be: 
#
#   string   => return without modification
#   arrayref => generates entry list by running each array entry back 
#               into this function - so, if this is an arrayref of 
#               strings, then we'll end up with a whole lot of strings.
#   hashref  => keys are field names, values are quoted, use 'like' 
#               and quoting.  Not ideal for non-text fields.
#
# Returns a single string, with each entry joined with ' AND '.

sub _limit_ref_to_remedy { 
    my ($self, $input) = @_;
    return $input unless ref $input;

    my $ars = $self->ars or return $self->_err_undef ("no db connection");

    my @entries;
    if (ref $input eq 'ARRAY') { 
        for my $item (@$input) {
            next unless defined $item;
            push @entries, $self->_limit_ref_to_remedy ($item);
        }
    } elsif (ref $input eq 'HASH') { 
        my %hash = %$input;
        my $entry;
        for my $item (keys %hash) { 
            next unless defined $hash{$item};
            $entry = "$item like " . $ars->quote ($hash{$item});
            push @entries, $entry;
        }
    }
    join (" AND ", @entries);
}

### _order_ref_to_remedy (INPUT)
# Creates an 'ORDER' field.  

sub _order_ref_to_remedy { _select_ref_to_remedy (@_) }

### _select_ref_to_remedy (INPUT)
# Creates a 'SELECT' field.  INPUT can be:
#
#   arrayref => fields are the contents of the array
#   string   => fields are delimited by comma/white-space
#
# Returns a comma-separated list of fields.

sub _select_ref_to_remedy {
    my ($self, $input) = @_;

    my @entries;
    if (ref $input) { @entries = @$input } 
    else            { @entries = split /,\s*|\s+/, $input } 
    return join (", ", @entries);
}

## _set_ref_to_remedy (INPUT)
# Finds the necessary Field/Value pairs for a SET field.  INPUT can be:
#
#   string   => returns the item modification
#   arrayref => returns an array of the DBI-quoted contents of the arrayref
#   hashref  => returns a hash, where the keys are the keys to the hashref and 
#               values are the DBI-quoted values from the hashref
#
# Note that we're usually going to use the 'hashref' bit, and the other ones
# may or may not be useful (and/or well-tested).

sub _set_ref_to_remedy {
    my ($self, $input) = @_;
    # this isn't right
    return $input unless ref $input;

    my $ars = $self->ars or return $self->_err_undef ("no db connection");
    
    my %entries;
    if (ref $input eq 'ARRAY') { 
        my @return;
        for my $item (@$input) {
            next unless defined $item;
            push @return, $ars->quote ($item);
        }
        return @return;

    } elsif (ref $input eq 'HASH')  {
        my %hash = %$input;
        my $entry;
        for my $item (keys %hash) { 
            next unless defined $hash{$item};
            $entries{$item} = $ars->quote ($hash{$item});
        }
        return %entries; 
    } else { 
        return;
    }
}

# Disconnect the database handle on object destruction to avoid warnings.
sub DESTROY { shift->disconnect }   

##############################################################################
### Final Documentation
##############################################################################

=head1 TODO

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy> 

=head1 SEE ALSO

Remedy::Config(8), Remedy::Schema(8), 
Remedy::Table(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
