package Remedy::Form::SupportGroup;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form::SupportGroup - groups of active users in Remedy

=head1 SYNOPSIS

    use Remedy::Form::SupportGroup;

    # $remedy is a Remedy object
    foreach my $group (Remedy::Form::SupportGroup->read ('db' => $remedy, 
        'all' => 1)) {
        print scalar $group->print;
    }  

=head1 DESCRIPTION

Remedy::Form::SupportGroup manages the I<CTM:Support Group> form, which        
manages small business units (at the "help desk" level, for instance).         

Remedy::Form::SupportGroup is a sub-class of B<Remedy::Form>, registered as
I<supportgroup>.

Note that groups that have actual system privileges are managed with 
B<Remedy::Form::Group>.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy::Form qw/init_struct/;
use Remedy::Form::SGA;

our @ISA = init_struct (__PACKAGE__);
Remedy::Form->register ('supportgroup', __PACKAGE__);

##############################################################################
### Class::Struct Functions ##################################################
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<Support Group ID>)

Internal ID of the entry.

=item name (I<Support Group Name>)

e.g. "ITS Help Desk Level 2"

=item email (I<Alternate Group Email Address>)

An email address that gets sent copies of all unassigned work.  Usually set to
a group email account, or a mail-to-news gateway, or something similar.

=back

=cut

sub field_map { 
    'id'    => 'Support Group ID',
    'name'  => 'Support Group Name',
    'email' => 'Alternate Group Email Address',
}

##############################################################################
### Local Functions ##########################################################
##############################################################################

=head2 Local Functions 

=over 4

=item person ()

Returns an array of all B<Remedy::Form::People> entries associated with this
support group.  Uses B<sga ()>.

=cut

sub person {
    my ($self, @rest) = @_;
    my @sga = $self->sga (@rest);
    my @return;
    foreach my $sga (@sga) { push @return, $sga->person }
    return @return;
}

=item sga ()

Returns a list of support group associations (B<Remedy::Form::SGA> objects)
that are associated with this support group.

=cut

sub sga {
    my ($self, @rest) = @_;
    return unless my $id = $self->id; 
    return $self->read ('Remedy::Form::SGA', 'Support Group ID' => $id, @rest);
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

Formats information about the support group, including the group's name and
email address, the number of members, and a list of those members.

Returns an array of formatted lines in an array context, or a single string
separated with newlines in a scalar context.

=cut

sub print {
    my ($self) = @_;
    my @return = "Group information for '" . $self->name. "'";

    my @people = $self->person;

    push @return, $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Name'                => $self->name,
        'Group Email Address' => $self->email || '(none)',
        'Number of Members'   => scalar @people || 0,
    );
    foreach my $person (@people) { push @return, '    ' . $person->name }

    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'CTM:Support Group' }

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy::Form>, B<Remedy::Form::SGA>

=head1 SEE ALSO

Remedy(8), Remedy::Form::People(8), Remedy::Form::Group(8)

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
