##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Remedy;
use Test::More tests => 9; 

##############################################################################
### main () ##################################################################
##############################################################################

$ENV{'REMEDY_CONFIG'} = "./config-test";
my $remedy = eval { Remedy->connect () };
ok ($remedy, "connection created");

my $form = $remedy->form ('CTM:People Organization');
ok ($form, "read a regular form");

ok ($form->name =~ m/CTM:People Organization/, "form name is as expected");

# Get the formdata object
my $formdata = $form->formdata;
ok ($formdata, "have full formdata from this form");

my $fieldId_to_fieldName_href = $formdata->get_fieldId_to_fieldName_href(); 
ok ($fieldId_to_fieldName_href); 

my $form2 = $remedy->form ('CTM:Support Group');
ok ($form2, "read another form"); 
ok ($form2->name != $form->name, "different forms have different names");

### TEST 3. Get a mapping from schema id to schema name


# ###
#### TEST 4. Make a select query 
####
#$new_form->set_session($session); 
#my $qry = 'SELECT name, schemaId FROM arschema';
#my @results = $new_form->execute_select_qry($qry); 
#ok (@results); 

$session->disconnect; 
