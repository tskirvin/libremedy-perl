package Remedy::Department;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Department - Department form

=head1 SYNOPSIS

    use Remedy::Department;

    # $remedy is a Remedy object
    foreach my $dept (Remedy::Department->read ('db' => $remedy, 'all' => 1)) {
        print scalar $dept->print_text;
    }  

=head1 DESCRIPTION

Remedy::Department manages the I<CTM:People Organization> form, which describes
the organization chart down to the department level.  It is a sub-class of
B<Remedy::Table>, so most of its functions are described there.

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy::Table qw/init_struct/;

our @ISA = init_struct (__PACKAGE__);

##############################################################################
### Class::Struct
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item id (I<People Organization ID>)

Internal ID of the entry

=item company (I<Company>)

Company name, ie I<Stanford University>

=item organization (I<Organization>)

Organization name, ie I<Vice President for Business Affairs>

=item department (I<Department>)

Department name, ie I<IT Services>

=back

=cut

sub field_map { 
    'id'           => "People Organization ID",
    'company'      => "Company",
    'organization' => "Organization",
    'department'   => "Department",
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
