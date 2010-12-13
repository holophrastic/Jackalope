package Jackalope::REST::Service::Target::List;
use Moose;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:STEVAN';

with 'Jackalope::REST::Service::Target';

sub execute {
    my ($self, $r, @args) = @_;
    my ($resources, $error) = $self->process_operation( 'list_resources' => ( $r, @args ) );
    return $error if $error;
    return $self->process_psgi_output([ 200, [], [ $resources ] ]);
}

__PACKAGE__->meta->make_immutable;

no Moose; 1;

__END__

=pod

=head1 NAME

Jackalope::REST::Service::Target::List - A Moosey solution to this problem

=head1 SYNOPSIS

  use Jackalope::REST::Service::Target::List;

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
