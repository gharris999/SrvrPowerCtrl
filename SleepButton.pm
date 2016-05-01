# ===============================================================================================================
#    SrvrPowerCtrl - a plugin for SqueezeCenter 7.3.x / Squeezebox Server 7.4.x
#    Allows shutdown/restart/suspend/hibernation of your Squeezebox Server
#    hardware via SBS's web interface, your Squeezebox's IR remote
#    or via a SBC / Touch / SqueezePlay.
#
#    Version 20160501.151506
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
#    SleepButton.pm -- access to SrvrPowerCtrl menu via sleep+hold
#
#    Thanks to Peter Watkins for suggesting this feature and supplying the code!
#

package Plugins::SrvrPowerCtrl::SleepButton;

use base qw(Slim::Plugin::Base);
use strict;

use Slim::Utils::Strings qw(string);
#use Slim::Player::Client;

#Global Variables..
use Plugins::SrvrPowerCtrl::Settings ();
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

use Plugins::SrvrPowerCtrl::Util;

sub GetSleepTime {
	my $sleeptime;
	my $cursleeptime;
	my $curtime;
	my @clients;
	my $curclient;

	#sleeping without playing...why wait?
	#if (!Plugins::SrvrPowerCtrl::Util::AnyPlayersPlaying()) {
	#	return 0;
	#}

	$sleeptime = 0;
	$curtime = time();

	@clients = Slim::Player::Client::clients();

	#find the longest outstanding sleep time...
	foreach $curclient (@clients) {
		$cursleeptime = int( $curclient->sleepTime() - $curtime );

		if ($sleeptime < $cursleeptime) {
			$sleeptime = $cursleeptime;
		}
	}

	if ($sleeptime > 0) {
		$sleeptime += 1;
		#$g{log}->is_debug && $g{log}->debug( "Setting Defer time == " . $cursleeptime . " from " . $curclient->name() );
	}

	return $sleeptime;
}

my $bSleepIsHooked = 0;

sub HookSleepButton {
	my ($bEnable) = @_;

	if ($bEnable) {
		if (!$bSleepIsHooked) {
			my $mode = 'PLUGIN.SrvrPowerCtrl::Plugin';
			Slim::Buttons::Common::addMode($mode, Plugins::SrvrPowerCtrl::Plugin::getFunctions(), \&Plugins::SrvrPowerCtrl::Plugin::setMode);
			Slim::Control::Request::subscribe( \&newPlayerCheck, [['client']],['new']);
			#$bSleepIsHooked = 1;
		}
	} else {
		if ($bSleepIsHooked) {
			Slim::Control::Request::unsubscribe( \&newPlayerCheck, [['client']],['new']);
			#$bSleepIsHooked = 0;
		}
	}

	$g{log}->is_debug && $g{log}->debug('Sleep+hold hook ' . ($bEnable ? '' : 'de-') . 'activated!');

	return !$bSleepIsHooked;
}

sub ChangeSleepHoldButtonHandlers {
	my ($bEnable) = @_;
	my @clients;
	my $curclient;

	@clients = Slim::Player::Client::clients();

	if ($bEnable) {
		if (!$bSleepIsHooked) {
			foreach $curclient (@clients) {
				if (Plugins::SrvrPowerCtrl::Util::IsVFDClient($curclient)) {
					mapKeyHold($curclient, 'sleep', 'modefunction_PLUGIN.SrvrPowerCtrl::Plugin->ourSleepHoldButtonHandler');
					$bSleepIsHooked = 1;
				}
			}
		}
	} else {
		if ($bSleepIsHooked) {
			foreach $curclient (@clients) {
				if (Plugins::SrvrPowerCtrl::Util::IsVFDClient($curclient)) {
					mapKeyHold($curclient, 'sleep', 'dead');
					$bSleepIsHooked = 0;
				}
			}
		}
	}

	#$g{log}->is_debug && $g{log}->debug('Sleep+hold hook ' . (($bEnable && $bSleepIsHooked) ? '' : 'de-') . 'activated!');

	return $bSleepIsHooked;
}

#sub GetDefSleepBtnProc {
#	$gfuncDefSleepBtn = $Slim::Buttons::Common::functions{'sleep'};
#}

sub oursleepButtonHandler {
    return Plugins::SrvrPowerCtrl::Plugin::setMode( {}, shift, 'push' );
}

sub ourSleepHoldButtonHandler {
	my ($client) = @_;
	my $action;

	$g{log}->is_debug && $g{log}->debug("shit+hold pressed..");

	if ( !$g{prefs}->bHookSleepButton ) {
		return;
	}

	$action = $g{prefs}->szSleepButtonAction;

	if ($action  eq 'plugin_menu') {
		if (Plugins::SrvrPowerCtrl::Util::IsValidClient($client)) {
			return oursleepButtonHandler( $client );
		}
	}

	my $msg = 'PLUGIN_SRVRPOWERCTRL_' . uc($action) . '_MSG';

	$g{log}->is_debug && $g{log}->debug("msg == " . $msg );

	$client->execute(['srvrpowerctrl', $action, string($msg), 'sleep+hold']);
}

#== From peterw's AllQuiet plugin: xxx+hold mapping support =================================================================================

sub newPlayerCheck {
	my ($request) = @_;
	#$g{log}->is_debug && $g{log}->debug("request: " . Data::Dump::dump(\$request));

	my $client = $request->client();

	#$g{log}->is_debug && $g{log}->debug(Plugins::SrvrPowerCtrl::Util::ClientSpec($client));

	#Only map players that have a VFD display..& don't mess with players that need a firmware upgrade..
	if ( $request->{_requeststr} eq "client,new" && Plugins::SrvrPowerCtrl::Util::IsVFDClient($client) && !$client->needsUpgrade()) {
	#if ( $request->{_requeststr} eq "client,new" && !$client->needsUpgrade()) {
		Slim::Utils::Timers::setTimer($client, time() + 2, \&mapKeyHold, 'sleep', 'modefunction_PLUGIN.SrvrPowerCtrl::Plugin->ourSleepHoldButtonHandler');
		$bSleepIsHooked = 1;
	}

	return $bSleepIsHooked;
}

sub mapKeyHold {
	my ($client, $baseKeyName, $function) = @_;
	my $mapsAltered = 0;

	#$g{log}->is_debug && $g{log}->debug( "Client is a: modelName: [" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'modelName') . "] model: [" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'model') . "] name: [" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'name') . "] id: [" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'id') . "] deviceid: [" . $client->deviceid . "]");
	#Plugins::SrvrPowerCtrl::Util::logArgs(@_);

	$g{log}->is_debug && $g{log}->debug( "Client: " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'name') . '(' . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'modelName') . "), baseKeyName: $baseKeyName, function: $function");


	#if ($::VERSION lt '7.1') {
	#if ( $g{nSCVersion} < 7.1 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	if (Slim::Utils::Versions::compareVersions($::VERSION , '7.1') < 0) {
		my $commonHoldFn = Slim::Hardware::IR::lookupFunction($client,$baseKeyName.'.hold','common');
		if ( (!defined($commonHoldFn)) || ($commonHoldFn ne $function) ) {
			$g{log}->fatal("You must manually edit the IR Default.map file in SqueezeCenter 7.0 to use ${baseKeyName}.hold for $function");
		}
		return;
	}

	my @maps  = @{$client->irmaps};

	for (my $i = 0; $i < scalar(@maps) ; ++$i) {
		if (ref($maps[$i]) eq 'HASH') {
			my %mHash = %{$maps[$i]};
			foreach my $key (keys %mHash) {
				if (ref($mHash{$key}) eq 'HASH') {
					my %mHash2 = %{$mHash{$key}};
					# if no $baseKeyName.hold
					if ( ($function eq 'dead' || !defined($mHash2{$baseKeyName.'.hold'})) || ($mHash2{$baseKeyName.'.hold'} eq 'dead') ) {
						#$g{log}->is_debug && $g{log}->debug("mapping $function to ${baseKeyName}.hold for $i-$key");
						if ( (defined($mHash2{$baseKeyName}) || (defined($mHash2{$baseKeyName.'.*'}))) &&
						     (!defined($mHash2{$baseKeyName.'.single'})) ) {
							# make baseKeyName.single = baseKeyName
							$mHash2{$baseKeyName.'.single'} = $mHash2{$baseKeyName};
						}
						# make baseKeyName.hold = $function
						$mHash2{$baseKeyName.'.hold'} = $function;

						#For SP-based players..
						#if (Plugins::SrvrPowerCtrl::Util::IsSPClient($client)) {
						#	$mHash2{$baseKeyName.'.hold_release'} = $function;
						#}

						# make baseKeyName.repeat = "dead"
						$mHash2{$baseKeyName.'.repeat'} = 'dead';
						# delete unqualified baseKeyName
						$mHash2{$baseKeyName} = undef;
						# delete baseKeyName.*
						$mHash2{$baseKeyName.'.*'} = undef;
						++$mapsAltered;
					}
					#} else {
					#	$g{log}->is_debug && $g{log}->debug("${baseKeyName}.hold mapping already exists for $i-$key");
					#}
					$mHash{$key} = \%mHash2;
				}
			}
			$maps[$i] = \%mHash;
		}
	}
	if ( $mapsAltered > 0 ) {
		$client->irmaps(\@maps);
		$g{log}->is_debug && $g{log}->debug('Mapping ' . $client->name() . "::" . $client->model() . "::" . $client->deviceid . "::" . $client->id() . "\'s ${baseKeyName}.hold to $function for $mapsAltered modes.");
		#$g{log}->is_debug && $g{log}->debug($client->name() . " ir maps: " . Data::Dump::dump(\@maps));
	}

	#does someone else already own sleep+hold?
	#if ($mapsAltered eq 0) {
	#	$g{prefs}->set('bHookSleepButton', 0 );
	#}
}



1;
