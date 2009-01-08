package Stanford::Remedy::SupportGroup;
our $VERSION = "0.12";
our $ID = q$Id: Remedy.pm 4743 2008-09-23 16:55:19Z tskirvin$;
# Copyright and license are in the documentation below.

=head1 NAME

Stanford::Remedy::SupportGroup - Support Group Association

=head1 SYNOPSIS

    use Stanford::Remedy::SupportGroup;

    # $remedy is a Stanford::Remedy object
    [...]

=head1 DESCRIPTION

Stanford::Remedy::SupportGroup [...]

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Stanford::Remedy;
use Stanford::Remedy::Table;

our @ISA = qw/Stanford::Remedy::SupportGroup::Struct Stanford::Remedy::Table/;

struct 'Stanford::Remedy::SupportGroup::Struct' => {
    'parent'    => '$',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=over 4

=item name ()

=cut

sub name { 'CTM:Support Group' }

=item schema ()

=cut

sub schema {
    return (
                 1 => "Entry ID",
                 3 => "Create Time",
        1000000015 => "Group",
    );
}

=back

=cut

###############################################################################
### Final Documentation #######################################################
###############################################################################

=head1 REQUIREMENTS

B<Class::Struct>, B<Stanford::Remedy::Table>

=head1 SEE ALSO

Stanford::Remedy(8)

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
