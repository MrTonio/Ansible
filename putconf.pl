#!/usr/bin/perl
 
use strict;
use warnings;
use Expect;
use Term::ReadKey;

my $version = "0.5"; 
my $host   = "S-ansible";
my $domain = "gsb.lan";
my $ip     = "172.16.0.9";
my $mask   = "255.255.255.0";
my $gw     = "172.16.0.254";
my $dns1   = "172.16.0.6";
my $dns2   = "172.16.0.1";
# les paquets a installer 
my $maj = "aptitude update && aptitude upgrade -y";
my $packages = "git curl vim python-dev python-yaml python-paramiko python-jinja2 git make expectk";

sub putconf {
        my ($file, $comment, $msg)= @_;
        print "Generation du fichier $file ...\n";
        my $dat = `date`;
        open (FILE, ">$file") or die "Erreur ecriture fichier $file : $! \n";
        print FILE "$comment $version - putconf - $dat"  if ($comment);
        print FILE $msg;
        close FILE;
};

print "Recherche et installation des mises à jours\n" ;
system "$maj" if ($packages);

print "Installation des prérequis\n";
system "aptitude install $packages -y";

print "Création des dossiers nécessaire\n";
system "mkdir /etc/ansible && mkdir /etc/playbook  && mkdir /opt/shinken && mkdir /opt/shinken/hosts && mkdir /root/scripts" ; 

print "Installation d'ansible\n" ;
system "cd ~ && git clone https://github.com/ansible/ansible.git";
system "cd ansible && make && make install";

# Key gen
print "Génération des clefs privée\n" ;

putconf ("/root/serverlist", "#",
"
#!/usr/bin/perl

my \$host = \"r-ext\" ;
my \$host = \"r-int\" ;
my \$host = \"s-mon\" ;
my \$host = \"s-proxy\" ;
my \$host = \"s-appli\" ;
my \$host = \"s-infra\" ;
");

system "chmod +x /root/serverlist"; 
system "ssh-keygen -t rsa -N \"\" -f ~/.ssh/id_rsa";

print "Mot de passe : ";
ReadMode('noecho');
my $password = ReadLine(0);
 
chomp $password;
ReadMode('normal');
 
open('FH', "./serverlist") or die "can't open ./serverlist: $!";
 
while (defined (my $host = <FH>)) {
  chomp $host;
 
  if(system("ssh -o BatchMode=yes -o ConnectTimeout=5 $host uptime 2>&1 | grep -q average") != "0")
  {
    my $cmd = "ssh-copy-id -i $host";
 
    print "Now copying key to $host";
 
    my $timeout = '10';
    my $ex = Expect->spawn($cmd) or die "Cannot spawn $cmd\n";
 
    $ex->expect($timeout, ["[pP]assword:"]);
    $ex->send("$password\n");
    $ex->soft_close();
  } else { print "Key already deployed on $host\n" }
}
close('FH');

# Dépot template shinken (.j2) 
system "git clone http://github.com/amadieu-romain/e4.shinken.git";

# Configuration générél
putconf("/etc/hostname", "", "$host\n");
 
putconf ("/etc/hosts", "#",
"127.0.0.1      localhost.localdomain localhost
127.0.1.1       $host
$ip     $host.$domain $host
 
# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
");
 
putconf ("/etc/network/interfaces", "#",
"
# The loopback network interface
auto lo
iface lo inet loopback
 
# The primary network interface
allow-hotplug eth0
iface eth0 inet static
        address $ip
        netmask $mask
        gateway $gw
	
iface eth1 inet dhcp
");
 
putconf ("/etc/resolv.conf","#",
"domain $domain
nameserver $dns1
");
 
putconf("/etc/ansible/hosts", "#",
"
 [adm]
s-infra

[serveurs]
s-mon
s-proxy

[routeurs]
r-ext
r-int

[shinken]
s-mon
"
);

putconf("/etc/playbook/install-mon.yml", "#",
"
---
- hosts: shinken
  tasks:

  - name: update a server
    apt: update_cache=yes
  - name: upgrade a server
    apt: upgrade=full

  - name: Installation des prérequis
    apt: pkg=curl state=installed

# - name: Export du proxy
#   shell: export http_proxy=http://10.121.32.69:8080 && https_proxy=https://10.121.32.69:8080

  - name: Installation de Shinken
    shell: curl -L http://install.shinken-monitoring.org | /bin/bash

  - name: Installation des plugins 
    shell: cd /usr/local/shinken && ./install -p manubulon && ./install -p nagios-plugins

  - include: deployemet.yml
"
);

putconf("/etc/playbook/deployement.yml", "#",
"
  - name: Transfert des fichiers hosts
    shell: scp s-ansible:/opt/shinken/hosts/hosts.tar.gz /usr/local/shinken/etc/hosts

  - name: Extraction du tar.gz 
    shell: tar -xvzf /usr/local/shinken/etc/hosts/hosts.tar.gz && mkdir /usr/local/shinken/etc/hosts/serveurs && mkdir /usr/local/shinken/etc/hosts/routeurs

  - name: Ajout des commandes pour NsClient ++ --> fichier commands.cfg
    template: src=/opt/shinken/commands.cfg.j2 dest=/usr/local/shinken/etc/commands.cfg

  - name: Ajout dU fichier hostgroups.cfg
    template: src=/opt/shinken/hostgroups.cfg.j2 dest=/usr/local/shinken/etc/hostgroups.cfg  

  - name: Ajout du fichier services.cfg
    template: src=/opt/shinken/s-win.cfg.j2 dest=/usr/local/shinken/etc/services/s-win.cfg

  - name: Ajout du fichier de dépendances 
    template: src=/opt/shinken/dependencies.cfg.j2 dest=/usr/local/shinken/etc/dependencies.cfg
"
);


# Début script
putconf("/root/scripts/gene.pl", "#",
"
\#!/usr/bin/perl

use strict;
use warnings;

my \$version = 0.1 ;
my \$fichier = shift \@ARGV;

sub putconf {
        my (\$file, \$msg)= \@_;
        print \"Generation du fichier \$file ...\n\";
        my \$dat = \`date\`;
        open (FILE, \">\$file\") or die \"Erreur ecriture fichier \$file : \$! \n\";
        print FILE \"### \$version - putconf - \$dat\" if (\$file ne \"/etc/hostname\") ;
        print FILE \$msg;
        close FILE;
};

if (!\$fichier) {
die \"usage : cgene <fichier>\n\";
}

open (FILE2,\"<\",\"\$fichier\") or die \"gene: erreur ouverture \$fichier \$!\n\" ;
while (\<FILE2\>) {
        chomp ;
        next if (!\$_);
        my(\$host,\$alias,\$ip,\$template) = split \/\:\/;
        print \"\$host \$alias\n\" ;
        next ;

putconf (\"/opt/shinken/hosts/\$host.conf\",
\"define host{
use \$template
host_name \$host
alias Windows \$alias
address \$ip
}
\"
);

};

system(\"tar -zcvf /opt/shinken/hosts/hosts.tar.gz /opt/shinken/hosts/\") ; 
" 
);
# Fin script 

putconf("/root/scripts/hostlist.txt", "#",
"
s-infra:infra:172.16.0.1:linux
s-proxy:proxy:172.16.0.2:linux
s-appli:infra:172.16.0.3:linux
s-win:win:172.16.0.6:linux
r-int:int:192.168.200.254:linux
r-ext:ext:192.168.200.253:linux
s-ansible:ansible:172.16.0.1:linux
s-mon:shinken:127.0.0.1:linux
"
);

putconf("/opt/shinken/s-win.cfg.j2", "#",
"
## In this directory you can put all your specific service
# definitions

define service {
    use generic-service
    #host_name s-win
    hostgroup_name windows-server
    service_description Espace disponnible C:
    check_command check_nt_diskc!80,!90
}


define service{
    use generic-service
    #host_name xxxx
    hostgroup_name windows-server
    service_description Charge CPU
    check_command check_nt_cpuload!80,!90
}

define service {
    use generic-service
    #host_name xxxx
    hostgroup_name windows-server
    service_description Ram
    check_command check_nt_memuse!70,!90
}

define service{
    use generic-service
    #host_name xxxx
    hostgroup_name windows-server
    service_description Etat nscp
    check_command check_nt_service!nscp

"
);
