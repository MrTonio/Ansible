#!/usr/bin/perl

use strict;
use warnings;

my $version = 0.1 ;
my $fichier = shift @ARGV;

sub putconf {
        my ($file, $msg)= @_;
        print "Generation du fichier $file ...\n";
        my $dat = `date`;
        open (FILE, ">$file") or die "Erreur ecriture fichier $file : $! \n";
        print FILE "### $version - putconf - $dat" if ($file ne "/etc/hostname") ;
        print FILE $msg;
        close FILE;
};

if (!$fichier) {
die "usage : creatusr <fichier>\n";
}

open (FILE2,"<","$fichier") or die "gene: erreur ouverture $fichier $!\n" ;
while (<FILE2>) {
	chomp ;
	next if (!$_);
	my($host,$alias,$ip,$template) = split /:/;
	print "$host $alias\n" ;
	next ;

putconf ("/opt/shinken/hosts/$host.conf",
"define host{
use $template
host_name $host
alias Windows $alias
address $ip
}
"
);

};

system("tar -zcvf /opt/shinken/hosts/hosts.tar.gz /opt/shinken/hosts/") ; 