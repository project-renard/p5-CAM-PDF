package CAM::PDF::GS::NoText;

=head1 NAME

CAM::PDF::GS::NoText - PDF graphic state

=head1 LICENSE

See CAM::PDF.

=head1 SYNOPSIS

    use CAM::PDF;
    my $pdf = CAM::PDF->new($filename);
    my $contentTree = $pdf->getPageContentTree(4);
    my $gs = $contentTree->computeGS(1);

=head1 DESCRIPTION

This class is used to represent the graphic state at a point in the
rendering flow of a PDF page.  This does not include the graphics
state for text blocks.  That functionality is in the subclass,
CAM::PDF::GS.

=cut

#----------------

use strict;
use warnings;

use vars qw(@ISA);

#----------------

=head1 FUNCTIONS

=over 4

=cut

#----------------

=item new DATA

Create a new instance, setting all state values to their defaults.
Stores a reference to DATA and sets the DATA property C<fm =E<gt> undef>.

=cut

sub new
{
   my $pkg = shift;
   my $refs = shift;

   my $self = bless({

      mode => "n",            # "c"har, "s"tring, "n"oop

      refs => $refs || {},

      c => undef,                # color
      cm => [1, 0, 0, 1, 0, 0],  # current transformation matrix
      w => 1.0,                  # line width
      J => 0,                    # line cap
      j => 0,                    # line join
      M => 0,                    # miter limit
      da => [],                  # dash pattern array
      dp => 0,                   # dash phase
      ri => undef,               # rendering intent
      i => 0,                    # flatness

      # Others, see PDF Ref page 149

      Tm => [1, 0, 0, 1, 0, 0],  # text matrix
      Tlm => [1, 0, 0, 1, 0, 0], # text matrix
      Tc => 0,                   # character spacing
      Tw => 0,                   # word spacing
      Tz => 1,                   # horizontal scaling
      TL => 0,                   # leading
      Tf => undef,               # font
      Tfs => undef,              # font size
      Tr => 0,                   # render mode
      Ts => 0,                   # rise
      wm => 0,                   # writing mode (0=horiz, 1=vert)

      Device => undef,
      device => undef,
      G => undef,
      g => undef,
      RG => undef,
      rg => undef,
      K => undef,
      k => undef,

      moved => [0,0],

      start => [0,0],
      last => [0,0],
      current => [0,0],

   }, $pkg);

   $self->{refs}->{fm} = undef;

   return $self;
}
#----------------

=item clone

Duplicate the instance.

=cut

sub clone
{
   my $self = shift;

   require Data::Dumper;
   my $newself;

   # don't clone references, just point to them
   my $refs = delete $self->{refs};

   eval Data::Dumper->Dump([$self], ["newself"]);
   if ($@)
   {
      die "Error in ".__PACKAGE__."::clone() - $@";
   }
   $self->{refs} = $newself->{refs} = $refs;  # restore references
   @{$newself->{moved}} = (0,0);
   return $newself;
}
#----------------

=back

=head1 CONVERSION FUNCTIONS

=over 4

=cut

#----------------

=item applyMatrix M1, M2

Apply m1 to m2, save in m2

=cut

sub applyMatrix
{
   my $self = shift;
   my $m1 = shift;
   my $m2 = shift;

   unless (ref($m1) eq "ARRAY" && ref($m2) eq "ARRAY")
   {
      require Data::Dumper;
      die "Bad arrays:\n".Dumper($m1,$m2);
   }

   my @m3;

   #$m3[0] = $m1->[0]*$m2->[0] + $m1->[2]*$m2->[1];
   #$m3[1] = $m1->[1]*$m2->[0] + $m1->[3]*$m2->[1];
   #$m3[2] = $m1->[0]*$m2->[2] + $m1->[2]*$m2->[3];
   #$m3[3] = $m1->[1]*$m2->[2] + $m1->[3]*$m2->[3];
   #$m3[4] = $m1->[0]*$m2->[4] + $m1->[2]*$m2->[5] + $m1->[4];
   #$m3[5] = $m1->[1]*$m2->[4] + $m1->[3]*$m2->[5] + $m1->[5];

   $m3[0] = $m2->[0]*$m1->[0] + $m2->[2]*$m1->[1];
   $m3[1] = $m2->[1]*$m1->[0] + $m2->[3]*$m1->[1];
   $m3[2] = $m2->[0]*$m1->[2] + $m2->[2]*$m1->[3];
   $m3[3] = $m2->[1]*$m1->[2] + $m2->[3]*$m1->[3];
   $m3[4] = $m2->[0]*$m1->[4] + $m2->[2]*$m1->[5] + $m2->[4];
   $m3[5] = $m2->[1]*$m1->[4] + $m2->[3]*$m1->[5] + $m2->[5];

   @$m2 = @m3;
}
#----------------

=item dot MATRIX, X, Y

Compute the dot product of a position against the coordinate matrix.

=cut

sub dot
{
   my $self = shift;
   my $cm = shift;
   my $x = shift;
   my $y = shift;

   return ($cm->[0]*$x + $cm->[2]*$y + $cm->[4],
           $cm->[1]*$x + $cm->[3]*$y + $cm->[5]);
}
#----------------

=item userToDevice X, Y

Convert user coordinates to device coordinates.

=cut

sub userToDevice
{
   my $self = shift;
   my $x = shift;
   my $y = shift;

   ($x,$y) = $self->dot($self->{cm}, $x, $y);
   $x -= $self->{refs}->{mediabox}->[0];
   $y -= $self->{refs}->{mediabox}->[1];
   return ($x, $y);
}
#----------------

sub getCoords
{
   my $self = shift;
   my $node = shift;

   my ($x1,$y1,$x2,$y2);
   if ($node->{name} =~ /^(m|l|h|c|v|y|re)$/)
   {
      ($x1,$y1) = $self->userToDevice(@{$self->{last}});
      ($x2,$y2) = $self->userToDevice(@{$self->{current}});
   }
   return ($x1,$y1,$x2,$y2);
}

sub nodeType
{
   my $self = shift;
   my $node = shift;

   if ($node->{type} eq "block")
   {
      return "block";
   }
   elsif ($node->{name} =~ /^(m|l|h|c|v|y|re)$/)
   {
      return "path";
   }
   elsif ($node->{name} =~ /^(S|s|F|f|f\*|B|B\*|b|b\*|n)$/)
   {
      return "paint";
   }
   elsif ($node->{name} =~ /^T/)
   {
      return "text";
   }
   else
   {
      return "op";
   }
}

#----------------

=back

=head1 DATA FUNCTIONS

=over 4

=cut

#----------------

=item i FLATNESS

=item j LINEJOIN

=item J LINECAP

=item ri RENDERING_INTENT

=item Tc CHARSPACE

=item TL LEADING

=item Tr RENDERING_MODE

=item Ts RISE

=item Tw WORDSPACE

=item w LINEWIDTH

=cut

# default setters
{
   my $code = "";
   foreach my $key (qw(i j J ri Tc TL Tr Ts Tw w))
   {
      $code .= "sub $key { \$_[0]->{$key} = \$_[1] }";
   }
   eval $code;
}
#----------------

=item g GRAY

=cut

sub g
{
   my $self = shift;
   my $g = shift;

   $self->{g} = [$g];
   $self->{device} = "DeviceGray";
}
#----------------

=item G GRAY

=cut

sub G
{
   my $self = shift;
   my $g = shift;

   $self->{G} = [$g];
   $self->{Device} = "DeviceGray";
}
#----------------

=item rg RED GREEN BLUE

=cut

sub rg
{
   my $self = shift;
   my $r = shift;
   my $g = shift;
   my $b = shift;

   $self->{rg} = [$r, $g, $b];
   $self->{device} = "DeviceRGB";
}
#----------------

=item RG RED GREEN BLUE

=cut

sub RG
{
   my $self = shift;
   my $r = shift;
   my $g = shift;
   my $b = shift;

   $self->{RG} = [$r, $g, $b];
   $self->{Device} = "DeviceRGB";
}
#----------------

=item k CYAN MAGENTA YELLOW BLACK

=cut

sub k
{
   my $self = shift;
   my $c = shift;
   my $m = shift;
   my $y = shift;
   my $k = shift;

   $self->{k} = [$c, $m, $y, $k];
   $self->{device} = "DeviceCMYK";
}
#----------------

=item K CYAN MAGENTA YELLOW BLACK

=cut

sub K
{
   my $self = shift;
   my $c = shift;
   my $m = shift;
   my $y = shift;
   my $k = shift;

   $self->{K} = [$c, $m, $y, $k];
   $self->{Device} = "DeviceCMYK";
}
#----------------

=item gs (Not implemented...)

=cut

sub gs
{
   my $self = shift;

   # See PDF Ref page 157
   #warn "gs operator not yet implemented";
}
#----------------

=item cm M1, M2, M3, M4, M5, M6

=cut

sub cm
{
   my $self = shift;
   
   $self->applyMatrix([@_], $self->{cm});
}
#----------------

=item d ARRAYREF, SCALAR

=cut

sub d
{
   my $self = shift;
   my $da = shift;
   my $dp = shift;

   @{$self->{da}} = @$da;
   $self->{dp} = $dp;
}
#----------------

sub m
{
   my $self = shift;
   my $x = shift;
   my $y = shift;

   @{$self->{start}} = @{$self->{last}} = @{$self->{current}} = ($x,$y);
}
sub l
{
   my $self = shift;
   my $x = shift;
   my $y = shift;

   @{$self->{last}} = @{$self->{current}};
   @{$self->{current}} = ($x,$y);
}
sub h
{
   my $self = shift;

   @{$self->{last}} = @{$self->{current}};
   @{$self->{current}} = @{$self->{start}};
}
sub c
{
   my $self = shift;
   my $x1 = shift;
   my $y1 = shift;
   my $x2 = shift;
   my $y2 = shift;
   my $x3 = shift;
   my $y3 = shift;

   @{$self->{last}} = @{$self->{current}};
   @{$self->{current}} = ($x3,$y3);
}
sub v
{
   my $self = shift;
   my $x1 = shift;
   my $y1 = shift;
   my $x2 = shift;
   my $y2 = shift;

   @{$self->{last}} = @{$self->{current}};
   @{$self->{current}} = ($x2,$y2);
}
sub y
{
   my $self = shift;
   my $x1 = shift;
   my $y1 = shift;
   my $x2 = shift;
   my $y2 = shift;

   @{$self->{last}} = @{$self->{current}};
   @{$self->{current}} = ($x2,$y2);
}
sub re
{
   my $self = shift;
   my $x = shift;
   my $y = shift;
   my $w = shift;
   my $h = shift;

   @{$self->{start}} = @{$self->{last}} = @{$self->{current}} = ($x,$y);
}
#----------------

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
