use 5.006;
use ExtUtils::MakeMaker;

open my $fh, 'MANIFEST' || die;
my @exefiles = grep {s/\s.*$//; /^scripts\/(?:asciify|.*\.pl)$/} <$fh>;
close $fh;

WriteMakefile(
   'NAME'		=> 'CAM::PDF',
   'VERSION_FROM'	=> 'lib/CAM/PDF.pm',
   'PREREQ_PM'		=> {
      'Text::PDF::File'          => '0.18',
      'Crypt::RC4'               => '2.02',
      'Digest::MD5'              => '2.16',
      'Getopt::Long'             => '2.0',    # needed for scripts
      'Pod::Usage'               => '1.0',    # needed for scripts
      'Test::More'               => '0.01',
   },
   'EXE_FILES'       => [@exefiles],
   'PL_FILES'        => {},
   ($] >= 5.005 ?
    (ABSTRACT_FROM => 'lib/CAM/PDF.pm',
     AUTHOR     => 'Clotho Advanced Media <cpan@clotho.com>') : ()),
);
