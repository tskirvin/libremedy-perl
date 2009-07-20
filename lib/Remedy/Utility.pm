package Remedy::Utility;
our $VERSION = "0.01";

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Exporter;
use Remedy::Log;

our @ISA = qw/Exporter/;
our @EXPORT_OK = qw/or_die logger logger_or_die/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=item logger ()

=cut

sub logger { Remedy::Log->get_logger }

=item logger_or_die (TEXT)

=cut

sub logger_or_die { $_[0]->or_die (shift->logger, "no logger", @_) }

=item or_die (VALUE, ERROR, EXTRATEXT, COUNT)

Checks to see if I<VALUE> is true; if it is not, then we will die with an error
message based on the calling function (two levels above what is offered with
I<COUNT>, a generic error message I<ERROR>, and a developer-provided, optional
error message I<EXTRATEXT>.  This is not done through a B<Log::Log4perl>
function because the most common call is I<logger_or_die ()>.

Returns I<VALUE>.

Meant to be used with functions like:

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


1;
