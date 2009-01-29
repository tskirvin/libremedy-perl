package Remedy::Form::People;
our $VERSION = "0.12";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Person - ticket-generation table

=head1 SYNOPSIS

    use Remedy;
    use Remedy::Person;

    [...]

=head1 DESCRIPTION

Remedy::Person tracks [...] 
It is a sub-class of B<Stanford::Packages::Form>, so
most of its functions are described there.

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy::Form qw/init_struct/;
use Remedy::Form::SGA;

our @ISA = init_struct (__PACKAGE__, 'people');

##############################################################################
### Class::Struct
##############################################################################

=head1 FUNCTIONS

These 

=head2 B<Class::Struct> Accessors

=over 4

=item id ($)

=item netid ($)

=item name ($)

=back

=cut

##############################################################################
### Local Functions 
##############################################################################

sub group {
    my ($self, @rest) = @_;
    my @sga = $self->sga (@rest);
    my @return;
    foreach my $sga (@sga) {
        push @return, $sga->group
    }
    return @return;
}

sub sga {
    my ($self, @rest) = @_;
    return unless $self->id;
    return Remedy::Form::SGA->read ('db' => $self->parent_or_die (@rest),
        'Person ID' => $self->id, @rest);
}

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map

=cut

sub field_map { 
    'id'            => "Person ID",
    'netid'         => "SUNET ID",
    'name'          => "Full Name",
    'first_name'    => "First Name",
    'last_name'     => "Last Name",
    'department'    => "Department",
    'phone'         => "Phone Number Business",
}

=item print_text ()

=cut

sub print_text {
    my ($self) = @_;
    my $user = $self->netid;
    return unless $user;

    my @groups = $self->group;

    my @return = "Person information for '$user'";
    
    push @return, $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Name'           => $self->format_email (
            join (' ', $self->first_name, $self->last_name), $user),
        'Department'     => $self->department,
        'Phone'          => $self->phone,
        'Support Groups' => scalar @groups || "(none)",
    );
    foreach my $group (@groups) { push @return, '    ' . $group->name }
    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'CTM:People' }

=back

=cut

###############################################################################
### Final Documentation
###############################################################################

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy::Form>

=head1 SEE ALSO

Remedy(8)

=head1 HOMEPAGE

TBD.

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
