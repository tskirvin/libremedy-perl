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

I<CONF> is a B<Remedy::Config> object, which contains details of how we will connect.

=cut

sub connect {
    my ($class, $config, %args) = @_;
    my $self = $class->new ();

    # Load and store configuration information
    my $conf = ($config && ref $config) ? $config 
                                        : Remedy::Config->load ($config);
    $self->config ($conf);

    # Get the logger
    my $logger = $self->config->logger;
    $self->logger ($logger);

    # Gather basic information from the configuration file; there's more to 
    # be had, but this is a good start.
    my $host = $conf->remedy_host or die "\$REMEDY_HOST not set\n";
    my $user = $conf->remedy_user or die "\$REMEDY_USER not set\n";

    my %opts = ( 
        'password' => $conf->remedy_pass, 
        'server'   => $host, 
        'tcpport'  => $conf->remedy_port,
        'username' => $user
    );

    $logger->debug ("creating remedy session to $host as $user");
    my $session = Remedy::Session->new (%opts) 
        or $logger->logdie ("couldn't create object: $@");
    $self->session ($session);

    local $@;
    $logger->debug ("connecting to remedy server");
    my $ctrl = eval { $session->connect () };
    unless ($ctrl) { 
        $@ =~ s/ at .*$//;
        $logger->logdie ("error on connect: $@");
    }

    return $self;
}

=item form (TABLE)

Returns the B<Remedy::Form> object corresponding to the table name I<TABLE>,
which can either be an internal Remedy table name, or a registered shortname
offered by the local forms.  See B<Remedy::Form::form ()> for more details.

=cut

sub form {
    my ($self, $form_name) = @_;
    return Remedy::Form->form ($form_name, 'parent' => $self);
}

=back

=cut

##############################################################################
### CRUD - Create, Read, Update, Delete
##############################################################################

=head2 CRUD

=over 4

=item create (FORM_NAME)

may not actually be what I want

=cut

sub create { 
    my ($self, $form_name, @args) = @_;
    # return $self->_doit ('create', 1, @_) 
}

=item read (FORM_NAME, ARGS)

=cut

sub read { 
    my ($self, $form_name, @args) = @_;

    my @return;
    foreach my $form ($self->form ($form_name)) {
        push @return, $form->read (@args);
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
    my ($self, $form_name, @args) = @_;
    my $count = 0;
    foreach my $entry ($self->read ($form_name, @args)) { 
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

=item new ()

=item config (B<Remedy::Config>)

=item logger (B<Remedy::Log>)

=item formdata (%)

=item session (B<Remedy::Session>)

=back

=head3 Additional Accessors

=over 4

=item config_or_die (TEXT)

Returns the current [...]

=item logger_or_die (TEXT)

=item session_or_die (TEXT)

=back

=cut

sub config_or_die  { shift->_or_die ('config',  "no configuration", @_) }
sub logger_or_die  { shift->_or_die ('logger',  "no logger",        @_) }
sub session_or_die { shift->_or_die ('session', "no session",       @_) }

###############################################################################
### Internal Subroutines ######################################################
###############################################################################

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

B<remedy-assign>, B<remedy-close>, B<remedy-list>, B<remedy-ticket>,
B<remedy-wrapper>

=head1 TODO

Touch up the documentation and make it more presentable; fix up the query for
the "unresolved" tickets to match the version run by other groups.

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
