package Remedy::User;
our $VERSION = "0.12";  
our $ID = q$Id: Remedy.pm 4743 2008-09-23 16:55:19Z tskirvin$;
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::User - basic API interface

=head1 SYNOPSIS

  use Remedy;

See the various sub-scripts for more details.

=head1 DESCRIPTION

Remedy is meant to be a central repository of functions to read and,
in some cases, modify tickets in our local trouble ticket system.  It is
converted from some scripts for previous versions of the system.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Remedy;
use Remedy::Table;

our @ISA = qw/Remedy::User::Struct Stanford::Remedy::Table/;

struct 'Remedy::User::Struct' => {
    'parent'    => '$',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=item schema ()

Returns the data schema.

=cut

sub name { 'User' }

sub schema {
    return ( 
                 1 => "Request ID",
                 2 => "Creator",
                 3 => "Create Date",
                 4 => "Assigned To",
                 5 => "Last Modified By",
                 6 => "Modified Date",
                 7 => "Status",
                 8 => "Full Name",
                15 => "Status History",
               101 => "Login Name",
               102 => "Password",
               103 => "Email Address",
               104 => "Group List",
               108 => "Default Notify Mechanism",
               109 => "License Type",
               110 => "Full Text License Type",
               119 => "Computed Grp List",
               122 => "Application License",
               179 => "Unique Identifier",
         301628400 => "AR Horizontal Line 1",
         301628500 => "AR Header Text 1",
         301628600 => "AR System Application Title",
         301628700 => "Box4",
         301628800 => "Box5",
         490000000 => "Instance ID",
         490000100 => "Object ID" 
    );
}

=back

=cut

##############################################################################
### Final Documentation
##############################################################################

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
