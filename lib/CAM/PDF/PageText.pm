package CAM::PDF::PageText;

use 5.006;
use warnings;
use strict;

our $VERSION = '1.04_01';

=head1 NAME

CAM::PDF::PageText - Extract text from PDF page tree

=head1 LICENSE

Copyright 2005 Clotho Advanced Media, Inc., <cpan@clotho.com>

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=over

=item $pkg->render($pagetree)

=item $pkg->render($pagetree, $verbose)

Turn a page content tree into a string.  This is a class method that
should be called like:

   CAM::PDF::PageText->render($pagetree);

=cut

sub render
{
   my $pkg      = shift;
   my $pagetree = shift;
   my $verbose  = shift;

   my $str          = q{};
   my @stack        = ([@{$pagetree->{blocks}}]);
   my $in_textblock = 0;

   ## The stack is a list of blocks.  We do depth-first on blocks, but
   ## we must be sure to traverse the children of the blocks in their
   ## original order.

   while (@stack > 0)
   {
      # keep grabbing the same node until it's empty
      my $node = $stack[-1];
      if (ref $node)
      {
         if (@$node > 0)   # Still has children?
         {
            my $block = shift @$node;   # grab the next child
            if ($block->{type} eq 'block')
            {
               if ($block->{name} eq 'BT')
               {
                  # Insert a flag on the stack to say when we leave the BT block
                  push @stack, 'BT';
                  $in_textblock = 1;
               }
               push @stack, [@{$block->{value}}];  # descend
            }
            elsif ($in_textblock)
            {
               if ($block->{type} ne 'op')
               {
                  die 'misconception';
               }
               my @args = @{$block->{args}};

               $str = $block->{name} eq 'TJ'   ? _TJ(     $str, \@args )
                    : $block->{name} eq 'Tj'   ? _Tj(     $str, \@args )
                    : $block->{name} eq q{\'}  ? _Tquote( $str, \@args )
                    : $block->{name} eq q{\"}  ? _Tquote( $str, \@args )
                    : $block->{name} eq 'Td'   ? _Td(     $str, \@args )
                    : $block->{name} eq 'TD'   ? _Td(     $str, \@args )
                    : $block->{name} eq 'T*'   ? _Tstar(  $str         )
                    : $str;
            }
         }
         else
         {
            # Node is now empty, clear it from the stack
            pop @stack;
         }
      }
      else
      {
         # This is the 'BT' flag we pushed on the stack above
         pop @stack;
         $in_textblock = 0;

         # Add a line break to divide the text
         $str =~ s/ [ ]* \z /\n/xms;
      }
   }
   return $str;
}

sub _TJ
{
   my $str = shift;
   my $args_ref = shift;

   if (@$args_ref != 1 || $args_ref->[0]->{type} ne 'array')
   {
      die 'Bad TJ';
   }

   $str =~ s/ (\S) \z /$1 /xms;
   foreach my $node (@{$args_ref->[0]->{value}})
   {
      if ($node->{type} eq 'string' || $node->{type} eq 'hexstring')
      {
         $str .= $node->{value};
      }
      elsif ($node->{type} eq 'number')
      {
         # Heuristic:
         #  "offset of more than a quarter unit forward"
         # means significant positive spacing
         if ($node->{value} < -250)
         {
            $str =~ s/ (\S) \z /$1 /xms;
         }
      }
   }
   return $str;
}

sub _Tj
{
   my $str      = shift;
   my $args_ref = shift;

   if (@$args_ref < 1 ||
       ($args_ref->[-1]->{type} ne 'string' && $args_ref->[-1]->{type} ne 'hexstring'))
   {
      die 'Bad Tj';
   }

   $str =~ s/ (\S) \z /$1 /xms;

   return $str . $args_ref->[-1]->{value};
}

sub _Tquote
{
   my $str      = shift;
   my $args_ref = shift;

   if (@$args_ref < 1 ||
       ($args_ref->[-1]->{type} ne 'string' && $args_ref->[-1]->{type} ne 'hexstring'))
   {
      die 'Bad Tquote';
   }

   $str =~ s/ [ ]* \z /\n/xms;

   return $str . $args_ref->[-1]->{value};
}

sub _Td
{
   my $str      = shift;
   my $args_ref = shift;

   if (@$args_ref != 2 || 
       $args_ref->[0]->{type} ne 'number' ||
       $args_ref->[1]->{type} ne 'number')
   {
      die 'Bad Td/TD';
   }

   # Heuristic:
   #   "move down in Y, and Y motion a large fraction of the X motion"
   # means new line
   if ($args_ref->[1]->{value} < 0 &&
       2 * (abs $args_ref->[1]->{value}) > abs $args_ref->[0]->{value})
   {
      $str =~ s/ [ ]* \z /\n/xms;
   }

   return $str;
}

sub _Tstar
{
   my $str = shift;

   $str =~ s/ [ ]* \z /\n/xms;

   return $str;
}

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>

Primary developer: Chris Dolan

=cut
