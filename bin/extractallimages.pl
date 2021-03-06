#!/usr/bin/perl -w

package main;

use warnings;
use strict;
use CAM::PDF;
use Getopt::Long;
use Pod::Usage;

our $VERSION = '1.60';

my %opts = (
            template   => 'crunchjpg_tmpl.pdf',

            verbose    => 0,
            help       => 0,
            version    => 0,
            skip       => {},
            only       => {},

            # Temporary values:
            onlyval    => [],
            skipval    => [],
            );

Getopt::Long::Configure('bundling');
GetOptions('S|skip=s'     => \@{$opts{skipval}},
           'O|only=s'     => \@{$opts{onlyval}},
           'v|verbose'  => \$opts{verbose},
           'h|help'     => \$opts{help},
           'V|version'  => \$opts{version},
           ) or pod2usage(1);
if ($opts{help})
{
   pod2usage(-exitstatus => 0, -verbose => 2);
}
if ($opts{version})
{
   print "CAM::PDF v$CAM::PDF::VERSION\n";
   exit 0;
}

foreach my $flag (qw( skip only ))
{
   foreach my $val (@{$opts{$flag.'val'}})
   {
      foreach my $key (split /\D+/xms, $val)
      {
         $opts{$flag}->{$key} = 1;
      }
   }
}
if (!-f $opts{template})
{
   die "Cannot find the template pdf called $opts{template}\n";
}

if (@ARGV < 2)
{
   pod2usage(1);
}

my $infile = shift;
my $outdir = shift;

my $doc = CAM::PDF->new($infile) || die "$CAM::PDF::errstr\n";

my $nimages = 0;
my $rimages = 0;
my %doneobjs;

foreach my $objnum (keys %{$doc->{xref}})
{
   my $xobj = $doc->dereference($objnum);
   if ($xobj->{value}->{type} eq 'dictionary')
   {
      my $im = $xobj->{value}->{value};
      if (exists $im->{Type} && $doc->getValue($im->{Type}) eq 'XObject' &&
          exists $im->{Subtype} && $doc->getValue($im->{Subtype}) eq 'Image')
      {
         my $ref = '(no name)';
         if ($im->{Name})
         {
            $ref = $doc->getValue($im->{Name});
         }
         my $w = $im->{Width} || $im->{W} || 0;
         if ($w)
         {
            $w = $doc->getValue($w);
         }
         my $h = $im->{Height} || $im->{H} || 0;
         if ($h)
         {
            $h = $doc->getValue($h);
         }

         next if (exists $doneobjs{$objnum});

         $nimages++;
         _inform("Image $nimages, $ref = object $objnum, (w,h)=($w,$h)", $opts{verbose});

         if (exists $opts{skip}->{$objnum} ||
             (0 < scalar keys %{$opts{only}} && !exists $opts{only}->{$objnum}))
         {
            _inform("Skipping object $objnum", $opts{verbose});
            next;
         }

         my $isjpg = _isjpg($im);

         my $oldsize = $doc->getValue($im->{Length});
         if (!$oldsize)
         {
            die "PDF error: Failed to get size of image\n";
         }

         my $tmpl = CAM::PDF->new($opts{template}) || die "$CAM::PDF::errstr\n";

         # Get a handle on the needed data bits from the template
         my $media_array = $tmpl->getValue($tmpl->getPage(1)->{MediaBox});
         my $rawpage = $tmpl->getPageContent(1);

         $media_array->[2]->{value} = $w;
         $media_array->[3]->{value} = $h;
         my $page = $rawpage;
         $page =~ s/xxx/$w/igxms;
         $page =~ s/yyy/$h/igxms;
         $tmpl->setPageContent(1, $page);
         $tmpl->replaceObject(9, $doc, $objnum, 1);

         my $ofile = "/tmp/crunchjpg.$$";
         $tmpl->cleanoutput($ofile);

         if (!-d $outdir)
         {
            require File::Path;
            File::Path::mkpath($outdir);
         }
         if ($isjpg)
         {
            my $result = `convert -quality 50 -density 72x72 -page ${w}x$h pdf:$ofile jpg:$outdir/$objnum.jpg`;  ## no critic (Backtick)
            _inform($result, $opts{verbose});
         }
         else
         {
            my $result = `convert -density 72x72 -page ${w}x$h pdf:$ofile gif:$outdir/$objnum.gif`;  ## no critic (Backtick)
            _inform($result, $opts{verbose});
         }

         $doneobjs{$objnum} = 1;
         $rimages++;
      }
   }
}

_inform("Extracted $rimages of $nimages images", $opts{verbose});


sub _isjpg
{
   my $im = shift;
   return if (!$im->{Filter});

   my $f = $im->{Filter};
   my @names = $f->{type} eq 'array' ? @{$f->{value}} : $f;
   for my $e (@names)
   {
      my $name = $doc->getValue($e);
      if (ref $name)
      {
         $name = $name->{value};
      }
      #warn "Checking $name\n";
      if ($name eq 'DCTDecode')
      {
         return 1;
      }
   }
   return;
}

sub _inform
{
   my $str     = shift;
   my $verbose = shift;

   if ($verbose)
   {
      print STDERR $str, "\n";
   }
   return;
}

__END__


=for stopwords extractallimages.pl ImageMagick

=head1 NAME

extractallimages.pl - Save copies of all PDF images to a directory

=head1 SYNOPSIS

 extractallimages.pl [options] infile.pdf outdirectory

 Options:
   -O --only=imnum     only output the specified images (can be used mutliple times)
   -S --skip=imnum     don't output the specified images (can be used mutliple times)
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

C<imnum> is a comma-separated list of integers indicating the images
in order that they appear in the PDF.  Use F<listimages.pl> to retrieve
the image numbers.

=head1 DESCRIPTION

Requires the ImageMagick B<convert> program to be available

Searches the PDF for images and saves them as individual files in the
specified directory.  The files are named C<E<lt>imnumE<gt>.jpg> or C<E<lt>imnumE<gt>.gif>.

=head1 SEE ALSO

CAM::PDF

F<crunchjpgs.pl>

F<listimages.pl>

F<extractjpgs.pl>

F<uninlinepdfimages.pl>

=head1 AUTHOR

See L<CAM::PDF>

=cut
