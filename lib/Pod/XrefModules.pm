package Pod::XrefModules {

    use v5.20;
    use strict;
    use warnings;

    use feature 'signatures';
    no warnings 'experimental::signatures';

    use Pod::Definitions;
    use Pod::Simple::Search;

    #
    # Instantiate
    #
    sub new ($class, @args) {
        my $self = {podfiles => {}, pods => {},
                    references => {}, see => {}, see_also => {},
                    @args};
        bless $self, $class;

        return $self;
    }

    #
    # Accessors
    #
    sub pods ($self) { return $self->{pods}; }   # returns { pod_name => content } hash
    sub podfiles ($self) { return $self->{podfiles}; } # returns { pod_name => filename } hash
    sub references ($self) { return $self->{references}; }
    sub see ($self) { return $self->{see}; }
    sub see_also ($self) { return $self->{see_also}; }

    # Accepts a list of module names, as globs to be passed to
    # Pod::Simple::Search.  If any item in the list (e.g., 'Mojo')
    # does not contain any wildcards ('*' or '?'), that item will also
    # be understood to include Pods in that tree (e.g., the glob
    # 'Mojo::*').  An item can also be an explicit filename.

    sub select ($self, @file_list) {
        
        my $pods = {};
        foreach my $parse_file (@file_list) {
            # TODO: 2020-10-11 Verify operation with UTF-8 pods.
            if ($parse_file =~ /\./) {                   # Looks like a filename, store verbatim
                $pods = { %{$pods}, {$parse_file => $parse_file} };
            } else {
                # Treat argument as a glob
                my $search = Pod::Simple::Search->new()->limit_glob($parse_file);
                my ($name2path, $path2name) = $search->survey();
                $pods = { %{$pods}, %{$name2path} };
                if ($parse_file !~ /[*?]/) { # Without explicit glob wildcards, default also to scanning ::*
                    $search = Pod::Simple::Search->new()->limit_glob($parse_file . '::*');
                    ($name2path, $path2name) = $search->survey();
                    $pods = { %{$pods}, %{$name2path} };
                }
            }
        }
        $self->{podfiles} = $pods;
        return $self;
    }
    
    #
    # Parses a single pod file and returns the Definitions within it
    #
    sub _parse_file ($self, $filename, $podname = undef) {
        my $pod_file = Pod::Definitions->new();
        $pod_file->parse_file($filename, $podname);
        return $pod_file;
    }

    #
    # Parses all selected files
    #
    sub parse ($self) {
        foreach my $f (keys %{$self->{podfiles}}) {
            my $pod = $self->_parse_file( $self->{podfiles}{$f}, $f );
            if ($f =~ /\./) {  # Looks like a filename; use the detected module name instead
                $f = $pod->manpage();
            }
            $self->{pods}{$f} = $pod;

            #
            # Create main reference entries for the items in each pod
            #
            if ( defined $pod->sections() ) {
                foreach my $section (keys %{$pod->sections()}) {
                    foreach my $definition (@{$pod->sections->{$section}}) {
                        push @{$self->{references}->{$definition->{cooked}}}, $definition;
                        # Each main key in the references (e.g., "FUNCTIONS")
                        # should generate a "see..." entry for its entries:
                        push @{$self->{see}->{$section}{$definition->{cooked}}}, $definition;
                    }
                }
            }
        }

        #
        # Additionally, for entries that look like:
        #
        #    insert_thing_here
        #
        # 'thing' and 'here' will each obtain a "See also" to
        # insert_thing_here, assuming 'thing' and 'here' are already main
        # entries.
        #
        foreach my $heading (keys %{$self->{references}}) {
            my @subwords = split ( '_', $heading );
            next unless scalar @subwords > 1;
            shift @subwords;  # Ignore first word
            foreach my $subword ( @subwords ) {
                if (exists $self->{references}->{$subword}) {
                    push @{$self->{see_also}->{$subword}}, @{$self->{references}->{$heading}};
                }
            }
        }

        # NOT_DONE:
        # Alternately, the above may benefit from "See also" to "thing" and
        # "here" if those words appear as main entries in the cross-reference.
        #
        
        #
        # Furthermore, add cross-references ("See...") as follows:
        #
        #    Searching in sorted lists     -> Sorted lists, searching in
        #    Counting and calculation      -> Calculation, counting and
        #    Operations on sorted lists    -> Sorted lists, operations on
        #    Treatment of an empty list    -> Empty list, treatment of
        #    Help with a concrete version  -> Concrete version, help with
        #
        
        foreach my $heading (keys %{$self->{references}}) {
            my $raw = $heading;                      # Cook the heading below
            $heading =~ s/\buse\s+case\b/use-case/;  # special case for "use" as an adjective
            $heading =~ s/\s+with\s+this\s*\z//;     # ignore "...with this" at end
            $heading =~ s/,.+\z//;                   # Ignore anything after a comma
            $heading =~ s/\w+ing\s+to//g;            # ignore, e.g., "trying to" 
            # 'la' here to capture 'a la'
            if ($heading =~ /^(.+?)((?:\s+(?:what|how|is|are|in|on|of|with|through|thru|a|an|the|it|I|I'm|la|can|do|use|using|format|way|so)\b)+)\s+(.+)\z/i) {
                my ($leading_words, $modifying_words, $keywords) = ($1, $2, $3);
                my $cooked = "$keywords, $leading_words$modifying_words";
                my @matched;
                foreach my $check_key (split /\s+/, $keywords) {
                    next if $check_key =~ /\b(:?to|in|of)\b/;  # Ignore prepositions, etc.
                    $check_key =~ s/[,.]//g;
                    # print "  [$check_key]";
                    if (exists $self->{references}->{$check_key}) {
                        push @matched, $check_key;
                    } elsif (exists $self->{references}->{lc($check_key)}) {
                        push @matched, lc($check_key);
                    }
                }
                # If none of the above keywords matched an existing entry, use the cooked text.
                push @matched, $cooked unless (scalar @matched);
                foreach my $m (@matched) {
                    push @{$self->{see}->{$m}{$raw}}, @{$self->{references}->{$raw}};
                }
            }
        }

        #
        # Merge the See and See-Also tables into the main references entries
        #
        foreach my $source (keys %{$self->{see}}) {
            foreach my $heading (keys %{$self->{see}->{$source}}) {
                my @see_links = @{$self->{see}->{$source}{$heading}};
                my @add_links;
                foreach my $l (@see_links) {
                    push @add_links, { %{$l}, type => 'see' };
                }
                push @{$self->{references}->{$source}}, @add_links;
            }
        }

        foreach my $source (keys %{$self->{see_also}}) {
            my @links = @{$self->{see_also}->{$source}};
            my @add_links;
            foreach my $l (@links) {
                push @add_links, { %{$l}, type => 'see-also' };
            }
            push @{$self->{references}->{$source}}, @add_links;
        }

        #
        # TODO:
        #
        # If Pod::Definitions is updated to save links within the L<> elements
        # in the See Also sections, and if the cross-references generated here
        # are maintained in a database, it might be useful to add a main entry
        # for each module name, with "See Also" links either as given (in the
        # case of L<> pointing to a website) or internally to whatever website
        # is hosting these cross-references (being mindful not to create links
        # to xref documents which do not exist).
        #


        return $self;

    }

}


1;

__END__

