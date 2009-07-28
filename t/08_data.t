use Test::More tests => 7;

use Remedy::Data;
use Remedy::Session;
use Remedy::Testing;
use Remedy::Session::Cache;

ok ($Remedy::Data::VERSION);

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

$formdata = Remedy::FormData->new(
  name => 'HPD:WorkLog',
  session  => $session,
); 
$tmp = $formdata->as_string();
ok ($tmp); 
Remedy::Testing::write_string_to_file($tmp, './HPD_WorkLog.txt');
