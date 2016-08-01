cd /home/bill/perl5/perlbrew/perls/perl-5.22.0/lib/site_perl/5.22.0
# Insert a prefix line with the main module name
# Xargs executes the conversion separately for each file
# Substitutes "X" with the filename
echo -e "Toadfarm\n" $(find Toadfarm/ -type f -print) | perl -e 's{/}{::}g; s/\.(.+)$//;' -p | xargs -I X sh -c 'perldoc -u X | pod2pdf --title X --margins 24 --page-size=Letter --output-file=/tmp/X.pdf'
# Perhaps use list under "Documentation Index" and "Plugins" headings to sort by.
pdfunite $(ls /tmp/Toadfarm*pdf | sort) /tmp/Toad.pdf

