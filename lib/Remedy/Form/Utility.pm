package Remedy::Form::Utility;

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
