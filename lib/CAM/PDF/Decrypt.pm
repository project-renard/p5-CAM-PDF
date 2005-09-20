package CAM::PDF::Decrypt;

=head1 NAME

CAM::PDF::Decrypt - PDF security helper

=head1 LICENSE

See CAM::PDF.

=head1 SYNOPSIS

    use CAM::PDF;
    my $pdf = CAM::PDF->new($filename);

=head1 DESCRIPTION

This class is used invisibly by CAM::PDF whenever it detects that a
document is encrypted.  See new(), getPrefs() and setPrefs() in that
module.

=cut

#----------------

#  These are included at runtime via eval below
# use Digest::MD5 qw(md5);
# use Crypt::RC4;

use warnings;
use strict;
use Carp;
use vars qw(@ISA);

# These constants come from the Adobe PDF Reference document, IIRC
my @padding = (
               0x28, 0xbf, 0x4e, 0x5e, 
               0x4e, 0x75, 0x8a, 0x41, 
               0x64, 0x00, 0x4e, 0x56, 
               0xff, 0xfa, 0x01, 0x08, 
               0x2e, 0x2e, 0x00, 0xb6, 
               0xd0, 0x68, 0x3e, 0x80, 
               0x2f, 0x0c, 0xa9, 0xfe, 
               0x64, 0x53, 0x69, 0x7a,
               );
my $padding = pack("C*", @padding);

#----------------

=head1 FUNCTIONS

=over 4

=cut

#----------------
# Internal function
#

sub loadlibs
{
   foreach my $lib ("Digest::MD5 qw(md5)", "Crypt::RC4")
   {
      eval("local \$SIG{__DIE__} = 'DEFAULT'; " .
           "local \$SIG{__WARN__} = 'DEFAULT'; " .
           "use $lib;");

      if ($@)
      {
         $CAM::PDF::errstr = "Failed to load library $lib.  The document cannot be decrypted.\n";
         return undef;
      }
   }
   return 1;
}
#----------------

=item new PDF, OWNERPASS, USERPASS, PROMPT

Create and validate a new decryption object.  If this fails, it will
set $CAM::PDF::errstr and return undef.

PROMPT is a boolean that says whether the user should be prompted for
a password on the command line.

=cut

sub new($$$$$)
{
   my $pkg = shift;
   my $doc = shift;
   my $opassword = shift;
   my $upassword = shift;
   my $prompt = shift;

   if (!$doc)
   {
      $CAM::PDF::errstr = "This is an invalid PDF doc\n";
      return undef;
   }

   if (!exists $doc->{trailer})
   {
      $CAM::PDF::errstr = "This PDF doc has no trailer\n";
      return undef;
   }

   my $self = bless({
      keycache => {},
   }, $pkg);

   if (!exists $doc->{trailer}->{Encrypt})
   {
      # This PDF doc is not encrypted.  Return an empty object
      $self->{noop} = 1;
      warn "got noop crypt\n" if ($CAM::PDF::speedtesting);
   }
   else
   {
      if ($doc->{trailer}->{Encrypt}->{type} eq "reference")
      {
         # If the encryption block is an indirect reference, store
         # it's location so we don't accidentally encrypt it.
         $self->{EncryptBlock} = $doc->{trailer}->{Encrypt}->{value};
      }
   
      if (!&loadlibs())
      {
         return undef;
      }
      warn "done loadlibs\n" if ($CAM::PDF::speedtesting);
      
      my $dict = $doc->getValue($doc->{trailer}->{Encrypt});
      
      if ($dict->{Filter}->{value} ne "Standard" || $dict->{V}->{value} != 1)
      {
         $CAM::PDF::errstr = "PDF doc encrypted with something other than Version 1 of the Standard filter\n";
         return undef;
      }
      
      foreach my $key ("O", "U", "P")
      {
         if (exists $dict->{$key})
         {
            $self->{$key} = $dict->{$key}->{value};
         }
         else
         {
            $CAM::PDF::errstr = "Requred decryption datum $key is missing.  The document cannot be decrypted.\n";
            return undef;
         }
      }

      my $success = 0;
      do {
         if ($self->check_pass($doc, $opassword, $upassword))
         {
            $success = 1;
         }
         elsif ($prompt)
         {
            print STDERR "Enter owner password: ";
            $opassword = <STDIN>;
            chop $opassword;
            
            print STDERR "Enter user password: ";
            $upassword = <STDIN>;
            chop $upassword;
         }
         else
         {
            $CAM::PDF::errstr = "Incorrect password(s).  The document cannot be decrypted.\n";
            return undef;
         }
      } while (!$success);
      warn "verified pass\n" if ($CAM::PDF::speedtesting);

      $self->{code} = $self->compute_hash($doc, $opassword);
      warn "got hash\n" if ($CAM::PDF::speedtesting);
   }      

   $self->{opass} = $opassword;
   $self->{upass} = $upassword;

   return $self;
}
#----------------

=item decode_permissions FIELD

Given a binary encoded permissions string from a PDF document, return
the four individual boolean fields as an array: 

  print boolean
  modify boolean
  copy boolean
  add boolean

=cut

sub decode_permissions
{
   my $self = shift;
   my $p = shift;

   my $b = unpack("b*",pack("V", $p));
   return split(//, substr($b,2,4));
}
#----------------

=item encode_permissions PRINT, MODIFY, COPY, ADD

Given four booleans, pack them into a single field in the PDF style
that decode_permissions can understand.  Returns that scalar.

=cut

sub encode_permissions
{
   my $self = shift;

   my %allow = ();

   $allow{print} = shift;
   $allow{modify} = shift;
   $allow{copy} = shift;
   $allow{add} = shift;

   foreach my $key (keys %allow)
   {
      $allow{$key} = ($allow{$key} ? 1 : 0);
   }

   # This is more complicated that decode, because we need to pad
   # endian-appropriately

   my @p = ($allow{print}, $allow{modify}, $allow{copy}, $allow{add});
   my $b = "00" . join("", @p) . "11"; # 8 bits: 2 pad, 4 data, 2 pad
   # Pad to 32 bits with the right endian-ness
   if (substr(unpack("B16",pack("s",255)),0,1) eq "1")
   {
      # little endian
      $b .= ("11111111" x 3);
   }
   else
   {
      # big endian
      $b = ("11111111" x 3) . $b;
   }
   # Make a signed 32-bit number (NOTE: should this really be signed???  need to check spec...)
   my $p = unpack("l",pack("b32", $b));

   #warn "(" . join(",", @p) . ") => $b => $p\n";
   return $p;
}
#----------------

=item set_passwords DOC, OWNERPASS, USERPASS

=item set_passwords DOC, OWNERPASS, USERPASS, PERMISSIONS

Change the PDF passwords to the specified values.  When the PDF is
output, it will be encrypted with the new passwords.

PERMISSIONS is an optional scalar of the form that decode_permissions
can understand.  If not specified, the existing values will be
retained.

=cut

sub set_passwords
{
   my $self = shift;
   my $doc = shift;
   my $opass = shift;
   my $upass = shift;
   my $p = shift || $self->{P} || $self->encode_permissions(1,1,1,1);

   if (!&loadlibs())
   {
      die $CAM::PDF::errstr;
   }

   $doc->clean();  # Mark EVERYTHING changed

   #  if no crypt block, create it and a trailer entry
   my $dict = CAM::PDF::Node->new("dictionary",
                                  {
                                     Filter => CAM::PDF::Node->new("label", "Standard"),
                                     V => CAM::PDF::Node->new("number", 1),
                                     R => CAM::PDF::Node->new("number", 2),
                                     P => CAM::PDF::Node->new("number", $p),
                                     O => CAM::PDF::Node->new("string", ""),
                                     U => CAM::PDF::Node->new("string", ""),
                                  });
   my $obj = CAM::PDF::Node->new("object", $dict);

   my $objnum = $self->{EncryptBlock};
   if ($objnum)
   {
      $doc->replaceObject($objnum, undef, $obj, 0);
   }
   else
   {
      $objnum = $doc->appendObject(undef, $obj, 0);
   }

   die "No trailer" if (!$doc->{trailer});

   # This may overwrite an existing ref, but that's no big deal, just a tiny bit inefficient
   $doc->{trailer}->{Encrypt} = CAM::PDF::Node->new("reference", $objnum);
   $doc->{EncryptBlock} = $objnum;

   #  if no ID, create it
   if (!$doc->{ID})
   {
      $doc->createID();
      #print "new ID: " . unpack("h*",$doc->{ID}) . " (" . length($doc->{ID}) . ")\n";
   }

   #  record data
   $self->{opass} = $opass;
   $self->{upass} = $upass;
   $self->{P} = $p;

   #  set O
   $self->{O} = $self->compute_o($opass, $upass);

   #  set U
   $self->{U} = $self->compute_u($doc, $upass);

   #  save O and U in the Encrypt block
   $obj = $doc->dereference($objnum);
   $obj->{value}->{value}->{O}->{value} = $self->{O};
   $obj->{value}->{value}->{U}->{value} = $self->{U};

   # Create a brand new object
   $doc->{crypt} = new(ref($self), $doc, $opass, $upass, 0);
   die "$CAM::PDF::errstr\n" if (!$doc->{crypt});

   return $doc->{crypt};
}
#----------------

=item encrypt DOC, STRING

Encrypt the scalar using the passwords previously specified.

=cut

sub encrypt
{
   my $self = shift;
   return $self->crypt(@_);
}
#----------------

=item decrypt DOC, STRING

Decrypt the scalar using the passwords previously specified.

=cut

sub decrypt
{
   my $self = shift;
   return $self->crypt(@_);
}
#----------------

my %tried;
sub crypt
{
   my $self = shift;
   my $doc = shift;
   my $content = shift;
   my $objnum = shift;
   my $gennum = shift;

   return $content if ($self->{noop});

   if (ref $content || ref $objnum || ref $gennum)
   {
      die "Trying to crypt data with non-scalar obj/gennum or content\n";
   }
   
   # DO NOT encrypt the encryption block!!  :-)
   return $content if ($objnum && $self->{EncryptBlock} && $objnum == $self->{EncryptBlock});

   if (!defined $gennum)
   {
      if (!$objnum)
      {
         # This is not a real document object.  It might be a trailer object.
         return $content;
      }

      &Carp::confess("gennum missing in crypt");
      
      $gennum = $doc->dereference($objnum)->{gennum};
   }
   
   return RC4($self->compute_key($objnum, $gennum), $content);
}
#----------------

sub compute_key
{
   my $self = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $id = $objnum . "_" .$gennum;
   if (!exists $self->{keycache}->{$id})
   {
      $self->{keycache}->{$id} = substr(md5($self->{code} . 
                                            substr(pack("V", $objnum), 0, 3) . 
                                            substr(pack("V", $gennum), 0, 2)),
                                        0, 10);
   }
   return $self->{keycache}->{$id};
}
#----------------

sub compute_hash
{
   my $self = shift;
   my $doc = shift;
   my $pass = shift;

   $pass = $self->format_pass($pass);

   my $p = pack("L", $self->{P}+0);
   my $b = unpack("b32", $p);
   if (substr $b, 0, 1 == 1)
   {
      # byte swap
      $p = substr($p,3,1).substr($p,2,1).substr($p,1,1).substr($p,0,1);
   }

   my $id = substr $doc->{ID}, 0, 16;

   my $input = $pass . $self->{O} . $p . $id;
   return substr(md5($input), 0, 5)
}
#----------------

sub compute_u
{
   my $self = shift;
   my $doc = shift;
   my $upass = shift;

   my $hash = $self->compute_hash($doc, $upass);
   return RC4($hash, $padding);
}
#----------------

sub compute_o
{
   my $self = shift;
   my $opass = shift;
   my $upass = shift;

   my $o = $self->format_pass($opass);
   my $u = $self->format_pass($upass);

   my $code = substr md5($o), 0, 5;
   return RC4($code, $u);
}
#----------------

sub check_pass
{
   my $self = shift;
   my $doc = shift;
   my $opass = shift;
   my $upass = shift;
   my $verbose = shift;

   my $crypto = $self->compute_o($opass, $upass);

   if ($verbose)
   {
      print "O: $opass\n";
      print "$crypto\n";
      print" vs.\n";
      print "$$self{O}\n";
   }

   my $cryptu = $self->compute_u($doc, $upass);

   if ($verbose)
   {
      print "U: $upass\n";
      print "$cryptu\n";
      print" vs.\n";
      print "$$self{U}\n";
   }

   return ($crypto eq $self->{O} && $cryptu eq $self->{U});
}
#----------------

sub format_pass
{
   my $self = shift;
   my $pass = shift || "";

   return substr $pass.$padding, 0, 32;
}
#----------------

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>
