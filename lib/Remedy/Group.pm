package Remedy::SGA;
our $VERSION = "0.12";  
our $ID = q$Id: Remedy.pm 4743 2008-09-23 16:55:19Z tskirvin$;
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::SGA - Support Group Association

=head1 SYNOPSIS

    use Remedy::SGA;

    # $remedy is a Remedy object
    [...]
    

=head1 DESCRIPTION

Stanfor::Remedy::SGA maps users (the B<User> table) to support groups
(B<Group>).

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Remedy;
use Remedy::Table;

our @ISA = qw/Remedy::System::Struct Stanford::Remedy::Table/;

struct 'Remedy::System::Struct' => {
    'parent'    => '$',
}

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=item table ()

=cut

sub table { 'Group' }

=item schema ()

=cut

sub schema {
    return ( 
                 1 => "Entry ID",
                 3 => "Create Time",
                 4 => "Login Name",
        1000000017 => "Full Name",
        1000000079 => "Group",
    );
}

=back

=cut

###############################################################################
### Final Documentation #######################################################
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

Copyright 2008 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
