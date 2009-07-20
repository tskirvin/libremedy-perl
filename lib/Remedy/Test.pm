package Remedy::Test;

use strict;
use warnings;

our $VERSION = '0.03';

use Stanford::Remedy::Session;

# The remctl ticket goes here.
my $ticket_location = undef;

sub END
{
  # If the remctl ticket file is defined, delete.
  if ($ticket_location)
  {
    unlink $ticket_location 
      or die "could not delete ticket location file '$ticket_location: $!";
  }
}

# Takes two parameters:
#  CONNECTION_FILE
#  CONNECT_METHOD (overrides connect_method in the connection method)
sub make_session
{
  my (%args) = (
                CONNECTION_FILE => 'connection.txt',
                @_,
               ); 

  my $connection_file = $args{'CONNECTION_FILE'}; 
  my $connect_method  = $args{'CONNECT_METHOD'}; 

  if (!(-f $connection_file))
  {
    die "connection file '$connection_file' not found";
  }
  
  ###
  ### Load connection information.
  use Config::Tiny;

  # Open the config file 
  my $config = Config::Tiny->read( $connection_file );
  if (!$config)
  {
    die "could not read connection file '$connection_file': $Config::Tiny::errstr";
  }

  # Read properties
  my $direct_server = $config->{connection}->{direct_server};
  my $remctl_server = $config->{connection}->{remctl_server};
  my $keytab_file   = $config->{connection}->{keytab_file};

  my $principal_primary  = $config->{connection}->{principal_primary};
  my $principal_instance = $config->{connection}->{principal_instance};
  my $principal_realm    = $config->{connection}->{principal_realm};

  my $direct_username = $config->{connection}->{direct_username};
  my $direct_password = $config->{connection}->{direct_password};

  # If this function was called with CONNECT_METHOD set, then we use 
  # its current value, otherwise, we use the value in the connection
  # file. 
  if (!$connect_method)
  {
    $connect_method = $config->{connection}->{connect_method};
  }


  ###
  ### If $connect_method is not defined or is not one of 'direct' or
  ###'remctl', use recmtl inless the ARS Perl module is installed. 

  my %allowed_types = ('direct' => 1, 'remctl' => 1,); 
  if (!$connect_method || !$allowed_types{$connect_method})
  {
    # $connect_method is not recognized, so see if the ARS Perl module
    # is installed. If it is, set $connect_method to 'direct', else set it 
    # to 'remctl'. 

    eval { require ARS };

    if ($@)
    {
      $connect_method = 'remctl';
    }
    else
    {
      $connect_method = 'direct';
    }
  }

  my $session;

  if ($connect_method =~ m{direct}i)
  {
    # Direct connection.
    my $username = $direct_username;
    my $password = $direct_password;

    $session = Stanford::Remedy::Session->new(
       'server'   => $direct_server,
       'username' => $username,
       'password' => $password,
                                            ); 
  }
  else
  {
    # Indirect (remctl) connection.

    # Get ticket ready.
    $ticket_location = 
    Stanford::Remedy::Session::make_kerberos_ticket(
           PRINCIPAL_PRIMARY  => $principal_primary,
           PRINCIPAL_INSTANCE => $principal_instance,
           PRINCIPAL_REALM    => $principal_realm,
           KEYTAB_FILE        => $keytab_file,
    ); 

    my $remctl_port = 4444;
    my $principal = qq{host/$remctl_server\@stanford.edu};

    $session = Stanford::Remedy::Session->new(
       'server'      => $remctl_server,
       'remctl_port' => $remctl_port,
       'principal'   => $principal,
                                            ); 
  }
 
  return $session;
}

# A convenience function to write a string to a file
sub write_string_to_file
{
  my ($string, $filename) = @_; 

  open (my $FH, ">", $filename)
    or die "could not open file '$filename' for writing: $!"; 

  print $FH $string; 

  close ($FH) 
    or die "could not close file '$filename' : $!"; 

  return 1;
}

# Close the incident with a given incident number. 
sub close_incident
{
  my ($incident_number, $session) = @_; 

  my $incident = Stanford::Remedy::Incident->new(
                  session => $session,
                                   );

  $incident->set_incident_number($incident_number);
  $incident->read_into(FIELDNAME => 'Incident Number');
  $incident->resolve(
        RESOLUTION_TEXT  => 'Resolving',
        ASSIGNEE         => 'Adam Lewenberg',
        ASSIGNEE_LOGINID => 'adamhl',
                     );
  $incident->set_status('Closed');

  $incident->save(); 

  return $incident;
}

1; 
