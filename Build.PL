use Module::Build;

open FILE, "MANIFEST";
@exefiles = grep {chomp; /^scripts\/.*\.pl$/ && $_ ne "test.pl"} <FILE>;
close FILE;
push @exefiles, "scripts/asciify";

Module::Build->new(
                   module_name => 'CAM::PDF',
                   license => 'perl',
                   requires => {
                      'Text::PDF::File'          => '0.18',
                      'Crypt::RC4'               => '2.02',
                      'Digest::MD5'              => '2.16',
                   },
                   recommends => {
                      'Getopt::Long'             => '2.0',    # needed for scripts
                      'Pod::Usage'               => '1.0',    # needed for scripts
                   },
                   build_requires => {
                      'Test::More'               => '0.01',
                   },
                   script_files => [@exefiles],
                   )->create_build_script;
