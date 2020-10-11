package Pod::References;

use v5.20;
our $VERSION = '0.01';

use Mojo::Base;

### See also, Pod::Index, Pod::Index::Builder
# However, those modules use Pod::Parser (which will be deprecated);
# instead, we should continue to base off Pod::Simple and friends

use Pod::Simple::SimpleTree;

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
