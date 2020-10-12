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
    $original =~ s/\smean\?$//;
    $original =~ s/\?$//;
    # How can I blip the blop? -> Blip the blop
    # Why doesn't my socket have a packet? -> Socket have a packet
    # Where are the pockets on the port? -> Pockets on the port
    if ($original =~ m/^((?:(?:who|what|when|where|which|why|how|is|are|did|a|an|the|do|does|don't|doesn't|can|not|I|my|need|to|about|there)\s+|error\s+"|message\s+")+)(.*)$/i) {
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

sub _save_definition ($self, $parser, $attrs, $head1, $text) {
    push @{$self->{sections}{$head1}}, $text;
}

sub _save_file_manpage ($self, $text) {
    $self->{manpage} = $text;
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

sub parse_file ($self, $file) {

    my $save_next;

    $self->{file} = $file;

    my $pod = Pod::Headings->new(
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

            $self->_save_definition ( $parser, $attrs, $parser->{_save_head1}, _clean_heading($plaintext) );

            1;
        },
        Para => sub ($parser, $elem, $attrs, $plaintext) {
            if ($parser->{_save_first_para}) {
                # print " .... text: $plaintext\n";
                $self->$save_next($parser, $elem, $attrs, _clean_heading($plaintext)) if defined $save_next;
                undef $save_next;
            }
            $parser->{_save_first_para} = 0;
            1;
        },
        L => 1,  # Return 0 to drop the plaintext passed to the containing element
    )->parse_file($file);

    1;
}








1;
