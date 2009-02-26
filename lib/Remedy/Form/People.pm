package Remedy::Form::People;
our $VERSION = "0.12";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form::People - users of Remedy

=head1 SYNOPSIS

    use Remedy::Form::People;

    # $remedy is a Remedy object
    foreach my $person ($remedy->read ('people', 'First Name' => "FIRST",
        'Last Name' => 'LAST')) {
        print scalar $person->print;
    }

=head1 DESCRIPTION

Remedy::Form::People manages the I<CTM:People> form in Remedy, which tracks
users that actually work with the Remedy system - for example, users
associated with a given support group (B<Remedy::Form::SupportGroup>,
B<Remedy::Form::SGA>).

Remedy::Form::People is a sub-class of B<Remedy::Form>, registered as I<people>.

Note that users that have actual system privileges are tracked with
B<Remedy::Form::User>.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy::Form qw/init_struct/;
use Remedy::Form::SGA;

our @ISA = init_struct (__PACKAGE__);
Remedy::Form->register ('people', __PACKAGE__);

##############################################################################
### Class::Struct Functions ##################################################
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<Person ID>)

Internal ID of the entry.

=item department (I<Department>)

e.g. I<IT Services>

=item first_name (I<First Name>)

=item netid (I<SUNET ID>)

Network ID of the user.  This is currently specific to Stanford, but can be set
to a different field for use at other sites.

=item name (I<Full Name>)

Full name of the person.  Generally formed by business logic by combining the
first and last names, so it's probably not worth setting except for searches.

=item last_name (I<Last Name>)

=item phone (I<Phone Number Business>)

=back

=cut

sub field_map {
    'id'            => "Person ID",
    'department'    => "Department",
    'first_name'    => "First Name",
    'last_name'     => "Last Name",
    'name'          => "Full Name",
    'netid'         => "SUNET ID",
    'phone'         => "Phone Number Business",

}

##############################################################################
### Local Functions ##########################################################
##############################################################################

=head2 Local Functions

=over 4

=item groups ()

Returns an array of all B<Remedy::Form::Group> entries associated with this 
user.  Uses B<sga ()>.

=cut

sub groups {
    my ($self, @rest) = @_;
    my @return;
    foreach my $sga ($self->sga (@rest)) { push @return, $sga->group }
    return @return;
}

=item sga ()

Returns a list of support group associations (B<Remedy::Form::SGA> objects) that
are associated with this user.

=cut

sub sga {
    my ($self, @rest) = @_;
    return unless my $id = $self->id;
    return $self->read ('Remedy::Form::SGA', 'Person ID' => $id, @rest);
}

=back

##############################################################################
### Remedy::Form Overrides ###################################################
##############################################################################

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map ()

=item print ()

Formats information about the user, including the username and email address
(based on B<netid ()> and the email domain configured in B<Remedy::Config>),
department, phone number, and associated support groups.

Returns an array of formatted lines in an array context, or a single string
separated with newlines in a scalar context.

=cut

sub print {
    my ($self) = @_;
    my $user = $self->netid;
    return unless $user;

    my @groups = $self->groups;

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

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 TODO

Make the 'netid' field configurable, for other institutions.

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy::Form>, B<Remedy::Form::SGA>

=head1 SEE ALSO

Remedy(8), Remedy::Form::SupportGroup(8), Remedy::Form::User(8)

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
