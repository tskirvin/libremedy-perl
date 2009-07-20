use Test::More tests => 5 ;

use Stanford::Remedy::Incident ;
use Stanford::Remedy::Testing ;

ok (1) ;


###
### Create a session
my $session = Stanford::Remedy::Testing::make_session() ; 

ok ($session) ; 
ok ($session->connect()) ;

# Make a fake incident (remember to supply a session object)
my $incident1 = Stanford::Remedy::Incident::make_fake($session) ; 
# Make sure the description has carriage returns.
my $description = <<"EOD";
A description
with
  carriage returns!
YES!
After encoding the non-padded data, if two octets of the 24-bit buffer are
padded-zeros, two "=" characters are appended to the output; if one octet
of the 24-bit buffer is filled with padded-zeros, one "=" character is
appended. This signals the decoder that the zero bits added due to padding
should be excluded from the reconstructed data. This also guarantees that
the encoded output length is a multiple of 4 bytes.

PEM requires that all encoded lines consist of exactly 64 printable
characters, with the exception of the last line, which may contain fewer
printable characters. Lines are delimited by whitespace characters
according to local (platform-specific) conventions.
EOD

$incident1->set_description($description) ; 
my $phone_number_before = $incident1->get_phone_number() ; 

my $xml = $incident1->to_xml() ; 
#warn $xml ; 

# Convert back
my $incident2 = Stanford::Remedy::Form::from_xml($xml, $session) ; 

my $phone_number_after = $incident2->get_phone_number() ; 

ok ($phone_number_before eq $phone_number_after) ; 
ok ($description eq $incident2->get_description()) ; 



