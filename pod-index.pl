#!/usr/env/perl

use Pod::Simple::SimpleTree;

use warnings;
use strict;

use v5.20;
use feature 'signatures';
no warnings 'experimental::signatures';

use Data::Dumper;

binmode(STDOUT, ":utf8");

# Compare,
#   CPAN::IndexPod
#   Pod::Index

# TODO:
# Probably ought to regard X<…> entities although metacpan doesn't create <a> for them.
#

# Original one-liner (sh)
# grep -r head2 . | perl -n -e 'chomp; s/:=head./:/; s{\./}{}; my($fil,$head)=split /:/;$href=$head;$href=~s/^\s//;$href=~s/\s/-/g;$fil=~s{\..+}{}g;$fil=~s{/}{::}g;print "$head: <a href=https://metacpan.org/pod/$fil#$href>$fil</a><br>\n"' | sort | uniq >/tmp/f.html

################

{
    # Maps local filename to manpage name.  Based on the =head1 NAME value.
    my %file_manpage;

    # All defined references.
    my %references;

    sub save_definition ($in_file, $refname, $display_name = $refname) {
        $references{$display_name}{strip_extension($in_file)} = 
          convert_to_href_text($refname);
    }

    sub save_file_manpage ($filename, $manpage) {
        $file_manpage{strip_extension($filename)} = $manpage;
    }

    sub manpages_list {
        return values %file_manpage;
    }

    sub manpage_get {
        return $file_manpage{$_[0]};
    }

    sub references_list {
        keys %references;
    }

    sub reference_get {
        return $references{$_[0]};
    }

    { 
        my $current_file;
        my $current_heading;
        my $save_next_text_as_module_name = 0;

        sub parse_entity ($element, $attrs, @subnodes) {
            if ($element =~ /^head(\d)/) {
                my $level = $1;
                $current_heading = plaintext_of(@subnodes);
                if ($level == 1 && (lc($current_heading) eq 'name')) {
                    $save_next_text_as_module_name = 1;
                } elsif ($level == 2) {
                    save_definition ( $current_file, $current_heading );
                }
            } elsif ($save_next_text_as_module_name && $element =~ /^para$/i ) {
                $save_next_text_as_module_name = 0;
                $current_heading = plaintext_of(@subnodes);
                $current_heading =~ m/^\s*(\S+)/;
                my $firstword = $1;
                save_file_manpage($current_file, $firstword);
            }
        }

        sub parse_document ($parse_file, $element_name, $attrs, @entities) {
            # called with root node of a POD document
            $current_heading = undef;
            $current_file = $parse_file;
            $save_next_text_as_module_name = 0;
            foreach my $ent (@entities) {
                parse_entity (@{$ent});
            }
        }
    }
}

################

# Retrieve plaintext from POD object

sub plaintext_of (@subnodes) {
    my $accreted_text = '';
    foreach my $n (@subnodes) {
	if (!ref $n) {		# string
	    $accreted_text .= $n;
	} else {		# array ref, presumably
	    my @subs = (@{$n});
	    shift @subs; shift @subs;
	    $accreted_text .= plaintext_of(@subs);
	}
    }
    return clean_heading($accreted_text);
}

sub strip_extension ($filename) {
    $filename =~ s/\.\w+$//;  # remove extension
    return $filename;
}

sub convert_to_href_text ($human_text) {
    $human_text =~ s/(\s|\(|=|\[)/-/g;
    $human_text =~ s/([^a-zA-Z0-9_\-*:])//g;
    return $human_text;
}

sub convert_local_path_to_href ($file) {
    $file =~ s{\..+}{}g;
    $file =~ s{/}{::}g;
    return $file;
}

################

sub clean_heading ($original) {
    # Clean headings for index display
    $original =~ s/^\s+//;
    $original =~ s/\smean\?$//;
    $original =~ s/\?$//;
    if ($original =~ m/^((?:(?:who|what|when|where|which|why|how|is|are|a|an|do|does|don't|doesn't|can|not|I|need|to|about|did|my|the|there)\s+|error\s+"|message\s+")+)(.*)$/i) {
        my ($prefix, $main) = ($1, ucfirst($2));
        $main =~ s/[?"]//g;
        # $prefix =~ s/[?"]//g;
        return $main;
    }
    # Nibbling the carrot -> Carrot, nibbling the
    if ($original =~ m/^(\w+ing(?:\s+and\s+\w+ing))\s+(a|an|the|some|any|all|to|from|your)?\b\s*(.*)$/) {
        my ($verb, $qualifier, $remainder) = ($1, $2, $3);
        $qualifier ||= '';
        # print ucfirst("$remainder, $verb $qualifier\n");
        return ucfirst("$remainder, $verb $qualifier");
    }
    # $variable=function_name(...) -> function_name
    if ($original =~ m/^[\$@]\w+\s*=\s*(?:\$\w+\s*->\s*)?(\w+)/) {
        return $1;
    }
    # $variable->function_name(...) -> function_name
    if ($original =~ m/^\$\w+\s*->\s*(\w+)/) {
        return $1;
    }
    # Module::Module->function_name(...) -> function_name
    if ($original =~ m/^\w+(?:::\w+)+\s*->\s*(\w+)/) {
        return $1;
    }
    # function_name($args,...) -> function_name
    if ($original =~ m/^(\w+)\s*\(\s*[\$@%]\w+/) {
        return $1;
    }
    # ($var, $var) = function_name(...) -> function_name
    if ($original =~ m/^\([\$@%][^)]+\)\s*=\s*(?:\$\w+\s*->\s*)?(\w+)/) {
        return $1;
    }
    return $original;
}

################

# Accepts a list of module names.  e.g., "Mojo Mojolicious"
# From this get a list of filenames in the Perl directory
# Create a hash whose keys are all the (*.pm, *.pod) files under those pathnames.
# Give POD files preference: remove any x/y.pm where x/y.pod exists.

use File::Find::Rule;
use Mojo::Path;

my @file_list;

# We are passed a list of things, which can be Perl module names,
# explicit filenames, or explict directories.

foreach my $index_it (@ARGV) { # List of things to index
    my $index_dir;  # Directory for this thing
    my @files;      # Found files for this thing

    if ($index_it =~ m{(/|\.)}) {
        $index_dir = $index_it; # simply add file or directory
    } else {
        my @module_paths = File::Find::Rule->file()->
          name("${index_it}.pod","${index_it}.pm")->in(@INC);
        # Now we have path to the Perl Module or its document.
        my $module_file = $module_paths[0];
        push @files, $module_file;  # The module file itself
        $index_dir = $module_file =~ s/\.\w+$//r;
    }
    if (-d $index_dir) {
        push @files, File::Find::Rule->file()
          ->name( '*.pm', '*.pod' )
            ->in( $index_dir );
    } elsif (-f $index_dir) {
        push @files, $index_dir; # Ah, a plain text file; index it.
    }

    push @file_list, @files;
}

foreach my $parse_file (@file_list) {
    # WL 2016-05-15 This does not seem to parse UTF-8 properly
    my $pod = Pod::Simple::SimpleTree->new->parse_file($parse_file);
    parse_document($parse_file, @{$pod->root});
}

foreach my $r (sort {fc($a) cmp fc($b)} references_list()) {
    my $new = clean_heading($r);
    if ($new ne $r) {
	foreach my $orig_file (keys %{reference_get($r)}) { 
	    save_definition( $orig_file, $r, $new);
	}
    }
}

################

use Mojo::DOM;

my $dom = Mojo::DOM->new( <<ASIMOV );
<!DOCTYPE html>
<html>
  <head>
    <style>
       .main {
         columns: 20em 2;
         -moz-columns: 20em 2;
       };
    </style>
  </head>
  <body>
  </body>
</html>

ASIMOV

$dom->at('head')->append_content('<title>Cross-Reference</title>');

$dom->at('body')->append_content('<h2>Perl Manpage Index</h2>');
$dom->at('body')->append_content(<<42);
<p style="float: right; margin-top: -2em;">
  <small>Generated with <a href="https://github.com/lindleyw/pod-index">W. Lindley's
  Pod Indexer</a></small>
</p>
42

$dom->at('body')->append_content('<div id="coverage"><p id="pod-listing">Covers the following:</p></div>');
$dom->at('body')->append_content('<div id="thumbs"></div>');
$dom->at('body')->append_content('<div id="contents"></div>');
$dom->at('#coverage')->append_content('<dl id="heading-listing"></dl>');

# List of indexed pages

foreach my $m (sort (manpages_list())) {
    my $module_html = qq(<a href="https://metacpan.org/pod/$m">$m</a>);
    if (index($m, '::') < 0) {  # major module heading
        $dom->at('#pod-listing')->append_content('<br />');
        $module_html = "<b>$module_html</b>";
    }
    $dom->at('#pod-listing')->append_content($module_html . ' ');
}
$dom->at('#pod-listing')->append_content(qq(<br />\n<hr />\n));

# Jump-to-thumb tabs

my @headings = sort {fc($a) cmp fc($b)} references_list();
my %thumbs;
for (@headings) {
    $thumbs{uc(substr($_,0,1))}++;
}
$dom->at('#thumbs')->append_content( join(' ', map {qq(<a href="#head_$_">$_</a>) } (sort keys %thumbs)) . "\n");

# Alphabetical list of headings, with thumb tabs

my %heading_words;

foreach my $heading (@headings) {
    $heading = clean_heading($heading);
    my @xref_words = split(/\s+/, $heading);
    my $first = shift @xref_words;
    foreach my $w (@xref_words) {
        push @{$heading_words{$w}}, $heading;
    }
}

foreach my $heading (@headings) {
    my $tab = uc(substr($heading,0,1)); # First character
    my $under_tab = $dom->at("#head_$tab dl");
    if (!defined $under_tab) {
        $dom->at('#contents')
          ->append_content(qq(\n<hr width="50%" />\n<div id="head_$tab" class="main"><h3>$tab</h3><dl></dl></div>\n));
        $under_tab = $dom->at("#head_$tab dl");
    }
    $under_tab->append_content(qq(<dt id="$heading">$heading</dt>));

    my @sources;
    foreach my $orig_file (sort {fc($a) cmp fc($b)} keys %{reference_get($heading)}) { 
	my $manpage = manpage_get($orig_file);
        next unless defined $manpage;
        my $r = reference_get($heading);
	push @sources, qq(<a href="https://metacpan.org/pod/${manpage}#$r->{$orig_file}">$manpage</a>);
    }
    $under_tab->append_content( '<dd>'.join(', ', @sources).'</dd>' );

    my @see_also;
    my @xref_words = split(/\s+/, $heading);
    my $first = shift @xref_words;
    if (reference_get($first) && defined $heading_words{$first}) {
        push @xref_words, @{$heading_words{$first}};
    }
    if (scalar @xref_words) {
        foreach my $xref_word (sort @xref_words) {
            my $reference = reference_get($xref_word) // reference_get(lc($xref_word));
            if (defined $reference) {
                push @see_also, qq(<a href="#$xref_word">$xref_word</a>);
            }
        }
    }
    if (scalar @see_also) {
        $under_tab->append_content( '<dd><i>See also:</i> '.join(', ', @see_also).'</dd>' );
    }

}

print $dom;
