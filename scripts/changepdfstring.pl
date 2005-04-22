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
my $fromstr = shift;
my $tostr = shift;
my $outfile = shift || "-";

my $doc = CAM::PDF->new($infile);
die "$CAM::PDF::errstr\n" if (!$doc);

foreach my $objnum (keys %{$doc->{xref}})
{
   my $obj = $doc->dereference($objnum);
   $doc->changeString($obj, {$fromstr => $tostr});
}

if ((!scalar (%{$doc->{changes}})) && exists $doc->{contents})
{
   print $doc->{contents};
}
else
{
   $doc->preserveOrder() if ($opts{order});
   if (!$doc->canModify())
   {
      die "This PDF forbids modification\n";
   }
   $doc->cleanoutput($outfile);
}

__END__

=head1 NAME

changepdfstring.pl - Search and replace in PDF metadata

=head1 SYNOPSIS

changepdfstring.pl [options] infile.pdf search-str replace-str [outfile.pdf]

 Options:
   -o --order          preserve the internal PDF ordering for output
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

=head1 DESCRIPTION

Searches through a PDF file's metadata for instances of search-str and
inserts replace-str.  Note that this does not change the actual PDF
page layout, but only interactive features, like forms and annotation.
To change page layout strings, use instead changepagestring.pl.

The search-str can be a literal string, or it can be a Perl regular
expression by wrapping it in C<regex(...)>.  For example:

  changepdfstring.pl in.pdf 'regex(CAM-PDF-(\d.\d+))' 'version=$1' out.pdf

=head1 SEE ALSO

CAM::PDF

changepagestring.pl

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>

