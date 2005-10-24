package CAM::PDF::PageText;

use 5.006;
use warnings;
use strict;

our $VERSION = '1.03';

=head1 NAME

CAM::PDF::PageText - Extract text from PDF pagetree

=head1 LICENSE

Copyright 2005 Clotho Advanced Media, Inc., <cpan@clotho.com>

This library is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 FUNCTIONS

=over

=item render PAGETREE

=item render PAGETREE, VERBOSE

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
   while (@stack > 0)
   {
      my $node = $stack[-1];
      if (ref $node)
      {
         if (@$node > 0)
         {
            my $block = shift @$node;
            if ($block->{type} eq 'block')
            {
               if ($block->{name} eq 'BT')
               {
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
               if ($block->{name} eq 'TJ')    ## no critic for if-elsif chain
               {
                  if (@args != 1 || $args[0]->{type} ne 'array')
                  {
                     die 'Bad TJ';
                  }

                  $str =~ s/(\S)$/$1 /s;
                  foreach my $node (@{$args[0]->{value}})
                  {
                     if ($node->{type} =~ /string/)
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
                           $str =~ s/(\S)$/$1 /s;
                        }
                     }
                  }
               }
               elsif ($block->{name} =~ /^Tj|\'|\"$/)
               {
                  if (@args < 1 ||
                      $args[-1]->{type} !~ /string$/)
                  {
                     die 'Bad Tj';
                  }
                  if ($block->{name} eq 'Tj')
                  {
                     $str =~ s/(\S)$/$1 /s;
                  }
                  else
                  {
                     $str =~ s/ *$/\n/s;
                  }
                  $str .= $args[-1]->{value};
               }
               elsif ($block->{name} eq 'Td' || $block->{name} eq 'TD')
               {
                  if (@args != 2 || 
                      $args[0]->{type} ne 'number' ||
                      $args[1]->{type} ne 'number')
                  {
                     die 'Bad Td/TD';
                  }
                  # Heuristic:
                  #   "move down in Y, and Y motion a large fraction of the X motion"
                  # means new line
                  if ($args[1]->{value} < 0 && 2*(abs $args[1]->{value}) > abs $args[0]->{value})
                  {
                     $str =~ s/ *$/\n/s;
                  }
               }
               elsif ($block->{name} eq 'T*')
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
         $in_textblock = 0;
         $str =~ s/ *$/\n/s;
         pop @stack;
      }
   }
   return $str;
}

1;
__END__

=back

=head1 AUTHOR

Clotho Advanced Media Inc., I<cpan@clotho.com>

Primary developer: Chris Dolan
