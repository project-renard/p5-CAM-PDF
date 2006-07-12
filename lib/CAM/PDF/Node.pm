package CAM::PDF::Node;

use 5.006;
use warnings;
use strict;

our $VERSION = '1.07';

=head1 NAME

CAM::PDF::Node - PDF element

=head1 LICENSE

Copyright 2006 Clotho Advanced Media, Inc., <cpan@clotho.com>

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=over

=item $pkg->new($type, $value)

=item $pkg->new($type, $value, $objnum)

=item $pkg->new($type, $value, $objnum, $gennum)

Create a new PDF element.

=cut

sub new
{
   my $pkg = shift;

   my $self = {
      type => shift,
      value => shift,
   };

   my $objnum = shift;
   my $gennum = shift;
   if (defined $objnum)
   {
      $self->{objnum} = $objnum;
   }
   if (defined $gennum)
   {
      $self->{gennum} = $gennum;
   }

   return bless $self, $pkg;
}

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>

Primary developer: Chris Dolan

=cut
