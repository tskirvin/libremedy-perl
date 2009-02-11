package Remedy;
our $VERSION = "0.13";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy - basic OO interface to the Remedy API

=head1 SYNOPSIS

    use Remedy;

    my $config = Remedy::Config->load ($CONFIGFILE);
    my $remedy = Remedy->connect ($config);

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
use Log::Log4perl qw/:easy/;
use POSIX qw/strftime/;

use Remedy::Config;
use Remedy::Form;
use Remedy::Session;

struct 'Remedy' => {
    'config'     => 'Remedy::Config',
    'error'      => '$',
    'logger'     => 'Log::Log4perl::Logger',
    'formdata'   => '%',
    'session'    => 'Remedy::Session',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=head2 Construction

=over 4

=item connect (CONFIG)

Connects to the Remedy server, and creates a B<Remedy::Session> object.

I<CONFIG> is either a B<Remedy::Config> object or a filename which we will load
to create a new B<Remedy::Config> object.  

=cut

sub connect {
    my ($class, $config, %args) = @_;
    my $self = $class->new ();

    ## Load and store configuration information
    my $conf = ($config && ref $config) ? $config 
                                        : Remedy::Config->load ($config);
    $self->config ($conf);

    ## Get and save the logger
    my $logger = $self->config->logger;
    $self->logger ($logger);

    ## Gather basic information from the configuration file; there's more to 
    ## be had, but this is a good start.
    my $host = $conf->remedy_host or die "\$REMEDY_HOST not set\n";
    my $user = $conf->remedy_user or die "\$REMEDY_USER not set\n";

    my %opts = ( 
        'password' => $conf->remedy_pass, 
        'server'   => $host, 
        'tcpport'  => $conf->remedy_port,
        'username' => $user
    );

    ## Create and save the Remedy::Session object
    { 
        local $@;
        $logger->debug ("creating remedy session to $host as $user");
        my $session = eval { Remedy::Session->new (%opts) } 
            or $logger->logdie ("couldn't create object: $@");
        $self->session ($session);
    }

    ## Actually connect to the Remedy server
    { 
        local $@;
        $logger->debug ("connecting to remedy server");
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
        push @return, $form->read (%args);
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

=item logger (B<Remedy::Log>)

=item formdata (%)

This hash is used by B<Remedy::Form> to cache form information (

=item session (B<Remedy::Session>)

Stores the actual connection

=back

=head3 Additional Accessors

=over 4

=item config_or_die (TEXT)

=item logger_or_die (TEXT)

=item session_or_die (TEXT)

Like B<config ()>, B<logger ()>, or B<session (), but die with an error 
(outside of the standard logging system) if the object is not yet set.  

=back

=cut

sub config_or_die  { shift->_or_die ('config',  "no configuration", @_) }
sub logger_or_die  { shift->_or_die ('logger',  "no logger",        @_) }
sub session_or_die { shift->_or_die ('session', "no session",       @_) }

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
