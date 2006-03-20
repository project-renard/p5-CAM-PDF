#!/usr/bin/perl -w

package main;

use warnings;
use strict;
use CAM::PDF;
use Getopt::Long;
use Pod::Usage;

our $VERSION = '1.06';

my %opts = (
            decode      => 0,
            cleanse     => 0,
            clearannots => 0,
            filters     => [],
            newprefs    => 0,
            prefs       => [],
            newpass     => 0,
            pass        => [],
            decrypt     => 0,
            newversion  => 0,

            verbose     => 0,
            order       => 0,
            help        => 0,
            version     => 0,

            # temporary variables
            looking     => q{},
            state       => 0,
            otherargs   => [],
            );

Getopt::Long::Configure('bundling');
GetOptions('1|2|3|4|5|6|7|8|9' => sub {$opts{newversion} = '1'.$_[0]}, 
           'c|cleanse'     => \$opts{cleanse},
           'd|decode'      => \$opts{decode},
           'f|filter=s'    => \@{$opts{filters}},
           'C|clearannots' => \$opts{clearannots},
           'X|decrypt'     => \$opts{decrypt},
           'p|pass'        => sub { @{$opts{pass}}=(); $opts{looking}='pass'; $opts{state}=2; $opts{newpass}=1; },
           'P|prefs'       => sub { @{$opts{prefs}}=(); $opts{looking}='prefs'; $opts{state}=4; $opts{newprefs}=1; },
           'v|verbose'     => \$opts{verbose},
           'o|order'       => \$opts{order},
           'h|help'        => \$opts{help},
           'V|version'     => \$opts{version},
           '<>'            => sub {
              if ($opts{looking})
              {
                 push @{$opts{$opts{looking}}}, $_[0];
                 if (--$opts{state} == 0)
                 {
                    $opts{looking} = q{};
                 }
              }
              else
              {
                 push @{$opts{otherargs}}, $_[0];
              }
           },
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

@ARGV = @{$opts{otherargs}};

if (@ARGV < 1)
{
   pod2usage(1);
}

my $infile = shift;
my $outfile = shift || q{-};

my $doc = CAM::PDF->new($infile) || die "$CAM::PDF::errstr\n";

if (!$doc->canModify())
{
   die "This PDF forbids modification\n";
}

if ($opts{newversion})
{
   $doc->{pdfversion} = $opts{newversion};
}

if ($opts{decode} || @{$opts{filters}} > 0)
{
   foreach my $obj (keys %{$doc->{xref}})
   {
      if ($opts{decode})
      {
         $doc->decodeObject($obj);
      }
      foreach my $filtername (@{$opts{filters}})
      {
         $doc->encodeObject($obj, $filtername);
      }
   }
}
if ($opts{newprefs} || $opts{newpass})
{
   my @p = $doc->getPrefs();
   if ($opts{newpass})
   {
      $p[0] = $opts{pass}->[0];
      $p[1] = $opts{pass}->[1];
   }
   if ($opts{newprefs})
   {
      $p[2] = $opts{prefs}->[0];
      $p[3] = $opts{prefs}->[1];
      $p[4] = $opts{prefs}->[2];
      $p[5] = $opts{prefs}->[3];
   }
   $doc->setPrefs(@p);
}
if ($opts{decrypt})
{
   $doc->cacheObjects();
   $doc->{crypt}->{noop} = 1;
   if ($doc->{crypt}->{EncryptBlock})
   {
      $doc->deleteObject($doc->{crypt}->{EncryptBlock});
      delete $doc->{trailer}->{Encrypt};
      delete $doc->{crypt}->{EncryptBlock};
   }
}

if ($opts{clearannots})
{
   $doc->clearAnnotations();
}
if ($opts{cleanse})
{
   $doc->cleanse();
}
if ($opts{order})
{
   $doc->preserveOrder();
}
$doc->cleanoutput($outfile);


__END__

=for stopwords rewritepdf.pl

=head1 NAME

rewritepdf.pl - Rebuild a PDF file

=head1 SYNOPSIS

 rewritepdf.pl [options] infile.pdf [outfile.pdf]\n";

 Options:
   -c --cleanse        seek and destroy unreferenced metadata in the document
   -C --clearannots    remove all annotations (including forms)
   -d --decode         uncompress any encoded elements
   -f --filter=name    compress all elements with this filter (can use more than once)
   -X --decrypt        remove encryption from the document
   -o --order          preserve the internal PDF ordering for output
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

   -p --pass opass upass              set a new owner and user password
   -P --prefs print modify copy add   set boolean permissions for the document

=head1 DESCRIPTION

Read and write a PDF document, and possibly modify it along the way.

The C<--cleanse> option could possibly break some PDFs which use
undocumented or poorly documented PDF features.  Namely, some PDFs
implicitly store their C<FontDescriptor> objects just before their Font
objects, without explicitly referring to the former.  Cleansing
removes the former, causing Acrobat Reader to choke.

We recommend that you avoid the C<--decode> and C<--filter> options, as
we're not sure they work right any longer.

=head1 SEE ALSO

CAM::PDF

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>

=cut
