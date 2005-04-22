package CAM::PDF::Renderer::Text;

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

=cut

#----------------

use strict;
use warnings;
use CAM::PDF::GS;

use vars qw(@ISA $xdensity $ydensity);
@ISA = qw(CAM::PDF::GS);

#----------------

=head1 GLOBALS

The $CAM::PDF::Renderer::Text::xdensity and
$CAM::PDF::Renderer::Text::ydensity define the scale of the ASCII
graphical output device.  They both default to 6.0.

=cut

$xdensity = $ydensity = 6.0;

#----------------

=head1 FUNCTIONS

=over 4

=item new

Calls the superclass constructor, and initializes the ASCII PDF page.

=cut

sub new
{
   my $pkg = shift;

   my $self = $pkg->SUPER::new(@_);
   if ($self)
   {
      my $w = int(($self->{refs}->{mediabox}->[2] -
                   $self->{refs}->{mediabox}->[0]) / $xdensity);
      my $h = int(($self->{refs}->{mediabox}->[3] -
                   $self->{refs}->{mediabox}->[1]) / $ydensity);
      $self->{refs}->{framebuffer} = CAM::PDF::Renderer::Text::FB->new($w, $h);
      $self->{mode} = "c";
   }
   return $self;
}
#----------------

=item renderText STRING

Prints the characters of the screen to our virtual ASCII framebuffer.

=cut

sub renderText
{
   my $self = shift;
   my $string = shift;

   my ($x, $y) = $self->textToDevice(0,0);
   $x = int($x / $xdensity);
   $y = int($y / $ydensity);

   $self->{refs}->{framebuffer}->set($x, $y, $string);
   #print "($x,$y) $string\n";
}
#----------------

package CAM::PDF::Renderer::Text::FB;

#----------------

=back

=head1 CAM::PDF::Renderer::Text::FB

This is the FrameBuffer class

=over 4

=cut

#----------------

=item new WIDTH, HEIGHT

Creates a new framebuffer.

=cut

sub new
{
   my $pkg = shift;
   my $w = shift;
   my $h = shift;

   my $self = bless({
      w => $w,
      h => $h,
      fb =>[],
   }, $pkg);
   for (my $r=0; $r<$h; $r++)
   {
      $self->{fb}->[$r] = [("")x$w];
   }
   return $self;
}
#----------------

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
#----------------

=item DESTROY

Prints the framebuffer to STDOUT just before it is destroyed.

=cut

sub DESTROY
{
   my $self = shift;

   my $fb = $self->{fb};
   for (my $r=$#$fb; $r >= 0; $r--)
   {
      my $row = $fb->[$r];
      if ($row)
      {
         #print "r $r c ".@$row."\n";
         #print ">";
         for (my $c=0; $c < @$row; $c++)
         {
            my $str = $row->[$c];
            $str = " " unless (defined $str && $str ne "");
            print $str;
         }
      }
      else
      {
         #print "r $r c 0\n";
         #print ">";
      }
      print "\n";
   }
}
#----------------

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
