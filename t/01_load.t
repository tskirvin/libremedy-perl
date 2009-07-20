##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Test::More tests => 20;

##############################################################################
### Module Checks ############################################################
##############################################################################
# 20 checks
    
use_ok ('Remedy');
use_ok ('Remedy::Config');
use_ok ('Remedy::Form');
use_ok ('Remedy::Form::Department');
use_ok ('Remedy::Form::Error');
use_ok ('Remedy::Form::Generic');
use_ok ('Remedy::Form::Group');
use_ok ('Remedy::Form::People');
use_ok ('Remedy::Form::SGA');
use_ok ('Remedy::Form::SupportGroup');
use_ok ('Remedy::Form::User');
use_ok ('Remedy::Form::Utility');
use_ok ('Remedy::Log');
use_ok ('Remedy::Session');
use_ok ('Remedy::Session::ARS');
use_ok ('Remedy::Session::Cache');
use_ok ('Remedy::Session::Form');
use_ok ('Remedy::Session::Form::Data');
use_ok ('Remedy::Session::Remctl');
use_ok ('Remedy::Utility');
