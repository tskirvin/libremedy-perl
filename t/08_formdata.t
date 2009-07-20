use Test::More tests => 7;

use Remedy::Session::Form::Data;
use Remedy::Session;
use Remedy::Testing;
use Remedy::Session::Cache;

ok ($Remedy::Session::Form::Data::VERSION);

my ($formdata, $start_time, $end_time, $tmp); 

###
### Create a session
my $session = Remedy::Testing::make_session(); 

ok ($session); 
ok ($session->connect());

#Remedy::Cache::turn_global_caching_off();
Remedy::Session::Cache::turn_global_caching_on();

$formdata = Remedy::FormData->new (
    name     => 'HPD:Help Desk',
    session  => $session,
); 

ok ($formdata); 

# Dump the formdata into a file
$tmp = $formdata->as_string ();
ok ($tmp); 

# Dump the formdata for HPD::HelpDesk into a file.
$formdata = Remedy::FormData->new(
  name => 'HPD:Help Desk',
  session  => $session,
); 
$tmp = $formdata->as_string();
ok ($tmp); 
Remedy::Testing::write_string_to_file($tmp, './HPD_Help_Desk.txt');


## Get a mapping from fieldname to fieldid
#$start_time = time(); 
#my %fieldname_to_fieldid = (); 
#for (my $i=0; $i<100; ++$i) 
#{
#  %rv = Remedy::FormData::get_hash_ref_mapping_from_sql(
#               SESSION => $session,
#               QRY     => 'SELECT name, schemaId FROM arschema',
#                                      );
#  ok (%rv); 
#}

# Time how long it takes to do a formdata populate with caching turned OFF.
#Remedy::Cache::turn_global_caching_off();

$start_time = time(); 
$formdata = Remedy::FormData->new(
  name => 'HPD:WorkLog',
  session  => $session,
); 
$tmp = $formdata->as_string();
ok ($tmp); 
Remedy::Testing::write_string_to_file($tmp, './HPD_WorkLog.txt');
$end_time = time(); 
# warn "elapsed time is " . ($end_time - $start_time) . " seconds"; 
Remedy::Session::Cache::turn_global_caching_on();
