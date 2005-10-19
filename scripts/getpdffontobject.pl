#!/usr/bin/perl -w

use warnings;
use strict;
use CAM::PDF;
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;

my %opts = (
            verbose    => 0,
            help       => 0,
            version    => 0,
            );

Getopt::Long::Configure('bundling');
GetOptions('v|verbose'  => \$opts{verbose},
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

if (@ARGV < 3)
{
   pod2usage(1);
}

my $file = shift;
my $pagenum = shift;
my $fontname = shift;

if ($pagenum !~ /^\d+$/ || $pagenum < 1)
{
   die "The page number must be an integer greater than 0\n";
}

my $doc = CAM::PDF->new($file) || die "$CAM::PDF::errstr\n";

my $font = $doc->getFont($pagenum, $fontname);
if (!$font)
{
   die "Font $fontname not found\n";
}

if ($opts{verbose})
{
   print Data::Dumper->Dump([$font], ['font']);
}


__END__

=head1 NAME

getpdffontobject.pl - Print the PDF form field names

=head1 SYNOPSIS

getpdffontobject.pl [options] infile.pdf pagenum fontname

 Options:
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

=head1 DESCRIPTION

Retrieves the font metadata from the PDF.  If --verbose is specified,
the memory representation is dumped to STDOUT.  Otherwise, the program
silently returns success or emits a failure message to STDERR.

The leading C</> on the fontname is optional.

=head1 SEE ALSO

CAM::PDF

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
