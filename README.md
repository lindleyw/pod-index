# pod-index
Create a concordance style index for a group of Perl modules

Usage:

    $ perl pod-index LIST_OF_MODULE_NAMES > list_of_module_names.html

For example:

    $ perl pod-index Mojo Mojolicious > Mojo.html

finds Mojo.pm and Mojolicious.pm in @INC, and indexes them and all modules under Mojo::* and Mojolicious::*

An example including Mojo and Mojolicious may be seen [here](http://wlindley.com/mojo/Mojo.html).


Prereqs

Mojolicious
List::MoreUtils
File::Find::Rule
