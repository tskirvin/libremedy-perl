##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use File::Temp qw/tempdir/;
use Remedy::Session::Cache;
use Test::More tests => 7;

##############################################################################
### Default Checks ###########################################################
##############################################################################
# 1 check

ok ($Remedy::Session::Cache::VERSION);

##############################################################################
### Cache Checks #############################################################
##############################################################################
# 6 checks 

my $namespace = "testing" . $$; 
my $cache_key = "a key" . $$;

my $cache = Remedy::Session::Cache->new ('namespace' => $namespace); 
ok ($cache); 

# Get the cache results (will not exist). 
my $cache_results_ref = $cache->get_value ($cache_key);
ok (! $cache_results_ref);

# Set something. 
my @data = [1, 2, {3, 4}];
ok ($cache->set_value ($cache_key, \@data));

$cache_results_ref = $cache->get_value ($cache_key);
ok ($cache_results_ref); 

# Change the default cache root 
my $tempdir = tempdir (CLEANUP => 1);
Remedy::Session::Cache::set_default_cache_root ($tempdir);
$cache = Remedy::Session::Cache->new (namespace => $namespace); 
ok ($cache);
ok ($cache->set_value ($cache_key, \@data));
