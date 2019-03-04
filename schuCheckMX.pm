package Mail::SpamAssassin::Plugin::schuCheckMX;

use strict;
use Mail::SpamAssassin;
use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::Logger;
use Mail::SpamAssassin::Timeout;

use Net::DNS;
use Net::SMTP;
use DBI;
use vars qw(@ISA);

my $driver   = "SQLite";
my $database = "/etc/mail/spamassassin/schuCheckMX/schuCheckMX.db";
my $dsn = "DBI:$driver:dbname=$database";
our $HELO = 'smtp.domain.com';

@ISA = qw(Mail::SpamAssassin::Plugin);

my $VERSION = "0.1";

sub new {
        my ($class, $mailsa) = @_;
        $class = ref($class) || $class;
        my $self = $class->SUPER::new($mailsa);
        bless ($self, $class);
        # Are network tests enabled?
        if ($mailsa->{local_tests_only}) {
                        dbg("SCHUCHECKMX: local tests only, not using schuCheckMX plugin");
        }
        else {
                        dbg("SCHUCHECKMX: Using schuCheckMX plugin $VERSION");
        }
        $self->register_eval_rule ("schucheckmx_ismx");
        $self->register_eval_rule ("schucheckmx_smtpping");
        
        return $self;
}

sub schucheckmx_ismx {
  my ($self, $permsgstatus) = @_;

  return 0 if $self->{main}->{local_tests_only}; # in case plugins ever get called

  # if a user set dns_available to no we shouldn't be doing MX lookups
  return 0 unless $permsgstatus->is_dns_available();

  # avoid FPs (and wasted processing) by not checking when all_trusted
  return 0 if $permsgstatus->check_all_trusted;

  # next we need the recipient domain's MX records... who's the recipient
  foreach my $from ($permsgstatus->all_from_addrs) {

    my( $user, $domain ) = split( "@", $from );
    dbg("SCHUCHECKMX_ISMX: going to test domain $domain");

    if ( ! $domain ){
      dbg("SCHUCHECKMX_ISMX: Couldn't find sender domain in permsgstatus->all_from_addrs");
      return 0;
    }

    my $res = Net::DNS::Resolver->new;
    my $packet = $res->query( $domain, 'MX' );

    if(  ! $packet ){
      dbg("SCHUCHECKMX_ISMX: Couldn't find MX record for $domain");
      return 1;
    }

  }

  return 0;
}

sub schucheckmx_smtpping {
  my ($self, $permsgstatus) = @_;
  my $smtp;
  my $dbh;

  return 0 if $self->{main}->{local_tests_only}; # in case plugins ever get called

  # if a user set dns_available to no we shouldn't be doing MX lookups
  return 0 unless $permsgstatus->is_dns_available();

  # avoid FPs (and wasted processing) by not checking when all_trusted
  return 0 if $permsgstatus->check_all_trusted;

  # get the database going
  if( ! -f $database ){
    dbg("SCHUCHECKMX_SMTPPING: Missing database, skipping schucheckmx_smtpping");
    return -1;
  } else {
    $dbh = DBI->connect($dsn, "", "", { RaiseError => 1 }) or dbg("SCHUCHECKMX_SMTPPING: Found database error: " .  $DBI::errstr );
  }

  # whack any old stuff
  $dbh->do("delete from schucheckmx where timestamp < date( 'now','-1 day');") or dbg("SCHUCHECKMX_SMTPPING: Found database error: " .  $DBI::errstr );

  # next we need the recipient domain's MX records... who's the recipient
  foreach my $from ($permsgstatus->all_from_addrs) {

    my( $user, $domain ) = split( "@", $from );
    dbg("SCHUCHECKMX_SMTPPING: going to test domain $domain");

    if ( ! $domain ){
      dbg("SCHUCHECKMX_SMTPPING: Couldn't find sender domain in permsgstatus->all_from_addrs");
      return 0;
    }

    my $result =  $dbh->selectrow_hashref( "select * from schucheckmx where domain = ?", {}, ( $domain ) ) ;

    if( $result ) {

      if( $result->{listeningsmtp} ) {
        dbg("SCHUCHECKMX_SMTPPING: found $domain cached in database, and listening");
        return 0;
      } else {
        dbg("SCHUCHECKMX_SMTPPING: found $domain cached in database, and NOT listening");
        return 1;
      }

    } 

    my $res = Net::DNS::Resolver->new;
    my $packet = $res->query( $domain, 'MX' );

    if( $packet ){

      foreach my $answer ( grep { $_->type eq "MX" } $packet->answer){

        # untaint
        $answer->exchange =~ /^(.*)$/;
        my $mx = $1;

        dbg("SCHUCHECKMX_SMTPPING: DNS returned '$mx' for $domain");

        if( $smtp = Net::SMTP->new( $mx, Hello => $HELO, Timeout => 60 ) ){
          dbg("SCHUCHECKMX_SMTPPING: Sent HELO $HELO got banner " .$smtp->banner);
          my $sth = $dbh->prepare( "insert into schucheckmx (domain, listeningsmtp) values (?, ?)" );
          $sth->execute( $domain, 1) or dbg("SCHUCHECKMX_SMTPPING: Found database error: " .  $DBI::errstr );
          $smtp->quit;
          return 0;
        } else {
          dbg("SCHUCHECKMX_SMTPPING: no smtp server listening");
        }

      }

      dbg("SCHUCHECKMX_SMTPPING: Could not get a banner from any of the smtp servers");
      my $sth = $dbh->prepare( "insert into schucheckmx (domain, listeningsmtp) values (?, ?)" );
      $sth->execute( $domain, 0) or dbg("SCHUCHECKMX_SMTPPING: Found database error: " .  $DBI::errstr );
      return 1;

    } else {


      if( $smtp = Net::SMTP->new( $domain, Hello => $HELO, Timeout => 60 ) ){
        dbg("SCHUCHECKMX_SMTPPING: sent HELO $HELO got banner " .$smtp->banner);
        $smtp->quit;
        my $sth = $dbh->prepare( "insert into schucheckmx (domain, listeningsmtp) values (?, ?)" );
        $sth->execute( $domain, 1) or dbg("SCHUCHECKMX_SMTPPING: Found database error: " .  $DBI::errstr );
        return 0;
      } else {
        my $sth = $dbh->prepare( "insert into schucheckmx (domain, listeningsmtp) values (?, ?)" );
        $sth->execute( $domain, 0) or dbg("SCHUCHECKMX_SMTPPING: Found database error: " .  $DBI::errstr );
        dbg("SCHUCHECKMX_SMTPPING: no smtp server listening");
        return 1;
      }

    }

  }

}

1;
