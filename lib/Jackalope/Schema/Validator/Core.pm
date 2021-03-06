package Jackalope::Schema::Validator::Core;
use Moose;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

use Jackalope::Util    ();
use Try::Tiny;
use Scalar::Util       ();
use List::AllUtils     ();
use Devel::PartialDump ();
use Data::Peek         ();

has 'formats' => (
    traits  => [ 'Hash' ],
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub {
        +{
            uri          => qr/.*/, # let anything through for now
            uri_template => qr/.*/, # same here, perhaps do more later on
            regex        => qr/.*/, # pretty much let anything pass
            # we are checking the string format of UUIDs
            uuid         => qr/[0-9A-Z]{8}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{12}/i,
            # we are checking against a hex digest here
            digest       => qr/[0-9a-z]{64}/,
        }
    },
    handles => {
        'is_valid_format'     => 'exists',
        'get_format_verifier' => 'get'
    }
);

sub any  { +{ pass => 1 } }
sub null {
    my (undef, undef, $data) = @_;
    (!defined $data)
        ? +{ pass => 1 }
        : +{ error => $data . ' is not null' }
}

sub boolean {
    my (undef, $schema, $data) = @_;
    Jackalope::Util::is_bool( $data )
        ? +{ pass => 1 }
        : +{ error => (defined $data ? $data : 'undef') . ' is not a boolean type' };
}

sub number {
    my (undef, $schema, $data) = @_;
    return {
        error => 'doesnt look like a number'
    } unless Scalar::Util::looks_like_number $data;

    return {
        error => 'numeric data is a reference'
    } if ref $data;

    if (exists $schema->{less_than}) {
        return {
            error => $data . ' is not less than ' . $schema->{less_than}
        } if $data >= $schema->{less_than};
    }
    if (exists $schema->{less_than_or_equal_to}) {
        return {
            error => $data . ' is not less than or equal to ' . $schema->{less_than_or_equal_to}
        } if $data > $schema->{less_than_or_equal_to};
    }
    if (exists $schema->{greater_than}) {
        return {
            error => $data . ' is not greater than ' . $schema->{greater_than}
        } if $data <= $schema->{greater_than};
    }
    if (exists $schema->{greater_than_or_equal_to}) {
        return {
            error => $data . ' is not greater than or equal to ' . $schema->{greater_than_or_equal_to}
        } if $data < $schema->{greater_than_or_equal_to};
    }
    if (exists $schema->{enum}) {
        return {
            error => $data . ' is not part of (number) enum (' . (join ', ' => @{ $schema->{enum} } ) . ')'
        } unless List::AllUtils::any { $data == $_ } @{ $schema->{enum} };
    }
    return +{ pass => 1 };
}

sub integer {
    my ($self, $schema, $data) = @_;
    return {
        error => (defined $data ? $data : 'undef') . ' is perhaps a floating point number'
    } unless defined $data && $data =~ /^-?[0-9]+$/;
    return $self->number( $schema, $data );
}

sub string {
    my ($self, $schema, $data) = @_;
    return {
        error => 'string data is not defined'
    } unless defined $data;

    return {
        error => 'string data is a reference'
    } if ref $data;

    my ($is_string) = Data::Peek::DDual( $data );
    return {
        error => 'string look more like a number'
    } unless defined $is_string;

    if (exists $schema->{literal}) {
        return {
            error => $data . ' must exactly match ' . $schema->{literal}
        } if $data ne $schema->{literal};
    }
    if (exists $schema->{min_length}) {
        return {
            error => $data . ' is not the minimum length of ' . $schema->{min_length}
        } if (length $data) <= ($schema->{min_length} - 1);
    }
    if (exists $schema->{max_length}) {
        return {
            error => $data . ' is more then the maximum length of ' . $schema->{max_length}
        } if (length $data) >= ($schema->{max_length} + 1);
    }
    if (exists $schema->{pattern}) {
        return {
            error => $data . ' does not match the pattern (' . $schema->{pattern} . ')'
        } if $data !~ /$schema->{pattern}/;
    }
    if (exists $schema->{format}) {
        return {
            error => $schema->{format} . ' is not one of the built-in formats ' . (Devel::PartialDump::dump $self->formats)
        } unless $self->is_valid_format( $schema->{format} );

        my $formatter = $self->get_format_verifier( $schema->{format} );
        return {
            error => $data . ' does not match the format (' . $schema->{format} . ')'
        } if $data !~ /$formatter/;
    }
    if (exists $schema->{enum}) {
        return {
            error => $data . ' is not part of (string) enum (' . (join ', ' => @{ $schema->{enum} } ) . ')'
        } unless List::AllUtils::any { $data eq $_ } @{ $schema->{enum} };
    }
    return +{ pass => 1 };
}

sub array {
    my ($self, $schema, $data) = @_;
    return {
        error => (Devel::PartialDump::dump $data) . ' is not an array'
    } unless ref $data eq 'ARRAY';

    if (exists $schema->{min_items}) {
        return {
            error => (Devel::PartialDump::dump $data) . ' does not meet the minimum items ' . $schema->{min_items} . ' with ' . (scalar @$data)
        } if (scalar @$data) <= ($schema->{min_items} - 1);
    }

    if (exists $schema->{max_items}) {
        return {
            error => (Devel::PartialDump::dump $data) . ' does not meet the maximum items ' . $schema->{max_items} . ' with ' . (scalar @$data)
        } if (scalar @$data) >= ($schema->{max_items} + 1);
    }

    return +{ pass => 1 } if (scalar @$data) == 0; # no need to carry on if it is empty

    if (exists $schema->{is_unique} && $schema->{is_unique}) {
        return  {
            error => (Devel::PartialDump::dump $data) . ' is not unique'
        } if (scalar @$data) != (scalar List::AllUtils::uniq @$data);
    }

    if (exists $schema->{items}) {
        my $item_schema = $schema->{items};
        my $validator   = $self->can( $item_schema->{type} );
        return {
            error => "could not find validator for '" . $item_schema->{type} . "' for array items"
        } if not defined $validator;
        my @results     = map { $self->$validator( $item_schema, $_ ) } @$data;
        my @errors      = grep { exists $_->{error} } @results;
        return {
            error      => (Devel::PartialDump::dump $data) . ' did not pass the test for ' . $item_schema->{type} . ' schemas',
            sub_errors => \@errors
        } if @errors;
    }
    return +{ pass => 1 };
}

sub object {
    my ($self, $schema, $data) = @_;
    return {
        error => (Devel::PartialDump::dump $data) . ' is not an object'
    } unless ref $data eq 'HASH';

    my %all_props = map { $_ => undef } keys %$data;

    my $has_properties = exists $schema->{properties} && scalar keys %{ $schema->{properties} };
    my $has_additional_properties = exists $schema->{additional_properties}
                                  && scalar keys %{ $schema->{additional_properties} };

    if ($has_properties) {
        my $result = $self->_check_properties(
            $schema->{properties}, $data, \%all_props
        );
        return {
            error      => (Devel::PartialDump::dump $data) . " did not pass properties check",
            sub_errors => $result
        } if exists $result->{error};
    }

    if ($has_additional_properties) {
        my $result = $self->_check_additional_properties(
            $schema->{additional_properties}, $data, \%all_props
        );
        return {
            error      => (Devel::PartialDump::dump $data) . " did not pass additional properties check",
            sub_errors => $result
        } if exists $result->{error};
    }

    if ($has_properties || $has_additional_properties) {
        return {
            error           => (Devel::PartialDump::dump $data) . ' did not match all the expected properties',
            remaining_props => \%all_props,
            schema          => $schema,
        } if (scalar keys %all_props) != 0;
    }

    if (exists $schema->{items}) {
        my $item_schema = $schema->{items};
        my $validator   = $self->can( $item_schema->{type} );
        return {
            error => "could not find validator for '" . $item_schema->{type} . "' for object items"
        } if not defined $validator;
        my @results     = map { $self->$validator( $item_schema, $_ )  } values %$data;
        my @errors      = grep { exists $_->{error} } @results;
        return {
            error      => (Devel::PartialDump::dump $data) . ' did not pass the test for ' . $item_schema->{type} . ' schemas',
            sub_errors => \@errors
        } if @errors;
    }
    return +{ pass => 1 };
}

sub schema { (shift)->object( @_ ) }

# ...

sub _check_properties {
    my ($self, $props, $data, $all_props) = @_;
    foreach my $k (keys %$props) {

        my $schema = $props->{ $k };

        if($schema->{optional}) {
            next if not exists $data->{ $k };
        } else {
            if($schema->{default}) {
                $data->{ $k } = $schema->{default} if not exists $data->{ $k };
            } else {
                return { error => "property '$k' didn't exist" } if not exists $data->{ $k };
            }
        }

        return {
            error => "could not find validator for property '$k' because it has no type"
        } if not exists $schema->{type};

        my $validator = $self->can( $schema->{type} );
        return {
            error => "could not find validator for '" . $schema->{type} . "' for property '$k'"
        } if not defined $validator;

        my $result    = $self->$validator( $schema, $data->{ $k } );
        return {
            error      => "property '$k' didn't pass the schema for '" . $schema->{type} . "'",
            sub_errors => $result
        } if exists $result->{error};

        delete $all_props->{ $k };
    }
    return +{ pass => 1 };
}

sub _check_additional_properties {
    my ($self, $props, $data, $all_props) = @_;
    foreach my $k (keys %$props) {

        my $schema = $props->{ $k };

        if (not exists $data->{ $k }) {
            delete $all_props->{ $k };
            next;
        }

        return {
            error => "could not find validator for additonal-property '$k' because it has no type"
        } if not exists $schema->{type};

        my $validator = $self->can( $schema->{type} );
        return {
            error => "could not find validator for '" . $schema->{type} . "' for additional-property '$k'"
        } if not defined $validator;

        my $result    = $self->$validator( $schema, $data->{ $k } );
        return {
            error      => "additional-property '$k' didn't pass the schema for '" . $schema->{type} . "'",
            sub_errors => $result
        } if exists $result->{error};

        delete $all_props->{ $k };
    }
    return +{ pass => 1 };
}

__PACKAGE__->meta->make_immutable;

no Moose; 1;

__END__

=pod

=head1 NAME

Jackalope::Schema::Validator::Core - A Moosey solution to this problem

=head1 SYNOPSIS

  use Jackalope::Schema::Validator::Core;

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item B<>

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 AUTHOR

Stevan Little E<lt>stevan.little@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2010 Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
