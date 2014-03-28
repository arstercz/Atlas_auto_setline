#!/usr/bin/env perl
=pod

=head1 NAME

atlas_auto_setline: a tool for automatic offline/online unusable slave node in Atlas open source software.

=head1 SYNOPSIS

Usage: atlas_auto_setline [OPTION...]

       perl atlas_auto_setline.pl --conf=db.conf --verbose --setline

atlas_auto_setline can help you monit the Atlas middleware, online/offline the slave node when slave either error or ok.

=head1 RISKS
 Use the slave Seconds_Behind_Master value to determine whether offline or not, this maybe not accurately.

 Offline function connect to Atlas admin interface to select the slave id which should be off.

 Slave ip address in db.conf file should be the ip address that in slave node, not atlas node address.

 user/pass should be the same either in slave or atlas.

=cut

use strict;
use warnings;
use Getopt::Long;
use DBI;
use DBD::mysql;
use Data::Dumper;
use POSIX qw(strftime);
use Config::Auto;

my $help     = 0;
my $conf     = "db.conf";
my $setline  = 0;
my $verbose  = 0;
my $version  = 0;

my $VER = '0.0.1';

GetOptions(
   "conf=s"     => \$conf,
   "help!"      => \$help,
   "setline!"   => \$setline,
   "verbose!"   => \$verbose,
   "version!"   => \$version,
);

sub usage {
   my $name = shift;
   system("perldoc $name");
   exit 0;
}


sub mysql_setup {
  my $command = `which mysql`;
  chomp($command);
  if (! -e $command) {
      print "Unable to fine mysql command in your \$PATH.\n";
      exit 1;
  }
}



sub get_slave_status {
   my ($host, $port, $user,  $pass) = @_;
   my $cur_time = strftime( "%Y-%m-%d %H:%M:%S", localtime(time) );

   # slave status.
   my %slave;
   my @slave_info = `mysql -h $host -P $port -u$user -p$pass -Bse 'show slave status\\G'`;
   foreach my $line (@slave_info) {
         next if $line =~ /1\. row/;
         $line =~ /([a-zA-Z_]*):\s(.*)/;
         $slave{$1} = $2;
   }
   print " +---$cur_time, $host, Slave_IO_Running: $slave{'Slave_IO_Running'}, Slave_SQL_Running: $slave{'Slave_SQL_Running'}, Seconds_Behind_Master: $slave{'Seconds_Behind_Master'}\n" if $verbose;
   if ($slave{'Slave_IO_Running'} eq 'Yes' and $slave{'Slave_SQL_Running'} eq 'Yes' and $slave{'Seconds_Behind_Master'} + 0 < 30) {
      return 'OK';
   } else {
      return 'ERR';
   }
}

# +-------------+------------------+-------+------+
# | backend_ndx | address          | state | type |
# +-------------+------------------+-------+------+
# |           1 | 10.0.23.200:3306 | up    | rw   |
# |           2 | 10.0.23.200:3306 | up    | ro   |
# |           3 | 10.0.23.205:3306 | up    | ro   |
# +-------------+------------------+-------+------+
sub atlas_ends {
  my ($host, $port, $user,  $pass, $slave_host) = @_;
  my @atlas_state = `mysql -h $host -P $port -u$user -p$pass -Bse 'select * from backends'`;
  my %admin_state;
  foreach my $line (@atlas_state) {
      next if $line !~ /$slave_host/;
      $line =~ /(\d+)\s+(.+)\s+(.+)\s+(.+)/;
      $admin_state{$port}{'id'} = $1;
      $admin_state{$port}{'port'} = $port;
      $admin_state{$port}{'state'} = $3;
      $admin_state{$port}{'type'}  = $4;
  }
  return \%admin_state;
}

sub atlas_setline {
   my ($tag,$host, $port, $user, $pass, $id) = @_;
   my $cur_time    = strftime( "%Y-%m-%d %H:%M:%S", localtime(time) );
   eval {
     if ($tag eq 'offline') {
        my @off = `mysql -h $host -P $port -u$user -p$pass -e "SET OFFLINE $id"`;
     }

     if ($tag eq 'online') {
        my @on  = `mysql -h $host -P $port -u$user -p$pass -e "SET ONLINE $id"`;
     }
   };
   if ($@) {
     print " +-- $cur_time SET $tag ERR :$@\n"
   } else {
     print " +-- $cur_time OK SET $tag node $host:$port\n" ;
   }
}

if ($help) {
    usage($0); 
}

if ($version) {
    print "Current version : $VER\n";
    exit 0;
}

$conf = "./$conf" if $conf && $conf =~ /^[^\/]/;
my $config   = Config::Auto::parse("$conf");
my $port_ref = $config->{'atlas_port'};

mysql_setup;

my $state = get_slave_status($config->{'slave_host'}, $config->{'slave_port'}, $config->{'slave_user'}, $config->{'slave_pass'});

for my $atlas_port (@$port_ref) {
      my $atlas_info = atlas_ends($config->{'atlas_host'}, $atlas_port, $config->{'atlas_user'}, $config->{'atlas_pass'}, $config->{'slave_host'});
      #set offline when slave has error but atlas is ok.
      if ( $state eq 'ERR' and $atlas_info->{$atlas_port}->{'port'} + 0 == $atlas_port and $atlas_info->{$atlas_port}->{'state'} eq 'up' and $atlas_info->{$atlas_port}->{'type'} eq 'ro') {
         atlas_setline('offline', $config->{'atlas_host'}, $atlas_port, $config->{'atlas_user'}, $config->{'atlas_pass'}, $atlas_info->{$atlas_port}->{'id'}) if $setline;
      }

      #set online when slave is ok but atlas is error. 
      if ( $state eq 'OK' and $atlas_info->{$atlas_port}->{'port'} + 0 == $atlas_port and $atlas_info->{$atlas_port}->{'state'} eq 'offline' and $atlas_info->{$atlas_port}->{'type'} eq 'ro')   {
         atlas_setline('online', $config->{'atlas_host'}, $atlas_port, $config->{'atlas_user'}, $config->{'atlas_pass'}, $atlas_info->{$atlas_port}->{'id'}) if $setline;
      }
}


=pod

=head1 DESCRIPTION

automatic set online/offline when slave node has error or delay.

=head1 OPTIONS

=over

=item --conf

type: var:value

Specifies slave and atlas source configuration:
  virtual ip address is recommonded.
  eg:
     #slave host and atlas admin host info.
      slave_host:10.0.23.205
      slave_port:3306
      slave_user:root
      slave_pass:a9vg_com-3306
      atlas_host:10.0.23.201
      atlas_port:5011, 5012, 5013
      atlas_user:admin
      atlas_pass:xxxxxx

=item --setline

Enable set online/offline mode

=item --verbose

type: integer

Whether print slave check info or not.

=item --version

type: integer

Version of this script.

=back

=head1 SYSTEM REQUIREMENTS

DBI, DBD::mysql, Config::Auto, Getopt::Long


=head1 BUGS

Does not support mutiple slave nodes, you can instead use the folling command:
for x in db1.conf db2.conf .. dbn.conf;do perl atlas_auto_setline.pl --conf=$x --verbose --setline

=head1 SEE ALSO

related tasks

=head1 AUTHOR

zhe.chen <chenzhe07@gmail.com>

=head1 CHANGELOG

v0.0.1 initial version

=cut
