# ===============================================================================================================
#    SrvrPowerCtrl - a plugin for SqueezeCenter 7.3.x / Squeezebox Server 7.4.x
#    Allows shutdown/restart/suspend/hibernation of your Squeezebox Server
#    hardware via SBS's web interface, your Squeezebox's IR remote
#    or via a SBC / Touch / SqueezePlay.
#
#    Version 20160501.145329
#
#    Copyright (C) 2008, 2009 Gordon Harris
#
#    This program is free software; you can redistribute it and/or
#    modify it under the terms of the GNU General Public License,
#    version 2, which should be included with this software.
#
#    Based on Adrian C's (aka tenwiseman) Server Power Control plugin:
#    http://adrianonline.wordpress.com/
#    http://forums.slimdevices.com/showthread.php?t=32674
#    Copyright AdrianOnline.Net Feb 2007. Initially modeled on Max Spicer's Max2.pm
#
#    Also includes code from PeterW's AllQuiet plugin: http://www.tux.org/~peterw/slim/slim7/AllQuiet/
#    AllQuiet copyright (c) 2007 by Peter Watkins (peterw@tux.org)
#
#
#    See a duscussion of this plugin at http://forums.slimdevices.com/showthread.php?t=48521
#
# ===============================================================================================================
#
#    Util.pm -- Misc routines..
#

package Plugins::SrvrPowerCtrl::Util;

use base qw(Slim::Plugin::Base);
use strict;

use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Time::Zone;
use File::Spec::Functions qw(:ALL);
use Cwd 'abs_path';
#use Cwd qw(abs_path);
use Scalar::Util qw(blessed);
use Socket;
#use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

#$x = "blip";


#Global Variables..
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;


#sub max ($$) { $_[$_[0] < $_[1]] }
#
#sub min ($$) { $_[$_[0] > $_[1]] }

# 7.0 == SqueezeCenter
# 7.4 == Squeezebox Server
# 7.7 == Logitech Media Server

sub SrvrPowerCtrlStats {
	return sprintf(string('PLUGIN_SRVRPOWERCTRL_BASIC_SETTINGS_HEADER_STATS'),
						$g{nAppVersion},
						GetSCInitials(),
						$::VERSION,
						$g{szOS},
						$g{szDistro},
						$g{szSCUser},
						($g{prefs}->{bNoShowMac} ? ' ' : $g{szServerMAC}));
}

#sub IsNull {
#	if (!defined( @_) || ! @_ ) {
#		return 1;
#	}
#	return 0;
#}

sub IsNumeric {
	my ($num) = @_;

	#$g{log}->is_debug && $g{log}->debug("Testing $num");

	if (!defined($num)) {
		return 0;
 	} elsif ($num =~ /^-?\d/) {
		return 1;
	}
	return 0;
}

sub IsValidClient {
	my $client = shift || return 0;
	if (eval{$client->id()}) {
		return 1;
	}
	return 0;
}


sub ClientAttribute {
	my ($client, $attr) = @_;
	if ( !defined($client) || !defined($attr) ) {
		return "no $attr";
	}
	return ( eval {$client->$attr()} || "no $attr" );
}

sub ClientSpec {
	my $client = shift;

	return ( "Client is a: modelName: [" . ClientAttribute($client, 'modelName') . "] model: [" . ClientAttribute($client, 'model') . "] deviceid: [" . ClientAttribute($client, 'deviceid') . "] name: [" . ClientAttribute($client, 'name') . "] id: [" . ClientAttribute($client, 'id') . "]");

}

sub IsVFDClient {
	my $client = shift || return 0;

	if ( ClientAttribute($client, 'model') =~ m/^(slimp3|boom|squeezebox|squeezebox2|squeezebox3|transporter)$/ ) {
		return 1;
	}

	return 0;
}

sub IsSPClient {
	my $client = shift || return 0;

	if ( ClientAttribute($client, 'model') =~ m/^(fab4|baby)$/ ) {
		return 1;
	}

	return 0;
}

sub GetPluginPath {
	my $fullname = File::Spec->rel2abs( __FILE__ );
	my ($volume, $path, $file) = File::Spec->splitpath($fullname);

	#Another aproach to resolve symlinks..
    my $absolute_path = $volume ? $volume . $path : $path;
    $path = abs_path($absolute_path);

	return $path;
}

sub GetFileOwner {
	my $szFilename = shift;
	my $uid = (stat "$szFilename" )[4];
	my $user = (getpwuid ($uid))[0];
	return $user;
}

sub GetSCName {
	if (Slim::Utils::Versions::compareVersions($::VERSION, '7.4') < 0) {
		return string('SQUEEZECENTER');
	}
	return string('SQUEEZEBOX_SERVER');
}

sub GetSCInitials {
	##returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	#if (Slim::Utils::Versions::compareVersions("$::VERSION", '10.0') >= 0) {
	#	return 'UEML';
	#} elsif (Slim::Utils::Versions::compareVersions("$::VERSION", '7.7') >= 0) {
	#	return 'LMS';
	#} elsif (Slim::Utils::Versions::compareVersions("$::VERSION", '7.4') >= 0) {
	#	return 'SBS';
	#}
	#return 'SC';
	
	my $nVer = GetSCVersion();
	if ( $nVer >= 10 ) {
		return 'UEML';
	} elsif ( $nVer >= 7.7 ) {
		return 'LMS';
	} elsif ( $nVer >= 7.4 ) {
		return 'SBS';
	} else {
		return 'SC';
	}
}

sub GetSCUser {
	my $szSCUser = Slim::Utils::OSDetect::getOS()->{osDetails}->{uid};
	return $szSCUser;
}


#Get the SqueezeCenter Version, change it from 7.3.4 form into 7.34 and make it numeric..
#LIMITATION: this would see 7.4.1 as equal to 7.4.10
sub GetSCVersion {
	my $nSCVersion = $::VERSION;
	my $nPos = index($nSCVersion, '.');

	if ($nPos > 0) {
		$nPos++;
		my $szMinor = substr($nSCVersion, $nPos);
		$szMinor =~ s/\.//g;
		$nSCVersion = substr($nSCVersion, 0, $nPos) . $szMinor;
	}

	$nSCVersion = $nSCVersion * 1;

	return $nSCVersion;
}

sub GetOSDistro {
	my $szDistro = Slim::Utils::OSDetect::getOS()->{osDetails}->{osName};

	#$g{log}->is_debug && $g{log}->debug ("Raw distro name   == $szDistro");

	# clean up the name, removing version info..
	# e.g. on OS X, osName == MacOSX10.6.1(10B504)
	# Remove digits..
	$szDistro =~ s/\d//g;
	# Remove periods..
	$szDistro =~ s/\.//g;
	# Remove anything within parenthises
	$szDistro =~ s/\(.*\)//g;
	# Remove trailing whitespace and anything after that..
	#$szDistro =~ s/(^\S*)\s.*$/\1/g;
	$szDistro =~ s/\s//g;


	#$g{log}->is_debug && $g{log}->debug ("Clean distro name == $szDistro");

	# from svn 28890 7.4 trunk, OSX.pm:
	#$szDistro =~ s/ \(\w+?\)$//;

	return $szDistro;
}

# Adapted from python code at from: http://code.activestate.com/recipes/439094/
sub IOCTLGetMacAddress {
	my $interface = shift || "eth0";

	socket(my $socket, AF_INET, SOCK_DGRAM, 0);
	my $buf  = pack("a256", $interface);
	# SIOCGIFHWADDR == 0x8927
	ioctl($socket, 0x8927, $buf);
	close($socket);
	my $macstr = sprintf("%s%s:%s%s:%s%s:%s%s:%s%s:%s%s",split('',uc unpack("H12",substr($buf, 18, 6))));
	return $macstr;
}

my $max_addrs = 30;

# Adapted from http://www.perlmonks.org/?node_id=53660
sub IOCTLGetInterfaces {
	my %interfaces;
	socket(my $socket, AF_INET, SOCK_DGRAM, 0); # or die "socket: $!";
	{
		my $ifreqpack = 'a16a16';
		my $buf = pack($ifreqpack, '', '') x $max_addrs;
		my $ifconf = pack('iP', length($buf), $buf);

		#SIOCGIFCONF == 0x8912
		ioctl($socket, 0x8912, $ifconf);

		my $len = unpack('iP', $ifconf);
		substr($buf, $len) = '';

		%interfaces = unpack("($ifreqpack)*", $buf);

		unless (keys(%interfaces) < $max_addrs) {
			# Buffer was too small
			$max_addrs += 10;
			redo;
		}
	}
	close($socket);

	for my $addr (values %interfaces) {
		$addr = inet_ntoa((sockaddr_in($addr))[1]);
	}

	my @nics;
	my $interfaceMAC;

	while( my ($interfaceName, $interfaceIP) = each %interfaces ) {
		#truncate the interface name..
		substr($interfaceName, index($interfaceName, chr(0))) = '';
		$interfaceMAC = IOCTLGetMacAddress ($interfaceName);
		push ( @nics, {
			interfaceName => $interfaceName,
			interfaceMAC  => $interfaceMAC,
			interfaceIP   => $interfaceIP,
		});
	}

	return @nics;
}


sub GetServerMacAddress {

	#If TinySC, don't make a system call..
	if ( defined( &Slim::Utils::OSDetect::isSqueezeOS ) && Slim::Utils::OSDetect::isSqueezeOS() ) {
		my $my_ip = Slim::Utils::Network::serverAddr();
		my @interfaces = IOCTLGetInterfaces();

		foreach my $interface (@interfaces) {
			if ( $my_ip eq  $interface->{interfaceIP} ) {
				return $interface->{interfaceMAC};
			}
		}
		return 'UNKNOWN';
	}

	my $serverMAC;

	if ($^O =~ /^m?s?win/i) {		## Windows?
		$serverMAC = `ipconfig /all`;
	} else {						## Everything else..
		$serverMAC = `ifconfig -a`;
		#$serverMAC = IOCTLGetMacAddress();
	}

	if ( $serverMAC =~ /((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})/i ) {
		$serverMAC = $1;
		$serverMAC =~ s/\-/\:/g ;	## Windows ipconfig formats MAC as aa-bb-cc-dd-ee-ff
		return $serverMAC;
	}

	return 'UNKNOWN';
}

sub ListOurLogEntries {
	my $bAddBR = shift || 0;

	my $szServerLogFile = Slim::Utils::Log::serverLogFile();
	#my $szLogEntry;
	my $szLogEntries = '';

	if (! -e $szServerLogFile || !open(SERVERLOG, "<$szServerLogFile")) {
		return 0;
	}

	while (<SERVERLOG>) {
		#$szLogEntry = $_;
		#if ($szLogEntry =~ m/(^.*SrvrPowerCtrl.*$)/) {
		if ($_ =~ m/(^.*SrvrPowerCtrl.*$)/) {
			$szLogEntries .= $1 . ($bAddBR ? '<br>' : "\n");
		}
	}

	close(SERVERLOG);

	return $szLogEntries;
}


sub ArchivePrefsAndLog {
	my $szArchiveFile = shift;
	my $szPrefsFile;
	my $szSrvrLogFile;
	my $szLogFile;
	my $szZipFile;

 	if ($g{szOS} eq 'win') {
		$szPrefsFile   = Slim::Utils::OSDetect::dirsFor('log') . "\\srvrpowerctrl_tmp.prefs";
		$szSrvrLogFile = Slim::Utils::OSDetect::dirsFor('log') . "\\srvrpowerctrl_tmp.log";
		$szLogFile     = Slim::Utils::OSDetect::dirsFor('log') . "\\srvrpowerctrl.log";
		$szZipFile     = Slim::Utils::OSDetect::dirsFor('log') . "\\srvrpowerctrl_tmp.zip";
	} else {
		$szPrefsFile   = Slim::Utils::OSDetect::dirsFor('log') . "srvrpowerctrl_tmp.prefs";
		$szSrvrLogFile = Slim::Utils::OSDetect::dirsFor('log') . "srvrpowerctrl_tmp.log";
		$szLogFile     = Slim::Utils::OSDetect::dirsFor('log') . "srvrpowerctrl.log";
		$szZipFile     = Slim::Utils::OSDetect::dirsFor('log') . "srvrpowerctrl_tmp.zip";
	}

	#$szPrefsFile =  '/tmp/srvrpowerctrl_tmp.prefs';
	#$szLogFile   =  '/tmp/srvrpowerctrl_tmp.log';
	#$szZipFile   =  '/tmp/srvrpowerctrl_tmp.zip';

	if (defined($szArchiveFile)) {
		$szZipFile = $szArchiveFile;
	}

	if (open(PREFSDUMP, ">$szPrefsFile")) {
		print PREFSDUMP Plugins::SrvrPowerCtrl::Settings::ListPrefs();
		close(PREFSDUMP);
	} else {
		$g{log}->error("Could not create prefsdump $szPrefsFile");
	}

	if (open(LOGDUMP, ">$szSrvrLogFile")) {
		print LOGDUMP ListOurLogEntries();
		close(LOGDUMP);
	} else {
		$g{log}->error("Could not create logdump $szLogFile");
	}

	my $zip;
	my $file_member;

	eval {
		require Archive::Zip;
		import Archive::Zip qw( :ERROR_CODES :CONSTANTS );
		#use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

		$zip = Archive::Zip->new();
	};

	$zip = Archive::Zip->new();

	#if (!defined $zip) {
	#	$g{log}->error("error loading Archive::Zip $@");
	#	return 0;
	#}

	if ( -e $szPrefsFile ) {
		$file_member = $zip->addFile( $szPrefsFile, 'srvrpowerctrl.prefs' );
	}

	if ( -e $szSrvrLogFile ) {
		$file_member = $zip->addFile( $szSrvrLogFile, 'server.log' );
	}

	if ( -e $szLogFile ) {
		$file_member = $zip->addFile( $szLogFile, 'srvrpowerctrl.log' );
	}

	unless ( $zip->writeToFileNamed($szZipFile) == 0 ) {
		$g{log}->error("Could not create archive $szZipFile");
		$szZipFile = undef;
	}

	unlink($szPrefsFile);
	unlink($szSrvrLogFile);

	if ( defined($szZipFile) && -e $szZipFile ) {
		$g{log}->info("Created prefs and log archive $szZipFile");
	}

	return $szZipFile;

}

sub AnyPlayersBusy {

	for my $client (Slim::Player::Client::clients()) {
		# Add lastActivityTime check from Michael Herger's tweaks to PreventStandby
		# Note that non-playing "activity" flags the player as busy only for the watchdog timer interval..i.e. 60 seconds...NOT for the full grace interval.
		if ( $client->isUpgrading() || $client->isPlaying() || (Time::HiRes::time() - $client->lastActivityTime <= $g{nWatchdogTimerInterval}) ) {
		#if ( $client->isUpgrading() || $client->isPlaying() ) {
			$g{log}->is_debug && $g{log}->debug("Player " . $client->name() . " is busy..");
			return 1;
		}
	}
	return 0;
}



sub AnyPlayersPlaying {
	my @clients;
	my $curclient;

	@clients = Slim::Player::Client::clients();

	foreach $curclient (@clients) {
		#$g{log}->is_debug && $g{log}->debug ($curclient->modelName() . ": " . $curclient->name() . " playmode is \[" . ClientAttribute($curclient, 'playmode') . "\]");
		if (Slim::Player::Source::playmode($curclient) eq 'play') {
			return 1;
		}
	}
	return 0;
}

sub AnyPlayersUpdating {
	my @clients;
	my $curclient;

	@clients = Slim::Player::Client::clients();

	foreach $curclient (@clients) {
		#Just block on isUpgrading, not on needsUpgrade..
		if ( $curclient->isUpgrading() ) {
			$g{log}->info ($curclient->modelName() . ": " . $curclient->name() . " needsUpgrade() is \[" . $curclient->needsUpgrade() . "\]");
			return 1;
		}
	}
	return 0;
}


sub DisplayPlayerMessage {
	my ($client, $message, $duration, $skipclient, $jivemessage, $bShouldBlock) = @_;
	my @clients;
	my $curclient;
	my $numclients;
	my $jive_duration;

	if (!defined($duration)) {
		$duration = $g{prefs}->nRegretDelay;
	} elsif (!$duration || !$message || !length($message)) {
		return;
	}

	#jive duration is in milliseconds, not seconds..
	$jive_duration = $duration * 1000;

	if (IsValidClient($client)) {
		push(@clients, $client);
	} else {
		@clients = Slim::Player::Client::clients();
	}

	$numclients = @clients;

	#fixup the message..change underscores to spaces..
	$message =~ s/_/ /sig;

	#$g{log}->is_debug && $g{log}->debug( "Displaying message \[" . (defined($jivemessage) ? $jivemessage : $message) . "\] on " . $numclients . " clients for " . $duration . " seconds.");

	foreach $curclient (@clients) {

		#Don't display a message here..
		if ( IsValidClient($skipclient) && ( ClientAttribute($skipclient, 'id') eq $curclient->id() ) ) {
			#$g{log}->is_debug && $g{log}->debug( "Not displaying message on " . $curclient->modelName() . ": " . $curclient->name() );
			next;
		}

		#Don't bother trying to disply the message on a SBR..
		if ($curclient->deviceid eq 7) {
			#$g{log}->is_debug && $g{log}->debug("Skipping display on " . $curclient->modelName() . ": " . $curclient->name() );
			next;
		}

		#$g{log}->is_debug && $g{log}->debug("Displaying message: [" . (defined($jivemessage) ? $jivemessage : $message) . "] on " . $curclient->modelName() . ":" . $curclient->model() . ": " . $curclient->name() );

		my $hDisp;

		##Change the font on the BOOM:
		if ($curclient->deviceid == 10) {
			$hDisp = {
					'line'			=> [ string('PLUGIN_SRVRPOWERCTRL_MODULE_NAME'), $message ],
					'fonts'			=> { 'graphic-160x32' => { 'line' => [ 'standard_n.1', 'standard_n.2' ] }, },
					};
		} else {
			$hDisp = {
					'line1'			=> string('PLUGIN_SRVRPOWERCTRL_MODULE_NAME'),
					'line2'			=> $message,
					};
		}

		#Display for any controlling SBC, touch, etc..
		$hDisp->{jive} = {
						'type'		=> 'popupInfo',
						'text'		=> [ (defined($jivemessage) ? $jivemessage : $message) ],
						'duration'	=> $jive_duration,
						};

		$curclient->showBriefly(
			$hDisp,
			$duration,
			0,  						# line2 is single line
			#(!$bShouldBlock ? 0 : 1),	# block updates
			!!$bShouldBlock+0,			# block updates
			1,  						# scroll to end
			(!IsValidClient($client) && Plugins::SrvrPowerCtrl::Watchdog::IsInEOD() ? 'powerOff' : 'idle'));	# Don't make this bright at night!

	}

}

sub UnBlockPlayerMessage {
	my ($client, $message, $duration) = @_;
	my @clients;
	my $curclient;

	#$g{log}->is_debug && $g{log}->debug( (IsValidClient($client) ? $client->name() : "All Clients") . ": " . ($message ? $message : "no message.") );

	#if (!IsNull($client)) {
	if (IsValidClient($client)) {
		push(@clients, $client);
	} else {
		@clients = Slim::Player::Client::clients();
	}

	foreach $curclient (@clients) {
		$curclient->unblock();
		$curclient->showBriefly( { 'jive' => { 'text'    => [ " " ], 'duration'	=> 100} },{'duration' => 10, 'block' => 0, } );
	}

	if (defined($message)) {
		$g{log}->is_debug && $g{log}->debug($message);
		DisplayPlayerMessage($client, $message, $duration);
	}

}


sub PowerOffPlayer {
	my ($client) = @_;
	my @clients;
	my $curclient;

	if (IsValidClient($client)) {
		push(@clients, $client);
	} else {
		@clients = Slim::Player::Client::clients();
	}

	foreach $curclient (@clients) {
		if ( $curclient->canPowerOff() && $curclient->power() ) {
			$g{log}->is_debug && $g{log}->debug( "Powering off " . $curclient->modelName() . ": " . $curclient->name());
			$curclient->execute(['power', '0']);
		}
	}
}

sub RestartSC {
	$g{log}->is_debug && $g{log}->debug("Attempting SC7.4 style service restart..");
	Slim::Control::Request::executeRequest(undef, ['restartserver']);
}


sub GetWhenShouldRun {
	my @aTime;
	my $szTime;

	@aTime = localtime(time());

	#forward 2 minutes..at on linux seems to need this..
	if ($aTime[0] >= 30) {
		$aTime[1] += 2;
	} else {
		#forward 1 minute..
		$aTime[1] += 1;
	}

	#we don't need no stinking seconds..
	$aTime[0] = 0;

	#fixup minutes..
	if ($aTime[1] >= 60) {
		if ($aTime[2] >= 23) {
			$aTime[2] = 0;
		}
		$aTime[1] -= 60;
	}

	$szTime = sprintf("%02d:%02d", $aTime[2], $aTime[1]);

	return $szTime;
}



# Quasi-printf processing of format placeholders in a command string..
# Substitution works as follows:
#
# %%	becomes		%
# %d	beccomes	unix epoch time (UTC)
# %l	becomes		unix epoch time + localtime offset
# %s	becomes		localtime 'YY-MM-DD HH:MM:SS'
# %f	becomes		localtime 'short-date', usu 'MM-DD-YY'
# %t	becomes		localtime 'HH:MM:SS'
# {+/-nnnn}			is used as a offset correction to the supplied time..

sub FormatCommand {
	my ($szCommand, $nTime, $nCorrection) = @_;

	if ( ! defined($szCommand) || ! length($szCommand) ) {
		return "";
	}

	if (!defined($nTime)) {
		$nTime = time();
	}

	if (!defined($nCorrection)) {
		$nCorrection = 0;
		#Anything within curly braces is interpreted as a request to correct the time, e.g. '{-120}' == subtract two minutes..
		if ( $szCommand =~ /\{(.+)\}/ ) {
			$nCorrection = $1;
			$szCommand =~ s/\{(.+)\}//g;		#remove the correction string..
			$g{log}->is_debug && $g{log}->debug("Command $szCommand contained a correction value of $nCorrection..");
		}
	}

	$nTime += $nCorrection;

	my $nTimeLocal 	= $nTime + tz_local_offset($nTime);
	my $szDate	 	= Slim::Utils::DateTime::shortDateF($nTime);
	my $szTime	 	= Slim::Utils::DateTime::timeF($nTime, "%H:%M:%S");
	my $szDateTime 	= Slim::Utils::DateTime::timeF($nTime, "%Y-%m-%d %H:%M:%S");

	#make % replacements
	#$g{log}->is_debug && $g{log}->debug("Before command: $szCommand");
	$szCommand =~ s/%%/¶/g;

	$szCommand =~ s/%d/$nTime/g;		# time as unix epoch
	$szCommand =~ s/%l/$nTimeLocal/g;	# local unix epoch
	$szCommand =~ s/%s/$szDateTime/g;	# YY-MM-DD HH:MM:SS
	$szCommand =~ s/%f/$szDate/g;		# Localtime short-date format, usu MM-DD-YY
	$szCommand =~ s/%t/$szTime/g;		# Localtime HH:MM:SS

	$szCommand =~ s/¶/%/g;

	#$g{log}->is_debug && $g{log}->debug("After command:  $szCommand");

	return $szCommand;
}

# From Peter Watkin's KidsPlay plugin: parseFields()
# sub to handle quoted fields, e.g. 'playlist play "/path/with some spaces/playlist.m3u"'
# sub to handle quoted fields, e.g. 'playlist play "/path/with some spaces/playlist.m3u"'
sub parseFields($) {
        my $line = shift;
	# certain characters should be escaped with a \ :
	# 	\ ; " [ ] { }
	# if the \ char is followed by any other char,
	# \ and the char following are interpreted as 2 chars
	my $specialC = "\\;\"\[\]\{\}";
	$line =~ s/^\s*//;
	$line =~ s/\s*$//;
	my @cooked = ();
	my $in = 0;
	my $quoted = 0;
	my $escaped = 0;
	my $i = 0;
	my $word = '';
	#my $iswindows = $^O =~ /^m?s?win/i;

	while ($i < length($line) ) {
		my $c = substr($line,$i++,1);
		$escaped = 0;
		#if ( $c eq "\\" && !$iswindows ) {
		if ( $c eq "\\" ) {
			$escaped = 1;
			if ($i < (length($line) -1)) {
				my $c2 = substr($line,$i++,1);
				if (index($specialC,$c2) > -1) {
					$c = $c2;
				} else {
					--$i;
					$escaped = 0;
				}

			} else {
				# just a \
			}
		}
		if ( $in ) {
			if ( $escaped ) {
				$word .= $c;
			} else {
				# end of this word?
				if ( ($quoted && ($c eq '"')) || ((!$quoted) && ($c =~ /\s/)) ) {
					push @cooked, $word;
					$word = '';
					$in = 0;
					$quoted = 0;
				} else {
					# build & keep moving
					$word .= $c;
				}
			}
		} else {
			# look for delim
			if ( $c eq '"' ) {
				$quoted = 1;
				$in = 1;
			} elsif ( $c !~ /\s/ ) {
				$quoted = 0;
				$in = 1;
				$word .= $c;
			}
		}
	}
	if ( $in ) { push @cooked, $word; }
	return @cooked;
}

#also Peter Watkin's code..
sub splitLines($$) {
	my $macro = shift;
	my $delim = shift;
	my @ms;
	my $line = '';
	my $i = 0;
	while ($i < length($macro) ) {
		my $c = substr($macro,$i,1);
		if ( $c eq "\\" ) {
			if ($i < (length($macro) -1)) {
				$c .= substr($macro,++$i,1);
			} else {
				# invalid escape!
				$c = '';
			}
		} else {
			if ($c eq $delim) {
				push @ms, $line;
				$line = '';
				$c = '';
			}
		}
		$line .= $c;
		++$i;
	}
	if ($line ne '') {
		push @ms, $line;
	}
	return @ms;
}



#Function "Slim::Control::Request::executeRequest" accepts the usual parameters
#of client, command array and callback params, and returns the request object.
#my $request = Slim::Control::Request::executeRequest($client, ['stop']);

sub CLIExecCmd {
	my ($callingclient, $command, $time) = @_;
	my @commands;
	my $cmd;
	my $res;
	my @results;

	if (! $command =~ m/^cli\:\/\//i ) {
		return -1;
	}

	#strip off the 'cli://'
	$command = substr($command,6);

	#allow multi-command cli requests using && as a separator..
	@commands = split('&&', $command );

	foreach $cmd (@commands) {
		#strip leading whitespace..
		$cmd =~ s/^\s// ;

		# parse the command
		my ($client, $arrayRef) = Slim::Control::Stdio::string_to_array($cmd);

		if (!defined $arrayRef) {
			next;
		}

		if (IsValidClient($client)) {
			$g{log}->info( ClientAttribute($client, 'name') . ' requesting command: ' . ClientAttribute($client, 'id') . " @{$arrayRef}" );
			$res = Slim::Control::Request::executeRequest($client, $arrayRef);

		} else {
			$g{log}->info( ClientAttribute($callingclient, 'name') . ' requesting command: ' . ClientAttribute($callingclient, 'id') . " @{$arrayRef}" );
			$res = Slim::Control::Request::executeRequest($callingclient, $arrayRef);

		}

		#don't dump huge results!
		$g{log}->is_debug && $g{log}->debug('results == ' . ($res->{_results}->{count} < 100 ? Data::Dump::dump($res->{_results}) : $res->{_results}));

		push(@results, $res);
	}
	return @results;
}

sub SystemExecCmd {
	my ($client, $command, $time) = @_;
	my @commands;
	my $cmd;
	my @cmd_args;
	my $res;
	my @results = ();

	if (!$command) {
		return -1;
	}

	@commands = splitLines($command,";");

	$g{log}->is_debug && $g{log}->debug( scalar(@commands) . " commands: $command");

	foreach $cmd (@commands) {

		$cmd =~ s/^\s*//;
		$cmd =~ s/\s*$//;

		$cmd = FormatCommand( $cmd, $time );

		if ( $cmd =~ m/^\s*cli\:\/\//i ) {
			$res = CLIExecCmd($client, $cmd, $time);
		} else {
			@cmd_args = parseFields($cmd);
			#make this log entry look less ominous..
			$g{log}->info( (IsValidClient($client) ? ClientAttribute($client, 'modelName') . ': ' . ClientAttribute($client, 'name') . ' via ' : '') . 'SrvrPowerCtrl executing command: ' . "@cmd_args" );
			$res = system @cmd_args[0..$#cmd_args];
			if ( $res == -1 ) {
				$g{log}->error("Command: \"@cmd_args\" failed to execute: $!");
			}
			$res = $res >> 8;


			#$res = "We are not doing this!";
			#sudo return values:
			#
			#Upon successful execution of a program, the exit status from sudo will simply be
			#the exit status of the program that was executed.
			#
			#Otherwise, sudo quits with an exit value of 1 if there is a configuration/permission
			#problem or if sudo cannot execute the given command. In the latter case the error string is printed to stderr.
			#$res == 1 may indicate a sudo permissions problem...not sure about return values from cmd.exe..
			$g{log}->is_debug && $g{log}->debug("Command: \"@cmd_args\" returned $res");
			push(@results, $res);
		}
	}


	return @results;
}


sub ScheduleCommand {
	my ($client, $item, $nAdditionalDelay) = @_;

	if (!defined($nAdditionalDelay)) {
		$nAdditionalDelay = 0;
	}

	#Find the next alarm and program the RTC to wake up the server at the appropriate time.
	if ($item->{'setrtcwakeup'}) {
		Plugins::SrvrPowerCtrl::Alarms::SetRTCWakeup();
	}

	#Do we want to call Slim::Utils::Timers::pendingTimers() here to see if there is anything to wait for?

	#cue up our action command to execute in the future..
	return Slim::Utils::Timers::setTimer(undef, time() + $item->{'cmdwait'} + $nAdditionalDelay,
		sub {
			my $res;
			my $command;
			my $cmdargs;
			my @cmd;

			#We're the timer action...clear the timer ID since it's fired..and the saved pending action..
			$g{tPendingActionTimer} = 0;
			$g{hPreviousAction} = $g{hPendingAction};
			$g{hPendingAction}->{isSleepDefered} = 0;
			$g{hPendingAction} = { };

			$command = $item->{command};

			# execute the coderef (if any) to get args for the cmd..
			if ( defined($item->{getcommandargcoderef}) ) {
				#execute the coderef..
				$cmdargs = &{$item->{getcommandargcoderef}}($client, $item);
				if ( defined($cmdargs) ) {
					if ( (IsNumeric($cmdargs)) && ($cmdargs == -1) ) {
						#fail mode..
						my $failmsg = sprintf( string('PLUGIN_SRVRPOWERCTRL_FAILURE_MSG'),  ucfirst( lc($item->{action}) ) );
						$g{log}->error("$item->{action} $item->{getcommandargcoderef} failed!");
						UnBlockPlayerMessage(undef, $failmsg);
						return;
					} else {
						#anything else returned is a cmdline arg for our script..
						$command = $item->{command} . ' ' . $cmdargs;
					}
				} else {
					#the coderef returned undef..
					$command = $item->{command};
				}
			}

			#if the command is a coderef rather than a script or system command name, execute it..
			if (ref($item->{command}) eq 'CODE') {
				$g{log}->is_debug && $g{log}->debug("Command is a coderef!");
				#execute the coderef..
				$cmdargs = &{$item->{command}}($client, $item);
			#else the command is a system command or script..
			} else {
				SystemExecCmd($client, $command);
			}

			if ($item->{'stopsc'}) {
				if (IsValidClient($client)) {
					#from SqueezeTray.pl
					$client->execute(['stopserver']);
				} else {
					main::stopServer();
				}
			}

			if (!$item->{dispblock}) {
				UnBlockPlayerMessage();
			}



		}, );
}


sub TestCoderefFail {
	my ($client, $item) = @_;

	$g{log}->is_debug && $g{log}->debug("Testing failure mode..");
	#$g{log}->is_debug && $g{log}->debug("client == " . $client->name() . ", type == " . $client->deviceid );
	$g{log}->is_debug && $g{log}->debug("client == " . ClientAttribute($client, 'name') . ", type == " . ClientAttribute($client, 'deviceid') );
	$g{log}->is_debug && $g{log}->debug("action == " . $item->{action} );

	return -1;
}


sub logHexDump {
    my $offset = 0;
    my(@array,$format);
	my $out;

	if (! $g{log}->is_debug ) {
		return;
	}

    foreach my $data (unpack("a16"x(length($_[0])/16)."a*",$_[0])) {
        my($len)=length($data);
        if ($len == 16) {
            @array = unpack('N4', $data);
            $format="0x%08x (%05d)   %08x %08x %08x %08x   %s\n";
        } else {
            @array = unpack('C*', $data);
            $_ = sprintf "%2.2x", $_ for @array;
            push(@array, '  ') while $len++ < 16;
            $format="0x%08x (%05d)" .
               "   %s%s%s%s %s%s%s%s %s%s%s%s %s%s%s%s   %s\n";
        }
        $data =~ tr/\0-\37\177-\377/./;
        $out = sprintf $format,$offset,$offset,@array,$data;
		$g{log}->debug($out);
        $offset += 16;
    }
}


sub logArgs {
	if (! $g{log}->is_debug ) {
		return;
	}

	my @args = @_;

	my $caller=(caller(1))[3]; # get full name
	$caller=~s/.*:://g; # remove package name

	if (!(@args)) {
		@args = ('undefined');
	}

	$g{log}->debug($caller . "() : " . Data::Dump::dump(\@args) );

	return 0;
}



#use JSON::XS::VersionOneAndTwo;

sub test {
	my ($request) = @_;

	logArgs($request);

	$request->setStatusProcessing();

	Plugins::SrvrPowerCtrl::Alarms::SetRTCWakeup();

	$request->setStatusDone();

	return 1;

}


1;

__END__
