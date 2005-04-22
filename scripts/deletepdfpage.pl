#!/usr/bin/perl -w

use strict;
use CAM::PDF;
use Getopt::Long;
use Pod::Usage;

my %opts = (
            verbose    => 0,
            order      => 0,
            help       => 0,
            version    => 0,
            );

Getopt::Long::Configure("bundling");
GetOptions("v|verbose"  => \$opts{verbose},
           "o|order"    => \$opts{order},
           "h|help"     => \$opts{help},
           "V|version"  => \$opts{version},
           ) or pod2usage(1);
pod2usage(-exitstatus => 0, -verbose => 2) if ($opts{help});
print("CAM::PDF v$CAM::PDF::VERSION\n"),exit(0) if ($opts{version});

if (@ARGV < 2)
{
   pod2usage(1);
}

my $infile = shift;
my $pagenums = shift;
my $outfile = shift || "-";

my $doc = CAM::PDF->new($infile);
die "$CAM::PDF::errstr\n" if (!$doc);

if (!$doc->deletePages($pagenums))
{
   die "Failed to delete a page\n";
}
$doc->preserveOrder() if ($opts{order});
if (!$doc->canModify())
{
   die "This PDF forbids modification\n";
}
$doc->cleanoutput($outfile);


__END__

=head1 NAME

deletepdfpage.pl - Remove one or more pages from a PDF

=head1 SYNOPSIS

deletepdfpage.pl [options] infile.pdf <pagenums> [outfile.pdf]

 Options:
   -o --order          preserve the internal PDF ordering for output
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

 <pagenums> is a comma-separated list of page numbers.
      Ranges like '2-6' allowed in the list
      Example: 4-6,2,12,8-9

=head1 DESCRIPTION

Remove the specified pages from a PDF document.  This may fail for
very complex, annotated PDF files, for example ones that Adobe
Illustrator emits.

=head1 SEE ALSO

CAM::PDF

appendpdf.pl

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
