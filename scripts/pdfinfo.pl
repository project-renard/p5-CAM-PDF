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
GetOptions("v|verbose"    => \$opts{verbose},
           "h|help"       => \$opts{help},
           "V|version"    => \$opts{version},
           ) or pod2usage(1);
pod2usage(-exitstatus => 0, -verbose => 2) if ($opts{help});
print("CAM::PDF v$CAM::PDF::VERSION\n"),exit(0) if ($opts{version});

if (@ARGV < 1)
{
   pod2usage(1);
}

while (@ARGV > 0)
{
   my $file = shift;
   my $doc = CAM::PDF->new($file, "", "", 1); # prompt for password
   die "$CAM::PDF::errstr\n" if (!$doc);
   
   $file = "STDIN" if ($file eq "-");
   my $size = length($doc->{content});
   my $pages = $doc->numPages();
   my @prefs = $doc->getPrefs();
   my $pdfversion = $doc->{pdfversion};
   my $info = $doc->{trailer}->{Info};
   $info &&= $doc->getValue($info);

   my @pagesize = (0,0);
   my $p = $doc->{Pages};
   my $box = $p->{MediaBox};
   if ($box)
   {
      $box = $box->{value};
      @pagesize = ($box->[2]->{value} - $box->[0]->{value},
                   $box->[3]->{value} - $box->[1]->{value});
   }

   print "File:         $file\n";
   print "File Size:    $size bytes\n";
   print "Pages:        $pages\n";
   if ($info)
   {
      foreach my $key (sort keys %$info)
      {
         my $val = $info->{$key}->{value};
         if ($info->{$key}->{type} eq "string" && $val && 
             $val =~ /^D:(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})([+-])(\d{2})\'(\d{2})\'$/)
         {
            my ($Y,$M,$D,$h,$m,$s,$sign,$tzh,$tzm) = ($1,$2,$3,$4,$5,$6,$7,$8,$9);
            eval "require Time::Local;";
            if (!$@)
            {
               my $time = Time::Local::timegm($s,$m,$h,$D,$M-1,$Y-1900);
               $time += "$sign".($tzh*3600 + $tzm*60);
               $val = localtime($time);
            }
         }
         printf "%-13s %s\n", $key.":", $val;
      }
   }
   print "Page Size:    ".($pagesize[0] ? "$pagesize[0] x $pagesize[1] pts" : "variable")."\n";
   print "Optimized:    ".($doc->isLinearized()?"yes":"no")."\n";
   print "PDF version:  $pdfversion\n";
   print "Security\n";
   if ($prefs[0] || $prefs[1])
   {
      print "  Passwd:     '$prefs[0]', '$prefs[1]'\n";
   }
   else
   {
      print "  Passwd:     none\n";
   }
   print "  Print:      ".($prefs[2]?"yes":"no")."\n";
   print "  Modify:     ".($prefs[3]?"yes":"no")."\n";
   print "  Copy:       ".($prefs[4]?"yes":"no")."\n";
   print "  Add:        ".($prefs[5]?"yes":"no")."\n";
   print "---------------------------------\n" if (@ARGV > 0);
}


__END__

=head1 NAME

pdfinfo.pl - Print information about PDF file(s)

=head1 SYNOPSIS

pdfinfo.pl [options] file.pdf [file.pdf ...]

 Options:
   -v --verbose        print diagnostic messages
   -h --help           verbose help message
   -V --version        print CAM::PDF version

=head1 DESCRIPTION

Prints to STDOUT various basic details about the specified PDF
file(s).

=head1 SEE ALSO

CAM::PDF

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
