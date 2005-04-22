#!/usr/bin/perl -w

use strict;
use CAM::PDF;
use Getopt::Long;
use Pod::Usage;

my %opts = (
            verbose    => 0,
            help       => 0,
            version    => 0,
            );

Getopt::Long::Configure("bundling");
GetOptions("v|verbose"  => \$opts{verbose},
           "h|help"     => \$opts{help},
           "V|version"  => \$opts{version},
           ) or pod2usage(1);
pod2usage(-exitstatus => 0, -verbose => 2) if ($opts{help});
print("CAM::PDF v$CAM::PDF::VERSION\n"),exit(0) if ($opts{version});

if (@ARGV < 1)
{
   pod2usage(1);
}

my $infile = shift;
my $outfile = shift || "-";

my $doc = CAM::PDF->new($infile);
die "$CAM::PDF::errstr\n" if (!$doc);

$doc->uninlineImages();
print $doc->toString() if ($opts{verbose});
if (!$doc->canModify())
{
   die "This PDF forbids modification\n";
}
$doc->cleanoutput($outfile);


__END__

=head1 NAME

uninlinepdfimages.pl - Save copies of all PDF JPG images to a directory

=head1 SYNOPSIS

uninlinepdfimages.pl [options] infile.pdf [outfile.pdf]

 Options:
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

=head1 DESCRIPTION

Searches the PDF for images and lists them on STDOUT in one of the
following formats:

  Image <n> page <p>, (w,h)=(<w>,<h>), ref <label> = object <objnum>, length <l>\n";
  Image <n> page <p>, (w,h)=(<w>,<h>), inline

=head1 SEE ALSO

CAM::PDF

crunchjpgs.pl

extractallimages.pl

extractjpgs.pl

listimages.pl

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
