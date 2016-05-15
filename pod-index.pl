#!/usr/env/perl

use Pod::Simple::SimpleTree;

use warnings;
use strict;

use v5.20;
use feature 'signatures';
no warnings 'experimental::signatures';

use Data::Dumper;

# Compare,
#   CPAN::IndexPod
#   Pod::Index

#
# Probably ought to regard X<…> entities although metacpan doesn't create <a> for them.
#

# Original one-liner (sh)
# grep -r head2 . | perl -n -e 'chomp; s/:=head./:/; s{\./}{}; my($fil,$head)=split /:/;$href=$head;$href=~s/^\s//;$href=~s/\s/-/g;$fil=~s{\..+}{}g;$fil=~s{/}{::}g;print "$head: <a href=https://metacpan.org/pod/$fil#$href>$fil</a><br>\n"' | sort | uniq >/tmp/f.html

# Evil global variables

my $current_file;
my $current_heading;

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

# sub convert_to_ 

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

# More evil globals.

# Maps local filename to manpage name.  Based on the =head1 NAME value.
my %file_manpage;

# All defined references.
my %references;

sub save_definition ($in_file, $refname, $display_name = $refname) {
    $references{$display_name}{strip_extension($in_file)} = 
      convert_to_href_text($refname);
}

sub save_file_manpage ($filename, $manpage) {
    $file_manpage{strip_extension($current_file)} = $manpage;
}

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

sub parse_document ($, $, @entities) {
    $current_heading = undef;
    $save_next_text_as_module_name = 0;
    foreach my $ent (@entities) {
	parse_entity (@{$ent});
    }
}

# Accepts a list of module names.  e.g., "Mojo Mojolicious"
# From this get a list of filenames in the Perl directory
# Create a hash whose keys are all the (*.pm, *.pod) files under those pathnames.
# Give POD files preference: remove any x/y.pm where x/y.pod exists.

use File::Find::Rule;
use Mojo::Path;

my @file_list;

foreach my $index_it (@ARGV) {
    # Look for module in 
    my @module_paths = File::Find::Rule->file()->name("${index_it}.pod","${index_it}.pm")->in(@INC);
    # Now we have path to the Perl Module or its document.
    my @files;
    my $module_file = $module_paths[0];
    push @files, $module_file;  # The module file itself

    my $index_dir = $module_file =~ s/\.\w+$//r;
    if (-d $index_dir) {
        # my $index_path = Mojo::Path->new($index_it);
        # my $index_dir = $index_path->to_dir;

        push @files, File::Find::Rule->file()
          ->name( '*.pm', '*.pod' )
            ->in( $index_dir );
    }

    push @file_list, @files;
}

foreach my $parse_file (@file_list) {
    $current_file = $parse_file;
    my $pod = Pod::Simple::SimpleTree->new->parse_file($parse_file);
    parse_document(@{$pod->root});
}

sub clean_heading ($original) {
    # Clean headings for index display
    $original =~ s/^\s+//;
    $original =~ s/\smean\?$//;
    if ($original =~ m/^((?:(?:who|what|when|where|which|why|how|is|are|a|an|do|does|don't|doesn't|can|not|I|need|to|about|did|my|the)\s+|error\s+"|message\s+")+)(.*)$/i) {
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


foreach my $r (sort {fc($a) cmp fc($b)} keys %references) {
    my $new = clean_heading($r);
    if ($new ne $r) {
	foreach my $orig_file (keys %{$references{$r}}) { 
	    save_definition( $orig_file, $r, $new);
	}
    }
}

print "<html><head><title>Cross-reference</title></head><body>\n";

print <<HEAD;
<h2>Perl Manpage Index</h2>
<p class="pod-listing">Covers the following:
HEAD

foreach my $m (sort values %file_manpage) {
    if (index($m, '::') < 0) {
        print "<br />";
    }
    print qq(<a href="https://metacpan.org/pod/$m">$m</a> );
}

print <<HEAD;
</p>
<hr>
HEAD

my @headings = sort {fc($a) cmp fc($b)} keys %references;
my %thumbs;
for (@headings) {
    $thumbs{uc(substr($_,0,1))}++;
}
print join(' ', map {qq(<a href="#head_$_">$_</a>) } (sort keys %thumbs)) . "\n";

my $last_head = '';

my $in_section = 0;

foreach my $r (@headings) {
    if (uc(substr($r,0,1)) ne $last_head) {
        $last_head = uc(substr($r,0,1));
        if ($in_section) {
            print "</dl>\n";
        }
        print qq(<h3 id="head_$last_head">$last_head</h3>\n);
        print "<dl>\n";
        $in_section = 1;
    }
    
    print "  <dt>$r</dt>\n<dd>";
    my @sources;
    foreach my $orig_file (sort {fc($a) cmp fc($b)} keys %{$references{$r}}) { 
	my $manpage = $file_manpage{$orig_file};
	 # my $href = 
	push @sources, qq(<a href="https://metacpan.org/pod/${manpage}#$references{$r}{$orig_file}">$manpage</a>);
    }
    print join(', ', @sources);
    print "</dd>\n";
}
print "</dl>\n";
print "</body></html>\n";

1;
