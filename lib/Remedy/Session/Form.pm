package Remedy::Session::Form;
our $VERSION = "0.01";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Session

=head1 SYNOPSIS

    use Remedy::Session::Form;

=head1 DESCRIPTION

Currently just a wrapper for B<Stanford::Remedy::Form>; please see that man
page for details.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use Stanford::Remedy::Form;

our @ISA = qw/Stanford::Remedy::Form/;

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 TODO

Move B<Stanford::Remedy::Form> into here.

=head1 REQUIREMENTS

B<Stanford::Remedy::Form>

=head1 SEE ALSO

Remedy(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
