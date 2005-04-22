package CAM::PDF::Renderer::Dump;

=head1 NAME

CAM::PDF::Renderer::Dump - Print the graphic state of each node

=head1 LICENSE

See CAM::PDF.

=head1 SYNOPSIS

    use CAM::PDF;
    my $pdf = CAM::PDF->new($filename);
    my $contentTree = $pdf->getPageContentTree(4);
    $contentTree->render("CAM::PDF::Renderer::Dump");

=head1 DESCRIPTION

This class is used to print to STDOUT the coordinates of each node of
a page layout.  It is written both for debugging and as a minimal
example of a renderer.

=cut

#----------------

use strict;
use warnings;
use CAM::PDF::GS;

use vars qw(@ISA);
@ISA = qw(CAM::PDF::GS);

#----------------

=head1 FUNCTIONS

=over 4

=item renderText STRING

Prints the string prefixed by its device and user coordinates.

=cut

sub renderText
{
   my $self = shift;
   my $string = shift;

   my ($xu, $yu) = $self->textToUser(0, 0);
   my ($xd, $yd) = $self->userToDevice($xu, $yu);

   printf "(%7.2f,%7.2f) (%7.2f,%7.2f) %s\n", $xd,$yd,$xu,$yu, $string;

   #my ($dxd, $dyd) = $self->textToDevice(@{$self->{moved}});
   #printf "(%7.2f,%7.2f) -> (%7.2f,%7.2f) %s\n", $xd,$yd,$dxd,$dyd, $string;
}

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
