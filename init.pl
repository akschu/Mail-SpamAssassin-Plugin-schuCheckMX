#!/usr/bin/perl

use DBI;
use schuCheckMX;
use Data::Dumper;

my $driver   = "SQLite";
my $database = "/etc/mail/spamassassin/schuCheckMX/schuCheckMX.db";
my $dsn = "DBI:$driver:dbname=$database";

if( ! -f $database ){
  print "New database, creating table...\n";
  my $dbh = DBI->connect($dsn, "", "", { RaiseError => 1 }) or diei $DBI::errstr;
  my $stmt = "CREATE TABLE schucheckmx (timestamp timestamp DEFAULT CURRENT_TIMESTAMP not null, domain char(255) not null, listeningsmtp bool not null);";
  my $rv = $dbh->do($stmt) or die $DBI::errstr;
  print "Table created successfully.\n  Please chown <spamassassin user> $database \n";
} else {
  print "Database found at $database, exiting....\n";
}
 
