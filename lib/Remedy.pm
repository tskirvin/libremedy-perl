package Remedy;
our $VERSION = "0.13";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy - basic OO interface to the Remedy API

=head1 SYNOPSIS

    use Remedy;

[...]

=head1 DESCRIPTION

Remedy offers an object-oriented interface to the ARSPerl Remedy API, usable to
read and modify tickets.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use POSIX qw/strftime/;

use Stanford::Remedy::Form;
use Stanford::Remedy::Session;

use Remedy::Config;
use Remedy::Table;
use Remedy::Incident;
use Remedy::Task;
use Remedy::User;

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

=head2 Class::Struct Methods

=over 4

=item new ()

=item config (B<Remedy::Config>)

=item loglevel ($)

=item formdata (%)

=item session (B<Stanford::Remedy::Session>)

=back

=head2 Construction

=over 4

=item connect (CONFIG)

Connects to the Remedy server, and creates a B<Stanford::Remedy::Connection> object.

I<CONF> is a B<Remedy::Config> object, which contains details of how we will connect.

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

=item init_form (CLASS [, EXTRA])

=cut

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

=back

=head2 CRUD

=over 4

=item create ()

=item read ()

=item update ()

=item delete ()

=back

=cut

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
    my $time = strftime ("%Y-%m-%d %H:%M:%S %Z", localtime (time));
    my $file = $self->config->logfile;
    return $self->warn_debug (2, 'no logfile set') unless defined $file;
    open (LOG, ">>", $file) 
        or return $self->warn_debug (1, "can't write to $file: $!");
    print LOG "$time: [$tag] $note\n";
    close LOG;
    return 1;
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

=item incident (AR, INCNUM)

Pulls full data about a ticket from C<INCNUM>, the incident number that is the
general key to the tickets.  Returns C<TKTHASH> information, a hashref that is
used by other functions.

=cut

sub list {
    my ($self, %args) = @_;
    Remedy::Incident->read ('db' => $self, %args);
}

sub incident {
    my ($self, $incnum) = @_;
    Remedy::Incident->read ('db' => $self, 'IncNum' => $incnum);
}

=item incident_create ()

=cut

sub incident_create { shift->create ('Remedy::Incident', @_) }

=item computer (HOSTNAME)

=cut

sub computer {
    my ($self, $cmdb) = @_;
    Remedy::ComputerSystem->read ('db' => $self, 'Name' => $cmdb);
}

=item user (USERNAME)

=cut

sub user {
    my ($self, $netid) = @_;
    # Remedy::User->read ('db' => $self, 'all' => 1, 'Login Name' => $netid);
    Remedy::User->read ('db' => $self, 'all' => 1,);
}

sub create {
    my ($self, $form) = @_;
    my $registered = Remedy::Table->registered_form ($form);
    $self->error ("no such form: '$form'") unless defined $registered;
    return $registered->new ('db' => $self);
}
sub read   { 
    my ($self, $form, @args) = @_;
    my $registered = Remedy::Table->registered_form ($form);
    $self->error ("no such form: '$form'") unless defined $registered;
    return $registered->read ('db' => $self, @args);
}
sub update { 
    my ($self, $form, $entry) = @_;
    ### 
    return
}
sub delete { 
    my ($self, $form, @args) = @_;
}

sub registered_classes { Remedy::Table->registered }

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
        #$tktdata{'1000000251'} = $COMPANY;     # 'Support Company'
        #$tktdata{'1000000014'} = $SUBORG;      # 'Support Organization'
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

=cut

##############################################################################
### Errors and Debugging #####################################################
##############################################################################

=head2 Errors and Debugging

=over 4

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

=item error (LEVEL, TEXT)

=cut

sub error { die shift->warn_level (0, @_), "\n" }

###############################################################################
### Internal Subroutines ######################################################
###############################################################################

sub DESTROY { if (my $session = shift->session) { $session->disconnect } }

###############################################################################
### Final Documentation #######################################################
###############################################################################

=head1 TODO

Merge B<Stanford::Remedy::Session>, B<Stanford::Remedy::Form>, and
B<Stanford::Remedy::FormData> into this module set.

B<Remedy::Incident> should be split into Ticket/Incident and Ticket/Task

=head1 REQUIREMENTS

B<Stanford::Remedy>

=head1 SEE ALSO

B<remedy-assign>, B<remedy-close>, B<remedy-list>, B<remedy-ticket>,
B<remedy-wrapper>

=head1 TODO

Touch up the documentation and make it more presentable; try to take advantage
of Adam's version of this class; fix up the query for the "unresolved" tickets
to match the version run by other groups.

=head1 AUTHOR

Tim Skirvin <tskirvin@stanford.edu>

=head1 HOMEPAGE

TBD.

=head1 LICENSE

Copyright 2008-2009 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
