package Remedy::Incident;
our $VERSION = "0.12";
our $ID = q$Id: Remedy.pm 4743 2008-09-23 16:55:19Z tskirvin$;
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

=item $DOMAIN

Added to the end of incomplete email addresses.  Defaults to 'stanford.edu'.
Should actually  be put somewhere else... I'll keep working on it.

=cut

our $DOMAIN = 'stanford.edu';

=back

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use POSIX qw/strftime/;

use Remedy::Audit;
use Remedy::Form;
use Remedy::TicketGen;
use Remedy::WorkLog;

our @ISA = (Remedy::Form::init_struct (__PACKAGE__, 
    'ticketgen' => 'Remedy::TicketGen'), 'Remedy::Form');

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

=cut

    $tktdata{'1000000156'} = $text;                 # 'Resolution'
    $tktdata{'1000005261'} = time;                  # 'Resolution Date'
    $tktdata{'7'}          = 4;                     # 'Status' = "Resolved"
    $tktdata{'1000000215'} = 11000;                 # 'Reported Source'
    $tktdata{'1000000150'} = 17000;                 # "No Further Action Required"
    # Not doing 1000000642, "Time Spent"

=cut

sub get_incnum {
    my ($self, %args) = @_;
    my ($parent, $session) = $self->parent_and_session (%args);

    return $self->inc_num if defined $self->inc_num;
    if (! $self->ticketgen) {
        my %args = ('db' => $parent);

        my $ticketgen = Remedy::TicketGen->create (%args) or $self->error 
            ("couldn't create new ticket number: " .  $session->error );
        $ticketgen->description ($args{'description'} || $self->default_desc);
        $ticketgen->submitter ($args{'user'} || $parent->config->remedy_user);

        print scalar $ticketgen->print_text, "\n";
        $ticketgen->save ('db' => $parent) 
            or $self->error ("couldn't create new ticket number: $@");
        $ticketgen->reload;
        $self->ticketgen ($ticketgen);
        $self->inc_num ($ticketgen->inc_num);
    }

    return $self->ticketgen->inc_num;
}

sub default_desc { "Created by " . __PACKAGE__ }

=item assignee 

=cut

sub assignee {
    my ($self) = @_;
    return _format_email ($self->assignee_name, $self->assignee_sunet);
}

=item requestor

=cut

sub requestor {
    my ($self) = @_;
    my $name = join (" ", $self->requestor_first_name || '',
                          $self->requestor_last_name || '');
    return _format_email ($name, $self->requestor_email || '');
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
        'Last Modified' => $self->format_date ($self->date_modified),
    );
    return wantarray ? @return : join ("\n", @return, '');
}

=item text_audit

=cut

sub text_audit {
    my ($self, %args) = @_;
    my (@return, $count);
    foreach my $audit ($self->audit (%args)) { 
        push @return, '' if $count;
        push @return, "Audit Entry " . ++$count;
        push @return, ($audit->print_text);
    }
    return unless $count;
    return wantarray ? @return : join ("\n", @return, '');
}

=item text_description ()

=cut

sub text_description {
    my ($self) = @_;
    my @return = "User-Provided Description";
    push @return, $self->format_text ({'prefix' => '  '},
        $self->description || '(none)');
    return wantarray ? @return : join ("\n", @return, '');
}

sub text_primary {
    my ($self, %args) = @_;
    my @return = "Primary Ticket Information";
    # print $self->form->as_string;
    push @return, $self->format_text_field ( 
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Ticket'        => $self->inc_num       || "(none set)", 
        'Summary'       => $self->summary,
        'Status'        => $self->status        || '(not set/invalid)',
        'Status Reason' => $self->status_reason || '(not set)',
        'Submitted'     => $self->format_date ($self->date_submit),
        'Urgency'       => $self->urgency       || '(not set)',
        'Priority'      => $self->priority      || '(not set)',
        'Incident Type' => $self->incident_type || "(none)",
    );

    return wantarray ? @return : join ("\n", @return, '');
}

sub text_resolution {
    my ($self) = @_;
    my @return = "Resolution";

    my $resolution= $self->resolution || return;
    push @return, $self->format_text_field ( 
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Date' => $self->format_date ($self->date_resolution),
    );
    push @return, '', $self->format_text ({'prefix' => '  '}, $resolution);

    return wantarray ? @return : join ("\n", @return, '');
}

sub text_worklog {
    my ($self, %args) = @_;
    my (@return, $count);
    foreach my $worklog ($self->worklog (%args)) { 
        push @return, '' if $count;
        push @return, "Work Log Entry " . ++$count;
        push @return, ($worklog->print_text);
    }
    return unless $count;
    return wantarray ? @return : join ("\n", @return, '');
}


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
    return Remedy::Audit->read ('db' => $self->parent_or_die (%args),
        'EID' => $self->id, %args);
}

=item worklog ()

=cut

sub worklog {
    my ($self, %args) = @_;
    return unless $self->inc_num;
    return Remedy::WorkLog->read ('db' => $self->parent_or_die (%args),
        'EID' => $self->inc_num, %args);
}

=item worklog_create ()

Creates a new worklog entry, pre-populated with 

=over 4

=item time (TIME)

=back

=cut

sub worklog_create {
    my ($self, %args) = @_;
    return unless $self->inc_num;
    my $worklog = Remedy::WorkLog->create (
        'db' => $self->parent_or_die (%args), %args);
    $worklog->inc_num ($self->inc_num);
    $worklog->date_submit ($args{'time'} || time);
    # add a category as well
    return $worklog;
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
    'date_resolution'       => "Estimated Resolution Date",
}

=item limit ()

=over 4

=item IncRef I<incref>

=item Type I<status>

=item Unassigned I<value>

=back

=cut

sub limit {
    my ($self, %args) = @_;
    my $parent  = $self->parent_or_die (%args);
    my $session = $self->session_or_die (%args);

    if (my $incnum = $args{'IncNum'}) { 
        my $id = $self->field_to_id ("Incident Number", 'db' => $parent);
        return "'$id' == \"$incnum\"";
    }

    $args{'Assigned Support Company'}      ||= $parent->config->company   || "%";
    $args{'Assigned Support Organization'} ||= $parent->config->sub_org   || "%";
    $args{'Assigned Group'}                ||= $parent->config->workgroup || "%";
    $args{'Assignee Login ID'}             ||= $parent->config->username  || "%";
    my @return = $self->limit_basic (%args);

    if (my $type = $args{'Type'}) { 
        my $id = $self->field_to_id ("Status", 'db' => $parent);
        if (lc $type eq 'open') { 
            push @return, "'$id' < \"Resolved\"";
        } elsif (lc $type eq 'closed') { 
            push @return, "'$id' >= \"Resolved\"";
        }
    }
    
    if ($args{'Unassigned'}) { 
        my $id = $self->field_to_id ("Assignee Login ID", 'db' => $parent);
        push @return, "'$id' == NULL";
    }

    if ($args{'before'}) { 
        # ...
    }
    return @return;
}

=item print_text ()

=cut

sub print_text {
    my ($self, %args) = @_;
    my $parent  = $self->parent_or_die (%args);
    my $session = $self->session_or_die (%args);

    my @return;
    push @return, ($self->text_primary (%args));
    push @return, '', ($self->text_requestor (%args));
    push @return, '', ($self->text_assignee (%args));
    push @return, '', ($self->text_description (%args));
    if (my @worklog = ($self->text_worklog (%args))) { 
        push @return, '', @worklog;
    }
    if (my @resolution = ($self->text_resolution (%args))) { 
        push @return, '', @resolution;
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

##############################################################################
### Internal Subroutines 
##############################################################################

### _format_email (NAME, EMAIL) 
# Format a name and email address consistently
sub _format_email {
    my ($name, $email) = @_;
    $name ||= "";
    if ($email) { $email .= '@' . $DOMAIN unless $email =~ /@/ } 
    else        { $email = "" }
    return $email ? "$name <$email>" : "$name";
}

###############################################################################
### Final Documentation
###############################################################################

=head1 REQUIREMENTS

B<Class::Struct>, B<Remedy::Form>

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
