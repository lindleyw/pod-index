#!/usr/bin/env perl

use lib 'lib';
use Pod::Headings;

use v5.20;
use feature 'signatures';
no warnings 'experimental::signatures';

##
## In our use-case, certain head1/head2 need to save the plaintext of
## the Para that follows them.  TODO: How to handle?
## 

my $p = Pod::Headings->new(
    head1 => sub ($parser, $elem, $attrs, $plaintext) {
        print " $elem: $plaintext\n";
        $parser->{_save_head1} = $plaintext;
        undef $parser->{_save_head2};
        $parser->{_save_first_para} = 1;
        1;
    },
    head2 => sub ($parser, $elem, $attrs, $plaintext) {
        print " $elem: $parser->{_save_head1}: $plaintext\n";
        $parser->{_save_head2} = $plaintext;
        $parser->{_save_first_para} = 1;
        1;
    },
    Para => sub ($parser, $elem, $attrs, $plaintext) {
        print " .... text: $plaintext\n" if $parser->{_save_first_para};
        $parser->{_save_first_para} = 0;
        1;
    },
    L => 1,  # Return 0 to drop the plaintext passed to the containing element
);

### TODO:
# Trap the first plain text after a head1 or head2, and prepare to save


$p->parse_file('/home/billl/perl5/perlbrew/perls/perl-5.32.0/lib/site_perl/5.32.0/ojo.pm');

