package CAM::PDF::Renderer::Images;

use 5.006;
use warnings;
use strict;

our $VERSION = '1.02_02';

=head1 NAME

CAM::PDF::Renderer::Images - Find all of the images in a page

=head1 LICENSE

See CAM::PDF.

=head1 SYNOPSIS

    use CAM::PDF;
    my $pdf = CAM::PDF->new($filename);
    my $contentTree = $pdf->getPageContentTree(4);
    my $gs = $contentTree->findImages();
    my @imageNodes = @{$gs->{images}};

=head1 DESCRIPTION

This class is used to identify all image nodes in a page content tree.

=head1 FUNCTIONS

=over

=item new

Creates a new renderer.

=cut

sub new
{
   my $pkg = shift;
   return bless {}, $pkg;
}

=item clone

Duplicates an instance.

=cut

sub clone
{
   my $obj = shift;

   my $pkg = ref $obj;
   my $self = $pkg->new();
   $self->{images} = $obj->{images};
}

=item Do DATA...

Record an indirect image node.

=cut

sub Do
{
   my $self = shift;
   my $value = [@_];

   $self->{images} ||= [];
   push @{$self->{images}}, {
      type => 'Do',
      value => $value,
   };
}

=item BI DATA...

Record an inline image node.

=cut

sub BI
{
   my $self = shift;
   my $value = [@_];

   $self->{images} ||= [];
   push @{$self->{images}}, {
      type => 'BI',
      value => $value,
   };
}

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
