package Remedy;
our $VERSION = "0.12";
our $ID = q$Id: Remedy.pm 4743 2008-09-23 16:55:19Z tskirvin$;
# Copyright and license are in the documentation below.

=head1 NAME

Remedy - basic OO interface to the Remedy API

=head1 SYNOPSIS

    use Remedy;

[...]

=head1 DESCRIPTION

Remedy offers an object-oriented interface to the ARSPerl Remedy API,
usable to read and modify tickets.  

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

# variables that must die
use vars qw/$TAG %remedy_HelpDesk %AR_SCHEMA %remedy_SGA %FILE_LOC/;

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use POSIX qw/strftime/;

use Stanford::Remedy::Form;
use Stanford::Remedy::Session;
use Stanford::Remedy::Incident;

use Remedy::Config;
use Remedy::Ticket;

struct 'Remedy' => {
    'config'   => 'Remedy::Config',
    'loglevel' => '$',
    'formdata' => '%',
    'session'  => 'Stanford::Remedy::Session',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=head2 Construction

=over 4

=item connect (CONFIG)

=over 4

=item 

=cut

sub connect {
    my ($class, $config, %args) = @_;

    my $self = $class->new ();

    # Load and store configuration information
    my $conf = $config if ($config && ref $config);
    $conf ||= Remedy::Config->new ($config);
    $self->config ($conf);

    # Gather basic information from the configuration file; there's more to 
    # be had, but this is a good start.
    my $host = $conf->remedy_host or $self->error ('$REMEDY_HOST not set');
    my $user = $conf->remedy_user or $self->error ('$REMEDY_USER not set');

    my %opts = ( 
        'password' => $conf->remedy_pass, 
        'server'   => $host, 
        'tcpport'  => $conf->remedy_port,
        'username' => $user
    );

    $self->warn_level (5, "creating remedy session to $host as $user");
    my $session = Stanford::Remedy::Session->new (%opts)
        or $self->error ("Couldn't create object: $@");
    $self->session ($session);

    local $@;
    $self->warn_level (5, "connecting to remedy server");
    my $ctrl = eval { $session->connect () };
    unless ($ctrl) { 
        $@ =~ s/ at .*$//;
        $self->error ("error on connect: $@");
    }

    return $self;
}

sub list {
    my ($self, %args) = @_;
    Remedy::Ticket->select ('db' => $self, %args);
}

=item parse_incident_number (NUMBER)

Given I<NUMBER>, pads that into a valid incident number - that is, something
that begins with either INC, TAS, or HD0, with a length of 15 characters.  If
no such prefix is offered, we'll assume you want 'INC', as so:  

  990977        INC000000990977

Returns undef if nothing can be created.

=cut

sub parse_incident_number {
    my ($self, $num) = @_;
    return $num if $num && $num =~ /^(HD0|INC|TAS)/ && length ($num) == 15;

    $num ||= "";
    if ($num =~ /^(HD0|TAS|INC)(\d+)$/) {
        $num = $1    . ('0' x (12 - length ($num))) . $2;
    } elsif ($num =~ /^(\d+)/) {
        $num = 'INC' . ('0' x (12 - length ($num))) . $1;
    } else {
        return;
    }
    return $num;
}

=back

=over 4

=item audit_entries (AR, INC_NUM)

Takes the incident number, and loads all audit information related to the
incident.  Returns the information as a hash or hashref (depending on context),
where the key is the relevant EntryID (suitable for sorting) and the value is a
hashref containing field ID/value pairs.

sub audit_entries {
    my ($self, $inc_num) = @_;
    my $ars = $self->ars;

    my $table = Remedy::Audit->table;

    my $eid = $self->eid_from_incnum ($inc_num);
    # Search by incident number - field 1000000161
    my $search = "'450' = \"$eid\"";
    my $query = ars_LoadQualifier($ars, $table, $search, 0);

    my %return;

    my %entries = $ars->query (
                                             $self->count, 0);
    foreach my $key (sort keys %entries) {
        next unless $key;

        (my %full = ars_GetEntry($ars, $self->schema, $key))
                || (warn "Error: $ars_errstr\n" and return);
        my $hash = {};
        foreach my $field (sort {$a<=>$b} keys %full) {
            $$hash{$field} = $full{$field};
        }
        $return{$key} = $hash;
    }

    wantarray ? %return : \%return;
}

=item eid_from_incnum (AR, INC_NUM)

Given a ticket 'INC' number (the 15-digit thing), gets the entry ID for that
ticket.  Returns it if possible, undef otherwise.


sub eid_from_incnum {
    my ($self, $inc_num) = @_;

    my $qs = "\'1000000161\' = \"$inc_num\"";
    my $lq = ars_LoadQualifier($self, $AR_SCHEMA{'HelpDesk'}, $qs);
    $self->remedy_log($TAG, "inc_num lq AR err: $ars_errstr") unless $lq;

    my @entries = ars_GetListEntry ($self, $AR_SCHEMA{'HelpDesk'},
                                    $lq, 0, 0, '1', 1);

    unless (scalar @entries) {
#        remedy_log($ars_errstr ? "getentry eid AR err: $ars_errstr"
#                               : "getentry eid AR err: no entries");
        return;
    }

    # Returns the first matching entry
    my $eid = shift @entries;
    $self->remedy_log_iflevel (5, $TAG, "$inc_num maps to entryid: $eid");
    return $eid;
}

=item group_from_incnum (AR, INC_NUM)

=cut

sub group_from_incnum { _info_from_incnum(shift, 'Assigned Group', @_); }

=item remedy_log (TAG, NOTE)

Writes out a log message to the log file specified in $FILE_LOC{RemedyLog}
(which is set in remedy.conf).  The log message looks like this:

  YYYY-MM-DD HH:MM:SS: [TAG] NOTE

Returns 1 if successful, undef on failure (with an error message printed to
STDERR).

=cut

sub remedy_log {
    my ($self, $tag, $note) = @_;
    $note ||= "no note";
    my $time = strftime ("%Y-%m-%d %H:%M:%S", localtime (time));
    my $file = $self->config->logfile;
    unless ($file) { warn "No logfile set!\n" && return }
    open (LOG, ">>$file") or (warn "Couldn't write to $file: '$!'"
                                                    and return);
    print LOG "$time: [$tag] $note\n";
    close LOG;
    1;
}

=item remedy_log_iflevel (LEVEL, TAG, TEXT)

Invokes B<remedy_log()> if C<LEVEL> is less than or equal to the globally-set
C<LOGLEVEL>.

=cut

sub remedy_log_iflevel {
    my ($self, $level, $tag, $text) = @_;
    return unless $level <= $self->loglevel;
    $self->remedy_log ($tag, $text);
}

=item remedy_logoff (SESSION)

Uses C<ars_Logoff()> to log C<SESSION> off from the remedy server.

=cut

sub remedy_logoff {
    my ($self) = @_;
    $self->warn_level (3, "closing connection");
    $self->ars->ars_Logoff();
}

=item search_sga (AR, [USER], [GID])

Searches the "Support Group Association" table, which matches users and
workgroups.  At least one of I<USER> (user login) or I<GID> (Group ID)
must be passed; searches the SGA table for as much information as it gets.  In
a scalar context, returns the first matched entry as a hashref with Key/Value
pairs being the information field numbers and the associated text; in a list
context, returns a hash of such entries, where the keys are the "Entry ID".

=cut

sub search_sga {
    my ($self, $user, $gid) = @_;
    return unless ($user || $gid);
    Remedy::SGA->search ('db' => $self, 'Login Name' => $user,
        'Group' => $gid);
}

=item search_supportgroup (AR, GroupName)

Searches the "Support Group" table for C<GroupName>.  In a scalar context,
returns the first matched entry as a hashref with Key/Value pairs being the
information field numbers and the associated text; in a list context, returns a
hash of such entries, where the keys are the "Entry ID".

=cut

sub search_supportgroup {
    my ($self, $group) = @_;
    Remedy::SupportGroup->search ('db' => $self, 'Group' => $group);
}

=item show_sga_full (AR, USER)

Shows debug-level information on all support group association associated with
C<USER>.

=cut

sub show_sga_full {
    my ($ar, $user) = @_;
    my @return = "All support group association information for '$user'";
    my %entries = search_sga($ar, $user);
    push @return, _show_hashinfo_debug ($ar, \%remedy_SGA, %entries);
    wantarray ? @return : join("\n", @return, '');
}

=item show_supportgroupinfo_full (AR, GROUP)

Shows all support group information for the group C<GROUP>.

=cut

sub show_supportgroupinfo_full {
    my ($ar, $group) = @_;
    my @return = "All support group information for '$group'";
    my %entries = search_supportgroup($ar, $group);
    #push @return, _show_hashinfo_debug($ar, \%remedy_SupportGroup, %entries);
    wantarray ? @return : join("\n", @return, '');
}

=item show_tkt_audit (AR, TKTHASHREF)

Shows all raw information about the worklog for the given C<TKTHASHREF>,
which is the result of an ars_GetEntry() call.

Returns either an array of strings or a pre-formatted string.

=cut

sub show_tkt_audit {
    my ($ar, $tkthash) = @_;
    remedy_log_iflevel(3, $TAG, "Entering show_tkt_worklog");

    my $inc_num = _helpdesk($tkthash, "Incident Number");
    my @return = "Audit Trail for $inc_num";

    my $count = 1;
    my %entries = audit_entries($ar, $inc_num);
    foreach my $key (sort keys %entries) {
        my $entry = $entries{$key};
        push @return, '', "Entry " . $count++;
        push @return, text_tkt_audit($ar, $entry);
    }
    unless (scalar %entries) { push @return, "  No Entries" }
    wantarray ? @return : join("\n", @return, '');
}

=item show_tkt_worklog (AR, TKTHASHREF)

Shows all raw information about the worklog for the given C<TKTHASHREF>,
which is the result of an ars_GetEntry() call.

Returns either an array of strings or a pre-formatted string.

=cut

sub show_tkt_worklog {
    my ($ar, $tkthash) = @_;
    remedy_log_iflevel(3, $TAG, "Entering show_tkt_worklog");

    my $inc_num = _helpdesk($tkthash, "Incident Number");
    my @return = "Worklog Entries for $inc_num";

    my $count = 1;
    my %entries = worklog_entries($ar, $inc_num);
    foreach my $key (sort keys %entries) {
        my $entry = $entries{$key};
        push @return, '', "Entry " . $count++;
        foreach my $field (sort {$a<=>$b} keys %{$entry}) {
            $$entry{$field} ||= "";
    #        my $value = $remedy_HDWorkLog{$field};
    #           $value = "*unknown*" unless defined $value;
    #        push @return, sprintf ($FORM_DEBUG_TEXT, $field, $value,
    #                                   $$entry{$field} || "(none)");
        }
    }
    unless (scalar %entries) { push @return, "  No Entries" }
    wantarray ? @return : join("\n", @return, '');
}


=item show_userinfo_full (AR, SUNetID)

=cut

sub show_userinfo_full {
    my ($self, $sunet) = @_;
    my @return = "All user information for '$sunet'";
    my %entries = $self->search_sga ($sunet);
    #push @return, _show_hashinfo_debug ($ar, \%remedy_SGA, %entries);
    #wantarray ? @return : join("\n", @return, '');
}

=item summary_search (AR, SEARCH [, SEARCH [, SEARCH ]] )

TBD.

=cut

sub summary_search {
    my ($self, @search) = @_;
    my $search = join(" and ", @search);
    my %entries = _helpdesk_search ($self, $search, $self->conf->count);
    my @return;
    foreach my $key (sort keys %entries) {
        my $entry = $entries{$key};
        push @return, scalar $self->summary_tkt ($entry);
    }
    wantarray ? @return : join("\n", @return, '');
}

=item text_tkt_audit (AR, AUDITHASH)

Returns a short version of the audit trail that might be somewhat
human-readable.

=cut

sub text_tkt_audit {
    my ($ar, $audhash) = @_;
    my @return;
    push @return, _format_text("Time", _form_date(
                                  _audit($audhash, "Create Time")));
    push @return, _format_text("Person", _audit($audhash, "Change Person"));
    my @fields = split(';', _audit($audhash, "Changed Fields"));
    my @parse = grep { $_ } @fields;
    push @return, _format_text("Changed Fields", join("; ", @parse));
    wantarray ? @return : join("\n", @return, '');
}

=item text_tktlist_assignee (AR, USERNAME, TYPE)

Returns a list of entries, formatted with B<summary_ticket()>, that were
assigned to the given C<USERNAME> and restricted by C<TYPE>.  Possible values
for C<TYPE>:

  open      Open tickets
  closed    Closed/Resolved tickets
  all       All tickets                 DEFAULT

=cut

sub text_tktlist_assignee {
    my ($ar, $user, $subtype) = @_;
    my $text;
    my @search = "'4' = \"$user\"";    # Search by Assignee SUNet ID

    if (lc $subtype eq 'open') {
        $text = "Open tickets assigned to user '$user'";
        push @search, "'7' < 4";  # Open tickets
    } elsif (lc $subtype eq 'closed') {
        $text = "Closed tickets assigned to user '$user'";
        push @search, "'7' >= 4"; # Closed tickets
    } else { $text = "All tickets assigned to user '$user'"; }

    _text_tkt_summary($ar, $text, @search);
}

=item text_tktlist_group (AR, GROUP, TYPE)

Returns a list of entries, formatted with B<summary_ticket()>, that were
assigned to the given C<GROUP> and restricted by C<TYPE>.  Possible values for
C<TYPE>:

  open      Open tickets
  closed    Closed/Resolved tickets
  all       All tickets                 DEFAULT

=cut

sub text_tktlist_group {
    my ($ar, $group, $subtype) = @_;
    my $text;
    my @search = "'1000000217' = \"$group\""; # Search by Assignee Group

    if (lc $subtype eq 'open') {
        $text = "Open tickets assigned to group '$group'";
        push @search, "'7' < 4";  # Open tickets
    } elsif (lc $subtype eq 'closed') {
        $text = "Closed tickets assigned to group '$group'";
        push @search, "'7' >= 4"; # Closed tickets
    } else { $text = "All tickets assigned to group '$group'"; }

    _text_tkt_summary($ar, $text, @search);
}

=item text_tktlist_submit (AR, USER, TYPE)

Returns a list of entries, formatted with B<summary_ticket()>, that were
submitted by the given C<USER> and restricted by C<TYPE>.  Possible values for
C<TYPE>:

  open      Open tickets
  closed    Closed/Resolved tickets
  all       All tickets                 DEFAULT

=cut

sub text_tktlist_submit {
    my ($ar, $user, $subtype) = @_;
    my $text;
    my @search = "'536871225' = \"$user\"";    # Search by Submitter SUNet ID

    if (lc $subtype eq 'open') {
        $text = "Open tickets submitted by user '$user'";
        push @search, "'7' < 4";  # Open tickets
    } elsif (lc $subtype eq 'closed') {
        $text = "Closed tickets submitted by user '$user'";
        push @search, "'7' >= 4"; # Closed tickets
    } else { $text = "All tickets submitted by user '$user'"; }

    _text_tkt_summary($ar, $text, @search);
}

=item text_tktlist_unassigned (AR, GROUP)

Finds unresolved tickets that are assigned to a C<GROUP> but are not yet
assigned to a specific person.

=cut

sub text_tktlist_unassigned {
    my ($ar, $group) = @_;
    my @search;

    push @search, "'7' < \"Resolved\"";         # Ticket is not resolved
    push @search, "'4' == NULL";                # Ticket is not assigned to a person
    push @search, "'1000000217' = \"$group\"";  # Ticket is from group GROUP

    my $string = "Unassigned tickets for '$group'";
    _text_tkt_summary($ar, $string, @search);
}

=item text_tktlist_unresolved (AR, GROUP, TIMESTAMP)

Finds unresolved tickets assigned to the group C<GROUP> that were submitted
before C<TIMESTAMP> (seconds-since-epoch), and skipping projects and orders.

=cut

sub text_tktlist_unresolved {
    my ($ar, $group, $time) = @_;

    my $formdate = _date_remedy ($time);

    my @search;
    push @search, "'7' < \"Resolved\"";         # Ticket is not resolved
    push @search, "'3' < \"$formdate\"";        # Ticket is from before DATE
    push @search, "'1000000217' = \"$group\"";  # Ticket is from group GROUP
    push @search, qq/('700000048' = \$--1\$ OR '700000048' != "Project" AND '700000048' != "Order")/;

    my $string = join(" ", "Unresolved tickets for '$group',",
                                "submitted before", _timedate($time));
    _text_tkt_summary($ar, $string, @search);
}


=cut

('Assigned Group*+' = "ITS Unix Systems" OR 'Assigned Group*+' = "ITS AFS" OR
'Assigned Group*+' = "ITS Directory Tech" OR 'Assigned Group*+' = "ITS Email
Servers" OR 'Assigned Group*+' = "ITS Kerberos" OR 'Assigned Group*+' = "ITS
Pubsw" OR 'Assigned Group*+' = "ITS Usenet" OR 'Assigned Group*+' = "ITS Web
Infrastructure") AND ('Status*' = "Assigned" OR 'Status*' = "In Progress" OR
'Status*' = "Pending" OR 'Status*' = "New") AND ('Last Modified Date' <= $DATE$
- (5*60*24*60)) AND ('Incident Type*' = "Request")

=cut

=item tkt (AR, INCNUM)

Pulls full data about a ticket from C<INCNUM>, the incident number that is the
general key to the tickets.  Returns C<TKTHASH> information, a hashref that is
used by other functions.

=cut

sub tkt {
    my ($self, $incnum) = @_;
    # $self->init_form ('Remedy::Ticket');
    Remedy::Ticket->select ('db' => $self, 'IncNum' => $incnum);
}

sub computer {
    my ($self, $cmdb) = @_;
    Remedy::ComputerSystem->select ('db' => $self, 'Name' => $cmdb);
}

sub init_form {
    my ($self, $class, @rest) = @_;
    return unless $class;

    local $@;
    my $return = eval { 
        require $class; 
        import $class @rest; 
        $class->import ($self) 
    };
    $self->error ("could not load class '$class': $@") unless $return;
    return $return;
}

=item tkt_assign (AR, TICKET, INFOHASH)

Assigns a ticket to a user and/or group.  C<INFOHASH> is a hash that contains
some combination of the following items:

  group     Group assignment ('Assigned Group').  Optional; will be pulled
            from existing ticket if necessary.
  person    SUNetID of the assigning user ('Assignee Login ID').  Optional;
            will be cleared if not set.

sub tkt_assign {
    my ($ar, $ticket, %hash) = @_;
    my $schema = $AR_SCHEMA{'HelpDesk'};

    my $person = $hash{'person'} || "";
    my $group  = $hash{'group'}  || "";
    # return "no group and/or person found" unless ($group || $person);

    my $eid = eid_from_incnum($ar, $ticket);
    return "no eid found" unless $eid;

    my %tktdata;

    # Get existing group if none is passed
    unless ($group) { $group = group_from_incnum($ar, $ticket) }

    my $ginfo = search_supportgroup($ar, $group);
    my $gid = ($ginfo && ref $ginfo) ? $$ginfo{'1'} : "";
    return "Cannot assign to invalid group '$group'" unless $gid;

    # Assign the group if it's passed to us; check to see if it's valid first
    if ($hash{'group'}) {
        $tktdata{'1000000079'} = $gid;          # 'Assigned Group ID'
        #$tktdata{'1000000251'} = $COMPANY;      # 'Support Company'
        #$tktdata{'1000000014'} = $SUBORG;       # 'Support Organization'
        $tktdata{'1000000217'} = $group;        # 'Assigned Group'
    }

    # Check to see if this person is a member of the group
    if ($person) {
        my $name = "";
        if (my $return = search_sga($ar, $person, $gid)) {
            $name   = $return->{$remedy_SGA{'Full Name'}};
            $person = $return->{$remedy_SGA{'Login Name'}};
        }
        return "User '$person' is not in group '$group'" unless $name;
        $tktdata{'1000000218'} = $name;     # 'Assignee'
        $tktdata{'4'}          = $person;   # 'Assignee' (SUNetID)
    } else {
        # leave the name/person blank; we're resetting the value
        $tktdata{'1000000218'} = undef;     # 'Assignee'
    }

    # Actually perform the update.
    unless (ars_SetEntry($ar, $schema, $eid, 0, %tktdata)) {
        return "Couldn't modify '$ticket': $ars_errstr";
    } else { return 0 }
}

=item tkt_close (AR, TICKET, TEXT)

Closes a ticket.

Note that you must assign the ticket first with tkt_assign(), but that this
function does not actually try to do so on its own.

Also note that you can close a ticket again, and it just overrides the old
text.  This may not be ideal; we'll revisit.

=cut

sub tkt_close {
    my ($ar, $ticket, $text) = @_;
    my $schema = $AR_SCHEMA{'HelpDesk'};

    my $eid = eid_from_incnum($ar, $ticket);
    return "no eid found" unless $eid;

    # should check to see if it's assigned properly?

    my %tktdata;
    $tktdata{'1000000156'} = $text;                 # 'Resolution'
    $tktdata{'1000005261'} = time;                  # 'Resolution Date'
    $tktdata{'7'}          = 4;                     # 'Status' = "Resolved"
    $tktdata{'1000000215'} = 11000;                 # 'Reported Source'
    $tktdata{'1000000150'} = 17000;                 # "No Further Action Required"
    # Not doing 1000000642, "Time Spent"

#    unless (ars_SetEntry($ar, $schema, $eid, 0, %tktdata)) {
#        return "Couldn't modify entry for $ticket: $ars_errstr";
#    } else { return 0 }
}

sub tkt_setstatus {
    my ($self, $ticket, $status) = @_;
    my $schema = $AR_SCHEMA{'HelpDesk'};

    my $eid = $self->eid_from_incnum ($ticket);
    return "no eid found" unless $eid;

    # should check to see if it's assigned properly?

    my %tktdata;
    $tktdata{'7'}          = 4;                     # 'Status' = "Resolved"
    $tktdata{'1000000215'} = 11000;                 # 'Reported Source'
    # Not doing 1000000642, "Time Spent"

#    unless (ars_SetEntry($ar, $schema, $eid, 0, %tktdata)) {
#        return "Couldn't modify entry for $ticket: $ars_errstr";
#    } else { return 0 }
}

=item text_groupinfo (AR, GROUPNAME)

Prints basic information about C<GROUPNAME>.  This consists of the name of the
group, the date that it was created, and the current members of the group (as
parsed out of the SupportGroup table).  Depending on method of invocation,
returns either a multi-line string or an array of lines that make up the
strong.

=cut

sub text_groupinfo {
    my ($ar, $group) = @_;
    remedy_log_iflevel(3, $TAG, "Entering text_groupinfo()");

    my @return = "Group information for '$group'";
    my $entry = search_supportgroup($ar, $group);
    if ($entry) {
        push @return, _format_text("Name", $group);
        push @return, _format_text("Group ID", _suppgrp($entry, "Entry ID"));
        push @return, _format_text("Created", _form_date(
                                    _suppgrp($entry, "Create Time")));
        push @return, _format_text("Members", "");
        my $gid = _suppgrp($entry, "Entry ID");
        my %groups = search_sga($ar, undef, $gid);
        foreach my $grp (sort keys %groups) {
            my $info = $groups{$grp};
            next unless ($info && ref $info);
            my $name =  _sgainfo($info, "Full Name") || "*unknown*";
            my $sunet = _sgainfo($info, "Login Name") || "*unknown*";
            push @return, "    $name <$sunet\@stanford.edu>";
        }
        push @return, "    No Matches" unless scalar %groups;

    } else { push @return, "  No Entries" }
    wantarray ? @return : join("\n", @return, '');
}

=item text_userinfo (AR, SUNETID)

Lists all information about the given user, including what groups the user is a
member of.  Depends on the 'User' table.

=cut

sub text_userinfo {
    my ($self, $ar, $sunet) = @_;
    $self->remedy_log_iflevel(3, $TAG, "Entering text_userinfo()");

    my @return = "User information for '$sunet'";

    my $entry = search_sga($ar, $sunet);
    if ($entry) {
        push @return, _format_text("Full Name",
                _sgainfo($entry, "Full Name") || "(unknown)");
        push @return, _format_text("SUNetID",
                _sgainfo($entry, "Login Name") || "(unknown)");
        my @groups = user_groups($ar, $sunet);
        if (scalar @groups) {
            push @return, _format_text("Subscribed Groups", "");
            foreach my $name (sort @groups) {
                push @return, "    $name";
            }
        } else {
            push @return, _format_text("Subscribed Groups", "None Found")
        }
    } else { push @return, "  No matches" }
    wantarray ? @return : join("\n", @return, '');
}

=cut

sub user_groups {
    my ($ar, $sunet) = @_;

    my @return;
    my %groups = search_sga($ar, $sunet);
    if (scalar %groups) {
        foreach my $group (sort keys %groups) {
            my $key = $groups{$group}->{'1000000079'};
            my $grp = _schema_search($ar, $AR_SCHEMA{'SuppGrp'},
                                            "'1' = \"$key\"");
            next unless ($grp && ref $grp);
            my $name = _suppgrp($grp, "Group") || "*unknown*";
            push @return, $name;
        }
    }
    @return;
}

=cut

=item warn_level (LEVEL, TEXT)

Iff I<LEVEL> is at least the value of I<loglevel> is set, writes a debugging
message C<TEXT> with the current package name to STDERR and log it to the log
as well.

=cut

sub warn_level {
    my ($self, $level, @text) = @_;
    @text = grep { $_ if defined $_ } @text;       # so we can ignore undef
    if (scalar @text && ($level <= 0 || $self->config->loglevel >= $level)) {
        warn __PACKAGE__, ": @text\n";
        $self->remedy_log ($level, @text);
    }
    return;
}

sub error { die shift->warn_level (0, @_), "\n" }

###############################################################################
### Internal Subroutines ######################################################
###############################################################################

=cut

### _date_remedy(TIME)
# We sort by seconds-since-epoch, apparently.
# Remedy database.  Note that this does, in fact, suck - two letter year?

sub _date_remedy { my ($time) = @_; $time ||= time; return $time; }

### _format_text (TEXT, VALUE)
# Returns a formatted string of the form "TEXT: VALUE", based on a pre-set
# format string.  Used for basic text layout.

sub _format_text {
    my ($text, @value) = @_;
    my $value = scalar @value ? join(" ", @value) : "";
    return "" unless (defined $text && defined $value);
    sprintf($FORM_TKT_TEXT, $text ? "$text:" : "", $value);
}

### _format_worklog_text (TEXT, VALUE)
# Returns a formatted string of the form "TEXT: VALUE", based on a pre-set
# format string.  Used for basic text layout of worklogs.

sub _format_worklog_text {
    my ($text, $value) = @_;
    return "" unless (defined $text && defined $value);
    sprintf($FORM_WORKLOG_TEXT, "$text:", $value);
}

### _form_array (ENTRY , ARRAYREF)
# Gets item ENTRY out of the array ARRAYREF, or some explanatory text if none
# exists.

sub _form_array {
    my ($value, $arrayref) = @_;
    return "not an array" unless ref $arrayref;
    return "(not set)" unless defined $value;
    defined $$arrayref[$value] ? $$arrayref[$value] : "No entry for '$value'";
}

### _form_date (DATE)
# Formats a date string from DATE.

sub _form_date {
    my ($value) = @_;
    $value ? _timedate ($value) : "(unknown)";
}

### _form_hash (ENTRY, HASHREF)
# Gets $HASHREF{$ENTRY} or some explanatory text if none exists.

sub _form_hash {
    my ($value, $hashref) = @_;
    return "" unless ref $hashref;
    $value ||= 0;
    defined $$hashref{$value} ? $$hashref{$value}
                              : "No entry for '$value'";
}

### _form_name_and_email (NAME, EMAIL)
# Forms consistent name-and-email field, like in a 'From' header.

sub _form_name_and_email {
    my ($name, $email) = @_;
    $name = "(unknown)" unless $email;
    if ($email) { $email .= '@stanford.edu' unless $email =~ /@/ }
    else        { $email = ""; }
    $email ? "$name <$email>" : "$name";
}

### _helpdesk  (TKTHASHREF, FIELD)
### _userinfo  (TKTHASHREF, FIELD)
### _groupinfo (TKTHASHREF, FIELD)
# Using _hashinfo(), returns either the value in TKTHASHREF based on FIELD
# from the appropriate remedy_* hash, or undef.
#sub _audit     { _hashinfo(\%remedy_Audit, @_) }
#sub _groupinfo { _hashinfo(\%remedy_Group, @_) }
#sub _userinfo  { _hashinfo(\%remedy_User, @_) }
#sub _helpdesk  { _hashinfo(\%remedy_HelpDesk, @_) }
#sub _suppgrp   { _hashinfo(\%remedy_SupportGroup, @_) }
#sub _sgainfo   { _hashinfo(\%remedy_SGA, @_) }

#sub _hashinfo {
#    my ($hash, $tkthash, $text) = @_;
#    return unless (ref $hash && ref $tkthash && defined $text);
#    return unless $$hash{$text};
#    $tkthash->{$$hash{$text}} || undef;
#}

### _info_from_incnum (AR, FIELD, INCNUM)
# Searches the HelpDesk field for information about a ticket INCNUM, and pulls
# information from a specific FIELD.  Depending on context, returns either a list
# of matching values, or just the first value (in a scalar context).

sub _info_from_incnum {
    my ($ar, $field, $inc_num) = @_;
    my $fieldid = $remedy_HelpDesk{$field} || return;

    my $qs = "\'1000000161\' = \"$inc_num\"";
    my $lq = ars_LoadQualifier($ar, $AR_SCHEMA{'HelpDesk'}, $qs);
    my @entries = ars_GetListEntryWithFields($ar, $AR_SCHEMA{'HelpDesk'},
                                   $lq, 0, 0);
    my (@return, $return);
    return unless (scalar @entries);
    while (@entries) {
        my $key = shift @entries;  my $value = shift @entries;
        next unless (defined $key && $value && ref $value);
        $return = $value->{$fieldid} unless defined $return;
        push @return, $value->{$fieldid};
    }

    # Returns the first matching entry
    wantarray ? @return : $return;
}

### _show_hashinfo_debug (AR, HASHREF, ENTRIES)
# Wrapper to show information about a given table in a consistent form, based
# on $FORM_DEBUG_TEXT.

sub _show_hashinfo_debug {
    my ($ar, $translate, %entries) = @_;

    my @return;
    foreach my $key (sort keys %entries) {
        my $entry = $entries{$key};
        foreach my $field (sort {$a<=>$b} keys %{$entry}) {
            $$entry{$field} ||= "";
            my $value = $$translate{$field};
               $value = "*unknown*" unless defined $value;
            push @return, sprintf ($FORM_DEBUG_TEXT, $field, $value,
                                       $$entry{$field} || "(none)");
        }
    }
    unless (scalar %entries) { push @return, "  No Entries" }
    wantarray ? @return : join("\n", @return);
}

=cut

1;

###############################################################################
### Final Documentation #######################################################
###############################################################################

=head1 REQUIREMENTS

B<ARS>

=head1 SEE ALSO

B<remedy-assign>, B<remedy-close>, B<remedy-list>, B<remedy-ticket>,
B<remedy-worklog>, B<remedy-wrapper>

=head1 TODO

Touch up the documentation and make it more presentable; try to take advantage
of Adam's version of this class; fix up the query for the "unresolved" tickets
to match the version run by other groups.

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 HOMEPAGE

TBD.

=head1 LICENSE

Licensed for internal Stanford use only.  This will hopefully be revisited
later.

=head1 COPYRIGHT

Copyright 2008-2009, Tim Skirvin and Board of Trustees, Leland Stanford
Jr. University

=cut
