use Test::More tests => 42 ;

use strict ;
use warnings ;

use Stanford::Remedy::Session ;
use Stanford::Remedy::Incident ;
use Stanford::Remedy::Misc qw ( write_log ) ;
use Stanford::Remedy::Logger qw ( clear_mark log_info ) ;
use Stanford::Remedy::Testing ;
use Stanford::Remedy::Cache ;

# Turn off caching when there are errors to make sure that
# caching is not the culprit
# Stanford::Remedy::Cache::turn_global_caching_off() ;

use Data::Dumper ;

my ($incident1, $incident2, $incident3, $incident4) ; 
my (@incidents, $rv, %rv, $formdata) ;

my ($status) ; 
#my $assignee = 'service alerts' ;
my $assignee = 'Remedy ServiceAlerts' ;
my $assignee_login_id = 'servicealerts' ;

###
### Create a session
my $session = Stanford::Remedy::Testing::make_session() ; 

ok ($session) ; 
ok ($session->connect()) ;

###
### TEST 2. Make a new Stanford::Remedy::Incident object.
###
$incident1 = Stanford::Remedy::Incident->new(session => $session,) ;
ok ($incident1) ;
ok ($incident1->get_name() eq 'HPD:Help Desk') ;

# Get the mapping from fieldName to fieldId. 
clear_mark() ; 
$formdata = $incident1->get_formdata() ; 

my $fieldName_to_fieldId_href = $formdata->get_fieldName_to_fieldId_href(); 

ok ($fieldName_to_fieldId_href) ;

# Get the the field id for Incident Number field (should end in '161')
my $fieldId = $fieldName_to_fieldId_href->{'Incident Number'} ;
ok ($fieldId =~ m{161$}) ;

###
### TEST 2. Make a new "fake" Stanford::Remedy::Incident object.
###

# Make a fake incident (remember to supply a session object)
$incident1 = Stanford::Remedy::Incident::make_fake($session) ; 

# Get the Phone Number and Last name.
my $Phone_Number = $incident1->get_value('Phone Number') ; 
my $Last_Name    = $incident1->get_value('Last Name') ; 

ok ($Phone_Number) ;
ok ($Last_Name) ;


my $FH ;
open ($FH , ">", "./dump.txt") ; 
print $FH $incident1->as_string() ; 
close ($FH) ; 

# We should NOT have a request id (yet).
ok (!$incident1->get_request_id()) ;
sleep 1 ;

# Save it!
clear_mark() ; 
log_info("about to save!") ;
$incident1->set_session($session) ; 
$incident1->save() ;
my $incident_number1 = $incident1->get_incident_number() ; 
my $end = time() ; 
log_info("finished save!") ;
clear_mark() ; 

# We should now have a request_id and a time of last modification
ok ($incident1->get_request_id()) ;

ok ($incident1->get_value('Submit Date')) ; 

open ($FH , ">", "./after.txt") ; 
print $FH $incident1->as_string() ; 
close ($FH) ; 

ok ($incident1->get_session()) ;

# Get the fieldId for the fieldName 'Phone Number'; should agree with the 
# previous setting $phone_number.
my $Phone_Number_fid = $incident1->convert_fieldName_to_fieldId('Phone Number') ; 
@incidents = $incident1->read_where(qq{'$Phone_Number_fid' = "$Phone_Number"}) ;
ok ((0 + @incidents) == 1) ; 

# Make a new fake incident but set the Last Name to the same as $incident1.
$incident2 = Stanford::Remedy::Incident::make_fake($session) ; 

$incident2->set_value('Last Name', $Last_Name) ;
$incident2->save() ;
my $incident_number2 = $incident2->get_incident_number() ; 

# Assign this incident.
my $assigned_group = 'ITS ITSM' ;
#$incident2->set_value('Assigned Support Company', 'Stanford University') ;
#$incident2->set_value('Assigned Support Organization', 'IT Services') ;
#$incident2->set_value('Assigned Group', $assigned_group) ;
my $impact = '4-Minor/Localized' ;
$incident2->set_enum_value('Impact', $impact) ;
$incident2->save() ; 

ok ($impact eq $incident2->get_enum_value('Impact')) ;
ok ($assigned_group eq $incident2->get_value('Assigned Group')) ;

# Assign this incident.
$incident2->assign(
          ASSIGNEE         => $assignee, 
          ASSIGNEE_LOGINID => $assignee_login_id, 
                  ) ; 

ok ($incident2->get_value('Assignee') eq $assignee) ;
ok ($incident2->get_value('Assignee Login ID') eq $assignee_login_id) ;
ok ($incident2->save()) ; 

ok ($incident2->get_value('Assignee') eq $assignee) ;
ok ($incident2->get_value('Assignee Login ID') eq $assignee_login_id) ;


# Resolve this incident.
my $resolution = 'A resolution XYZ.' ;
$incident2->set_value('First Name', 'ABCXYZ') ;

$incident2->resolve(
      RESOLUTION_TEXT  => $resolution,
      ASSIGNEE         => $assignee,
      ASSIGNEE_LOGINID => $assignee_login_id,
                   ) ;

ok ($resolution eq $incident2->get_value('Resolution')) ;

ok ('Resolved' eq $incident2->get_status()) ;

$incident2->save() ; 

# Close this incident.
$incident2->close() ; 
$incident2->save() ; 
ok ($incident2->get_status() =~ m{closed}i) ;


# Read in all incidents with the 'Last Name' of $Last_Name.
my $Last_Name_fid = $incident2->convert_fieldName_to_fieldId('Last Name') ; 
@incidents = $incident2->read_where(qq{'$Last_Name_fid' = "$Last_Name"}) ;
ok ((0 + @incidents) == 2) ; 


# Create a NEW incident and read in the incident just created.
$incident2 = Stanford::Remedy::Incident->new(session => $session,) ;
$incident2->set_request_id($incident1->get_request_id()) ;
$incident2->read_into() ;

# The two submit dates should agree.
ok ($incident2->get_value('Submit Date') 
 eq $incident1->get_value('Submit Date')) ;


# We want to update. 
my $new_description = "A new (updated) description $$" ;
$incident1->set_value('Description', $new_description) ;
$incident1->update() ; 

$incident2->set_request_id($incident1->get_request_id()) ;
$incident2->read_into() ;

ok ($incident2->get_value('Description') eq $new_description) ;


# Do a form read but restrict the fieldNames we want to use. 
$incident2 = Stanford::Remedy::Incident->new(
                  session => $session,
                                   ) ;
my %only_these_fieldNames = 
(
  'Incident Number' => 1,
  'First Name'      => 1,
  'Last Name'       => 1,
) ;

$incident2->set_only_these_fieldNames_href(\%only_these_fieldNames) ; 

$incident2->set_request_id($incident1->get_request_id()) ;
$incident2->read_into() ;

# Most of the fields should be empty. 
ok (!defined($incident2->get_value('Description'))) ;
ok (!defined($incident2->get_value('Phone Number'))) ;
ok (!defined($incident2->get_value('SUNet ID+'))) ;
ok ( defined($incident2->get_value('First Name'))) ;
ok ( defined($incident2->get_value('Last Name'))) ;


## 
# Change the default cache location and do a read to make 

# First, mess up %Stanford::Remedy::Form::REMEDY_FORM_DATA.
%Stanford::Remedy::Form::REMEDY_FORM_DATA = () ; 
my $tempdir = File::Temp::tempdir(CLEANUP => 1);
Stanford::Remedy::Cache::set_default_cache_root($tempdir) ;
$incident3 = Stanford::Remedy::Incident->new(
                  session => $session,
                                   ) ;
my $cache = $incident3->get_cache() ; 
$incident3->set_request_id($incident1->get_request_id()) ;
$incident3->read_into() ;
ok ( defined($incident3->get_value('First Name'))) ;
## 

## Try a read into where we specify more than one field.
$incident1 = Stanford::Remedy::Incident::make_fake($session) ; 
$incident2 = Stanford::Remedy::Incident::make_fake($session) ; 
$incident3 = Stanford::Remedy::Incident::make_fake($session) ; 

# Change the first name and phone numbers.
$incident1->set_first_name('John') ;
$incident2->set_first_name('Johanna') ;
$incident3->set_first_name('John') ;
my $time = time() ; 
$incident1->set_phone_number($time) ;
$incident2->set_phone_number($time + 10) ;
$incident3->set_phone_number($time) ;

ok ($incident1->save()) ; 
ok ($incident2->save()) ; 
ok ($incident3->save()) ; 

# Now do a read
$incident4 = Stanford::Remedy::Incident->new(
                  session => $session,
                                   ) ;
$incident4->set_first_name('John') ;
$incident4->set_phone_number($time) ;
my @fields_to_read = ('First Name', 'Phone Number') ;
my @objects = $incident4->read(FIELDNAME => \@fields_to_read) ;
my $number_returned = 0 + @objects ;
ok ($number_returned == 2) ;

my $inc1 = $objects[0] ;
my $inc3 = $objects[1] ;
ok ($inc1->get_phone_number() eq $incident1->get_phone_number()) ;
ok ($inc3->get_phone_number() eq $incident3->get_phone_number()) ;

ok ($inc1->get_incident_number() eq $incident1->get_incident_number()) ;
ok ($inc3->get_incident_number() eq $incident3->get_incident_number()) ;

# Close the incident
$incident1->resolve(
      RESOLUTION_TEXT  => $resolution,
      ASSIGNEE         => $assignee,
      ASSIGNEE_LOGINID => $assignee_login_id,
                   ) ;
$incident2->resolve(
      RESOLUTION_TEXT  => $resolution,
      ASSIGNEE         => $assignee,
      ASSIGNEE_LOGINID => $assignee_login_id,
                   ) ;
$incident3->resolve(
      RESOLUTION_TEXT  => $resolution,
      ASSIGNEE         => $assignee,
      ASSIGNEE_LOGINID => $assignee_login_id,
                   ) ;

$incident1->close() ;
$incident2->close() ;
$incident3->close() ;

$incident1->save() ; 
$incident2->save() ; 
$incident3->save() ; 



#####################################

# Note that to close incident1 we have to have an assignee and
# resolution text.

$incident3 = Stanford::Remedy::Testing::close_incident($incident_number1, $session) ;
ok ($incident3->get_status() =~ m{closed}i) ;

$incident3 = Stanford::Remedy::Testing::close_incident($incident_number2, $session) ;
ok ($incident3->get_status() =~ m{closed}i) ;


