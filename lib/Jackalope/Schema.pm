package Jackalope::Schema;
use Moose;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

use Jackalope::Schema::Validators;
use Data::Visitor::Callback;

has 'original_schemas' => (
    init_arg => 'schemas',
    is       => 'ro',
    isa      => 'ArrayRef[HashRef]',
    required => 1
);

has 'compiled_schemas' => (
    is      => 'ro',
    isa     => 'HashRef[HashRef]',
    lazy    => 1,
    builder => '_compile_schemas'
);

has 'validators' => (
    is      => 'ro',
    isa     => 'Jackalope::Schema::Validators',
    lazy    => 1,
    default => sub { Jackalope::Schema::Validators->new },
);

# compile all the schemas ...
sub BUILD { (shift)->compiled_schemas }

sub validate {
    my ($self, $schema, $data) = @_;

    unless (exists $schema->{__compiled_properties} && exists $schema->{__compiled_additional_properties}) {
        $schema = $self->_flatten_extends( $schema, $self->compiled_schemas );
        $schema = $self->_resolve_refs( $schema, $self->compiled_schemas );
    }

    my $schema_type = $schema->{type};

    my $result = $self->validators->validate_schema(
        $self->compiled_schemas->{'schema/types/' . $schema_type},
        $schema
    );

    if ($result->{error}) {
        require Data::Dumper;
        die Data::Dumper::Dumper [
            "Invalid schema",
            $result,
            $schema,
            $self->compiled_schemas->{'schema/types/' . $schema_type}
        ];
    }

    my $validator = $self->validators->get_validator_for_type( $schema_type );
    return $self->validators->$validator(
        $schema,
        $data
    );
}

# ...

sub _compile_schemas {
    my $self = shift;

    my @schemas = @{ $self->original_schemas };

    # - first we should build the basic schema map
    #   so that we can resolve uris, but this will
    #   not be what is actually stored, we have to
    #   build that at the end

    my %schema_map;
    foreach my $schema ( @schemas ) {
        $schema_map{ $schema->{id} } = $schema;
    }

    # - then we should flatten extends, but we should
    #   process the schemas individually and only
    #   process 'extends' that are 'refs' (which should
    #   perhaps be enforced in the spec??)

    my @flattened;
    foreach my $schema ( @schemas ) {
        push @flattened => $self->_flatten_extends( $schema, \%schema_map );
    }

    # - then we should resolve all the reminaing refs
    #   we need to be stricter about checking that it
    #   is indeed a ref and not the ref spec

    my @resolved;
    foreach my $schema ( @schemas ) {
        push @resolved => $self->_resolve_refs( $schema, \%schema_map );
    }

    return +{ map { $_->{id} => $_ } @resolved };
}

sub _flatten_extends {
    my ($self, $schema, $schema_map) = @_;
    return Data::Visitor::Callback->new(
        hash => sub {
            my ($v, $data) = @_;
            if ( exists $data->{'extends'} &&  $self->_is_ref( $data->{'extends'} ) ) {
                return $self->_compile_properties( $data, $schema_map );
            }
            return $data;
        }
    )->visit(
        $self->_compile_properties( $schema, $schema_map )
    );
}

sub _resolve_refs {
    my ($self, $schema, $schema_map) = @_;
    return Data::Visitor::Callback->new(
        hash => sub {
            my ($v, $data) = @_;
            if (exists $data->{'$ref'} && $self->_is_ref( $data )) {
                return $schema_map->{ $data->{'$ref'} }
            }
            return $data;
        }
    )->visit( $schema );
}

sub _is_ref {
    my ($self, $ref) = @_;
    return (exists $ref->{'$ref'} && ((scalar keys %$ref) == 1)) ? 1 : 0;
}

sub _compile_properties {
    my ($self, $schema, $schema_map) = @_;
    my ($compiled_properties, $compiled_additional_properties) = $self->_compile_extended_properties( $schema, $schema_map );
    $schema->{'__compiled_properties'}            = $compiled_properties;
    $schema->{'__compiled_additional_properties'} = $compiled_additional_properties;
    return $schema;
}

sub _compile_extended_properties {
    my ($self, $schema, $schema_map) = @_;
    return (
        $self->_merge_properties( properties            => $schema, $schema_map ),
        $self->_merge_properties( additional_properties => $schema, $schema_map )
    );
}

sub _merge_properties {
    my ($self, $type, $schema, $schema_map) = @_;
    return +{
        (exists $schema->{'extends'}
            ? %{ $self->_merge_properties( $type, $schema_map->{ $schema->{'extends'}->{'$ref'} }, $schema_map ) }
            : ()),
        %{ $schema->{ $type } || {} },
    }
}


__PACKAGE__->meta->make_immutable;

no Moose; 1;

__END__

=pod

=head1 NAME

Jackalope::Schema - A Moosey solution to this problem

=head1 SYNOPSIS

  use Jackalope::Schema;

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
