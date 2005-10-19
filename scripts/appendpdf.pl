#!/usr/bin/perl -w

use warnings;
use strict;
use CAM::PDF;
use Getopt::Long;
use Pod::Usage;

my %opts = (
            verbose    => 0,
            prepend    => 0,
            forms      => 0,
            order      => 0,
            help       => 0,
            version    => 0,
            );

Getopt::Long::Configure('bundling');
GetOptions('f|forms'    => \$opts{forms},
           'v|verbose'  => \$opts{verbose},
           'p|prepend'  => \$opts{prepend},
           'o|order'    => \$opts{order},
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

if (@ARGV < 2)
{
   pod2usage(1);
}

my @files = ();
my @docs = ();

push @files, shift;
push @files, shift;
my $outfile = shift || q{-};

foreach my $file (@files)
{
   my $doc = CAM::PDF->new($file) || die "$CAM::PDF::errstr\n";
   push @docs, $doc;
}

if ($opts{prepend})
{
   if ($opts{verbose})
   {
      print 'Prepending '.$docs[1]->numPages().' page(s) to original '.$docs[0]->numPages()." page(s)\n";
   }
   $docs[0]->prependPDF($docs[1]);
}
else
{
   if ($opts{verbose})
   {
      print 'Appending '.$docs[1]->numPages().' page(s) to original '.$docs[0]->numPages()." page(s)\n";
   }
   $docs[0]->appendPDF($docs[1]);
}

if (!$opts{forms})
{
   $docs[0]->clearAnnotations();
}
   
if ($opts{order})
{
   $docs[0]->preserveOrder();
}
if (!$docs[0]->canModify())
{
   die "This PDF forbids modification\n";
}
$docs[0]->cleanoutput($outfile);


__END__

=head1 NAME

appendpdf.pl - Append one PDF to another

=head1 SYNOPSIS

appendpdf.pl [options] file1.pdf file2.pdf [outfile.pdf]

 Options:
   -p --prepend        prepend the document instead of appending it
   -f --forms          wipe all forms and annotations from the PDF
   -o --order          preserve the internal PDF ordering for output
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

=head1 DESCRIPTION

Copy the contents of file2.pdf to the end of file1.pdf.  This may
break complex PDFs which include forms, so the --forms option is
provided to eliminate those elements from the resulting PDF.

=head1 SEE ALSO

CAM::PDF

deletepdfpage.pl

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>

