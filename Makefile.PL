use 5.008000;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Nagios::Plugin::IMAPQuota',
    VERSION_FROM      => 'lib/Nagios/Plugin/IMAPQuota.pm', # finds $VERSION
    PREREQ_PM         => { 'Nagios::Plugin' => 0.35, 'Mail::IMAPClient' => 3.28 }, # e.g., Module::Name => 1.1
	EXE_FILES         => [ 'script/check_imap_quota.pl' ],
	LICENSE           => 'gpl',
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Nagios/Plugin/IMAPQuota.pm', # retrieve abstract from module
       AUTHOR         => 'Tore A. Klock <alphapenguin73@gmail.com>') : ()),
);
