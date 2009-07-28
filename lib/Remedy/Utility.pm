package Remedy::Utility;
our $VERSION = "0.02";

=head1 NAME

Remedy::Utility - utility functions for Remedy sub-modules

=head1 SYNOPSIS

    use Remedy::Utility qw/or_die logger_or_die/;

=head1 DESCRIPTION

Remedy::Utility offers a number of optional functions that can be imported by
other modules in the B<Remedy> family.  

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Exporter;
use Remedy::Log;

our @ISA       = qw/Exporter/;
our @EXPORT    = qw//;
our @EXPORT_OK = qw/or_die logger logger_or_die/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head2 Subroutines 

All of these are individually exported on request, but are not exported by
default.

=over 4

=item logger ()

Invokes B<Remedy::Log-E<gt>get_logger ()>, which grabs the default logger.  

=cut

sub logger { Remedy::Log->get_logger }

=item logger_or_die (TEXT)

Combines B<logger ()> and B<or_die ()>.  I<TEXT> is passed in as the
I<EXTRATEXT> in B<or_die ()>; the default error is simply I<no logger>.

The big trick is that, if the item called doesn't yet have its B<logger ()>
set, then we will pull the value from B<Remedy::Utility::logger ()>.

=cut

sub logger_or_die { 
    my ($self, @rest) = @_;
    my $logger = $self->logger || Remedy::Utility::logger;
    return $self->or_die ($logger, "no logger", @rest); 
}

=item or_die (VALUE, ERROR, EXTRATEXT, COUNT)

Checks to see if I<VALUE> is true; if it is not, then we will die with an error
message based on the calling function (two levels above what is offered with
I<COUNT>, a generic error message I<ERROR>, and a developer-provided, optional
error message I<EXTRATEXT>.  This is not done through a B<Log::Log4perl>
function because the most common call is I<logger_or_die ()>.

Returns I<VALUE>.

Meant to be used with functions like B<logger_or_die ()>:

    sub logger_or_die { $_[0]->or_die (shift->logger, "no logger", @_) }

=cut

sub or_die {
    my ($self, $value, $error, $extra, $count) = @_;
    return $value if $value;
    $count ||= 0;

    my $func;
    my $back = $count + 2;
    while ($back >= 0) { last if $func = (caller ($back--))[3] }

    chomp ($extra) if defined $extra;
    my $fulltext = sprintf ("%s: %s", $func, $extra ? "$error ($extra)"
                                                    : $error);
    die "$fulltext\n";
}

=back

=cut

1;

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Remedy::Log>

=head1 SEE ALSO

B<Exporter>

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University.

All rights reserved.

=cut
