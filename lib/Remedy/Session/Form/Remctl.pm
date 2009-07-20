package Remedy::Session::Form::Remctl;

use strict;
use warnings;

our $VERSION = '0.03';

our (@ISA, @EXPORT_OK);
BEGIN 
{
  require Exporter; 
  @ISA = qw(Exporter);
  @EXPORT_OK = qw 
  (
    process_incoming_remctl
    make_session
    remctl_call
  ); 
}

use Stanford::Remedy::Misc qw ( local_die thaw_object freeze_object );
use Stanford::Remedy::Session;
use Stanford::Remedy::Form;

# VERY IMPORTANT! Be sure to load ALL the form-derived modules here.
use Stanford::Remedy::Incident;
use Stanford::Remedy::WorkLog;
use Stanford::Remedy::Association;

use Data::Dumper;


# Due to (current) remctl limits, we cannot send a frozen (serialized)
# object greater than a certain length as the object is a command-line
# argument and there are command-line length limits. 
#
# To indicate that there is NO size limit, set $FREEZE_SIZE_LIMIT to any
# non-positive value (such as 0). 
my $FREEZE_SIZE_LIMIT = 128000; # This should be a comfortable margin.


# Returns a reference to the results.
sub make_remctl_call
{
  my ($remctl, $action, $frozen) = @_; 

  if (!$remctl)
  {
    local_die("missing remctl object");
  }

  if (!$action)
  {
    local_die("missing action");
  }

  if (!$frozen)
  {
    local_die("missing serialized string");
  }

  # 1. Send the command.
  my $type = "remedy-gateway"; 
  $remctl->command($type, $action, $frozen)
    or die "Cannot send command: ", $remctl->error, "\n";

  # 2. Get data(may be lots)
  my $stdout = q{}; 
  my $stderr = q{}; 
  my $output;

  do 
  {
    $output = $remctl->output();

    if ($output->type() eq 'output') 
    {
      # STDOUT
      if ($output->stream == 1) 
     {
        $stdout .= $output->data();
      } 
      # STDERR
      elsif ($output->stream == 2) 
      {
        $stderr .= $output->data();
      }
    } 
    elsif ($output->type() eq 'error') 
    {
      $stderr .= $output->data();
    } 
    elsif ($output->type() eq 'status') 
    {
      my $status = $output->status();
      if ($status != 0)
      {
        #warn "status is " . $output->status();
        #warn "stdout so far is $stdout"; 
      }
    } 
    else 
    {
      die "Unknown output token from library: ", $output->type, "\n";
    }
  }
  while ($output->type() eq 'output');

  # The results returned will either be a (frozen) string or a 
  # reference to some more complicated object.

  # 3. Unserialize results (unless there errors).
  my $results_ref;
  if ($stderr)
  {
    local_die("[$action] ERROR: $stderr");
  }  
  elsif ($stdout)
  {
    $results_ref = thaw_object($stdout);
  }

  # Return (a reference to) the results.
  return $results_ref;
}


# 
# ARG_LIST is a reference to an array of references, each of which is an
# argument. 
# 
# For example, when making the read_where remctl call, you would do so
# thusly: 
#
#    my $form_name    = q{HPD:Help Desk};  
#    my $where_clause = q{'First Name' = "John"};  
#    remctl_call(
#                     ACTION   => 'read_where',
#                     ARG_LIST => [$form_name, $where_clause, ],
#                );
#
sub remctl_call
{
  my (%args) = (
                OBJECT_SIZE_LIMIT => $FREEZE_SIZE_LIMIT,
                ARG_LIST          => [],
                @_,
               ); 

  ### 0. Parse passed parameters and set things up.

  my $action            = $args{ACTION}; 
  my $arg_list          = $args{ARG_LIST}; 
  my $session           = $args{SESSION}; 
  my $object_size_limit = $args{OBJECT_SIZE_LIMIT}; 

  #warn "ACTION is '$action'"; 

  # Normalize $object_size_limit to be an integer. 
  if (!defined($object_size_limit))
  {
    $object_size_limit = 0; 
  }

  ### 1. The session object is required.
  if (!$session)
  {
    local_die("cannot make remctl call without a Stanford::Remedy::Session object"); 
  } 

  ### 3. Freeze the arguments.
  my $arg_list_frozen = freeze_object($arg_list); 

  # 4. If there is a freeze size limit and the object 
  # exceeds this limit, die. 
  my $frozen_length = length($arg_list_frozen); 
  if ($frozen_length > $object_size_limit)
  {
    local_die("the argument list's frozen length is $frozen_length characters which "
      . "exceeds the limit of $object_size_limit characters (action was '$action')"); 
  }

  # 5. Make the remctl call. 
  my $remctl = $session->get_remctl(); 
  my $results_ref
    = make_remctl_call($remctl, $action, $arg_list_frozen);

  # 7. Return the results (reference).
  return $results_ref;
}


################################################################################
################################################################################

# The next set of functions are intended to be called on the server-side
# of a remctl communication.

# This function processes remctl calls on the server side. To use it, 
# create a script...

# The full path of the logfile goes in $PR_LOGFILE
our $PR_LOGFILE = '/tmp/remedy.log';

sub pr_set_logfile
{
  my ($logfile) = @_; 
 
  if (!$logfile)
  {
    local_die("no logfile specified"); 
  }

  $PR_LOGFILE = $logfile;
  return;
}

# We want a prefix to use when writing to the log file
my $PR_PREFIX = '[remedy-gateway][main]';

sub process_incoming_remctl
{
  my (%args) = (
                @_,
               ); 

  ## STEP 0. Parse the parameters.
  my $command  = $args{COMMAND};
  my $arguments_serialized 
               = $args{ARGUMENTS_SERIALIZED};
  my $server   = $args{SERVER};
  my $username = $args{USERNAME};
  my $password = $args{PASSWORD};
  my $logfile  = $args{LOGFILE};

  ## STEP 1. Set the logfile.
  pr_set_logfile($logfile); 
  pr_write_log("START");

  ## STEP 2. Find out what type of command this is.

  # Get the first argument. Should be one of these: 
  #
  #   * test
  #   * SetEntry (ARS wrapper)
  #   * CreateEntry (ARS wrapper)
  #   * select_qry
  #   * read_where

  my %allowed_commands =
  ( 
    'test'         => 1,
    'SetEntry'     => 1,
    'CreateEntry'  => 1,
    'select_qry'   => 1,
    'read_where'   => 1,
    'ars_GetFieldTable' => 1,
    'ars_GetField' => 1,
    'ars_GetFieldsForSchema' => 1,
  ); 

  if (!$command)
  {
    pr_exit_with_error("missing command");
  }
  elsif (!$allowed_commands{$command})
  {
    pr_exit_with_error("command '$command' not recognized");
  }

  pr_write_log("command is '$command'");

  ## STEP 3. Unserialize the argument string (if it exists).
  my $arguments_aref = undef;
  if ($arguments_serialized)
  {
    $arguments_aref = unserialize($arguments_serialized); 
  }

  ## STEP 4. Make the Stanford::Remedy::Session object.
  my $session = make_session($server, $username, $password); 

  ## STEP 5. Process the command
  my $results; 

  if ($command eq 'test')
  {
    # Merely for testing that the interface is up.
    $results = pr_test($arguments_aref, $session); 
  }
  elsif ($command eq 'SetEntry')
  {
    # Execute the ARSPerl command SetEntry.
    $results = pr_SetEntry($arguments_aref, $session); 
  }
  elsif ($command eq 'CreateEntry')
  {
    # Execute the ARSPerl command CreateEntry.
    $results = pr_CreateEntry($arguments_aref, $session); 
  }
  elsif ($command eq 'read_where')
  {
    # Return all form objects matchine a specified query.
    my $start_time = time(); 
    $results = pr_read_where($arguments_aref, $session); 
    pr_write_log("elapsed where time was " . (time() - $start_time));
  }
  elsif ($command eq 'select_qry')
  {
    # Given a SELECT statment, execute and return the results serialized.
    $results = pr_select_qry($arguments_aref, $session); 
  }
  elsif ($command eq 'ars_GetFieldTable')
  {
    # Given a form name, return its field names and ids.
    $results = pr_ars_GetFieldTable($arguments_aref, $session); 
  }
  elsif ($command eq 'ars_GetField')
  {
    # Given a form name, return its properties.
    $results = pr_ars_GetField($arguments_aref, $session); 
    pr_write_log(Dumper $results);
  }
  elsif ($command eq 'ars_GetFieldsForSchema')
  {
    # Given a form name, return its properties.
    $results = pr_ars_GetFieldsForSchema($arguments_aref, $session); 
    pr_write_log(Dumper $results);
  }
  else
  {
    pr_exit_with_error("I do not know what is happening?!?");
  }

  ## STEP 4. Freeze results and print.  
  my $results_frozen;
  eval
  {
    $results_frozen = freeze_object($results); 
  };

  if ($@)
  {
    pr_exit_with_error("error freezing results: $@");
    pr_exit_with_error("error freezing results: $@");
  }


  ## FINAL STEP. Cleanup and return frozen results.
  $session->disconnect(); 
  pr_write_log("FINISH");

  return $results_frozen;
}


##########################################################################################

## These functions do the actual work.
sub pr_test
{
  return "This is a test"; 
}


sub pr_SetEntry
{
  my ($arguments_aref, $session) = @_; 

  # Step 1. Parse $arguments_aref. All the arguments are mandatory.
  my ($name, $request_id, $fields_aref) = @$arguments_aref;

  my @fields = @$fields_aref;

  # Step 2. Create a new form object so we can call SetEntry
  my $form = Stanford::Remedy::Form->new(
                   name    => $name,
                   session => $session,
                                         );

  # Step 3. Call the SetEntry method
  my $rv;
  eval
  {
    $rv = $form->SetEntry($request_id, \@fields);
  };

  if ($@)
  {
    my $msg = qq{error calling SetEntry on form '$name': } . $@  
            . " Affected fields: " . join(",", @fields); 
    pr_exit_with_error($msg); 
  }

  # Final Step: Return true since everything worked out.
  return 1;
}

sub pr_CreateEntry
{
  my ($arguments_aref, $session) = @_; 

  # Step 1. Parse $arguments_aref. All the arguments are mandatory.
  my ($name, $fields_aref) = @$arguments_aref;

  my @fields = @$fields_aref;

  # Step 2. Create a new form object so we can call CreateEntry
  my $form = Stanford::Remedy::Form->new(
                   name    => $name,
                   session => $session,
                                         );

  # Step 3. Call the CreateEntry method.
  my $request_id; 
  eval
  {
    $request_id = $form->CreateEntry(\@fields);
  };

  { no warnings;
    pr_write_log("\$request_id is $request_id: $@"); 
    pr_write_log(join(",", @fields)); 
  }

  if ($@)
  {
    my $msg = qq{error calling CreateEntry on form '$name': } . $@ 
            . " Affected fields: " . join(",", @fields); 
    pr_exit_with_error($msg); 
  }

  # Final Step: Return the request id.
  return $request_id;
}

sub pr_ars_GetFieldTable
{
  my ($arguments_aref, $session) = @_; 

  # Step 1. Parse $arguments_aref. All the arguments are mandatory.
  my ($name) = @$arguments_aref;

  my %fieldName_to_fieldId = (); 

  # Step 2. Call the ars_GetFieldTable method.
  eval
  {
    %fieldName_to_fieldId 
      = Stanford::Remedy::FormData::ars_GetFieldTable($session, $name); 
  };

  { 
    no warnings;
    pr_write_log("finished GetFieldTable call for name '$name': $@"); 
  }

  if ($@)
  {
    my $msg = q{error calling ars_GetFieldTable: } . $@; 
    pr_exit_with_error($msg); 
  }

  # Final Step: Return a reference to the result hash.
  return \%fieldName_to_fieldId;
}

sub pr_ars_GetField
{
  my ($arguments_aref, $session) = @_; 

  # Step 1. Parse $arguments_aref. All the arguments are mandatory.
  my ($name, $fieldId) = @$arguments_aref;

  my $field_properties_ref; 

  # Step 2. Call the ars_GetField function.
  eval
  {
    $field_properties_ref
      = Stanford::Remedy::FormData::ars_GetField($session, $name, $fieldId); 
  };

  { 
    no warnings;
    pr_write_log("finished GetField call for name '$name' and field id '$fieldId': $@"); 
  }

  if ($@)
  {
    my $msg = q{error calling ars_GetField: } . $@; 
    pr_exit_with_error($msg); 
  }

  # Final Step: Return the results
  return $field_properties_ref;
}

sub pr_ars_GetFieldsForSchema
{
  my ($arguments_aref, $session) = @_; 

  # Step 1. Parse $arguments_aref. All the arguments are mandatory.
  my ($name) = @$arguments_aref;

  my %fieldId_to_field_properties = (); 

  # Step 2. Call the ars_GetFieldsForSchema function from FormData
  eval
  {
    %fieldId_to_field_properties
      = Stanford::Remedy::FormData::ars_GetFieldsForSchema($session, $name); 
  };

  { 
    no warnings;
    pr_write_log("finished GetFieldsForSchema call for name '$name'"); 
  }

  if ($@)
  {
    my $msg = q{error calling ars_GetFieldsForSchema: } . $@; 
    pr_exit_with_error($msg); 
  }

  # Final Step: Return the results
  return \%fieldId_to_field_properties;
}

# Given a SQL SELECT statement, execute and return the results 
# serialized.
sub pr_select_qry
{
  my ($arguments_aref, $session) = @_; 

  # Step 1. Parse $arguments_aref. All the arguments are mandatory.
  my ($select_qry) = @$arguments_aref;

  # Step 2. Do some basic error checking on the query.
  if (!$select_qry)
  {
    my $msg = "cannot run a select query without a query"; 
    pr_exit_with_error($msg); 
  }

  if ($select_qry !~ m{^select}i)
  {
    my $msg = "the query '$select_qry' does not appear to be a SELECT query"; 
    pr_exit_with_error($msg); 
  }

  # Step 4. Execute the query and store the results.
  pr_write_log("[select_qry] about to run query '$select_qry'"); 
  my @select_results = (); 
  eval
  {
    Stanford::Remedy::FormData::execute_query_return_results(
          SESSION      => $session,
          QRY          => $select_qry,
          RESULTS_AREF => \@select_results,
                                   ); 
  };

  if ($@)
  {
    my $msg = "error executing query '$select_qry': $@"; 
    pr_exit_with_error($msg); 
  }

  # Final Step: Return serialized object.
  return \@select_results;
}


# Call the read_where command.
sub pr_read_where
{
  my ($arguments_aref, $session) = @_; 

  # Step 1. Parse $arguments_aref. All the arguments are mandatory.
  my ($form, $where_clause) = @$arguments_aref;

  # Step 2. Do some basic error checking on the query.
  if (!$form)
  {
    my $msg = "cannot run read_where without a form object"; 
    pr_exit_with_error($msg); 
  }

  if (!$where_clause)
  {
    my $msg = "cannot run read_where without a WHERE clause"; 
    pr_exit_with_error($msg); 
  }

  # my $msg = Dumper $form; 
  # pr_write_log("form is $msg"); 
  my $name = $form->get_name(); 
  if (!$name)
  {
    my $msg = "cannot run read_where without a form name"; 
    pr_exit_with_error($msg); 
  }
  pr_write_log("[read_where] name is '$name'"); 

  # Step 3. Associate $form with $session.
  $form->set_session($session); 

  # Step 4. Call read_where.
  my @objects = (); 
  eval
  {
    @objects = $form->read_where($where_clause); 
  };

  if ($@)
  {
    my $msg = "error calling read_where (where clause is '$where_clause'): $@"; 
    pr_exit_with_error($msg); 
  }

  # Final Step: Return serialized object.
  pr_write_log("about to return " . (0+@objects) . " object"); 
  return \@objects;
}


# Given a serialized object, returns an unserialized object. Dies
# on failure. 
sub unserialize
{
  pr_write_log("about to unserialize"); 
  my ($serialized) = @_; 

  if (!$serialized)
  {
    my $msg = "cannot unserialize the empty string";
    pr_exit_with_error($msg);
  } 

  return thaw_object($serialized); 
}

# Make a connected Stanford::Remedy::Session object.
sub make_session
{
  my ($server, $username, $password) = @_; 

  my $session;
  eval
  {
    $session = Stanford::Remedy::Session->new(
                'username' => $username,
                'password' => $password,
                'server'   => $server,
                                              );
  };

  if ($@)
  {
    my $msg = "could not create Stanford::Remedy::Session object: $@"; 
    pr_exit_with_error($msg); 
  }

  # Connect.
  $session->connect(); 

  return $session;
}


sub pr_exit_with_error
{
  my ($msg, $prefix) = @_; 

  if (!$prefix)
  {
    $prefix = q{}; 
  }

  my $formatted_msg = "$PR_PREFIX$prefix $msg";
  pr_write_log($formatted_msg);
  pr_write_log("FINISH (ERROR)");
  die $formatted_msg;
}

sub pr_write_log
{
  my ($msg) = @_; 
  return Stanford::Remedy::Misc::write_log($msg, $PR_LOGFILE); 
}

1;
