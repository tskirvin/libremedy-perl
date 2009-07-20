use Test::More tests => 3 ;

use Stanford::Remedy::Remctl ;
use Stanford::Remedy::Session ;
use Stanford::Remedy::Testing ;


# If the connect fails, skip this.
SKIP: 
{
  my $session ;
  eval 
  { 
    $session = Stanford::Remedy::Testing::make_session(
      CONNECT_METHOD => 'remctl', # Must override in order to test remctl functions.
    ) ; 
  } ;

  skip "skipping test of remctl", 3 if $@ ;

  ok ($session) ; 
  ok ($session->connect()) ;

  # Call the 'test' remctl action
  my $rv = Stanford::Remedy::Remctl::remctl_call(
                   SESSION  => $session,
                   ACTION   => 'test',
                       ) ; 

  ok ($rv =~ m{test}i) ; 
}