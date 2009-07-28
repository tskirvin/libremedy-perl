package Remedy::Form::Group;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form::Group - user privilege groups form

=head1 SYNOPSIS

    use Remedy::Form::Group;

    # $remedy is a Remedy object
    foreach (Remedy::Form::Group->read ('db' => $remedy, 'all' => 1)) {
        print scalar $_->print_text;
    }

=head1 DESCRIPTION

Remedy::Form::Group manages the I<Group> form in Remedy, which tracks user
privilege groups.  

Remedy::Form::Group is a sub-class of B<Remedy::Form>, registered as 'group'.

Note that groups of users that are managing queues, for instance, are tracked
with B<Remedy::SupportGroup>.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy::Form qw/init_struct/;

our @ISA = init_struct (__PACKAGE__);
Remedy::Form->register ('group', __PACKAGE__);

##############################################################################
### Class::Struct ############################################################
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<Request ID>)

Internal ID of the entry.

=item name (I<Group Name>)

e.g. 'Sub Administrator'

=item summary (I<Long Group Name>)

=item description (I<Comments>)

=back

=cut

sub field_map {
    'id'          => 'Request ID',
    'name'        => 'Group Name',
    'summary'     => 'Long Group Name',
    'description' => 'Comments'
}

##############################################################################
### Remedy::Form Overrides ###################################################
##############################################################################

=head2 B<Remedy::Form> Overrides

=over 4

=item field_map ()

=item print ()

Returns an array of formatted lines in an array context, or a single string
separated with newlines in a scalar context.

=cut

sub print {
    my ($self) = @_;
    my @return = "Group information for '" . $self->name. "'";

    push @return, $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Name'        => $self->name,
        'Summary'     => $self->summary,
        'Description' => $self->description,
    );

    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'Group' }

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy::Form>

=head1 SEE ALSO

Remedy(8), Remedy::Form::SupportGroup(8)

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
