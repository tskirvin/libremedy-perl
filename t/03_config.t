##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy::Config;
use Test::More tests => 4;

$ENV{'REMEDY_CONFIG'} = "./config-test";

##############################################################################
### Default Checks ###########################################################
##############################################################################
# 1 check

ok ($Remedy::Config::VERSION);

##############################################################################
### Config Checks ############################################################
##############################################################################
# 3 checks 

ok (my $config = Remedy::Config->load ($ENV{REMEDY_CONFIG}), 
    "can load the configuration file");
ok ($config->remedy_host, "config file mentions the remedy host");
ok ($config->debug, "we get a debugging summary");


### TODO: cache exists, log exists, a few variables exist
