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
use POSIX qw/strftime/;

use Remedy::Config;
use Remedy::Form;
use Remedy::Session;

struct 'Remedy' => {
    'config'     => 'Remedy::Config',
    'debugl'     => '$',
    'formdata'   => '%',
    'session'    => 'Remedy::Session',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=head2 Class::Struct Methods

=over 4

=item new ()

=item config (B<Remedy::Config>)

=item debug ($)

=item formdata (%)

=item session (B<Remedy::Session>)

=back

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
    my $session = Remedy::Session->new (%opts)
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

=back

=cut

##############################################################################
### CRUD - Create, Read, Update, Delete
##############################################################################

=head2 CRUD

=over 4

=item create (FORM_NAME)

=cut

sub create {
    my ($self, $form_name) = @_;
    my $form = Remedy::Form->form ($form_name, 'db' => $self) || return;
    return $form->create ('db' => $self);
}

=item read (FORM_NAME, ARGS)

=cut

sub read   { 
    my ($self, $form_name, @args) = @_;
    my $form = Remedy::Form->form ($form_name, 'db' => $self) || return;
    return $form->read ('db' => $self, @args);
}

=item update (FORM_NAME, [...])

Not yet tested, probably wrong.  In fact, probably ought to do this atomically.

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
### Errors and Debugging #####################################################
##############################################################################

=head2 Errors and Debugging

=over 4

=item warn_level (LEVEL, TEXT)

Iff I<LEVEL> is at least the value of I<debug> is set, writes a debugging
message C<TEXT> with the current package name to STDERR.

=cut

sub warn_level {
    my ($self, $level, @text) = @_;
    @text = grep { $_ if defined $_ } @text;       # so we can ignore undef
    if (scalar @text && ($level <= 0 || $self->config->debug >= $level)) {
        my $text = join ("\n", @text);
        chomp $text;
        warn __PACKAGE__, ": $text\n";
    }
    return;
}

=item error (TEXT)

Exits with an error message I<TEXT>.

=cut

sub error { die shift->warn_level (0, @_), "\n" }

###############################################################################
### Internal Subroutines ######################################################
###############################################################################

sub DESTROY { if (my $session = shift->session) { $session->disconnect } }

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
