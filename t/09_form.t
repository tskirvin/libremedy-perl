use Test::More tests => 10; 

use Remedy::Form;
use Remedy::Testing;

my ($form, $form2, $rv, %rv, $FH, $formdata);

### Create a session
my $session = Remedy::Testing::make_session(); 

ok ($session); 
ok ($session->connect());

###
### TEST 2. Make a new Remedy::Form object. 
###

$form = Remedy::Form->new(
                  session => $session,
                  name    => 'HPD:Help Desk',
                                   );
ok ($form);

$form->populate(); 
#warn $form->as_string();

ok ($form->get_name =~ m/HPD:Help Desk/);
ok ($form->get_populated);

# Get the formdata object
$formdata = $form->get_formdata ();

my $fieldId_to_fieldName_href = $formdata->get_fieldId_to_fieldName_href(); 
ok ($fieldId_to_fieldName_href); 

$form2 = Remedy::Form->new(
                  session => $session,
                  name    => 'HPD:WorkLog',
                                   );
ok ($form2); 

###
### TEST 3. Get a mapping from schema id to schema name
###


# ok (Remedy::Form::schemaId_to_name('HPD:Help Desk', $session));


# Test freeze and thaw.
$form->set_session(undef);
my $request_id = 'IDZZZ12345' . $$;
$form->set_request_id($request_id); 
my $icicle = Remedy::Misc::freeze_object($form);
ok($icicle);

my $new_form = Remedy::Misc::thaw_object($icicle);
ok ($new_form);
ok ($new_form->get_request_id() eq $form->get_request_id());

# ###
#### TEST 4. Make a select query 
####
#$new_form->set_session($session); 
#my $qry = 'SELECT name, schemaId FROM arschema';
#my @results = $new_form->execute_select_qry($qry); 
#ok (@results); 

$session->disconnect(); 

