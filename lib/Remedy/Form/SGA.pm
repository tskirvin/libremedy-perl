package Remedy::Form::SGA;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::SGA - Support Group Association form

=head1 SYNOPSIS

    use Remedy::SGA;

    # $remedy is a Remedy object
    foreach my $group (Remedy::SGA->read ('db' => $remedy, 'all' => 1)) {
        print scalar $group->print_text;
    }  

=head1 DESCRIPTION

Remedy::SGA manages the I<CTM:Support Group Association> form, which maps
together users and support groups.  It is a sub-class of B<Remedy::Form>, so
most of its functions are described there.

[...]

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy::Form::People;
use Remedy::Form::SupportGroup;
use Remedy::Form qw/init_struct/;

our @ISA = init_struct (__PACKAGE__, 'sga');

##############################################################################
### Class::Struct
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<Support Group Association ID>)

Internal ID of the entry.

=item person (I<Full NameName>)

Locally stored name of the associated person, ie 'Tim Skirvin'.

=item group_id (I<Support Group ID>)

Internal ID of the associated group.  

=item person_id (I<Comments>)

A longer, text description of the purpose of the group

=item role (I<Support Group Assocation Role>)

Not really sure, but it's populated and may be useful somehow.

=back

=cut

sub field_map { 
    'id'           => 'Support Group Association ID',
    'login'        => "Login ID",
    'name'         => 'Full Name',
    'group_id'     => 'Support Group ID',
    'person_id'    => 'Person ID',
    'role'         => 'Support Group Association Role',
}

##############################################################################
### Local Functions 
##############################################################################

=head2 Associations 

=over 4

=item group

=cut

sub group {
    my ($self, @rest) = @_;
    return unless $self->group_id;
    return Remedy::Form::SupportGroup->read (
        'db' => $self->parent_or_die (@rest), 'ID' => $self->group_id, @rest);
}

=item person ()

=cut

sub person {
    my ($self, @rest) = @_;
    return unless $self->group_id;
    return Remedy::Form::People->read ('db' => $self->parent_or_die (@rest),
        'ID' => $self->person_id, @rest);
}

=back

=head2 B<Remedy::Form Overrides>

=over 4

=item print_text ()

=cut

sub print_text {
    my ($self, @rest) = @_;
    my @return = "SGA information for '" . $self->name. "'";

    my $group = $self->group or return 'no such group: ' . $self->group_id; 
    push @return, $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'ID'          => $self->id,
        'Person'      => $self->format_email ($self->name, $self->login),
        'Group'       => $group->name,
        'Role'        => $self->role,
    );

    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'CTM:Support Group Association' }

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
