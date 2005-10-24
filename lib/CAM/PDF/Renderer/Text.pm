package CAM::PDF::Renderer::Text;

use 5.006;
use warnings;
use strict;
use base qw(CAM::PDF::GS);

our $VERSION = '1.03';

=head1 NAME

CAM::PDF::Renderer::Text - Render an ASCII image of a PDF page

=head1 LICENSE

See CAM::PDF.

=head1 SYNOPSIS

    use CAM::PDF;
    my $pdf = CAM::PDF->new($filename);
    my $contentTree = $pdf->getPageContentTree(4);
    $contentTree->render("CAM::PDF::Renderer::Text");

=head1 DESCRIPTION

This class is used to print to STDOUT the coordinates of each node of
a page layout.  It is written both for debugging and as a minimal
example of a renderer.

=head1 GLOBALS

The $CAM::PDF::Renderer::Text::xdensity and
$CAM::PDF::Renderer::Text::ydensity define the scale of the ASCII
graphical output device.  They both default to 6.0.

=cut

our $xdensity = 6.0;
our $ydensity = 6.0;

=head1 FUNCTIONS

=over

=item new

Calls the superclass constructor, and initializes the ASCII PDF page.

=cut

sub new
{
   my $pkg = shift;

   my $self = $pkg->SUPER::new(@_);
   if ($self)
   {
      my $fw = ($self->{refs}->{mediabox}->[2] - $self->{refs}->{mediabox}->[0]) / $xdensity;
      my $fh = ($self->{refs}->{mediabox}->[3] - $self->{refs}->{mediabox}->[1]) / $ydensity;
      my $w = int $fw;
      my $h = int $fh;
      $self->{refs}->{framebuffer} = CAM::PDF::Renderer::Text::FB->new($w, $h);
      $self->{mode} = 'c';
   }
   return $self;
}

=item renderText STRING

Prints the characters of the screen to our virtual ASCII framebuffer.

=cut

sub renderText
{
   my $self = shift;
   my $string = shift;

   my ($x, $y) = $self->textToDevice(0,0);
   $x = int $x / $xdensity;
   $y = int $y / $ydensity;

   $self->{refs}->{framebuffer}->set($x, $y, $string);
   #print "($x,$y) $string\n";
}
#----------------

package CAM::PDF::Renderer::Text::FB;

=back

=head1 CAM::PDF::Renderer::Text::FB

This is the FrameBuffer class

=over

=item new WIDTH, HEIGHT

Creates a new framebuffer.

=cut

sub new
{
   my $pkg = shift;
   my $w = shift;
   my $h = shift;

   my $self = bless {
      w => $w,
      h => $h,
      fb =>[],
   }, $pkg;
   for my $r (0 .. $h-1)
   {
      $self->{fb}->[$r] = [(q{})x$w];
   }
   return $self;
}

=item set X, Y, STRING

Renders a string on the framebuffer.

=cut

sub set
{
   my $self = shift;
   my $x = shift;
   my $y = shift;
   my $string = shift;
   
   CAM::PDF->asciify(\$string);

   my $fb = $self->{fb};
   if (defined $fb->[$y])
   {
      if (defined $fb->[$y]->[$x])
      {
         $fb->[$y]->[$x] .= $string;
         #$fb->[$y]->[$x] = $string;
      }
      else
      {
         #print "bad 1\n";
         $fb->[$y]->[$x] = $string;
      }
   }
   else
   {
      #print "bad 2\n";
      $fb->[$y] = [];
      $fb->[$y]->[$x] = $string;
   }
}

=item DESTROY

Prints the framebuffer to STDOUT just before it is destroyed.

=cut

sub DESTROY
{
   my $self = shift;

   my $fb = $self->{fb};
   for my $r (reverse 0 .. $#$fb)
   {
      my $row = $fb->[$r];
      if ($row)
      {
         #print "r $r c ".@$row."\n";
         #print '>';
         for my $c (0 .. $#$row)
         {
            my $str = $row->[$c];
            if (!defined $str || $str eq q{})
            {
               $str = q{ };
            }
            print $str;
         }
      }
      else
      {
         #print "r $r c 0\n";
         #print '>';
      }
      print "\n";
   }
}

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
