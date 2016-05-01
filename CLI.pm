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
#    CLI.pm -- helper routines for srvrpowerctrl CLI processing
#

package Plugins::SrvrPowerCtrl::CLI;

use base qw(Slim::Plugin::Base);
use strict;

use Slim::Utils::Strings qw(string);

#Global Variables..
use Plugins::SrvrPowerCtrl::Settings ();
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

#use Plugins::SrvrPowerCtrl::Watchdog;

#[srverpowerctrl status]
sub cliGetStatus {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my ($nIdled, $nEODd) = Plugins::SrvrPowerCtrl::Watchdog::GetIdleCountDown();
	my ($nIdle, $nEOD)   = Plugins::SrvrPowerCtrl::Watchdog::GetIdleCount();
	my $nRTCWakeupTime   = Plugins::SrvrPowerCtrl::Alarms::GetRTCWakeupTime();


	$request->addResult('_action', 'status:enabled');
	$request->addResult('_version', "version:$g{nAppVersion}");
	$request->addResult('_path', "path:$g{szAppPath}");
	$request->addResult('_os', "os:$g{szOS}");
	$request->addResult('_distro', "distro:$g{szDistro}");
	$request->addResult('_servermac', "server_mac:" . ($g{prefs}->bNoShowMac ? 'not-shown' : $g{szServerMAC}));
	$request->addResult('_idlecountdown', "idlecountdown:$nIdled");
	$request->addResult('_eodcountdown', "eodcountdown:$nEODd");
	$request->addResult('_idlecount', "idlecount:$nIdle");
	$request->addResult('_eodcount', "eodcount:$nEOD");
	$request->addResult('_wakealarm', "wakealarm:$nRTCWakeupTime");

	$request->setStatusDone();
}

#[srvrpowerctrl actions]		##reports a list of all the available actions possible..
sub cliGetActions {
	my ($request) = @_;
	# CLI available actions which aren't in the Menu::ActionItems..
	my @actions = ( 'status', 'actions', 'setblock', 'clearblock', 'listblock', 'listblocks', 'getidlecount', 'getidlecountdown', 'setidlecount', 'resetidlecount', 'getwakealarm', 'setwakealarm', 'setpref', 'getpref', 'listprefs', 'setlog', 'dumplog', 'zipdata' );
	my $actionlist;

	$request->setStatusProcessing();

	foreach my $item (@{$g{aActions}}) {
		#if ($item->{menuindex} ge 0) {
			push (@actions, $item->{'action'});

		#}
	}

	$actionlist = join(':', @actions);
	$request->addResult('_action', $actionlist);

	$request->setStatusDone();
}

sub cliSetBlock {
	my ($request) = @_;
	my $client = $request->client();
	my $action = $request->getParam( '_action');
	my $blockowner = $request->getParam('_switchclient');
	my $message = $request->getParam( '_message');

	if ( !defined($blockowner) ) {
		$blockowner = 'viacli';
	}

	$g{log}->is_debug && $g{log}->debug("Attempting to set block via CLI: caller: $blockowner, message: $message");
	my $blockcode = Plugins::SrvrPowerCtrl::Plugin::blockAction($client, 'set', $blockowner, $message);

	if (Plugins::SrvrPowerCtrl::Util::IsNumeric($blockcode) && $blockcode < 0) {
		$g{log}->error( "BadParam: $action");
		$request->addResult('_blockcode', $blockcode);
		$request->setStatusBadParams();
		$request->setStatusDone();
		return;
	} else {
		$request->addResult('_blockcode', $blockcode);
		$request->setStatusDone();
		Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage(undef, $message, 10);
		return;
	}

}

sub cliClearBlock {
	my ($request) = @_;
	my $client = $request->client();
	my $action = $request->getParam( '_action');
	my $blockowner = $request->getParam('_switchclient');
	my $message = $request->getParam( '_message');
	my $blockcount = 0;

	if ( !defined($blockowner) ) {
		$blockowner = 'viacli';
	}

	$g{log}->is_debug && $g{log}->debug("Attempting to clear block via CLI: caller: $blockowner, message: $message");

	$blockcount = Plugins::SrvrPowerCtrl::Plugin::blockAction($client, 'clear', $blockowner, $message);

	#A zero result indicates that the last block has been clearned
	if ($blockcount >= 0) {
		$request->addResult('_blockcode', $blockcount);
		$request->setStatusDone();
		Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage(undef, $message, 10);
		return;
	} else {  #A -1 result indicates error..
		$g{log}->error( "BadParam: $action");
		$request->addResult('_blockcode', $blockcount);
		$request->setStatusBadParams();
		return;
	}

}

sub cliListBlock {
	my ($request) = @_;
	my $n;

	#$g{log}->is_debug && $g{log}->debug( "listblock request.." );
	$g{log}->debug( "listblock request.." );

	$n = 0;
	if (Plugins::SrvrPowerCtrl::Block::BlockFileExists()){
		my $blockfile = Plugins::SrvrPowerCtrl::Block::GetBlockFileName();
		#silence a warning in the log..
		#$blockfile =~ s!\/!\\/!g;
		$request->addResult('_block' . $n, "blockfile\|viacli\|$blockfile"  );
		$n++;
	}
	foreach my $element (@{$g{aBlockAction}}) {
		if ( defined($element->{'caller'}) ) {
			$request->addResult('_block' . $n, "$element->{'blockcode'}|$element->{'caller'}|$element->{'reason'}"  );
			$n++;
		}
	}

	if (!$n) {
		$request->addResult('_block', 'no_blocks'  );
	}

	$request->setStatusDone();
	return 0;
}

sub cliGetIdleCountDown {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my ($nIdle, $nEOD) = Plugins::SrvrPowerCtrl::Watchdog::GetIdleCountDown();

	$request->addResult('_idlecountdown', "idlecountdown:$nIdle");
	$request->addResult('_eodcountdown', "eodcountdown:$nEOD");

	$request->setStatusDone();
}


sub cliGetIdleCount {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my ($nIdle, $nEOD) = Plugins::SrvrPowerCtrl::Watchdog::GetIdleCount();

	$request->addResult('_idlecount', "idlecount:$nIdle");
	$request->addResult('_eodcount', "eodcount:$nEOD");

	$request->setStatusDone();
}

sub cliSetIdleCount {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my $nNewIdle = $request->getParam( '_message');
	my $nNewEOD = $request->getParam('_switchclient');
	my ($nIdle, $nEOD) = Plugins::SrvrPowerCtrl::Watchdog::SetIdleCount($nNewIdle, $nNewEOD);

	$request->addResult('_idlecount', "idlecount:$nIdle");
	$request->addResult('_eodcount', "eodcount:$nEOD");

	$request->setStatusDone();
}

sub cliResetIdleCount {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my ($nIdle, $nEOD) = Plugins::SrvrPowerCtrl::Watchdog::ResetIdleCount();

	$request->addResult('_idlecount', "idlecount:$nIdle");
	$request->addResult('_eodcount', "eodcount:$nEOD");

	$request->setStatusDone();
}

sub cliGetNextRTCWakeAlarm {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my $szTime;
	my $szFormat1 = $request->getParam( '_message');
	my $szFormat2 = $request->getParam('_switchclient');

	$g{log}->is_debug && $g{log}->debug( "param1: " . ($szFormat1 ? $szFormat1 : "undefined") . "  param2: " . ($szFormat2 ? $szFormat2 : "undefined") );

	my $nRTCWakeupTime   = Plugins::SrvrPowerCtrl::Alarms::GetRTCWakeupTime();

	if ($nRTCWakeupTime) {
		if (defined($szFormat1)) {
			$szTime = $szFormat1;
		}

		if (defined($szFormat2)) {
			$szTime = $szTime . ' '. $szFormat2;
		}

		if (!defined($szTime)) {
			$szTime = '%d';
		}

		$g{log}->is_debug && $g{log}->debug( "szTime before: $szTime");

		$szTime = Plugins::SrvrPowerCtrl::Util::FormatCommand($szTime, $nRTCWakeupTime);

		$g{log}->is_debug && $g{log}->debug( "szTime after: $szTime");
	} else {
		$szTime = "0";
	}

	$request->addResult('_wakealarm', "wakealarm:$szTime");

	$request->setStatusDone();
}

sub cliSetNextRTCWakeAlarm {
	my ($request) = @_;
	my $nRet;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	#arg processing:

	#no args == Set using next alarm..

	#arg1 == time to set the alarm
	#arg2 == who's calling...if 'system',

	my $nWakeupTime = $request->getParam( '_message');

	if (defined($nWakeupTime)) {
		if (!Plugins::SrvrPowerCtrl::Util::IsNumeric($nWakeupTime)) {
			$nWakeupTime = 0;
		}
		$nWakeupTime = $nWakeupTime * 1;
	}

	my $szWhoIsCalling = $request->getParam('_switchclient');


	$g{log}->is_debug && $g{log}->debug( "param1: " . ($nWakeupTime ? $nWakeupTime : "undefined") . "  param2: " . ($szWhoIsCalling ? $szWhoIsCalling : "undefined") );

	#If we've initiated the sleep, don't try to process a system sleep request!!
	if ( !((defined($szWhoIsCalling) && $szWhoIsCalling eq 'system') && $g{hPreviousAction}) ) {
		$nRet = Plugins::SrvrPowerCtrl::Alarms::SetRTCWakeup($nWakeupTime);
	} else {
		$g{log}->info( "Ignoring setnextwakeuptime request from system. Wakeup time has already been set!" );
	}


	$request->addResult('_wakealarm', "wakealarm:". (!$nRet ? 'no%20alarms' : "$nRet"));

	$request->setStatusDone();

}

sub cliPrefsList {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my $dumpFileName = $request->getParam( '_message');


	my @prefs=split("\n", Plugins::SrvrPowerCtrl::Settings::ListPrefs());
	my $n = 0;

	foreach my $pref (@prefs) {
		$request->addResult("_pref${n}", "$pref");
		$n++;
	}

	if (defined($dumpFileName)) {
		if (open(DUMPFILE, ">>$dumpFileName")) {
			#print DUMPFILE Data::Dump::dump($g{prefs});
			print DUMPFILE Plugins::SrvrPowerCtrl::Settings::ListPrefs();
			close(DUMPFILE);
		}
	}


	$request->setStatusDone();
}

sub cliPrefSet {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my $prefName = $request->getParam( '_message') || 'undef';
	my $prefNameFound = Plugins::SrvrPowerCtrl::Settings::FindPrefName($prefName);

	if (!defined($prefNameFound)) {
		$request->addResult('_badparam',"BadPrefName:$prefName");
		return $request->setStatusBadParams();
	}

	my $prefValue = $request->getParam('_switchclient');

	$g{prefs}->set($prefNameFound, $prefValue);

	$request->addResult('_servermac', "server_mac:" . ($g{prefs}->bNoShowMac ? 'not-shown' : $g{szServerMAC}));

	$request->setStatusDone();

}

sub cliPrefGet {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my $prefName = Plugins::SrvrPowerCtrl::Settings::FindPrefName($request->getParam( '_message'));
	my $prefValue = $g{prefs}->get($prefName);

	$request->addResult('_pref', "$prefName:$prefValue");

	$request->setStatusDone();

}

sub cliLogList {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my $dumpFileName = $request->getParam( '_message');

	my @aLogEntries = split("\n", Plugins::SrvrPowerCtrl::Util::ListOurLogEntries());
	my $n = 0;

	foreach my $szEntry (@aLogEntries) {
		$request->addResult("_entry${n}", "$szEntry");
		$n++;
	}

	if (defined($dumpFileName)) {
		if (open(DUMPFILE, ">>$dumpFileName")) {
			print DUMPFILE Plugins::SrvrPowerCtrl::Util::ListOurLogEntries();
			close(DUMPFILE);
		}
	}

	$request->setStatusDone();
}

sub cliPrefsLogArchive {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my $szArchiveFileName = $request->getParam( '_message');

	my $szRet = Plugins::SrvrPowerCtrl::Util::ArchivePrefsAndLog($szArchiveFileName);

	if (!defined($szRet)) {
		$g{log}->error("Invalid name for zip file: $szArchiveFileName");
		$request->addResult('_badparam',"BadArchiveName:$szArchiveFileName");
		return $request->setStatusBadParams();
	}

	$request->addResult("zipfile", "$szRet");
	$request->setStatusDone();
}



sub cliLogSetLevel {
	my ($request) = @_;

	$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump($request));

	$request->setStatusProcessing();

	my $szLogLevel = $request->getParam( '_message');

	if (!defined($szLogLevel)) {
		$szLogLevel = Plugins::SrvrPowerCtrl::Settings::LogGetLevel();
		$request->addResult("_loglevel", "loglevel:" . $szLogLevel);
		return $request->setStatusDone();
	}

	my $bPersistent = $request->getParam('_switchclient');

	$bPersistent = !!$bPersistent;

	my ($bRet, $szNewLevel) = Plugins::SrvrPowerCtrl::Settings::LogChangeLevel($szLogLevel, $bPersistent);

	if (!$bRet) {
		#$g{log}->error("Invalid logging level: $szLogLevel");
		$request->addResult('_badparam',"BadLogLevel:$szLogLevel");
		return $request->setStatusBadParams();
	}

	$request->addResult("_loglevel", "loglevel:" . $szNewLevel);

	$request->setStatusDone();

}

# -----------------------------------------------------------------------------
# This is the SC-CLI extension offered by the plugin.  Called by CLI, SBC, etc.

sub pluginCLI {
	my ($request) = @_;
	my $client;
	my $curclient;
	my $item;
	my $action = lc($request->getParam( '_action'));
	my $message = $request->getParam( '_message');
	my $switchclient = $request->getParam('_switchclient');
	my $fromJive = $request->getParam('_fromjive');
	my $timeoutmsg;

	$client = $request->client();

	$g{log}->is_debug && $g{log}->debug("pluginCLI request == " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'id') . "->\[$action, $message, $switchclient, $fromJive\]");

	# If an action is already pending, then this is a request to cancel...
	if ($g{tPendingActionTimer}) {
		return CancelRequest($request, $client);
	}

	# Check that this is a valid request
	if( $request->isNotCommand( [['srvrpowerctrl']])) {
		$g{log}->error( "BadDispatch!");
		$request->setStatusBadDispatch();
		return;
	}

	if ($action eq 'status'){
		#Request is just asking for confirmation that SrvrPowerCtrl is enabled..
		return cliGetStatus($request);
	} elsif ($action eq 'actions' || $action eq 'help'){
		#Request is just asking for a list of the enabled actions..
		return cliGetActions($request);
	} elsif ($action eq 'setblock') {
		#check for block/clear requests..
		return cliSetBlock($request);
	} elsif ($action eq 'clearblock') {
		return cliClearBlock($request);
	} elsif ($action eq 'listblock') {
		return cliListBlock($request);
	} elsif ($action eq 'listblocks') {
		return cliListBlock($request);
	} elsif ($action eq 'getidlecount') {
		return cliGetIdleCount($request);
	} elsif ($action eq 'getidlecountdown') {
		return cliGetIdleCountDown($request);
	} elsif ($action eq 'setidlecount') {
		return cliSetIdleCount($request);
	} elsif ($action eq 'resetidlecount') {
		return cliResetIdleCount($request);
	} elsif ($action eq 'getwakealarm') {
		return cliGetNextRTCWakeAlarm($request);
	} elsif ($action eq 'setwakealarm') {
		return cliSetNextRTCWakeAlarm($request);
	} elsif ($action eq 'setpref' || $action eq 'prefset') {
		return cliPrefSet($request);
	} elsif ($action eq 'getpref' || $action eq 'prefget') {
		return cliPrefGet($request);
	} elsif ($action eq 'listprefs' || $action eq 'prefslist'  || $action eq 'dumpprefs'|| $action eq 'prefsdump') {
		return cliPrefsList($request);
	} elsif ($action eq 'setlog' || $action eq 'setloglevel' || $action eq 'logset' || $action eq 'logsetlevel'|| $action eq 'loglevel') {
		return cliLogSetLevel($request);
	} elsif ($action eq 'dumplog' || $action eq 'logdump') {
		return cliLogList($request);
	} elsif ($action eq 'zipdata') {
		return cliPrefsLogArchive($request);
	} elsif ($action eq 'test') {
		return Plugins::SrvrPowerCtrl::Util::test($request);
	}


	# Check for other allowed action items..
	$item = Plugins::SrvrPowerCtrl::Menu::findActionItem($action);
	if (!defined($item)) {
		$g{log}->error( "BadParam: $action");
		$request->addResult('_badparam' . "BadParam: $action"  );
		$request->setStatusBadParams();
		return;
	}

	#OK, this is a valid request..let's proceed..
	$request->setStatusProcessing();


	if (defined($switchclient)) {
		#$g{log}->is_debug && $g{log}->debug( "switchclient == $switchclient");
		#Make this a minimum time-out..no opportunity to cancel anyway..
		$item->{cancelwait} = 3;
		if ($switchclient eq 'sleep+hold') {
			#undefine this param...it's not really for this purpose anyway..
			$switchclient = undef;
			$g{log}->debug( "sleep+hold request from " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'name'));
		} else {
			#Is this a non-Jive CLI request to switch to SN?  If so, then $switchclient is a MAC address..
			$client = Slim::Player::Client::getClient($switchclient);
			if (Plugins::SrvrPowerCtrl::Util::IsValidClient($client)) {
				#$g{log}->debug( "client == " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'modelName') . "::" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'model') . "::\'" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'name') . "\'--\>" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'id'));
				$request->clientid($switchclient);
			} else {
				#$g{log}->debug( "client == undef");
				$client = undef;
			}
		}
	} else {
		#$g{log}->is_debug && $g{log}->debug( "switchclient == nada $switchclient");
	}

	#cue up the action..
	if (!Plugins::SrvrPowerCtrl::Plugin::prepareAction($client, $item, 0, $fromJive)) {
		$request->addResult('_action', "$action is blocked.\n");
		$request->setStatusDone();
		return;
	}

	$request->addResult('_action', $action . " in " . $item->{cancelwait} . " seconds.\n");
	$request->setStatusDone();
	#$g{hPreviousAction} = 0;
}


sub CancelRequest {
	my ($request, $client) = @_;
	my $message;

	Plugins::SrvrPowerCtrl::Plugin::cancelAction($client);

	#restore our jive menu..
	#$g{log}->is_debug && $g{log}->debug("Restoring our jive menu");
	#&addJiveMenu();

	$request->setStatusDone();
	return;
}

1;
