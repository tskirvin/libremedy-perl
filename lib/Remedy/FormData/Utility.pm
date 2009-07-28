package Remedy::FormData::Utility;
$VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::FormData::Utility - additional functions for Remedy::FormData

=head1 SYNOPSIS

    use Remedy::FormData::Utility;

    [...]

=head1 DESCRIPTION

Remedy::FormData::Utility offers add...

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

## Number of characters designated for the field name in the debug functions
our $DEBUG_CHARS = 30;

## Default wrap width for Text::Wrap
$Text::Wrap::columns = 80;

## Default wrap type for Text::Wrap
$Text::Wrap::huge = 'overflow';

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;

use Exporter;
use POSIX qw/strftime/;
use Text::Wrap;

our @ISA = qw/Exporter/;
our @EXPORT = qw/as_string format_date format_text format_text_field/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=over 4

=item as_string (ARGHASH)

Creates a summary of all valid data within the current form, formatted for
screen output.  The lines are sorted numerically by field ID, and show the
field ID, the field name, and the set value.  All of this is then formatted for
80 characters and wrapped using B<Text::Wrap>.

I<ARGHASH>

=over 4

=item raw (0|1)

If set, then we will print the raw value of the database values in addition to
the human-converted ones.  These raw values will appear following the human
values.

=back

=cut

sub as_string {
    my ($self, %args) = @_;
    my %schema = $self->schema (%args);

    my (@entries, @return, %max);
    my ($maxid, $maxfield, $maxvalue);
    foreach my $id (sort {$a<=>$b} keys %schema) {
        next unless defined $schema{$id};
        my $field = $schema{$id};

        my $raw    = $self->value ($field);
        my $format = $self->data_to_human ($field, $raw);
        next unless defined $format;
        map { s/^\s+|\s+$//g } $format, $raw;

        $max{'id'}    = length ($id)    if length ($id)    > $max{'id'};
        $max{'field'} = length ($field) if length ($field) > $max{'field'};

        push @entries, [$id, $field || "*unknown*", $format, $raw];
    }

    $max{'field'} = $DEBUG_CHARS if $max{'field'} > $DEBUG_CHARS;

    foreach my $entry (@entries) {
        my ($id, $field, $value, $raw) = @{$entry};
        my $id_field    = '%'  . $max{'id'}    . 'd';
        my $field_field = '%-' . $max{'field'} . 's';
        my $size  = $max{'id'} + $max{'field'} + 2;

        my $form    = "$id_field $field_field %s";
        my $rawform = (' ' x $max{'id'}) . ' %-' . $max{'field'}. 's %s';

        push @return, wrap ('', ' ' x ($size), 
            sprintf ($form, $id, $field, $value));
        if ($args{'raw'} && $raw != $value) { 
            push @return, wrap ('', ' ' x ($size), 
                sprintf ($rawform, '  RAW VALUE', $raw));
        }
    } 

    wantarray ? @return : join ("\n", @return, '');
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

TODO: MAKE THIS WORK SOMEHOW

=cut

sub format_email {
    my ($self, $name, $email) = @_;
    $name ||= "";
    if ($email) { 
        $email .= '@' . $self->config_or_die->domain unless $email =~ /@/;
    } else { $email = "" }
    return $email ? "$name <$email>" : $name;
}   

=item format_text (ARGHASHREF, TEXT)

Formats 

=over 4

=item minwidth (CHARS)

=item prefix (STRING)

=back

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

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 TODO

=head1 REQUIREMENTS

B<Text::Wrap>

=head1 SEE ALSO

Remedy::FormData(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
