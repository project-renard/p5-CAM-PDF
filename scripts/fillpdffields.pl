#!/usr/bin/perl -w

use strict;
use CAM::PDF;
use Getopt::Long;
use Pod::Usage;

my %opts = (
            triggerclear => 0,
            verbose    => 0,
            order      => 0,
            help       => 0,
            version    => 0,
            );

Getopt::Long::Configure("bundling");
GetOptions("t|triggerclear"  => \$opts{triggerclear},
           "v|verbose"  => \$opts{verbose},
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
my $outfile = shift;

my $doc = CAM::PDF->new($infile);
die "$CAM::PDF::errstr\n" if (!$doc);

my @list = (@ARGV);
$doc->fillFormFields(@list);
if ($opts{triggerclear})
{
   for (my $i=0; $i < @list; $i+=2)
   {
      my $obj = $doc->getFormField($list[$i]);
      delete $obj->{value}->{value}->{AA} if ($obj);
   }
}

$doc->preserveOrder() if ($opts{order});
if (!$doc->canModify())
{
   die "This PDF forbids modification\n";
}
$doc->cleanoutput($outfile);


__END__

=head1 NAME

fillpdffields.pl - Replace PDF form fields with specified values

=head1 SYNOPSIS

fillpdffields.pl [options] infile.pdf outfile.pdf field value [field value ...]

 Options:
   -t --triggerclear   remove all of the form triggers after replacing values
   -o --order          preserve the internal PDF ordering for output
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

=head1 DESCRIPTION

Fill in the forms in the PDF with the specified values, identified by
their field names.  See listpdffields.pl for a the names of the form
fields.

=head1 SEE ALSO

CAM::PDF

listpdffields.pl

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
