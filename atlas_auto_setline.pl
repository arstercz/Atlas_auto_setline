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
my $threshold= 30;
my $interval = 10;

my $VER = '0.0.2';

GetOptions(
   "conf=s"     => \$conf,
   "help!"      => \$help,
   "setline!"   => \$setline,
   "verbose!"   => \$verbose,
   "version!"   => \$version,
   "threshold=i"=> \$threshold,
   "interval=i" => \$interval,
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
   my ($host, $port, $user,  $pass, $threshold) = @_;
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
   if ($slave{'Slave_IO_Running'} eq 'Yes' and $slave{'Slave_SQL_Running'} eq 'Yes' and $slave{'Seconds_Behind_Master'} + 0 < $threshold) {
      return 'OK';
   } else {
      return 'ERR';
   }
}


#+-------------+-------------------+-------+------+
#| backend_ndx | address           | state | type |
#+-------------+-------------------+-------+------+
#|           1 | 172.30.0.153:3306 | up    | rw   |
#|           2 | 172.30.0.153:3306 | up    | ro   |
#|           3 | 172.30.0.154:3306 | up    | ro   |
#|           4 | 172.30.0.133:3306 | up    | ro   |
#+-------------+-------------------+-------+------+
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
   my ($tag,$slavehost, $atlashost, $port, $user, $pass, $id) = @_;
   my $cur_time    = strftime( "%Y-%m-%d %H:%M:%S", localtime(time) );
   eval {
     if ($tag eq 'offline') {
        my @off = `mysql -h $atlashost -P $port -u$user -p$pass -e "SET OFFLINE $id"`;
     }

     if ($tag eq 'online') {
        my @on  = `mysql -h $atlashost -P $port -u$user -p$pass -e "SET ONLINE $id"`;
     }
   };
   if ($@) {
     print " +-- $cur_time SET $tag ERR :$@\n"
     send_msg("$cur_time SET $tag ERR");
   } else {
     print " +-- $cur_time OK SET $tag node $slavehost:$port\n" ;
     send_msg("$cur_time OK SET $tag node $slavehost:$port");
   }
}

#SIG{'INT'} and SIG{'TERM'} should be ignored when do set online/offline progress.
sub catch_sig {
    my $signame = shift;
    local $SIG{$signame} = 'IGNORE' if $signame eq 'INT' or $signame eq 'TERM';
    our $halt = 1;
    print STDOUT "+-- signal $signame was ignored when in the online/offline progress.\n";
    return $SIG{$signame};
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
my $host_ref = $config->{'slave_host'};
my $mail_ref = $config->{'mail'};

my @port;
if (ref($port_ref) eq "ARRAY") {
  foreach my $adminport (@$port_ref) {
     push @port, $adminport;
  }
} else {
  push @port, $port_ref;
}

my @slave_host;
if (ref($host_ref) eq "ARRAY") {
   foreach my $host (@$host_ref) {
     push @slave_host, $host;
   }
} else {
     push @slave_host, $host_ref;
}

my @mail;
if (ref($mail_ref) eq "ARRAY") {
    foreach my $recv (@$mail_ref) {
        push @mail, $recv;
    }
} else {
    push @mail, $mail_ref;
}

sub send_msg {
    my $data = join("\n", map { $_ = '+-- ' . $_ } @_);
    my $to = join( ' ', @mail);
    eval {
        `echo "$data" | /bin/mail -r "atlas\@setline.com" -s "atlas auto setline" $to`;
    };  

    if ( $@ ) { 
       warn "error send: $@";
    }   
}

mysql_setup;

while(1) {
    sleep($interval) if $interval;
    foreach my $slavehost (@slave_host) {
        my $state = get_slave_status($slavehost, $config->{'slave_port'}, $config->{'slave_user'}, $config->{'slave_pass'}, $threshold);

        {
            local $SIG{'INT'} = \&catch_sig;
            local $SIG{'TERM'} = \&catch_sig;
            for my $atlas_port (@port) {
                my $atlas_info = atlas_ends($config->{'atlas_host'}, $atlas_port, $config->{'atlas_user'}, $config->{'atlas_pass'}, $slavehost);
                #set offline when slave has error but atlas is ok.
                if ( $state eq 'ERR' and $atlas_info->{$atlas_port}->{'port'} + 0 == $atlas_port and $atlas_info->{$atlas_port}->{'state'} eq 'up' and $atlas_info->{$atlas_port}->{'type'} eq 'ro') {
                   atlas_setline('offline', $slavehost, $config->{'atlas_host'}, $atlas_port, $config->{'atlas_user'}, $config->{'atlas_pass'}, $atlas_info->{$atlas_port}->{'id'}) if $setline;
                }

                #set online when slave is ok but atlas is error. 
                if ( $state eq 'OK' and $atlas_info->{$atlas_port}->{'port'} + 0 == $atlas_port and $atlas_info->{$atlas_port}->{'state'} eq 'offline' and $atlas_info->{$atlas_port}->{'type'} eq 'ro')   {
                   atlas_setline('online', $slavehost, $config->{'atlas_host'}, $atlas_port, $config->{'atlas_user'}, $config->{'atlas_pass'}, $atlas_info->{$atlas_port}->{'id'}) if $setline;
                }
            }
        }
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
   slave_host:172.30.0.15,172.30.0.16     #multi slave hosts, split with ','.
   slave_port:3306                        #slave service port
   slave_user:slave_user                  #slave user, which can detect slave lag info.
   slave_pass:xxxxxx                      #slave_user password
   atlas_host:172.30.0.18                 #atlas service ip address, virtual ip is recommended.
   atlas_port:5012                        #atlas service port, one mysql_proxyd one port
   atlas_user:admin                       #atlas user
   atlas_pass:xxxxxxx                     #atlas user password

=item --setline

Enable set online/offline mode

=item --verbose

type: integer

Whether print slave check info or not.

=item --version

type: integer

Version of this script.

=item --threshold

type: integer

set offline node if slave lag greater than threshold value, default 30s.

=item --interval

type: integer

check every interval seconds.

=back

=head1 SYSTEM REQUIREMENTS

DBI, DBD::mysql, Config::Auto, Getopt::Long


=head1 BUGS

=head1 SEE ALSO

related tasks

=head1 AUTHOR

zhe.chen <chenzhe07@gmail.com>

=head1 CHANGELOG

v0.0.1 initial version

=cut
