#!/usr/bin/perl -w

use strict;
use CAM::PDF;
use Getopt::Long;
use Pod::Usage;

my %opts = (
            verbose     => 0,
            order       => 0,
            help        => 0,
            version     => 0,
            );

Getopt::Long::Configure("bundling");
GetOptions("v|verbose"     => \$opts{verbose},
           "o|order"       => \$opts{order},
           "h|help"        => \$opts{help},
           "V|version"     => \$opts{version},
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

if (!$doc->canModify())
{
   die "This PDF forbids modification\n";
}

foreach my $objnum (keys %{$doc->{xref}})
{
   my $obj = $doc->dereference($objnum);
   my $val = $obj->{value};
   if ($val->{type} eq "dictionary")
   {
      my $dict = $val->{value};
      my $changed = 0;
      foreach my $key (qw(Metadata
                          PieceInfo
                          LastModified
                          Thumb
                          Group))
      {
         if (exists $dict->{$key})
         {
            delete $dict->{$key};
            $changed = 1;
         }
      }
      if ($changed)
      {
         $doc->{changes}->{$objnum} = 1;
      }
   }
}

$doc->cleanse();
$doc->preserveOrder() if ($opts{order});
$doc->cleanoutput($outfile);


__END__

=head1 NAME

deillustrate.pl - Remove Adobe Illustrator metadata from a PDF file

=head1 SYNOPSIS

deillustrate.pl [options] infile.pdf [outfile.pdf]\n";

 Options:
   -o --order          preserve the internal PDF ordering for output
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

=head1 DESCRIPTION

Adobe Illustrator has a very handy feature that allows an author to
embed special metadata in a PDF that allows Illustrator to reopen the
file fully editable.  However, this extra data does increase the size
of the PDF unnecessarily if no further editing is expected, as is the
case for most PDFs that will be distributed on the web.  Depending on
the PDF, this can dramatically reduce the file size.

This program uses a few heuristics to find and delete the
Illustrator-specific data.  This program also removes embedded
thumbnail representations of the PDF for further byte savings.

=head1 SEE ALSO

CAM::PDF

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>