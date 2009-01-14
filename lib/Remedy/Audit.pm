package Remedy::Audit;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Audit - per-ticket worklogs

=head1 SYNOPSIS

    use Remedy::Audit;

    # $remedy is a Remedy object
    my @audit = Remedy::Audit->read (
        'db' => $remedy, 'IncNum' => 'INC000000002371');
    for my $item (@audit) { print scalar $item->print_text }

=head1 DESCRIPTION

Stanfor::Remedy::Unix::WorkLog tracks individual work log entries for tickets as part
of the remedy database.  It is a sub-class of B<Stanford::Packages::Form>, so
most of its functions are described there.

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy;
use Remedy::Form;

our @ISA = (Remedy::Form::init_struct (__PACKAGE__), 'Remedy::Form');

##############################################################################
### Class::Struct
##############################################################################

=head1 FUNCTIONS

These 

=head2 B<Class::Struct> Accessors

=over 4

=back

=cut

##############################################################################
### Local Functions 
##############################################################################

=head2 Local Functions

=over 4

=back

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map

=cut

sub field_map { 
    'id'          => 'Request ID',
    'create_time' => 'Create Date',
    'inc_ref'     => "Original Request ID",
    'user'        => "User",
    'fields'      => "Fields Changed",
    'data'        => "Log",
}

=item limit (ARGS)

Takes the following arguments:

=over 4

=item IncRef I<incref>

If set, then we will just search based on the Incident Number.

=back

Defaults to B<limit_basic ()>.

=cut

sub limit {
    my ($self, %args) = @_;
    my $parent = $self->parent_or_die (%args);

    my %hash = $self->schema (%args);
    # foreach (sort {$a<=>$b} %hash) { warn "  $_: $hash{$_}\n" }
    
    if (my $incnum = $args{'EID'}) { 
        my $id = $self->field_to_id ("Original Request ID", 'db' => $parent);
        return "'$id' == \"$incnum\"";
    }

    return $self->limit_basic (%args);
}

=item print_text ()

Returns a short list of the salient points of the audit entry - the
submitter, the submission date, the short description, and the actual text of
the worklog.

=cut

sub print_text {
    my ($self, %args) = @_;

    my @fields = split (';', $self->fields);
    my @parse  = grep { $_ } @fields;

    my @return = $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Time'   => $self->format_date ($self->create_time),
        'Person' => $self->user,
        'Changed Fields' => join ('; ', @parse),
    );

    return wantarray ? @return : join ("\n", @return, '');
}

sub print_text_old {
    my ($self, %args) = @_;

    my @return = $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Submitter'   => $self->submitter,
        'Date'        => $self->format_date (self->date_submit),
        'Description' => $self->description,
        'Attachments' => $self->attachments || 0);

    push @return, '', $self->format_text ({'prefix' => '  '},
        $self->details || "No text provided");

    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'HPD:HelpDesk_AuditLogSystem' }

=back

=cut

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
