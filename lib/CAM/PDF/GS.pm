package CAM::PDF::GS;

use 5.006;
use strict;
use warnings;
use base qw(CAM::PDF::GS::NoText);

our $VERSION = '1.03';

=head1 NAME

CAM::PDF::GS - PDF graphic state

=head1 LICENSE

See CAM::PDF.

=head1 SYNOPSIS

    use CAM::PDF;
    my $pdf = CAM::PDF->new($filename);
    my $contentTree = $pdf->getPageContentTree(4);
    my $gs = $contentTree->computeGS();

=head1 DESCRIPTION

This class is used to represent the graphic state at a point in the
rendering flow of a PDF page.  Much of the functionality is actually
based in the parent class, CAM::PDF::GS::NoText.

Subclasses that want to do something useful with text should override
the renderText() method.

=head1 CONVERSION FUNCTIONS

=over

=item getCoords NODE

Computes device coords for the specified node.  This implementation
handles text-printing nodes, and hands all other types to the
superclass.

=cut

sub getCoords
{
   my $self = shift;
   my $node = shift;

   if ($node->{name} =~ /^(TJ|Tj|quote|doublequote)$/)
   {
      my ($x1,$y1) = $self->userToDevice(@{$self->{last}});
      my ($x2,$y2) = $self->userToDevice(@{$self->{current}});
      return ($x1,$y1,$x2,$y2);
   }
   else
   {
      return $self->SUPER::getCoords($node);
   }
}

=item textToUser X, Y

Convert text coordinates (Tm) to user coordinates.  Returns the
converted X and Y.

=cut

sub textToUser
{
   my $self = shift;
   my $x = shift;
   my $y = shift;

   return $self->dot($self->{Tm}, $x, $y);

   ## PDF Ref page 313
   #my $tf = [$self->{Tfs}*$self->{Tz}, 0,
   #          0,                        $self->{Tfs},
   #          0,                        $self->{Ts}];
   #return $self->dot($self->{Tm}, $self->dot($tf, $x, $y));
}

=item textToDevice X, Y

Convert text coordinates (Tm) to device coordinates.  Returns
the converted X and Y.

=cut

sub textToDevice
{
   my $self = shift;
   my $x = shift;
   my $y = shift;

   return $self->userToDevice($self->textToUser($x, $y));
}

=item textLineToUser X, Y

Convert text coordinates (Tlm) to user coordinates.  Returns
the converted X and Y.

=cut

sub textLineToUser
{
   my $self = shift;
   my $x = shift;
   my $y = shift;

   return $self->dot($self->{Tlm}, $x, $y);
}

=item textLineToDevice X, Y

Convert text coordinates (Tlm) to device coordinates.
Returns the converted X and Y.

=cut

sub textLineToDevice
{
   my $self = shift;
   my $x = shift;
   my $y = shift;

   return $self->userToDevice($self->textLineToUser($x, $y));
}

=item renderText STRING, WIDTH

A general method for rendering strings, from Tj or TJ.  This is a
no-op, but subclasses may override.

=cut

sub renderText
{
   my $self = shift;
   my $string = shift;
   my $width = shift;

   # noop, override in subclasses
}

=item Tadvance WIDTH

Move the text cursor.

=cut

sub Tadvance
{
   my $self = shift;
   my $width = shift;

   my $tx = 0;
   my $ty = 0;
   if ($self->{wm} == 0)
   {
      $tx = ($width * $self->{Tfs} + $self->{Tc} + $self->{Tw}) * $self->{Tz};
   }
   else
   {
      $ty = $width * $self->{Tfs} + $self->{Tc} + $self->{Tw};
   }
   $self->{moved}->[0] += $tx;
   $self->{moved}->[1] += $ty;

   $self->applyMatrix([1,0,0,1,$tx,$ty], $self->{Tm});
}

=back

=head1 DATA FUNCTIONS

=over

=item BT

=cut

sub BT
{
   my $self = shift;
  
   @{$self->{Tm}} = (1, 0, 0, 1, 0, 0);
   @{$self->{Tlm}} = (1, 0, 0, 1, 0, 0);
}

=item Tf FONTNAME, FONTSIZE

=cut

sub Tf
{
   my $self = shift;
   my $fontname = shift;
   my $fontsize = shift;

   $self->{Tf} = $fontname;
   $self->{Tfs} = $fontsize;
   $self->{refs}->{fm} = $self->{refs}->{doc}->getFontMetrics($self->{refs}->{properties}, $fontname);

   # TODO: support vertical text mode (wm = 1)
   $self->{wm} = 0;
}

=item Tstar

=cut

sub Tstar
{
   my $self = shift;

   $self->Td(0, -$self->{TL});
}

=item Tz SCALE

=cut

sub Tz
{
   my $self = shift;
   my $scale = shift;

   $self->{Tz} = $scale/100.0;
}

=item Td X, Y

=cut

sub Td
{
   my $self = shift;
   my $x = shift;
   my $y = shift;
   
   $self->applyMatrix([1,0,0,1,$x,$y], $self->{Tlm});
   @{$self->{Tm}} = @{$self->{Tlm}};
}

=item TD X, Y

=cut

sub TD
{
   my $self = shift;
   my $x = shift;
   my $y = shift;

   $self->TL(-$y);
   $self->Td($x,$y);
}

=item Tj STRING

=cut

sub Tj
{
   my $self = shift;
   my $string = shift;

   @{$self->{last}} = $self->textToUser(0,0);
   $self->_Tj($string);
   @{$self->{current}} = $self->textToUser(0,0);
}

sub _Tj
{
   my $self = shift;
   my $string = shift;

   if (!$self->{refs}->{fm})
   {
      die "No font metrics for font $self->{Tf}";
   }

   my @parts;
   if ($self->{mode} eq 'c' || $self->{wm} == 1)
   {
      @parts = split //, $string;
   }
   else
   {
      @parts = ($string);
   }
   foreach my $substr (@parts)
   {
      my $dw = $self->{refs}->{doc}->getStringWidth($self->{refs}->{fm}, $substr);
      $self->renderText($substr, $dw);
      $self->Tadvance($dw);
   }
}

=item TJ ARRAYREF

=cut

sub TJ
{
   my $self = shift;
   my $array = shift;

   @{$self->{last}} = $self->textToUser(0,0);
   foreach my $node (@$array)
   {
      if ($node->{type} eq 'number')
      {
         my $dw = -$node->{value} / 1000.0;
         $self->Tadvance($dw);
      }
      else
      {
         $self->_Tj($node->{value});
      }
   }
   @{$self->{current}} = $self->textToUser(0,0);
}

=item quote

=cut

sub quote
{
   my $self = shift;
   my $string = shift;

   @{$self->{last}} = $self->textToUser(0,0);
   $self->Tstar();
   $self->_Tj($string);
   @{$self->{current}} = $self->textToUser(0,0);
}

=item doublequote

=cut

sub doublequote
{
   my $self = shift;
   $self->{Tw} = shift;
   $self->{Tc} = shift;
   my $string = shift;

   $self->quote($string);
}

=item Tm M1, M2, M3, M4, M5, M6

=cut

sub Tm
{
   my $self = shift;
   
   @{$self->{Tm}} = @{$self->{Tlm}} = @_;
}

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
