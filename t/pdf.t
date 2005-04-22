#!/usr/bin/perl -w

use warnings;
use strict;
use Carp;
$SIG{__WARN__} = $SIG{__DIE__} = \&confess;

BEGIN
{
   use Test::More tests => 17;
   use_ok("CAM::PDF");
}

my @testdocs = (
                "t/inlineimage.pdf",
                );

is_deeply([CAM::PDF->rangeToArray(0,10)],
          [0,1,2,3,4,5,6,7,8,9,10], "range test");
is_deeply([CAM::PDF->rangeToArray(0,10,"1-2")],
          [1,2], "range test");
is_deeply([CAM::PDF->rangeToArray(0,10,"-3")],
          [0,1,2,3], "range test");
is_deeply([CAM::PDF->rangeToArray(0,10,"8-")],
          [8,9,10], "range test");
is_deeply([CAM::PDF->rangeToArray(0,10,3,4,"6-8",11,2)],
          [3,4,6,7,8,2], "range test");
is_deeply([CAM::PDF->rangeToArray(0,10,"7-4")],
          [7,6,5,4], "range test");
is_deeply([CAM::PDF->rangeToArray(10,20,"1-3,6,22,25-28")],
          [], "range test");
is_deeply([CAM::PDF->rangeToArray(10,20,"-3")],
          [], "range test");
is_deeply([CAM::PDF->rangeToArray(10,20,"25-")],
          [], "range test");

foreach my $file (@testdocs)
{
   my $doc = CAM::PDF->new($file);
   ok($doc, "open pdf");
   
   my $tree = $doc->getPageContentTree(1);
   ok($tree && @{$tree->{blocks}} > 0, "parse page content");
   ok($tree->validate(), "validate page content");
   $doc->setPageContent(1, $tree->toString());
   my $tree2 = $doc->getPageContentTree(1);
   is_deeply($tree2->{blocks}, $tree->{blocks}, "page content toString validity");

   # Add some pages
   my $dupe = CAM::PDF->new($file);
   $doc->appendPDF($dupe);
   $doc->appendPDF($dupe);
   $doc->appendPDF($dupe);
   $doc->cleansave();
   is($doc->numPages(), 4, "append pages");

   ok($doc->extractPages(2,4), "extract/delete pages");
   $doc->cleansave();
   is($doc->numPages(), 2, "extract page check");
}
