package Remedy::Form::Incident;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Incident - Support Group Association

=head1 SYNOPSIS

use Remedy::Incident;

# $remedy is a Remedy object
[...]

=head1 DESCRIPTION

Stanfor::Remedy::Incident maps users (the B<User> table) to support groups
(B<Group>).

=cut

##############################################################################
### Configuration 
##############################################################################

=head1 VARIABLES

These variables primarily hold human-readable translations of the status,
impact, etc of the ticket; but there are a few other places for customization.

=over 4

=item %TEXT

=cut

our %TEXT = ('debug' => \&Remedy::Form::debug_text);

=back

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy::Ticket;

use Remedy::Form qw/init_struct/;

use Remedy::Form::Audit;
use Remedy::Form::TicketGen;
use Remedy::Form::Time;
use Remedy::Form::WorkLog;
use Remedy::Form::User;

our @ISA = init_struct (__PACKAGE__, 'ticketgen' => 'Remedy::Form::TicketGen');
unshift @ISA, 'Remedy::Ticket::Functions'; 

Remedy::Form->register ('incident', __PACKAGE__);

##############################################################################
### Subroutines
##############################################################################

=head1 FUNCTIONS

=head2 Local Methods

=over 4

=item close (TEXT)

=cut

sub close {
    my ($self, $text, %args) = @_;
    # $self->assign
}

sub assign  {
    my ($self, %args) = @_;
    
    
}
sub resolve {}
sub set_status {}

sub read_lala {
    warn "\@_: @_\n";
    warn "@ISA\n";
    return SUPER::read (@_);
}

=cut

    $tktdata{'1000000156'} = $text;                 # 'Resolution'
    $tktdata{'1000005261'} = time;                  # 'Resolution Date'
    $tktdata{'7'}          = 4;                     # 'Status' = "Resolved"
    $tktdata{'1000000215'} = 11000;                 # 'Reported Source'
    $tktdata{'1000000150'} = 17000;                 # "No Further Action Required"
    # Not doing 1000000642, "Time Spent"

=cut

=item get_incnum (ARGHASH)

Finds the incident number for the current incident.  If we do not already
have one set and stored in B<inc_num ()>, then we will create one using
B<Remedy::TicketGen ().

=over 4

=item description (TEXT)

=item user (USER)

=back

=cut

sub get_incnum {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die ();

    return $self->inc_num if defined $self->inc_num;
    if (! $self->ticketgen) {
        my %args;

        my $ticketgen = $parent->create ('Remedy::Form::TicketGen') 
            or $self->error ("couldn't create new ticket number");
        $ticketgen->description ($args{'description'} || $self->default_desc);
        $ticketgen->submitter ($args{'user'} || $parent->config->remedy_user);

        print scalar $ticketgen->print_text, "\n";
        $ticketgen->save ('db' => $parent) 
            or $self->error ("couldn't create new ticket number: $@");
        $ticketgen->reload;
        $self->ticketgen ($ticketgen);
        $self->inc_num ($ticketgen->inc_num);
    }

    return $self->inc_num;
}

sub default_desc { "Created by " . __PACKAGE__ }

=item assignee 

=cut

sub assignee {
    my ($self) = @_;
    return $self->format_email ($self->assignee_name, $self->assignee_sunet);
}

=item requestor

=cut

sub requestor {
    my ($self) = @_;
    my $name = join (" ", $self->requestor_first_name || '',
                          $self->requestor_last_name || '');
    return $self->format_email ($name, $self->requestor_email || '');
}

=item text_assignee ()

=cut

sub text_assignee {
    my ($self) = @_;
    my @return = "Ticket Assignee Info";
    push @return, $self->format_text_field ( 
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Group'         => $self->assignee_group || "(unassigned)",
        'Name'          => $self->assignee,
        'Last Modified' => $self->date_modified,
    );
    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'assignee'} = \&text_assignee;

=item text_audit

=cut

sub text_audit {
    my ($self, %args) = @_;
    my ($count, @return);
    foreach my $audit ($self->audit (%args)) { 
        push @return, '' if $count;
        push @return, "Audit Entry " . ++$count;
        push @return, ($audit->print_text);
    }
    return "No Audit Information" unless $count;
    unshift @return, "Audit Entries ($count)";
    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'audit'} = \&text_audit;

=item text_description ()

=cut

sub text_description {
    my ($self) = @_;
    my @return = "User-Provided Description";
    push @return, $self->format_text ({'prefix' => '  '},
        $self->description || '(none)');
    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'description'} = \&text_description;

=item text_primary ()

=cut

sub text_primary {
    my ($self, %args) = @_;
    my @return = "Primary Ticket Information";
    push @return, $self->format_text_field ( 
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Ticket'            => $self->inc_num       || "(none set)", 
        'Summary'           => $self->summary,
        'Status'            => $self->status        || '(not set/invalid)',
        'Status Reason'     => $self->status_reason || '(not set)',
        'Submitted'         => $self->date_submit,
        'Urgency'           => $self->urgency       || '(not set)',
        'Priority'          => $self->priority      || '(not set)',
        'Incident Type'     => $self->incident_type || "(none)",
    );

    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'primary'} = \&text_primary;

=item text_requestor ()

=cut

sub text_requestor {
    my ($self) = @_;
    my @return = "Requestor Info";
    
    push @return, $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'SUNet ID'    => $self->sunet || "(none)",
        'Name'        => $self->requestor,
        'Phone'       => $self->requestor_phone,
        'Affiliation' => $self->requestor_affiliation,
    );
    
    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'requestor'} = \&text_requestor;

sub text_resolution {
    my ($self) = @_;
    my @return = "Resolution";

    my $resolution= $self->resolution || return;
    push @return, $self->format_text_field ( 
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Date'              => $self->date_resolution,
    );
    push @return, '', $self->format_text ({'prefix' => '  '}, $resolution);

    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'resolution'} = \&text_resolution;

sub text_summary {
    my ($self, %args) = @_;
    my @return = "Summary Ticket Information";
    my @timelog = $self->timelog (%args);
    my @worklog = $self->worklog (%args);
    my @audit   = $self->audit   (%args);
    push @return, $self->format_text_field ( 
        {'minwidth' => 20, 'prefix' => '  '}, 
        'WorkLog Entries' => scalar @worklog,
        'TimeLog Entries' => scalar @timelog,
        'Audit Entries'   => scalar @audit,
        'Time Spent (mins)' => $self->total_time_spent || 0,
    );
    
    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'summary'} = \&text_summary;

=item text_timelog ()

=cut

sub text_timelog {
    my ($self, %args) = @_;
    my (@return, $count);
    foreach my $time ($self->timelog (%args)) { 
        push @return, '' if $count;
        push @return, "Time Entry " . ++$count;
        push @return, ($time->print_text);
    }
    return "No TimeLog Entries";
    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'timelog'} = \&text_timelog;

=item text_worklog ()

=cut

sub text_worklog {
    my ($self, %args) = @_;
    my (@return, $count);
    foreach my $worklog ($self->worklog (%args)) { 
        push @return, '' if $count;
        push @return, "Work Log Entry " . ++$count;
        push @return, ($worklog->print_text);
    }
    return "No WorkLog Entries" unless $count;
    return wantarray ? @return : join ("\n", @return, '');
}
$TEXT{'worklog'} = \&text_worklog;

=back

=cut

##############################################################################
### Related Classes
##############################################################################

=head2 Related Classes

=over 4

=item audit ()

=cut

sub audit {
    my ($self, %args) = @_;
    return unless $self->inc_num;
    return $self->read ('Remedy::Audit', 'EID' => $self->inc_num, %args);
}

=item worklog ()

=cut

sub worklog {
    my ($self, %args) = @_;
    return unless $self->inc_num;
    return $self->read ('Remedy::WorkLog', 'EID' => $self->inc_num, %args);
}

=item timelog ()

=cut

sub timelog {
    my ($self, %args) = @_;
    return unless $self->inc_num;
    return $self->read ('Remedy::Time', 'EID' => $self->inc_num, %args);
}

=item worklog_create ()

Creates a new worklog entry, pre-populated with the date and the current
incident number.  You will still have to add other data.

=over 4

=item timelog_create (TIME)

=back

=cut

sub worklog_create {
    my ($self, %args) = @_;
    return unless $self->inc_num;
    my $worklog = Remedy::WorkLog->new ('db' => $self->parent_or_die (%args));
    $worklog->inc_num ($self->inc_num);
    $worklog->date_submit ($self->format_date (time));
    return $worklog;
}

sub timelog_create {
    my ($self, %args) = @_;
    return unless $self->inc_num;
    my $timelog = Remedy::Time->new ( 'db' => $self->parent_or_die (%args));
    $timelog->inc_num ($self->inc_num);
    return $timelog;
}

=back

=cut

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map

=cut

sub field_map { 
    'id'                    => "Entry ID",
    'date_submit'           => "Submit Date",
    'assignee_sunet'        => "Assignee Login ID",
    'date_modified'         => "Last Modified Date",
    'status'                => "Status",
    'sunet'                 => "SUNet ID+",
    'requestor_affiliation' => "SU Affiliation_chr",
    'requestor_email'       => "Requester Email_chr",
    'incident_type'         => "Incident Type",
    'summary'               => "Description",
    'requestor_last_name'   => "Last Name",
    'requestor_first_name'  => "First Name",
    'requestor_phone'       => "Phone Number",
    'status_reason'         => "Status_Reason",
    'resolution'            => "Resolution",
    'inc_num'               => "Incident Number",
    'urgency'               => "Urgency",
    'impact'                => "Impact",
    'priority'              => "Priority",
    'description'           => "Detailed Decription",
    'assignee_group'        => "Assigned Group",
    'assignee_name'         => "Assignee",
    'time_spent'            => "Time Spent (min)",
    'total_time_spent'      => "Total Time Spent (min)",
    'date_resolution'       => "Estimated Resolution Date",
}

=item limit_pre ()

extra is above

=cut

sub limit_pre {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die ();
    my $config = $parent->config_or_die ('no configuration');

    if (my $incnum = $args{'incnum'}) { return ('Incident Number' => $incnum) }

    $args{'Assigned Support Company'}      ||= $config->company   || "%";
    $args{'Assigned Support Organization'} ||= $config->sub_org   || "%";
    $args{'Assigned Group'}                ||= $config->workgroup || "%";

    my %fields = $self->fields (%args);

    my @extra;

    if (my $extra = $args{'extra'}) { 
        @extra = ref $extra ? @$extra : $extra;
        delete $args{'extra'};
    }

    if (my $groups = $args{'groups'}) {
        if (my $id = $fields{'Assigned Group'}) {
            my @list;
            foreach (ref $groups ? @$groups : $groups) { 
                my $name = $_->name;
                push @list, "'$id' = \"$name\"";
            }
            push @extra, ('(' . join (" OR ", @list) . ')')
                if scalar @list;
        }
    }

    # Don't forget 'Incident Type' and a simple "only give me tasks" option

#('Assigned Group*+' = "ITS Unix Systems" OR 'Assigned Group*+' = [...])
#AND ('Status*' = "Assigned" OR 'Status*' OR [...]) 
#AND ('Last Modified Date' <= $DATE$  (5*60*24*60)) AND ('Incident Type*' = "Request")

    if (my $status = lc $args{'status'}) { 
        if (my $margin = $self->human_to_data ('Status', 'Resolved')) {
            if    ($status eq 'open')   { $args{'Status'} = "-$margin"      }
            elsif ($status eq 'closed') { $args{'Status'} = "+=$margin"     }
            else                        { $args{'Status'} = $args{'status'} }
        }
        delete $args{'status'};
    } 

    if (my $user_assign = $args{'assigned_user'}) { 
        $args{'Assignee Login ID'} = $user_assign;
        delete $args{'assigned_user'};
    } else { 
        $args{'Assignee Login ID'} = $config->username || '%';
    }

    if (my $user_submit = $args{'submitted_user'}) { 
        $args{'SUNet ID+'} = $user_submit;
        delete $args{'submitted_user'};
    }

    if ($args{'unassigned'}) { 
        $args{'Assignee Login ID'} = undef;
        delete $args{'unassigned'};
    }

    if (my $modify = $args{'last_modify_before'}) { 
        $args{'Last Modified Date'} = "-$modify";
        delete $args{'last_modify_before'};
    }

    if (my $create = $args{'submit_before'}) { 
        $args{'Submit Date'} = "-$create";
        delete $args{'submit_before'};
    }

    if (scalar @extra) { $args{'extra'} ||= [@extra] }

    return %args;
}


=item print_text ()

=cut

sub print_text {
    my ($self, @list) = @_;

    unless (scalar @list) { 
        @list = qw/primary requestor assignee description resolution/;
    }
    
    my @return;
    foreach (@list) { 
        next unless my $func = $TEXT{$_};
        my $text = scalar $self->$func;
        push @return, $text if defined $text;
    }

    return wantarray ? @return : join ("\n", @return, '');
}

sub summary_text {
    my ($self) = @_;

    my $inc_num = $self->inc_num;
       $inc_num =~ s/^INC0+//;
    my $request = $self->sunet || 'NO_SUNETID';
       $request =~ s/NO_SUNETID|^\s*$/(none)/g;
    my $assign  = $self->assignee_sunet || "(none)";
    my $group   = $self->assignee_group || "(none)";
    my $summary = $self->summary || "";
    map { s/\s+$// } $summary, $group, $assign, $request;

    my $update = $self->date_modified;
    my $create = $self->date_submit;

    my @return;
    push @return, sprintf ("%-8s   %-8s   %-8s   %-32s  %12s", 
        $inc_num, $request, $assign, $group, $self->status || '(not set)');
    push @return, sprintf ("  Created: %s   Updated: %s", $create, $update);
    push @return, sprintf ("  Summary: %s", $summary);

    return wantarray ? @return : join ("\n", @return, '');
}


=item table ()

=cut

sub table { 'HPD:Help Desk' }

=item name (FIELD)

=cut

sub name { 
    my ($self, $field) = @_;
    my $id = $self->field_to_id ($field);
    return $self->map->{$field};
}

=back

=cut

###############################################################################
### Final Documentation
###############################################################################

=head1 REQUIREMENTS

B<Remedy::Ticket>, B<Class::Struct>, B<Remedy::Form>

=head1 SEE ALSO

Remedy(8)

=head1 HOMEPAGE

TBD.

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
