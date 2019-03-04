# Mail-SpamAssassin-Plugin-schuCheckMX

## What is is this for?

schuCheckMX is a spamassassin plugin that looks for two things:

1.  Does the ingress message have a from or reply-to header, and if so, does the domain in that address have an MX record?
2.  Does the this same domain also have an SMTP server listening?

The idea is that you wouldn't want to get email from someone you can't reply to.

## Dependencies

This plugin requires DBI, sqlite, Net::SMTP, and Net::DNS

## Install

Install is pretty simple, you extract this code in /etc/mail/spamassassin/schuCheckMX (or anywhere you want) then edit init.pl and schuCheckMX.pm to point to your database file.  Run ./init.pl and it will create the database file.  Now chown <spamassassin user> $database file.   Now that your database is ready, symlink schuCheckMX.cf to your spamassassin config directory.

That should be it.

To confirm everything is working, pass a message through spamassassin and look for the SCHUCHECKMX debug messages:

spamassassin -D < test.eml 

## Support

I'm running this on my own mail system and it seems to work well, but I haven't flung a bunch of time at it to polish or fully test it.  If you find issues when email schu@schu.net, and I'll try to help.


