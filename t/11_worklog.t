use Test::More tests => 13;

use strict;
use warnings;
    
SKIP: {
    
    use Remedy::Form::Incident;
    use Remedy::WorkLog;
    use Remedy::Misc qw ( write_log );
    use Remedy::Testing;
    
    use Data::Dumper;
    
    
    my $session = Remedy::Testing::make_session(); 
    
    ok ($session); 
    ok ($session->connect());
    
    my ($request_id, $incident_number, @worklogs); 
    
    
    # Make sure that the $VERSION variable is defined.
    ok ($Remedy::WorkLog::VERSION);
    
    
    # Make a new incident (worklogs cannot exist without incidents)
    my $incident = Remedy::Incident::make_fake($session); 
    ok ($incident);
    
    
    # Save the incident.
    #warn $incident->as_string();
    $incident->save(); # Slow. Why?
    
    # Make a fake worklog
    my $worklog1 = Remedy::WorkLog::make_fake($session, $incident); 
    ok ($worklog1); 
    
    # Save it. 
    $request_id = $worklog1->save();
    ok ($request_id); 
    
    # Read the incident associated with this worklog
    $incident_number = $incident->get_incident_number();
    $incident->set_incident_number($incident_number); 
    $incident->read_into(); 
    
    my $FH;
    my $filename = "./HPD_Worklog2.txt";
    open ($FH , ">", $filename); 
    print $FH $worklog1->as_string(); 
    close ($FH); 
    
    open ($FH , ">", $filename); 
    print $FH $worklog1->as_string(); 
    close ($FH); 
    
    #warn $incident->as_string();
    
    # The incident number for $incident and for $worklog1 should be the same.
    ok ($worklog1->get_incident_number() 
     eq $incident->get_incident_number());
    
    ## Get the worklogs from this incident. 
    @worklogs = @{ $incident->get_worklogs_aref() }; 
    
    # There should be at least one.
    ok (@worklogs); 
    
    # Make another fake worklog.
    
    my $worklog2 = Remedy::WorkLog::make_fake($session, $incident); 
    ok ($worklog2); 
    
    $worklog2->save(); 
    
    # The request id of $worklog2 should be different than the request id of 
    # $worklog1, but the incident numbers should be the same.
    ok ($worklog1->get_request_id() ne $worklog2->get_request_id());
    ok ($worklog1->get_incident_number() eq $worklog2->get_incident_number());
    
    # Re-read this incident. 
    $incident->read_into(); 
    
    ## Get the worklogs from this incident. 
    @worklogs = @{ $incident->get_worklogs_aref() }; 
    
    #warn Dumper @worklogs;
    
    # There should now be TWO
    ok ((0 + @worklogs) == 2); 
    
    # Close the incident
    my $incident1 = Remedy::Testing::close_incident($incident_number, $session);
    ok ($incident1->get_status() =~ m{closed}i);
    
}
