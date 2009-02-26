package Remedy;
our $VERSION = "0.13";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy - basic OO interface to the Remedy API

=head1 SYNOPSIS

    use Remedy;
    use Log::Log4perl qw/get_logger :no_extra_logdie_message/;

    my $logger = get_logger ('');
    my $remedy = eval { Remedy->connect ($CONFIG, 'debug' => $DEBUG) }
        or $logger->logdie ("couldn't connect to database: $@");
    $logger->logdie ($@) if $@;

    my $table = 'HPD:Help Desk';
    $logger->info ("pulling data about $table");
    foreach my $obj ($remedy->form ($table)) {
        if (defined $obj) {
            print scalar $obj->debug_table;
            exit 0;
        } else {
            print "No information for '$table'; known values:\n";
            foreach (sort $remedy->registered_classes) { print " * $_\n" }
            exit 1;
        }
    }

=head1 DESCRIPTION

Remedy offers a generic object-oriented interface to the ARSPerl Remedy
API, to usable read and modify objects in the Remedy database.  

This parent class is mostly just a wrapper to the functions that do the real
work:  B<Remedy::Session>, which manages the connection to the database itself,
and the B<Remedy::Form> family, which manages the database tables (forms) and
their individual entries.  Configuration is provided through B<Remedy::Config>,
and logging is provided through B<Remedy::Log>.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;

use Remedy::Config;
use Remedy::Form;
use Remedy::Session;

struct 'Remedy' => {
    'config'     => 'Remedy::Config',
    'formdata'   => '%',
    'logobj'     => 'Remedy::Log',
    'session'    => 'Remedy::Session',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=head2 Construction

=over 4

=item connect (ARGHASH)

Connects to the Remedy server, and creates a B<Remedy::Session> object.

Argument hash I<ARGHASH> accepts the following options:

=over 4

=item config I<CONFIG>

I<CONFIG> is either a B<Remedy::Config> object or a filename which we will
load to create a new B<Remedy::Config> object.  No default, which means that
B<Remedy::Config> will try to find a file with its own logic; see
B<Remedy::Config> for details.

=item debug I<COUNT>

Increases the debugging level for screen output by I<COUNT> levels, using
B<Remedy::Log::more_logging ()>.  See B<Remedy::Log> for more details.

=back

=cut

sub connect {
    my ($class, %args) = @_;
    my $self = $class->new ();

    ## Load and store configuration information
    my $config = $args{'config'};
    my $conf = ($config && ref $config) ? $config 
                                        : Remedy::Config->load ($config);
    $self->config ($conf);

    ## Get and save the logger
    $self->logobj ($self->config->log);
    if (my $debug = $args{'debug'}) { $self->logobj->more_logging ($debug); }

    ## From now on, we can print debugging messages when necessary
    my $logger = $self->logger_or_die ('no logger at init');

    ## Gather basic information from the configuration file; there's more to 
    ## be had, but this is a good start.
    my $host = $conf->remedy_host or $logger->logdie ("\$REMEDY_HOST not set");
    my $user = $conf->remedy_user or $logger->logdie ("\$REMEDY_USER not set");

    my %opts = ( 
        'password' => $conf->remedy_pass, 
        'server'   => $host, 
        'tcpport'  => $conf->remedy_port,
        'username' => $user
    );

    ## Create and save the Remedy::Session object
    $logger->debug ("creating remedy session to $host as $user");
    { 
        local $@;
        my $session = eval { Remedy::Session->new (%opts) } 
            or $logger->logdie ("couldn't create object: $@");
        $self->session ($session);
    }

    ## Actually connect to the Remedy server
    $logger->debug ("connecting to remedy server at $host");
    { 
        local $@;
        my $ctrl = eval { $self->session->connect () };
        unless ($ctrl) { 
            $@ =~ s/ at .*$//;
            $logger->logdie ("error on connect: $@");
        }
    }

    return $self;
}

=item form (TABLE)

Returns the B<Remedy::Form> object(s) corresponding to the table name I<TABLE>,
which can either be an internal Remedy table name, or a registered shortname
offered by the local forms.  See B<Remedy::Form::form ()> for more details.

=cut

sub form {
    my ($self, $form_name) = @_;
    $self->logger_or_die->all ("form ($form_name)");
    return Remedy::Form->form ($form_name, 'parent' => $self);
}

=back

=cut

##############################################################################
### CRUD - Create, Read, Update, Delete
##############################################################################

=head2 CRUD

Create, Read, Update, and Delete tables

=over 4

=item create (FORM_NAME)

may not actually be what I want

=cut

sub create { 
    my ($self, $form_name, @args) = @_;
    $self->logger_or_die->all ("create ($form_name)");
    return $self->form ($form_name, @args);
    # return $self->_doit ('create', 1, @_) 
}

=item read (FORM_NAME, ARGHASH)

Given the form I<FORM_NAME>, returns an appropriate 

=cut

sub read { 
    my ($self, $form_name, %args) = @_;
    my @return;
    foreach my $form ($self->form ($form_name)) {
        $self->logger_or_die->all (sprintf ("read (%s)", $form->table));
        push @return, $form->read ($form->table, %args);
    }
    return @return;
}

=item update (FORM_NAME, [...])

Not yet tested, probably wrong.  Probably ought to do this atomically.

=cut

sub update { 
    my ($self, $form_name, @args) = @_;
    my $count = 0;
    foreach my $entry ($self->read ($form_name, @args)) { 
        $entry->save || next;
        $count++;
    }
    return $count;
}

=item delete (FORM_NAME, [...])

Not yet tested, probably wrong.

=cut

sub delete { 
    my ($self, $form_name, %args) = @_;
    my $count = 0;
    foreach my $entry ($self->read ($form_name, %args)) { 
        $entry->delete || next;
        $count++;
    }
    return $count;
}

=item registered_classes ()

Lists the classes currently registred with B<Remedy::Form>.  Informational
only.  We might move or upgrade this later.

=cut

sub registered_classes { Remedy::Form->registered }

=item more_logging (COUNT)

Increase the logging level to STDERR.

=cut

sub more_logging {
    my ($self, $amount, @args) = @_;
    my $log = $self->logobj || return;
    $log->more_logging ($amount, @args);
}

=back

=cut

##############################################################################
### Class::Struct Methods ####################################################
##############################################################################

=head2 Class::Struct Methods

=head3 Regular Accessors

=over 4

=item config (B<Remedy::Config>)

Configuration 

=item logobj (B<Remedy::Log>)

=item formdata (%)

This hash is used by B<Remedy::Form> to cache form information (

=item session (B<Remedy::Session>)

Stores the actual connection

=back

=head3 Additional Accessors

=over 4

=item logger ()

Returns the actual B<Log::Log4perl::logger> object contained within the
B<Remedy::Log> object.  Dies 

=cut

sub logger { shift->logobj_or_die->logger (@_) }

=item config_or_die (TEXT)

=item logger_or_die (TEXT)

=item logobj_or_die (TEXT)

=item session_or_die (TEXT)

Like B<config ()>, B<logger ()>, B<logobj ()>, or B<session ()>, but die with   
an error (outside of the standard logging system) if the object is not yet     
set.                                                                           

=cut

sub config_or_die  { shift->_or_die ('config',  "no configuration", @_) }
sub logobj_or_die  { shift->_or_die ('logobj',  "no logger",        @_) }
sub logger_or_die  { shift->_or_die ('logger',  "no logger",        @_) }
sub session_or_die { shift->_or_die ('session', "no session",       @_) }

=back

=cut

###############################################################################
### Internal Subroutines ######################################################
###############################################################################

### DESTROY ()
# Tries to close the session on object destruction, if it's connected
sub DESTROY { if (my $session = shift->session) { $session->disconnect } }

### _or_die (TYPE, ERROR, EXTRATEXT, COUNT)
# Helper function for Class::Struct accessors.  If the value is not defined -
# that is, it wasn't set - then we will immediately die with an error message
# based on a the calling function (can go back extra levels by offering
# COUNT), a generic error message ERROR, and a developer-provided, optional
# error message EXTRATEXT.  
sub _or_die {
    my ($self, $type, $error, $extra, $count) = @_;
    return $self->$type if defined $self->$type;
    $count ||= 0;

    my $func = (caller ($count + 2))[3];    # default two levels back

    chomp ($extra);
    my $fulltext = sprintf ("%s: %s", $func, $extra ? "$error ($extra)"
                                                    : $error);
    die "$fulltext\n";
}

###############################################################################
### Final Documentation #######################################################
###############################################################################

=head1 REQUIREMENTS

B<Stanford::Remedy>

=head1 SEE ALSO

B<remedy>, B<remedy-ticket>, B<remedy-dump>

=head1 TODO

Make the B<delete ()> and B<update ()> functions useful.  

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
