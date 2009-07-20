package Remedy::Session;
our $VERSION = "0.01";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Session

=head1 SYNOPSIS

    use Remedy::Session;

    my $session = Remedy::Session->new (
        'server'   => 'r7-app1-dev.stanford.edu',
        'username' => $user,
        'password' => $pass) or die "couldn't create remedy session: $@\n";

    eval { $session->connect } or die "error on connect: $@\n";

=head1 DESCRIPTION

Currently (mostly) a wrapper for B<Stanford::Remedy::Session>; please see that
man page for details.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our %DEFAULT = ('default' => 'ARS');

##############################################################################
### Declarations #############################################################
##############################################################################

use Stanford::Remedy::Session;
use Remedy::Session::Cache;
use Remedy::Utility qw/or_die/;

use Class::Struct;

our @ISA = qw/Stanford::Remedy::Session/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

sub new {
    my ($proto, %args) = @_;
    $args{'type'} ||= $DEFAULT{'type'};
    if ($args{'type'} eq 'remctl') { Remedy::Session::Remctl->new (@_) }
    if ($args{'type'} eq 'ARS')    { Remedy::Session::Remctl->new (@_) }
    else { die "no such session type: '$type'\n" }
}

sub connect    { die "cannot connect without session type\n" }
sub disconnect { die "cannot disconnect without session type\n" }
sub as_string  { 'invalid object' }

sub type { 'unknown' }

foreach my $func (qw/remctl server ctrl username password tcpport lang
                     authString remctl_port port principal/) { 
    foreach my $sub ('', 'get_', 'set_') {
        my $text = "sub $func$sub { undef }";
        eval $text;
    }
}
sub get_server_or_die { 
    $_[0]->or_die (shift->get_server, "no server parameter", @_);
}

=head2 Subroutines

=over 4

=item error ()

Pulls the value of B<$ARS::ars_errstr>, and returns it (if it is defined) or
the string 'no ars error'.

=back

=cut

sub error {
    return defined $ARS::ars_errstr ? $ARS::ars_errstr : '(no ars error)';
}

=back

=head2 ARS Wrappers

=over 4

=item ars_GetField (NAME, FIELDID [, CACHE])

=cut

sub ars_GetField { return {} }

=item ars_GetFieldTable ([CTRL], SCHEMA)

=cut

sub ars_GetFieldTable { return () }

=item ars_GetFieldsForSchema (NAME [, CACHE])

=cut

sub ars_GetFieldsForSchema { return () }

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 TODO

Move B<Stanford::Remedy::Session> into here.

=head1 REQUIREMENTS

B<Stanford::Remedy::Session>

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
