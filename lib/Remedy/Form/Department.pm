package Remedy::Form::Department;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Department - departments in remedy

=head1 SYNOPSIS

    use Remedy::Department;

    # $remedy is a Remedy object
    foreach my $dept (Remedy::Department->read ('db' => $remedy, 'all' => 1)) {
        print scalar $dept->print_text;
    }  

=head1 DESCRIPTION

Remedy::Department manages the I<CTM:People Organization> form in Remedy,
which describes the organization chart down to the department level.  

Remedy::Department is a sub-class of B<Remedy::Form>, registered as
I<department>.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy::Form qw/init_struct/;

our @ISA = init_struct (__PACKAGE__);
Remedy::Form->register ('department', __PACKAGE__);

##############################################################################
### Class::Struct Accessors ##################################################
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<People Organization ID>)

Internal ID of the entry

=item company (I<Company>)

e.g. I<Stanford University>

=item organization (I<Organization>)

e.g. I<Vice President for Business Affairs>

=item department (I<Department>)

e.g. I<IT Services>

=back

=cut

sub field_map { 
    'id'           => "People Organization ID",
    'company'      => "Company",
    'organization' => "Organization",
    'department'   => "Department",
}

##############################################################################
### Remedy::Form Overrides ###################################################
##############################################################################

=head2 B<Remedy::Form> Overrides

=over 4

=item field_map ()

=item print ()

Formats information about the department, including the company name,
organization name, and department name, as well as the entry's ID.

Returns an array of formatted lines in an array context, or a single string
separated with newlines in a scalar context.

=cut

sub print {
    my ($self) = @_;
    my @return = "Department information for '" . $self->department . "'";

    push @return, $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'ID'           => $self->id,
        'Company'      => $self->company,
        'Organization' => $self->organization,
        'Department'   => $self->department,
    );

    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'CTM:People Organization' }

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

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
