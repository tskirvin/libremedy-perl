package Remedy::WorkLog;
our $VERSION = "0.12";
our $ID = q$Id: Remedy.pm 4743 2008-09-23 16:55:19Z tskirvin$;
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Worklog - per-ticket worklogs

=head1 SYNOPSIS

    use Remedy::Worklog;

    # $remedy is a Remedy object
    my @worklog = Remedy::WorkLog->select (
        'db' => $remedy, 'IncNum' => 'INC000000002371');
    for my $wl (@worklog) { print scalar $wl->print_text }

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

our @ISA = (Remedy::Form::init_struct (__PACKAGE__),
    'Remedy::Form');

##############################################################################
### Class::Struct
##############################################################################

=head1 FUNCTIONS

These 

=head2 B<Class::Struct> Accessors

=over 4

=item attach1, attach2, attach3, attach4, attach5 ($)

These list the five possible attachments per-worklog-entry.  Not yet well
supported.  These correspond to fields 'z2AF Work Log01' to 'zaAF Work Log 05'.

=item date_submit ($)

The date that the worklog was created.  Corresponds to field 

=item description ($)

=item details ($)

=item id ($)

=item inc_num ($)

Incident number of the original ticket.  Corresponds to field 'Incident Number'.

=item map (%)

A 

=item parent ($)

=item submitter ($)

Address of the person who created this worklog entry.  Corresponds to field
'Work Log Submitter'.

=back

=cut

##############################################################################
### Local Functions 
##############################################################################

=head2 Local Functions

=over 4

=item attachments 

Lists the names of the attachments connected with this worklog, separated with
semicolons, or 'none' if there are none.

=cut

sub attachments {
    my ($self) = @_;
    my @list;
    for my $i (qw(1 2 3 4 5)) {
        my $func = "attach$i";
        my $attach = $self->$func;
        if ($attach && ref $attach) { 
            push @list, $$attach{'name'};
        }
            
    }
    return scalar @list ? join ("; ", @list) : "none";
}

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map

=cut

sub field_map { 
    'id'                    => 'Work Log ID',
    'description'           => 'Description',
    'details'               => 'Detailed Description',
    'date_submit'           => 'Work Log Submit Date',
    'submitter'             => 'Work Log Submitter',
    'inc_num'               => 'Incident Number',
    'attach1'               => 'z2AF Work Log01',
    'attach2'               => 'z2AF Work Log02',
    'attach3'               => 'z2AF Work Log03',
    'attach4'               => 'z2AF Work Log04',
    'attach5'               => 'z2AF Work Log05',
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

    if (my $incnum = $args{'IncNum'}) { 
        my $id = $self->field_to_id ("Incident Number", %args);
        return "'$id' == \"$incnum\"";
    }

    return $self->limit_basic (%args);
}

=item print_text ()

Returns a short list of the salient points of the worklog entry - the
submitter, the submission date, the short description, and the actual text of
the worklog.

=cut

sub print_text {
    my ($self, %args) = @_;

    my @return = $self->format_text_field (
        {'minwidth' => 20, 'prefix' => '  '}, 
        'Submitter'   => $self->submitter,
        'Date'        => $self->format_date ({}, $self->date_submit),
        'Description' => $self->description,
        'Attachments' => $self->attachments || 0);

    push @return, '', $self->format_text ({'prefix' => '  '},
        $self->details || "No text provided");

    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'HPD:WorkLog' }

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
