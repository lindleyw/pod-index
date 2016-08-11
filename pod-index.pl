#!/usr/bin/env perl

use Pod::Simple::SimpleTree;

use warnings;
use strict;

use v5.20;
use feature 'signatures';
no warnings 'experimental::signatures';

use Data::Dumper;

use List::MoreUtils qw(uniq);

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
    my %file_version;

    # All defined references.
    my %references;
    my %ref_under_header;

    sub save_definition ($in_file, $main_heading, $refname, $display_name = $refname) {
        # print STDERR "   $main_heading  $refname $in_file ($display_name)\n"
        #   if defined $main_heading;
        if (defined $main_heading) {
            $ref_under_header{$main_heading =~ s/(?:(\w)(\w+))/\u$1\L$2/gr}{$display_name} =
              convert_to_href_text($refname);
        }
        $references{$display_name}{strip_extension($in_file)} = 
          convert_to_href_text($refname);
    }

    sub save_file_manpage ($filename, $manpage) {
        $file_manpage{strip_extension($filename)} = $manpage;
    }

    sub save_file_version ($filename, $version) {
        $file_version{strip_extension($filename)} = $version;
    }

    sub manpages_list {
        return values %file_manpage;
    }

    sub manpage_get {
        return $file_manpage{$_[0]};
    }

    sub version_get {
        while (my ($file, $name) = each %file_manpage) {
            return $file_version{$file} if ($name eq $_[0]);
        }
    }

    sub references_list {
        keys %references;
    }

    sub reference_get {
        return $references{$_[0]};
    }

    sub ref_under_header_list {
        return keys %ref_under_header;
    }

    sub ref_under_header_get {
        return $ref_under_header{$_[0]};
    }

    { 
        my $current_file;
        my $current_heading;
        my $current_h1;
        my $save_next_text_as_module_name = 0;
        my $save_next_text_as;

        sub parse_entity ($element, $attrs, @subnodes) {
            if ($element =~ /^head(\d)/) {
                my $level = $1;
                my $h_text = plaintext_of(@subnodes);
                if ($level == 1) {
                    $current_h1 = $h_text;
                    if (lc($current_h1) eq 'name') {
                        $save_next_text_as = 'module_name';
                    } elsif (lc($current_h1) eq 'version') {
                        $save_next_text_as = 'version';
                    }
                } elsif ($level == 2) {
                    $current_heading = $h_text;
                    save_definition ( $current_file, $current_h1, $current_heading );
                }
            } elsif (defined $save_next_text_as && $element =~ /^para$/i ) {
                if ($save_next_text_as eq 'module_name') {
                    $current_heading = plaintext_of(@subnodes);
                    $current_heading =~ m/^\s*(\S+)/;
                    my $firstword = $1;
                    save_file_manpage($current_file, $firstword);
                    # "Mojo::Log" → index under last component: "Log"
                    save_definition ( $current_file, $current_h1, 
                                      (split /::/, $firstword)[-1] );
                } elsif ($save_next_text_as eq 'version') {
                    my $version = plaintext_of(@subnodes);
                    $version =~ s/version//i;
                    $version =~ s/\s+//g;
                    save_file_version($current_file, $version);
                }
                undef $save_next_text_as;
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
	    save_definition( $orig_file, undef, $r, $new);
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
$dom->at('body')->append_content(<<ASIMOV);
<p style="float: right; margin-top: -2em;">
  <small>Generated with <a href="https://github.com/lindleyw/pod-index">W. Lindley's
  Pod Indexer</a></small>
</p>
ASIMOV

$dom->at('body')->append_content('<div id="coverage"><p id="pod-listing">Covers the following:</p></div>');
$dom->at('body')->append_content('<div id="thumbs"></div>');
$dom->at('body')->append_content('<div id="contents"></div>');
$dom->at('body')->append_content('<div id="sections"></div>');
$dom->at('#coverage')->append_content('<dl id="heading-listing"></dl>');

# List of pages to be indexed

foreach my $m (sort (manpages_list())) {
    my $module_html = qq(<a href="https://metacpan.org/pod/$m">$m</a>);
    if (index($m, '::') < 0) {  # major module heading
        $dom->at('#pod-listing')->append_content('<br />');
        $module_html = "<b>$module_html</b>";
        my $version = version_get($m);
        $module_html .= " <small>(v$version)</small>" if defined $version;
    }
    $dom->at('#pod-listing')->append_content($module_html . ' ');
}
$dom->at('#pod-listing')->append_content(qq(<br />\n<hr />\n));

# Jump-to-thumb tabs

my @headings = uniq sort {fc($a) cmp fc($b)} (references_list(), ref_under_header_list());
my %thumbs;
for (@headings) {
    $thumbs{uc(substr($_,0,1))}++;
}
$dom->at('#thumbs')->append_content( join(' ', map {qq(<a href="#head_$_">$_</a>) } (sort keys %thumbs)) . "\n");

# Alphabetical list of headings, with thumb tabs

my %heading_words;

foreach my $heading (@headings) {
    $heading = clean_heading($heading);
    my @xref_words = split(/(?:\s|_)+/, $heading);
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
    if (defined reference_get($heading)) {
        foreach my $orig_file (sort {fc($a) cmp fc($b)} keys %{reference_get($heading)}) {
            my $manpage = manpage_get($orig_file);
            next unless defined $manpage;
            my $r = reference_get($heading);
            push @sources, qq(<a href="https://metacpan.org/pod/${manpage}#$r->{$orig_file}">$manpage</a>);
        }
        $under_tab->append_content( '<dd>'.join(', ', @sources).'</dd>' );
    }

    my @see_also;
    my @xref_words = split(/\s+/, $heading);
    my $first = shift @xref_words;
    if (reference_get($first) && defined $heading_words{$first}) {
        push @xref_words, @{$heading_words{$first}};
    }
    if (scalar @xref_words) {
        foreach my $xref_word (sort @xref_words) {
            REFCAP:
            foreach ($xref_word, lc($xref_word), uc($xref_word)) {
                my $reference = reference_get($_);
                if (defined $reference) {
                    push @see_also, qq(<a href="#$_">$xref_word</a>);
                    last REFCAP;
                }
            }
        }
    }

    my $items = ref_under_header_get($heading);
    if (defined $items) {
        my %items = %{$items};
        my @subheads;
        foreach my $subhead (sort {fc($::a) cmp fc($b)} (keys %items)) {
            push @see_also, qq(<a href="#$subhead">$subhead</a>);
        }
    }

    if (scalar @see_also) {
        $under_tab->append_content( '<dd><i>See also:</i> '.join(', ', @see_also).'</dd>' );
    }

}

print $dom;
