package CAM::PDF;

use 5.006;
use warnings;
use strict;
use Carp;
use English qw(-no_match_vars);
use CAM::PDF::Node;
use CAM::PDF::Decrypt;

our $VERSION = '1.05';

=for stopwords eval'ed CR-NL PDFLib defiltered prefill indices inline de-embedding

=head1 NAME

CAM::PDF - PDF manipulation library

=head1 LICENSE

Copyright 2005 Clotho Advanced Media, Inc., <cpan@clotho.com>

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SYNOPSIS

    use CAM::PDF;
    
    my $pdf = CAM::PDF->new('test1.pdf');
    
    my $page1 = $pdf->getPageContent(1);
    [ ... mess with page ... ]
    $pdf->setPageContent(1, $page1);
    [ ... create some new content ... ]
    $pdf->appendPageContent(1, $newcontent);
    
    my $anotherpdf = CAM::PDF->new('test2.pdf');
    $pdf->appendPDF($anotherpdf);
    
    my @prefs = $pdf->getPrefs();
    $prefs[$CAM::PDF::PREF_OPASS] = 'mypassword';
    $pdf->setPrefs(@prefs);
    
    $pdf->cleanoutput('out1.pdf');
    print $pdf->toPDF();

Many example scripts are included in this distribution to do useful
tasks.  See the C<script> subdirectory.

=head1 DESCRIPTION

This package reads and writes any document that conforms to the PDF
specification generously provided by Adobe at
L<http://partners.adobe.com/public/developer/pdf/index_reference.html>
(link last checked Oct 2005).

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

=cut

our $PREF_OPASS  = 0;
our $PREF_UPASS  = 1;
our $PREF_PRINT  = 2;
our $PREF_MODIFY = 3;
our $PREF_COPY   = 4;
our $PREF_ADD    = 5;

our $MAX_STRING  = 65;  # length of output string

my %filterabbrevs = (
                     AHx => 'ASCIIHexDecode',
                     A85 => 'ASCII85Decode',
                     CCF => 'CCITTFaxDecode',
                     DCT => 'DCTDecode',
                     Fl  => 'FlateDecode',
                     LZW => 'LZWDecode',
                     RL  => 'RunLengthDecode',
                     );

my %inlineabbrevs = (
                     %filterabbrevs,
                     BPC => 'BitsPerComponent',
                     CS  => 'ColorSpace',
                     D   => 'Decode',
                     DP  => 'DecodeParms',
                     F   => 'Filter',
                     H   => 'Height',
                     IM  => 'ImageMask',
                     I   => 'Interpolate',
                     W   => 'Width',
                     CMYK => 'DeviceCMYK',
                     G   => 'DeviceGray',
                     RGB => 'DeviceRGB',
                     I   => 'Indexed',
                     );

=head1 API

=head2 Functions intended to be used externally

 $self = CAM::PDF->new(content | filename | '-')
 $self->toPDF()
 $self->needsSave()
 $self->save()
 $self->cleansave()
 $self->output(filename | '-')
 $self->cleanoutput(filename | '-')
 $self->preserveOrder()
 $self->appendObject(olddoc, oldnum, [follow=(1|0)])
 $self->replaceObject(newnum, olddoc, oldnum, [follow=(1|0)])
    (olddoc can be undef in the above for adding new objects)
 $self->numPages()
 $self->getPageText(pagenum)
 $self->getPageContent(pagenum)
 $self->setPageContent(pagenum, content)
 $self->appendPageContent(pagenum, content)
 $self->deletePage(pagenum)
 $self->deletePages(pagenum, pagenum, ...)
 $self->extractPages(pagenum, pagenum, ...)
 $self->appendPDF(CAM::PDF object)
 $self->prependPDF(CAM::PDF object)
 $self->wrapString(string, width, fontsize, page, fontlabel)
 $self->getFontNames(pagenum)
 $self->addFont(page, fontname, fontlabel, [fontmetrics])
 $self->deEmbedFont(page, fontname, [newfontname])
 $self->deEmbedFontByBaseName(page, basename, [newfont])
 $self->getPrefs()
 $self->setPrefs()
 $self->canPrint()
 $self->canModify()
 $self->canCopy()
 $self->canAdd()
 $self->getFormFieldList()
 $self->fillFormFields(fieldname, value, [fieldname, value, ...])
   or $self->fillFormFields(%values)
 $self->clearFormFieldTriggers(fieldname, fieldname, ...)

Note: 'clean' as in cleansave() and cleanobject() means write a fresh
PDF document.  The alternative (e.g. save()) reuses the existing doc
and just appends to it.  Also note that 'clean' functions sort the
objects numerically.  If you prefer that the new PDF docs more closely
resemble the old ones, call preserveOrder() before cleansave() or
cleanobject().

=head2 Slightly less external, but useful, functions

 $self->toString()
 $self->getPage(pagenum)
 $self->getFont(pagenum, fontname)
 $self->getFonts(pagenum)
 $self->getStringWidth(fontdict, string)
 $self->getFormField(fieldname)
 $self->getFormFieldDict(object)
 $self->isLinearized()
 $self->decodeObject(objectnum)
 $self->decodeAll(any-node)
 $self->decodeOne(dict-node)
 $self->encodeObject(objectnum, filter)
 $self->encodeOne(any-node, filter)
 $self->changeString(obj-node, hashref)

=head2 Deeper utilities

 $self->pageAddName(pagenum, name, objectnum)
 $self->getPageObjnum(pagenum)
 $self->getPropertyNames(pagenum)
 $self->getProperty(pagenum, propname)
 $self->getValue(any-node)
 $self->dereference(objectnum)  or $self->dereference(name,pagenum)
 $self->deleteObject(objectnum)
 $self->copyObject(obj-node)
 $self->cacheObjects()
 $self->setObjNum(obj-node, num)
 $self->getRefList(obj-node)
 $self->changeRefKeys(obj-node, hashref)

=head2 More rarely needed utilities

 $self->getObjValue(objectnum)

=head2 Routines that should not be called

 $self->_startdoc()
 $self->delinearlize()
 $self->build*()
 $self->parse*()
 $self->write*()
 $self->*CB()
 $self->traverse()
 $self->fixDecode()
 $self->abbrevInlineImage()
 $self->unabbrevInlineImage()
 $self->cleanse()
 $self->clean()
 $self->createID()


=head1 FUNCTIONS

=head2 Object creation/manipulation

=over

=item $doc->new($package, $content)

=item $doc->new($package, $content, $ownerpass, $userpass)

=item $doc->new($package, $content, $ownerpass, $userpass, $prompt)

=item $doc->new($package, $content, $ownerpass, $userpass, $options)

Instantiate a new CAM::PDF object.  C<$content> can be a document in a
string, a filename, or '-'.  The latter indicates that the document
should be read from standard input.  If the document is password
protected, the passwords should be passed as additional arguments.  If
they are not known, a boolean C<$prompt> argument allows the programmer to
suggest that the constructor prompt the user for a password.  This is
rudimentary prompting: passwords are in the clear on the console.

This constructor takes an optional final argument which is a hash
reference.  This hash can contain any of the following optional
parameters:

=over

=item prompt_for_password => $boolean

This is the same as the C<$prompt> argument described above.

=item fault_tolerant => $boolean

This flag causes the instance to be more lenient when reading the
input PDF.  Currently, this only affects PDFs which cannot be
successfully decrypted.

=back

=cut

sub new
{
   my $pkg = shift;
   my $content = shift;  # or a filename
   # Optional args:
   my $opassword = shift;
   my $upassword = shift;
   my $options;
   # Backward compatible support for prompt flag as final argument
   if (ref $_[0])
   {
      $options = shift;
      if ((ref $options) ne 'HASH')
      {
         croak 'Options must be a hash reference';
      }
   }
   else
   {
      $options = {
         prompt_for_password => shift,
      };
   }


   my $pdfversion = '1.2';
   if ($content =~ m/ \A%PDF-([\d\.]+) /xms)
   {
      if ($1 && $1 > $pdfversion)
      {
         $pdfversion = $1;
      }
   }
   else
   {
      if (1024 > length $content)
      {
         my $file = $content;
         if ($file eq q{-})
         {
            $content = q{};
            my $offset = 0;
            my $step = 4096;
            while ($step == read STDIN, $content, $step, $offset)
            {
               $offset += $step;
            }
         }
         else
         {
            my $fh;
            if (!open $fh, '<', $file)
            {
               $CAM::PDF::errstr = "Failed to open $file: $!\n";
               return;
            }
            binmode $fh;
            read $fh, $content, (-s $file);
            close $fh;
         }
      }
      if ($content =~ m/ \A%PDF-([\d\.]+) /xms)
      {
         if ($1 && $1 > $pdfversion)
         {
            $pdfversion = $1;
         }
      }
      else
      {
         $CAM::PDF::errstr = "Content does not begin with \"%PDF-\"\n";
         return;
      }
   }
   #warn "got pdfversion $pdfversion\n";

   my $self = {
      options => $options,

      pdfversion => $pdfversion,
      maxstr => $CAM::PDF::MAX_STRING,  # length of output string
      content => $content,
      contentlength => length $content,
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
   bless $self, $pkg;
   if (!$self->_startdoc())
   {
      return;
   }
   if ($self->{trailer}->{ID})
   {
      my $id = $self->getValue($self->{trailer}->{ID});
      if (ref $id)
      {
         my $accum = q{};
         for my $obj (@$id)
         {
            $accum .= $self->getValue($obj);
         }
         $id = $accum;
      }
      $self->{ID} = $id;
   }
   #$self->{ID} ||= q{};

   $self->{crypt} = CAM::PDF::Decrypt->new($self, $opassword, $upassword,
                                          $self->{options}->{prompt_for_password});
   if (!$self->{crypt} && !$self->{options}->{fault_tolerant})
   {
      return;
   }

   return $self;
}

=item $doc->toPDF()

Serializes the data structure as a PDF document stream and returns as
in a scalar.

=cut

sub toPDF
{
   my $self = shift;

   if ($self->needsSave())
   {
      $self->cleansave();
   }
   return $self->{content};
}

=item $doc->toString()

Returns a serialized representation of the data structure.
Implemented via Data::Dumper.

=cut

sub toString
{
   my $self = shift;
   my @skip = @_ == 0 ? qw(content) : @_;

   my %hold = ();
   for my $key (@skip)
   {
      $hold{$key} = delete $self->{$key};
   }

   require Data::Dumper;
   my $result = Data::Dumper->Dump([$self], [qw(doc)]);

   for my $key (keys %hold)
   {
      $self->{$key} = $hold{$key};
   }
   return $result;
}

################################################################################

=back

=head2 Document reading

(all of these functions are intended for internal only)

=over

=cut


# PRIVATE METHOD
# read the document index and some metadata.

sub _startdoc
{
   my $self = shift;
   
   ### Parse the document metadata

   # Start by parsing out the location of the last xref block
   if ($self->{content} !~ m/ startxref\s*(\d+)\s*%%EOF\s*\z /xms)
   {
      $CAM::PDF::errstr = "Cannot find the index in the PDF content\n";
      return;
   }

   # Parse the hierarchy of xref blocks
   $self->{startxref} = $1;
   $self->{trailer} = $self->_buildxref($self->{startxref}, $self->{xref}, $self->{versions});
   if (!defined $self->{trailer})
   {
      return;
   }

   ### Cache some page content descriptors

   # Get the document root catalog
   if (!exists $self->{trailer}->{Root})
   {
      $CAM::PDF::errstr = "No root node present in PDF trailer.\n";
      return;
   }
   my $root = $self->getRootDict();
   if (!$root || (ref $root) ne 'HASH')
   {
      $CAM::PDF::errstr = "The PDF root node is not a dictionary.\n";
      return;
   }

   # Get the root of the page tree
   if (!exists $root->{Pages})
   {
      $CAM::PDF::errstr = "The PDF root node doesn't have a reference to the page tree.\n";
      return;
   }
   my $pages = $self->getPagesDict();
   if (!$pages || (ref $pages) ne 'HASH')
   {
      $CAM::PDF::errstr = "The PDF page tree root is not a dictionary.\n";
      return;
   }

   # Get the number of pages in the document
   $self->{PageCount} = $self->getValue($pages->{Count});
   if (!$self->{PageCount} || $self->{PageCount} < 1)
   {
      $CAM::PDF::errstr = "Bad number of pages in PDF document\n";
      return;
   }

   return 1;
}

# PRIVATE FUNCTION
#  read document index

sub _buildxref
{
   my $self = shift;
   my $startxref = shift;
   my $index = shift;
   my $versions = shift;

   my $trailerpos = index $self->{content}, 'trailer', $startxref;

   # Workaround for Perl 5.6.1 bug
   if ($trailerpos > 0 && $trailerpos < $startxref)
   {
      my $xrefstr = substr $self->{content}, $startxref;
      $trailerpos = $startxref + index $xrefstr, 'trailer';
   }

   my $end = substr $self->{content}, $startxref, $trailerpos-$startxref;

   if ($end !~ s/ \A xref\s+ //xms)
   {
      my $len = length $end;
      $CAM::PDF::errstr = "Could not find PDF cross-ref table at location $startxref/$trailerpos/$len\n" . $self->trimstr($end);
      return;
   }
   my $part = 0;
   while ($end =~ s/ \A (\d+)\s+(\d+)\s+ //xms)
   {
      my $s = $1;
      my $n = $2;

      $part++;
      for my $i (0 .. $n-1)
      {
         my $objnum = $s+$i;
         next if (exists $index->{$objnum});

         my $row = substr $end, $i*20, 20;
         if ($row !~ m/ \A (\d{10}) [ ] (\d{5}) [ ] (\w) /xms)
         {
            $CAM::PDF::errstr = "Could not decipher xref row:\n" . $self->trimstr($row);
            return;
         }
         if ($3 eq 'n')
         {
            $index->{$objnum} = $1;
            $versions->{$objnum} = $2;
         }
         if ($objnum > $self->{maxobj})
         {
            $self->{maxobj} = $objnum;
         }
      }

      $end = substr $end, 20*$n;
   }

   my $sxrefpos = index $self->{content}, 'startxref', $trailerpos;
   if ($sxrefpos > 0 && $sxrefpos < $trailerpos)  # workaround for 5.6.1 bug
   {
      my $tail = substr $self->{content}, $trailerpos;
      $sxrefpos = $trailerpos + index $tail, 'startxref';
   }
   $end = substr $self->{content}, $trailerpos, $sxrefpos-$trailerpos;

   if ($end !~ s/ \A trailer\s* //xms)
   {
      $CAM::PDF::errstr = "Did not find expected trailer block after xref\n" . $self->trimstr($end);
      return;
   }
   my $trailer = $self->parseDict(\$end)->{value};
   if (exists $trailer->{Prev})
   {
      if (!$self->_buildxref($trailer->{Prev}->{value}, $index, $versions))
      {
         return;
      }
   }
   return $trailer;
}

# PRIVATE FUNCTION
# _buildendxref -- compute the end of each object
#    note that this is not always the *actual* end of the object, but
#    we guarantee that the object will end at or before this point.

sub _buildendxref
{
   my $self = shift;

   my $r = {};
   my %rev = reverse %{$self->{xref}};
   my @pos = sort keys %rev;
   for my $i (0 .. $#pos-1)
   {
      # set the end of each object to be the beginning of the next object
      $r->{$rev{$pos[$i]}} = $pos[$i+1];
   }
   # The end of the last object is the end of the file
   $r->{$rev{$pos[$#pos]}} = $self->{contentlength};

   $self->{endxref} = $r;
   return;
}

# PRIVATE FUNTION
# _buildNameTable -- descend into the page tree and extract all XObject
# and Font name references.

sub _buildNameTable
{
   my $self = shift;
   my $pagenum = shift;

   if (!$pagenum || $pagenum eq 'All')   # Build the ENTIRE name table
   {
      $self->cacheObjects();
      for my $p (1 .. $self->{PageCount})
      {
         $self->_buildNameTable($p);
      }
      my %n = ();
      for my $obj (values %{$self->{objcache}})
      {
         if ($obj->{value}->{type} eq 'dictionary')
         {
            my $dict = $obj->{value}->{value};
            if ($dict->{Name})
            {
               $n{$dict->{Name}->{value}} = CAM::PDF::Node->new('reference', $obj->{objnum});
            }
         }
      }
      $self->{Names}->{All} = {%n};
      return;
   }

   return if (exists $self->{Names}->{$pagenum});

   my %n;
   my $page = $self->getPage($pagenum);
   while ($page)
   {
      my $objnum = $self->getPageObjnum($pagenum);
      if (exists $page->{Resources})
      {
         my $r = $self->getValue($page->{Resources});
         for my $key ('XObject', 'Font')
         {
            if (exists $r->{$key})
            {
               my $x = $self->getValue($r->{$key});
               if ((ref $x) eq 'HASH')
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
         $page = $self->getValue($page);
      }
   }

   $self->{Names}->{$pagenum} = {%n};
   return;
}

=item $doc->getRootDict()

Returns the Root dictionary for the PDF.

=cut

sub getRootDict
{
   my $self = shift;

   return $self->getValue($self->{trailer}->{Root});
}

=item $doc->getPagesDict()

Returns the root Pages dictionary for the PDF.

=cut

sub getPagesDict
{
   my $self = shift;

   return $self->getValue($self->getRootDict()->{Pages});
}

=item $doc->parseObj($string)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return an object
Node.  This can be called as a class method in most circumstances, but
is intended as an instance method.

=cut

sub parseObj
{
   my $self = shift;
   my $c = shift;
   my $objnum = shift; #unused
   my $gennum = shift; #unused

   if ($$c !~ m/ \G(\d+)\s+(\d+)\s+obj\s* /cgxms)
   {
      die "Expected object open tag\n" . $self->trimstr($$c);
   }
   $objnum = $1;
   $gennum = $2;

   my $obj;
   if ($$c =~ m/ \G(.*?)endobj\s* /cgxms)
   {
      my $string = $1;
      $obj = $self->parseAny(\$string, $objnum, $gennum);
      if ($string =~ m/ \Gstream /xms)
      {
         if ($obj->{type} ne 'dictionary')
         {
            die "Found an object stream without a preceding dictionary\n" . $self->trimstr($$c);
         }
         $obj->{value}->{StreamData} = $self->parseStream(\$string, $objnum, $gennum, $obj->{value});
      }
   }
   else
   {
      die "Expected endobj\n" . $self->trimstr($$c);
   }
   return CAM::PDF::Node->new('object', $obj, $objnum, $gennum);
}


=item $doc->parseInlineImage($string)

=item $doc->parseInlineImage($string, $objnum)

=item $doc->parseInlineImage($string, $objnum, $gennum)

Given a fragment of PDF page content, parse it and return an object
Node.  This can be called as a class method in some cases, but
is intended as an instance method.

=cut

sub parseInlineImage
{
   my $self = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   if ($$c !~ m/ \GBI\b /xms)
   {
      die "Expected inline image open tag\n" . $self->trimstr($$c);
   }
   my $dict = $self->parseDict($c, $objnum, $gennum, 'BI\\b\\s*', 'ID\\b');
   $self->unabbrevInlineImage($dict);
   $dict->{value}->{Type} = CAM::PDF::Node->new('label', 'XObject', $objnum, $gennum);
   $dict->{value}->{Subtype} = CAM::PDF::Node->new('label', 'Image', $objnum, $gennum);
   $dict->{value}->{StreamData} = $self->parseStream($c, $objnum, $gennum, $dict->{value},
                                                     qr/ \s* /xms, qr/ \s*EI\b /xms);
   $$c =~ m/ \G\s+ /cgxms;

   return CAM::PDF::Node->new('object', $dict, $objnum, $gennum);
}


=item $doc->writeInlineImage($objectnode)

This is the inverse of parseInlineImage(), intended for use only in
the CAM::PDF::Content class.

=cut

sub writeInlineImage
{
   my $self = shift;
   my $obj = shift;

   # Make a copy since we are going to trash the image
   my $dictobj = $self->copyObject($obj)->{value};

   my $dict = $dictobj->{value};
   delete $dict->{Type};
   delete $dict->{Subtype};
   my $stream = $dict->{StreamData}->{value};
   delete $dict->{StreamData};
   $self->abbrevInlineImage($dictobj);
   #$dict->{L} ||= CAM::PDF::Node->new('number', length($stream));
   
   my $str = $self->writeAny($dictobj);
   $str =~ s/ \A <<    /BI /xms;
   $str =~ s/    >> \z / ID/xms;
   $str .= "\n" . $stream . "\nEI";
   return $str;
}

=item $doc->parseStream($string, $objnum, $gennum, $dictnode)

This should only be used by parseObj(), or other specialized cases.

Given a fragment of PDF page content, parse it and return a stream
Node.  This can be called as a class method in most circumstances, but
is intended as an instance method.

The dictionary Node argument is typically the body of the object Node
that precedes this stream.

=cut

sub parseStream
{
   my $self   = shift;
   my $c      = shift;
   my $objnum = shift;
   my $gennum = shift;
   my $dict   = shift;

   my $begin = shift || qr/ stream\r?\n /xms;
   my $end   = shift || qr/ \s*endstream\s* /xms;

   if ($$c !~ m/ \G$begin /cgxms)
   {
      die "Expected stream open tag\n" . $self->trimstr($$c);
   }

   my $stream;

   my $l = $dict->{Length} || $dict->{L};
   if (!defined $l)
   {
      if ($begin =~ m/ \Gstream /xms)
      {
         die "Missing stream length\n" . $self->trimstr($$c);
      }
      if ($$c =~ m/ \G$begin(.*?)$end /cgxms)
      {
         $stream = $1;
         my $len = length $stream;
         $dict->{Length} = CAM::PDF::Node->new('number', $len, $objnum, $gennum);
      }
      else
      {
         die "Missing stream begin/end\n" . $self->trimstr($$c);
      }
   }
   else
   {
      my $length = $self->getValue($l);
      my $pos = pos $$c;
      $stream = substr $$c, $pos, $length;
      pos($$c) += $length;    ## no critic for builtin with parens
      if ($$c !~ m/ \G$end /cgxms)
      {
         die "Expected endstream\n" . $self->trimstr($$c);
      }
   }

   if (ref $self)
   {
      # in the rare case of CAM::PDF::Content::_parseInlineImage, this
      # may be called as a class method, thus making the above test
      # necessary

      if ($self->{crypt})
      {
         $stream = $self->{crypt}->decrypt($self, $stream, $objnum, $gennum);
      }
   }

   return CAM::PDF::Node->new('stream', $stream, $objnum, $gennum);
}

=item $doc->parseDict($string)

=item $doc->parseDict($string, $objnum)

=item $doc->parseDict($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return an dictionary
Node.  This can be called as a class method in most circumstances, but
is intended as an instance method.

=cut

sub parseDict
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $begin = shift || '<<\\s*';
   my $end = shift || '>>\\s*';

   my $dict = {};
   if ($$c =~ m/ \G$begin /cgxms)
   {
      while ($$c !~ m/ \G$end /cgxms)
      {
         #warn "looking for label:\n" . $pkg_or_doc->trimstr($$c);
         my $keyref = $pkg_or_doc->parseLabel($c, $objnum, $gennum);
         my $key = $keyref->{value};
         #warn "looking for value:\n" . $pkg_or_doc->trimstr($$c);
         my $value = $pkg_or_doc->parseAny($c, $objnum, $gennum);
         $$dict{$key} = $value;
      }
   }

   return CAM::PDF::Node->new('dictionary', $dict, $objnum, $gennum);
}

=item $doc->parseArray($string)

=item $doc->parseArray($string, $objnum)

=item $doc->parseArray($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return an array
Node.  This can be called as a class or instance method.

=cut

sub parseArray
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $array = [];
   if ($$c =~ m/ \G\[\s* /cgxms)
   {
      while ($$c !~ m/ \G\]\s* /cgxms)
      {
         #warn "looking for array value:\n" . $pkg_or_doc->trimstr($$c);
         push @$array, $pkg_or_doc->parseAny($c, $objnum, $gennum);
      }
   }

   return CAM::PDF::Node->new('array', $array, $objnum, $gennum);
}

=item $doc->parseLabel($string)

=item $doc->parseLabel($string, $objnum)

=item $doc->parseLabel($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return a label
Node.  This can be called as a class or instance method.

=cut

sub parseLabel
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $label;
   if ($$c =~ m/ \G\/([^\s<>\/\[\]\(\)]+)\s* /cgxms)
   {
      $label = $1;
   }
   else
   {
      die "Expected identifier label:\n" . $pkg_or_doc->trimstr($$c);
   }
   return CAM::PDF::Node->new('label', $label, $objnum, $gennum);
}

=item $doc->parseRef($string)

=item $doc->parseRef($string, $objnum)

=item $doc->parseRef($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return a reference
Node.  This can be called as a class or instance method.

=cut

sub parseRef
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $newobjnum;
   if ($$c =~ m/ \G(\d+)\s+\d+\s+R\s* /cgxms)
   {
      $newobjnum = $1;
   }
   else
   {
      die "Expected object reference\n" . $pkg_or_doc->trimstr($$c);
   }
   return CAM::PDF::Node->new('reference', $newobjnum, $objnum, $gennum);
}

=item $doc->parseNum($string)

=item $doc->parseNum($string, $objnum)

=item $doc->parseNum($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return a number
Node.  This can be called as a class or instance method.

=cut

sub parseNum
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $value;
   if ($$c =~ m/ \G([\d\.\-\+]+)\s* /cgxms)
   {
      $value = $1;
   }
   else
   {
      die "Expected numerical constant\n" . $pkg_or_doc->trimstr($$c);
   }
   return CAM::PDF::Node->new('number', $value, $objnum, $gennum);
}

=item $doc->parseString($string)

=item $doc->parseString($string, $objnum)

=item $doc->parseString($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return a string
Node.  This can be called as a class or instance method.

=cut

sub parseString
{
   my $pkg_or_doc = shift;
   my $c          = shift;
   my $objnum     = shift;
   my $gennum     = shift;

   my $value = q{};
   if ($$c =~ m/ \G\( /cgxms)
   {
      # TODO: use Text::Balanced or Regexp::Common from CPAN??

      my $depth = 1;
      while ($depth > 0)
      {
         if ($$c =~ m/ \G([^\(\)]*)([\(\)]) /cgxms)
         {
            my $string = $1;
            my $delim  = $2;
            $value .= $string;
            
            # Make sure this is not an escaped paren, OR an real paren
            # preceded by an escaped backslash!
            if ($string =~ m/ (\\+) \z/xms && 1 == (length $1) % 2)
            {
               $value .= $delim;
            }
            elsif ($delim eq '(')
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
      $$c =~ m/ \G\s* /cgxms;
   }
   else
   {
      die "Expected string opener\n" . $pkg_or_doc->trimstr($$c);
   }

   # Unescape slash-escaped characters.  Treat \\ specially.
   my @parts = split /\\\\/xms, $value, -1;
   for (@parts)
   {
      # concatenate continued lines
      s/ \\\r?\n //gxms;
      s/ \\\r    //gxms;

      # special characters
      s/ \\n /\n/gxms;
      s/ \\r /\r/gxms;
      s/ \\t /\t/gxms;
      s/ \\f /\f/gxms;
      # TODO: handle backspace char
      #s/ \\b /???/gxms;

      # octal numbers
      s/ \\(\d{1,3}) /chr oct $1/gexms;

      # Ignore all other slashes (i.e. following characters are treated literally)
      s/ \\ //gxms;
   }
   $value = join q{\\}, @parts;

   if (ref $pkg_or_doc)
   {
      my $self = $pkg_or_doc;
      if ($self->{crypt})
      {
         $value = $self->{crypt}->decrypt($self, $value, $objnum, $gennum);
      }
   }
   return CAM::PDF::Node->new('string', $value, $objnum, $gennum);
}

=item $doc->parseHexString($string)

=item $doc->parseHexString($string, $objnum)

=item $doc->parseHexString($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return a hex string
Node.  This can be called as a class or instance method.

=cut

sub parseHexString
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $str = q{};
   if ($$c =~ m/ \G<([\da-fA-F]*)>\s* /cgxms)
   {
      $str = $1;
      my $len = length $str;
      if ($len % 2 == 1)
      {
         $str .= '0';
      }
      $str = pack 'H*', $str;
   }
   else
   {
     die "Expected hex string\n" . $pkg_or_doc->trimstr($$c);
   }

   if (ref $pkg_or_doc)
   {
      my $self = $pkg_or_doc;
      if ($self->{crypt})
      {
         $str = $self->{crypt}->decrypt($self, $str, $objnum, $gennum);
      }
   }
   return CAM::PDF::Node->new('hexstring', $str, $objnum, $gennum);
}

=item $doc->parseBoolean($string)

=item $doc->parseBoolean($string, $objnum)

=item $doc->parseBoolean($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return a boolean
Node.  This can be called as a class or instance method.

=cut

sub parseBoolean
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $val = q{};
   if ($$c =~ m/ \G(true|false)\s* /cgxmsi)
   {
      $val = lc $1;
   }
   else
   {
     die "Expected boolean true or false keyword\n" . $pkg_or_doc->trimstr($$c);
   }

   return CAM::PDF::Node->new('boolean', $val, $objnum, $gennum);
}

=item $doc->parseNull($string)

=item $doc->parseNull($string, $objnum)

=item $doc->parseNull($string, $objnum, $gennum)

Use parseAny() instead of this, if possible.

Given a fragment of PDF page content, parse it and return a null
Node.  This can be called as a class or instance method.

=cut

sub parseNull
{
   my $pkg_or_doc = shift;
   my $c = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $val = q{};
   if ($$c =~ m/ \Gnull\s* /cgxmsi)
   {
      $val = undef;
   }
   else
   {
     die "Expected null keyword\n" . $pkg_or_doc->trimstr($$c);
   }

   return CAM::PDF::Node->new('null', $val, $objnum, $gennum);
}

=item $doc->parseAny($string)

=item $doc->parseAny($string, $objnum)

=item $doc->parseAny($string, $objnum, $gennum)

Given a fragment of PDF page content, parse it and return a Node of
the appropriate type.  This can be called as a class or instance
method.

=cut

sub parseAny
{
   my $p      = shift;  # pkg or doc
   my $c      = shift;
   my $objnum = shift;
   my $gennum = shift;

   return $$c =~ m/ \G \d+\s+\d+\s+R\b /xms  ? $p->parseRef(      $c, $objnum, $gennum)
        : $$c =~ m/ \G \/              /xms  ? $p->parseLabel(    $c, $objnum, $gennum)
        : $$c =~ m/ \G <<              /xms  ? $p->parseDict(     $c, $objnum, $gennum)
        : $$c =~ m/ \G \[              /xms  ? $p->parseArray(    $c, $objnum, $gennum)
        : $$c =~ m/ \G \(              /xms  ? $p->parseString(   $c, $objnum, $gennum)
        : $$c =~ m/ \G \<              /xms  ? $p->parseHexString($c, $objnum, $gennum)
        : $$c =~ m/ \G [\d\.\-\+]+     /xms  ? $p->parseNum(      $c, $objnum, $gennum)
        : $$c =~ m/ \G (true|false)    /ixms ? $p->parseBoolean(  $c, $objnum, $gennum)
        : $$c =~ m/ \G null            /ixms ? $p->parseNull(     $c, $objnum, $gennum)
        : die "Unrecognized type in parseAny:\n" . $p->trimstr($$c);
}

################################################################################

=back

=head2 Data Accessors

=over

=item $doc->getValue($object)

I<For INTERNAL use>

Dereference a data object, return a value.  Given an node object
of any kind, returns raw scalar object: hashref, arrayref, string,
number.  This function follows all references, and descends into all
objects.

=cut

sub getValue
{
   my $self = shift;
   my $obj = shift;

   return if (! ref $obj);

   while ($obj->{type} eq 'reference' || $obj->{type} eq 'object')
   {
      if ($obj->{type} eq 'reference')
      {
         my $objnum = $obj->{value};
         $obj = $self->dereference($objnum);
      }
      if ($obj->{type} eq 'object')
      {
         $obj = $obj->{value};
      }
      return if (! ref $obj);
   }

   return $obj->{value};
}

=item $doc->getObjValue($objectnum)

I<For INTERNAL use>

Dereference a data object, and return a value.  Behaves just like the
getValue() function, but used when all you know is the object number.

=cut

sub getObjValue
{
   my $self = shift;
   my $objnum = shift;

   return $self->getValue(CAM::PDF::Node->new('reference', $objnum));
}


=item $doc->dereference($objectnum)

=item $doc->dereference($name, $pagenum)

I<For INTERNAL use>

Dereference a data object, return a PDF object as an node.  This
function makes heavy use of the internal object cache.  Most (if not
all) object requests should go through this function.

C<$name> should look something like '/R12'.

=cut

sub dereference
{
   my $self = shift;
   my $key = shift;
   my $pagenum = shift; # only used if $key is a named resource

   if ($key =~ s/ \A\/ //xms)  # strip off the leading slash while testing
   {
      # This is a request for a named object
      $self->_buildNameTable($pagenum);
      $key = $self->{Names}->{$pagenum}->{$key};
      return if (!defined $key);
      # $key should now point to a 'reference' object
      if ((ref $key) ne 'CAM::PDF::Node')
      {
         die "Assertion failed: key is a reference object in dereference\n";
      }
      $key = $key->{value};
   }

   if (!exists $self->{objcache}->{$key})
   {
      #print "Filling cache for obj \#$key...\n";

      my $pos = $self->{xref}->{$key};

      if (!$pos)
      {
         warn "Bad request for object $key at position 0 in the file\n";
         return;
      }

      ## This is the old method.  It is slow.  Below is faster.
      #my $end = substr $self->{content}, $pos;

      ## This is faster, but disastrous if 'endobj' is a string in the obj!!!
      #$endpos = index $self->{content}, 'endobj', $pos;
      #if ($endpos == -1)
      #{
      #   die "Didn't find endobj after obj\n";
      #}

      # This is fastest and safest
      if (!exists $self->{endxref})
      {
         $self->_buildendxref();
      }
      my $endpos = $self->{endxref}->{$key};
      if (!defined $endpos || $endpos < $pos)
      {
         # really slow, but a totally safe fallback
         $endpos = $self->{contentlength};
      }

      my $end = substr $self->{content}, $pos, $endpos - $pos + 6;
      $self->{objcache}->{$key} = $self->parseObj(\$end, $key);
   }

   return $self->{objcache}->{$key};
}


=item $doc->getPropertyNames($pagenum)

=item $doc->getProperty($pagenum, $propertyname)

Each PDF page contains a list of resources that it uses (images,
fonts, etc).  getPropertyNames() returns an array of the names of
those resources.  getProperty() returns a node representing a
named property (most likely a reference node).

=cut

sub getPropertyNames
{
   my $self = shift;
   my $pagenum = shift;

   $self->_buildNameTable($pagenum);
   my $props = $self->{Names}->{$pagenum};
   return if (!defined $props);
   return keys %$props;
}
sub getProperty
{
   my $self = shift;
   my $pagenum = shift;
   my $name = shift;

   $self->_buildNameTable($pagenum);
   my $props = $self->{Names}->{$pagenum};
   return if (!defined $props);
   return if (!defined $name);
   return $props->{$name};
}

=item $doc->getFont($pagenum, $fontname)

I<For INTERNAL use>

Returns a dictionary for a given font identified by its label,
referenced by page.

=cut

sub getFont
{
   my $self = shift;
   my $pagenum = shift;
   my $fontname = shift;

   $fontname =~ s/ \A\/? /\//xms; # add leading slash if needed
   my $obj = $self->dereference($fontname, $pagenum);
   return if (!$obj);

   my $dict = $self->getValue($obj);
   if ($dict && $dict->{Type} && $dict->{Type}->{value} eq 'Font')
   {
      return $dict;
   }
   else
   {
      return;
   }
}

=item $doc->getFontNames($pagenum)

I<For INTERNAL use>

Returns a list of fonts for a given page.

=cut

sub getFontNames
{
   my $self = shift;
   my $pagenum = shift;

   $self->_buildNameTable($pagenum);
   my $list = $self->{Names}->{$pagenum};
   my @names;
   if ($list)
   {
      for my $key (keys %$list)
      {
         my $dict = $self->getValue($list->{$key});
         if ($dict && $dict->{Type} && $dict->{Type}->{value} eq 'Font')
         {
            push @names, $key;
         }
      }
   }
   return @names;
}


=item $doc->getFonts($pagenum)

I<For INTERNAL use>

Returns an array of font objects for a given page.

=cut

sub getFonts
{
   my $self = shift;
   my $pagenum = shift;

   $self->_buildNameTable($pagenum);
   my $list = $self->{Names}->{$pagenum};
   my @fonts;
   if ($list)
   {
      for my $key (keys %$list)
      {
         my $dict = $self->getValue($list->{$key});
         if ($dict && $dict->{Type} && $dict->{Type}->{value} eq 'Font')
         {
            push @fonts, $dict;
         }
      }
   }
   return @fonts;
}

=item $doc->getFontByBaseName($pagenum, $fontname)

I<For INTERNAL use>

Returns a dictionary for a given font, referenced by page and the name
of the base font.

=cut

sub getFontByBaseName
{
   my $self = shift;
   my $pagenum = shift;
   my $fontname = shift;

   $self->_buildNameTable($pagenum);
   my $list = $self->{Names}->{$pagenum};
   for my $key (keys %$list)
   {
      my $num = $list->{$key}->{value};
      my $obj = $self->dereference($num);
      my $dict = $self->getValue($obj);
      if ($dict &&
          $dict->{Type} && $dict->{Type}->{value} eq 'Font' &&
          $dict->{BaseFont} && $dict->{BaseFont}->{value} eq $fontname)
      {
         return $dict;
      }
   }
   return;
}

=item $doc->getFontMetrics($properties $fontname)

I<For INTERNAL use>

Returns a data structure representing the font metrics for the named
font.  The property list is the results of something like the
following:

  $self->_buildNameTable($pagenum);
  my $properties = $self->{Names}->{$pagenum};

Alternatively, if you know the page number, it might be easier to do:

  my $font = $self->dereference($fontlabel, $pagenum);
  my $fontmetrics = $font->{value}->{value};

where the C<$fontlabel> is something like '/Helv'.  The getFontMetrics()
method is useful in the cases where you've forgotten which page number
you are working on (e.g. in CAM::PDF::GS), or if your property list
isn't part of any page (e.g. working with form field annotation
objects).

=cut

sub getFontMetrics
{
   my $self = shift;
   my $props = shift;
   my $fontname = shift;

   my $fontmetrics;

   #print STDERR "looking for font $fontname\n";

   # Sometimes we are passed just the object list, sometimes the whole
   # properties data structure
   if ($props->{Font})
   {
      $props = $self->getValue($props->{Font});
   }

   if ($props->{$fontname})
   {
      my $fontdict = $self->getValue($props->{$fontname});
      if ($fontdict && $fontdict->{Type} && $fontdict->{Type}->{value} eq 'Font')
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
   #print STDERR "Failed to get font\n" if (!$fontmetrics);
   return $fontmetrics;
}

=item $doc->addFont($pagenum, $fontname, $fontlabel)

=item $doc->addFont($pagenum, $fontname, $fontlabel, $fontmetrics)

Adds a reference to the specified font to the page.

If a font metrics hash is supplied (it is required for a font other
than the 14 core fonts), then it is cloned and inserted into the new
font structure.  Note that if those font metrics contain references
(e.g. to the C<FontDescriptor>), the referred objects are not copied --
you must do that part yourself.

For Type1 fonts, the font metrics must minimally contain the following
fields: C<Subtype>, C<FirstChar>, C<LastChar>, C<Widths>,
C<FontDescriptor>.

=cut

sub addFont
{
   my $self = shift;
   my $pagenum = shift;
   my $name = shift;
   my $label = shift;
   my $fontmetrics = shift; # optional

   # Check if this font already exists
   my $page = $self->getPage($pagenum);
   if (exists $page->{Resources})
   {
      my $r = $self->getValue($page->{Resources});
      if (exists $r->{Font})
      {
         my $f = $self->getValue($r->{Font});
         if (exists $f->{$label})
         {
            # Font already exists.  Skip.
            return $self;
         }
      }
   }

   # Build the font
   my $dict = CAM::PDF::Node->new('dictionary',
                                 {
                                    Type => CAM::PDF::Node->new('label', 'Font'),
                                    Name => CAM::PDF::Node->new('label', $label),
                                    BaseFont => CAM::PDF::Node->new('label', $name),
                                 },
                                 );
   if ($fontmetrics)
   {
      my $copy = $self->copyObject($fontmetrics);
      for my $key (keys %$copy)
      {
         if (!$dict->{value}->{$key})
         {
            $dict->{value}->{$key} = $copy->{$key};
         }
      }
   }
   else
   {
      $dict->{value}->{Subtype} = CAM::PDF::Node->new('label', 'Type1');
   }

   # Add the font to the document
   my $fontobjnum = $self->appendObject(undef, CAM::PDF::Node->new('object', $dict), 0);

   # Add the font to the page
   my ($objnum,$gennum) = $self->getPageObjnum($pagenum);
   if (!exists $page->{Resources})
   {
      $page->{Resources} = CAM::PDF::Node->new('dictionary', {}, $objnum, $gennum);
   }
   my $r = $self->getValue($page->{Resources});
   if (!exists $r->{Font})
   {
      $page->{Font} = CAM::PDF::Node->new('dictionary', {}, $objnum, $gennum);
   }
   my $f = $self->getValue($r->{Font});
   $f->{$label} = CAM::PDF::Node->new('reference', $fontobjnum, $objnum, $gennum);

   delete $self->{Names}->{$pagenum}; # decache
   $self->{changes}->{$objnum} = 1;
   return $self;
}

=item $doc->deEmbedFont($pagenum, $fontname)

=item $doc->deEmbedFont($pagenum, $fontname, $basefont)

Removes embedded font data, leaving font reference intact.  Returns
true if the font exists and 1) font is not embedded or 2) embedded
data was successfully discarded.  Returns false if the font does not
exist, or the embedded data could not be discarded.

The optional C<$basefont> parameter allows you to change the font.  This
is useful when some applications embed a standard font (see below) and
give it a funny name, like C<SYLXNP+Helvetica>.  In this example, it's
important to change the basename back to the standard C<Helvetica> when
de-embedding.

De-embedding the font does NOT remove it from the PDF document, it
just removes references to it.  To get a size reduction by throwing
away unused font data, you should use the following code sometime
after this method.

  $self->cleanse();

For reference, the standard fonts are C<Times-Roman>, C<Helvetica>, and
C<Courier> (and their bold, italic and bold-italic forms) plus C<Symbol> and
C<Zapfdingbats>. (Adobe PDF Reference v1.4, p.319)

=cut

sub deEmbedFont
{
   my $self = shift;
   my $pagenum = shift;
   my $fontname = shift;
   my $basefont = shift;

   my $success;
   my $font = $self->getFont($pagenum, $fontname);
   if ($font)
   {
      $self->_deEmbedFontObj($font, $basefont);
      $success = $self;
   }
   else
   {
      $success = undef;
   }
   return $success;
}

=item $doc->deEmbedFontByBaseName($pagenum, $fontname)

=item $doc->deEmbedFontByBaseName($pagenum, $fontname, $basefont)

Just like deEmbedFont(), except that the font name parameter refers to
the name of the current base font instead of the PDF label for the
font.

=cut

sub deEmbedFontByBaseName
{
   my $self = shift;
   my $pagenum = shift;
   my $fontname = shift;
   my $basefont = shift;

   my $success;
   my $font = $self->getFontByBaseName($pagenum, $fontname);
   if ($font)
   {
      $self->_deEmbedFontObj($font, $basefont);
      $success = $self;
   }
   else
   {
      $success = undef;
   }
   return $success;
}

sub _deEmbedFontObj
{
   my $self = shift;
   my $font = shift;
   my $basefont = shift;
   
   if ($basefont)
   {
      $font->{BaseFont} = CAM::PDF::Node->new('label', $basefont);
   }
   delete $font->{FontDescriptor};
   delete $font->{Widths};
   delete $font->{FirstChar};
   delete $font->{LastChar};
   $self->{changes}->{$font->{Type}->{objnum}} = 1;
   return;
}

=item $doc->wrapString($string, $width, $fontsize, $fontmetrics)

=item $doc->wrapString($string, $width, $fontsize, $pagenum, $fontlabel)

Returns an array of strings wrapped to the specified width.

=cut

sub wrapString
{
   my $self = shift;
   my $string = shift;
   my $width = shift;
   my $size = shift;

   my $fm;
   if (defined $_[0] && ref $_[0])
   {
      $fm = shift;
   }
   else
   {
      my $pagenum = shift;
      my $fontlabel = shift;
      $fm = $self->getFont($pagenum, $fontlabel);
   }

   $string =~ s/ \r\n /\n/gxms;
   # no split limit, so trailing null strings are omitted
   my @strings = split /[\r\n]/xms, $string;
   my @out;
   $width /= $size;
   #print STDERR 'wrapping '.join('|',@strings)."\n";
   for my $s (@strings)
   {
      $s =~ s/ \s+\z //xms;
      my $w = $self->getStringWidth($fm, $s);
      if ($w <= $width)
      {
         push @out, $s;
      }
      else
      {
         $s =~ s/ \A(\s*) //xms;
         my $cur = $1;
         my $curw = $cur eq q{} ? 0 : $self->getStringWidth($fm, $cur);
         while ($s)
         {
            $s =~ s/ \A(\s*)(\S*) //xms;
            my $sp = $1;
            my $wd = $2;
            my $wwd = $wd eq q{} ? 0 : $self->getStringWidth($fm, $wd);
            if ($curw == 0)
            {
               $cur = $wd;
               $curw = $wwd;
            }
            else
            {
               my $wsp = $sp eq q{} ? 0 : $self->getStringWidth($fm, $sp);
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
         if (0 < length $cur)
         {
            push @out, $cur;
         }
      }
   }
   #print STDERR 'wrapped to '.join('|',@out)."\n";
   return @out;
}

=item $doc->getStringWidth($fontmetrics, $string)

I<For INTERNAL use>

Returns the width of the string, using the font metrics if possible.

=cut

sub getStringWidth
{
   my $self = shift;
   my $fontmetrics = shift;
   my $string = shift;

   if (! defined $string || $string eq q{})
   {
      return 0;
   }

   my $width = 0;
   if ($fontmetrics)
   {
      if ($fontmetrics->{Widths})
      {
         my $firstc  = $self->getValue($fontmetrics->{FirstChar});
         my $lastc   = $self->getValue($fontmetrics->{LastChar});
         my $widths  = $self->getValue($fontmetrics->{Widths});
         my $missing_width;
         my $fd;
         for my $char (unpack 'C*', $string)
         {
            if ($char >= $firstc && $char <= $lastc)
            {
               $width += $widths->[$char - $firstc]->{value};
            }
            else
            {
               if (!defined $missing_width)
               {
                  $missing_width = 0; # fallback
                  if (!$fd)
                  {
                     if (exists $fontmetrics->{FontDescriptor})
                     {
                        $fd = $self->getValue($fontmetrics->{FontDescriptor});
                     }
                  }
                  if ($fd)
                  {
                     if (exists $fd->{MissingWidth})
                     {
                        $missing_width = $self->getValue($fd->{MissingWidth});
                     }
                  }
               }
               $width += $missing_width;
            }
         }
         $width /= 1000.0;  # units conversion
      }
      elsif ($fontmetrics->{BaseFont})
      {
         my $fontname = $self->getValue($fontmetrics->{BaseFont});
         if (!exists $self->{fontmetrics}->{$fontname})
         {
            require Text::PDF::SFont;
            require Text::PDF::File;
            my $pdf = Text::PDF::File->new();
            $self->{fontmetrics}->{$fontname} =
                Text::PDF::SFont->new($pdf, $fontname, 'NULL');
         }
         if ($self->{fontmetrics}->{$fontname})
         {
            $width = $self->{fontmetrics}->{$fontname}->width($string);
         }
      }
      else
      {
         warn 'Failed to understand this font';
      }
   }

   if ($width == 0)
   {
      # HACK!!!
      #warn "Using klugy width!\n";
      $width = 0.2 * length $string;
   }

   return $width;
}

=item $doc->numPages()

Returns the number of pages in the PDF document.

=cut

sub numPages
{
   my $self = shift;
   return $self->{PageCount};
}

=item $doc->getPage($pagenum)

I<For INTERNAL use>

Returns a dictionary for a given numbered page.

=cut

sub getPage
{
   my $self = shift;
   my $pagenum = shift;

   if ($pagenum < 1 || $pagenum > $self->{PageCount})
   {
      warn "Invalid page number requested: $pagenum\n";
      return;
   }

   if (!exists $self->{pagecache}->{$pagenum})
   {
      my $node = $self->getPagesDict();
      my $nodestart = 1;
      while ($self->getValue($node->{Type}) eq 'Pages')
      {
         #warn "getPage: nodestart $nodestart\n";
         my $kids = $self->getValue($node->{Kids});
         if ((ref $kids) ne 'ARRAY')
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
               my $sub = $self->getValue($kids->[$child]);
               if ($sub->{Type}->{value} ne 'Pages')
               {
                  #warn "getPage:   wrong leaf\n";
                  # Its a leaf, and not the right one.  Move on.
                  $nodestart++;
               }
               else
               {
                  my $count = $self->getValue($sub->{Count});
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

         $node = $self->getValue($kids->[$child]);
         if (! ref $node)
         {
            require Data::Dumper;
            Carp::cluck Data::Dumper::Dumper($node);
         }
      }
      
      #warn "getPage: done\n";

      # Ok, now we've got the right page.  Store it.
      $self->{pagecache}->{$pagenum} = $node;
   }

   return $self->{pagecache}->{$pagenum};
}

=item $doc->getPageObjnum($pagenum)

I<For INTERNAL use>

Return the number of the PDF object in which the specified page occurs.

=cut

sub getPageObjnum
{
   my $self = shift;
   my $pagenum = shift;

   my $page = $self->getPage($pagenum);
   return if (!$page);
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

=item $doc->getPageText($pagenum)

Extracts the text from a PDF page as a string.

=cut

sub getPageText
{
   my $self = shift;
   my $pagenum = shift;
   my $verbose = shift;

   my $pagetree = $self->getPageContentTree($pagenum, $verbose);
   if (!$pagetree)
   {
      return;
   }

   require CAM::PDF::PageText;
   return CAM::PDF::PageText->render($pagetree, $verbose);
}

=item $doc->getPageContentTree($pagenum)

Retrieves a parsed page content data structure, or undef if there is a
syntax error or if the page does not exist.

=cut

sub getPageContentTree
{
   my $self = shift;
   my $pagenum = shift;
   my $verbose = shift;

   my $content = $self->getPageContent($pagenum);
   return if (!defined $content);

   $self->_buildNameTable($pagenum);

   my $page = $self->getPage($pagenum);
   my $box = [0, 0, 612, 792];
   if ($page->{MediaBox})
   {
      my $mediabox = $self->getValue($page->{MediaBox});
      $box->[0] = $self->getValue($mediabox->[0]);
      $box->[1] = $self->getValue($mediabox->[1]);
      $box->[2] = $self->getValue($mediabox->[2]);
      $box->[3] = $self->getValue($mediabox->[3]);
   }

   require CAM::PDF::Content;
   my $tree = CAM::PDF::Content->new($content, {
      doc => $self,
      properties => $self->{Names}->{$pagenum},
      mediabox => $box,
   }, $verbose);

   return $tree;
}

=item $doc->getPageContent($pagenum)

Return a string with the layout contents of one page.

=cut

sub getPageContent
{
   my $self = shift;
   my $pagenum = shift;

   my $page = $self->getPage($pagenum);
   if (!$page || !exists $page->{Contents})
   {
      return q{};
   }

   my $contents = $self->getValue($page->{Contents});

   if (! ref $contents)
   {
      return $contents;
   }
   elsif ((ref $contents) eq 'HASH')
   {
      # doesn't matter if it's not encoded...
      return $self->decodeOne(CAM::PDF::Node->new('dictionary', $contents));
   }
   elsif ((ref $contents) eq 'ARRAY')
   {
      my $stream = q{};
      for my $arrobj (@$contents)
      {
         my $data = $self->getValue($arrobj);
         if (! ref $data)
         {
            $stream .= $data;
         }
         elsif ((ref $data) eq 'HASH')
         {
            $stream .= $self->decodeOne(CAM::PDF::Node->new('dictionary',$data));  # doesn't matter if it's not encoded...
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
      return; # should never get here
   }
}

=item $doc->getName($object)

I<For INTERNAL use>

Given a PDF object reference, return it's name, if it has one.  This
is useful for indirect references to images in particular.

=cut

sub getName
{
   my $self = shift;
   my $obj = shift;

   if ($obj->{value}->{type} eq 'dictionary')
   {
      my $dict = $obj->{value}->{value};
      if (exists $dict->{Name})
      {
         return $self->getValue($dict->{Name});
      }
   }
   return q{};
}

=item $doc->getPrefs()

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

  my ($canCopy) = ($self->getPrefs())[$CAM::PDF::PREF_COPY];

=cut

sub getPrefs
{
   my $self = shift;

   my @p = (1,1,1,1);
   if (exists $self->{crypt}->{P})
   {
      @p = $self->{crypt}->decode_permissions($self->{crypt}->{P});
   }
   return($self->{crypt}->{opass}, $self->{crypt}->{upass}, @p);
}

=item $doc->canPrint()

Return a boolean indicating whether the Print permission is enabled
on the PDF.

=cut

sub canPrint
{
   my $self = shift;
   return ($self->getPrefs())[$PREF_PRINT];
}

=item $doc->canModify()

Return a boolean indicating whether the Modify permission is enabled
on the PDF.

=cut

sub canModify
{
   my $self = shift;
   return ($self->getPrefs())[$PREF_MODIFY];
}

=item $doc->canCopy()

Return a boolean indicating whether the Copy permission is enabled
on the PDF.

=cut

sub canCopy
{
   my $self = shift;
   return ($self->getPrefs())[$PREF_COPY];
}

=item $doc->canAdd()

Return a boolean indicating whether the Add permission is enabled
on the PDF.

=cut

sub canAdd
{
   my $self = shift;
   return ($self->getPrefs())[$PREF_ADD];
}

=item $doc->getFormFieldList()

Return an array of the names of all of the PDF form fields.  The names
are the full hierarchical names constructed as explained in the PDF
reference manual.  These names are useful for the fillFormFields()
function.

=cut

sub getFormFieldList
{
   my $self = shift;
   my $parentname = shift;  # very optional

   my $prefix = (defined $parentname ? $parentname . q{.} : q{});

   my $kidlist;
   if (defined $parentname && $parentname ne q{})
   {
      my $parent = $self->getFormField($parentname);
      return if (!$parent);
      my $dict = $self->getValue($parent);
      return if (!exists $dict->{Kids});
      $kidlist = $self->getValue($dict->{Kids});
   }
   else
   {
      my $root = $self->getRootDict()->{AcroForm};
      return if (!$root);
      my $parent = $self->getValue($root);
      return if (!exists $parent->{Fields});
      $kidlist = $self->getValue($parent->{Fields});
   }

   my @list = ();
   for my $kid (@$kidlist)
   {
      if ((! ref $kid) || (ref $kid) ne 'CAM::PDF::Node' || $kid->{type} ne 'reference')
      {
         die "Expected a reference as the form child of '$parentname'\n";
      }
      my $obj = $self->dereference($kid->{value});
      my $dict = $self->getValue($obj);
      my $name = '(no name)';  # assume the worst
      if (exists $dict->{T})
      {
         $name = $self->getValue($dict->{T});
      }
      $name = $prefix . $name;
      push @list, $name;
      if (exists $dict->{TU})
      {
         push @list, $prefix . $self->getValue($dict->{TU}) . ' (alternate name)';
      }
      $self->{formcache}->{$name} = $obj;
      my @kidnames = $self->getFormFieldList($name);
      if (@kidnames > 0)
      {
         #push @list, 'descend...';
         push @list, @kidnames;
         #push @list, 'ascend...';
      }
   }
   return @list;
}

=item $doc->getFormField($name)

I<For INTERNAL use>

Return the object containing the form field definition for the
specified field name.  C<$name> can be either the full name or the
"short/alternate" name.

=cut

sub getFormField
{
   my $self = shift;
   my $fieldname = shift;

   return if (!defined $fieldname);

   if (! exists $self->{formcache}->{$fieldname})
   {
      my $kidlist;
      my $parent;
      if ($fieldname =~ m/ \. /xms)
      {
         $fieldname =~ s/ \A(.*)\.([\.]+)\z /$2/xms;
         my $parentname = $1;
         $parent = $self->getFormField($parentname);
         return if (!$parent);
         my $dict = $self->getValue($parent);
         return if (!exists $dict->{Kids});
         $kidlist = $self->getValue($dict->{Kids});
      }
      else
      {
         my $root = $self->getRootDict()->{AcroForm};
         return if (!$root);
         $parent = $self->dereference($root->{value});
         return if (!$parent);
         my $dict = $self->getValue($parent);
         return if (!exists $dict->{Fields});
         $kidlist = $self->getValue($dict->{Fields});
      }

      $self->{formcache}->{$fieldname} = undef;  # assume the worst...
      for my $kid (@$kidlist)
      {
         my $obj = $self->dereference($kid->{value});
         $obj->{formparent} = $parent;
         my $dict = $self->getValue($obj);
         if (exists $dict->{T})
         {
            $self->{formcache}->{$self->getValue($dict->{T})} = $obj;
         }
         if (exists $dict->{TU})
         {
            $self->{formcache}->{$self->getValue($dict->{TU})} = $obj;
         }
      }
   }

   return $self->{formcache}->{$fieldname};
}

=item $doc->getFormFieldDict($formfieldobject)

I<For INTERNAL use>

Return a hash reference representing the accumulated property list for
a form field, including all of it's inherited properties.  This should
be treated as a read-only hash!  It ONLY retrieves the properties it
knows about.

=cut

sub getFormFieldDict
{
   my $self = shift;
   my $field = shift;

   return if (!defined $field);

   my $dict = {};
   if ($field->{formparent})
   {
      $dict = $self->getFormFieldDict($field->{formparent});
   }
   my $olddict = $self->getValue($field);

   if ($olddict->{DR})
   {
      $dict->{DR} ||= CAM::PDF::Node->new('dictionary', {});
      my $dr = $self->getValue($dict->{DR});
      my $olddr = $self->getValue($olddict->{DR});
      for my $key (keys %{%$olddr})
      {
         if ($dr->{$key})
         {
            if ($key eq 'Font')
            {
               my $fonts = $self->getValue($olddr->{$key});
               for my $font (keys %$fonts)
               {
                  $dr->{$key}->{$font} = $self->copyObject($fonts->{$font});
               }
            }
            else
            {
               warn "Unknown resource key '$key' in form field dictionary";
            }
         }
         else
         {
            $dr->{$key} = $self->copyObject($olddr->{$key});
         }
      }
   }

   # Some properties are simple: inherit means override
   for my $prop (qw(Q DA Ff V FT))
   {
      if ($olddict->{$prop})
      {
         $dict->{$prop} = $self->copyObject($olddict->{$prop});
      }
   }

   return $dict;
}

################################################################################

=back

=head2 Data/Object Manipulation

=over

=item $doc->setPrefs($ownerpass, $userpass, $print?, $modify?, $copy?, $add?)

Alter the document's security information.  Note that modifying these
parameters must be done respecting the intellectual property of the
original document.  See Adobe's statement in the introduction of the
reference manual.

Note: any omitted booleans default to false.  So, these two are
equivalent:

    $pdf->setPrefs('password', 'password');
    $pdf->setPrefs('password', 'password', 0, 0, 0, 0);

=cut

sub setPrefs
{
   my $self = shift;
   my @prefs = (@_);

   my $p = $self->{crypt}->encode_permissions(@prefs[2..5]);
   $self->{crypt}->set_passwords($self, @prefs[0..1], $p);
   return;
}

=item $doc->setName($object, $name)

I<For INTERNAL use>

Change the name of a PDF object structure.

=cut

sub setName
{
   my $self = shift;
   my $obj = shift;
   my $name = shift;

   if ($name && $obj->{value}->{type} eq 'dictionary')
   {
      $obj->{value}->{value}->{Name} = CAM::PDF::Node->new('label', $name, $obj->{objnum}, $obj->{gennum});
      if ($obj->{objnum})
      {
         $self->{changes}->{$obj->{objnum}} = 1;
      }
      return $self;
   }
   return;
}

=item $doc->removeName($object)

I<For INTERNAL use>

Delete the name of a PDF object structure.

=cut

sub removeName
{
   my $self = shift;
   my $obj = shift;

   if ($obj->{value}->{type} eq 'dictionary' && exists $obj->{value}->{value}->{Name})
   {
      delete $obj->{value}->{value}->{Name};
      if ($obj->{objnum})
      {
         $self->{changes}->{$obj->{objnum}} = 1;
      }
      return $self;
   }
   return;
}


=item $doc->pageAddName($pagenum, $name, $objectnum)

I<For INTERNAL use>

Append a named object to the metadata for a given page.

=cut

sub pageAddName
{
   my $self = shift;
   my $pagenum = shift;
   my $name = shift;
   my $key = shift;

   $self->_buildNameTable($pagenum);
   my $page = $self->getPage($pagenum);
   my ($objnum, $gennum) = $self->getPageObjnum($pagenum);
   
   if (!exists $self->{NameObjects}->{$pagenum})
   {
      if ($objnum)
      {
         $self->{changes}->{$objnum} = 1;
      }
      if (!exists $page->{Resources})
      {
         $page->{Resources} = CAM::PDF::Node->new('dictionary', {}, $objnum, $gennum);
      }
      my $r = $self->getValue($page->{Resources});
      if (!exists $r->{XObject})
      {
         $r->{XObject} = CAM::PDF::Node->new('dictionary', {}, $objnum, $gennum);
      }
      $self->{NameObjects}->{$pagenum} = $self->getValue($r->{XObject});
   }
   
   $self->{NameObjects}->{$pagenum}->{$name} = CAM::PDF::Node->new('reference', $key, $objnum, $gennum);
   if ($objnum)
   {
      $self->{changes}->{$objnum} = 1;
   }
   return;
}

=item $doc->setPageContent($pagenum, $content)

Replace the content of the specified page with a new version.  This
function is often used after the getPageContent() function and some
manipulation of the returned string from that function.

=cut

sub setPageContent
{
   my $self = shift;
   my $pagenum = shift;
   my $content = shift;

   # Note that this *could* be implemented as 
   #   delete current content
   #   appendPageContent
   # but that would lose the optimization below of reusing the content
   # object, where possible

   my $page = $self->getPage($pagenum);

   my $stream = $self->createStreamObject($content, 'FlateDecode');
   if ($page->{Contents} && $page->{Contents}->{type} eq 'reference')
   {
      my $key = $page->{Contents}->{value};
      $self->replaceObject($key, undef, $stream, 0);
   }
   else
   {
      my ($objnum, $gennum) = $self->getPageObjnum($pagenum);
      my $key = $self->appendObject(undef, $stream, 0);
      $page->{Contents} = CAM::PDF::Node->new('reference', $key, $objnum, $gennum);
      $self->{changes}->{$objnum} = 1;
   }
   return;
}

=item $doc->appendPageContent($pagenum, $content)

Add more content to the specified page.  Note that this function does
NOT do any page metadata work for you (like creating font objects for
any newly defined fonts).

=cut

sub appendPageContent
{
   my $self = shift;
   my $pagenum = shift;
   my $content = shift;

   my $page = $self->getPage($pagenum);

   my ($objnum, $gennum) = $self->getPageObjnum($pagenum);
   my $stream = $self->createStreamObject($content, 'FlateDecode');
   my $key = $self->appendObject(undef, $stream, 0);
   my $streamref = CAM::PDF::Node->new('reference', $key, $objnum, $gennum);

   if (!$page->{Contents})
   {
      $page->{Contents} = $streamref;
   }
   elsif ($page->{Contents}->{type} eq 'array')
   {
      push @{$page->{Contents}->{value}}, $streamref;
   }
   elsif ($page->{Contents}->{type} eq 'reference')
   {
      $page->{Contents} = CAM::PDF::Node->new('array', [ $page->{Contents}, $streamref ], $objnum, $gennum);
   }
   else
   {
      die "Unsupported Content type \"$page->{Contents}->{type}\" on page $pagenum\n";
   }
   $self->{changes}->{$objnum} = 1;
   return;
}

=item $doc->extractPages($pages...)

Remove all pages from the PDF except the specified ones.  Like
deletePages(), the pages can be multiple arguments, comma separated
lists, ranges (open or closed).

=cut

sub extractPages
{
   my $self = shift;
   return $self if (@_ == 0); # no-work shortcut
   my @pages = $self->rangeToArray(1,$self->numPages(),@_);

   if (@pages == 0)
   {
      croak 'Tried to delete all the pages';
   }

   my %pages = map {$_,1} @pages; # eliminate duplicates

   # make a list that is the complement of the @pages list
   my @delete = grep {!$pages{$_}} 1..$self->numPages();

   return $self if (@delete == 0); # no-work shortcut
   return $self->_deletePages(@delete);
}

=item $doc->deletePages($pages...)

Remove the specified pages from the PDF.  The pages can be multiple
arguments, comma separated lists, ranges (open or closed).

=cut

sub deletePages
{
   my $self = shift;
   return $self if (@_ == 0); # no-work shortcut
   my @pages = $self->rangeToArray(1,$self->numPages(),@_);

   return $self if (@pages == 0); # no-work shortcut

   my %pages = map {$_,1} @pages; # eliminate duplicates

   if ($self->numPages() == scalar keys %pages)
   {
      croak 'Tried to delete all the pages';
   }

   return $self->_deletePages(keys %pages);
}

sub _deletePages
{
   my $self = shift;

   # Pages should be reverse sorted since we need to delete from the
   # end to make the page numbers come out right.
   my @objnums;
   for (sort {$b <=> $a} @_)
   {
      my $objnum = $self->_deletePage($_);
      if (!$objnum)
      {
         $self->_deleteRefsToPages(@objnums);  # emergency cleanup to prevent corruption
         return;
      }
      push @objnums, $objnum;
   }
   $self->_deleteRefsToPages(@objnums);
   $self->cleanse();
   return $self;
}

=item $doc->deletePage($pagenum)

Remove the specified page from the PDF.  If the PDF has only one page,
this method will fail.

=cut

sub deletePage
{
   my $self = shift;
   my $pagenum = shift;

   my $objnum = $self->_deletePage($pagenum);
   if ($objnum)
   {
      $self->_deleteRefsToPages($objnum);
      $self->cleanse();
   }
   return $objnum ? $self : ();
}

# Internal method, called by deletePage() or deletePages()
# Returns the objnum of the deleted page

sub _deletePage
{
   my $self = shift;
   my $pagenum = shift;

   if ($self->numPages() <= 1) # don't delete the last page
   {
      croak 'Tried to delete the only page';
   }
   my ($objnum, $gennum) = $self->getPageObjnum($pagenum);
   if (!defined $objnum)
   {
      croak 'Tried to delete a non-existent page';
   }

   # Removing references to the page is hard:
   # (much of this code is lifted from getPage)
   my $parentdict = undef;
   my $node = $self->dereference($self->getRootDict()->{Pages}->{value});
   my $nodedict = $node->{value}->{value};
   my $nodestart = 1;
   while ($node && $nodedict->{Type}->{value} eq 'Pages')
   {
      my $count;
      if ($nodedict->{Count}->{type} eq 'reference')
      {
         my $countobj = $self->dereference($nodedict->{Count}->{value});
         $count = $countobj->{value}->{value}--;
         $self->{changes}->{$countobj->{objnum}} = 1;
      }
      else
      {
         $count = $nodedict->{Count}->{value}--;
      }
      $self->{changes}->{$node->{objnum}} = 1;

      if ($count == 1)
      {
         # only one left, so this is it
         if (!$parentdict)
         {
            croak 'Tried to delete the only page';
         }
         my $parentkids = $self->getValue($parentdict->{Kids});
         @$parentkids = grep {$_->{value} != $node->{objnum}} @$parentkids;
         $self->{changes}->{$parentdict->{Kids}->{objnum}} = 1;
         $self->deleteObject($node->{objnum});
         last;
      }

      my $kids = $self->getValue($nodedict->{Kids});
      if (@$kids == 1)
      {
         # Count was not 1, so this must not be a leaf node
         # hop down into node's child

         my $sub = $self->dereference($kids->[0]->{value});
         my $subdict = $sub->{value}->{value};
         $parentdict = $nodedict;
         $node = $sub;
         $nodedict = $subdict;
      }
      else
      {
         # search through all kids
         for my $child (0 .. $#$kids)
         {
            my $sub = $self->dereference($kids->[$child]->{value});
            my $subdict = $sub->{value}->{value};

            if ($subdict->{Type}->{value} ne 'Pages')
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
               my $count = $self->getValue($subdict->{Count});
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
   $self->deleteObject($objnum);

   # Caches are now bad for all pages from this one
   $self->decachePages($pagenum .. $self->numPages());

   $self->{PageCount}--;

   return $objnum;
}

sub _deleteRefsToPages
{
   my $self = shift;
   my %objnums = map {$_,1} @_;

   my $root = $self->getRootDict();
   if ($root->{Names})
   {
      my $names = $self->getValue($root->{Names});
      if ($names->{Dests})
      {
         my $dests = $self->getValue($names->{Dests});
         if ($self->_deleteDests($dests, \%objnums))
         {
            delete $names->{Dests};
         }
      }

      if (0 == scalar keys %$names)
      {
         my $names_objnum = $root->{Names}->{value};
         $self->deleteObject($names_objnum);
         delete $root->{Names};
      }
   }

   if ($root->{Outlines})
   {
      my $outlines = $self->getValue($root->{Outlines});
      $self->_deleteOutlines($outlines, \%objnums);
   }
   return;
}

sub _deleteOutlines
{
   my $self = shift;
   my $outlines = shift;
   my $objnums = shift;

   my @deletes;
   my @stack = ($outlines);

   #my $nodes = 0;
   #my $dests = 0;
   #my $deleted = 0;

   while (@stack > 0)
   {
      my $node = shift @stack;

      #$nodes++;

      # Check for a Destination (aka internal hyperlink)
      # A is indirect ref, Dest is direct ref; only one can be present
      my $dest;
      if ($node->{A})
      {
         $dest = $self->getValue($node->{A});
         $dest = $self->getValue($dest->{D});
      }
      elsif ($node->{Dest})
      {
         $dest = $self->getValue($node->{Dest});
      }
      if ($dest && (ref $dest) && (ref $dest) eq 'ARRAY')
      {
         my $ref = $dest->[0];
         if ($ref && $ref->{type} eq 'reference' && $objnums->{$ref->{value}})
         {
            $self->deleteObject($ref->{objnum});
            # Easier to just delete both, even though only one may exist
            delete $node->{A};
            delete $node->{Dest};

            #$deleted++;
         }
         #$dests++;
      }

      if ($node->{Next})
      {
         push @stack, $self->getValue($node->{Next});
      }
      if ($node->{First})
      {
         push @stack, $self->getValue($node->{First});
      }
   }
   #print "nodes: $nodes, dests: $dests, deleted: $deleted\n";
   return;
}

sub _deleteDests
{
   my $self = shift;
   my $dests = shift;
   my $objnums = shift;
   
   ## Accumulate the nodes to delete
   my @deletes;
   my @stack = ([$dests]);
   
   #my $nodes = 0;
   #my $Namenodes = 0;
   #my $Names = 0;
   #my $kidnodes = 0;
   #my $kids = 0;
   #my $leafs = 0;
   #my $others = 0;

   while (@stack > 0)
   {
      #$nodes++;

      my $chain = pop @stack;
      my $node = $chain->[0];
      if ($node->{Names})
      {
         my $pairs = $self->getValue($node->{Names});
         for (my $i=1; $i<@$pairs; $i+=2)  ## no critic for C-style for loop
         {
            push @stack, [$self->getValue($pairs->[$i]), @$chain];
         }
         #$Names += @$pairs/2;
         #$Namenodes++;
      }
      elsif ($node->{Kids})
      {
         my $list = $self->getValue($node->{Kids});
         push @stack, map {[$self->getValue($_), @$chain]} @$list;
         #$kids += @$list;
         #$kidnodes++;
      }
      elsif ($node->{D})
      {
         #$leafs++;
         my $props = $self->getValue($node->{D});
         my $ref = $props->[0];
         if ($ref && $ref->{type} eq 'reference' && $objnums->{$ref->{value}})
         {
            push @deletes, $chain;
         }
      }
      #else
      #{
      #   $others++;
      #}
   }

   #my $deletes = @deletes;
   #print "nodes: $nodes ($Namenodes/$kidnodes), names: $Names, kids: $kids, leafs: $leafs, others: $others, deletes: $deletes\n";
   
   ## Delete the nodes, and their parents if applicable
   for my $chain (@deletes)
   {
      my $obj = shift @$chain;
      my $objnum = [values %$obj]->[0]->{objnum};
      if (!$objnum)
      {
         die 'Destination object lacks an object number (number '.@$chain.' in the chain)';
      }
      $self->deleteObject($objnum);
      #$nodes--;
      #$leafs--;
      #$deletes--;

      # Ascend chain...  $objnum gets overwritten
      my $child = $obj;
      
    CHAIN:
      for my $node (@$chain)
      {
         last if (exists $node->{deleted});  # internal flag
         
         my $node_objnum = [values %$node]->[0]->{objnum} || die;
         
         if ($node->{Names})
         {
            my $pairs = $self->getValue($node->{Names});
            my $limits = $self->getValue($node->{Limits});
            my $redo_limits = 0;
            
            # Find and remove child reference
            # iterate over keys of key-value array
            for (my $i=@$pairs-2; $i>=0; $i-=2)  ## no critic for C-style for loop
            {
               if ($pairs->[$i+1]->{value} == $objnum)
               {
                  my $name = $pairs->[$i]->{value} || die 'No name in Name tree';
                  splice @$pairs, $i, 2;
                  if ($limits->[0]->{value} eq $name || $limits->[1]->{value} eq $name)
                  {
                     $redo_limits = 1;
                  }
                  #$Names--;
               }
            }

            if (@$pairs > 0)
            {
               if ($redo_limits)
               {
                  my @names;
                  for (my $i=0; $i<@$pairs; $i+=2)  ## no critic for C-style for loop
                  {
                     push @names, $pairs->[$i]->{value};
                  }
                  @names = sort @names;
                  $limits->[0]->{value} = $names[0];
                  $limits->[1]->{value} = $names[-1];
               }
               last CHAIN;
            }
            #$Namenodes--;
         }

         elsif ($node->{Kids})
         {
            my $list = $self->getValue($node->{Kids});
            
            # Find and remove child reference
            for my $i (reverse 0 .. $#$list)
            {
               if ($list->[$i]->{value} == $objnum)
               {
                  splice @$list, $i, 1;
                  #$kids--;
               }
            }
            
            if (@$list > 0)
            {
               if ($node->{Limits})
               {
                  my $limits = $self->getValue($node->{Limits});
                  if (!$limits || @$limits != 2)
                  {
                     die 'Internal error: trouble parsing the Limits array in a name tree';
                  }
                  my @names;
                  for my $i (0..@$list)
                  {
                     my $child = $self->getValue($list->[$i]);
                     my $child_limits = $self->getValue($child->{Limits});
                     push @names, map {$_->{value}} @$child_limits;
                  }
                  @names = sort @names;
                  $limits->[0]->{value} = $names[0];
                  $limits->[1]->{value} = $names[-1];
               }
               last CHAIN;
            }
            #$kidnodes--;
         }
         
         else
         {
            die 'Internal error: found a parent node with neither Names nor Kids.  This should be impossible.';
         }
         
         # If we got here, the node is empty, so delete it and move onward
         $self->deleteObject($node_objnum);
         $node->{deleted} = undef;  # internal flag
         #$nodes--;
         
         # Prepare for next iteration
         $child = $node;
         $objnum = $node_objnum;
      }
   }

   #print "nodes: $nodes ($Namenodes/$kidnodes), names: $Names, kids: $kids, leafs: $leafs, others: $others, deletes: $deletes\n";

   return exists $dests->{deleted};
}

=item $doc->decachePages($pagenum, $pagenum, ...)

Clears cached copies of the specified page data structures.  This is
useful if an operation has been performed that changes a page.

=cut

sub decachePages
{
   my $self = shift;
   my @pages = @_;

   for (@pages)
   {
      delete $self->{pagecache}->{$_};
      delete $self->{Names}->{$_};
      delete $self->{NameObjects}->{$_};
   }
   delete $self->{Names}->{All};
   return $self;
}


=item $doc->addPageResources($pagenum, $resourcehash)

Add the resources from the given object to the page resource
dictionary.  If the page does not have a resource dictionary, create
one.  This function avoids duplicating resources where feasible.

=cut

sub addPageResources
{
   my $self = shift;
   my $pagenum = shift;
   my $newrsrcs = shift;

   return if (!$newrsrcs);
   my $page = $self->getPage($pagenum);
   return if (!$page);

   my ($anyobj) = values %$page;
   my $objnum = $anyobj->{objnum};
   my $gennum = $anyobj->{gennum};

   my $pagersrcs;
   if ($page->{Resources})
   {
      $pagersrcs = $self->getValue($page->{Resources});
   }
   else
   {
      $pagersrcs = {};
      $page->{Resources} = CAM::PDF::Node->new('dictionary', $pagersrcs, $objnum, $gennum);
      $self->{changes}->{$objnum} = 1;
   }
   for my $type (keys %$newrsrcs)
   {
      my $new_r = $self->getValue($newrsrcs->{$type});
      my $page_r;
      if ($pagersrcs->{$type})
      {
         $page_r = $self->getValue($pagersrcs->{$type});
      }
      if ($type eq 'Font')
      {
         if (!$page_r)
         {
            $page_r = {};
            $pagersrcs->{$type} = CAM::PDF::Node->new('dictionary', $page_r, $objnum, $gennum);
            $self->{changes}->{$objnum} = 1;
         }
         for my $font (keys %$new_r)
         {
            next if (exists $page_r->{$font});
            my $val = $new_r->{$font};
            if ($val->{type} ne 'reference')
            {
               die 'Internal error: font entry is not a reference';
            }
            $page_r->{$font} = CAM::PDF::Node->new('reference', $val->{value}, $objnum, $gennum);
            #warn "add font $font\n";
            $self->{changes}->{$objnum} = 1;
         }
      }
      elsif ($type eq 'ProcSet')
      {
         if (!$page_r)
         {
            $page_r = [];
            $pagersrcs->{$type} = CAM::PDF::Node->new('array', $page_r, $objnum, $gennum);
            $self->{changes}->{$objnum} = 1;
         }
         for my $proc (@$new_r)
         {
            if ($proc->{type} ne 'label')
            {
               die 'Internal error: procset entry is not a label';
            }
            next if (grep {$_->{value} eq $proc->{value}} @$page_r);
            push @$page_r, CAM::PDF::Node->new('label', $proc->{value}, $objnum, $gennum);
            #warn "add procset $$proc{value}\n";
            $self->{changes}->{$objnum} = 1;
         }
      }
      elsif ($type eq 'Encoding')
      {
         # TODO: is this a hack or is it right?
         # EXPLICITLY skip /Encoding from form DR entry
      }
      else
      {
         warn "Internal error: unsupported resource type '$type'";
      }
   }
   return;
}

=item $doc->appendPDF($pdf)

Append pages from another PDF document to this one.  No optimization
is done -- the pieces are just appended and the internal table of
contents is updated.

Note that this can break documents with annotations.  See the
F<appendpdf.pl> script for a workaround.

=cut

sub appendPDF
{
   my $self = shift;
   my $doc2 = shift;
   my $prepend = shift; # boolean, default false

   my $pageroot = $self->getPagesDict();
   my ($anyobj) = values %$pageroot;
   my $objnum = $anyobj->{objnum};
   my $gennum = $anyobj->{gennum};

   my $root = $self->getRootDict();
   my $root2 = $doc2->getRootDict();
   my $pageobj2 = $doc2->dereference($root2->{Pages}->{value});
   my ($key, %refkeys) = $self->appendObject($doc2, $pageobj2->{objnum}, 1);
   my $subpage = $self->getObjValue($key);

   my $newdict = {};
   my $newpage = CAM::PDF::Node->new('object',
                                     CAM::PDF::Node->new('dictionary', $newdict));
   $newdict->{Type} = CAM::PDF::Node->new('label', 'Pages');
   $newdict->{Kids} = CAM::PDF::Node->new('array',
                                          [
                                           CAM::PDF::Node->new('reference', $prepend ? $key : $objnum),
                                           CAM::PDF::Node->new('reference', $prepend ? $objnum : $key),
                                           ]);
   $self->{PageCount} += $doc2->{PageCount};
   $newdict->{Count} = CAM::PDF::Node->new('number', $self->{PageCount});
   my $newpagekey = $self->appendObject(undef, $newpage, 0);
   $root->{Pages}->{value} = $newpagekey;

   $pageroot->{Parent} = CAM::PDF::Node->new('reference', $newpagekey, $key, $subpage->{gennum});
   $subpage->{Parent} = CAM::PDF::Node->new('reference', $newpagekey, $key, $subpage->{gennum});

   #my $kidlist = $self->getValue($pageroot->{Kids});
   #push @$kidlist, CAM::PDF::Node->new('reference', $key, $objnum, $gennum);
   #$self->{changes}->{$objnum} = 1;

   #print STDERR "$newpagekey $objnum $key\n";

   if ($root2->{AcroForm})
   {
      my $forms = $doc2->getValue($doc2->getValue($root2->{AcroForm})->{Fields});
      my @newforms = ();
      for my $reference (@$forms)
      {
         if ($reference->{type} ne 'reference')
         {
            die 'Internal error: expected a reference';
         }
         my $newkey = $refkeys{$reference->{value}};
         #print STDERR "old ".$reference->{value}." new $newkey\n";
         if ($newkey)
         {
            push @newforms, CAM::PDF::Node->new('reference', $newkey);
         }
      }
      if ($root->{AcroForm})
      {
         my $mainforms = $self->getValue($self->getValue($root->{AcroForm})->{Fields});
         for my $reference (@newforms)
         {
            $reference->{objnum} = $mainforms->[0]->{objnum};
            $reference->{gennum} = $mainforms->[0]->{gennum};
         }
         push @$mainforms, @newforms;
      }
      else
      {
         #my $key = $self->appendObject($doc2, $pageobj2->{objnum}, 0);
         die 'adding new forms is not implemented';
      }
   }

   if ($prepend)
   {
      # clear caches
      $self->{pagecache} = {};
      $self->{Names} = {};
      $self->{NameObjects} = {};
   }

   return $key;
}

=item $doc->prependPDF($pdf)

Just like appendPDF() except the new document is inserted on page 1
instead of at the end.

=cut

sub prependPDF
{
   my $self = shift;
   return $self->appendPDF(@_, 1);
}

=item $doc->duplicatePage($pagenum)

=item $doc->duplicatePage($pagenum, $leaveblank)

Inserts an identical copy of the specified page into the document.
The new page's number will be C<$pagenum + 1>.

If C<$leaveblank> is true, the new page does not get any content.
Thus, the document is broken until you subsequently call
setPageContent().

=cut

sub duplicatePage
{
   my $self = shift;
   my $pagenum = shift;
   my $leave_blank = shift || 0;

   my $page = $self->getPage($pagenum);
   my $objnum = $self->getPageObjnum($pagenum);
   my $newobjnum = $self->appendObject($self, $objnum, 0);
   my $newdict = $self->getObjValue($newobjnum);
   delete $newdict->{Contents};
   my $parent = $self->getValue($page->{Parent});
   push @{$self->getValue($parent->{Kids})}, CAM::PDF::Node->new('reference', $newobjnum);

   while ($parent)
   {
      $self->{changes}->{$parent->{Count}->{objnum}} = 1;
      if ($parent->{Count}->{type} eq 'reference')
      {
         my $countobj = $self->dereference($parent->{Count}->{value});
         $countobj->{value}->{value}++;
         $self->{changes}->{$countobj->{objnum}} = 1;
      }
      else
      {
         $parent->{Count}->{value}++;
      }
      $parent = $self->getValue($parent->{Parent});
   }
   $self->{PageCount}++;

   if (!$leave_blank)
   {
      $self->setPageContent($pagenum+1, $self->getPageContent($pagenum));
   }

   # Caches are now bad for all pages from this one
   $self->decachePages($pagenum + 1 .. $self->numPages());

   return $self;
}

=item $doc->createStreamObject($content)

=item $doc->createStreamObject($content, $filter ...)

I<For INTERNAL use>

Create a new Stream object.  This object is NOT added to the document.
Use the appendObject() function to do that after calling this
function.

=cut

sub createStreamObject
{
   my $self = shift;
   my $content = shift;

   my $dict = CAM::PDF::Node->new('dictionary',
                                 {
                                    Length => CAM::PDF::Node->new('number', length $content),
                                    StreamData => CAM::PDF::Node->new('stream', $content),
                                 },
                                 );

   my $obj = CAM::PDF::Node->new('object', $dict);

   while (my $filter = shift)
   {
      #warn "$filter encoding\n";
      $self->encodeOne($obj->{value}, $filter);
   }

   return $obj;
}

=item $doc->uninlineImages()

=item $doc->uninlineImages($pagenum)

Search the content of the specified page (or all pages if the
page number is omitted) for embedded images.  If there are any, replace
them with indirect objects.  This procedure uses heuristics to detect
in-line images, and is subject to confusion in extremely rare cases of text
that uses C<BI> and C<ID> a lot.

=cut

sub uninlineImages
{
   my $self = shift;
   my $pagenum = shift;

   my $changes = 0;
   if (!$pagenum)
   {
      my $pages = $self->numPages();
      for my $p (1 .. $pages)
      {
         $changes += $self->uninlineImages($p);
      }
   }
   else
   {
      my $c = $self->getPageContent($pagenum);
      my $pos = 0;
      while (($pos = index $c, 'BI', $pos) != 1)
      {
         # manual \bBI check
         # if beginning of string or token
         if ($pos == 0 || (substr $c, $pos-1, 1) =~ m/ \W /xms)
         {
            my $part = substr $c, $pos;
            if ($part =~ m/ \A BI\b(.*?)\bID\b /xms)
            {
               my $im = $1;

               ## Long series of tests to make sure this is really an
               ## image and not just coincidental text

               # Fix easy cases of "BI text) BI ... ID"
               $im =~ s/ \A .*\bBI\b //xms; 
               # There should never be an EI inside of a BI ... ID
               next if ($im =~ m/ \bEI\b /xms);
               
               # Easy tests: is this the beginning or end of a string?
               # (these aren't really good tests...)
               next if ($im =~ m/ \A \)    /xms);
               next if ($im =~ m/    \( \z /xms);
               
               # this is the most complex heuristic:
               # make sure that there is an open paren before every close
               # if not, then the "BI" or the "ID" was part of a string
               my $test = $im;  # make a copy we can scribble on
               my $failed = 0;
               # get rid of escaped parens for the test
               $test =~ s/ \\[\(\)] //gxms; 
               # Look for closing parens
               while ($test =~ s/ \A(.*?)\) //xms)
               {
                  # If there is NOT an opening paren before the
                  # closing paren we detected above, then the start of
                  # our string is INSIDE a paren pair, thus a failure.
                  my $bit = $1;
                  if ($bit !~ m/ \( /xms)
                  {
                     $failed = 1;
                     last;
                  }
               }
               next if ($failed);
               
               # End of heuristics.  This is likely a real embedded image.
               # Now do the replacement.

               my $oldlen = length $part;
               my $image = $self->parseInlineImage(\$part, undef);
               my $newlen = length $part;
               my $imagelen = $oldlen - $newlen;
               
               # Construct a new image name like "I3".  Start with
               # "I1" and continue until we get an unused "I<n>"
               # (first, get the list of already-used labels)
               $self->_buildNameTable($pagenum);
               my $i = 1;
               my $name = 'Im1';
               while (exists $self->{Names}->{$pagenum}->{$name})
               {
                  $name = 'Im' . ++$i;
               }
               
               $self->setName($image, $name);
               my $key = $self->appendObject(undef, $image, 0);
               $self->pageAddName($pagenum, $name, $key);
               
               $c = (substr $c, 0, $pos) . "/$name Do" . (substr $c, $pos+$imagelen);
               $changes++;
            }
         }
      }
      if ($changes > 0)
      {
         $self->setPageContent($pagenum, $c);
      }
   }
   return $changes;
}

=item $doc->appendObject($doc, $objectnum, $recurse?)

=item $doc->appendObject($undef, $object, $recurse?)

Duplicate an object from another PDF document and add it to this
document, optionally descending into the object and copying any other
objects it references.

Like replaceObject(), the second form allows you to append a
newly-created block to the PDF.

=cut

sub appendObject
{
   my $self = shift;
   my $doc2 = shift;
   my $key2 = shift;
   my $follow = shift;

   my $objnum = ++$self->{maxobj};
   #$self->{xref}->{$objnum} = undef;
   #$self->{endxref}->{$objnum} = undef if (exists $self->{endxref});
   $self->{versions}->{$objnum} = -1;

   my %refkeys = $self->replaceObject($objnum, $doc2, $key2, $follow);
   if (wantarray)
   {
      return ($objnum, %refkeys);
   }
   else
   {
      return $objnum;
   }
}

=item $doc->replaceObject($objectnum, $doc, $objectnum, $recurse?)

=item $doc->replaceObject($objectnum, $undef, $object)

Duplicate an object from another PDF document and insert it into this
document, replacing an existing object.  Optionally descend into the
original object and copy any other objects it references.

If the other document is undefined, then the object to copy is taken
to be an anonymous object that is not part of any other document.
This is useful when you've just created that anonymous object.

=cut

sub replaceObject
{
   my $self = shift;
   my $key = shift;
   my $doc2 = shift;
   my $key2 = shift;
   my $follow = shift;

   # careful! 'undef' means something different from '0' here!
   if (!defined $follow)
   {
      $follow = 1;
   }

   my $obj;
   my $obj2;
   if ($doc2)
   {
      $obj2 = $doc2->dereference($key2);
      $obj = $self->copyObject($obj2);
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

   $self->setObjNum($obj, $key, 0);

   # Preserve the name of the object
   if ($self->{xref}->{$key})  # make sure it isn't a brand new object
   {
      my $oldname = $self->getName($self->dereference($key));
      if ($oldname)
      {
         $self->setName($obj, $oldname);
      }
      else
      {
         $self->removeName($obj);
      }
   }

   $self->{objcache}->{$key} = $obj;
   $self->{changes}->{$key} = 1;

   my %newrefkeys = ($key2, $key);
   if ($follow)
   {
      for my $oldrefkey ($doc2->getRefList($obj2))
      {
         next if ($oldrefkey == $key2);
         my $newkey = $self->appendObject($doc2, $oldrefkey, 0);
         $newrefkeys{$oldrefkey} = $newkey;
      }
      $self->changeRefKeys($obj, \%newrefkeys);
      for my $newkey (values %newrefkeys)
      {
         $self->changeRefKeys($self->dereference($newkey), \%newrefkeys);
      }
   }
   return (%newrefkeys);
}

=item $doc->deleteObject($objectnum)

Remove an object from the document.  This function does NOT take care
of dependencies on this object.

=cut

sub deleteObject
{
   my $self = shift;
   my $objnum = shift;

   delete $self->{versions}->{$objnum};
   delete $self->{objcache}->{$objnum};
   delete $self->{xref}->{$objnum};
   delete $self->{endxref}->{$objnum};
   delete $self->{changes}->{$objnum};
   return;
}

=item $doc->cleanse()

Remove unused objects.  I<WARNING:> this function breaks some PDF
documents because it removes objects that are strictly part of the
page model hierarchy, but which are required anyway (like some font
definition objects).

=cut

sub cleanse
{
   my $self = shift;

   my $base = CAM::PDF::Node->new('dictionary', $self->{trailer});
   my @list = sort {$a<=>$b} $self->getRefList($base);
   #print join(',', @list), "\n";

   for my $i (1 .. $self->{maxobj})
   {
      if (@list > 0 && $list[0] == $i)
      {
         shift @list;
      }
      else
      {
         #warn "delete object $i\n";
         $self->deleteObject($i);
      }
   }
   return;
}

=item $doc->createID()

I<For INTERNAL use>

Generate a new document ID.  Contrary the Adobe recommendation, this
is a random number.

=cut

sub createID
{
   my $self = shift;

   # Warning: this is non-repeatable, and depends on Linux!

   my $addbytes;
   if ($self->{ID})
   {
      # do not change the first half of an existing ID
      $self->{ID} = substr $self->{ID}, 0, 16;
      $addbytes = 16;
   }
   else
   {
      $self->{ID} = q{};
      $addbytes = 32;
   }

   # Append $addbytes random bytes
   # First try the system random number generator
   if (-f '/dev/urandom')
   {
      if (open my $fh, '<', '/dev/urandom')
      {
         read $fh, $self->{ID}, $addbytes, 32-$addbytes;
         close $fh;
         $addbytes = 0;
      }
   }
   # If that failed, use Perl's random number generator
   for (1..$addbytes)
   {
      $self->{ID} .= pack 'C', int rand 256;
   }

   if ($self->{trailer})
   {
      $self->{trailer}->{ID} = CAM::PDF::Node->new('array',
                               [
                                CAM::PDF::Node->new('hexstring', substr $self->{ID}, 0, 16),
                                CAM::PDF::Node->new('hexstring', substr $self->{ID}, 16, 16),
                                ],
                               );
   }

   return 1;
}

=item $doc->fillFormFields($name => $value, ...)

Set the default values of PDF form fields.  The name should be the
full hierarchical name of the field as output by the
getFormFieldList() function.  The argument list can be a hash if you
like.  A simple way to use this function is something like this:

    my %fields = (fname => 'John', lname => 'Smith', state => 'WI');
    $field{zip} = 53703;
    $self->fillFormFields(%fields);

=cut

sub fillFormFields
{
   my $self = shift;
   my @list = (@_);

   my $filled = 0;
   while (@list > 0)
   {
      my $key = shift @list;
      my $value = shift @list;
      if (!defined $value)
      {
         $value = q{};
      }

      next if (!$key);
      next if (ref $key);
      my $obj = $self->getFormField($key);
      next if (!$obj);

      my $objnum = $obj->{objnum};
      my $gennum = $obj->{gennum};

      # This read-only dict includes inherited properties
      my $propdict = $self->getFormFieldDict($obj);

      # This read-write dict does not include inherited properties
      my $dict = $self->getValue($obj);
      $dict->{V}  = CAM::PDF::Node->new('string', $value, $objnum, $gennum);
      #$dict->{DV} = CAM::PDF::Node->new('string', $value, $objnum, $gennum);

      if ($propdict->{FT} && $self->getValue($propdict->{FT}) eq 'Tx')  # Is it a text field?
      {
         # Set up display of form value
         if (!$dict->{AP})
         {
            $dict->{AP} = CAM::PDF::Node->new('dictionary', {}, $objnum, $gennum);
         }
         if (!$dict->{AP}->{value}->{N})
         {
            my $newobj = CAM::PDF::Node->new('object', 
                                            CAM::PDF::Node->new('dictionary',{}),
                                            );
            my $num = $self->appendObject(undef, $newobj, 0);
            $dict->{AP}->{value}->{N} = CAM::PDF::Node->new('reference', $num, $objnum, $gennum);
         }
         my $formobj = $self->dereference($dict->{AP}->{value}->{N}->{value});
         my $formonum = $formobj->{objnum};
         my $formgnum = $formobj->{gennum};
         my $formdict = $self->getValue($formobj);
         if (!$formdict->{Subtype})
         {
            $formdict->{Subtype} = CAM::PDF::Node->new('label', 'Form', $formonum, $formgnum);
         }
         my @rect = (0,0,0,0);
         if ($dict->{Rect})
         {
            my $r = $self->getValue($dict->{Rect});
            my ($x1, $y1, $x2, $y2) = @$r;
            @rect = (
               $self->getValue($x1),
               $self->getValue($y1),
               $self->getValue($x2),
               $self->getValue($y2),
            );
         }
         my $dx = $rect[2]-$rect[0];
         my $dy = $rect[3]-$rect[1];
         if (!$formdict->{BBox})
         {
            $formdict->{BBox} = CAM::PDF::Node->new('array',
                                                   [
                                                    CAM::PDF::Node->new('number', 0, $formonum, $formgnum),
                                                    CAM::PDF::Node->new('number', 0, $formonum, $formgnum),
                                                    CAM::PDF::Node->new('number', $dx, $formonum, $formgnum),
                                                    CAM::PDF::Node->new('number', $dy, $formonum, $formgnum),
                                                    ],
                                                   $formonum,
                                                   $formgnum);
         }
         my $text = $value;
         $text =~ s/ \r\n? /\n/gxms;
         $text =~ s/ \n+\z //xms;

         my @rsrcs;
         my $fontmetrics = 0;
         my $fontname    = q{};
         my $fontsize    = 0;
         my $da          = q{};
         my $tl          = q{};
         my $border      = 2;
         my $tx          = $border;
         my $ty          = $border + 2;
         my $stringwidth;
         if ($propdict->{DA}) {
            $da = $self->getValue($propdict->{DA});

            # Try to pull out all of the resources used in the text object
            @rsrcs = ($da =~ m/ \/([^\s<>\/\[\]\(\)]+) /gxms);

            # Try to pull out the font size, if any.  If more than
            # one, pick the last one.  Font commands look like:
            # "/<fontname> <size> Tf"
            if ($da =~ m/ \s*\/(\w+)\s+(\d+)\s+Tf.*? \z /xms)
            {
               $fontname = $1;
               $fontsize = $2;
               if ($fontname)
               {
                  if ($propdict->{DR})
                  {
                     my $dr = $self->getValue($propdict->{DR});
                     $fontmetrics = $self->getFontMetrics($dr, $fontname);
                  }
                  #print STDERR "Didn't get font\n" if (!$fontmetrics);
               }
            }
         }

         my %flags = (
                      Justify => 'left',
                      );
         if ($propdict->{Ff})
         {
            # Just decode the ones we actually care about
            # PDF ref, 3rd ed pp 532,543
            my $ff = $self->getValue($propdict->{Ff});
            my @flags = split //xms, unpack 'b*', pack 'V', $ff;
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
            my $q = $self->getValue($propdict->{Q}) || 0;
            $flags{Justify} = $q==2 ? 'right' : ($q==1 ? 'center' : 'left');
         }

         # The order of the following sections is important!
         if ($flags{Password})
         {
            $text =~ s/ [^\n] /*/gxms;  # Asterisks for password characters
         }

         if ($fontmetrics && (!$fontsize))
         {
            # Fix autoscale fonts
            $stringwidth = 0;
            my $lines = 0;
            for my $line (split /\n/xms, $text)  # trailing null strings omitted
            {
               $lines++;
               my $w = $self->getStringWidth($fontmetrics, $line);
               if ($w && $w > $stringwidth)
               {
                  $stringwidth = $w;
               }
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
            $da =~ s/ \/$fontname\s+0\s+Tf\b /\/$fontname $fontsize Tf/gxms;
         }
         if ($fontsize)
         {
            # This formula is TOTALLY empirical.  It's probably wrong.
            $ty = $border + 2 + (9-$fontsize)*0.4;
         }


         # escape characters
         $text = $self->writeString($text);

         if ($flags{Multiline})
         {
            # TODO: wrap the field with wrapString()??
            # Shawn Dawson of Silent Solutions pointed out that this does not auto-wrap the input text

            my $linebreaks = $text =~ s/ \\n /\) Tj T* \(/gxms;

            # Total guess work:
            # line height is either 150% of fontsize or thrice
            # the corner offset
            $tl = $fontsize ? $fontsize * 1.5 : $ty * 3;

            # Bottom aligned
            #$ty += $linebreaks * $tl;
            # Top aligned
            $ty = $dy - $border - $tl;

            if ($flags{Justify} ne 'left')
            {
               warn 'Justified text not supported for multiline fields';
            }

            $tl .= ' TL';
         }
         else
         {
            if ($flags{Justify} ne 'left' && $fontmetrics)
            {
               my $width = $stringwidth || $self->getStringWidth($fontmetrics, $text);
               my $diff = $dx - $width*$fontsize;

               if ($flags{Justify} eq 'center')
               {
                  $text = ($diff/2)." 0 Td $text";
               }
               elsif ($flags{Justify} eq 'right')
               {
                  $text = "$diff 0 Td $text";
               }
            }
         }

         # Move text from lower left corner of form field
         my $tm = "1 0 0 1 $tx $ty Tm ";

         $text =  "$tl $da $tm $text Tj";
         $text = "1 g 0 0 $dx $dy re f /Tx BMC q 1 1 ".($dx-$border).q{ }.($dy-$border)." re W n BT $text ET Q EMC";
         my $len = length $text;
         $formdict->{Length} = CAM::PDF::Node->new('number', $len, $formonum, $formgnum);
         $formdict->{StreamData} = CAM::PDF::Node->new('stream', $text, $formonum, $formgnum);

         if (@rsrcs > 0) {
            if (!$formdict->{Resources})
            {
               $formdict->{Resources} = CAM::PDF::Node->new('dictionary', {}, $formonum, $formgnum);
            }
            my $rdict = $self->getValue($formdict->{Resources});
            if (!$rdict->{ProcSet})
            {
               $rdict->{ProcSet} = CAM::PDF::Node->new('array',
                                                      [
                                                       CAM::PDF::Node->new('label', 'PDF', $formonum, $formgnum),
                                                       CAM::PDF::Node->new('label', 'Text', $formonum, $formgnum),
                                                       ],
                                                      $formonum,
                                                      $formgnum);
            }
            if (!$rdict->{Font})
            {
               $rdict->{Font} = CAM::PDF::Node->new('dictionary', {}, $formonum, $formgnum);
            }
            my $fdict = $self->getValue($rdict->{Font});

            # Search out font resources.  This is a total kluge.
            # TODO: the right way to do this is to look for the DR
            # attribute in the form element or it's ancestors.
            for my $font (@rsrcs)
            {
               my $fobj = $self->dereference("/$font", 'All');
               if (!$fobj)
               {
                  die "Could not find resource /$font while preparing form field $key\n";
               }
               $fdict->{$font} = CAM::PDF::Node->new('reference', $fobj->{objnum}, $formonum, $formgnum);
            }
         }
      }
      $filled++;
   }
   return $filled;
}


=item $doc->clearFormFieldTriggers($name, $name, ...)

Disable any triggers set on data entry for the specified form field
names.  This is useful in the case where, for example, the data entry
Javascript forbids punctuation and you want to prefill with a
hyphenated word.  If you don't clear the trigger, the prefill may not
happen.

=cut

sub clearFormFieldTriggers
{
   my $self = shift;

   for my $fieldname (@_)
   {
      my $obj = $self->getFormField($fieldname);
      if ($obj)
      {
         if (exists $obj->{value}->{value}->{AA})
         {
            delete $obj->{value}->{value}->{AA};
            my $objnum = $obj->{objnum};
            if ($objnum)
            {
               $self->{changes}->{$objnum} = 1;
            }
         }
      }
   }
   return;
}

=item $doc->clearAnnotations()

Remove all annotations from the document.  If form fields are
encountered, their text is added to the appropriate page.

=cut

sub clearAnnotations
{
   my $self = shift;

   my $formrsrcs;
   my $root = $self->getRootDict();
   if ($root->{AcroForm})
   {
      my $acroform = $self->getValue($root->{AcroForm});
      # Get the form resources
      if ($acroform->{DR})
      {
         $formrsrcs = $self->getValue($acroform->{DR});
      }

      # Kill off the forms
      $self->deleteObject($root->{AcroForm}->{value});
      delete $root->{AcroForm};
   }

   # Iterate through the pages, deleting annotations

   my $pages = $self->numPages();
   for my $p (1..$pages)
   {
      my $page = $self->getPage($p);
      if ($page->{Annots}) {
         $self->addPageResources($p, $formrsrcs);
         my $annotsarray = $self->getValue($page->{Annots});
         delete $page->{Annots};
         for my $annotref (@$annotsarray)
         {
            my $annot = $self->getValue($annotref);
            if ((ref $annot) ne 'HASH')
            {
               die 'Internal error: annotation is not a dictionary';
            }
            # Copy all text field values into the page, if present
            if ($annot->{Subtype} && 
                $annot->{Subtype}->{value} eq 'Widget' &&
                $annot->{FT} &&
                $annot->{FT}->{value} eq 'Tx' &&
                $annot->{AP})
            {
               my $ap = $self->getValue($annot->{AP});
               my $rect = $self->getValue($annot->{Rect});
               my $x = $self->getValue($rect->[0]);
               my $y = $self->getValue($rect->[1]);
               if ($ap->{N})
               {
                  my $n = $self->dereference($ap->{N}->{value})->{value};
                  my $content = $self->decodeOne($n, 0);
                  if (!$content)
                  {
                     die 'Internal error: expected a content stream from the form copy';
                  }
                  $content =~ s/ \bre(\s+)f\b /re$1n/gxms;
                  $content = "q 1 0 0 1 $x $y cm\n$content Q\n";
                  $self->appendPageContent($p, $content);
                  $self->addPageResources($p, $self->getValue($n->{value}->{Resources}));
               }
            }
            $self->deleteObject($annotref->{value});
         }
      }
   }

   # kill off the annotation dependencies
   $self->cleanse();
   return;
}


################################################################################

=back

=head2 Document Writing

=over

=item $doc->preserveOrder()

Try to recreate the original document as much as possible.  This may
help in recreating documents which use undocumented tricks of saving
font information in adjacent objects.

=cut

sub preserveOrder
{
   # Call this to record the order of the objects in the original file
   # If called, then any new file will try to preserve the original order
   my $self = shift;

   my %positions = reverse %{$self->{xref}};
   $self->{order} = [map {($positions{$_})} sort {$a<=>$b} keys %positions];
   #print 'Wrote order ' . join(q{,},@{$self->{order}}) . "\n";
   return;
}

=item $doc->isLinearized()

Returns a boolean indicating whether this PDF is linearized (aka
"optimized").

=cut

sub isLinearized
{
   my $self = shift;

   my $first;
   if (exists $self->{order})
   {
      $first = $self->{order}->[0];
   }
   else
   {
      my %revxref = reverse %{$self->{xref}};
      ($first) = sort {$a <=> $b} keys %revxref;
      $first = $revxref{$first};
   }

   my $linearized = undef; # false
   my $obj = $self->dereference($first);
   if ($obj && $obj->{value}->{type} eq 'dictionary')
   {
      if (exists $obj->{value}->{value}->{Linearized})
      {
         $linearized = $self; # true
      }
   }
   return $linearized;
}

=item $doc->delinearize()

I<For INTERNAL use>

Undo the tweaks used to make the document 'optimized'.  This function
is automatically called on every save or output since this library
does not yet support linearized documents.

=cut

sub delinearize
{
   my $self = shift;

   return if ($self->{delinearized});

   # Turn off Linearization, if set
   my $first;
   if (exists $self->{order})
   {
      $first = $self->{order}->[0];
   }
   else
   {
      # Sort by doc byte offset, select smallest
      my %revxref = reverse %{$self->{xref}};
      ($first) = sort {$a <=> $b} keys %revxref;
      $first = $revxref{$first};
   }

   my $obj = $self->dereference($first);
   if ($obj->{value}->{type} eq 'dictionary')
   {
      if (exists $obj->{value}->{value}->{Linearized})
      {
         $self->deleteObject($first);
      }
   }

   $self->{delinearized} = 1;
   return;
}

=item $doc->clean()

Cache all parts of the document and throw away it's old structure.
This is useful for writing PDFs anew, instead of simply appending
changes to the existing documents.  This is called by cleansave() and
cleanoutput().

=cut

sub clean
{
   my $self = shift;

   # Make sure to extract everything before we wipe the old version
   $self->cacheObjects();

   $self->delinearize();

   # Update the ID number to make this document distinct from the original.
   # If there is already an ID, only the second half is changed
   $self->createID();

   # Mark everything changed
   %{$self->{changes}} = (
                         %{$self->{changes}},
                         map { $_ => 1 } keys %{$self->{xref}},
                         );

   # Mark everything new
   %{$self->{versions}} = (
                          %{$self->{versions}},
                          map { $_ => -1 } keys %{$self->{xref}},
                          );

   $self->{xref} = {};
   delete $self->{endxref};
   $self->{startxref} = 0;
   $self->{content} = q{};
   $self->{contentlength} = 0;
   delete $self->{trailer}->{Prev};
   return;
}

=item $doc->needsSave()

Returns a boolean indicating whether the save() method needs to be
called.  Like save(), this has nothing to do with whether the document
has been saved to disk, but whether the in-memory representation of
the document has been serialized.

=cut

sub needsSave
{
   my $self = shift;

   return 0 != keys %{$self->{changes}};
}

=item $doc->save()

Serialize the document into a single string.  All changed document
elements are normalized, and a new index and an updated trailer are
created.

This function operates solely in memory.  It DOES NOT write the
document to a file.  See the output() function for that.

=cut

sub save
{
   my $self = shift;

   if (!$self->needsSave())
   {
      return $self;
   }

   $self->delinearize();

   delete $self->{endxref};

   if (!$self->{content})
   {
      $self->{content} = '%PDF-' . $self->{pdfversion} . "\n%\217\n";
   }

   my %allobjs = (%{$self->{changes}}, %{$self->{xref}});
   my @objects = sort {$a<=>$b} keys %allobjs;
   if ($self->{order}) {

      # Sort in the order in $self->{order} array, with the rest later
      # in objnum order
      my %o = ();
      my $n = @{$self->{order}};
      for my $i (0 .. $n-1)
      {
         $o{$self->{order}->[$i]} = $i;
      }
      @objects = sort {($o{$a}||$a+$n) <=> ($o{$b}||$b+$n)} @objects;
   }
   delete $self->{order};

   my %newxref = ();
   for my $key (@objects)
   {
      next if (!$self->{changes}->{$key});
      $newxref{$key} = length $self->{content};

      #print "Writing object $key\n";
      $self->{content} .= $self->writeObject($key);

      $self->{xref}->{$key} = $newxref{$key};
      $self->{versions}->{$key}++;
      delete $self->{changes}->{$key};
   }

   if ($self->{content} !~ m/ [\r\n] \z /xms)
   {
      $self->{content} .= "\n";
   }

   my $startxref = length $self->{content};

   # Append the new xref
   $self->{content} .= "xref\n";
   my %blocks = (
                 0 => "0000000000 65535 f \n",
                 );
   for my $key (keys %newxref)
   {
      $blocks{$key} = sprintf "%010d %05d n \n", $newxref{$key}, $self->{versions}->{$key};
   }

   # If there is only one version of the document, there must be no
   # holes in the xref.  Test for versions by checking the Prev record
   # in the trailer
   if (!$self->{trailer}->{Prev})
   {
      # Fill in holes
      my $prevfreeblock = 0;
      for my $key (reverse 0 .. $self->{maxobj}-1)
      {
         if (!exists $blocks{$key})
         {
            # Add an entry to the free list
            # On $key == 0, this blows away the above definition of
            # the head of the free block list, but that's no big deal.
            $blocks{$key} = sprintf "%010d %05d f \n", 
                                    $prevfreeblock, ($key == 0 ? 65_535 : 1);
            $prevfreeblock = $key;
         }
      }
   }
   
   my $currblock = q{};
   my $currnum   = 0;
   my $currstart = 0;
   my @blockkeys = sort {$a<=>$b} keys %blocks;
   for my $i (0 .. $#blockkeys)
   {
      my $key = $blockkeys[$i];
      $currblock .= $blocks{$key};
      $currnum++;
      if ($i == $#blockkeys || $key+1 < $blockkeys[$i+1])
      {
         $self->{content} .= "$currstart $currnum\n$currblock";
         if ($i < $#blockkeys)
         {
            $currblock = q{};
            $currnum   = 0;
            $currstart = $blockkeys[$i+1];
         }
      }
   }

   #   Append the new trailer
   $self->{trailer}->{Size} = CAM::PDF::Node->new('number', $self->{maxobj} + 1);
   if ($self->{startxref})
   {
      $self->{trailer}->{Prev} = CAM::PDF::Node->new('number', $self->{startxref});
   }
   $self->{content} .= "trailer\n" . $self->writeAny(CAM::PDF::Node->new('dictionary', $self->{trailer})) . "\n";

   # Append the new startxref
   $self->{content} .= "startxref\n$startxref\n";
   $self->{startxref} = $startxref;

   # Append EOF
   $self->{content} .= "%%EOF\n";

   $self->{contentlength} = length $self->{content};

   return $self;
}

=item $doc->cleansave()

Call the clean() function, then call the save() function.

=cut

sub cleansave
{
   my $self = shift;

   $self->clean();
   return $self->save();
}

=item $doc->output($filename)

=item $doc->output()

Save the document to a file.  The save() function is called first to
serialize the data structure.  If no filename is specified, or if the
filename is '-', the document is written to standard output.

Note: it is the responsibility of the application to ensure that the
PDF document has either the Modify or Add permission.  You can do this
like the following:

   if ($self->canModify()) {
      $self->output($outfile);
   } else {
      die "The PDF file denies permission to make modifications\n";
   }

=cut

sub output
{
   my $self = shift;
   my $file = shift;
   if (!defined $file)
   {
      $file = q{-};
   }

   $self->save();

   if ($file eq q{-})
   {
      binmode STDOUT;
      print $self->{content};
   }
   else
   {
      open my $fh, '>', $file or die "Failed to write file $file\n";
      binmode $fh;
      print {$fh} $self->{content};
      close $fh;
   }
   return $self;
}

=item $doc->cleanoutput($file)

=item $doc->cleanoutput()

Call the clean() function, then call the output() function to write a
fresh copy of the document to a file.

=cut

sub cleanoutput
{
   my $self = shift;
   my $file = shift;

   $self->clean();
   return $self->output($file);
}

=item $doc->writeObject($objnum)

Return the serialization of the specified object.

=cut

sub writeObject
{
   my $self = shift;
   my $objnum = shift;

   return "$objnum 0 " . $self->writeAny($self->dereference($objnum));
}

=item $doc->writeString($string)

Return the serialization of the specified string.  Works on normal or
hex strings.  If encryption is desired, the string should be encrypted
before being passed here.

=cut

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

   my $maxstr = (ref $pkg_or_doc) ? $pkg_or_doc->{maxstr} : $CAM::PDF::MAX_STRING;
   my @strs = grep {$_ ne q{}} split /(.{$maxstr}})/xms, $string;
   for (@strs)
   {
      s/ \\       /\\\\/gxms;  # escape escapes -- this line must come first!
      s/ ([\(\)]) /\\$1/gxms;  # escape parens
      s/ \n       /\\n/gxms;
      s/ \r       /\\r/gxms;
      s/ \t       /\\t/gxms;
      s/ \f       /\\f/gxms;
      # TODO: handle backspace char
      #s/ ???      /\\b/gxms;
   }
   return '(' . (join "\\\n", @strs) . ')';
}

=item $doc->writeAny($node)

Returns the serialization of the specified node.  This handles all
Node types, including object Nodes.

=cut

sub writeAny
{
   my $self = shift;
   my $obj = shift;

   if (! ref $obj)
   {
      die 'Not a ref';
   }

   my $key = $obj->{type};
   my $val = $obj->{value};
   my $objnum = $obj->{objnum};
   my $gennum = $obj->{gennum};

   return $key eq 'string'     ? $self->writeString($self->{crypt}->encrypt($self, $val, $objnum, $gennum))
        : $key eq 'hexstring'  ? '<' . (unpack 'H*', $self->{crypt}->encrypt($self, $val, $objnum, $gennum)) . '>'
        : $key eq 'number'     ? "$val"
        : $key eq 'reference'  ? "$val 0 R" # TODO: lookup the gennum and use it instead of 0 (?)
        : $key eq 'boolean'    ? $val
        : $key eq 'null'       ? 'null'
        : $key eq 'label'      ? "/$val"
        : $key eq 'array'      ? $self->_writeArray($obj)
        : $key eq 'dictionary' ? $self->_writeDictionary($obj)
        : $key eq 'object'     ? $self->_writeObject($obj)

        : die "Unknown key '$key' in writeAny (objnum ".($objnum||'<none>').")\n";
}

sub _writeArray
{
   my $self = shift;
   my $obj = shift;

   my $val = $obj->{value};
   if (@$val == 0)
   {
      return '[ ]';
   }
   my $str = q{};
   my @strs;
   for (@$val)
   {
      my $newstr = $self->writeAny($_);
      if ($str ne q{})
      {
         if ($self->{maxstr} < length $str . $newstr)
         {
            push @strs, $str;
            $str = q{};
         }
         else
         {
            $str .= q{ };
         }
      }
      $str .= $newstr;
   }
   if (@strs > 0)
   {
      $str = join "\n", @strs, $str;
   }
   return '[ ' . $str . ' ]';
}

sub _writeDictionary
{
   my $self = shift;
   my $obj = shift;

   my $val = $obj->{value};
   my $str = q{};
   my @strs;
   if (exists $val->{Type})
   {
      $str .= ($str ? q{ } : q{}) . '/Type ' . $self->writeAny($val->{Type});
   }
   if (exists $val->{Subtype})
   {
      $str .= ($str ? q{ } : q{}) . '/Subtype ' . $self->writeAny($val->{Subtype});
   }
   for my $dictkey (sort keys %$val)
   {
      next if ($dictkey eq 'Type');
      next if ($dictkey eq 'Subtype');
      next if ($dictkey eq 'StreamDataDone');
      if ($dictkey eq 'StreamData')
      {
         if (exists $val->{StreamDataDone})
         {
            delete $val->{StreamDataDone};
            next;
         }
         # This is a stream way down deep in the data...  Probably due to a solidifyObject
         
         # First, try to handle the easy case:
         if (2 == scalar keys %$val && (exists $val->{Length} || exists $val->{L}))
         {
            my $str = $val->{$dictkey}->{value};
            my $len = length $str;
            my $unpacked = unpack 'H' . $len*2, $str;
            return $self->writeAny(CAM::PDF::Node->new('hexstring', $unpacked, $obj->{objnum}, $obj->{gennum}));
         }
         
         # TODO: Handle more complex streams ...
         die "This stream is too complex for me to write... Giving up\n";
         
         next;
      }
      
      my $newstr = "/$dictkey " . $self->writeAny($val->{$dictkey});
      if ($str ne q{})
      {
         if ($self->{maxstr} < length $str . $newstr)
         {
            push @strs, $str;
            $str = q{};
         }
         else
         {
            $str .= q{ };
         }
      }
      $str .= $newstr;
   }
   if (@strs > 0)
   {
      $str = join "\n", @strs, $str;
   }
   return '<< ' . $str . ' >>';
}

sub _writeObject
{
   my $self = shift;
   my $obj = shift;

   my $val = $obj->{value};
   if (! ref $val)
   {
      die "Obj data is not a ref! ($val)";
   }
   my $stream;
   if ($val->{type} eq 'dictionary' && exists $val->{value}->{StreamData})
   {
      $stream = $val->{value}->{StreamData}->{value};
      my $length = length $stream;
      
      my $l = $val->{value}->{Length} || $val->{value}->{L};
      my $oldlength = $self->getValue($l);
      if ($length != $oldlength)
      {
         $val->{value}->{Length} = CAM::PDF::Node->new('number', $length, $obj->{objnum}, $obj->{gennum});
         delete $val->{value}->{L};
      }
      $val->{value}->{StreamDataDone} = 1;
   }
   my $str = $self->writeAny($val);
   if ($stream)
   {
      $stream = $self->{crypt}->encrypt($self, $stream, $obj->{objnum}, $obj->{gennum});
      $str .= "\nstream\n" . $stream . 'endstream';
   }
   return "obj\n$str\nendobj\n";
}

######################################################################

=back

=head2 Document Traversing

=over

=item $doc->traverse($dereference, $node, $callbackfunc, $callbackdata)

Recursive traversal of a PDF data structure.

In many cases, it's useful to apply one action to every node in an
object tree.  The routines below all use this traverse() function.
One of the most important parameters is the first: the C<$dereference>
boolean.  If true, the traversal follows reference Nodes.  If false,
it does not descend into reference Nodes.

=cut

sub traverse
{
   my $self = shift;
   my $deref = shift;
   my $obj = shift;
   my $func = shift;
   my $funcdata = shift;

   my $traversed = {};
   my @stack = ($obj);

   my $i = 0;
   while ($i < @stack)
   {
      my $obj = $stack[$i++];
      $self->$func($obj, $funcdata);

      my $type = $obj->{type};
      my $val = $obj->{value};

      if ($type eq 'object')
      {
         # Shrink stack periodically
         splice @stack, 0, $i;
         $i = 0;
         # Mark object done
         if ($obj->{objnum})
         {
            $traversed->{$obj->{objnum}} = 1;
         }
      }

      push @stack, $type eq 'dictionary'          ? values %$val
                 : $type eq 'array'               ? @$val
                 : $type eq 'object'              ? $val
                 : $type eq 'reference'
                   && $deref
                   && !exists $traversed->{$val}  ? $self->dereference($val)
                 : ();
   }
   return;
}

# decodeObject and decodeAll differ from each other like this:
#
#  decodeObject JUST decodes a single stream directly below the object
#  specified by the objnum
#
#  decodeAll descends through a whole object tree (following
#  references) decoding everything it can find

=item $doc->decodeObject($objectnum)

I<For INTERNAL use>

Remove any filters (like compression, etc) from a data stream
indicated by the object number.

=cut

sub decodeObject
{
   my $self = shift;
   my $objnum = shift;

   my $obj = $self->dereference($objnum);

   $self->decodeOne($obj->{value}, 1);
   return;
}

=item $doc->decodeAll($object)

I<For INTERNAL use>

Remove any filters from any data stream in this object or any object
referenced by it.

=cut

sub decodeAll
{
   my $self = shift;
   my $obj = shift;

   $self->traverse(1, $obj, \&decodeOne, 1);
   return;
}

=item $doc->decodeOne($object)

=item $doc->decodeOne($object, $save?)

I<For INTERNAL use>

Remove any filters from an object.  The boolean flag C<$save> (defaults to
false) indicates whether this removal should be permanent or just
this once.  If true, the function returns success or failure.  If
false, the function returns the defiltered content.

=cut

sub decodeOne
{
   my $self = shift;
   my $obj = shift;
   my $save = shift || 0;

   my $changed = 0;
   my $data = q{};

   if ($obj->{type} eq 'dictionary')
   {
      my $dict = $obj->{value};

      $data = $dict->{StreamData}->{value};
      #warn 'decoding thing ' . ($dict->{StreamData}->{objnum} || '(unknown)') . "\n";

      # Don't work on {F} since that's too common a word
      #my $filtobj = $dict->{Filter} || $dict->{F};
      my $filtobj = $dict->{Filter}; 

      if (defined $filtobj)
      {
         my @filters;
         if ($filtobj->{type} eq 'array')
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
         elsif ($parmobj->{type} eq 'array')
         {
            @parms = @{$parmobj->{value}};
         }
         else
         {
            @parms = ($parmobj);
         }

         for my $filter (@filters)
         {
            if ($filter->{type} ne 'label')
            {
               warn "All filter names must be labels\n";
               require Data::Dumper;
               warn Data::Dumper->Dump([$filter], ['Filter']);
               next;
            }
            my $filtername = $filter->{value};

            # Make sure this is not an encrypt dict
            next if ($filtername eq 'Standard');

            #if ($filtername eq 'LZWDecode' || $filtername eq 'LZW')
            #{
            #   warn "$filtername filter not supported\n";
            #   next;
            #}

            my $filt;
            eval {
               require Text::PDF::Filter;
               my $package = 'Text::PDF::' . ($filterabbrevs{$filtername} || $filtername);
               $filt = $package->new;
               if (!$filt)
               {
                  die;
               }
            };
            if ($EVAL_ERROR)
            {
               warn "Failed to open filter $filtername (Text::PDF::$filtername)\n";
               last;
            }

            my $oldlength = length$data;

            {
               # Hack to turn off warnings in Filter library
               no warnings;
               $data = $filt->infilt($data, 1);
            }

            $self->fixDecode(\$data, $filtername, shift @parms);
            my $length = length $data;

            #warn "decoded length: $oldlength -> $length\n";

            if ($save)
            {
               my $objnum = $dict->{StreamData}->{objnum};
               my $gennum = $dict->{StreamData}->{gennum};
               if ($objnum)
               {
                  $self->{changes}->{$objnum} = 1;
               }
               $changed = 1;
               $dict->{StreamData}->{value} = $data;
               if ($length != $oldlength)
               {
                  $dict->{Length} = CAM::PDF::Node->new('number', $length, $objnum, $gennum);
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

=item $doc->fixDecode($data, $filter, $params)

This is a utility method to do any tweaking after removing the filter
from a data stream.

=cut

sub fixDecode
{
   my $self = shift;
   my $data = shift;
   my $filter = shift;
   my $parms = shift;

   if (!$parms)
   {
      return;
   }
   my $d = $self->getValue($parms);
   if (!$d || (ref $d) ne 'HASH')
   {
      die "DecodeParms must be a dictionary.\n";
   }
   if ($filter eq 'FlateDecode' || $filter eq 'Fl' || 
       $filter eq 'LZWDecode' || $filter eq 'LZW')
   {
      if (exists $d->{Predictor})
      {
         my $p = $self->getValue($d->{Predictor});
         if ($p >= 10 && $p <= 15)
         {
            #warn "Fix PNG\n";
            if (exists $d->{Columns})
            {
               my $c       = $self->getValue($d->{Columns});
               my $len     = length $$data;
               my $newdata = q{};

               my $i = 1;
               while ($i < $len)
               {
                  $newdata .= substr $$data, $i, $c;
                  $i += $c+1;
               }
               $$data = $newdata;
            }
         }
      }
   }
   return;
}

=item $doc->encodeObject($objectnum, $filter)

Apply the specified filter to the object.

=cut

sub encodeObject
{
   my $self = shift;
   my $objnum = shift;
   my $filtername = shift;

   my $obj = $self->dereference($objnum);

   $self->encodeOne($obj->{value}, $filtername);
   return;
}

=item $doc->encodeOne($object, $filter)

Apply the specified filter to the object.

=cut

sub encodeOne
{
   my $self = shift;
   my $obj = shift;
   my $filtername = shift;

   my $changed = 0;

   if ($obj->{type} eq 'dictionary')
   {
      my $dict = $obj->{value};
      my $objnum = $obj->{objnum};
      my $gennum = $obj->{gennum};

      if (! exists $dict->{StreamData})
      {
         #warn "Object does not contain a Stream to encode\n";
         return 0;
      }

      if ($filtername eq 'LZWDecode' || $filtername eq 'LZW')
      {
         $filtername = 'FlateDecode';
         warn "LZWDecode filter not supported for encoding.  Using $filtername instead\n";
      }
      my $filt;
      eval {
         require Text::PDF::Filter;
         my $package = "Text::PDF::$filtername";
         $filt = $package->new;
         if (!$filt)
         {
            die;
         }
      };
      if ($EVAL_ERROR)
      {
         warn "Failed to open filter $filtername (Text::PDF::$filtername)\n";
         return 0;
      }

      my $l = $dict->{Length} || $dict->{L};
      my $oldlength = $self->getValue($l);
      $dict->{StreamData}->{value} = $filt->outfilt($dict->{StreamData}->{value}, 1);
      my $length = length $dict->{StreamData}->{value};

      if (! defined $oldlength || $length != $oldlength)
      {
         if (defined $l && $l->{type} eq 'reference')
         {
            my $lenobj = $self->dereference($l->{value})->{value};
            if ($lenobj->{type} ne 'number')
            {
               die "Expected length to be a reference to an object containing a number while encoding\n";
            }
            $lenobj->{value} = $length;
         }
         elsif (!defined $l || $l->{type} eq 'number')
         {
            $dict->{Length} = CAM::PDF::Node->new('number', $length, $objnum, $gennum);
            delete $dict->{L};
         }
         else
         {
            die "Unexpected type \"$l->{type}\" for Length while encoding.\n" .
                "(expected \"number\" or \"reference\")\n";
         }
      }

      # Record the filter
      my $newfilt = CAM::PDF::Node->new('label', $filtername, $objnum, $gennum);
      my $f = $dict->{Filter} || $dict->{F};
      if (!defined $f)
      {
         $dict->{Filter} = $newfilt;
         delete $dict->{F};
      }
      elsif ($f->{type} eq 'label')
      {
         $dict->{Filter} = CAM::PDF::Node->new('array', [
                                                         $newfilt,
                                                         $f,
                                                         ],
                                               $objnum, $gennum);
         delete $dict->{F};
      }
      elsif ($f->{type} eq 'array')
      {
         unshift @{$f->{value}}, $newfilt;
      }
      else
      {
         die "Confused: Filter type is \"$f->{type}\", not the\n" .
             "expected \"array\" or \"label\"\n";
      }

      if ($dict->{DecodeParms} || $dict->{DP})
      {
         die "Insertion of DecodeParms not yet supported...\n";
      }

      if ($objnum)
      {
         $self->{changes}->{$objnum} = 1;
      }
      $changed = 1;
   }
   return $changed;
}


=item $doc->setObjNum($object, $objectnum, $gennum)

Descend into an object and change all of the INTERNAL object number
flags to a new number.  This is just for consistency of internal
accounting.

=cut

sub setObjNum
{
   my $self = shift;
   my $obj = shift;
   my $objnum = shift;
   my $gennum = shift;
   
   $self->traverse(0, $obj, \&_setObjNumCB, [$objnum, $gennum]);
   return;
}

# PRIVATE FUNCTION

sub _setObjNumCB
{
   my $self = shift;
   my $obj = shift;
   my $nums = shift;
   
   $obj->{objnum} = $nums->[0];
   $obj->{gennum} = $nums->[1];
   return;
}

=item $doc->getRefList($object)

I<For INTERNAL use>

Return an array all of objects referred to in this object.

=cut

sub getRefList
{
   my $self = shift;
   my $obj = shift;
   
   my $list = {};
   $self->traverse(1, $obj, \&_getRefListCB, $list);

   return (sort keys %$list);
}

# PRIVATE FUNCTION

sub _getRefListCB
{
   my $self = shift;
   my $obj = shift;
   my $list = shift;
   
   if ($obj->{type} eq 'reference')
   {
      $list->{$obj->{value}} = 1;
   }
   return;
}

=item $doc->changeRefKeys($object, $hashref)

I<For INTERNAL use>

Renumber all references in an object.

=cut

sub changeRefKeys
{
   my $self = shift;
   my $obj = shift;
   my $newrefkeys = shift;

   my $follow = shift || 0;   # almost always false

   $self->traverse($follow, $obj, \&_changeRefKeysCB, $newrefkeys);
   return;
}

# PRIVATE FUNCTION

sub _changeRefKeysCB
{
   my $self = shift;
   my $obj = shift;
   my $newrefkeys = shift;
   
   if ($obj->{type} eq 'reference')
   {
      if (exists $newrefkeys->{$obj->{value}})
      {
         $obj->{value} = $newrefkeys->{$obj->{value}};
      }
   }
   return;
}

=item $doc->abbrevInlineImage($object)

Contract all image keywords to inline abbreviations.

=cut

sub abbrevInlineImage
{
   my $self = shift;
   my $obj = shift;

   $self->traverse(0, $obj, \&_abbrevInlineImageCB, {reverse %inlineabbrevs});
   return;
}

=item $doc->unabbrevInlineImage($object)

Expand all inline image abbreviations.

=cut

sub unabbrevInlineImage
{
   my $self = shift;
   my $obj = shift;

   $self->traverse(0, $obj, \&_abbrevInlineImageCB, \%inlineabbrevs);
   return;
}

# PRIVATE FUNCTION

sub _abbrevInlineImageCB
{
   my $self = shift;
   my $obj = shift;
   my $convert = shift;

   if ($obj->{type} eq 'label')
   {
      my $new = $convert->{$obj->{value}};
      if (defined $new)
      {
         $obj->{value} = $new;
      }
   }
   elsif ($obj->{type} eq 'dictionary')
   {
      my $dict = $obj->{value};
      for my $key (keys %$dict)
      {
         my $new = $convert->{$key};
         if (defined $new && $new ne $key)
         {
            $dict->{$new} = $dict->{$key};
            delete $dict->{$key};
         }
      }
   }
   return;
}

=item $doc->changeString($object, $hashref)

Alter all instances of a given string.  The hashref is a dictionary of
from-string and to-string.  If the from-string looks like C<regex(...)>
then it is interpreted as a Perl regular expression and is eval'ed.
Otherwise the search-and-replace is literal.

=cut

sub changeString
{
   my $self = shift;
   my $obj = shift;
   my $changelist = shift;

   $self->traverse(0, $obj, \&_changeStringCB, $changelist);
   return;
}

# PRIVATE FUNCTION

sub _changeStringCB
{
   my $self = shift;
   my $obj = shift;
   my $changelist = shift;

   if ($obj->{type} eq 'string')
   {
      for my $key (keys %$changelist)
      {
         if ($key =~ m/ \A regex\((.*)\) \z /xms)
         {
            my $regex = $1;
            my $res;
            eval {
               $res = ($obj->{value} =~ s/ $regex /$$changelist{$key}/gxms);
            };
            if ($EVAL_ERROR)
            {
               die "Failed regex search/replace: $EVAL_ERROR\n";
            }
            if ($res && $obj->{objnum})
            {
               $self->{changes}->{$obj->{objnum}} = 1;
            }
         }
         else
         {
            if ($obj->{value} =~ s/ $key /$$changelist{$key}/gxms && $obj->{objnum})
            {
               $self->{changes}->{$obj->{objnum}} = 1;
            }
         }
      }
   }
   return;
}

######################################################################

=back

=head2 Utility functions

=over

=item $doc->rangeToArray($min, $max, $list...)

Converts string lists of numbers to an array.  For example,

    CAM::PDF->rangeToArray(1, 15, '1,3-5,12,9', '14-', '8 - 6, -2');

becomes

    (1,3,4,5,12,9,14,15,8,7,6,1,2)

=cut

sub rangeToArray
{
   my $pkg_or_doc = shift;
   my $min = shift;
   my $max = shift;
   my @array1 = grep {defined $_} @_;

   @array1 = map { 
      s/ [^\d\-,] //gxms;   # clean
      m/ ([\d\-]+) /gxms;   # split on numbers and ranges
   } @array1;

   my @array2;
   if (@array1 == 0)
   {
      @array2 = $min .. $max;
   }
   else
   {
      for (@array1)
      {
         if (m/ (\d*)-(\d*) /xms)
         {
            my $a = $1;
            my $b = $2;
            if ($a eq q{})
            {
               $a = $min-1;
            }
            if ($b eq q{})
            {
               $b = $max+1;
            }
            
            # Check if these are possible
            next if ($a < $min && $b < $min);
            next if ($a > $max && $b > $max);
            
            if ($a < $min)
            {
               $a = $min;
            }
            if ($b < $min)
            {
               $b = $min;
            }
            if ($a > $max)
            {
               $a = $max;
            }
            if ($b > $max)
            {
               $b = $max;
            }
            
            if ($a > $b)
            {
               push @array2, reverse $b .. $a;
            }
            else
            {
               push @array2, $a .. $b;
            }
         }
         elsif ($_ >= $min && $_ <= $max)
         {
            push @array2, $_;
         }
      }
   }
   return @array2;
}

=item $doc->trimstr($string)

Used solely for debugging.  Trims a string to a max of 40 characters,
handling nulls and non-Unix line endings.

=cut

sub trimstr
{
   my $pkg_or_doc = shift;
   my $s = $_[0];

   my $pos = pos $_[0];
   $pos ||= 0;

   if (!defined $s || $s eq q{})
   {
      $s = '(empty)';
   }
   elsif (length $s > 40)
   {
      $s = (substr $s, $pos, 40) . '...';
   }
   $s =~ s/ \r /^M/gxms;
   return $pos . q{ } . $s . "\n";
}

=item $doc->copyObject($node)

Clones a node via Data::Dumper and eval().

=cut

sub copyObject
{
   my $self = shift;
   my $obj = shift;

   # replace $obj with a copy of itself
   require Data::Dumper;
   my $d = Data::Dumper->new([$obj],['obj']);
   $d->Purity(1)->Indent(0);
   eval $d->Dump();   ## no critic for string eval

   return $obj;
}   


=item $doc->cacheObjects()

Parses all object Nodes and stores them in the cache.  This is useful
for cases where you intend to do some global manipulation and want all
of the data conveniently in RAM.

=cut

sub cacheObjects
{
   my $self = shift;

   for my $key (keys %{$self->{xref}})
   {
      if (!exists $self->{objcache}->{$key})
      {
         $self->{objcache}->{$key} = $self->dereference($key);
      }
   }
   return;
}

=item $doc->asciify($string)

Helper class/instance method to massage a string, cleaning up some
non-ASCII problems.  This is a very ad-hoc list.  Specifically:

=over

=item f-i ligatures

=item (R) symbol

=back

=cut

sub asciify
{
   my $pkg_or_doc = shift;
   my $R_string = shift;   # scalar reference

   ## Heuristics: fix up some odd text characters:
   # f-i ligature
   $$R_string =~ s/ \223 /fi/gxms;
   # Registered symbol
   $$R_string =~ s/ \xae /(R)/gxms;
   return $pkg_or_doc;
}

1;
__END__

=back

=head1 COMPATIBILITY

This library was primarily developed against the 3rd edition of the
reference (PDF v1.4) with a few updates from 4th edition.  This
library focuses on PDF v1.2 features.  Nonetheless, it should be
forward and backward compatible in the majority of cases.

=head1 PERFORMANCE

This module is written with good speed and flexibility in mind, often
at the expense of memory consumption.  Entire PDF documents are
typically slurped into RAM.  As an example, simply calling
C<new('PDFReference15_v15.pdf')> (the 14 MB Adobe PDF Reference V1.5
document) pushes Perl to consume 84 MB of RAM on my development
machine.

=head1 SEE ALSO

There are several other PDF modules on CPAN.  Below is a brief
description of a few of them.

=over

=item PDF::API2

As of v0.46.003, LGPL license.

This is the leading PDF library, in my opinion.

Excellent text and font support.  This is the highest level library of
the bunch, and is the most complete implementation of the Adobe PDF
spec.  The author is amazingly responsive and patient.

=item Text::PDF

As of v0.25, Artistic license.

Excellent compression support (CAM::PDF cribs off this Text::PDF
feature).  This has not been developed since 2003.

=item PDF::Reuse

As of v0.32, Artistic/GPL license, like Perl itself.

This library is not object oriented, so it can only process one PDF at
a time, while storing all data in global variables.

=back

CAM::PDF is the only one of these that has regression tests.
Currently, CAM::PDF has test coverage of about 50%, as reported by
C<Build testcover>.

Additionally, PDFLib is a commercial package not on CPAN
(L<www.pdflib.com>).  It is a C-based library with a Perl interface.
It is designed for PDF creation, not for reuse.

=head1 INTERNALS

The data structure used to represent the PDF document is composed
primarily of a hierarchy of Node objects.  Every node in the document
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
metadata.  Every node in the hierarchy contains its object and
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

=cut
