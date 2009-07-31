package Remedy::FormData;
our $VERSION = '0.08';
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::FormData - manage Remedy form attributes

=head1 SYNOPSIOS

    use Remedy::FormData;

    # $session is a Remedy::Session sub-object
    my $data = eval { Remedy::FormData->new ('session' => $session,
        'name' => 'FORM NAME');
    die "Failed to create new Remedy::FormData object: $@\n" if $@;

    my $error = $data->populate;
    die "could not populate object: $error\n" if $error;

    # Describe the entire object
    print scalar $data->as_string;

=head1 DESCRIPTION

Remedy::FormData manages the connections necessary to translate a Remedy
form (or table) into a collection of data hashes which describe both the
form and the fields contained within.  These fields have several attributes
including a numeric field id, field name, and a datatype.  Past the fields,
we also manage a data cache (B<Remedy::Cache>) and a copy of the data session
(B<Remedy::Session>).

In general, the end user will not use this class directly.  Instead,
manipulation of the data in the form takes place in B<Remedy::Form>.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

## How many characters should we save for the 'prefix' of a line when we're
## printing a single line of text?
our $LINE_PREFIX = 35;

## What should we name our cache variables?
our $CACHE_NAME  = __PACKAGE__;

## Which fields from the struct are we going to save in the cache?
our @CACHE_FIELDS = qw/name_to_id name_to_type name_to_enum name_update
                       name_default name_to_fopt/;

##############################################################################
### Public Variables #########################################################
##############################################################################

=head1 PUBLIC VARIABLES

These internal hashes map the integer values of various field data stored
within Remedy into human-readable descriptions.  They may be useful as
reference.  Note that these hashes are not exported.

=over 4

=item %DATATYPE_CODE_TO_TEXT

Maps datatype codes to text - i.e., I<2> to I<integer>.

=cut

our %DATATYPE_CODE_TO_TEXT = (
     2 => 'integer',
     3 => 'real',
     4 => 'character',
     6 => 'enum',
     7 => 'date',
    11 => 'attachment',
    12 => 'currency',
    31 => 'text',
    32 => 'button',
    33 => 'table_field',
    34 => 'column_title',
    35 => 'page',
    36 => 'page_holder',
    37 => 'attachment_pool',
);

=item %FORMTYPE_CODE_TO_DESC

Maps fieldtype codes to text - i.e. I<2> to I<join_form>.

=cut

our %FORMTYPE_CODE_TO_DESC = (
    0 => 'no_store',
    1 => 'other',
    2 => 'join_form',
    3 => 'view_form',
    4 => 'vendor_form',
);

=item %FOPT_CODE_TO_DESC

Maps fopt (field option) codes to text - i.e. <2> to <optional>.

=cut

our %FOPT_CODE_TO_DESC = (
    1 => 'required',
    2 => 'optional',
    3 => 'system',
    4 => 'display_only',
);

=back

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Remedy::Cache;
use Remedy::Log;
use Remedy::Utility qw/or_die logger_or_die/;

our @ISA = qw/Remedy::FormData::Struct/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

Remedy::FormData is a sub-classed B<Class::Struct> function - that is, it has
many functions that are created by B<Class::Struct>, but overrides the B<new
()> function for more

=head2 Basic Object and B<Class::Struct> Accessors

=over 4

=item new (ARGHASH)

Creates and returns the new object.  I<ARGHASH> is used to initialize the
underlying B<Class::Struct> object, but it also takes the following options:

=over 2

=item nocache I<INT>

If this is set, then we will remove the cache, even if it is offered.

If this is not set, and no cache is directly offered, then we will create a new
one on initialization.

=back

Fails if we do not have a name or a session.  

Returns the object on success, dies on failure.

=cut

sub new {
    my ($proto, %args) = @_;
    my $class = ref ($proto) || $proto;
    my $self = Remedy::FormData::Struct->new (%args);
    bless $self, $class;

    ## Get the logger.
    my $logger = $self->logger || $self->logger (Remedy::Log->logger);

    if (! $args{'nocache'} && !$self->cache) {
        $self->cache (Remedy::Cache->new ('namespace' => $CACHE_NAME));
    }

    my $name    = $self->name_or_die ('cannot initialize without a name');
    my $session = $self->session_or_die;

    # $self->populate;

    return $self;
}

=back

=cut

##############################################################################
### Class::Struct Accessors ##################################################
##############################################################################

=head2 B<Class::Struct> Accessors

These fields can be initialized via B<new ()> or per-function.

=over 4

=item cache (Remedy::Cache)

A data cache.

=item logger (Log::Log4perl::Logger)

A B<Log::Log4perl::Logger> object.  If not offered on initialization, we will
try to pull the logger using B<Remedy::Log-E<gt>logger>.

=item name ($)

The name of the form/table.

=item name_default (%)

Map field names to their default values.

=item name_to_enum (%)

Map field names to possible enumerated values for that field (values are
arrayrefs).

=item name_to_fopt (%)

Map field names to the field options attribute.

=item name_to_id (%)

Map field names to field IDs.

=item name_to_type (%)

Map field names to the datatype attribute.

=item name_update (%)

Map field names to the 'is this updateable' attribute.

=item session (Remedy::Session)

The B<Remedy::Session> object.

=cut

struct 'Remedy::FormData::Struct' => {
    'cache'        => 'Remedy::Cache',
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

=back

=cut

##############################################################################
### Main Functions ###########################################################
##############################################################################

=head2

=over 4

=item populate ()

Populates the object.  If possible, we will pull the information from the data
cache; if the data is not stored there, we will use B<populate_from_session
()> (and then store the data in the cache if the cache is enabled at all).

=cut

sub populate {
    my ($self) = @_;
    my $logger = $self->logger_or_die;
    my $name   = $self->name_or_die;

    my $cache_key = $self->cache_key if $self->cache;
    if ($cache_key) {
        my $error = $self->cache_read ($cache_key);
        return unless $error;
        $logger->debug ("info about $name not found in cache: $error");
    }
    $logger->debug ("populating $name from session");
    my $return = $self->populate_from_session;

    $self->cache_write ($cache_key) if $cache_key;
    return $return;
}

=item populate_from_session ()

Populates the object without even considering the cache.  This requires two
calls to the B<Remedy::Session> object: B<GetFieldTable ()> to retrieve
field-to-ID mappings, and B<GetFieldsForSchema ()> to retrieve the rest
of the information.  Be warned: this is fairly complicated on the back-end.

=cut

sub populate_from_session {
    my ($self) = @_;
    my $logger  = $self->logger_or_die;
    my $session = $self->session_or_die ("cannot populate without session");
    my $name    = $self->name_or_die;

    ## Initialize all the mappings to be empty.
    my (%name_to_type, %name_default, %name_to_fopt, %name_update,
        %name_to_enum, %id_to_enum);

    ## Retrieve field <-> id mappings
    my %name_to_id = $session->GetFieldTable ($name, $self->cache);
    $logger->all (sprintf ("%d fields in table", scalar keys %name_to_id));

    ## Get mappings of name to datatype, defaultValue, fOption, etc
    $logger->all ("GetFieldsForSchema ($session, $name)");
    my %id_to_property = $session->GetFieldsForSchema ($name, $self->cache);

    ## Keep track of a list of fields that we don't want to track.
    my @remove;

    ## Populate the hashes
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
        #   1 --> required     (YES)
        #   2 --> option       (YES)
        #   3 --> system       (NO)
        #   4 --> display only (NO)
        $name_update{$name} = $id if ($option <= 2);

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

        ## 'attach' fields are sometimes buggy?  Guess so.  Drop them.
        ## (may want to drop 'attach_pool' too.)
        if ($datatype eq 'attach') { push @remove, $id }
    }

    my %id_to_name = reverse %name_to_id;

    ## Loop through all the mappings and set $name_to_enum
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


    ## Set the object values appropriately
    $self->name_to_id   (\%name_to_id);
    $self->name_to_type (\%name_to_type);
    $self->name_default (\%name_default);
    $self->name_to_fopt (\%name_to_fopt);
    $self->name_update  (\%name_update);
    $self->name_to_enum (\%name_to_enum);

    ## Status History (fieldId 15) is weird: it is not really a field at all,
    ## so delete it.  Or at least that's what Adam said.
    push @remove, 15;

    ## Actually remove the fields we don't want to see again.
    foreach (@remove) { $self->delete_fieldId ($_) }

    return;
}

=item delete_fieldId (ID)

Delete the field ID I<ID> from all of the B<name_*> mappings.  

=cut

sub delete_fieldId {
    my ($self, $fieldid) = @_;

    my $name_to_id = $self->name_to_id;
    my $id_to_name = $self->id_to_name;

    my $name_to_type = $self->name_to_type;
    my $name_update  = $self->name_update;

    my $fieldname = $id_to_name->{$fieldid};
    if (!$fieldname) {
        $self->logger_or_die->warn ("no name for field ID '$fieldid'");
        return;
    }

    delete $name_to_id->{$fieldname};
    delete $name_to_type->{$fieldname};
    delete $name_update->{$fieldname};

    return;
}

=back

=cut

##############################################################################
### Cache Management #########################################################
##############################################################################

=head2 Cache Management

=over 4

=item cache_key ()

Creates a cache 'key'.

=cut

sub cache_key {
    my ($self) = @_;
    my ($package, $filename, $line) = caller (1);
    return join (';', $package, $self->session_or_die->server_or_die,
        $self->name_or_die);
}

=item cache_read (KEY)

Takes I<RESULTS> - a value returned from B<Remedy::Cache> - and
populates the I<name_*> fields with it.

=cut

sub cache_read {
    my ($self, $key) = @_;
    return "no key" unless $key;

    $self->logger_or_die->all ("reading '$key' from cache");
    if (my $results = $self->cache_or_die->get_value ($key)) {
        foreach my $f (@CACHE_FIELDS) { $self->$f ($results->{$f}) }
        return;
    } else {
        return "no match";
    }
}

=item cache_write (KEY)

Populates the cache with the key I<KEY> the value

=cut

sub cache_write {
    my ($self, $key) = @_;
    return "no key" unless $key;

    my %store = ();
    foreach my $f (@CACHE_FIELDS) { $store{$f} = $self->$f }

    $self->logger_or_die->all ("writing '$key' to cache");
    return $self->cache_or_die->set_value ($key, \%store) ? 0 : 1;
}

=item id_to_name ()

Returns a hash reference mapping field IDs to field names.  This is actually
just an inverted version of B<name_to_id ()>.

=cut

sub id_to_name {
    my $name_to_id = shift->name_to_id;
    my %reverse = reverse %$name_to_id;
    return \%reverse;
}

=item as_string ()

=cut

sub as_string {
    my ($self, $values_href, %opts) = @_;
    $values_href ||= {};

    my @return;
    if (! $opts{'no_session'}) {
        my $session = $self->session;
        if ($session) { push @return, $session->as_string ('  ') }
        else          { push @return, "session undefined"        }
    }

    push @return, _display_one_line ('Form Name', $self->name);
    push @return, '';

    my %name_to_id   = %{ $self->name_to_id };
    my %name_to_type = %{ $self->name_to_type };
    my %name_default = %{ $self->name_default };
    my %name_to_fopt = %{ $self->name_to_fopt };
    my %name_to_enum = %{ $self->name_to_enum };

    my $session = $self->session;


    # Sort according to value of key
    my $sort_fref = sub { (0 + $name_to_id{$a}) <=> (0 + $name_to_id{$b}) };

    foreach my $name (sort $sort_fref keys %name_to_id) {
        my $id = $name_to_id{$name};

        ## 1. Get the datatype
        my $datatype = $name_to_type{$name};

        my $datatype_text = $datatype;
        if (exists $DATATYPE_CODE_TO_TEXT{$datatype}) {
            $datatype_text = $DATATYPE_CODE_TO_TEXT{$datatype};
        }

        ## 2. Get the value
        my $value;
        if    (exists $values_href->{$name}) { $value = $values_href->{$name} }
        else                                 { $value = '<NULL>' }

        $value = '<CONFUSED>' unless defined $value;

        ## 3. Is there a default value?
        my $default = $name_default{$name};

        my @notes;

        my $fopt = $name_to_fopt{$name};
        push @notes, $FOPT_CODE_TO_DESC{$fopt};

        ## Actually create the entry.
        push @return, _display_one_line ($name, sprintf ("%s [%10d %8s] %s",
            $value, $id, $datatype_text, $FOPT_CODE_TO_DESC{$fopt}));

        ## Defaults get listed on the next line
        if (defined $default) {
            push @return, _display_one_line (" - default", $default);
        }

        ## Is this an enum?
        if ($name_to_enum{$name})  {
            my $enum_values = $name_to_enum{$name};
            push @return, _format_enum_values ($enum_values);
        }
    }

    return wantarray ? @return : join ("\n", @return, '');
}

=back

=cut

##############################################################################
### Additional Accessors #####################################################
##############################################################################

=head2 Additional Accessors 

=over 4

=item cache_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<cache ()>.

=cut

sub cache_or_die    { $_[0]->or_die (shift->cache,   "no cache",   @_) }

=item ctrl_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<ctrl ()>.

=cut

=item logger_or_die ()

See B<Remedy::Utility::logger_or_die ()>.

=cut

=item name_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<name ()>.

=cut

=item session_or_die ()

Uses B<Remedy::Utility::or_die ()> to get the value of B<session ()>.

=cut

sub ctrl_or_die     { $_[0]->or_die (shift->ctrl,    "no ctrl",    @_) }
sub name_or_die     { $_[0]->or_die (shift->name,    "no name",    @_) }
sub session_or_die  { $_[0]->or_die (shift->session, "no session", @_) }

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
    my $prefix = qq/$attribute /;
    my $length = $LINE_PREFIX - length ($prefix);
    my $spaces = ' ' x $length;
    $value = '' unless defined $value;
    return join ('', $prefix, $spaces, $value);
}

sub _format_enum_values {
    my ($enum_values_href) = @_;
    my %enum_values = %$enum_values_href;

    my @return;
    foreach my $key (sort {$a<=>$b} keys %enum_values) {
        push @return, _display_one_line (sprintf (" - enum value %-3d", $key),
            $enum_values{$key});
    }
    return wantarray ? @return : join ("\n", @return, '');
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 NOTES

=head2 IGNORED FIELDS

B<Remedy::FormData>, while intended to be all-inclusive, does drop a few fields
in order to function properly.

=over 4

=item Field ID 15 (I<Status History>)

This is apparently a weird field.  Adam commented in his original code:

    Status History (fieldId '15') is weird: it is not really a
    field at all, so delete it.

I don't quite understand why it's weird, but I can confirm that it *is* weird.
It is a regular 'system' type field, too, so I don't understand why.

=item All Fields with datatype I<attach>

Every time we have encounted this field type, it has caused problems with SQL
select statements (error I<ORA-00918: column ambiguously defined>).  We haven't
had to use it yet, either.  More information would probably be helpful, but for
now, dropping the field it seems the best way to go.

=back

=head1 REQUIREMENTS

B<Remedy::Cache>, B<Remedy::Log>

=head1 SEE ALSO

B<Remedy::FormData::Entry>

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

Based on B<Stanford::Remedy::FormData> by Adam Lewenberg <adamhl@stanford.edu>

=head1 COPYRIGHT & LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
