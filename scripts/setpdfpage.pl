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

if (@ARGV < 3)
{
   pod2usage(1);
}

my $infile = shift;
my $pagetext = shift;
my $pagenum = shift;
my $outfile = shift || "-";

my $doc = CAM::PDF->new($infile);
die "$CAM::PDF::errstr\n" if (!$doc);

my $content;
if ($pagetext eq "-")
{
   $content = join('', <STDIN>);
}
else
{
   local *FILE;
   open(FILE, $pagetext) or die "Failed to open $pagetext: $!\n";
   $content = join('', <FILE>);
   close(FILE);
}

$doc->setPageContent($pagenum, $content);

$doc->preserveOrder() if ($opts{order});
if (!$doc->canModify())
{
   die "This PDF forbids modification\n";
}
$doc->cleanoutput($outfile);


__END__

=head1 NAME

setpdfpage.pl - Replace a page of PDF layout

=head1 SYNOPSIS

setpdfpage.pl [options] infile.pdf page.txt pagenum [outfile.pdf]

 Options:
   -o --order          preserve the internal PDF ordering for output
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

=head1 DESCRIPTION

Assign the specified ASCII file to be the page content for the PDF
page indicated.  The existing page layout is discarded.

=head1 SEE ALSO

CAM::PDF

getpdfpage.pl

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
