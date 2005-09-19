package CAM::PDF;

=head1 NAME

CAM::PDF - PDF manipulation library

=head1 LICENSE

Copyright 2005 Clotho Advanced Media, Inc., <cpan@clotho.com>

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SYNOPSIS

    use CAM::PDF;
    
    my $pdf = new CAM::PDF("test1.pdf");
    
    my $page1 = $pdf->getPageContent(1);
    [ ... mess with page ... ]
    $pdf->setPageContent(1, $page1);
    [ ... create some new content ... ]
    $pdf->appendPageContent(1, $newcontent);
    
    my @prefs = $pdf->getPrefs();
    $prefs[$CAM::PDF::PREF_OPASS] = "mypassword";
    $pdf->setPrefs(@prefs);
    
    $pdf->cleanoutput("out1.pdf");

Many example scripts are included in this distribution to do basic
tasks.

=head1 DESCRIPTION

This package reads and writes any document that conforms to the PDF
specification generously provided by Adobe at (3rd edition, for PDF
v1.4 as of May 2002)
http://partners.adobe.com/asn/developer/acrosdk/docs/filefmtspecs/PDFReference.pdf

The file format is well-supported, with the exception of the
"linearized" or "optimized" output format, which this module can read
but not write.  Many specific aspects of the document model are not
manipulable with this package (like fonts), but if the input document
is correctly written, then this module will preserve the model
integrity.

This library grants you some power over the PDF security model.  Note
that applications editing PDF documents via this library MUST respect
the security preferences of the document.  Any violation of this
respect is contrary to Adobe's intellectual property position, as
stated in the reference manual at the above URL.

Technical detail regarding corrupt PDFs: This library adheres strictly
to the PDF specification.  Adobe's Acrobat Reader is more lenient,
allowing some corrupted PDFs to be viewable.  Therefore, it is
possible that some PDFs may be readable by Acrobat that are illegible
to this library.  In particular, files which have had line endings
converted to or from DOS/Windows style (i.e. CR-NL) may be rendered
unusable even though Acrobat does not complain.  Future library
versions may relax the parser, but not yet.

=head1 PERFORMANCE

This module is written with good speed and flexibility in mind, often at the
expense of memory consumption.  Entire PDF documents are typically
slurped into RAM.  As an example, simply calling C<new()> the 14 MB
Adobe PDF Reference V1.5 document pushes Perl to consume 84 MB of RAM
on my development machine.

=cut

use strict;
use warnings;
use Carp;
use CAM::PDF::Decrypt;

# For debugging only:
my $speedtesting = 0;  # debug flag

use vars qw($VERSION @ISA $MAX_STRING
            $PREF_OPASS $PREF_UPASS $PREF_PRINT $PREF_MODIFY $PREF_COPY $PREF_ADD);
$VERSION = "1.00";

$PREF_OPASS  = 0;
$PREF_UPASS  = 1;
$PREF_PRINT  = 2;
$PREF_MODIFY = 3;
$PREF_COPY   = 4;
$PREF_ADD    = 5;

$MAX_STRING  = 65;  # length of output string

my %filterabbrevs = (
                     AHx => "ASCIIHexDecode",
                     A85 => "ASCII85Decode",
                     CCF => "CCITTFaxDecode",
                     DCT => "DCTDecode",
                     Fl  => "FlateDecode",
                     LZW => "LZWDecode",
                     RL  => "RunLengthDecode",
                     );

my %inlineabbrevs = (
                     %filterabbrevs,
                     BPC => "BitsPerComponent",
                     CS  => "ColorSpace",
                     D   => "Decode",
                     DP  => "DecodeParms",
                     F   => "Filter",
                     H   => "Height",
                     IM  => "ImageMask",
                     I   => "Interpolate",
                     W   => "Width",
                     CMYK => "DeviceCMYK",
                     G   => "DeviceGray",
                     RGB => "DeviceRGB",
                     I   => "Indexed",
                     );

=head1 API

=head2 Functions intended to be used externally

 $doc = CAM::PDF->new(content | filename | '-')
 $doc->toPDF()
 $doc->needsSave()
 $doc->save()
 $doc->cleansave()
 $doc->output(filename | '-')
 $doc->cleanoutput(filename | '-')
 $doc->preserveOrder()
 $doc->appendObject(olddoc, oldnum, [follow=(1|0)])
 $doc->replaceObject(newnum, olddoc, oldnum, [follow=(1|0)])
    (olddoc can be undef in the above for adding new objects)
 $doc->numPages()
 $doc->getPageText(pagenum)
 $doc->getPageContent(pagenum)
 $doc->setPageContent(pagenum, content)
 $doc->appendPageContent(pagenum, content)
 $doc->deletePage(pagenum)
 $doc->deletePages(pagenum, pagenum, ...)
 $doc->extractPages(pagenum, pagenum, ...)
 $doc->appendPDF(CAM::PDF object)
 $doc->prependPDF(CAM::PDF object)
 $doc->wrapString(string, width, fontsize, page, fontlabel)
 $doc->getFontNames(pagenum)
 $doc->addFont(page, fontname, fontlabel, [fontmetrics])
 $doc->deEmbedFont(page, fontname, [newfontname])
 $doc->deEmbedFontByBaseName(page, basename, [newfont])
 $doc->getPrefs()
 $doc->setPrefs()
 $doc->canPrint()
 $doc->canModify()
 $doc->canCopy()
 $doc->canAdd()
 $doc->getFormFieldList()
 $doc->fillFormFields(fieldname, value, [fieldname, value, ...])
   or $doc->fillFormFields(%values)
 $doc->clearFormFieldTriggers(fieldname, fieldname, ...)

Note: 'clean' as in 'cleansave' and 'cleanobject' means write a fresh
PDF document.  The alternative (e.g. 'save') reuses the existing doc
and just appends to it.  Also note that 'clean' functions sort the
objects numerically.  If you prefer that the new PDF docs more closely
resemble the old ones, call 'preserveOrder' before 'cleansave' or
'cleanobject.'

=head2 Slightly less external, but useful, functions

 $doc->toString()
 $doc->getPage(pagenum)
 $doc->getFont(pagenum, fontname)
 $doc->getFonts(pagenum)
 $doc->getStringWidth(fontdict, string)
 $doc->getFormField(fieldname)
 $doc->getFormFieldDict(object)
 $doc->isLinearized()
 $doc->decodeObject(objectnum)
 $doc->decodeAll(any-node)
 $doc->decodeOne(dict-node)
 $doc->encodeObject(objectnum, filter)
 $doc->encodeOne(any-node, filter)
 $doc->changeString(obj-node, hashref)

=head2 Deeper utilities

 $doc->pageAddName(pagenum, name, objectnum)
 $doc->getPageObjnum(pagenum)
 $doc->getPropertyNames(pagenum)
 $doc->getProperty(pagenum, propname)
 $doc->getValue(any-node)
 $doc->dereference(objectnum)  or $doc->dereference(name,pagenum)
 $doc->deleteObject(objectnum)
 $doc->copyObject(obj-node)
 $doc->cacheObjects()
 $doc->setObjNum(obj-node, num)
 $doc->getRefList(obj-node)
 $doc->changeRefKeys(obj-node, hashref)

=head2 More rarely needed utilities

 $doc->getObjValue(objectnum)

=head2 Routines that should not be called

 $doc->startdoc()
 $doc->delinearlize()
 $doc->build*()
 $doc->parse*()
 $doc->write*()
 $doc->*CB()
 $doc->traverse()
 $doc->fixDecode()
 $doc->abbrevInlineImage()
 $doc->unabbrevInlineImage()
 $doc->cleanse()
 $doc->clean()
 $doc->createID()


=head1 FUNCTIONS

=head2 Object creation/manipulation

=over 4

=cut

#------------------

=item new PACKAGE, CONTENT

=item new PACKAGE, CONTENT, OWNERPASS, USERPASS

=item new PACKAGE, CONTENT, OWNERPASS, USERPASS, PROMPT?

Instantiate a new CAM::PDF object.  CONTENT can be a ducument in a
string, a filename, or '-'.  The latter indicates that the document
should be read from standard input.  If the document is password
protected, the passwords should be passed as additional arguments.  If
they are not known, a boolean argument allows the programmer to
suggest that the constructor prompt the user for a password.  This is
rudimentary prompting: passwords are in the clear on the console.

=cut

sub new($$$$$)
{
   my $pkg = shift;
   my $content = shift;  # or a filename
   # Optional args:
   my $opassword = shift;
   my $upassword = shift;
   my $promptForPassword = shift;

   my $pdfversion = "1.2";
   if ($content =~ /^%PDF-([\d\.]+)/)
   {
      $pdfversion = $1 if ($1 && $1 > $pdfversion);
   }
   else
   {
      if (length($content) < 1024)
      {
         my $file = $content;
         if ($file eq "-")
         {
            $content = "";
            my $offset = 0;
            my $step = 4096;
            while (read(STDIN, $content, $step, $offset) == $step)
            {
               $offset += $step;
            }
         }
         else
         {
            local *F;
            if (!open(F, $file))
            {
               $CAM::PDF::errstr = "Failed to open $file: $!\n";
               return undef;
            }
            binmode F;
            read(F, $content, (-s $file));
            close(F);
         }
      }
      if ($content =~ /^%PDF-([\d\.]+)/)
      {
         $pdfversion = $1 if ($1 && $1 > $pdfversion);
      }
      else
      {
         $CAM::PDF::errstr = "Content does not begin with \"%PDF-\"\n";
         return undef;
      }
   }
   #warn "got pdfversion $pdfversion\n";

   warn "done reading\n" if ($speedtesting);

   my $doc = {
      pdfversion => $pdfversion,
      maxstr => $CAM::PDF::MAX_STRING,  # length of output string
      content => $content,
      contentlength => length($content),
      xref => {},
      maxobj => 0,
      changes => {},
      versions => {},

      # Caches:
      objcache => {},
      pagecache => {},
      formcache => {},
      Names => {},
      NameObjects => {},
      fontmetrics => {},
   };
   bless $doc, $pkg;
   if (!$doc->startdoc())
   {
      return undef;
   }
   warn "done starting\n" if ($speedtesting);

   if ($doc->{trailer}->{ID})
   {
      my $id = $doc->getValue($doc->{trailer}->{ID});
      if (ref $id)
      {
         my $accum = "";
         foreach my $obj (@$id)
         {
            $accum .= $doc->getValue($obj);
         }
         $id = $accum;
      }
      $doc->{ID} = $id;
   }
   #$doc->{ID} ||= "";
   warn "done getting ID\n" if ($speedtesting);

   $doc->{crypt} = CAM::PDF::Decrypt->new($doc, $opassword, $upassword, $promptForPassword);
   return undef if (!defined $doc->{crypt});
   warn "done loading crypt\n" if ($speedtesting);

   return $doc;
}

#------------------

=item toPDF

Serializes the data structure as a PDF document stream and returns as
in a scalar.

=cut

sub toPDF
{
   my $doc = shift;

   if ($doc->needsSave())
   {
      $doc->cleansave();
   }
   return $doc->{content};
}
#------------------

=item toString

Returns a serialized representation of the data structure.
Implemented via Data::Dumper.

=cut

sub toString
{
   my $doc = shift;

   my %hold = ();
   foreach my $key (qw(content crypt))
   {
      $hold{$key} = delete $doc->{$key};
   }

   require Data::Dumper;
   my $result = Data::Dumper->Dump([$doc], [qw(doc)]);

   foreach my $key (keys %hold)
   {
      $doc->{$key} = $hold{$key};
   }
   return $result;
}

################################################################################

=back

=head2 Document reading

(all of these functions are internal only)

=over 4

=cut


#------------------
# PRIVATE FUNCTION
#  read the document index and some metadata

sub startdoc
{
   my $doc = shift;
   
   ### Parse the document metadata

   # Start by parsing out the location of the last xref block
   if ($doc->{content} !~ /startxref\s*(\d+)\s*%%EOF\s*$/s)
   {
      $CAM::PDF::errstr = "Cannot find the index in the PDF content";
      return undef;
   }

   warn "got eof\n" if ($speedtesting);

   # Parse the hierarchy of xref blocks
   $doc->{startxref} = $1;
   $doc->{trailer} = $doc->buildxref($doc->{startxref}, $doc->{xref}, $doc->{versions});
   if (!defined $doc->{trailer})
   {
      return undef;
   }

   warn "got xref\n" if ($speedtesting);

   ### Cache some page content descriptors

   # Get the document root catalog
   if (!exists $doc->{trailer}->{Root})
   {
      $CAM::PDF::errstr = "No root node present in PDF trailer.\n";
      return undef;
   }
   $doc->{Root} = $doc->getValue($doc->{trailer}->{Root});
   if ((!$doc->{Root}) || (ref $doc->{Root} ne "HASH"))
   {
      $CAM::PDF::errstr = "The PDF root node is not a dictionary.\n";
      return undef;
   }

   warn "got root\n" if ($speedtesting);

   # Get the root of the page tree
   if (!exists $doc->{Root}->{Pages})
   {
      $CAM::PDF::errstr = "The PDF root node doesn't have a reference to the page tree.\n";
      return undef;
   }
   $doc->{Pages} = $doc->getValue($doc->{Root}->{Pages});
   if ((!$doc->{Root}) || (ref $doc->{Root} ne "HASH"))
   {
      $CAM::PDF::errstr = "The PDF page tree root is not a dictionary.\n";
      return undef;
   }

   warn "got pageroot\n" if ($speedtesting);

   # Get the number of pages in the document
   $doc->{PageCount} = $doc->getValue($doc->{Pages}->{Count});
   if ((!$doc->{PageCount}) || $doc->{PageCount} < 1)
   {
      $CAM::PDF::errstr = "Bad number of pages in PDF document\n";
      return undef;
   }

   warn "got page count\n" if ($speedtesting);

   return 1;
}

#------------------
# PRIVATE FUNCTION
#  read document index

sub buildxref
{
   my $doc = shift;
   my $startxref = shift;
   my $index = shift;
   my $versions = shift;

   warn "  do xref " . ($main::nxref++) . "\n" if ($speedtesting);

   my $trailerpos = index($doc->{content}, "trailer", $startxref);
   if ($trailerpos > 0 && $trailerpos < $startxref)  # workaround for 5.6.1 bug
   {
      $trailerpos = index(substr($doc->{content}, $startxref), "trailer") + $startxref;
}
   my $end = substr $doc->{content}, $startxref, $trailerpos-$startxref;

   warn "    got end\n" if ($speedtesting);

   if ($end !~ s/^xref\s+//s)
   {
      #$CAM::PDF::errstr = "Could not find PDF cross-ref table at location $startxref\n" . $doc->trimstr($end);
      $CAM::PDF::errstr = "Could not find PDF cross-ref table at location $startxref/$trailerpos/".length($end)."\n" . $doc->trimstr($end);
      return undef;
   }
   my $part = 0;
   while ($end =~ s/^(\d+)\s+(\d+)\s+//s)
   {
      my $s = $1;
      my $n = $2;

      $part++;
      warn "    do part $part: $s $n\n" if ($speedtesting);

      for (my $i = 0; $i < $n; $i++)
      {
         my $objnum = $s+$i;
         next if (exists $index->{$objnum});

         my $row = substr $end, $i*20, 20;
         if ($row !~ /^(\d{10}) (\d{5}) (\w)/)
         {
            $CAM::PDF::errstr = "Could not decipher xref row:\n" . $doc->trimstr($row);
            return undef;
         }
         if ($3 eq "n")
         {
            $index->{$objnum} = $1;
            $versions->{$objnum} = $2;
         }
         if ($objnum > $doc->{maxobj})
         {
            $doc->{maxobj} = $objnum;
         }
      }

      warn "    done part $part\n" if ($speedtesting);

      $end = substr $end, 20*$n;
   }

   warn "  done xref block\n" if ($speedtesting);

   my $sxrefpos = index $doc->{content}, "startxref", $trailerpos;
   if ($sxrefpos > 0 && $sxrefpos < $trailerpos)  # workaround for 5.6.1 bug
   {
      $sxrefpos = index(substr($doc->{content}, $trailerpos), "startxref") + $trailerpos;
   }
   $end = substr $doc->{content}, $trailerpos, $sxrefpos-$trailerpos;

   warn "  do trailer\n" if ($speedtesting);

   if ($end !~ s/^trailer\s*//s)
   {
      $CAM::PDF::errstr = "Did not find expected trailer block after xref\n" . $doc->trimstr($end);
      return undef;
   }
   my $trailer = $doc->parseDict(\$end)->{value};
   if (exists $trailer->{Prev})
   {
      if (!$doc->buildxref($trailer->{Prev}->{value}, $index, $versions))
      {
         return undef;
      }
   }
   return $trailer;
}

#------------------
# PRIVATE FUNCTION
# buildendxref -- compute the end of each object
#    note that this is not always the *actual* end of the object, but
#    we guarantee that the object will end at or before this point.

sub buildendxref
{
   my $doc = shift;

   my $r = {};
   warn "  reverse" if ($speedtesting);
   my %rev = reverse %{$doc->{xref}};
   warn "  sort" if ($speedtesting);
   my @pos = sort keys %rev;
   warn "  loop" if ($speedtesting);
   for (my $i = 0; $i < $#pos; $i++)
   {
      # set the end of each object to be the beginning of the next object
      $r->{$rev{$pos[$i]}} = $pos[$i+1];
   }
   # The end of the last object is the end of the file
   $r->{$rev{$pos[$#pos]}} = $doc->{contentlength};

   warn "  done" if ($speedtesting);

   $doc->{endxref} = $r;
}

#------------------
# PRIVATE FUNTION
# buildNameTable -- descend into the page tree and extract all XObject
# and Font name references.

sub buildNameTable
{
   my $doc = shift;
   my $pagenum = shift;

   if ((!$pagenum) || $pagenum eq "All")   # Build the ENTIRE name table
   {
      $doc->cacheObjects();
      foreach my $p (1 .. $doc->{PageCount})
      {
         $doc->buildNameTable($p);
      }
      my %n = ();
      foreach my $obj (values %{$doc->{objcache}})
      {
         if ($obj->{value}->{type} eq "dictionary")
         {
            my $dict = $obj->{value}->{value};
            if ($dict->{Name})
            {
               $n{$dict->{Name}->{value}} = CAM::PDF::Node->new("reference", $obj->{objnum});
            }
         }
      }
      $doc->{Names}->{All} = {%n};
      return;
   }

   return if (exists $doc->{Names}->{$pagenum});

   my %n = ();
   my $page = $doc->getPage($pagenum);
   do {
      my $objnum = $doc->getPageObjnum($pagenum);
      if (exists $page->{Resources})
      {
         my $r = $doc->getValue($page->{Resources});
         foreach my $key ("XObject", "Font")
         {
            if (exists $r->{$key})
            {
               my $x = $doc->getValue($r->{$key});
               if (ref $x eq "HASH")
               {
                  %n = (%$x, %n);
               }
            }
         }
      }

      # Inherit from parent
      $page = $page->{Parent};
      if ($page)
      {
         $page = $doc->getValue($page);
      }
   } while ($page);

   $doc->{Names}->{$pagenum} = {%n};
}

#------------------
# PRIVATE FUNCTION

sub parseObj
{
   my $doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   if ($$c !~ /\G(\d+)\s+(\d+)\s+obj\s*/scg)
   {
      die "Expected object open tag\n" . $doc->trimstr($$c);
   }
   $objnum = $1;
   $gennum = $2;

   my $obj;
   if ($$c =~ /\G(.*?)endobj\s*/scg)
   {
      my $string = $1;
      $obj = $doc->parseAny(\$string, $objnum, $gennum);
      if ($string =~ /\Gstream/)
      {
         if ($obj->{type} ne "dictionary")
         {
            die "Found an object stream without a preceding dictionary\n" . $doc->trimstr($$c);
         }
         $obj->{value}->{StreamData} = $doc->parseStream(\$string, $objnum, $gennum, $obj->{value});
      }
   }
   else
   {
      die "Expected endobj\n" . $doc->trimstr($$c);
   }
   return CAM::PDF::Node->new("object", $obj, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseInlineImage
{
   my $doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   if ($$c !~ /\GBI\b/s)
   {
      die "Expected inline image open tag\n" . $doc->trimstr($$c);
   }
   my $dict = $doc->parseDict($c, $objnum, $gennum, "BI\\b\\s*", "ID\\b");
   $doc->unabbrevInlineImage($dict);
   $dict->{value}->{Type} = CAM::PDF::Node->new("label", "XObject", $objnum, $gennum);
   $dict->{value}->{Subtype} = CAM::PDF::Node->new("label", "Image", $objnum, $gennum);
   $dict->{value}->{StreamData} = $doc->parseStream($c, $objnum, $gennum, $dict->{value}, "\\s*", "\\s*EI\\b");
   $$c =~ /\G\s+/scg;

   return CAM::PDF::Node->new("object", $dict, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION
#   This is the inverse of parseInlineImage, intended for use only in
#   the CAM::PDF::Content class
sub writeInlineImage
{
   my $doc = shift;
   my $obj = shift;

   # Make a copy since we are going to trash the image
   my $dictobj = $doc->copyObject($obj)->{value};

   my $dict = $dictobj->{value};
   delete $dict->{Type};
   delete $dict->{Subtype};
   my $stream = $dict->{StreamData}->{value};
   delete $dict->{StreamData};
   $doc->abbrevInlineImage($dictobj);
   #$dict->{L} ||= CAM::PDF::Node->new("number", length($stream));
   
   my $str = $doc->writeAny($dictobj);
   $str =~ s/^<</BI /s;
   $str =~ s/>>$/ ID/s;
   $str .= "\n" . $stream . "\nEI";
   return $str;
}

#------------------
# PRIVATE FUNCTION

sub parseStream
{
   my $doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;
   my $dict = shift;

   my $begin = shift || "stream\\r?\\n";
   my $end = shift || "\\s*endstream\\s*";

   if ($$c !~ /\G$begin/scg)
   {
      die "Expected stream open tag\n" . $doc->trimstr($$c);
   }

   my $stream;

   my $l = $dict->{Length} || $dict->{L};
   if (!defined $l)
   {
      if ($begin =~ /\Gstream/)
      {
         die "Missing stream length\n" . $doc->trimstr($$c);
      }
      if ($$c =~ /\G$begin(.*?)$end/scg)
      {
         $stream = $1;
         $dict->{Length} = CAM::PDF::Node->new("number", length($stream), $objnum, $gennum);
      }
      else
      {
         die "Missing stream begin/end\n" . $doc->trimstr($$c);
      }
   }
   else
   {
      my $length = $doc->getValue($l);
      $stream = substr $$c, pos($$c), $length;
      pos($$c) += $length;
      if ($$c !~ /\G$end/scg)
      {
         die "Expected endstream\n" . $doc->trimstr($$c);
      }
   }

   $stream = $doc->{crypt}->decrypt($stream, $objnum, $gennum) if (ref($doc) && $doc->{crypt});

   return CAM::PDF::Node->new("stream", $stream, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseDict
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $begin = shift || "<<\\s*";
   my $end = shift || ">>\\s*";

   my $dict = {};
   if ($$c =~ /\G$begin/scg)
   {
      while ($$c !~ /\G$end/scg)
      {
         #warn "looking for label:\n" . $pkg_or_doc->trimstr($$c);
         my $keyref = $pkg_or_doc->parseLabel($c, $objnum, $gennum);
         my $key = $keyref->{value};
         #warn "looking for value:\n" . $pkg_or_doc->trimstr($$c);
         my $value = $pkg_or_doc->parseAny($c, $objnum, $gennum);
         $$dict{$key} = $value;
      }
   }

   return CAM::PDF::Node->new("dictionary", $dict, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseArray
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $array = [];
   if ($$c =~ /\G\[\s*/scg)
   {
      while ($$c !~ /\G\]\s*/scg)
      {
         #warn "looking for array value:\n" . $pkg_or_doc->trimstr($$c);
         push @$array, $pkg_or_doc->parseAny($c, $objnum, $gennum);
      }
   }

   return CAM::PDF::Node->new("array", $array, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseLabel
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $label;
   if ($$c =~ /\G\/([^\s<>\/\[\]\(\)]+)\s*/scg)
   {
      $label = $1;
   }
   else
   {
      die "Expected identifier label:\n" . $pkg_or_doc->trimstr($$c);
   }
   return CAM::PDF::Node->new("label", $label, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseRef
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $newobjnum;
   if ($$c =~ /\G(\d+)\s+\d+\s+R\s*/scg)
   {
      $newobjnum = $1;
   }
   else
   {
      die "Expected object reference\n" . $pkg_or_doc->trimstr($$c);
   }
   return CAM::PDF::Node->new("reference", $newobjnum, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseNum
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $value;
   if ($$c =~ /\G([\d\.\-\+]+)\s*/scg)
   {
      $value = $1;
   }
   else
   {
      die "Expected numerical constant\n" . $pkg_or_doc->trimstr($$c);
   }
   return CAM::PDF::Node->new("number", $value, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseString
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $value = "";
   if ($$c =~ /\G\(/)
   {
      while ($$c =~ /\G\(/scg)
      {
         my $depth = 1;
         while ($depth > 0)
         {
            if ($$c =~ /\G([^\(\)]*)([\(\)])/scg)
            {
               my $string = $1;
               my $delim = $2;
               $value .= $string;
               
               # Make sure this is not an escaped paren, OR an real paren
               # preceded by an escaped backslash!
               if ($string =~ /(\\+)$/ && (length($1) % 2) == 1)
               {
                  $value .= $delim;
               }
               elsif ($delim eq "(")
               {
                  $value .= $delim;
                  $depth++;
               }
               elsif(--$depth > 0)
               {
                  $value .= $delim;
               }
            }
            else
            {
               die "Expected string closing\n" . $pkg_or_doc->trimstr($$c);
            }
         }
         $$c =~ /\G\s*/scg;
      }
   }
   else
   {
      die "Expected string opener\n" . $pkg_or_doc->trimstr($$c);
   }

   # Unescape slash-escaped characters.  Treat \\ specially.
   my @parts = split /\\\\/s, $value;
   foreach (@parts)
   {
      # concatenate continued lines
      s/\\\r?\n//sg;
      s/\\\r//sg;

      # special characters
      s/\\n/\n/g;
      s/\\r/\r/g;
      s/\\t/\t/g;
      s/\\f/\f/g;
      # TODO: handle backspace char
      #s/\\b/???/g;

      # octal numbers
      s/\\(\d{1,3})/chr(oct($1))/ge;

      # Ignore all other slashes (i.e. following characters are treated literally)
      s/\\//g;
   }
   $value = join("\\", @parts);

   $value = $pkg_or_doc->{crypt}->decrypt($value, $objnum, $gennum) if (ref($pkg_or_doc) && $pkg_or_doc->{crypt});

   return CAM::PDF::Node->new("string", $value, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseHexString
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $str = "";
   if ($$c =~ /\G<([\da-fA-F]*)>\s*/scg)
   {
      $str = $1;
      $str .= "0" if (length($str) % 2 == 1);
      $str = pack "H*", $str;
   }
   else
   {
     die "Expected hex string\n" . $pkg_or_doc->trimstr($$c);
   }

   $str = $pkg_or_doc->{crypt}->decrypt($str, $objnum, $gennum) if (ref($pkg_or_doc) && $pkg_or_doc->{crypt});

   return CAM::PDF::Node->new("hexstring", $str, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseBoolean
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $val = "";
   if ($$c =~ /\G(true|false)\s*/scgi)
   {
      $val = lc $1;
   }
   else
   {
     die "Expected boolean true or false keyword\n" . $pkg_or_doc->trimstr($$c);
   }

   return CAM::PDF::Node->new("boolean", $val, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseNull
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $val = "";
   if ($$c =~ /\Gnull\s*/scgi)
   {
      $val = undef;
   }
   else
   {
     die "Expected null keyword\n" . $pkg_or_doc->trimstr($$c);
   }

   return CAM::PDF::Node->new("null", $val, $objnum, $gennum);
}

#------------------
# PRIVATE FUNCTION

sub parseAny
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   if ($$c =~ /\G\d+\s+\d+\s+R\b/s)
   {
      return $pkg_or_doc->parseRef($c, $objnum, $gennum);
   }
#   elsif ($$c =~ /\G(\d+)\s+(\d+)\s+obj\b/s)
#   {
#      return $pkg_or_doc->parseObj($c, $1, $2);
#   }
   elsif ($$c =~ /\G\//)
   {
      return $pkg_or_doc->parseLabel($c, $objnum, $gennum);
   }
   elsif ($$c =~ /\G<</)
   {
      return $pkg_or_doc->parseDict($c, $objnum, $gennum);
   }
   elsif ($$c =~ /\G\[/)
   {
      return $pkg_or_doc->parseArray($c, $objnum, $gennum);
   }
   elsif ($$c =~ /\G\(/)
   {
      return $pkg_or_doc->parseString($c, $objnum, $gennum);
   }
   elsif ($$c =~ /\G\</)
   {
      return $pkg_or_doc->parseHexString($c, $objnum, $gennum);
   }
   elsif ($$c =~ /\G[\d\.\-\+]+/)
   {
      return $pkg_or_doc->parseNum($c, $objnum, $gennum);
   }
   elsif ($$c =~ /\G(true|false)/i)
   {
      return $pkg_or_doc->parseBoolean($c, $objnum, $gennum);
   }
   elsif ($$c =~ /\Gnull/i)
   {
      return $pkg_or_doc->parseNull($c, $objnum, $gennum);
   }
   else
   {
      die "Unrecognized type in parseAny:\n" . $pkg_or_doc->trimstr($$c);
   }
}

################################################################################

=back

=head2 Data Accessors

=over 4

=cut


#------------------

=item getValue OBJECT

I<For INTERNAL use>

Dereference a data object, return a value.  Given an node object
of any kind, returns raw scalar object: hashref, arrayref, string,
number.  This function follows all references, and descends into all
objects.

=cut

sub getValue
{
   my $doc = shift;
   my $obj = shift;

   return undef if (!ref $obj);

   #require Data::Dumper;
   #warn Data::Dumper->Dump([$obj], ["getvalue"]);

   while ($obj->{type} eq "reference" || $obj->{type} eq "object")
   {
      if ($obj->{type} eq "reference")
      {
         my $objnum = $obj->{value};
         $obj = $doc->dereference($objnum);
      }
      if ($obj->{type} eq "object")
      {
         $obj = $obj->{value};
      }
      return undef if (!ref $obj);
   }

   return $obj->{value};
}

#------------------

=item getObjValue OBJECTNUM

I<For INTERNAL use>

Dereference a data object, and return a value.  Behaves just like the
getValue() function, but used when all you know is the object number.

=cut

sub getObjValue
{
   my $doc = shift;
   my $objnum = shift;

   return $doc->getValue(CAM::PDF::Node->new("reference", $objnum));
}


#------------------

=item dereference OBJECTNUM

=item dereference NAME, PAGENUM

I<For INTERNAL use>

Dereference a data object, return a PDF object as an node.  This
function makes heavy use of the internal object cache.  Most (if not
all) object requests should go through this function.

NAME should look something like '/R12'.

=cut

sub dereference
{
   my $doc = shift;
   my $key = shift;
   my $pagenum = shift; # only used if $key is a named resource

   if ($key =~ s/^\///)  # strip off the leading slash while testing
   {
      # This is a request for a named object
      $doc->buildNameTable($pagenum);
      $key = $doc->{Names}->{$pagenum}->{$key};
      return undef if (!defined $key);
      # $key should now point to a "reference" object
      if (ref $key ne "CAM::PDF::Node")
      {
         die "Assertion failed: key is a reference object in dereference\n";
      }
      #require Data::Dumper;
      #warn Data::Dumper->Dump([$key], ["key"]);
      $key = $key->{value};
   }

   if (!exists $doc->{objcache}->{$key})
   {
      #print "Filling cache for obj \#$key...\n";

      my $pos = $doc->{xref}->{$key};

      if (!$pos)
      {
         warn "Bad request for object $key at position 0 in the file\n";
         return undef;
      }

      ## This is the old method.  It is slow.  Below is faster.
      #my $end = substr $doc->{content}, $pos;

      ## This is faster, but disastrous if "endobj" is a string in the obj!!!
      #$endpos = index $doc->{content}, "endobj", $pos;
      #if ($endpos == -1)
      #{
      #   die "Didn't find endobj after obj\n";
      #}

      # This is fastest and safest
      $doc->buildendxref() if (!exists $doc->{endxref});
      my $endpos = $doc->{endxref}->{$key};
      if ((!defined $endpos) || $endpos < $pos)
      {
         # really slow, but a totally safe fallback
         $endpos = $doc->{contentlength};
      }

      my $end = substr $doc->{content}, $pos, $endpos - $pos + 6;
      $doc->{objcache}->{$key} = $doc->parseObj(\$end, $key);
   }

   return $doc->{objcache}->{$key};
}


#------------------

=item getPropertyNames PAGENUM

=item getProperty PAGENUM, PROPERTYNAME

Each PDF page contains a list of resources that it uses (images,
fonts, etc).  getPropertyNames() returns an array of the names of
those resources.  getProperty() returns a node representing a
named property (most likely a reference node).

=cut

sub getPropertyNames
{
   my $doc = shift;
   my $pagenum = shift;

   $doc->buildNameTable($pagenum);
   my $props = $doc->{Names}->{$pagenum};
   return () if (!defined $props);
   return keys %$props;
}
sub getProperty
{
   my $doc = shift;
   my $pagenum = shift;
   my $name = shift;

   $doc->buildNameTable($pagenum);
   my $props = $doc->{Names}->{$pagenum};
   return undef if (!defined $props);
   return undef if (!defined $name);
   return $props->{$name};
}

#------------------

=item getFont PAGENUM, FONTNAME

I<For INTERNAL use>

Returns a dictionary for a given font identified by its label,
referenced by page.

=cut

sub getFont
{
   my $doc = shift;
   my $pagenum = shift;
   my $fontname = shift;

   $fontname =~ s|^/?|/|; # add leading slash if needed
   my $obj = $doc->dereference($fontname, $pagenum);
   return undef if (!$obj);

   my $dict = $doc->getValue($obj);
   if ($dict && $dict->{Type} && $dict->{Type}->{value} eq "Font")
   {
      return $dict;
   }
   else
   {
      return undef;
   }
}

#------------------

=item getFontNames PAGENUM

I<For INTERNAL use>

Returns a list of fonts for a given page.

=cut

sub getFontNames
{
   my $doc = shift;
   my $pagenum = shift;

   $doc->buildNameTable($pagenum);
   my $list = $doc->{Names}->{$pagenum};
   my @names;
   if ($list)
   {
      foreach my $key (keys %$list)
      {
         my $dict = $doc->getValue($list->{$key});
         if ($dict && $dict->{Type} && $dict->{Type}->{value} eq "Font")
         {
            push @names, $key;
         }
      }
   }
   return @names;
}


=item getFonts PAGENUM

I<For INTERNAL use>

Returns an array of font objects for a given page.

=cut

sub getFonts
{
   my $doc = shift;
   my $pagenum = shift;

   $doc->buildNameTable($pagenum);
   my $list = $doc->{Names}->{$pagenum};
   my @fonts;
   if ($list)
   {
      foreach my $key (keys %$list)
      {
         my $dict = $doc->getValue($list->{$key});
         if ($dict && $dict->{Type} && $dict->{Type}->{value} eq "Font")
         {
            push @fonts, $dict;
         }
      }
   }
   return @fonts;
}

#------------------

=item getFontByBaseName PAGENUM, FONTNAME

I<For INTERNAL use>

Returns a dictionary for a given font, referenced by page and the name
of the base font.

=cut

sub getFontByBaseName
{
   my $doc = shift;
   my $pagenum = shift;
   my $fontname = shift;

   $doc->buildNameTable($pagenum);
   my $list = $doc->{Names}->{$pagenum};
   foreach my $key (keys %$list)
   {
      my $num = $list->{$key}->{value};
      my $obj = $doc->dereference($num);
      my $dict = $doc->getValue($obj);
      if ($dict &&
          $dict->{Type} && $dict->{Type}->{value} eq "Font" &&
          $dict->{BaseFont} && $dict->{BaseFont}->{value} eq $fontname)
      {
         return $dict;
      }
   }
   return undef;
}
#------------------

=item getFontMetrics PROPERTIES FONTNAME

I<For INTERNAL use>

Returns a data structure representing the font metrics for the named
font.  The property list is the results of something like the
following:

  $doc->buildNameTable($pagenum);
  my $properties = $doc->{Names}->{$pagenum};

Alternatively, if you know the page number, it might be easier to do:

  my $font = $doc->dereference($fontlabel, $pagenum);
  my $fontmetrics = $font->{value}->{value};

where the fontlabel is something like "/Helv".  The getFontMetrics
method is useful in the cases where you've forgotten which page number
you are working on (e.g. in CAM::PDF::GS), or if your property list
isn't part of any page (e.g. working with form field annotation
objects).

=cut

sub getFontMetrics
{
   my $doc = shift;
   my $props = shift;
   my $fontname = shift;

   my $fontmetrics;

   #print STDERR "looking for font $fontname\n";

   # Sometimes we are passed just the object list, sometimes the whole
   # properties data structure
   if ($props->{Font})
   {
      $props = $doc->getValue($props->{Font});
   }

   if ($props->{$fontname})
   {
      my $fontdict = $doc->getValue($props->{$fontname});
      if ($fontdict && $fontdict->{Type} && $fontdict->{Type}->{value} eq "Font")
      {
         $fontmetrics = $fontdict;
         #print STDERR "Got font\n";
      }
      else
      {
         #print STDERR "Almost got font\n";
      }
   }
   else
   {
      #print STDERR "No font with that name in the dict\n";
   }
   #print STDERR "Failed to get font\n" unless($fontmetrics);
   return $fontmetrics;
}
#------------------

=item addFont PAGENUM, FONTNAME, FONTLABEL

=item addFont PAGENUM, FONTNAME, FONTLABEL, FONTMETRICS

Adds a reference to the specified font to the page.

If a fontmetrics hash is supplied (it is required for a font other
than the 14 core fonts), then it is cloned and inserted into the new
font structure.  Note that if those fontmetrics contain references
(e.g. to the FontDescriptor), the referred objects are not copied --
you must do that part yourself.

For Type1 fonts, the fontmetrics must minimally contain the following
fields: C<Subtype>, C<FirstChar>, C<LastChar>, C<Widths>,
C<FontDescriptor>.

=cut

sub addFont
{
   my $doc = shift;
   my $pagenum = shift;
   my $name = shift;
   my $label = shift;
   my $fontmetrics = shift; # optional

   # Check if this font already exists
   my $page = $doc->getPage($pagenum);
   if (exists $page->{Resources})
   {
      my $r = $doc->getValue($page->{Resources});
      if (exists $r->{Font})
      {
         my $f = $doc->getValue($r->{Font});
         if (exists $f->{$label})
         {
            # Font already exists.  Skip.
            return $doc;
         }
      }
   }

   # Build the font
   my $dict = CAM::PDF::Node->new("dictionary",
                                 {
                                    Type => CAM::PDF::Node->new("label", "Font"),
                                    Name => CAM::PDF::Node->new("label", $label),
                                    BaseFont => CAM::PDF::Node->new("label", $name),
                                 },
                                 );
   if ($fontmetrics)
   {
      my $copy = $doc->copyObject($fontmetrics);
      foreach my $key (keys %$copy)
      {
         if (!$dict->{value}->{$key})
         {
            $dict->{value}->{$key} = $copy->{$key};
         }
      }
   }
   else
   {
      $dict->{value}->{Subtype} = CAM::PDF::Node->new("label", "Type1");
   }

   # Add the font to the document
   my $fontobjnum = $doc->appendObject(undef, CAM::PDF::Node->new("object", $dict), 0);

   # Add the font to the page
   my ($objnum,$gennum) = $doc->getPageObjnum($pagenum);
   if (!exists $page->{Resources})
   {
      $page->{Resources} = CAM::PDF::Node->new("dictionary", {}, $objnum, $gennum);
   }
   my $r = $doc->getValue($page->{Resources});
   if (!exists $r->{Font})
   {
      $page->{Font} = CAM::PDF::Node->new("dictionary", {}, $objnum, $gennum);
   }
   my $f = $doc->getValue($r->{Font});
   $f->{$label} = CAM::PDF::Node->new("reference", $fontobjnum, $objnum, $gennum);

   delete $doc->{Names}->{$pagenum}; # decache
   $doc->{changes}->{$objnum} = 1;
   return $doc;
}

#------------------

=item deEmbedFont PAGENUM, FONTNAME

=item deEmbedFont PAGENUM, FONTNAME, BASEFONT

Removes embedded font data, leaving font reference intact.  Returns
true if the font exists and 1) font is not embedded or 2) embedded
data was successfully discarded.  Returns false if the font does not
exist, or the embedded data could not be discarded.

The optional basefont parameter allows you to change the font.  This
is useful when some applications embed a standard font (see below) and
give it a funny name, like "SYLXNP+Helvetica".  In this example, it's
important to change the basename back to the standard "Helvetica" when
dembedding.

De-embedding the font does NOT remove it from the PDF document, it
just removes references to it.  To get a size reduction by throwing
away unused font data, you should use the following code sometime
after this method.

  $doc->cleanse();

For reference, the standard fonts are Times-Roman, Helvetica, and
Courier (and their bold, italic and bold-italic forms) plus Symbol and
Zapfdingbats. (Adobe PDF Reference v1.4, p.319)

=cut

sub deEmbedFont
{
   my $doc = shift;
   my $pagenum = shift;
   my $fontname = shift;
   my $basefont = shift;

   my $success;
   my $font = $doc->getFont($pagenum, $fontname);
   if ($font)
   {
      $doc->deEmbedFontObj($font, $basefont);
      $success = $doc;
   }
   else
   {
      $success = undef;
   }
   return $success;
}
#------------------

=item deEmbedFontByBaseName PAGENUM, FONTNAME

=item deEmbedFontByBaseName PAGENUM, FONTNAME, BASEFONT

Just like deEmbedFont(), except that the font name parameter refers to
the name of the current base font instead of the PDF label for the
font.

=cut

sub deEmbedFontByBaseName
{
   my $doc = shift;
   my $pagenum = shift;
   my $fontname = shift;
   my $basefont = shift;

   my $success;
   my $font = $doc->getFontByBaseName($pagenum, $fontname);
   if ($font)
   {
      $doc->deEmbedFontObj($font, $basefont);
      $success = $doc;
   }
   else
   {
      $success = undef;
   }
   return $success;
}
#------------------
sub deEmbedFontObj
{
   my $doc = shift;
   my $font = shift;
   my $basefont = shift;
   
   if ($basefont)
   {
      $font->{BaseFont} = CAM::PDF::Node->new("label", $basefont);
   }
   delete $font->{FontDescriptor};
   delete $font->{Widths};
   delete $font->{FirstChar};
   delete $font->{LastChar};
   $doc->{changes}->{$font->{Type}->{objnum}} = 1;
}
#------------------

=item wrapString STRING, WIDTH, FONTSIZE, FONTMETRICS

=item wrapString STRING, WIDTH, FONTSIZE, PAGENUM, FONTLABEL

Returns an array of strings wrapped to the specified width.

=cut

sub wrapString
{
   my $doc = shift;
   my $string = shift;
   my $width = shift;
   my $size = shift;

   my $fm;
   if (defined $_[0] && ref($_[0]))
   {
      $fm = shift;
   }
   else
   {
      my $pagenum = shift;
      my $fontlabel = shift;
      $fm = $doc->getFont($pagenum, $fontlabel);
   }

   $string =~ s/\r\n/\n/gs;
   my @strings = split /[\r\n]/, $string;
   my @out;
   $width /= $size;
   #print STDERR "wrapping ".join("|",@strings)."\n";
   foreach my $s (@strings)
   {
      $s =~ s/\s+$//;
      my $w = $doc->getStringWidth($fm, $s);
      if ($w <= $width)
      {
         push @out, $s;
      }
      else
      {
         $s =~ s/^(\s*)//;
         my $cur = $1;
         my $curw = $cur eq "" ? 0 : $doc->getStringWidth($fm, $cur);
         while ($s)
         {
            $s =~ s/^(\s*)(\S*)//;
            my $sp = $1;
            my $wd = $2;
            my $wwd = $wd eq "" ? 0 : $doc->getStringWidth($fm, $wd);
            if ($curw == 0)
            {
               $cur = $wd;
               $curw = $wwd;
            }
            else
            {
               my $wsp = $sp eq "" ? 0 : $doc->getStringWidth($fm, $sp);
               if ($curw + $wsp + $wwd <= $width)
               {
                  $cur .= $sp . $wd;
                  $curw += $wsp + $wwd;
               }
               else
               {
                  push @out, $cur;
                  $cur = $wd;
                  $curw = $wwd;
               }
            }
         }
         if (length($cur) > 0)
         {
            push @out, $cur;
         }
      }
   }
   #print STDERR "wrapped to ".join("|",@out)."\n";
   return @out;
}
#------------------

=item getStringWidth FONTMETRICS, STRING

I<For INTERNAL use>

Returns the width of the string, using the font metrics if possible.

=cut

sub getStringWidth
{
   my $doc = shift;
   my $fontmetrics = shift;
   my $string = shift;

   return 0 if ((! defined $string) || $string eq "");

   my $width = 0;
   if ($fontmetrics)
   {
      if ($fontmetrics->{Widths})
      {
         my $first  = $doc->getValue($fontmetrics->{FirstChar});
         my $last   = $doc->getValue($fontmetrics->{LastChar});
         my $widths = $doc->getValue($fontmetrics->{Widths});
         my $missingWidth;
         my $fd;
         foreach my $char (unpack "C*", $string)
         {
            if ($char >= $first && $char <= $last)
            {
               $width += $widths->[$char - $first]->{value};
            }
            else
            {
               if (!defined $missingWidth)
               {
                  $missingWidth = 0; # fallback
                  if (!$fd)
                  {
                     if (exists $fontmetrics->{FontDescriptor})
                     {
                        $fd = $doc->getValue($fontmetrics->{FontDescriptor});
                     }
                  }
                  if ($fd)
                  {
                     if (exists $fd->{MissingWidth})
                     {
                        $missingWidth = $doc->getValue($fd->{MissingWidth});
                     }
                  }
               }
               $width += $missingWidth;
            }
         }
         $width /= 1000.0;  # units conversion
      }
      elsif ($fontmetrics->{BaseFont})
      {
         my $fontname = $doc->getValue($fontmetrics->{BaseFont});
         if (!exists $doc->{fontmetrics}->{$fontname})
         {
            require Text::PDF::SFont;
            require Text::PDF::File;
            my $pdf = Text::PDF::File->new();
            $doc->{fontmetrics}->{$fontname} =
                Text::PDF::SFont->new($pdf, $fontname, "NULL");
         }
         if ($doc->{fontmetrics}->{$fontname})
         {
            $width = $doc->{fontmetrics}->{$fontname}->width($string);
         }
      }
      else
      {
         warn "Can't comprehend this font";
      }
   }

   if ($width == 0)
   {
      # HACK!!!
      warn "Using klugy width!\n";
      $width = length($string)*0.2;
   }

   return $width;
}

#------------------

=item numPages

Returns the number of pages in the PDF document.

=cut

sub numPages
{
   my $doc = shift;
   return $doc->{PageCount};
}

#------------------

=item getPage PAGENUM

I<For INTERNAL use>

Returns a dictionary for a given numbered page.

=cut

sub getPage
{
   my $doc = shift;
   my $pagenum = shift;

   if ($pagenum < 1 || $pagenum > $doc->{PageCount})
   {
      warn "Invalid page number requested: $pagenum\n";
      return undef;
   }

   if (!exists $doc->{pagecache}->{$pagenum})
   {
      my $node = $doc->{Pages};
      my $nodestart = 1;
      while ($doc->getValue($node->{Type}) eq "Pages")
      {
         #warn "getPage: nodestart $nodestart\n";
         my $kids = $doc->getValue($node->{Kids});
         if (ref $kids ne "ARRAY")
         {
            die "Error: \@kids is not an array\n";
         }
         my $child = 0; 
         if (@$kids == 1)
         {
            #warn "getPage: just one kid\n";
            # Do the simple case first:
            $child = 0;
            # nodestart is unchanged
         }
         else
         {
            # search through all kids EXCEPT don't bother looking at
            # the last one because that is surely the right one if all
            # the others are wrong.
            
            #warn "getPage: checking kids\n";

            while ($child < $#$kids)
            {
               #warn "getPage:   checking kid $child of $#$kids\n";

               if ($pagenum == $nodestart)
               {
                  #warn "getPage:   match\n";
                  # the first leaf of the kid is the page we want.  It
                  # doesn't matter if the kid is a leaf or a node.
                  last;
               }

               # Retrieve the dictionary of this child
               my $sub = $doc->getValue($kids->[$child]);
               if ($sub->{Type}->{value} ne "Pages")
               {
                  #warn "getPage:   wrong leaf\n";
                  # Its a leaf, and not the right one.  Move on.
                  $nodestart++;
               }
               else
               {
                  my $count = $doc->getValue($sub->{Count});
                  if ($nodestart + $count - 1 >= $pagenum)
                  {
                     #warn "getPage:   descend\n";
                     # The page we want is in this kid.  Descend.
                     last;
                  }
                  else
                  {
                     #warn "getPage:   wrong node\n";

                     # Not in this kid.  Move on.
                     $nodestart += $count;
                  }
               }
               $child++;
            }
         }
         #warn "getPage: get new node\n";

         $node = $doc->getValue($kids->[$child]);
         if (!ref $node)
         {
            require Data::Dumper;
            Carp::cluck(Data::Dumper::Dumper($node));
         }
      }
      
      #warn "getPage: done\n";

      # Ok, now we've got the right page.  Store it.
      $doc->{pagecache}->{$pagenum} = $node;
   }

   return $doc->{pagecache}->{$pagenum};
}

#------------------

=item getPageObjnum PAGENUM

I<For INTERNAL use>

Return the number of the PDF object in which the specified page occurs.

=cut

sub getPageObjnum
{
   my $doc = shift;
   my $pagenum = shift;

   my $page = $doc->getPage($pagenum);
   return undef if (!$page);
   my ($anyobj) = values %$page;
   if (!$anyobj)
   {
      die "Internal error: page has no attributes!!!\n";
   }
   if (wantarray)
   {
      return ($anyobj->{objnum}, $anyobj->{gennum});
   }
   else
   {
      return $anyobj->{objnum};
   }
}   

#------------------

=item getPageText PAGENUM

Extracts the text from a PDF page as a string.

=cut

sub getPageText
{
   my $doc = shift;
   my $pagenum = shift;
   my $verbose = shift;

   my $pagetree = $doc->getPageContentTree($pagenum, $verbose);
   if (!$pagetree)
   {
      return undef;
   }

   #require Data::Dumper;
   #warn Data::Dumper->Dump([$pagetree], ["pagetree"]);

   my $str = "";
   my @stack = ([@{$pagetree->{blocks}}]);
   my $inBT = 0;
   while (@stack > 0)
   {
      my $node = $stack[-1];
      if (ref($node))
      {
         if (@$node > 0)
         {
            my $block = shift @$node;
            if ($block->{type} eq "block")
            {
               if ($block->{name} eq "BT")
               {
                  push @stack, "BT";
                  $inBT = 1;
               }
               push @stack, [@{$block->{value}}];  # descend
            }
            elsif ($inBT)
            {
               die "misconception" if ($block->{type} ne "op");
               my @args = @{$block->{args}};
               if ($block->{name} eq "TJ")
               {
                  die "Bad TJ" if (@args != 1 || $args[0]->{type} ne "array");

                  $str =~ s/(\S)$/$1 /s;
                  foreach my $node (@{$args[0]->{value}})
                  {
                     if ($node->{type} =~ /string/)
                     {
                        $str .= $node->{value};
                     }
                     elsif ($node->{type} eq "number")
                     {
                        # Heuristic:
                        #  "offset of more than a quarter unit forward"
                        # means significant positive spacing
                        if ($node->{value} < -250)
                        {
                           $str =~ s/(\S)$/$1 /s;
                        }
                     }
                  }
               }
               elsif ($block->{name} =~ /^Tj|\'|\"$/)
               {
                  die "Bad Tj" unless (@args >= 1 &&
                                       $args[-1]->{type} =~ /string$/);
                  if ($block->{name} eq "Tj")
                  {
                     $str =~ s/(\S)$/$1 /s;
                  }
                  else
                  {
                     $str =~ s/ *$/\n/s;
                  }
                  $str .= $args[-1]->{value};
               }
               elsif ($block->{name} eq "Td" || $block->{name} eq "TD")
               {
                  die "Bad Td/TD" unless (@args == 2 && 
                                          $args[0]->{type} eq "number" &&
                                          $args[1]->{type} eq "number");
                  # Heuristic:
                  #   "move down in Y, and Y motion a large fraction of the X motion"
                  # means new line
                  if ($args[1]->{value} < 0 && 2*abs($args[1]->{value}) > abs($args[0]->{value}))
                  {
                     $str =~ s/ *$/\n/s;
                  }
               }
               elsif ($block->{name} eq "T*")
               {
                  $str =~ s/ *$/\n/s;
               }
            }
         }
         else
         {
            pop @stack;
         }
      }
      else
      {
         $inBT = 0;
         $str =~ s/ *$/\n/s;
         pop @stack;
      }
   }
   return $str;
}
#------------------

=item getPageContentTree PAGENUM

Retrieves a parsed page content data structure, or undef if there is a
syntax error or if the page does not exist.

=cut

sub getPageContentTree
{
   my $doc = shift;
   my $pagenum = shift;
   my $verbose = shift;

   my $content = $doc->getPageContent($pagenum);
   return undef if (!defined $content);

   $doc->buildNameTable($pagenum);

   my $page = $doc->getPage($pagenum);
   my $box = [0, 0, 612, 792];
   if ($page->{MediaBox})
   {
      my $mediabox = $doc->getValue($page->{MediaBox});
      $box->[0] = $doc->getValue($mediabox->[0]);
      $box->[1] = $doc->getValue($mediabox->[1]);
      $box->[2] = $doc->getValue($mediabox->[2]);
      $box->[3] = $doc->getValue($mediabox->[3]);
   }

   require CAM::PDF::Content;
   my $tree = CAM::PDF::Content->new($content, {
      doc => $doc,
      properties => $doc->{Names}->{$pagenum},
      mediabox => $box,
   }, $verbose);

   return $tree;
}
#------------------

=item getPageContent PAGENUM

Return a string with the layout contents of one page.

=cut

sub getPageContent
{
   my $doc = shift;
   my $pagenum = shift;

   my $page = $doc->getPage($pagenum);
   if (!$page || !exists $page->{Contents})
   {
      return "";
   }

   my $contents = $doc->getValue($page->{Contents});

   if (!ref $contents)
   {
      return $contents;
   }
   elsif (ref $contents eq "HASH")
   {
      # doesn't matter if it's not encoded...
      return $doc->decodeOne(CAM::PDF::Node->new("dictionary", $contents));
   }
   elsif (ref $contents eq "ARRAY")
   {
      my $stream = "";
      foreach my $arrobj (@$contents)
      {
         my $data = $doc->getValue($arrobj);
         if (!ref $data)
         {
            $stream .= $data;
         }
         elsif (ref $data eq "HASH")
         {
            $stream .= $doc->decodeOne(CAM::PDF::Node->new("dictionary",$data));  # doesn't matter if it's not encoded...
         }
         else
         {
            die "Unexpected content type for page contents\n";
         }
      }
      return $stream;
   }
   else
   {
      die "Unexpected content type for page contents\n";
   }
}

#------------------

=item getName OBJECT

I<For INTERNAL use>

Given a PDF object reference, return it's name, if it has one.  This
is useful for indirect references to images in particular.

=cut

sub getName
{
   my $doc = shift;
   my $obj = shift;

   if ($obj->{value}->{type} eq "dictionary")
   {
      my $dict = $obj->{value}->{value};
      if (exists $dict->{Name})
      {
         return $doc->getValue($dict->{Name});
      }
   }
   return "";
}

#------------------

=item getPrefs

Return an array of security information for the document:

  owner password
  user password
  print boolean
  modify boolean
  copy boolean
  add boolean

See the PDF reference for the intended use of the latter four booleans.

This module publishes the array indices of these values for your
convenience:

  $CAM::PDF::PREF_OPASS
  $CAM::PDF::PREF_UPASS
  $CAM::PDF::PREF_PRINT
  $CAM::PDF::PREF_MODIFY
  $CAM::PDF::PREF_COPY
  $CAM::PDF::PREF_ADD

So, you can retrieve the value of the Copy boolean via:

  my ($canCopy) = ($doc->getPrefs())[$CAM::PDF::PREF_COPY];

=cut

sub getPrefs
{
   my $doc = shift;

   my @p = (1,1,1,1);
   if (exists $doc->{crypt}->{P})
   {
      @p = $doc->{crypt}->decode_permissions($doc->{crypt}->{P});
   }
   return($doc->{crypt}->{opass}, $doc->{crypt}->{upass}, @p);
}
#------------------

=item canPrint

Return a boolean indicating whether the Print permission is enabled
on the PDF.

=cut

sub canPrint
{
   my $doc = shift;
   return ($doc->getPrefs())[$PREF_PRINT];
}
#------------------

=item canModify

Return a boolean indicating whether the Modify permission is enabled
on the PDF.

=cut

sub canModify
{
   my $doc = shift;
   return ($doc->getPrefs())[$PREF_MODIFY];
}
#------------------

=item canCopy

Return a boolean indicating whether the Copy permission is enabled
on the PDF.

=cut

sub canCopy
{
   my $doc = shift;
   return ($doc->getPrefs())[$PREF_COPY];
}
#------------------

=item canAdd

Return a boolean indicating whether the Add permission is enabled
on the PDF.

=cut

sub canAdd
{
   my $doc = shift;
   return ($doc->getPrefs())[$PREF_ADD];
}
#------------------

=item getFormFieldList

Return an array of the names of all of the PDF form fields.  The names
are the full heirarchical names constructed as explained in the PDF
reference manual.  These names are useful for the fillFormFields()
function.

=cut

sub getFormFieldList
{
   my $doc = shift;
   my $parentname = shift;  # very optional

   my $prefix = (defined $parentname ? $parentname . "." : "");

   my $kidlist;
   if (defined $parentname && $parentname ne "")
   {
      my $parent = $doc->getFormField($parentname);
      return () if (!$parent);
      my $dict = $doc->getValue($parent);
      return () if (!exists $dict->{Kids});
      $kidlist = $doc->getValue($dict->{Kids});
   }
   else
   {
      my $root = $doc->{Root}->{AcroForm};
      return () if (!$root);
      my $parent = $doc->getValue($root);
      return () if (!exists $parent->{Fields});
      $kidlist = $doc->getValue($parent->{Fields});
   }

   my @list = ();
   foreach my $kid (@$kidlist)
   {
      if ((!ref($kid)) || ref($kid) ne "CAM::PDF::Node" || $kid->{type} ne "reference")
      {
         die "Expected a reference as the form child of '$parentname'\n";
      }
      my $obj = $doc->dereference($kid->{value});
      my $dict = $doc->getValue($obj);
      my $name = "(no name)";  # assume the worst
      if (exists $dict->{T})
      {
         $name = $doc->getValue($dict->{T});
      }
      $name = $prefix . $name;
      push @list, $name;
      if (exists $dict->{TU})
      {
         push @list, $prefix . $doc->getValue($dict->{TU}) . " (alternate name)";
      }
      $doc->{formcache}->{$name} = $obj;
      my @kidnames = $doc->getFormFieldList($name);
      if (@kidnames > 0)
      {
         #push @list, "descend...";
         push @list, @kidnames;
         #push @list, "ascend...";
      }
   }
   return @list;
}

#------------------

=item getFormField NAME

I<For INTERNAL use>

Return the object containing the form field definition for the
specified field name.  NAME can be either the full name or the
"short/alternate" name.

=cut

sub getFormField
{
   my $doc = shift;
   my $fieldname = shift;

   return undef if (!defined $fieldname);

   if (! exists $doc->{formcache}->{$fieldname})
   {
      my $kidlist;
      my $parent;
      if ($fieldname =~ /\./)
      {
         $fieldname =~ s/^(.*)\.([\.]+)$/$2/;
         my $parentname = $1;
         $parent = $doc->getFormField($parentname);
         return undef if (!$parent);
         my $dict = $doc->getValue($parent);
         return undef if (!exists $dict->{Kids});
         $kidlist = $doc->getValue($dict->{Kids});
      }
      else
      {
         my $root = $doc->{Root}->{AcroForm};
         return undef if (!$root);
         $parent = $doc->dereference($root->{value});
         return undef if (!$parent);
         my $dict = $doc->getValue($parent);
         return undef if (!exists $dict->{Fields});
         $kidlist = $doc->getValue($dict->{Fields});
      }

      $doc->{formcache}->{$fieldname} = undef;  # assume the worst...
      foreach my $kid (@$kidlist)
      {
         my $obj = $doc->dereference($kid->{value});
         $obj->{formparent} = $parent;
         my $dict = $doc->getValue($obj);
         if (exists $dict->{T})
         {
            $doc->{formcache}->{$doc->getValue($dict->{T})} = $obj;
         }
         if (exists $dict->{TU})
         {
            $doc->{formcache}->{$doc->getValue($dict->{TU})} = $obj;
         }
      }
   }

   return $doc->{formcache}->{$fieldname};
}

#------------------

=item getFormFieldDict FORMFIELDOBJECT

I<For INTERNAL use>

Return a hashreference representing the accumulated property list for
a formfield, including all of it's inherited properties.  This should
be treated as a read-only hash!  It ONLY retrieves the properties it
knows about.

=cut

sub getFormFieldDict
{
   my $doc = shift;
   my $field = shift;

   return undef if (!defined $field);

   my $dict = {};
   if ($field->{formparent})
   {
      $dict = $doc->getFormFieldDict($field->{formparent});
   }
   my $olddict = $doc->getValue($field);

   if ($olddict->{DR})
   {
      $dict->{DR} ||= CAM::PDF::Node->new("dictionary", {});
      my $dr = $doc->getValue($dict->{DR});
      my $olddr = $doc->getValue($olddict->{DR});
      foreach my $key (keys %{%$olddr})
      {
         if ($dr->{$key})
         {
            if ($key eq "Font")
            {
               my $fonts = $doc->getValue($olddr->{$key});
               foreach my $font (keys %$fonts)
               {
                  $dr->{$key}->{$font} = $doc->copyObject($fonts->{$font});
               }
            }
            else
            {
               warn "Unknown resource key '$key' in form field dictionary";
            }
         }
         else
         {
            $dr->{$key} = $doc->copyObject($olddr->{$key});
         }
      }
   }

   # Some properties are simple: inherit means override
   foreach my $prop (qw(Q DA Ff V FT))
   {
      if ($olddict->{$prop})
      {
         $dict->{$prop} = $doc->copyObject($olddict->{$prop});
      }
   }

   return $dict;
}

################################################################################

=back

=head2 Data/Object Manipulation

=over 4

=cut


#------------------

=item setPrefs OWNERPASS, USERPASS, PRINT?, MODIFY?, COPY?, ADD?

Alter the document's security information.  Note that modifying these
parameters must be done respecting the intellectual property of the
original document.  See Adobe's statement in the introduction of the
reference manual.

=cut

sub setPrefs
{
   my $doc = shift;
   my @prefs = (@_);

   my $p = $doc->{crypt}->encode_permissions(@prefs[2..5]);
   $doc->{crypt}->set_passwords(@prefs[0..1], $p);
}

#------------------

=item setName OBJECT, NAME

I<For INTERNAL use>

Change the name of a PDF object structure.

=cut

sub setName
{
   my $doc = shift;
   my $obj = shift;
   my $name = shift;

   if ($name && $obj->{value}->{type} eq "dictionary")
   {
      $obj->{value}->{value}->{Name} = CAM::PDF::Node->new("label", $name, $obj->{objnum}, $obj->{gennum});
      $doc->{changes}->{$obj->{objnum}} = 1 if ($obj->{objnum});
      return 1;
   }
   return 0;
}

#------------------

=item removeName OBJECT

I<For INTERNAL use>

Delete the name of a PDF object structure.

=cut

sub removeName
{
   my $doc = shift;
   my $obj = shift;

   if ($obj->{value}->{type} eq "dictionary" && exists $obj->{value}->{value}->{Name})
   {
      delete $obj->{value}->{value}->{Name};
      $doc->{changes}->{$obj->{objnum}} = 1 if ($obj->{objnum});
      return 1;
   }
   return 0;
}


#------------------

=item pageAddName PAGENUM, NAME, OBJECTNUM

I<For INTERNAL use>

Append a named object to the metadata for a given page.

=cut

sub pageAddName
{
   my $doc = shift;
   my $pagenum = shift;
   my $name = shift;
   my $key = shift;

   $doc->buildNameTable($pagenum);
   my $page = $doc->getPage($pagenum);
   my ($objnum, $gennum) = $doc->getPageObjnum($pagenum);
   
   if (!exists $doc->{NameObjects}->{$pagenum})
   {
      $doc->{changes}->{$objnum} = 1 if ($objnum);
      if (!exists $page->{Resources})
      {
         $page->{Resources} = CAM::PDF::Node->new("dictionary", {}, $objnum, $gennum);
      }
      my $r = $doc->getValue($page->{Resources});
      if (!exists $r->{XObject})
      {
         $r->{XObject} = CAM::PDF::Node->new("dictionary", {}, $objnum, $gennum);
      }
      $doc->{NameObjects}->{$pagenum} = $doc->getValue($r->{XObject});
   }
   
   $doc->{NameObjects}->{$pagenum}->{$name} = CAM::PDF::Node->new("reference", $key, $objnum, $gennum);
   $doc->{changes}->{$objnum} = 1 if ($objnum);
}

#------------------

=item setPageContent PAGENUM, CONTENT

Replace the content of the specified page with a new version.  This
function is often used after the getPageContent() function and some
manipulation of the returned string from that function.

=cut

sub setPageContent
{
   my $doc = shift;
   my $pagenum = shift;
   my $content = shift;

   # Note that this *could* be implemented as 
   #   delete current content
   #   appendPageContent
   # but that would lose the optimization below of reusing the content
   # object, where possible

   my $page = $doc->getPage($pagenum);

   my $stream = $doc->createStreamObject($content, "FlateDecode");
   if ($page->{Contents} && $page->{Contents}->{type} eq "reference")
   {
      my $key = $page->{Contents}->{value};
      $doc->replaceObject($key, undef, $stream, 0);
   }
   else
   {
      my ($objnum, $gennum) = $doc->getPageObjnum($pagenum);
      my $key = $doc->appendObject(undef, $stream, 0);
      $page->{Contents} = CAM::PDF::Node->new("reference", $key, $objnum, $gennum);
      $doc->{changes}->{$objnum} = 1;
   }
}

#------------------

=item appendPageContent PAGENUM, CONTENT

Add more content to the specified page.  Note that this function does
NOT do any page metadata work for you (like creating font objects for
any newly defined fonts).

=cut

sub appendPageContent
{
   my $doc = shift;
   my $pagenum = shift;
   my $content = shift;

   my $page = $doc->getPage($pagenum);

   my ($objnum, $gennum) = $doc->getPageObjnum($pagenum);
   my $stream = $doc->createStreamObject($content, "FlateDecode");
   my $key = $doc->appendObject(undef, $stream, 0);
   my $streamref = CAM::PDF::Node->new("reference", $key, $objnum, $gennum);

   if (!$page->{Contents})
   {
      $page->{Contents} = $streamref;
   }
   elsif ($page->{Contents}->{type} eq "array")
   {
      push @{$page->{Contents}->{value}}, $streamref;
   }
   elsif ($page->{Contents}->{type} eq "reference")
   {
      $page->{Contents} = CAM::PDF::Node->new("array", [ $page->{Contents}, $streamref ], $objnum, $gennum);
   }
   else
   {
      die "Unsupported Content type \"" . $page->{Contents}->{type} . "\" on page $pagenum\n";
   }
   $doc->{changes}->{$objnum} = 1;
}

#------------------

=item extractPages PAGES...

Remove all pages from the PDF except the specified ones.  Like
deletePages(), the pages can be multiple arguments, comma separated
lists, ranges (open or closed).

=cut

sub extractPages
{
   my $doc = shift;
   my @pages = $doc->rangeToArray(1,$doc->numPages(),@_);

   my %pages = map {$_,1} @pages; # eliminate duplicates

   # make a list that is the complement of the @pages list
   my @delete = grep {!$pages{$_}} 1..$doc->numPages();
   return $doc->deletePages(@delete);
}
#------------------

=item deletePages PAGES...

Remove the specified pages from the PDF.  The pages can be multiple
arguments, comma separated lists, ranges (open or closed).

=cut

sub deletePages
{
   my $doc = shift;
   my @pages = $doc->rangeToArray(1,$doc->numPages(),@_);

   my %pages = map {$_,1} @pages; # eliminate duplicates

   # Pages should be reverse sorted since we need to delete from the
   # end to make the page numbers come out right.

   foreach (sort {$b <=> $a} keys %pages)
   {
      #print "del $_\n";
      return undef unless ($doc->deletePage_internal($_));
   }
   $doc->cleanse();
   return $doc;
}
#------------------

=item deletePage PAGENUM

Remove the specified page from the PDF.  If the PDF has only one page,
this method will fail.

=cut

sub deletePage
{
   my $doc = shift;
   my $pagenum = shift;

   my $result = $doc->deletePage_internal($pagenum);
   $doc->cleanse() if ($result);
   return $result;
}
#------------------

# Internal method, called by deletePage() or deletePages()

sub deletePage_internal
{
   my $doc = shift;
   my $pagenum = shift;

   if ($doc->numPages() <= 1) # don't delete the last page
   {
      return undef;
   }
   my ($objnum, $gennum) = $doc->getPageObjnum($pagenum);
   return undef if (!defined $objnum);

   # Removing references to the page is hard:
   # (much of this code is lifted from getPage)
   my $parentdict = undef;
   my $node = $doc->dereference($doc->{Root}->{Pages}->{value});
   my $nodedict = $node->{value}->{value};
   my $nodestart = 1;
   while ($node && $nodedict->{Type}->{value} eq "Pages")
   {
      my $count;
      if ($nodedict->{Count}->{type} eq "reference")
      {
         my $countobj = $doc->dereference($nodedict->{Count}->{value});
         $count = $countobj->{value}->{value}--;
         $doc->{changes}->{$countobj->{objnum}} = 1;
      }
      else
      {
         $count = $nodedict->{Count}->{value}--;
      }
      $doc->{changes}->{$node->{objnum}} = 1;

      if ($count == 1)
      {
         # only one left, so this is it
         if (!$parentdict)
         {
            die "Tried to delete the only page";
         }
         my $parentkids = $doc->getValue($parentdict->{Kids});
         @$parentkids = grep {$_->{value} != $node->{objnum}} @$parentkids;
         $doc->{changes}->{$parentdict->{Kids}->{objnum}} = 1;
         $doc->deleteObject($node->{objnum});
         last;
      }

      my $kids = $doc->getValue($nodedict->{Kids});
      if (@$kids == 1)
      {
         # Count was not 1, so this must not be a leaf node
         # hop down into node's child

         my $sub = $doc->dereference($kids->[0]->{value});
         my $subdict = $sub->{value}->{value};
         $parentdict = $nodedict;
         $node = $sub;
         $nodedict = $subdict;
      }
      else
      {
         # search through all kids
         for (my $child=0; $child < @$kids; $child++)
         {
            my $sub = $doc->dereference($kids->[$child]->{value});
            my $subdict = $sub->{value}->{value};

            if ($subdict->{Type}->{value} ne "Pages")
            {
               if ($pagenum == $nodestart)
               {
                  # Got it!
                  splice @$kids, $child, 1;
                  $node = undef;  # flag that we are done
                  last;
               }
               else
               {
                  # Its a leaf, and not the right one.  Move on.
                  $nodestart++;
               }
            }
            else
            {
               my $count = $doc->getValue($subdict->{Count});
               if ($nodestart + $count - 1 >= $pagenum)
               {
                  # The page we want is in this kid.  Descend.
                  $parentdict = $nodedict;
                  $node = $sub;
                  $nodedict = $subdict;
                  last;
               }
               else
               {
                  # Not in this kid.  Move on.
                  $nodestart += $count;
               }
            }
            if ($child == $#$kids)
            {
               die "Internal error: did not find the page to delete -- corrupted page index\n";
            }
         }
      }
   }

   # Removing the page is easy:
   $doc->deleteObject($objnum);

   # Caches are now bad for all pages from this one
   $doc->decachePages($pagenum .. $doc->numPages());

   $doc->{PageCount}--;

   return $doc;
}

sub decachePages
{
   my $doc = shift;
   my @pages = @_;

   for (@pages)
   {
      delete $doc->{pagecache}->{$_};
      delete $doc->{Names}->{$_};
      delete $doc->{NameObjects}->{$_};
   }
   delete $doc->{Names}->{All};
}

#------------------

=item addPageResources PAGENUM, RESOURCEHASH

Add the resources from the given object to the page resource
dictionary.  If the page does not have a resource dictionary, create
one.  This function avoids duplicating resources where feasible.

=cut

sub addPageResources
{
   my $doc = shift;
   my $pagenum = shift;
   my $newrsrcs = shift;

   return if (!$newrsrcs);
   my $page = $doc->getPage($pagenum);
   return if (!$page);

   my ($anyobj) = values %$page;
   my $objnum = $anyobj->{objnum};
   my $gennum = $anyobj->{gennum};

   my $pagersrcs;
   if ($page->{Resources})
   {
      $pagersrcs = $doc->getValue($page->{Resources});
   }
   else
   {
      $pagersrcs = {};
      $page->{Resources} = CAM::PDF::Node->new("dictionary", $pagersrcs, $objnum, $gennum);
      $doc->{changes}->{$objnum} = 1;
   }
   foreach my $type (keys %$newrsrcs)
   {
      my $new_r = $doc->getValue($newrsrcs->{$type});
      my $page_r;
      if ($pagersrcs->{$type})
      {
         $page_r = $doc->getValue($pagersrcs->{$type});
      }
      if ($type eq "Font")
      {
         if (!$page_r)
         {
            $page_r = {};
            $pagersrcs->{$type} = CAM::PDF::Node->new("dictionary", $page_r, $objnum, $gennum);
            $doc->{changes}->{$objnum} = 1;
         }
         foreach my $font (keys %$new_r)
         {
            next if (exists $page_r->{$font});
            my $val = $new_r->{$font};
            if ($val->{type} ne "reference")
            {
               die "Internal error: font entry is not a reference";
            }
            $page_r->{$font} = CAM::PDF::Node->new("reference", $val->{value}, $objnum, $gennum);
            #warn "add font $font\n";
            $doc->{changes}->{$objnum} = 1;
         }
      }
      elsif ($type eq "ProcSet")
      {
         if (!$page_r)
         {
            $page_r = [];
            $pagersrcs->{$type} = CAM::PDF::Node->new("array", $page_r, $objnum, $gennum);
            $doc->{changes}->{$objnum} = 1;
         }
         foreach my $proc (@$new_r)
         {
            if ($proc->{type} ne "label")
            {
               die "Internal error: procset entry is not a label";
            }
            next if (grep {$_->{value} eq $proc->{value}} @$page_r);
            push @$page_r, CAM::PDF::Node->new("label", $proc->{value}, $objnum, $gennum);
            #warn "add procset $$proc{value}\n";
            $doc->{changes}->{$objnum} = 1;
         }
      }
      elsif ($type eq "Encoding")
      {
         # TODO: is this a hack or is it right?
         # EXPLICITLY skip /Encoding from form DR entry
      }
      else
      {
         warn "Internal error: unsupported resource type '$type'";
      }
   }
}

#------------------

=item appendPDF PDF

Append pages from another PDF document to this one.  No optimization
is done -- the pieces are just appended and the internal table of
contents is updated.

Note that this can break documents with annotations.  See the
appendpdf.pl script for a workaround.

=cut

sub appendPDF
{
   my $doc = shift;
   my $doc2 = shift;
   my $prepend = shift; # boolean, default false

   my $pageroot = $doc->{Pages};
   my ($anyobj) = values %$pageroot;
   my $objnum = $anyobj->{objnum};
   my $gennum = $anyobj->{gennum};

   my $pageobj2 = $doc2->dereference($doc2->{Root}->{Pages}->{value});
   my ($key, %refkeys) = $doc->appendObject($doc2, $pageobj2->{objnum}, 1);
   my $subpage = $doc->getObjValue($key);

   my $newdict = {};
   my $newpage = CAM::PDF::Node->new("object",
                                     CAM::PDF::Node->new("dictionary", $newdict));
   $newdict->{Type} = CAM::PDF::Node->new("label", "Pages");
   $newdict->{Kids} = CAM::PDF::Node->new("array",
                                          [
                                           CAM::PDF::Node->new("reference", $prepend ? $key : $objnum),
                                           CAM::PDF::Node->new("reference", $prepend ? $objnum : $key),
                                           ]);
   $doc->{PageCount} += $doc2->{PageCount};
   $newdict->{Count} = CAM::PDF::Node->new("number", $doc->{PageCount});
   my $newpagekey = $doc->appendObject(undef, $newpage, 0);
   $doc->{Root}->{Pages}->{value} = $newpagekey;
   $doc->{Pages} = $doc->getObjValue($newpagekey);

   $pageroot->{Parent} = CAM::PDF::Node->new("reference", $newpagekey, $key, $subpage->{gennum});
   $subpage->{Parent} = CAM::PDF::Node->new("reference", $newpagekey, $key, $subpage->{gennum});

   #my $kidlist = $doc->getValue($pageroot->{Kids});
   #push @$kidlist, CAM::PDF::Node->new("reference", $key, $objnum, $gennum);
   #$doc->{changes}->{$objnum} = 1;

   #print STDERR "$newpagekey $objnum $key\n";

   if ($doc2->{Root}->{AcroForm})
   {
      my $forms = $doc2->getValue($doc2->getValue($doc2->{Root}->{AcroForm})->{Fields});
      my @newforms = ();
      #require Data::Dumper;
      #print STDERR Data::Dumper->Dump([$forms],["forms"]);
      foreach my $reference (@$forms)
      {
         if ($reference->{type} ne "reference")
         {
            die "Internal error: expected a reference";
         }
         my $newkey = $refkeys{$reference->{value}};
         #print STDERR "old ".$reference->{value}." new $newkey\n";
         if ($newkey)
         {
            push @newforms, CAM::PDF::Node->new("reference", $newkey);
         }
      }
      if ($doc->{Root}->{AcroForm})
      {
         my $mainforms = $doc->getValue($doc->getValue($doc->{Root}->{AcroForm})->{Fields});
         foreach my $reference (@newforms)
         {
            $reference->{objnum} = $mainforms->[0]->{objnum};
            $reference->{gennum} = $mainforms->[0]->{gennum};
         }
         push @$mainforms, @newforms;
      }
      else
      {
         #my $key = $doc->appendObject($doc2, $pageobj2->{objnum}, 0);
         die "adding new forms is not implemented";
      }
   }

   if ($prepend)
   {
      # clear caches
      $doc->{pagecache} = {};
      $doc->{Names} = {};
      $doc->{NameObjects} = {};
   }

   return $key;
}

#------------------

=item prependPDF PDF

Just like appendPDF() except the new document is inserted on page 1
instead of at the end.

=cut

sub prependPDF
{
   my $doc = shift;
   return $doc->appendPDF(@_, 1);
}

#------------------

=item duplicatePage PAGENUM

=item duplicatePage PAGENUM, LEAVEBLANK

Inserts an identical copy of the specified page into the document.
The new page's number will be C<pagenum + 1>.

If C<leaveblank> is true, the new page does not get any content.
Thus, the document is broken until you subsequently call
setPageContent().

=cut

sub duplicatePage
{
   my $doc = shift;
   my $pagenum = shift;
   my $leaveBlank = shift || 0;

   my $page = $doc->getPage($pagenum);
   my $objnum = $doc->getPageObjnum($pagenum);
   my $newobjnum = $doc->appendObject($doc, $objnum, 0);
   my $newdict = $doc->getObjValue($newobjnum);
   delete $newdict->{Contents};
   my $parent = $doc->getValue($page->{Parent});
   push @{$doc->getValue($parent->{Kids})}, CAM::PDF::Node->new("reference", $newobjnum);

   while ($parent)
   {
      $doc->{changes}->{$parent->{Count}->{objnum}} = 1;
      if ($parent->{Count}->{type} eq "reference")
      {
         my $countobj = $doc->dereference($parent->{Count}->{value});
         $countobj->{value}->{value}++;
         $doc->{changes}->{$countobj->{objnum}} = 1;
      }
      else
      {
         $parent->{Count}->{value}++;
      }
      $parent = $doc->getValue($parent->{Parent});
   }
   $doc->{PageCount}++;

   unless ($leaveBlank)
   {
      $doc->setPageContent($pagenum+1, $doc->getPageContent($pagenum));
   }

   # Caches are now bad for all pages from this one
   $doc->decachePages($pagenum + 1 .. $doc->numPages());
}
#------------------

=item createStreamObject CONTENT

=item createStreamObject CONTENT, FILTER ...

I<For INTERNAL use>

Create a new Stream object.  This object is NOT added to the document.
Use the appendObject() function to do that after calling this
function.

=cut

sub createStreamObject
{
   my $doc = shift;
   my $content = shift;

   my $dict = CAM::PDF::Node->new("dictionary",
                                 {
                                    Length => CAM::PDF::Node->new("number", length($content)),
                                    StreamData => CAM::PDF::Node->new("stream", $content),
                                 },
                                 );

   my $obj = CAM::PDF::Node->new("object", $dict);

   while (my $filter = shift)
   {
      #warn "$filter encoding\n";
      $doc->encodeOne($obj->{value}, $filter);
   }

   return $obj;
}

#------------------

=item uninlineImages

=item uninlineImages PAGENUM

Search the content of the specified page (or all pages if the
page number is omitted) for embedded images.  If there are any, replace
them with indirect objects.  This procedure uses heuristics to detect
inline images, and is subject to confusion in extremely rare cases of text
that uses "BI" and "ID" a lot.

=cut

sub uninlineImages
{
   my $doc = shift;
   my $pagenum = shift;

   my $changes = 0;
   if (!$pagenum)
   {
      my $pages = $doc->numPages();
      for ($pagenum=1; $pagenum <= $pages; $pagenum++)
      {
         $changes += $doc->uninlineImages($pagenum);
      }
   }
   else
   {
      my $c = $doc->getPageContent($pagenum);
      my $pos = 0;
      while (($pos = index $c, "BI", $pos) != -1)
      {
         if ($pos == 0 || substr($c,$pos-1,1) =~ /\W/) # manual \bBI check
         {
            my $part = substr $c, $pos;
            if ($part =~ /^BI\b(.*?)\bID\b/s)
            {
               my $im = $1;

               ## Long series of tests to make sure this is really an
               ## image and not just coincidental text

               # Fix easy cases of "BI text) BI ... ID"
               $im =~ s/^.*\bBI\b//; 
               # There should never be an EI inside of a BI ... ID
               next if ($im =~ /\bEI\b/);
               
               # Easy tests: is this the beginning or end of a string?
               # (these aren't really good tests...)
               next if ($im =~ /^\)/);
               next if ($im =~ /\($/);
               
               # this is the most complex heuristic:
               # make sure that there is an open paren before every close
               # if not, then the "BI" or the "ID" was part of a string
               my $test = $im;  # make a copy we can scribble on
               my $failed = 0;
               # get rid of escaped parens for the test
               $test =~ s/\\[\(\)]//gs; 
               # Look for closing parens
               while ($test =~ s/^(.*?)\)//s)
               {
                  # If there is NOT an opening paren before the
                  # closing paren we detected above, then the start of
                  # our string is INSIDE a paren pair, thus a failure.
                  my $bit = $1;
                  if ($bit !~ /\(/)
                  {
                     $failed = 1;
                     last;
                  }
               }
               next if ($failed);
               
               # End of heuristics.  This is likely a real embedded image.
               # Now do the replacement.

               my $oldlen = length($part);
               my $image = $doc->parseInlineImage(\$part, undef);
               my $newlen = length($part);
               my $imagelen = $oldlen-$newlen;
               
               # Construct a new image name like "I3".  Start with
               # "I1" and continue until we get an unused "I<n>"
               # (first, get the list of already-used labels)
               $doc->buildNameTable($pagenum);
               my $name;
               my $i = 1;
               do {
                  $name = "Im" . ($i++);
               } while (exists $doc->{Names}->{$pagenum}->{$name});
               
               $doc->setName($image, $name);
               my $key = $doc->appendObject(undef, $image, 0);
               $doc->pageAddName($pagenum, $name, $key);
               
               $c = substr($c, 0, $pos) . "/$name Do" . substr($c, $pos+$imagelen);
               $changes++;
            }
         }
      }
      $doc->setPageContent($pagenum, $c) if ($changes > 0);
   }
   return $changes;
}

#------------------

=item appendObject DOC, OBJECTNUM, RECURSE?

=item appendObject undef, OBJECT, RECURSE?

Duplicate an object from another PDF document and add it to this
document, optionally descending into the object and copying any other
objects it references.

Like replaceObject(), the second form allows you to append a
newly-created block to the PDF.

=cut

sub appendObject
{
   my $doc = shift;
   my $doc2 = shift;
   my $key2 = shift;
   my $follow = shift;

   my $objnum = ++$doc->{maxobj};
   #$doc->{xref}->{$objnum} = undef;
   #$doc->{endxref}->{$objnum} = undef if (exists $doc->{endxref});
   $doc->{versions}->{$objnum} = -1;

   my %refkeys = $doc->replaceObject($objnum, $doc2, $key2, $follow);
   if (wantarray)
   {
      return ($objnum, %refkeys);
   }
   else
   {
      return $objnum;
   }
}

#------------------

=item replaceObject OBJECTNUM, DOC, OBJECTNUM, RECURSE?

=item replaceObject OBJECTNUM, undef, OBJECT

Duplicate an object from another PDF document and insert it into this
document, replacing an existing object.  Optionally descend into the
original object and copy any other objects it references.

If the other document is undefined, then the object to copy is taken
to be an anonymous object that is not part of any other document.
This is useful when you've just created that anonymous object.

=cut

sub replaceObject
{
   my $doc = shift;
   my $key = shift;
   my $doc2 = shift;
   my $key2 = shift;
   my $follow = shift;

   # careful! "undef" means something different from "0" here!
   $follow = 1 if (!defined $follow);

   my $obj;
   my $obj2;
   if ($doc2)
   {
      $obj2 = $doc2->dereference($key2);
      $obj = $doc->copyObject($obj2);
   }
   else
   {
      $obj = $key2;
      if ($follow)
      {
         warn "Error: you cannot \"follow\" an object if it has no document.\n" .
             "Resetting follow = false and continuing....\n";
         $follow = 0;
      }
   }

   $doc->setObjNum($obj, $key);

   # Preserve the name of the object
   if ($doc->{xref}->{$key})  # make sure it isn't a brand new object
   {
      my $oldname = $doc->getName($doc->dereference($key));
      if ($oldname)
      {
         $doc->setName($obj, $oldname);
      }
      else
      {
         $doc->removeName($obj);
      }
   }

   $doc->{objcache}->{$key} = $obj;
   $doc->{changes}->{$key} = 1;

   my %newrefkeys = ($key2, $key);
   if ($follow)
   {
      foreach my $oldrefkey ($doc2->getRefList($obj2))
      {
         next if ($oldrefkey == $key2);
         my $newkey = $doc->appendObject($doc2, $oldrefkey, 0);
         $newrefkeys{$oldrefkey} = $newkey;
      }
      $doc->changeRefKeys($obj, \%newrefkeys);
      foreach my $newkey (values %newrefkeys)
      {
         $doc->changeRefKeys($doc->dereference($newkey), \%newrefkeys);
      }
   }
   return (%newrefkeys);
}

#------------------

=item deleteObject OBJECTNUM

Remove an object from the document.  This function does NOT take care
of dependencies on this object.

=cut

sub deleteObject
{
   my $doc = shift;
   my $objnum = shift;

   delete $doc->{versions}->{$objnum};
   delete $doc->{objcache}->{$objnum};
   delete $doc->{xref}->{$objnum};
   delete $doc->{endxref}->{$objnum};
   delete $doc->{changes}->{$objnum};
}

#------------------

=item cleanse

Remove unused objects.  I<WARNING:> this function breaks some PDF
documents because it removes objects that are strictly part of the
page model heirarchy, but which are required anyway (like some font
definition objects).

=cut

sub cleanse
{
   my $doc = shift;

   #die "The cleanse() command causes corrupt PDF docs.  Don't use it.\n";
   
   my $base = CAM::PDF::Node->new("dictionary",$doc->{trailer});
   my @list = sort {$a<=>$b} $doc->getRefList($base);
   #print join(",", @list), "\n";

   for (my $i=1; $i<=$doc->{maxobj}; $i++)
   {
      if (@list > 0 && $list[0] == $i)
      {
         shift @list;
      }
      else
      {
         #warn "delete object $i\n";
         $doc->deleteObject($i);
      }
   }
}

#------------------

=item createID

I<For INTERNAL use>

Generate a new document ID.  Contrary the Adobe recommendation, this
is a random number.

=cut

sub createID
{
   my $doc = shift;

   # Warning: this is non-repeatable, and depends on Linux!

   my $addbytes;
   if ($doc->{ID})
   {
      # do not change the first half of an existing ID
      $doc->{ID} = substr $doc->{ID}, 0, 16;
      $addbytes = 16;
   }
   else
   {
      $doc->{ID} = "";
      $addbytes = 32;
   }

   local *FILE;
   open(FILE, "/dev/urandom") or return undef;
   read(FILE, $doc->{ID}, $addbytes, 32-$addbytes);
   close(FILE);

   if ($doc->{trailer})
   {
      $doc->{trailer}->{ID} = CAM::PDF::Node->new("array",
                               [
                                CAM::PDF::Node->new("hexstring", substr($doc->{ID}, 0, 16)),
                                CAM::PDF::Node->new("hexstring", substr($doc->{ID}, 16, 16)),
                                ],
                               );
   }

   return 1;
}

#------------------

=item fillFormFields NAME => VALUE ...

Set the default values of PDF form fields.  The name should be the
full heirarchical name of the field as output by the
getFormFieldList() function.  The argument list can be a hash if you
like.  A simple way to use this function is something like this:

    my %fields = (fname => "John", lname => "Smith", state => "WI");
    $field{zip} = 53703;
    $doc->fillFormFields(%fields);

=cut

sub fillFormFields
{
   my $doc = shift;
   my @list = (@_);

   my $filled = 0;
   while (@list > 0)
   {
      my $key = shift @list;
      my $value = shift @list;
      $value = "" if (!defined $value);

      next if (!$key);
      next if (ref $key);
      my $obj = $doc->getFormField($key);
      next if (!$obj);

      my $objnum = $obj->{objnum};
      my $gennum = $obj->{gennum};

      # This read-only dict includes inherited properties
      my $propdict = $doc->getFormFieldDict($obj);

      # This read-write dict does not include inherited properties
      my $dict = $doc->getValue($obj);
      $dict->{V}  = CAM::PDF::Node->new("string", $value, $objnum, $gennum);
      #$dict->{DV} = CAM::PDF::Node->new("string", $value, $objnum, $gennum);

      if ($propdict->{FT} && $doc->getValue($propdict->{FT}) eq "Tx")  # Is it a text field?
      {
         # Set up display of form value
         if (!$dict->{AP})
         {
            $dict->{AP} = CAM::PDF::Node->new("dictionary", {}, $objnum, $gennum);
         }
         if (!$dict->{AP}->{value}->{N})
         {
            my $newobj = CAM::PDF::Node->new("object", 
                                            CAM::PDF::Node->new("dictionary",{}),
                                            );
            my $num = $doc->appendObject(undef, $newobj, 0);
            $dict->{AP}->{value}->{N} = CAM::PDF::Node->new("reference", $num, $objnum, $gennum);
         }
         my $formobj = $doc->dereference($dict->{AP}->{value}->{N}->{value});
         my $formonum = $formobj->{objnum};
         my $formgnum = $formobj->{gennum};
         my $formdict = $doc->getValue($formobj);
         if (!$formdict->{Subtype})
         {
            $formdict->{Subtype} = CAM::PDF::Node->new("label", "Form", $formonum, $formgnum);
         }
         my @rect = (0,0,0,0);
         if ($dict->{Rect})
         {
            my $r = $doc->getValue($dict->{Rect});
            my ($x1, $y1, $x2, $y2) = @$r;
            @rect = ($doc->getValue($x1), $doc->getValue($y1),
                     $doc->getValue($x2), $doc->getValue($y2));
         }
         my $dx = $rect[2]-$rect[0];
         my $dy = $rect[3]-$rect[1];
         if (!$formdict->{BBox})
         {
            $formdict->{BBox} = CAM::PDF::Node->new("array",
                                                   [
                                                    CAM::PDF::Node->new("number", 0, $formonum, $formgnum),
                                                    CAM::PDF::Node->new("number", 0, $formonum, $formgnum),
                                                    CAM::PDF::Node->new("number", $dx, $formonum, $formgnum),
                                                    CAM::PDF::Node->new("number", $dy, $formonum, $formgnum),
                                                    ],
                                                   $formonum,
                                                   $formgnum);
         }
         my $text = $value;
         $text =~ s/\r\n?/\n/gs;
         $text =~ s/\n+$//s;

         my @rsrcs = ();
         my $fontmetrics = 0;
         my $fontname = "";
         my $fontsize = 0;
         my $da = "";
         my $tl = "";
         my $border = 2;
         my $tx = $border;
         my $ty = $border + 2;
         my $stringwidth;
         if ($propdict->{DA}) {
            $da = $doc->getValue($propdict->{DA});

            # Try to pull out all of the resources used in the text object
            @rsrcs = ($da =~ /\/([^\s<>\/\[\]\(\)]+)/g);

            # Try to pull out the font size, if any.  If more than
            # one, pick the last one.  Font commands look like:
            # "/<fontname> <size> Tf"
            if ($da =~ /\s*\/(\w+)\s+(\d+)\s+Tf.*?$/)
            {
               $fontname = $1;
               $fontsize = $2;
               if ($fontname)
               {
                  if ($propdict->{DR})
                  {
                     my $dr = $doc->getValue($propdict->{DR});
                     $fontmetrics = $doc->getFontMetrics($dr, $fontname);
                  }
                  #print STDERR "Didn't get font\n" unless($fontmetrics);
               }
            }
         }

         my %flags = (
                      Justify => "left",
                      );
         if ($propdict->{Ff})
         {
            # Just decode the ones we actually care about
            # PDF ref, 3rd ed pp 532,543
            my $ff = $doc->getValue($propdict->{Ff});
            my @flags = split //, unpack("b*", pack("V", $ff));
            $flags{ReadOnly}        = $flags[0];
            $flags{Required}        = $flags[1];
            $flags{NoExport}        = $flags[2];
            $flags{Multiline}       = $flags[12];
            $flags{Password}        = $flags[13];
            $flags{FileSelect}      = $flags[20];
            $flags{DoNotSpellCheck} = $flags[22];
            $flags{DoNotScroll}     = $flags[23];
         }
         if ($propdict->{Q})
         {
            my $q = $doc->getValue($propdict->{Q}) || 0;
            $flags{Justify} = $q==2 ? "right" : ($q==1 ? "center" : "left");
         }

         # The order of the following sections is important!
         if ($flags{Password})
         {
            $text =~ s/[^\n]/*/g;  # Asterisks for password characters
         }

         if ($fontmetrics && (!$fontsize))
         {
            # Fix autoscale fonts
            $stringwidth = 0;
            my $lines = 0;
            foreach my $line (split /\n/, $text)
            {
               $lines++;
               my $w = $doc->getStringWidth($fontmetrics, $line);
               $stringwidth = $w if ($w && $w > $stringwidth);
            }
            $lines ||= 1;
            # Initial guess
            $fontsize = ($dy - 2 * $border)/($lines * 1.5);
            my $fontwidth = $fontsize*$stringwidth;
            my $maxwidth = $dx - 2 * $border;
            if ($fontwidth > $maxwidth)
            {
               $fontsize *= $maxwidth/$fontwidth;
            }
            $da =~ s/\/$fontname\s+0\s+Tf\b/\/$fontname $fontsize Tf/g;
         }
         if ($fontsize)
         {
            # This formula is TOTALLY empirical.  It's probably wrong.
            $ty = $border + 2 + (9-$fontsize)*0.4;
         }


         # escape characters
         $text = $doc->writeString($text);

         if ($flags{Multiline})
         {
            my $linebreaks = $text =~ s/\\n/\) Tj T* \(/g;

            # Total guess work:
            # line height is either 150% of fontsize or thrice
            # the corner offset
            $tl = $fontsize ? $fontsize * 1.5 : $ty * 3;

            # Bottom aligned
            #$ty += $linebreaks * $tl;
            # Top aligned
            $ty = $dy - $border - $tl;

            if ($flags{Justify} ne "left")
            {
               warn "Justified text not supported for multiline fields";
            }

            $tl .= " TL";
         }
         else
         {
            if ($flags{Justify} ne "left" && $fontmetrics)
            {
               my $width = $stringwidth || $doc->getStringWidth($fontmetrics, $text);
               my $diff = $dx - $width*$fontsize;

               if ($flags{Justify} eq "center")
               {
                  $text = ($diff/2)." 0 Td $text";
               }
               elsif ($flags{Justify} eq "right")
               {
                  $text = "$diff 0 Td $text";
               }
            }
         }

         # Move text from lower left corner of form field
         my $tm = "1 0 0 1 $tx $ty Tm ";

         $text =  "$tl $da $tm $text Tj";
         $text = "1 g 0 0 $dx $dy re f /Tx BMC q 1 1 ".($dx-$border)." ".($dy-$border)." re W n BT $text ET Q EMC";
         $formdict->{Length} = CAM::PDF::Node->new("number", length($text), $formonum, $formgnum);
         $formdict->{StreamData} = CAM::PDF::Node->new("stream", $text, $formonum, $formgnum);

         if (@rsrcs > 0) {
            if (!$formdict->{Resources})
            {
               $formdict->{Resources} = CAM::PDF::Node->new("dictionary", {}, $formonum, $formgnum);
            }
            my $rdict = $doc->getValue($formdict->{Resources});
            if (!$rdict->{ProcSet})
            {
               $rdict->{ProcSet} = CAM::PDF::Node->new("array",
                                                      [
                                                       CAM::PDF::Node->new("label", "PDF", $formonum, $formgnum),
                                                       CAM::PDF::Node->new("label", "Text", $formonum, $formgnum),
                                                       ],
                                                      $formonum,
                                                      $formgnum);
            }
            if (!$rdict->{Font})
            {
               $rdict->{Font} = CAM::PDF::Node->new("dictionary", {}, $formonum, $formgnum);
            }
            my $fdict = $doc->getValue($rdict->{Font});

            # Search out font resources.  This is a total kluge.
            # TODO: the right way to do this is to look for the DR
            # attribute in the form element or it's ancestors.
            foreach my $font (@rsrcs)
            {
               my $fobj = $doc->dereference("/$font", "All");
               if (!$fobj)
               {
                  die "Could not find resource /$font while preparing form field $key\n";
               }
               $fdict->{$font} = CAM::PDF::Node->new("reference", $fobj->{objnum}, $formonum, $formgnum);
            }
         }
      }
      $filled++;
   }
   return $filled;
}


#------------------

=item clearFormFieldTriggers NAME, NAME, ...

Disable any triggers set on data entry for the specified form field
names.  This is useful in the case where, for example, the data entry
javascript forbids punctuation and you want to prefill with a
hyphenated word.  If you don't clear the trigger, the prefill may not
happen.

=cut

sub clearFormFieldTriggers
{
   my $doc = shift;

   foreach my $fieldname (@_)
   {
      my $obj = $doc->getFormField($fieldname);
      if ($obj)
      {
         if (exists $obj->{value}->{value}->{AA})
         {
            delete $obj->{value}->{value}->{AA};
            my $objnum = $obj->{objnum};
            $doc->{changes}->{$objnum} = 1 if ($objnum);
         }
      }
   }
}

#------------------

=item clearAnnotations

Remove all annotations from the document.  If form fields are
encountered, their text is added to the appropriate page.

=cut

sub clearAnnotations
{
   my $doc = shift;

   my $formrsrcs;
   if ($doc->{Root}->{AcroForm})
   {
      my $acroform = $doc->getValue($doc->{Root}->{AcroForm});
      # Get the form resources
      if ($acroform->{DR})
      {
         $formrsrcs = $doc->getValue($acroform->{DR});
      }

      # Kill off the forms
      $doc->deleteObject($doc->{Root}->{AcroForm}->{value});
      delete $doc->{Root}->{AcroForm};
   }

   # Iterate through the pages, deleting annotations

   my $pages = $doc->numPages();
   foreach my $p (1..$pages)
   {
      my $page = $doc->getPage($p);
      if ($page->{Annots}) {
         $doc->addPageResources($p, $formrsrcs);
         my $annotsarray = $doc->getValue($page->{Annots});
         delete $page->{Annots};
         foreach my $annotref (@$annotsarray)
         {
            my $annot = $doc->getValue($annotref);
            if (ref($annot) ne "HASH")
            {
               die "Internal error: annotation is not a dictionary";
            }
            # Copy all text field values into the page, if present
            if ($annot->{Subtype} && 
                $annot->{Subtype}->{value} eq "Widget" &&
                $annot->{FT} &&
                $annot->{FT}->{value} eq "Tx" &&
                $annot->{AP})
            {
               my $ap = $doc->getValue($annot->{AP});
               my $rect = $doc->getValue($annot->{Rect});
               my $x = $doc->getValue($rect->[0]);
               my $y = $doc->getValue($rect->[1]);
               if ($ap->{N})
               {
                  my $n = $doc->dereference($ap->{N}->{value})->{value};
                  my $content = $doc->decodeOne($n, 0);
                  if (!$content)
                  {
                     die "Internal error: expected a content stream from the form copy";
                  }
                  #require Data::Dumper;                  
                  #print Data::Dumper->Dump([$n], ["n"]);
                  #warn "Add to page $p: \n$content\n";
                  $content =~ s/\bre(\s+)f\b/re$1n/gs;
                  $content = "q 1 0 0 1 $x $y cm\n$content Q\n";
                  $doc->appendPageContent($p, $content);
                  $doc->addPageResources($p, $doc->getValue($n->{value}->{Resources}));
               }
            }
            $doc->deleteObject($annotref->{value});
         }
      }
   }

   # kill off the annotation dependencies
   $doc->cleanse();
}


################################################################################

=back

=head2 Document Writing

=over 4

=cut


#------------------

=item preserveOrder

Try to recreate the original document as much as possible.  This may
help in recreating documents which use undocumented tricks of saving
font information in adjacent objects.

=cut

sub preserveOrder
{
   # Call this to record the order of the objects in the original file
   # If called, then any new file will try to preserve the original order
   my $doc = shift;

   my %positions = reverse %{$doc->{xref}};
   $doc->{order} = [map {($positions{$_})} sort {$a<=>$b} keys %positions];
   #print "Wrote order " . join(",",@{$doc->{order}}) . "\n";
}

#------------------

=item isLinearized

Returns a boolean indicating whether this PDF is linearized (aka
"optimized").

=cut

sub isLinearized
{
   my $doc = shift;

   my $first;
   if (exists $doc->{order})
   {
      $first = $doc->{order}->[0];
   }
   else
   {
      my %revxref = reverse %{$doc->{xref}};
      ($first) = sort {$a <=> $b} keys %revxref;
      $first = $revxref{$first};
   }

   my $linearized = undef; # false
   my $obj = $doc->dereference($first);
   if ($obj && $obj->{value}->{type} eq "dictionary")
   {
      if (exists $obj->{value}->{value}->{Linearized})
      {
         $linearized = $doc; # true
      }
   }
   return $linearized;
}
#------------------

=item delinearize

I<For INTERNAL use>

Undo the tweaks used to make the document 'optimized'.  This function
is automatically called on every save or output since this library
does not yet support linearized documents.

=cut

sub delinearize
{
   my $doc = shift;

   return if ($doc->{delinearized});

   # Turn off Linearization, if set
   my $first;
   if (exists $doc->{order})
   {
      $first = $doc->{order}->[0];
   }
   else
   {
      # Sort by doc byte offset, select smallest
      my %revxref = reverse %{$doc->{xref}};
      ($first) = sort {$a <=> $b} keys %revxref;
      $first = $revxref{$first};
   }

   my $obj = $doc->dereference($first);
   if ($obj->{value}->{type} eq "dictionary")
   {
      if (exists $obj->{value}->{value}->{Linearized})
      {
         $doc->deleteObject($first);
      }
   }

   $doc->{delinearized} = 1;
}

#------------------

=item clean

Cache all parts of the document and throw away it's old structure.
This is useful for writing PDFs anew, instead of simply appending
changes to the existing documents.  This is called by cleansave and
cleanoutput.

=cut

sub clean
{
   my $doc = shift;

   # Make sure to extract everything before we wipe the old version
   $doc->cacheObjects();

   $doc->delinearize();

   #delete $doc->{ID};

   # Mark everything changed
   %{$doc->{changes}} = (
                         %{$doc->{changes}},
                         map {($_,1)} keys %{$doc->{xref}},
                         );

   # Mark everything new
   %{$doc->{versions}} = (
                          %{$doc->{versions}},
                          map {($_,-1)} keys %{$doc->{xref}},
                          );

   $doc->{xref} = {};
   delete $doc->{endxref};
   $doc->{startxref} = 0;
   $doc->{content} = "";
   $doc->{contentlength} = 0;
   delete $doc->{trailer}->{Prev};
}
#------------------

=item needsSave

Returns a boolean indicating whether the save() method needs to be
called.  Like save(), this has nothing to do with whether the document
has been saved to disk, but whether the in-memory representation of
the document has been serialized.

=cut

sub needsSave
{
   my $doc = shift;

   return (keys(%{$doc->{changes}}) != 0);
}
#------------------

=item save

Serialize the document into a single string.  All changed document
elements are normalized, and a new index and an updated trailer are
created.

This function operates solely in memory.  It DOES NOT write the
document to a file.  See the output() function for that.

=cut

sub save
{
   my $doc = shift;

   if (!$doc->needsSave())
   {
      return;
   }

   $doc->delinearize();

   delete $doc->{endxref};

   if (!$doc->{content})
   {
      $doc->{content} = "%PDF-" . $doc->{pdfversion} . "\n%\217\n";
   }

   my %allobjs = (%{$doc->{changes}}, %{$doc->{xref}});
   my @objects = sort {$a<=>$b} keys %allobjs;
   if ($doc->{order}) {

      # Sort in the order in $doc->{order} array, with the rest later
      # in objnum order
      my %o = ();
      my $n = @{$doc->{order}};
      foreach my $i (0 .. $n-1)
      {
         $o{$doc->{order}->[$i]} = $i;
      }
      @objects = sort {($o{$a}||$a+$n) <=> ($o{$b}||$b+$n)} @objects;
   }
   delete $doc->{order};

   my %newxref = ();
   foreach my $key (@objects)
   {
      next if (!$doc->{changes}->{$key});
      $newxref{$key} = length($doc->{content});

      #print "Writing object $key\n";
      $doc->{content} .= $doc->writeObject($key);

      $doc->{xref}->{$key} = $newxref{$key};
      $doc->{versions}->{$key}++;
      delete $doc->{changes}->{$key};
   }

   $doc->{content} .= "\n" if ($doc->{content} !~ /[\r\n]$/s);

   my $startxref = length($doc->{content});

   # Append the new xref
   $doc->{content} .= "xref\n";
   my %blocks = (
                 0 => "0000000000 65535 f \n",
                 );
   foreach my $key (keys(%newxref))
   {
      $blocks{$key} = sprintf "%010d %05d n \n", $newxref{$key}, $doc->{versions}->{$key};
   }

   # If there is only one version of the document, there must be no
   # holes in the xref.  Test for versions by checking the Prev record
   # in the trailer
   if (!$doc->{trailer}->{Prev})
   {
      # Fill in holes
      my $prevfreeblock = 0;
      for (my $key = $doc->{maxobj}-1; $key >= 0; $key--)
      {
         if (!exists $blocks{$key})
         {
            # Add an entry to the free list
            # On $key == 0, this blows away the above definition of
            # the head of the free block list, but that's no big deal.
            $blocks{$key} = sprintf("%010d %05d f \n", 
                                    $prevfreeblock, ($key == 0 ? 65535 : 1));
            $prevfreeblock = $key;
         }
      }
   }
   
   my $currblock = "";
   my $currnum = 0;
   my $currstart = 0;
   my @blockkeys = sort {$a<=>$b} keys %blocks;
   for (my $i = 0; $i < @blockkeys; $i++)
   {
      my $key = $blockkeys[$i];
      $currblock .= $blocks{$key};
      $currnum++;
      if ($i == $#blockkeys || $key+1 < $blockkeys[$i+1])
      {
         $doc->{content} .= "$currstart $currnum\n$currblock";
         if ($i < $#blockkeys)
         {
            $currblock = "";
            $currnum = 0;
            $currstart = $blockkeys[$i+1];
         }
      }
   }

   #   Append the new trailer
   $doc->{trailer}->{Size} = CAM::PDF::Node->new("number", $doc->{maxobj} + 1);
   $doc->{trailer}->{Prev} = CAM::PDF::Node->new("number", $doc->{startxref}) if ($doc->{startxref});
   $doc->{content} .= "trailer\n" . $doc->writeAny(CAM::PDF::Node->new("dictionary", $doc->{trailer})) . "\n";

   # Append the new startxref
   $doc->{content} .= "startxref\n$startxref\n";
   $doc->{startxref} = $startxref;

   # Append EOF
   $doc->{content} .= "%%EOF\n";

   $doc->{contentlength} = length($doc->{content});
}

#------------------

=item cleansave

Call the clean() function, then call the save() function.

=cut

sub cleansave
{
   my $doc = shift;

   $doc->clean();
   $doc->save();
}

#------------------

=item output FILENAME

=item output

Save the document to a file.  The save() function is called first to
serialize the data structure.  If no filename is specified, or if the
filename is '-', the document is written to standard output.

Note: it is the responsibility of the application to ensure that the
PDF document has either the Modify or Add permission.  You can do this
like the following:

   if ($doc->canModify()) {
      $doc->output($outfile);
   } else {
      die "The PDF file denies permission to make modifications\n";
   }

=cut

sub output
{
   my $doc = shift;
   my $file = shift;
   $file = "-" if (!defined $file);

   $doc->save();

   if ($file eq "-")
   {
      binmode STDOUT;
      print $doc->{content};
   }
   else
   {
      local *OUT;
      open OUT, ">$file" or die "Failed to write file $file\n";
      binmode OUT;
      print OUT $doc->{content};
      close OUT;
   }
   return $doc;
}

#------------------

=item cleanoutput FILE

=item cleanoutput

Call the clean() function, then call the output() function to write a
fresh copy of the document to a file.

=cut

sub cleanoutput
{
   my $doc = shift;
   my $file = shift;

   $doc->clean();
   $doc->output($file);
}

#------------------
# PRIVATE FUNTION

sub writeObject
{
   my $doc = shift;
   my $objnum = shift;

   return "$objnum 0 " . $doc->writeAny($doc->dereference($objnum));
}

#------------------
# PRIVATE FUNTION

sub writeString
{
   my $pkg_or_doc = shift;
   my $string = shift;

   # Divide the string into manageable pieces, which will be
   # re-concatenated with "\" continuation characters at the end of
   # their lines
   
   # -- This code used to do concatenation by juxtaposing multiple
   # -- "(<fragment>)" compenents, but this breaks many PDF
   # -- implementations (incl Acrobat5 and XPDF)
   
   # Break the string into pieces of length $maxstr.  Note that an
   # artifact of this usage of split returns empty strings between
   # the fragments, so grep them out

   my $maxstr = ref($pkg_or_doc) ? $pkg_or_doc->{maxstr} : $CAM::PDF::MAX_STRING;
   my @strs = grep {$_ ne ""} split /(.{$maxstr}})/, $string;
   foreach (@strs)
   {
      s/\\/\\\\/g;       # escape escapes -- this line must come first!
      s/([\(\)])/\\$1/g; # escape parens
      s/\n/\\n/g;
      s/\r/\\r/g;
      s/\t/\\t/g;
      s/\f/\\f/g;
      # TODO: handle backspace char
      #s/???/\\b/g;
   }
   return "(" . join("\\\n", @strs) . ")";
}

#------------------
# PRIVATE FUNTION

sub writeAny
{
   my $doc = shift;
   my $obj = shift;

   die "Not a ref! " if (! ref $obj);

   my $key = $obj->{type};
   my $val = $obj->{value};
   my $objnum = $obj->{objnum};
   my $gennum = $obj->{gennum};

   if ($key eq "string")
   {
      $val = $doc->{crypt}->encrypt($val, $objnum, $gennum);

      return $doc->writeString($val);
   }
   elsif ($key eq "hexstring")
   {
      $val = $doc->{crypt}->encrypt($val, $objnum, $gennum);
      return "<" . unpack("H*", $val) . ">";
   }
   elsif ($key eq "number")
   {
      return "$val";
   }
   elsif ($key eq "reference")
   {
      return "$val 0 R"; # TODO: lookup the gennum and use it instead of 0 (?)
   }
   elsif ($key eq "boolean")
   {
      return $val;
   }
   elsif ($key eq "null")
   {
      return "null";
   }
   elsif ($key eq "label")
   {
      return "/$val";
   }
   elsif ($key eq "array")
   {
      if (@$val == 0)
      {
         return "[ ]";
      }
      my $str = "";
      my @strs = ();
      foreach (@$val)
      {
         my $newstr = $doc->writeAny($_);
         if ($str ne "")
         {
            #$str .= (length($str) > $doc->{maxstr} ? "\n" : " ");
            #$str .= "\n";
            if (length($str . $newstr) > $doc->{maxstr})
            {
               push @strs, $str;
               $str = "";
            }
            else
            {
               $str .= " ";
            }
         }
         $str .= $newstr;
      }
      $str = join("\n", @strs, $str) if (@strs > 0);
      return "[ " . $str . " ]";
   }
   elsif ($key eq "dictionary")
   {
      my $str = "";
      my @strs = ();
      if (exists $val->{Type})
      {
         $str .= ($str ? " " : "") . "/Type " . $doc->writeAny($val->{Type});
      }
      if (exists $val->{Subtype})
      {
         $str .= ($str ? " " : "") . "/Subtype " . $doc->writeAny($val->{Subtype});
      }
      foreach my $dictkey (sort keys %$val)
      {
         next if ($dictkey eq "Type");
         next if ($dictkey eq "Subtype");
         next if ($dictkey eq "StreamDataDone");
         if ($dictkey eq "StreamData")
         {
            if (exists $val->{StreamDataDone})
            {
               delete $val->{StreamDataDone};
               next;
            }
            # This is a stream way down deep in the data...  Probably due to a solidifyObject

            # First, try to handle the easy case:
            if (scalar keys(%$val) == 2 && (exists $val->{Length} || exists $val->{L}))
            {
               my $str = $val->{$dictkey}->{value};
               return $doc->writeAny(CAM::PDF::Node->new("hexstring", unpack("H".length($str)*2, $str), $objnum, $gennum));
            }

            # TODO: Handle more complex streams ...
            die "This stream is too complex for me to write... Giving up\n";
            #require Data::Dumper;
            #warn Data::Dumper->Dump([$val->{$dictkey}], [qw(streamdata)]);

            next;
         }

         my $newstr = "/$dictkey " . $doc->writeAny($val->{$dictkey});
         if ($str ne "")
         {
            #$str .= (length($str) > $doc->{maxstr} ? "\n" : " ");
            #$str .= "\n";
            if (length($str . $newstr) > $doc->{maxstr})
            {
               push @strs, $str;
               $str = "";
            }
            else
            {
               $str .= " ";
            }
         }
         $str .= $newstr;
      }
      $str = join("\n", @strs, $str) if (@strs > 0);
      return "<< " . $str . " >>";
   }
   elsif ($key eq "object")
   {
      die "Obj data is not a ref! ($val)"  if (! ref $val);
      my $stream;
      if ($val->{type} eq "dictionary" && exists $val->{value}->{StreamData})
      {
         $stream = $val->{value}->{StreamData}->{value};
         my $length = length($stream);

         my $l = $val->{value}->{Length} || $val->{value}->{L};
         my $oldlength = $doc->getValue($l);
         if ($length != $oldlength)
         {
            $val->{value}->{Length} = CAM::PDF::Node->new("number", $length, $objnum, $gennum);
            delete $val->{value}->{L};
         }
         $val->{value}->{StreamDataDone} = 1;
      }
      my $str = $doc->writeAny($val);
      if ($stream)
      {
         $stream = $doc->{crypt}->encrypt($stream, $objnum, $gennum);
         $str .= "\nstream\n" . $stream . "endstream";
      }
      return "obj\n$str\nendobj\n";
   }
   else
   {
      $objnum ||= "<none>";
      die "Unknown key '$key' in writeAny (objnum $objnum)\n";
   }
}

######################################################################

=back

=head2 Document Traversing

=over 4

=cut


########
# traversing
#
# In many cases, it's useful to apply one action to every node in an
# object tree.  The routines below all use the &traverse() function.
# One of the most important parameters is the first: $deref=(1|0) If
# true, the traversal follows "reference" nodes.  If false, it does
# descend into "refererence" nodes.
########

#------------------
# PRIVATE FUNCTION

sub traverse
{
   my $doc = shift;
   my $deref = shift;
   my $obj = shift;
   my $func = shift;
   my $funcdata = shift;
   my $traversed = shift || {};
   my $desc = shift || 0;

   my $debug = 0;

   print(("  " x $desc) . "traversing " . $obj->{type} . "\n") if ($debug);

   $doc->$func($obj, $funcdata);

   my $key = $obj->{type};
   my $val = $obj->{value};

   if ($key eq "dictionary")
   {
      foreach my $dictkey (keys %$val)
      {
         $doc->traverse($deref, $val->{$dictkey}, $func, $funcdata, $traversed, $desc+1);
      }
   }
   elsif ($key eq "array")
   {
      foreach my $arrindex (0 .. $#$val)
      {
         $doc->traverse($deref, $val->[$arrindex], $func, $funcdata, $traversed, $desc+1);
      }
   }
   elsif ($key eq "object")
   {
      $traversed->{$obj->{objnum}} = 1 if ($obj->{objnum});
      $doc->traverse($deref, $val, $func, $funcdata, $traversed, $desc+1);
   }
   elsif ($key eq "reference")
   {
      if ($deref && (!exists $traversed->{$val}))
      {
         $doc->traverse($deref, $doc->dereference($val), $func, $funcdata, $traversed, $desc+1);
      }
   }

   print(("  " x $desc) . "returning $key\n") if ($debug);
}

# decodeObject and decodeAll differ from each other like this:
#
#  decodeObject JUST decodes a single stream directly below the object
#  specified by the objnum
#
#  decodeAll descends through a whole object tree (following
#  references) decoding everything it can find

#------------------

=item decodeObject OBJECTNUM

I<For INTERNAL use>

Remove any filters (like compression, etc) from a data stream
indicated by the object number.

=cut

sub decodeObject
{
   my $doc = shift;
   my $objnum = shift;

   my $obj = $doc->dereference($objnum);

   $doc->decodeOne($obj->{value}, 1);
}

#------------------

=item decodeAll OBJECT

I<For INTERNAL use>

Remove any filters from any data stream in this object or any object
referenced by it.

=cut

sub decodeAll
{
   my $doc = shift;
   my $obj = shift;

   $doc->traverse(1, $obj, \&decodeOne, 1);
}

#------------------

=item decodeOne OBJECT

=item decodeOne OBJECT, SAVE?

I<For INTERNAL use>

Remove any filters from an object.  The boolean flag SAVE (defaults to
false) indicates whether this defiltering should be permanent or just
this once.  If true, the function returns success or failure.  If
false, the function returns the defiltered content.

=cut

sub decodeOne
{
   my $doc = shift;
   my $obj = shift;
   my $save = shift || 0;

   my $changed = 0;
   my $data = "";

   if ($obj->{type} eq "dictionary")
   {
      my $dict = $obj->{value};

      $data = $dict->{StreamData}->{value};
      #warn "decoding thing " . ($dict->{StreamData}->{objnum} || "(unknown)") . "\n";

      # Don't work on {F} since that's too common a word
      #my $filtobj = $dict->{Filter} || $dict->{F};
      my $filtobj = $dict->{Filter}; 

      if (defined $filtobj)
      {
         my @filters;
         if ($filtobj->{type} eq "array")
         {
            @filters = @{$filtobj->{value}};
         }
         else
         {
            @filters = ($filtobj);
         }
         my $parmobj = $dict->{DecodeParms} || $dict->{DP};
         my @parms;
         if (!$parmobj)
         {
            @parms = ();
         }
         elsif ($parmobj->{type} eq "array")
         {
            @parms = @{$parmobj->{value}};
         }
         else
         {
            @parms = ($parmobj);
         }

         foreach my $filter (@filters)
         {
            if ($filter->{type} ne "label")
            {
               warn("All filter names must be labels\n");
               require Data::Dumper;
               warn Data::Dumper->Dump([$filter], ["Filter"]);
               next;
            }
            my $filtername = $filter->{value};

            # Make sure this is not an encrypt dict
            next if ($filtername eq "Standard");

            #if ($filtername eq "LZWDecode" || $filtername eq "LZW")
            #{
            #   warn("$filtername filter not supported\n");
            #   next;
            #}

            my $filt;
            eval {
               #no strict qw(vars);
               require Text::PDF::Filter;
               my $package = "Text::PDF::" . ($filterabbrevs{$filtername} || $filtername);
               $filt = $package->new;
               die if (!$filt);
            };
            if ($@)
            {
               warn("Failed to open filter $filtername (Text::PDF::$filtername)\n");
               last;
            }

            my $oldlength = length($data);
            {
               # Hack to turn off warnings in Filter library
               local $^W = 0;
               $data = $filt->infilt($data, 1);
            }
            $doc->fixDecode(\$data, $filtername, shift @parms);
            my $length = length($data);

            #warn "decoded length: $oldlength -> $length\n";

            if ($save)
            {
               my $objnum = $dict->{StreamData}->{objnum};
               my $gennum = $dict->{StreamData}->{gennum};
               $doc->{changes}->{$objnum} = 1 if ($objnum);
               $changed = 1;
               $dict->{StreamData}->{value} = $data;
               if ($length != $oldlength)
               {
                  $dict->{Length} = CAM::PDF::Node->new("number", $length, $objnum, $gennum);
                  delete $dict->{L};
               }
               
               # These changes should happen later, but I prefer to do it
               # redundantly near the changes hash
               delete $dict->{Filter};
               delete $dict->{F};
               delete $dict->{DecodeParms};
               delete $dict->{DP};
            }
         }
      }
   }

   if ($save)
   {
      return $changed;
   }
   else
   {
      return $data;
   }
}

#------------------
# PRIVATE FUNCTION
#  fixDecode - do any tweaking after removing the filter from a data stream

sub fixDecode
{
   my $doc = shift;
   my $data = shift;
   my $filter = shift;
   my $parms = shift;

   return if (!$parms);
   my $d = $doc->getValue($parms);
   if ((!$d) || ref $d ne "HASH")
   {
      die "DecodeParms must be a dictionary.\n";
   }
   if ($filter eq "FlateDecode" || $filter eq "Fl" || 
       $filter eq "LZWDecode" || $filter eq "LZW")
   {
      if (exists $d->{Predictor})
      {
         my $p = $doc->getValue($d->{Predictor});
         if ($p >= 10 && $p <= 15)
         {
            #warn "Fix PNG\n";
            if (exists $d->{Columns})
            {
               my $c = $doc->getValue($d->{Columns});
               my $l = length($$data);
               my $newdata = "";
               for (my $i=1; $i < $l; $i += $c+1)
               {
                  $newdata .= substr $$data, $i, $c;
               }
               $$data = $newdata;
            }
         }
      }
   }
}

#------------------

=item encodeObject OBJECTNUM, FILTER

Apply the specified filter to the object.

=cut

sub encodeObject
{
   my $doc = shift;
   my $objnum = shift;
   my $filtername = shift;

   my $obj = $doc->dereference($objnum);

   $doc->encodeOne($obj->{value}, $filtername);
}

#------------------

=item encodeOne OBJECT, FILTER

Apply the specified filter to the object.

=cut

sub encodeOne
{
   my $doc = shift;
   my $obj = shift;
   my $filtername = shift;

   my $changed = 0;

   if ($obj->{type} eq "dictionary")
   {
      my $dict = $obj->{value};
      my $objnum = $obj->{objnum};
      my $gennum = $obj->{gennum};

      if (! exists $dict->{StreamData})
      {
         #warn "Object does not contain a Stream to encode\n";
         return 0;
      }

      if ($filtername eq "LZWDecode" || $filtername eq "LZW")
      {
         $filtername = "FlateDecode";
         warn("LZWDecode filter not supported for encoding.  Using $filtername instead\n");
      }
      my $filt;
      eval {
         #no strict qw(vars);
         require "Text/PDF/Filter.pm";
         my $package = "Text::PDF::$filtername";
         $filt = $package->new;
         die if (!$filt);
      };
      if ($@)
      {
         warn("Failed to open filter $filtername (Text::PDF::$filtername)\n");
         return 0;
      }

      my $l = $dict->{Length} || $dict->{L};
      my $oldlength = $doc->getValue($l);
      $dict->{StreamData}->{value} = $filt->outfilt($dict->{StreamData}->{value}, 1);
      my $length = length($dict->{StreamData}->{value});

      if ((! defined $oldlength) || $length != $oldlength)
      {
         if (defined $l && $l->{type} eq "reference")
         {
            my $lenobj = $doc->dereference($l->{value})->{value};
            if ($lenobj->{type} ne "number")
            {
               die "Expected length to be a reference to an object containing a number while encoding\n";
            }
            $lenobj->{value} = $length;
         }
         elsif ((!defined $l) || $l->{type} eq "number")
         {
            $dict->{Length} = CAM::PDF::Node->new("number", $length, $objnum, $gennum);
            delete $dict->{L};
         }
         else
         {
            die "Unexpected type \"" . $l->{type} . "\" for Length while encoding.\n" .
                "(expected \"number\" or \"reference\")\n";
         }
      }

      # Record the filter
      my $newfilt = CAM::PDF::Node->new("label", $filtername, $objnum, $gennum);
      my $f = $dict->{Filter} || $dict->{F};
      if (!defined $f)
      {
         $dict->{Filter} = $newfilt;
         delete $dict->{F};
      }
      elsif ($f->{type} eq "label")
      {
         $dict->{Filter} = CAM::PDF::Node->new("array", [
                                                         $newfilt,
                                                         $f,
                                                         ],
                                               $objnum, $gennum);
         delete $dict->{F};
      }
      elsif ($f->{type} eq "array")
      {
         unshift @{$f->{value}}, $newfilt;
      }
      else
      {
         die "Confused: Filter type is \"" . $f->{type} . "\", not the\n" .
             "expected \"array\" or \"label\"\n";
      }

      if ($dict->{DecodeParms} || $dict->{DP})
      {
         die "Insertion of DecodeParms not yet supported...\n";
      }

      $doc->{changes}->{$objnum} = 1 if ($objnum);
      $changed = 1;
   }
   return $changed;
}


#------------------

=item setObjNum OBJECT, OBJECTNUM

Descend into an object and change all of the INTERNAL object number
flags to a new number.  This is just for consistency of internal
accounting.

=cut

sub setObjNum
{
   my $doc = shift;
   my $obj = shift;
   my $objnum = shift;
   
   $doc->traverse(0, $obj, \&setObjNumCB, $objnum);
}

#------------------
# PRIVATE FUNCTION

sub setObjNumCB
{
   my $doc = shift;
   my $obj = shift;
   my $objnum = shift;
   
   $obj->{objnum} = $objnum;
}

#------------------

=item getRefList OBJECT

I<For INTERNAL use>

Return an array all of objects referred to in this object.

=cut

sub getRefList
{
   my $doc = shift;
   my $obj = shift;
   
   my $list = {};
   $doc->traverse(1, $obj, \&getRefListCB, $list);

   return (sort keys %$list);
}

#------------------
# PRIVATE FUNCTION

sub getRefListCB
{
   my $doc = shift;
   my $obj = shift;
   my $list = shift;
   
   if ($obj->{type} eq "reference")
   {
      $list->{$obj->{value}} = 1;
   }
}

#------------------

=item changeRefKeys OBJECT, HASHREF

I<For INTERNAL use>

Renumber all references in an object.

=cut

sub changeRefKeys
{
   my $doc = shift;
   my $obj = shift;
   my $newrefkeys = shift;

   my $follow = shift || 0;   # almost always false

   $doc->traverse($follow, $obj, \&changeRefKeysCB, $newrefkeys);
}

#------------------
# PRIVATE FUNCTION

sub changeRefKeysCB
{
   my $doc = shift;
   my $obj = shift;
   my $newrefkeys = shift;
   
   if ($obj->{type} eq "reference")
   {
      $obj->{value} = $newrefkeys->{$obj->{value}} if (exists $newrefkeys->{$obj->{value}});
   }
}

#------------------

=item abbrevInlineImage OBJECT

Contract all image keywords to inline abbreviations.

=cut

sub abbrevInlineImage
{
   my $doc = shift;
   my $obj = shift;

   $doc->traverse(0, $obj, \&abbrevInlineImageCB, {reverse %inlineabbrevs});
}

#------------------

=item unabbrevInlineImage OBJECT

Expand all inline image abbreviations.

=cut

sub unabbrevInlineImage
{
   my $doc = shift;
   my $obj = shift;

   $doc->traverse(0, $obj, \&abbrevInlineImageCB, \%inlineabbrevs);
}

#------------------
# PRIVATE FUNCTION

sub abbrevInlineImageCB
{
   my $doc = shift;
   my $obj = shift;
   my $convert = shift;

   if ($obj->{type} eq "label")
   {
      my $new = $convert->{$obj->{value}};
      $obj->{value} = $new if (defined $new);
   }
   elsif ($obj->{type} eq "dictionary")
   {
      my $dict = $obj->{value};
      foreach my $key (keys %$dict)
      {
         my $new = $convert->{$key};
         if (defined $new && $new ne $key)
         {
            $dict->{$new} = $dict->{$key};
            delete $dict->{$key};
         }
      }
   }
}

#------------------

=item changeString OBJECT, HASHREF

Alter all instances of a given string.  The hashref is a dictionary of
oldstring and newstring.  If the oldstring looks like 'regex(...)'
then it is intrepreted as a Perl regular expresssion and is eval'ed.
Otherwise the search-and-replace is literal.

=cut

sub changeString
{
   my $doc = shift;
   my $obj = shift;
   my $changelist = shift;

   $doc->traverse(0, $obj, \&changeStringCB, $changelist);
}

#------------------
# PRIVATE FUNCTION

sub changeStringCB
{
   my $doc = shift;
   my $obj = shift;
   my $changelist = shift;

   if ($obj->{type} eq "string")
   {
      foreach my $key (keys %$changelist)
      {
         if ($key =~ /^regex\((.*)\)$/)
         {
            my $regex = $1;
            my $res;
            eval "\$res = (\$obj->{value} =~ s/$regex/$$changelist{$key}/gs);";
            if ($@)
            {
               die "Failed regex search/replace: $@\n";
            }
            if ($res)
            {
               $doc->{changes}->{$obj->{objnum}} = 1 if ($obj->{objnum});
            }
         }
         else
         {
            if ($obj->{value} =~ s/$key/$$changelist{$key}/gs)
            {
               $doc->{changes}->{$obj->{objnum}} = 1 if ($obj->{objnum});
            }
         }
      }
   }
}

######################################################################

=back

=head2 Utility functions

(these are for internal use only)

=over 4

=cut

#------------------
# PRIVATE FUNCTION

sub rangeToArray
{
   my $pkg_or_doc = shift;
   my $min = shift;
   my $max = shift;
   my @array1 = @_;

   @array1 = map { 
      s/[^\d\-,]//g if (defined $_);  # clean
      defined $_ ? /([\d\-]+)/g : ()
   } @array1;

   my @array2;
   if (@array1 == 0)
   {
      @array2 = $min .. $max;
   }
   else
   {
      foreach (@array1)
      {
         if (/(\d*)-(\d*)/)
         {
            my $a = $1;
            my $b = $2;
            $a = $min-1 if ($a eq "");
            $b = $max+1 if ($b eq "");
            
            # Check if these are possible
            next if ($a < $min && $b < $min);
            next if ($a > $max && $b > $max);
            
            $a = $min if ($a < $min);
            $b = $min if ($b < $min);
            $a = $max if ($a > $max);
            $b = $max if ($b > $max);
            
            if ($a > $b)
            {
               push @array2, reverse $b .. $a;
            }
            else
            {
               push @array2, $a .. $b;
            }
         }
         else
         {
            push @array2, $_ if ($_ >= $min && $_ <= $max);
         }
      }
   }
   return @array2;
}

#------------------
# PRIVATE FUNCTION

sub trimstr
{
   my $pkg_or_doc = shift;
   my $s = $_[0];

   if (!defined $s || $s eq "")
   {
      $s = "(empty)";
   }
   elsif (length $s > 40)
   {
      $s = substr($s, pos($_[0])||0, 40) . "...";
   }
   $s =~ s/\r/^M/gs;
   return pos($_[0])." ".$s."\n";
}

#------------------
# PRIVATE FUNCTION

sub copyObject
{
   my $doc = shift;
   my $obj = shift;

   # replace $obj with a copy of itself
   require Data::Dumper;
   my $d = Data::Dumper->new([$obj],["obj"]);
   $d->Purity(1)->Indent(0);
   eval $d->Dump();

   return $obj;
}   


#------------------
# PRIVATE FUNCTION

sub cacheObjects
{
   my $doc = shift;

   foreach my $key (keys %{$doc->{xref}})
   {
      if (!exists $doc->{objcache}->{$key})
      {
         $doc->{objcache}->{$key} = $doc->dereference($key);
      }
   }
}

#------------------
# PRIVATE FUNCTION

sub asciify
{
   my $pkg_or_doc = shift;
   my $R_string = shift;   # scalar reference

   ## Heuristics: fix up some odd text characters:
   # f-i ligature
   $$R_string =~ s/\223/fi/g;
   # Registered symbol
   $$R_string =~ s/\xae/(R)/g;
   return $pkg_or_doc;
}

######################################################################

package CAM::PDF::Node;

sub new
{
   my $pkg = shift;

   my $self = {
      type => shift,
      value => shift,
   };

   my $objnum = shift;
   my $gennum = shift;
   $self->{objnum} = $objnum if (defined $objnum);
   $self->{gennum} = $gennum if (defined $gennum);

   return bless($self, $pkg);
}

1;
__END__

=back

=head1 INTERNALS

The data structure used to represent the PDF document is composed
primarily of a heirarchy of Node objects.  Every node in the document
tree has this structure:

    type => <type>
    value => <value>
    objnum => <object number>
    gennum => <generation number>

where the <value> depends on the <type>, and <type> is one of 

     Type        Value
     ----        -----
     object      Node
     stream      byte string
     string      byte string
     hexstring   byte string
     number      number
     reference   integer (object number)
     boolean     "true" | "false"
     label       string
     array       arrayref of Nodes
     dictionary  hashref of (string => Node)
     null        undef

All of these except "stream" are directly related to the PDF data
types of the same name.  Streams are treated as special cases in this
library since the have a non-general syntax and placement in the
document body.  Internally, streams are very much like strings, except
that they have filters applied to them.

All objects are referenced indirectly by their numbers, as defined in
the PDF document.  In all cases, the dereference() function should be
used to deserialize objects into their internal representation.  This
function is also useful for looking up named objects in the page model
metadata.  Every node in the heirarchy contains its object and
generation number.  You can think of this as a sort of a pointer back
to the root of each node tree.  This serves in place of a "parent"
link for every node, which would be harder to maintain.

The PDF document itself is represented internally as a hash reference
with many components, including the document content, the document
metadata (index, trailer and root node), the object cache, and several
other caches, in addition to a few assorted bookkeeping structures.

The core of the document is represented in the object cache, which is
only populated as needed, thus avoiding the overhead of parsing the
whole document at read time.

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>

Primary developer: Chris Dolan
