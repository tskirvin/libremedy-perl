package Remedy::Form::User;
our $VERSION = "0.12";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form::User - system accounts on remedy

=head1 SYNOPSIS

    use Remedy::Form::People;

    # $remedy is a Remedy object
    foreach my $user ($remedy->read ('user', 'all' => 1)) { 
        print scalar $user->print;
    }

=head1 DESCRIPTION

Remedy::Form::User manages the I<User> form in Remedy, which tracks system
accounts for the Remedy system - that is, accounts with usernames and
passwords.

Remedy::Form::User is a sub-class of B<Remedy::Form>, registered as 'user'.

Note that users that actually use the system are tracked with
B<Remedy::Form::People>.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy::Form qw/init_struct/;
use Remedy::Form::People;

our @ISA = init_struct (__PACKAGE__);
Remedy::Form->register ('user', __PACKAGE__);

##############################################################################
### Class::Struct Accessors ##################################################
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<Request ID>)

=item group_list (I<Group List>)

Not currently parsed.

=item name (I<Full Name>)

=item netid (I<Login Name>)

=back

=cut

sub field_map { 
    'id'         => 'Request ID',
    'group_list' => 'Group List',
    'name'       => "Full Name",
    'netid'      => "Login Name",
}

##############################################################################
### Remedy::Form Overrides ###################################################
##############################################################################

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map

=item print ()

Formats information about the user, including the name and network ID.

Returns an array of formatted lines in an array context, or a single string
separated with newlines in a scalar context.

=cut

sub print {
    my ($self) = @_;
    my $user = $self->netid;
    return unless $user;
    my @groups = $self->groups;

    my @return = "User information for '$user'";
    
    push @return, $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Full Name'   => $self->name,
        'SUNet ID'    => $self->netid || "(none)",
    );
    foreach my $group (@groups) {
        push @return, "    $group"
    }
    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'User' }

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy::Form>

=head1 SEE ALSO

Remedy(8), Remedy::Form::People(8)

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
