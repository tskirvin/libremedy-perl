##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy;
use Remedy::Session;
use Remedy::Session::ARS;
use Test::More tests => 3;

$ENV{'REMEDY_CONFIG'} = "./config-test";

##############################################################################
### Default Checks ###########################################################
##############################################################################
# 2 checks

ok ($Remedy::Session::VERSION);
ok ($Remedy::Session::ARS::VERSION);

##############################################################################
### Initial Connection #######################################################
##############################################################################

my $table = 'CTM:People Organization';
my $remedy = eval { Remedy->connect };

ok ($remedy, "connection created");
ok (my $session = $remedy->session, "session connected");

$session->disconnect() ; 



