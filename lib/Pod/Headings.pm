package Pod::Headings;

use v5.20;
use Pod::Simple;
our @ISA = qw(Pod::Simple);
our $VERSION = '0.01';

use feature 'signatures';
no warnings 'experimental::signatures';

#
# Can pass a list of handlers to new()
#
sub new ($class, @args) {
    my $self = $class->SUPER::new();
    $self->{handlers} = {@args}; # if scalar @args;
    return $self;
}

## NOTE: Does not handle nested elements.

sub _handle_element_start ($parser, $element_name, $attr_hash_r) {
    # print " ( $element_name ) ";
    return unless defined $parser->{handlers}{$element_name};
    $parser->{_heading_save} = $element_name;
    $parser->{_save_text} = undef;
    $parser->{_save_attrs} = $attr_hash_r;
}

sub _handle_element_end ($parser, $element_name, $attr_hash_r = undef) {
    return unless $element_name eq $parser->{_heading_save};
    if (ref $parser->{handlers}{$element_name} eq 'CODE') {
        $parser->{handlers}{$element_name}->($parser, $element_name, $parser->{_save_attrs}, $parser->{_save_text});
    }
}

sub _handle_text ($parser, $text) {
    # print " [$text]";
    $parser->{_save_text} .= $text if defined $parser->{_heading_save};
}

# TODO
# head2 needs to call a handler with the text of its containing head1.




1;

__END__

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
                    } elsif (lc($current_h1) eq 'see also') {
                        $save_next_text_as = 'see_also';
                    }
                    else { print STDERR " --- $current_h1\n"; }
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
                } elsif ($save_next_text_as eq 'see_also') {
                    save_see_also($current_file, @subnodes);
                    $DB::single = 1;
                    print "x";
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


sub xxxxxxx {
    my $pod = Pod::Simple::SimpleTree->new->parse_file($parse_file);
    parse_document($parse_file, @{$pod->root});

}



1;

__END__
