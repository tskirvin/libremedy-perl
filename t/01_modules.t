##############################################################################
### Configuration ############################################################
##############################################################################

use vars qw/@MODULES $SIZE/;

BEGIN { 
    our @MODULES = ( 
        'Remedy',
        'Remedy::Cache',
        'Remedy::Config',
        'Remedy::Form',
        'Remedy::Form::Department',
        'Remedy::Form::Error',
        'Remedy::Form::Generic',
        'Remedy::Form::Group',
        'Remedy::Form::People',
        'Remedy::Form::SGA',
        'Remedy::Form::SupportGroup',
        'Remedy::Form::User',
        'Remedy::Form::Utility',
        'Remedy::FormData',
        'Remedy::FormData::Entry',
        'Remedy::FormData::Utility',
        'Remedy::Log',
        'Remedy::Session',
        'Remedy::Session::ARS',
        'Remedy::Utility',
    );
    our $SIZE = scalar @MODULES;
}

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Test::More tests => $SIZE;

##############################################################################
### Module Checks ############################################################
##############################################################################
# XX checks (varies by the size of @MODULES)

foreach (@MODULES) { use_ok ($_) }
