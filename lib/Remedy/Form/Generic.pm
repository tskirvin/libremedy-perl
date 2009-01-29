package Remedy::Form::Generic;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form::Generic - generic remedy forms

=head1 SYNOPSIS

    use Remedy::Department;

    # $remedy is a Remedy object
    foreach my $dept (Remedy::Department->read ('db' => $remedy, 'all' => 1)) {
        print scalar $dept->print_text;
    }  

=head1 DESCRIPTION

Remedy::Department manages the I<CTM:People Organization> form, which describes
the organization chart down to the department level.  It is a sub-class of
B<Remedy::Form>, so most of its functions are described there.

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy::Form qw/init_struct/;

our @ISA = init_struct (__PACKAGE__, 'generic');

##############################################################################
### Class::Struct
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

None.

=cut

sub field_map { }

sub table_human { shift->table }

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
