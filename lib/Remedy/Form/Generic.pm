package Remedy::Form::Generic;
our $VERSION = "0.10";
# Copyright and license are in the documentation below.

=head1 NAME

Remedy::Form::Generic - generic remedy forms

=head1 SYNOPSIS

    use Remedy::Form::Generic;

    # $remedy is a Remedy object
    foreach my $obj ($remedy->read ('TABLENAME', 'option1' => 'value1',
        'option2' => 'value2', 'option3' => 'value3' )) {
        print scalar $obj->print_text;
    }

=head1 DESCRIPTION

Remedy::Form::Generic is used to look at forms in a "generic" manner, where all
we know is the name of the form (e.g. I<CTM:People>).

Remedy::Form::Generic is both a special sub-class of, and a helper class to,
B<Remedy::Form>.

=cut

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Remedy::Form;

our @ISA = init_struct (__PACKAGE__);

##############################################################################
### Class::Struct Functions ##################################################
##############################################################################

=head1 FUNCTIONS

=head2 B<Class::Struct> Accessors

=over 4

=item table (I<Table Name>)

Unlike all other tables, the generic table can set the associated table name.

=back

=cut

##############################################################################
### Remedy::Form Overrides ###################################################
##############################################################################

=head2 B<Remedy::Form> Overrides

=over 4

=item init_struct ()

Like B<Remedy::Form::init_struct ()>, except that we don't actually register
any class names; there are no 'extras' or named accessors; and the returned
base class is 'Remedy::Form'.

=cut

sub init_struct {
    my ($class, %extra) = @_;
    our $new = $class . "::Struct";

    struct $new => {'entry'  => 'Remedy::FormData::Entry',
                    'parent' => 'Remedy',
                    'table'  => '$',
                    'key_field' => '%'};

    return ('Remedy::Form', $new);
}

=item field_map ()

Empty.

=cut

sub field_map { }

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Remedy::Form>

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
