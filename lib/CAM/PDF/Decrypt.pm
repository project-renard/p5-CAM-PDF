package CAM::PDF::Decrypt;

#  These are included at runtime via eval below
# use Digest::MD5;
# use Crypt::RC4;

use 5.006;
use warnings;
use strict;
use Carp;
use English qw(-no_match_vars);
use CAM::PDF;
use CAM::PDF::Node;

our $VERSION = '1.09';

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

# These constants come from the Adobe PDF Reference document, IIRC
my $padding = pack 'C*',
    0x28, 0xbf, 0x4e, 0x5e, 
    0x4e, 0x75, 0x8a, 0x41, 
    0x64, 0x00, 0x4e, 0x56, 
    0xff, 0xfa, 0x01, 0x08, 
    0x2e, 0x2e, 0x00, 0xb6, 
    0xd0, 0x68, 0x3e, 0x80, 
    0x2f, 0x0c, 0xa9, 0xfe, 
    0x64, 0x53, 0x69, 0x7a;


=head1 FUNCTIONS

=over

=item $pkg->new($pdf, $ownerpass, $userpass, $prompt)

Create and validate a new decryption object.  If this fails, it will
set $CAM::PDF::errstr and return undef.

C<$prompt> is a boolean that says whether the user should be prompted for
a password on the command line.

=cut

sub new
{
   my $pkg = shift;
   my $doc = shift;
   my $opassword = shift;
   my $upassword = shift;
   my $prompt = shift;

   if (!$doc)
   {
      $CAM::PDF::errstr = "This is an invalid PDF doc\n";
      return;
   }

   if (!exists $doc->{trailer})
   {
      $CAM::PDF::errstr = "This PDF doc has no trailer\n";
      return;
   }

   my $self = bless {
      keycache => {},
   }, $pkg;

   if (!exists $doc->{trailer}->{Encrypt})
   {
      # This PDF doc is not encrypted.  Return an empty object
      $self->{noop} = 1;
   }
   else
   {
      if ($doc->{trailer}->{Encrypt}->{type} eq 'reference')
      {
         # If the encryption block is an indirect reference, store
         # it's location so we don't accidentally encrypt it.
         $self->{EncryptBlock} = $doc->{trailer}->{Encrypt}->{value};
      }
   
      require Digest::MD5;
      require Crypt::RC4;
      
      my $dict = $doc->getValue($doc->{trailer}->{Encrypt});
      
      if ($dict->{Filter}->{value} ne 'Standard' || $dict->{V}->{value} != 1)
      {
         $CAM::PDF::errstr = "CAM::PDF only supports Version 1 of the Standard encryption filter.  This PDF uses something else.\n";
         return;
      }
      
      foreach my $key ('O', 'U', 'P')
      {
         if (exists $dict->{$key})
         {
            $self->{$key} = $dict->{$key}->{value};
         }
         else
         {
            $CAM::PDF::errstr = "Requred decryption datum $key is missing.  The document cannot be decrypted.\n";
            return;
         }
      }

      if (!$doc->{ID})
      {
         $CAM::PDF::errstr = "This PDF lacks an ID.  The document cannot be decrypted.\n";
         return;
      }

      my $success = 0;
      while (!$success)
      {
         if ($self->_check_pass($doc->{ID}, $opassword, $upassword))
         {
            $success = 1;
         }
         elsif ($prompt)
         {
            print STDERR 'Enter owner password: ';
            $opassword = <STDIN>;
            chomp $opassword;
            
            print STDERR 'Enter user password: ';
            $upassword = <STDIN>;
            chomp $upassword;
         }
         else
         {
            $CAM::PDF::errstr = "Incorrect password(s).  The document cannot be decrypted.\n";
            return;
         }
      }

      $self->{code} = $self->_compute_hash($doc->{ID}, $opassword);
   }

   $self->{opass} = $opassword;
   $self->{upass} = $upassword;

   return $self;
}

=item $self->decode_permissions($field)

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

   my $b = unpack 'b*', pack 'V', $p;
   return split //xms, substr $b, 2, 4;
}

=item $self->encode_permissions($print, $modify, $copy, $add)

Given four booleans, pack them into a single field in the PDF style
that decode_permissions can understand.  Returns that scalar.

=cut

sub encode_permissions
{
   my $self = shift;

   my %allow;
   $allow{print}  = shift;
   $allow{modify} = shift;
   $allow{copy}   = shift;
   $allow{add}    = shift;

   foreach my $key (keys %allow)
   {
      $allow{$key} = $allow{$key} ? 1 : 0;
   }

   # This is more complicated that decode, because we need to pad
   # endian-appropriately

   my $perms = join q{}, $allow{print}, $allow{modify}, $allow{copy}, $allow{add};
   my $b = '00' . $perms . '11'; # 8 bits: 2 pad, 4 data, 2 pad
   # Pad to 32 bits with the right endian-ness
   my $binary = unpack 'B16', pack 's', 255;
   if ('1' eq substr $binary, 0, 1)
   {
      # little endian
      $b .= '11111111' x 3;
   }
   else
   {
      # big endian
      $b = ('11111111' x 3) . $b;
   }
   # Make a signed 32-bit number (NOTE: should this really be signed???  need to check spec...)
   my $p = unpack 'l', pack 'b32', $b;

   return $p;
}

=item $self->set_passwords($doc, $ownerpass, $userpass)

=item $self->set_passwords($doc, $ownerpass, $userpass, $permissions)

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

   require Digest::MD5;
   require Crypt::RC4;

   $doc->clean();  # Mark EVERYTHING changed

   #  if no crypt block, create it and a trailer entry
   my $dict = CAM::PDF::Node->new('dictionary',
                                  {
                                     Filter => CAM::PDF::Node->new('label', 'Standard'),
                                     V => CAM::PDF::Node->new('number', 1),
                                     R => CAM::PDF::Node->new('number', 2),
                                     P => CAM::PDF::Node->new('number', $p),
                                     O => CAM::PDF::Node->new('string', q{}),
                                     U => CAM::PDF::Node->new('string', q{}),
                                  });
   my $objnode = CAM::PDF::Node->new('object', $dict);

   my $objnum = $self->{EncryptBlock};
   if ($objnum)
   {
      $doc->replaceObject($objnum, undef, $objnode, 0);
   }
   else
   {
      $objnum = $doc->appendObject(undef, $objnode, 0);
   }

   if (!$doc->{trailer})
   {
      die 'No trailer';
   }

   # This may overwrite an existing ref, but that's no big deal, just a tiny bit inefficient
   $doc->{trailer}->{Encrypt} = CAM::PDF::Node->new('reference', $objnum);
   $doc->{EncryptBlock} = $objnum;

   #  if no ID, create it
   if (!$doc->{ID})
   {
      $doc->createID();
      #print 'new ID: ' . unpack('h*',$doc->{ID}) . ' (' . length($doc->{ID}) . ")\n";
   }
   #else { print 'old ID: '.unpack('h*',$doc->{ID}) . ' (' . length($doc->{ID}) . ")\n"; }

   #  record data
   $self->{opass} = $opass;
   $self->{upass} = $upass;
   $self->{P} = $p;

   #  set O  (has to be first because U uses O)
   $self->{O} = $self->_compute_o($opass, $upass);

   #  set U
   $self->{U} = $self->_compute_u($doc->{ID}, $upass);

   #  save O and U in the Encrypt block
   $dict = $doc->getObjValue($objnum);
   $dict->{O}->{value} = $self->{O};
   $dict->{U}->{value} = $self->{U};

   # Create a brand new instance
   my $pkg = ref $self;
   $doc->{crypt} = $pkg->new($doc, $opass, $upass, 0)
       || die "$CAM::PDF::errstr\n";

   return $doc->{crypt};
}

=item $self->encrypt($doc, $string)

Encrypt the scalar using the passwords previously specified.

=cut

sub encrypt
{
   my $self = shift;
   return $self->_crypt(@_);
}

=item $self->decrypt($doc, $string)

Decrypt the scalar using the passwords previously specified.

=cut

sub decrypt
{
   my $self = shift;
   return $self->_crypt(@_);
}

# INTERNAL FUNCTION
# The real work behind encrpyt/decrypt

my %tried;
sub _crypt
{
   my $self    = shift;
   my $doc     = shift;
   my $content = shift;
   my $objnum  = shift;
   my $gennum  = shift;

   return $content if ($self->{noop});

   if (ref $content || ref $objnum || ref $gennum)
   {
      die 'Trying to crypt data with non-scalar obj/gennum or content';
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

      croak 'gennum missing in crypt';
   }
   
   return Crypt::RC4::RC4($self->_compute_key($objnum, $gennum), $content);
}

sub _compute_key
{
   my $self   = shift;
   my $objnum = shift;
   my $gennum = shift;

   my $id = $objnum . '_' .$gennum;
   if (!exists $self->{keycache}->{$id})
   {
      my $objstr = pack 'V', $objnum;
      my $genstr = pack 'V', $gennum;

      my $objpadding = substr $objstr, 0, 3;
      my $genpadding = substr $genstr, 0, 2;

      my $hash = Digest::MD5::md5($self->{code} . $objpadding . $genpadding);

      $self->{keycache}->{$id} = substr $hash, 0, 10;
   }
   return $self->{keycache}->{$id};
}

sub _compute_hash
{
   my $self = shift;
   my $doc_id  = shift;
   my $pass = shift;

   #print "_compute_hash for password $pass, P: $self->{P}, ID: $doc_id, O: $self->{O}\n" if ($pass);

   $pass = $self->_format_pass($pass);

   my $p = pack 'L', $self->{P}+0;
   my $b = unpack 'b32', $p;
   if (1 == substr $b, 0, 1)
   {
      # big endian, so byte swap
      $p = (substr $p,3,1).(substr $p,2,1).(substr $p,1,1).(substr $p,0,1);
   }

   my $id = substr $doc_id, 0, 16;

   my $input = $pass . $self->{O} . $p . $id;
   return substr Digest::MD5::md5($input), 0, 5;
}

sub _compute_u
{
   my $self  = shift;
   my $doc_id   = shift;
   my $upass = shift;

   my $hash = $self->_compute_hash($doc_id, $upass);
   return Crypt::RC4::RC4($hash, $padding);
}

sub _compute_o
{
   my $self  = shift;
   my $opass = shift;
   my $upass = shift;

   my $o = $self->_format_pass($opass);
   my $u = $self->_format_pass($upass);

   my $code = substr Digest::MD5::md5($o), 0, 5;
   return Crypt::RC4::RC4($code, $u);
}

sub _check_pass
{
   my $self    = shift;
   my $doc_id  = shift;
   my $opass   = shift;
   my $upass   = shift;

   my $crypto = $self->_compute_o($opass, $upass);
   my $cryptu = $self->_compute_u($doc_id, $upass);

   #print 'O: '.(defined $opass ? $opass : '(undef)')."\n$crypto\n vs.\n$self->{O}\n";
   #print 'U: '.(defined $upass ? $upass : '(undef)')."\n$cryptu\n vs.\n$self->{U}\n";

   return $crypto eq $self->{O} && $cryptu eq $self->{U};
}

sub _format_pass
{
   my $self = shift;
   my $pass = shift;

   if (!defined $pass)
   {
      $pass = q{};
   }

   return substr $pass.$padding, 0, 32;
}

1;
__END__

=back

=head1 AUTHOR

See L<CAM::PDF>

=cut
