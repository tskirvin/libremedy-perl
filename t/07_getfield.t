use Test::More tests => 9 ;

use Stanford::Remedy::Remctl ;
use Stanford::Remedy::Session ;
use Stanford::Remedy::Testing ;
use Stanford::Remedy::Cache ;
use Data::Dumper ;

#Stanford::Remedy::Cache::turn_global_caching_off() ; 

my $session = Stanford::Remedy::Testing::make_session() ; 

ok ($session) ; 
ok ($session->connect()) ;

my (%fieldName_to_fieldId) ; 

%fieldName_to_fieldId 
  = Stanford::Remedy::FormData::ars_GetFieldTable($session, 'HPD:Help Desk') ; 
ok (%fieldName_to_fieldId) ;
ok ($fieldName_to_fieldId{'Incident Number'} =~ m{161}) ;

%fieldName_to_fieldId 
  = Stanford::Remedy::FormData::ars_GetFieldTable($session, 'HPD:Help Desk') ; 
ok (%fieldName_to_fieldId) ;

%fieldName_to_fieldId 
  = Stanford::Remedy::FormData::ars_GetFieldTable($session, 'HPD:Help Desk') ; 
ok (%fieldName_to_fieldId) ;

# Get the field Id for 'Incident Number'
my $fieldId = $fieldName_to_fieldId{'Incident Number'} ;
my $field_properties_ref 
#  = Stanford::Remedy::FormData::ars_GetField($session, 'HPD:Help Desk', '1000000572') ; 
  = Stanford::Remedy::FormData::ars_GetField($session, 'HPD:Help Desk', $fieldId) ; 

ok ($field_properties_ref) ;
ok ($field_properties_ref->{'fieldId'} =~ m{^1.*161$}) ;
#warn Dumper $field_properties_ref ;

# Get all the field properties for a form
my %fieldId_to_field_properties
  = Stanford::Remedy::FormData::ars_GetFieldsForSchema($session, 'HPD:WorkLog') ; 
ok (%fieldId_to_field_properties) ; 