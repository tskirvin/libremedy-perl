use Test::More tests => 12 ;

use strict ;
use warnings ;

use Stanford::Remedy::Session ;
use Stanford::Remedy::Association ;
use Stanford::Remedy::Testing ;

use Data::Dumper ;

###
### Create a session
my $session = Stanford::Remedy::Testing::make_session() ; 

ok ($session) ; 
ok ($session->connect()) ;

## Make TWO fake incidents.
my ($incident1, $incident2, $incident3) ;
my ($incident_number1, $incident_number2) ;

$incident1 = Stanford::Remedy::Incident::make_fake($session) ; 
ok ($incident1->save()) ; 
$incident_number1 = $incident1->get_incident_number() ; 

$incident2 = Stanford::Remedy::Incident::make_fake($session) ; 
ok ($incident2->save()) ; 
$incident_number2 = $incident2->get_incident_number() ; 

# Associate these two incidents 
my ($association1, $association2) 
 = Stanford::Remedy::Association::relate(
                               FORM1 => $incident1,
                               FORM2 => $incident2,
                               SESSION => $session,
                               ASSOCIATION_TYPE1 => 'Caused',
                               ASSOCIATION_TYPE2 => 'Caused by',
                                          ) ;

ok ($association1) ; 
ok ($association2) ; 

ok ($association1->get_requestid_1() eq $incident1->get_incident_number()) ;
ok ($association1->get_requestid_2() eq $incident2->get_incident_number()) ;
ok ($association2->get_requestid_2() eq $incident1->get_incident_number()) ;
ok ($association2->get_requestid_1() eq $incident2->get_incident_number()) ;


$incident3 = Stanford::Remedy::Testing::close_incident($incident_number1, $session) ;
ok ($incident3->get_status() =~ m{closed}i) ;

$incident3 = Stanford::Remedy::Testing::close_incident($incident_number2, $session) ;
ok ($incident3->get_status() =~ m{closed}i) ;
