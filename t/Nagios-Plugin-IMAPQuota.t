# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Nagios-Plugin-IMAPQuota.t'

#########################

use strict;
use warnings;

use Test::More tests => 2;
BEGIN { use_ok('Nagios::Plugin::IMAPQuota') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.
#

diag( "Testing Nagios::Plugin::IMAPQuota $Nagios::Plugin::IMAPQuota::VERSION, Perl $], $^X" );

can_ok('Nagios::Plugin::IMAPQuota','run');

