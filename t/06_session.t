use Test::More tests => 3;

use Remedy::Session;
use Remedy::Testing;

ok ($Remedy::Session::VERSION);

###
### Create a session
my $session = Stanford::Remedy::Testing::make_session() ; 

ok ($session) ; 
ok ($session->connect()) ;

$session->disconnect() ; 



