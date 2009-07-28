package Remedy::Session;
our $VERSION = "0.90";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Session - provides data connection to the Remedy database

=head1 SYNOPSIS

    use Remedy::Session;

    my $session = Remedy::Session->new (
        'type'     => 'ARS',
        'server'   => 'r7-app1-dev.stanford.edu',
        'username' => $user,
        'password' => $pass) or die "couldn't create remedy session: $@\n";

    eval { $session->connect } or die "error on connect: $@\n";

=head1 DESCRIPTION

Remedy::Session provides the data connection to the Remedy database.  It is
primarily a wrapper for B<Remedy::Session::ARS>, though it is written with the
understanding that we may eventually want B<Remedy::Session::Remctl>.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our %DEFAULT = ('type' => 'ARS');

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy::Session::ARS;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=head2 Constructor 

=over 4

=item new (ARGHASH)

Creates a new object of the appropriate B<Remedy::Session> sub-class.  
Chooses this sub-class based on I<ARGHASH>:

=over 2

=item type TYPE

Chooses which type of object to create based on I<TYPE>.  Currently supports:

    ARS         Remedy::Session::ARS        (DEFAULT)

=back

All other arguments are passed to B<new ()> in the appropriate object.

=cut

sub new {
    my ($proto, @rest) = @_;
    my %args = (%DEFAULT, @rest);
    my $type = $args{'type'} || 'none';
    if ($type eq 'ARS') { Remedy::Session::ARS->new    (%args)  }
    else                { die "invalid session type: '$type'\n" }
}

=back

=cut

##############################################################################
### Default Subroutines ######################################################
##############################################################################

=head2 Defaults and Examples

The following routines are defined as defaults, which are therefore inherited
by other classes and can be overridden as necessary.

=over 4

=item as_string ()

Returns a string describing the object - which, if you're invoking it from the
parent class, is just going to read I<INVALID OBJECT>.

=cut

sub as_string  { 'INVALID OBJECT' }

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Remedy::Session::ARS>

=head1 SEE ALSO

Remedy::Session::Remctl(8), Remedy(8)

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
