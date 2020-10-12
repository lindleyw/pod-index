package Pod::Definitions;

use v5.20;
use Pod::Headings;
our $VERSION = '0.01';

use feature 'signatures';
no warnings 'experimental::signatures';

#
#
#
sub new ($class, @args) {
    my $self = {@args};
    bless $self, $class;

    return $self;
}

#
# Accessors
#

sub file ($self) { return $self->{file}; }       # Local path to file
sub manpage ($self) { return $self->{manpage}; } # Full name of manpage ('Mojo::Path')
sub module ($self) { return $self->{module}; }   # Module leaf name ('Path')
sub sections ($self) { return $self->{sections}; } # Hash (key=toplevel section) of arrays
                                # of section names

#
# Helpers
#

sub _clean_heading ($original) {
    # Clean headings for index display
    $original =~ s/^\s+//;
    $original =~ s/\s(?:mean|go)\?$//;
    $original =~ s/\?$//;
    # Which versions are supported -> Versions supported
    # How much does... How well is... How many...
    $original =~ s/^(?:(?:what|which|how|many|much|well|is|are|do)\s+)+(\S.*?)?\b(?:is|are|do)\s+/\u\1/i;
    $original =~ s/\s{2,}/ /g;

    # How can I blip the blop? -> Blip the blop
    # Why doesn't my socket have a packet? -> Socket have a packet
    # Where are the pockets on the port? -> Pockets on the port
    if ($original =~ m/^((?:(?:who|what|when|where|which|why|how|is|are|did|a|an|the|do|does|don't|doesn't|can|not|I|my|need|to|about|there)\s+|error\s+"\.*|message\s+"\.*)+)(.*)$/i) {
        my ($prefix, $main) = ($1, ucfirst($2));
        $main =~ s/[?"]//g;
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

#
#
#

sub convert_to_href_text ($human_text) {
    $human_text =~ s/(\s|\(|=|\[)/-/g;
    $human_text =~ s/([^a-zA-Z0-9_\-*:])//g;
    return $human_text;
}

sub _save_definition ($self, $parser, $attrs, $head1, $text) {
    push @{$self->{sections}{$head1}}, {raw => $text,
                                        cooked => _clean_heading($text),
                                        link => $self->manpage().'#'.convert_to_href_text($text),
                                    };
}

sub _save_file_manpage ($self, $text) {
    $self->{manpage} = $text unless defined $self->{manpage};
}

sub _save_file_module_leaf ($self, $text) {
    $self->{module} = $text;
}

sub _save_module_name ($self, $parser, $elem, $attrs, $text) {
    $text =~ m/^\s*(?<module_name>\S+)/;
    my $module_name = $+{module_name};
    $self->_save_file_manpage($module_name);
    # "Mojo::Log" → index under last component: "Log"
    $self->_save_file_module_leaf( (split /::/, $module_name)[-1] );
}

sub _save_version ($self, $parser, $elem, $attrs, $text) {
    $self->{version} = $text;
}

sub _save_see_also ($self, $parser, $elem, $attrs, $text) {
    push @{$self->{see_also}}, $text;
}

sub parse_file ($self, $file, $podname = undef) {

    my $save_next;

    $self->{file} = $file;
    $self->_save_file_manpage($podname) if defined $podname;

    return Pod::Headings->new(
        head1 => sub ($parser, $elem, $attrs, $plaintext) {
            # print " $elem: $plaintext\n";
            $parser->{_save_head1} = $plaintext;
            undef $parser->{_save_head2};
            $parser->{_save_first_para} = 1;

            if (lc($plaintext) eq 'name') {
                $save_next = \&_save_module_name;
            } elsif (lc($plaintext) eq 'version') {
                $save_next = \&_save_version;
            } elsif (lc($plaintext) eq 'see also') {
                $save_next = \&_save_see_also;
            } else {
                undef $save_next;
            }

            1;
        },
        head2 => sub ($parser, $elem, $attrs, $plaintext) {
            # print " $elem: $parser->{_save_head1}: $plaintext\n";
            $parser->{_save_head2} = $plaintext;
            $parser->{_save_first_para} = 1;

            $self->_save_definition ( $parser, $attrs, $parser->{_save_head1}, $plaintext );

            1;
        },
        Para => sub ($parser, $elem, $attrs, $plaintext) {
            if ($parser->{_save_first_para}) {
                # print " .... text: $plaintext\n";
                $self->$save_next($parser, $elem, $attrs, $plaintext) if defined $save_next;
                undef $save_next;
            }
            $parser->{_save_first_para} = 0;
            1;
        },
        L => 1,  # Return 0 to drop the plaintext passed to the containing element
    )->parse_file($file);
}

1;

__END__

=pod

=head1 NAME

Pod::Definitions -- extract main sections and contained definitions from Pod

=head1 SYNOPSIS

    my $pod_file = Pod::Definitions->new();
    $pod_file->parse_file($file_name);

=head1 DESCRIPTION

This class uses L<Pod::Headings> to parse a Pod file and extract the
top-level (head1) headings, and the names of the functions, methods,
events, or such as documented therein.

Heading names, presumed to be written in the English language, are
simplifed for indexing purposes. (See the internal C<_clean_heading()>
routine for the gory details.)  For example:

    What is the Q function?               -> Q function
    How can I blip the blop?              -> Blip the blop
    Why doesn't my socket have a packet?  -> Socket have a packet
    Where are the pockets on the port?    -> Pockets on the port
    I need to reap the zombie             -> Reap the zombie
    What does the error "Disk full" mean? -> Disk full
    What about backwards compatibility?   -> Backwards compatibility
    Reaping the zombie from proctab       -> Zombie, reaping from proctab
    $c = Mojo::Path->new()                -> new

Currently, captialization (other than rewrites of type type shown
above) is mostly left for the caller to handle.

=head1 METHODS

=head2 new

Creates a new object of type Pod::Definitions

=head2 parse_file ($filename)

Parse a podfile, or Perl source file. Returns the Pod::Headings
object, which, as a subclass of Pod::Simple, may give various useful
information about the parsed document (e.g., the line_count() or
pod_para_count() methods, or the source_dead() method which will be
true if the Pod::Simple parser successfully read, and came to the end
of, a document).

=head2 file

Local path to file as passed to parse_file

=head2 manpage

Full name of manpage (e.g., 'Mojo::Path').

=head2 module

Module leaf name (e.g., 'Path')

=head2 sections

Hash (with the key being the toplevel section, e.g., "FUNCTIONS") of
arrays of section names, or undef if no sections (other than the
standard NAME and SEE ALSO) were given in the Pod file

=head1 SEE ALSO

L<Pod::Simple>, L<Pod::Headings>

=head1 SUPPORT

This module is managed in an open GitHub repository,
(( link here )) Feel free to fork and contribute, or to clone and send patches.

=head1 AUTHOR

This module was written and is maintained by William Lindley
<wlindley@cpan.org>.

=cut
