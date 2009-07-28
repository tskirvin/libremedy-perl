##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy;
use Remedy::FormData;
use Test::More tests => 14;

$ENV{'REMEDY_CONFIG'} = "./config-test";

##############################################################################
### Default Checks ###########################################################
##############################################################################
# 1 check

ok ($Remedy::FormData::VERSION);

##############################################################################
### Arbitrary Data Lookup ####################################################
##############################################################################
# 13 checks

my $table = 'CTM:People Organization';

my $remedy = eval { Remedy->connect };

ok ($remedy, "connection created");
ok (my $session = $remedy->session);

ok (my $data = Remedy::FormData->new ('session' => $session, 
    'name' => $table), "getting information from '$table'");
ok (my $data_nocache = Remedy::FormData->new ('session' => $session, 
    'name' => $table, 'nocache' => 1), "getting non-cached information");

ok ($data->name eq $table, "table names match");
ok ($data_nocache->name eq $table, "table names match again");

ok ($data->name_default, "we have default values");
ok ($data_nocache->name_default, "we have default values again");

ok ($data->cache, "our cache exists");
ok (! $data_nocache->cache, "cache doesn't exist when it shouldn't");

ok ($data->name_to_id, "there is a name-to-id map");
ok ($data->id_to_name, "there is an id-to-name map");
ok ($data->name_to_type, "there is a name-to-datatype map");
