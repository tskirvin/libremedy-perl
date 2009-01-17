package Remedy::SupportGroup;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::SupportGroup - Department form

=head1 SYNOPSIS

    use Remedy::SupportGroup;

    # $remedy is a Remedy object
    foreach my $group (Remedy::SupportGroup->read ('db' => $remedy, 'all' => 1)) {
        print scalar $group->print_text;
    }  

=head1 DESCRIPTION

Remedy::SupportGroup manages the I<SupportGroup> form, which manages access privileges
for groups of users.  It is a sub-class of B<Remedy::Table>, so most of its
functions are described there.

Note that if you're looking for the support group mappings, you should see
B<Remedy::SupportSupportGroup>.

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy::Table qw/init_struct/;
use Remedy::SGA;

our @ISA = init_struct (__PACKAGE__);

##############################################################################
### Class::Struct
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<Request ID>)

Internal ID of the entry.

=item name (I<SupportGroup Name>)

Name of the group, ie 'Sub Administrator'

=item summary (I<Long SupportGroup Name>)

A short description of the group 

=item description (I<Comments>)

A longer, text description of the purpose of the group

=back

=cut

sub field_map { 
    'id'          => 'Support Group ID',
    'name'        => 'Support Group Name',
    #'summary'     => 'Long SupportGroup Name',
    #'description' => 'Comments'
}

##############################################################################
### Local Functions 
##############################################################################

=head2 B<Remedy::Table Overrides>

=over 4

=item print_text ()

=cut

sub print_text {
    my ($self) = @_;
    my @return = "SupportGroup information for '" . $self->name. "'";

    push @return, $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Name'        => $self->name,
        #'Summary'     => $self->summary,
        #'Description' => $self->description,
    );

    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'CTM:Support Group' }

=back

=cut

###############################################################################
### Final Documentation
###############################################################################

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy::Table>

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
