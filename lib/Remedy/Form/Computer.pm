package Remedy::Form::Computer;
our $VERSION = "0.12";
our $ID = q$Id: Remedy.pm 4743 2008-09-23 16:55:19Z tskirvin$;
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Computer - per-ticket worklogs

=head1 SYNOPSIS

    use Remedy::Worklog;

    # $remedy is a Remedy object
    my @worklog = Remedy::ComputerSystem->select (
        'db' => $remedy, 'IncNum' => 'INC000000002371');
    for my $wl (@worklog) { print scalar $wl->print_text }

=head1 DESCRIPTION

Remedy::ComputerSystem tracks individual work log entries for tickets as part
of the remedy database.  It is a sub-class of B<Remedy::Form>, so most of its
functions are described there.

=cut

##############################################################################
### Declarations
##############################################################################

use strict;
use warnings;

use Remedy::Form qw/init_struct/;

our @ISA = init_struct (__PACKAGE__);

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

Incident number of the original ticket.  Correspons to field 'Incident Number'.

=item map (%)

[...]

=item parent ($)

[...]

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

=back

=head2 B<Remedy::Form Overrides>

=over 4

=item field_map

=cut

sub field_map { 
    'id'                    =>          1,
    'serial'                => 2000000001,
}

=item limit (ARGS)

Takes the following arguments:

=over 4

=item IncRef I<incref>

If set, then we will just search based on the Incident Number.

=back

Defaults to B<limit_basic ()>.

=cut

sub limit_extra {
    my ($self, %args) = @_;

    if (my $incnum = $args{'IncNum'}) { 
        my $id = $self->field_to_id ("Incident Number");
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
        'Date'        => $self->format_date ($self->date_submit),
        'Description' => $self->description,
        'Attachments' => $self->attachments || 0);

    push @return, '', $self->format_text ({'prefix' => '  '},
        $self->details || "No text provided");

    return wantarray ? @return : join ("\n", @return, '');
}

=item table ()

=cut

sub table { 'BMC.CORE:BMC_ComputerSystem' }

=item schema ()

=cut

sub schema {
    return (
#          112 => "CMDB Row Level Security",     # must be '1000000000'
#    200000001 => "Serial Number",
#    200000003 => "Category",
#    200000004 => "Type",
#    200000005 => "Item",
#    200000020 => "Name",
#    200000022 => "Physical Memory",
#    240000007 => "Description",
#    240001002 => "Model",
#    240001003 => "Manufacturer",
#    301002900 => "Owner Name",
#    301016000 => "Hostname",
#    301016200 => "Primary Type",                # integer, 1-31
#    400079600 => "ClassID",                     # must be 'BMC_COMPUTERSYSTEM'
#    400127400 => "Dataset ID",
#    490021100 => "UserDisplayObjectName",       # must be 'Computer System'
    );
}

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

Copyright 2008 Board of Trustees, Leland Stanford Jr. University

This program is free software; you may redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
