##############################################################################
### Configuration ############################################################
##############################################################################

our $CLASS = "Remedy::Form::SupportGroup";
our $ENTRY_COUNT = 3;

$ENV{'REMEDY_CONFIG'} = "./config-test";

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy;
use Test::More tests => 12;

##############################################################################
### Default Checks ###########################################################
##############################################################################
# 2 checks

use_ok ($CLASS);
ok (my $version = eval { '$' . $CLASS . "::VERSION" }, '$VERSION is set');
##############################################################################
### Arbitrary Data Lookup ####################################################
##############################################################################
# 7 checks

my $remedy = eval { Remedy->connect };
ok ($remedy, "connection created") or diag ("connection failed: $@");

ok (my %map = $CLASS->field_map, "$CLASS has a field map");
ok (my $table = $CLASS->table, "$CLASS has a table name");

ok (my $form = $remedy->form ($table), "have information about $table");
ok (my @entries = $remedy->read ($table, 'max' => $ENTRY_COUNT, 
    'where' => '1=1'), "can read information from $table");
ok (scalar @entries == $ENTRY_COUNT, "got the right number of entries");

my $entry = $entries[0];
ok (my $print = $entry->print, "entry prints");

##############################################################################
### Check the key fields #####################################################
##############################################################################
# 3 checks 

foreach (keys %map) { 
    ok (defined $entry->$_, "entry has key value $_") 
}
