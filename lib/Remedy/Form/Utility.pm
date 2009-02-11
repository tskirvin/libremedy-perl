package Remedy::Form::Utility;

##############################################################################
### Configuration ############################################################
##############################################################################

## Number of characters designated for the field name in the debug functions
our $DEBUG_CHARS = 30;

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;

use POSIX qw/strftime/;
use Text::Wrap;

$Text::Wrap::columns = 80;
$Text::Wrap::huge    = 'overflow';

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head2 Subroutines 

=over 4

=item debug_pretty ()

Creates a summary of all valid data within the current form, formatted for
screen output.  The lines are sorted numerically by field ID, and show the
field ID, the field name, and the set value.  All of this is then formatted for
80 characters and wrapped using B<Text::Wrap>.

=cut

sub debug_pretty {
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

=item debug_table ()

=cut

sub debug_table {
    my ($self) = @_;
    return unless $self->remedy_form;
    return $self->remedy_form->as_string ('no_session' => 1);
}

=item format_date (TIME)

Given seconds-from-epoch I<TIME>, returns a date value that looks like
I<YYYY-MM-DD HH:MM:SS ZZZ>.  If I<TIME> is invalid, returns I<(unknown time)>.

=cut

sub format_date {
    my ($self, $time) = @_;  
    return '(unknown time)' unless $time;
    return strftime ('%Y-%m-%d %H:%M:%S %Z', localtime ($time));
}

=item format_email (NAME, EMAIL)

Tries to return something of the form 'name <address@email.com>'.  Both inputs
are optional, and default to an empty string.  I<NAME> is self-explanatory;
I<EMAIL> will have the value of the parent's I<DOMAIN> value added after the
'@' if one is not already offered.

=cut

sub format_email {
    my ($self, $name, $email) = @_;
    $name ||= "";
    if ($email) { 
        $email .= '@' . $self->parent->config->domain unless $email =~ /@/;
    } else { $email = "" }
    return $email ? "$name <$email>" : $name;
}   

=item format_text (ARGHASHREF, TEXT)

[...]

=cut

sub format_text {
    my ($self, $args, @print) = @_;
    $args ||= {};

    my $width  = $$args{'minwidth'} || 0;
    my $prefix = $$args{'prefix'} || '';

    my @return = wrap ($prefix, $prefix, @print);
    
    return wantarray ? @return : join ("\n", @return, '');   
}

=item format_text_field (ARGHASHREF, FIELD, TEXT [, FIELD2, TEXT2 [...]))

[...]

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
        $text =~ s/^\s+|\s+$//;
        my $value = defined $text ? $text : "*unknown*";
        push @entries, [$field, $value];
        $width = length ($field) if length ($field) > $width;
    }
    
    foreach my $entry (@entries) {
        my $field = '%-' . $width . 's';
        push @return, wrap ($prefix, $prefix . ' ' x ($width + 1), sprintf 
            ("$field %s", @{$entry})); 
    } 

    return wantarray ? @return : join ("\n", @return, '');   
}


1;
