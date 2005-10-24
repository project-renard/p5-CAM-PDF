use Module::Build;

# Grab the list of cmdline programs
open my $fh, 'MANIFEST' || die;
my @exefiles = grep {s/\s.*$//; /^scripts\/(?:asciify|.*\.pl)$/} <$fh>;
close $fh;

Module::Build->new(
   module_name => 'CAM::PDF',
   dist_author => 'Clotho Advanced Media, Inc. <cpan@clotho.com>',
   license => 'perl',
   requires => {
      'perl' => '5.6.0',
      'Text::PDF::File' => '0.18',
      'Crypt::RC4' => '2.02',
      'Digest::MD5' => '2.16',
   },
   recommends => {
      # Needed for scripts
      'Getopt::Long' => '2.0',    
      'Pod::Usage' => '1.0',

      # Optional in tests, skipped if not present
      'Test::Pod' => 0,
      'Test::Pod::Coverage' => 0,
      'Test::Memory::Cycle' => '1.02',
   },
   build_requires => {
      'Test::More' => 0,  # needs to be v0.62 for Test::Memory::Cycle v1.02
   },
   script_files => [@exefiles],
   add_to_cleanup => [ 'CAM-PDF-*' ],
)->create_build_script;
