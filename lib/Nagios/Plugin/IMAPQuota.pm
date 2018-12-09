package Nagios::Plugin::IMAPQuota;
use strict;
use warnings;
use Nagios::Plugin;
use Mail::IMAPClient;

our $VERSION = '0.1';

our %defaults = (
    host     => 'localhost',
    warning  => '@0:10%',      # Same as 10:%
    critical => '@0:5%',       # same as 5:%
    mailbox  => 'INBOX',
    logname  => undef,
    port     => 143,
    starttls => 0,
    ssl      => 0
);

sub run {
    my $np = Nagios::Plugin->new(
        usage => q{Usage: %s -H <host> -l <username> -a <password> [options]},
        blurb =>
q{This plugin monitors the quota status of one or more IMAP mailboxes under a single account.

		It is intended to keep track of available space in important mailboxes that are rarely--or not at all--monitored by humans, thus enabling users to prevent messages from bouncing when the mailbox is full.
		},
        version => $VERSION
    );
    $np->add_arg(
        spec     => 'host|H=s',
        default  => $defaults{host},
        help     => qq{Server hostname. (Default: '%s')},
        required => 1
    );
    $np->add_arg(
        spec     => 'warning|w=s',
        default  => $defaults{warning},
        required => 1,
        help     => [
qq{Exit with WARNING status if the amount of free space is outside this range (in KB)},
qq{Exit with WARNING status if the percentage of free space is outside this range. (default: '%s')}
        ],
        label => [ '[@]start:end', '[@]start:end%' ],
    );
    $np->add_arg(
        spec     => 'critical|c=s',
        default  => $defaults{critical},
        required => 1,
        help     => [
qq{Exit with CRITICAL status if the amount of free space is outside this range (in KB)},
qq{Exit with CRITICAL status if the percentage of free space is outside this range. (default: '%s')}
        ],
        label => [ '[@]start:end', '[@]start:end%' ],
    );
    $np->add_arg(
        spec => 'mailbox|M=s@',
        help =>
          qq{Mailbox name (may be repeated, if necessary). (default: '%s').},
        default  => $defaults{mailbox},
        required => 1
    );
    $np->add_arg(
        spec     => 'logname|l=s',
        required => 1,
        help     => qq{IMAP server username (default: '%s')},
        default  => $defaults{logname}
    );
    $np->add_arg(
        spec     => 'authentication|a=s',
        required => 1,
        help     => 'IMAP server password.'
    );
    $np->add_arg(
        spec     => 'port|p=i',
        default  => $defaults{port},
        required => 1,
        help     => qq{IMAP server port number. (default: '%s')}
    );
    $np->add_arg(
        spec    => 'starttls',
        default => 0,
        help    => 'Connect using STARTTLS. (default: '
          . ( $defaults{starttls} ? 'yes' : 'no' ) . ')',
    );
    $np->add_arg(
        spec    => 'ssl',
        default => 0,
        help    => 'Connect using SSL. (default: '
          . ( $defaults{ssl} ? 'yes' : 'no' ) . ')',
    );
    $np->getopts;

    my $opts = $np->opts;

    $opts->{mailbox} = [ $opts->mailbox ]
      unless ( ref $opts->{mailbox} eq 'ARRAY' );

    my ( $warn_pct, $crit_pct, $warn_size, $crit_size );
    if ( $opts->warning =~ /(.+)%$/ ) {
        $warn_pct = $1;
    }
    else {
        $warn_size = $opts->warning;
    }

    if ( $opts->critical =~ /(.+)%$/ ) {
        $crit_pct = $1;
    }
    else {
        $crit_size = $opts->critical;
    }
    if ( $opts->verbose >= 2 ) {
        log_info('Runtime Options:');
        log_info( ' Host: ',           $opts->host );
        log_info( ' Port: ',           $opts->port );
        log_info( ' Logname: ',        $opts->logname );
        log_info( ' Password: ',       $opts->authentication );
        log_info( ' Mailbox: ',        join( ', ', @{ $opts->mailbox } ) );
        log_info( ' Critical range: ', $opts->critical );
        log_info( ' Warning range: ',  $opts->warning );
        log_info( ' STARTTLS: ', ( $opts->starttls ? 'yes' : 'no' ) );
        log_info( ' SSL: ',      ( $opts->ssl      ? 'yes' : 'no' ) );
    }
    alarm $opts->timeout;
    if (
        my $imap = Mail::IMAPClient->new(
            Server   => $opts->host,
            Port     => $opts->port,
            Starttls => $opts->starttls,
            Ssl      => $opts->ssl,
            User     => $opts->logname,
            Password => $opts->authentication,
            Debug    => ( $opts->verbose > 2 ),
            Timeout  => $opts->timeout
        )
      )
    {
        my @features = $imap->capability();
        log_error( 'capability: ' . $imap->LastError ) if ( $imap->LastError );
        if ( $imap->has_capability('QUOTA') ) {
            foreach my $mailbox ( @{ $opts->mailbox } ) {
                if ( $imap->examine($mailbox) ) {
                    my $quota_max = $imap->quota($mailbox);
                    log_error( 'quota: ' . $imap->LastError )
                      if ( $imap->LastError );
                    my $quota_used = $imap->quota_usage($mailbox);
                    log_error( 'quota_usage: ' . $imap->LastError )
                      if ( $imap->LastError );
                    my $message_count = $imap->message_count($mailbox);
                    log_error( 'message_count ' . $imap->LastError )
                      if ( $imap->LastError );
                    if (   defined $quota_used
                        && defined $quota_max
                        && $quota_max > 0 )
                    {
                        my $quota_pct      = ( 100 * $quota_used / $quota_max );
                        my $quota_free     = $quota_max - $quota_used;
                        my $quota_free_pct = ( 100 * $quota_free / $quota_max );

                        $np->add_perfdata(
                            label    => "$mailbox\_storage",
                            value    => $quota_used,
                            uom      => 'KB',
                            warning  => $warn_size,
                            critical => $crit_size,
                            max      => $quota_max,
                            min      => 0
                        );
                        $np->add_perfdata(
                            label => "$mailbox\_messages",
                            value => $message_count
                        );
                        my $code;
                        if ( defined $crit_pct && defined $warn_pct ) {
                            $code = $np->check_threshold(
                                check    => $quota_free_pct,
                                warning  => $warn_pct,
                                critical => $crit_pct
                            );
                        }
                        else {
                            $code = $np->check_threshold(
                                check    => $quota_free,
                                warning  => $warn_size,
                                critical => $crit_size
                            );
                        }

                        # Report status of quota
                        $np->add_message(
                            $code,
                            sprintf(
'%s has %d messages using %d (%d%%) of %d KB allocated (%d KB free)',
                                $mailbox,   $message_count, $quota_used,
                                $quota_pct, $quota_max,     $quota_free
                            )
                        );
                    }
                }
                else {
                    log_error( 'examine: ' . $imap->LastError );
                }
            }
            $imap->logout();
            log_error( 'logout: ' . $imap->LastError ) if ( $imap->LastError );
        }
        else {
            $np->add_message( CRITICAL,
                "QUOTA is not supported by " . $opts->host );
        }
    }
    else {
        $np->add_message( CRITICAL, "Connect failed: $@" );
    }
    my ( $code, $message ) = $np->check_messages();
    $np->nagios_exit( return_code => $code, message => $message );
}

sub log_info  { print STDERR 'INFO: ',  @_, "\n"; }
sub log_error { print STDERR 'ERROR: ', @_, "\n"; }

1;
__END__

=head1 NAME

Nagios::Plugin::IMAPQuota - Nagios plugin to monitor the quota usage of an IMAP mailbox.

=head1 SYNOPSIS

check_imap_quota.pl -H <host> -l <username> -a <password> --starttls

The status message looks something like this:
  
  INBOX has 6524 messages using 472540 (90%) of 524288 KB allocated (51748 KB free) 

It also reports performance statistics, which are formatted like this, for easy consumption by graphing tools.

  INBOX_storage=472540KB;;;0;524288 INBOX_messages=6524;;

=head1 DESCRIPTION

This plugin monitors the quota status of one or more IMAP mailboxes under a single account. It also reports on the number of messages in the mailbox.

=head1 OPTIONS

=over 4

=item -?, --usage

Print usage information

=item -h, --help

Print detailed help screen

=item -V, --version

Print version information

=item --extra-opts=[section][@file]

Read options from an ini file. See http://nagiosplugins.org/extra-opts for usage and examples.

=item -H, --host=STRING

Server hostname. (Default: 'localhost')

=item -w, --warning=[@]start:end

Exit with WARNING status if the amount of free space is outside this range (in KB)

=item -w, --warning=[@]start:end%

Exit with WARNING status if the percentage of free space is outside this range. (default: '@0:10%')

=item -c, --critical=[@]start:end

Exit with CRITICAL status if the amount of free space is outside this range (in KB)

=item -c, --critical=[@]start:end%

Exit with CRITICAL status if the percentage of free space is outside this range. (default: '@0:5%')

=item -M, --mailbox=STRING

Mailbox name (may be repeated, if necessary). (default: 'INBOX').

=item -l, --logname=STRING

IMAP server username (default: '')

=item -a, --authentication=STRING

IMAP server password.

=item -p, --port=INTEGER

IMAP server port number. (default: '143')

=item --starttls

Connect using STARTTLS. (default: no)

=item --ssl

Connect using SSL. (default: no)

=item -t, --timeout=INTEGER

Seconds before plugin times out (default: 15)

=item -v, --verbose

Show details for command-line debugging (can repeat up to 3 times)

=back

=head1 METHODS

=over 4

=item run

  Run the plugin.

=back

=head1 SEE ALSO

L<Nagios::Plugin::POP3> - an addon to monitor the number of messages in a POP mailbox.

L<Nagios::Plugin> - the framework on which this module is built.

L<Mail::IMAPClient> - the workhorse behind this module.

=head1 AUTHOR

Tore A. Klock E<lt>alphapenguin73@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Tore A. Klock

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
It may be used, redistributed and/or modified under the terms of the GNU
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

=cut
