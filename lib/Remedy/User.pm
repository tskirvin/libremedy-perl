package Remedy::User;
our $VERSION = "0.12";
our $ID = q$Id: Remedy.pm 4743 2008-09-23 16:55:19Z tskirvin$;
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::User - ticket-generation table

=head1 SYNOPSIS

    use Remedy;
    use Remedy::User;

    [...]

=head1 DESCRIPTION

Remedy::User tracks [...] 
It is a sub-class of B<Stanford::Packages::Form>, so
most of its functions are described there.

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy;
use Remedy::Form;

our @ISA = (Remedy::Form::init_struct (__PACKAGE__), 'Remedy::Form');

##############################################################################
### Class::Struct
##############################################################################

=head1 FUNCTIONS

These 

=head2 B<Class::Struct> Accessors

=over 4

=item description ($)

=item incnum ($)

=item submitter ($)

=back

=cut

##############################################################################
### Local Functions 
##############################################################################

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map

=cut

sub field_map { 
}

=item name ()

=cut

sub name {
    my ($self, %args) = @_;
    return $self->inc_num;
}

=item table ()

=cut

sub table { 'User' }

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
