package Remedy::Form::SGA;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form::SGA - association form between Support Groups and People

=head1 SYNOPSIS

    use Remedy::Form::SGA;

    # $remedy is a Remedy object
    foreach my $sga ($remedy->read ('sga', 'all' => 1)) {
        print scalar $sga->print;
    }  

=head1 DESCRIPTION

Remedy::Form::SGA manages the I<CTM:Support Group Association> form in Remedy,
which maps together B<Remedy::Form::SupportGroup> and B<Remedy::Form::People>.

Remedy::Form::SGA is a sub-class of B<Remedy::Form>, registered as I<sga> and
I<supportgroupassociation>.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy::Form::People;
use Remedy::Form::SupportGroup;
use Remedy::Form qw/init_struct/;

our @ISA = init_struct (__PACKAGE__);

Remedy::Form->register ('sga', __PACKAGE__);
Remedy::Form->register ('supportgroupassocation', __PACKAGE__);

##############################################################################
### Class::Struct ############################################################
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<Support Group Association ID>)

Internal ID of the entry.

=item group_id (I<Support Group ID>)

Internal ID of the associated support group (B<Remedy::Form::SupportGroup>).  

=item login (I<Login ID>)

Network ID of the associated person.  Set in the database for convenience; 
business logic manages this, so don't try to set it.

=item name (I<Full Name>)

Full name of the associated person.  Again, a convenience offering in the
database.

=item person_id (I<Comments>)

Internal ID of the associated person (B<Remedy::Form::People>).  

=item role (I<Support Group Assocation Role>)

Not really sure, but it's populated and may be useful somehow.

=back

=cut

sub field_map { 
    'id'           => 'Support Group Association ID',
    'group_id'     => 'Support Group ID',
    'login'        => "Login ID",
    'name'         => 'Full Name',
    'person_id'    => 'Person ID',
    'role'         => 'Support Group Association Role',
}

##############################################################################
### Local Functions ##########################################################
##############################################################################

=head2 Local Functions

=over 4

=item group ()

Returns the B<Remedy::Form::SupportGroup> object associated with the ID saved
in B<group_id ()>.

=cut

sub group {
    my ($self, @rest) = @_;
    return unless my $id = $self->group_id;
    return $self->read ('Remedy::Form::SupportGroup', 'ID' => $id, @rest);
}

=item person ()

Returns the B<Remedy::Form::People> object associated with the ID saved in
B<person_id ()>.  

=cut

sub person {
    my ($self, @rest) = @_;
    return unless my $id = $self->person_id;
    return $self->read ('Remedy::Form::People', 'ID' => $id, @rest);
}

=back

=cut

##############################################################################
### Remedy::Form Overrides ###################################################
##############################################################################

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map ()

=item print ()

Formats information about the support-group assocation, including the person's
name and email address (based on B<login ()> and the email domain configured in
B<Remedy::Config>), the group's name, and the role of the association.

Returns an array of formatted lines in an array context, or a single string
separated with newlines in a scalar context.

=cut

sub print {
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

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy::Form>, B<Remedy::Form::SupportGroup>,
B<Remedy::Form::People>

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
