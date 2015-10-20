# ===============================================================================================================
#    SrvrPowerCtrl - a plugin for SqueezeCenter 7.3.x / Squeezebox Server 7.4.x
#    Allows shutdown/restart/suspend/hibernation of your Squeezebox Server
#    hardware via SBS's web interface, your Squeezebox's IR remote
#    or via a SBC / Touch / SqueezePlay.
#
#    Version 20120716.103808
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
#    Watchdog.pm -- watchdog routines..support for shutting down server if players have been idle
#                   for a user-settable time period..
#


package Plugins::SrvrPowerCtrl::Watchdog;

use base qw(Slim::Plugin::Base);
use Slim::Utils::Strings qw(string);
use strict;

use Slim::Utils::DateTime;
use Slim::Utils::Validate;

use Data::Dumper;


#Global Variables..
use Plugins::SrvrPowerCtrl::Settings ();
use Plugins::SrvrPowerCtrl::Stats;
use Plugins::SrvrPowerCtrl::lib::bQueue;

use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

#Globals for this module..
my $bUseSystemIdleWatchdog = 0;		#Used so that IdleWatchdog can be temporarily disabled..
my $nWatchdogActionDelay = 5;		#number of seconds to wait before immediate action..
my $bUseOnWakeupWatchdog = 0;		#Not indicated in prefs anymore...this gets enabled by other watchdogs..

#bQueue objects..
my $bqActivity;
my $bqEODActivity;


#sub min ($$) { $_[$_[0] > $_[1]] }

sub max ($$) { $_[$_[0] < $_[1]] }


sub ActivateWatchdogs {

	#$g{nWatchdogTimerInterval} = 20;	#number of seconds between watchdog checks..should be 60.

	# Activate the SleepPlayDone watchdog..
	ActivateSleepEndWatchdog($g{prefs}->bUseSleepEndWatchdog);

	# Activate the end-of-day idle-player watchdog..
	ActivateEODWatchdog($g{prefs}->bUseEODWatchdog);

	# Activate the SystemIdle watchdog..
	ActivateIdleWatchdog(ShouldMonitorSystem());

	# Activate the OnWakeup watchdog..
	ActivateOnWakeupWatchdog($bUseOnWakeupWatchdog);

}

sub ShouldMonitorSystem {

	#if ($g{log}->is_debug ) {
	#	$g{log}->debug(sprintf("Should Monitor System: %d", (
	#					$g{prefs}->bIdleMonitorSystem && (
	#						$g{prefs}->bIdleChkPlayers ||
	#						$g{prefs}->nIdleNetThreshold ||
	#						$g{prefs}->nIdleDisksThreshold  ||
	#						$g{prefs}->nIdleCPULoadThreshold ||
	#						length ( $g{prefs}->szIdleWatchdogCustCheck_cmd )
	#				))));
	#}

	return (
		$g{prefs}->bIdleMonitorSystem && (
			$g{prefs}->bIdleChkPlayers ||
			$g{prefs}->bIdleChkLogons ||
			$g{prefs}->bIdleChkSamba ||
			$g{prefs}->nIdleNetThreshold ||
			$g{prefs}->nIdleDisksThreshold  ||
			$g{prefs}->nIdleCPULoadThreshold ||
			length ( $g{prefs}->szIdleWatchdogCustCheck_cmd ) )
	);

}

sub ActivateIdleWatchdog {
	my $bEnable = shift;

	if (!defined($bqActivity)) {
		$bqActivity = Plugins::SrvrPowerCtrl::lib::bQueue->new($g{prefs}->nIdleWatchdogTimeout, 1, 0, 0); #queue length, fill, no-hires, no-autoread
		#$g{log}->is_debug && $g{log}->debug("bqActivity: " . Dumper($bqActivity));

	} else {
		$bqActivity->resize($g{prefs}->nIdleWatchdogTimeout, 1, 0, 0);
	}

	if ($bEnable){
		$bUseOnWakeupWatchdog = 1;
		$bUseSystemIdleWatchdog = 1;

		#Seed the system stat functions..
		($g{prefs}->bIdleWatchdogChkNet && Plugins::SrvrPowerCtrl::Stats::NetStat($g{szOS}, time()));
		($g{prefs}->bIdleWatchdogChkDisks && Plugins::SrvrPowerCtrl::Stats::DiskStat($g{szOS}, time()));


	} else {
		$bUseSystemIdleWatchdog = 0;
	}

	$g{log}->is_debug && $g{log}->debug('System idle watchdog ' . (!$bEnable ? 'de-' : '') . 'activated!');

	return $bEnable;
}


sub CueWatchdogAction {
	my $item = shift;

	#use this as an alternative to Plugins::SrvrPowerCtrl::Plugin::prepareAction() since
	# we don't need a cancel time-out in this context and we don't want to advertise too
	# heavily on the device screens..

	#Don't prepare an action if one is already pending..
	if ($g{tPendingActionTimer}) {
		$g{log}->is_debug && $g{log}->debug("Timer # $g{tPendingActionTimer} already pending.  Action " . $item->{action} . " ignored..");
		return 0;
	}

	#Temporarily disable the idle-watchdog...let the wakeup-watchdog re-enable it..
	$bUseSystemIdleWatchdog = 0;

	#cue up the requested action..
	$g{tPendingActionTimer} = Slim::Utils::Timers::setTimer( undef, time() + $nWatchdogActionDelay, \&Plugins::SrvrPowerCtrl::Plugin::performAction, ( $item ) );
	if ($g{tPendingActionTimer}) {
		$g{log}->is_debug && $g{log}->debug("Timer # $g{tPendingActionTimer} created.  Action " . $item->{action} . " is pending in $nWatchdogActionDelay seconds..");
		$item->{exeTime} = time() + $nWatchdogActionDelay;
		$g{hPendingAction} = $item;
		$g{log}->is_debug && $g{log}->debug("Pending Action: " . Data::Dump::dump($g{hPendingAction}) );
		return 1;
	}
	return 0;
}


sub GetIdleCount {
	return (	(Plugins::SrvrPowerCtrl::lib::bQueue::getbottomsetbitindex($bqActivity)), (Plugins::SrvrPowerCtrl::lib::bQueue::getbottomsetbitindex($bqEODActivity)) );
}

sub GetIdleCountDown {
	return (	($g{prefs}->nIdleWatchdogTimeout - Plugins::SrvrPowerCtrl::lib::bQueue::getbottomsetbitindex($bqActivity)), ($g{prefs}->nEODWatchdogTimeout - Plugins::SrvrPowerCtrl::lib::bQueue::getbottomsetbitindex($bqEODActivity)) );
}


#sub SetIdleCount {
#	($nIdlePlayersTimeCount, $nEODPlayersTimeCount) = @_;
#	return ($nIdlePlayersTimeCount, $nEODPlayersTimeCount);
#}

sub SetIdleCount {
	# ($nIdlePlayersTimeCount, $nEODPlayersTimeCount) = @_;
	#return ($nIdlePlayersTimeCount, $nEODPlayersTimeCount);

	my ($nIdlePlayersTimeCount, $nEODPlayersTimeCount) = @_;

	Plugins::SrvrPowerCtrl::lib::bQueue::empty($bqActivity);
	Plugins::SrvrPowerCtrl::lib::bQueue::set($bqActivity, $nIdlePlayersTimeCount);
	Plugins::SrvrPowerCtrl::lib::bQueue::empty($bqEODActivity);
	Plugins::SrvrPowerCtrl::lib::bQueue::set($bqEODActivity, $nEODPlayersTimeCount);

	return (	(Plugins::SrvrPowerCtrl::lib::bQueue::getbottomsetbitindex($bqActivity)), (Plugins::SrvrPowerCtrl::lib::bQueue::getbottomsetbitindex($bqEODActivity)) );
}


sub ResetIdleCount {
	#$nIdlePlayersTimeCount = 0;
	#$nEODPlayersTimeCount = 0;
	#return ($nIdlePlayersTimeCount, $nEODPlayersTimeCount);

	Plugins::SrvrPowerCtrl::lib::bQueue::fill($bqActivity);
	Plugins::SrvrPowerCtrl::lib::bQueue::fill($bqEODActivity);

	return (	(Plugins::SrvrPowerCtrl::lib::bQueue::getbottomsetbitindex($bqActivity)), (Plugins::SrvrPowerCtrl::lib::bQueue::getbottomsetbitindex($bqEODActivity)) );
}


#CheckIdleCondition: 1 == not idle; 0 = idle

#Idle check order of precedence:
#Block set
#Player firmware updating
#Library scanning
#Player playing
#Network interface not idle
#Hard disks not idle
#CPU load not idle
#Custom check script returns not 0

sub CheckIdleCondition {
	my $nCurTime = shift || time();
	my $bReducedCheck = shift || 0;

	#Basic idle check..
	if ( Plugins::SrvrPowerCtrl::Block::IsBlocked() ||
		Plugins::SrvrPowerCtrl::Util::AnyPlayersUpdating() ||
		Slim::Music::Import->stillScanning() ) {
		return 1;
	}
	#System monitoring check..
	if (!$bReducedCheck) {
		if (($g{prefs}->bIdleChkPlayers && Plugins::SrvrPowerCtrl::Util::AnyPlayersPlaying()) ||
			($g{prefs}->bIdleChkLogons && Plugins::SrvrPowerCtrl::Stats::IsLogonCountNotIdle()) ||
			($g{prefs}->bIdleChkSamba && Plugins::SrvrPowerCtrl::Stats::IsSambaNotIdle()) ||
			($g{prefs}->nIdleNetThreshold && Plugins::SrvrPowerCtrl::Stats::IsNetIfaceNotIdle($nCurTime)) ||
			($g{prefs}->nIdleDisksThreshold && Plugins::SrvrPowerCtrl::Stats::IsDiskNotIdle($nCurTime)) ||
			($g{prefs}->nIdleCPULoadThreshold && Plugins::SrvrPowerCtrl::Stats::IsCPUNotIdle()) ||
			(length($g{prefs}->szIdleWatchdogCustCheck_cmd) && (Plugins::SrvrPowerCtrl::Util::SystemExecCmd(undef, $g{prefs}->szIdleWatchdogCustCheck_cmd, $nCurTime))[0] )
			) {
			return 1;
		}
	}
	return 0;
}

sub IdleWatchdog {
	my $nCurTime = shift;

	my $item;
	my @clients;
	my $curclient;
	my $action;
	my $nTimeDelay;

	if (!$bUseSystemIdleWatchdog) {
		$g{log}->is_debug && $g{log}->debug("HEY! IdleWatchdog is supposed to be disabled!");
		return 0;
	}

	$bqActivity->push( CheckIdleCondition($nCurTime) );

	$g{log}->is_debug && $g{log}->debug("Activity history: " . $bqActivity->readbstr() . " System is " . ($bqActivity->getbottombit() ? "NOT idle" : "idle") . " with " . ($g{prefs}->nIdleWatchdogTimeout - $bqActivity->getbottomsetbitindex()) . " minutes left in the idle countdown..");

	#Is the system idle?
	if ( $bqActivity->isempty() ) {
		$g{log}->is_debug && $g{log}->debug("System is idle and idle timeout of $g{prefs}->nIdleWatchdogTimeout minutes has elapsed..");

		$action = $g{prefs}->szIdleWatchdogAction;
		$item = Plugins::SrvrPowerCtrl::Menu::findActionItem($action);
		if (!defined($item)) {
			$g{log}->error( "Bad IdleWatchdog Action: $action");
			return;
		}

		#cue up the requested action..
		return CueWatchdogAction( $item );

	}
	return 1;
}


sub SecondsToTimeStr {
	my $nSecs = shift || 0;

	return Slim::Utils::DateTime::secsToPrettyTime($nSecs);
}


sub TimeStrToSeconds {
	my $szTime = shift;
	my $seconds;

	if (  ( !defined($szTime) ) ||
	      ( !defined(Slim::Utils::Validate::isTime($szTime)) )
		) {
		return -1;
	}

	$seconds = Slim::Utils::DateTime::prettyTimeToSecs($szTime);

	if (!$seconds) {
		return -1;
	}

	return $seconds;
}


sub IsInEOD {
	my $nCurTime = shift || time();
	my $nEODStartSeconds;
	my $nEODEndSeconds;
	my $nNowSeconds;

	#Get the seconds since midnight..
	my ($lt_sec,$lt_min,$lt_hour) = (localtime($nCurTime))[0,1,2];

	#??Why do we need to add 1 here??
	$nNowSeconds = ($lt_hour * 3600) + ($lt_min * 60) + $lt_sec + 1;

	#calculate the nEODStartSeconds..
	$nEODStartSeconds =  TimeStrToSeconds($g{prefs}->szEODWatchdogStartTime);
	if ($nEODStartSeconds == -1) {
		return -1;
	}

	#calculate the nEODEndSeconds..
	$nEODEndSeconds =  TimeStrToSeconds($g{prefs}->szEODWatchdogEndTime);
	if ($nEODEndSeconds == -1) {
		return -1;
	}

	#my $szNowTime = SecondsToTimeStr($nNowSeconds);
	#$g{log}->is_debug && $g{log}->debug("now: $szNowTime, $nNowSeconds -- EODStart:$nEODStartSeconds, EODEnd: $nEODEndSeconds");

	#if we start before midnight and end tomorrow...
	if ( ($nEODStartSeconds > $nEODEndSeconds) && (($nNowSeconds >= $nEODStartSeconds) || ($nNowSeconds <= $nEODEndSeconds)) ) {
		return 1;
	} elsif ( ($nNowSeconds >= $nEODStartSeconds) && ($nNowSeconds <= $nEODEndSeconds) ) {
		return 1;
	}

	return 0;
}

sub TimeToStartOfEOD {
	my $nCurTime = shift || time();
	my ($lt_sec,$lt_min,$lt_hour) = localtime($nCurTime);
	my $nNowSeconds;
	my $nEODStartSeconds;

	#get the seconds since last midnight..
	$nNowSeconds = $lt_sec + ($lt_min * 60) + ($lt_hour * 3600);

	#calculate the nEODStartSeconds..
	$nEODStartSeconds =  TimeStrToSeconds($g{prefs}->szEODWatchdogStartTime);
	if ($nEODStartSeconds == -1) {
		return -1;
	}

	#if we are past start of EOD today..
	if ($nNowSeconds > $nEODStartSeconds) {
		return 86400 - $nNowSeconds + $nEODStartSeconds;
	} else {
		return $nEODStartSeconds - $nNowSeconds;
	}

	return 0;
}


#Another tweak to the EOD behavior that I'm thinking of trying is this:
#
#If the EOD idle timeout is set to zero, then the custom script gets executed just
#once within that EOD period. All other EOD idle invocations would ignore the custom
#script and fire the selected 'stock' action instead. This would allow the custom script
#to fire once and perform the big chores. Then, with SC restarted, the next EOD action
#could be a quick suspend. Thus the server would be awake for a shorter time for the chores.

my $bStartedInEOD = 0;				#Don't check EOD if we start durring EOD.

sub ActivateEODWatchdog {
	my $bEnable = shift;

	if (!defined($bqEODActivity)) {
		$bqEODActivity = Plugins::SrvrPowerCtrl::lib::bQueue->new($g{prefs}->nEODWatchdogTimeout, 1, 0, 0); #queue length, fill, no-hires, no-autoread
		#$g{log}->debug("bqEODActivity: " . Dumper($bqEODActivity));

	} else {
		$bqEODActivity->resize($g{prefs}->nEODWatchdogTimeout, 1, 0, 0);
		#$g{log}->debug("bqEODActivity: " . Dumper($bqEODActivity));
	}


	if ($bEnable) {
		$bUseOnWakeupWatchdog = 1;
	}

	$bStartedInEOD = $bEnable && IsInEOD();

	if ($bStartedInEOD && $g{log}->is_debug) {
		$g{log}->is_debug && $g{log}->debug("SrvrPowerCtrl started in EOD..");
	}

	$g{log}->is_debug && $g{log}->debug('EOD watchdog ' . (!$bEnable ? 'de-' : '') . 'activated!');

	return $bEnable;
}



#Another tweak to the EOD behavior that I'm thinking of trying is this:
#
#If the EOD idle timeout is set to zero, then the custom script gets executed just
#once within that EOD period. All other EOD idle invocations would ignore the custom
#script and fire the selected 'stock' action instead. This would allow the custom script
#to fire once and perform the big chores. Then, with SC restarted, the next EOD action
#could be a quick suspend. Thus the server would be awake for a shorter time for the chores.



sub EODWatchdog {
	my $nCurTime = shift;

	my $item;
	my @clients;
	my $curclient;
	my $action;
	my $nTimeDelay;
	my $bIsIdle = 1;

	#Check the idle condition..if idle grace is 0, use reduced idle checking.  If queue-length is zero, the idle value is pushed out immediatly.
	$bIsIdle = !$bqEODActivity->push( CheckIdleCondition($nCurTime, !$g{prefs}->nEODWatchdogTimeout) );

	$g{log}->is_debug && $g{log}->debug("EOD Activity history: [$bIsIdle] " . $bqEODActivity->readbstr());
	$g{log}->is_debug && $g{log}->debug("System is " . ($bqEODActivity->getbottombit() ? "NOT idle" : "idle") . " with " . ($g{prefs}->nEODWatchdogTimeout - $bqEODActivity->getbottomsetbitindex()) . " minutes left in the EOD idle countdown..");

	#If the system is idle..(a zero length queue will always be idle..)
	if ($bqEODActivity->isempty() && $bIsIdle) {
		#If we've transitioned into the EOD and there is a custom action..
		if (!$bStartedInEOD && ( defined($g{prefs}->szEODWatchdog_cmd) && length($g{prefs}->szEODWatchdog_cmd) > 0 )) {
			#Execute the custom command..if any.
			$action = 'specialcmd';
			$item =  ( {	action					=> $action,
							actionid				=> 0xFFFFFFFF,
							menuindex				=> -1,
							menutext				=> string('PLUGIN_SRVRPOWERCTRL_SPECIALCMD'),
							message					=> string('PLUGIN_SRVRPOWERCTRL_SPECIALCMD_MSG'),
							dispblock				=> 1,
							getcommandargcoderef	=> undef,
							poweroffplayers			=> $g{prefs}->bPowerOffPlayers,
							push2as					=> 0,
							checkblock				=> 1,
							cancelwait				=> 0,
							cmdwait					=> 5,
							refreshwait				=> -1,
							stopsc					=> 0,
							setrtcwakeup			=> Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup(),
							isSleepDefered			=> 0,
							command					=> $g{prefs}->szEODWatchdog_cmd } ) ;

		} else {
		#Else: We started in the EOD..or there is no custom action.  Execute the combobox EOD action..
			$action = $g{prefs}->szEODWatchdogAction;
			$item = Plugins::SrvrPowerCtrl::Menu::findActionItem($action);
		}

		if (!defined($item)) {
			$g{log}->error( "BadEODWatchdog Action: $action");
			return;
		}

		#cue up the requested action..
		return CueWatchdogAction( $item );

	}

	return 1;
}


my $bSleepTimerIsActive = 0;

sub SleepRequestMonitor {
	my $request = shift;
	my $client;
	my $cmd;
	my $nSleepTime;
	my $nCurrentSleepTime;

	$cmd = $request->getRequestString();

	$g{log}->is_debug && $g{log}->debug("cmd == $cmd");

	if ($cmd ne 'sleep') {
		return 0;
	}

	$client = $request->client() || return 0;

	$nSleepTime = $client->sleepTime();
	$nCurrentSleepTime = $client->currentSleepTime();

	$g{log}->is_debug && $g{log}->debug("MonitorSleepRequests called for client: ". $client->name() || 'no client' . ", cmd: $cmd, sleepTime: $nSleepTime, currentSleepTime: $nCurrentSleepTime");

	#if $nSleepTime || $nCurrentSleepTime are 0, the the user has canceled sleep..and we should cancel end of sleep action..
	if (!$nSleepTime || !$nCurrentSleepTime){
		$g{log}->is_debug && $g{log}->debug("Sleep timer canceled!");
		$bSleepTimerIsActive = 0;
		#Cancel any pending action..
		if (defined($g{tPendingActionTimer})) {
			Plugins::SrvrPowerCtrl::Plugin::cancelAction(undef, $g{hPendingAction});
		}
		ActivateSleepRequestMonitor(0);
	} else {
		$g{log}->is_debug && $g{log}->debug("Sleep timer detected!");
		$bSleepTimerIsActive = 1;
		if ( $g{tPendingActionTimer} ) {
			Plugins::SrvrPowerCtrl::Plugin::resecheduleAction(undef, $g{hPendingAction});
		}

	}

}

my $bSleepRequestMonitorIsActive = 0;

sub ActivateSleepRequestMonitor {
	my $bEnable = shift;

	if ($bEnable && !$bSleepRequestMonitorIsActive){
		Slim::Control::Request::subscribe( \&SleepRequestMonitor, [['sleep']]);
		$bSleepRequestMonitorIsActive = 1;
		$g{log}->is_debug && $g{log}->debug("SleepRequestMonitor activated!");
	} elsif (!$bEnable && $bSleepRequestMonitorIsActive) {
		Slim::Control::Request::unsubscribe( \&SleepRequestMonitor, [['sleep']]);
		$bSleepRequestMonitorIsActive = 0;
		$g{log}->is_debug && $g{log}->debug("SleepRequestMonitor deactivated!");
	}

	return $bEnable;
}

sub ActivateSleepEndWatchdog {
	my $bEnable = shift;

	$bSleepTimerIsActive = 0;

	$bUseOnWakeupWatchdog = $bEnable;

	#This was commented out.  Why?
	ActivateSleepRequestMonitor($bEnable);

	$g{log}->is_debug && $g{log}->debug('Sleep-end watchdog ' . (!$bEnable ? 'de-' : '') . 'activated!');

	return $bEnable;
}

sub SleepEndWatchdog {
	my $nCurTime = shift;
	my $action;
	my $item;
	my $nSleepTime = Plugins::SrvrPowerCtrl::SleepButton::GetSleepTime();

	if ($nSleepTime && !$bSleepTimerIsActive) {
		$bSleepTimerIsActive = 1;
		ActivateSleepRequestMonitor(1);
		return 0;
	}

	if (!$nSleepTime && $bSleepTimerIsActive) {
		#we've transitioned to end of sleep..
		$g{log}->is_debug && $g{log}->debug("End of sleep timer detected!");

		#restart the sleep timer active flag for our eventual return from suspend/hibernate/SN..
		$bSleepTimerIsActive = 0;

		#check to see that all other players are idle before taking action...
		if ( Plugins::SrvrPowerCtrl::Block::IsBlocked() || Plugins::SrvrPowerCtrl::Util::AnyPlayersPlaying() || Plugins::SrvrPowerCtrl::Util::AnyPlayersUpdating() || Slim::Music::Import->stillScanning() ) {
			$g{log}->is_debug && $g{log}->debug("Not idle condition..end-of-sleep action not taken!");
			return 0;
		}

		$action = $g{prefs}->szSleepEndWatchdogAction;

		$item = Plugins::SrvrPowerCtrl::Menu::findActionItem($action);
		if (!defined($item)) {
			$g{log}->error( "Bad SleepEndWatchdog Action: $action");
			return 0;
		}

		#Temporarily disable the idle-watchdog...let the wakeup-watchdog or the PlayRequestsMonitor re-enable it..
		$bUseSystemIdleWatchdog = 0;

		#Stop monitoring sleep requests...
		ActivateSleepRequestMonitor(0);

		#cue up the requested action..
		$g{log}->error( "SleepEndWatchdog Action: $action");
		return CueWatchdogAction( $item );
	}
	return 1;
}

my $nLastOnWakeupTimeCheck = 0;		#Last wakeup time-check..

sub ActivateOnWakeupWatchdog {
	my $bEnable = shift;

	if ($bEnable) {
		$nLastOnWakeupTimeCheck = time();
		$bUseOnWakeupWatchdog	= 1;
	} else {
		$nLastOnWakeupTimeCheck = 0;
		#We have to really, really, really mean it in order to disable this..
		if (! $g{prefs}->bUseSleepEndWatchdog &&
			! $g{prefs}->bUseEODWatchdog &&
			! ShouldMonitorSystem() &&
			! $g{prefs}->szOnWakeup_cmd ) {
			$bUseOnWakeupWatchdog	= 0;
		}
	}

	$g{log}->is_debug && $g{log}->debug('OnWakeup watchdog ' . (!$bEnable ? 'de-' : '') . 'activated!');

	return $bEnable;
}


sub OnWakeupWatchdog {
	my $nCurTime = shift || time();

	#Is this check more than 30 seconds past due? Then have we returned from a suspend or hibernation.  If time is moving backwards, then a system time change has occured.
	if ( ($nCurTime > ( $nLastOnWakeupTimeCheck + int($g{nWatchdogTimerInterval} * 1.5) )) || $nCurTime < $nLastOnWakeupTimeCheck ) {

		#Did we wakeup in the EOD?
		$bStartedInEOD = $g{prefs}->bUseEODWatchdog && IsInEOD($nCurTime);

		#reset the activity history..
		if ($bStartedInEOD) {
			$bqEODActivity->fill();
		} else {
			$bqActivity->fill();
		}

		$g{log}->info('Wakeup Call' . ($bStartedInEOD ? ' in EOD' : '') . '!!');

		#clear the previous action..
		$g{hPreviousAction} = ( );

		#perform our OnWakup cmd..
		Plugins::SrvrPowerCtrl::Util::SystemExecCmd(undef, $g{prefs}->szOnWakeup_cmd, $nCurTime);

		# Pull back any players from SqueezeNetwork that we want..
		if ($g{prefs}->bOnWakeupFetchPlayers) {
			#force SBS to refresh the list of mysb.com players 20 seconds before we try to fetch back..
			my $nDelay = max(2, $g{prefs}->nOnWakeupFetchPlayersDelay - 20);
			Slim::Utils::Timers::setTimer( undef, time() + $nDelay, \&Slim::Networking::SqueezeNetwork::Players::fetch_players, );
			$g{tPendingPullFromASTimer} = Slim::Utils::Timers::setTimer(undef, time() + $g{prefs}->nOnWakeupFetchPlayersDelay, \&Plugins::SrvrPowerCtrl::AltServer::PullFromAltServer, );
		}

	}

	#Re-activate the IdleSystem monitor if it's disabled..
	if (!$bUseSystemIdleWatchdog && ShouldMonitorSystem()) {
		ActivateIdleWatchdog(1);
	}

	$nLastOnWakeupTimeCheck = $nCurTime;

}



sub _OnTheInterval {
	my $nTimeFuture = shift || time() + $g{nWatchdogTimerInterval};
	#This corrects for timer drift..
	return $nTimeFuture + (($nTimeFuture % $g{nWatchdogTimerInterval}) < ($g{nWatchdogTimerInterval} / 2) ? - ($nTimeFuture % $g{nWatchdogTimerInterval}) : ($g{nWatchdogTimerInterval} - ($nTimeFuture % $g{nWatchdogTimerInterval})));
}

my $nSecsOffset = 0;															#Let's not always fire the timer right at the top of the interval..

sub ActivateSPCWatchdog {
	my $bEnable = shift;
	my $nDelay = shift || $g{nWatchdogTimerInterval};
	my $szTimerName = 'srvrpowerctrl.watchdog';
	my $szParamValue = 'multi.check';

	my $nTime = time();

	if ($bEnable) {
		$nSecsOffset = ( $g{log}->is_debug ? 0 : int(rand(11)) );				#Fire sometime between 0 and 10 of the offset..
		$g{tSPCWatchdogTimer} = Slim::Utils::Timers::setTimer($szTimerName, _OnTheInterval($nTime + $g{nWatchdogTimerInterval}) + $nSecsOffset, \&SPCWatchdog, ($szParamValue), );
	} else {
		if (defined($g{tSPCWatchdogTimer})) {
			Slim::Utils::Timers::killSpecific($g{tSPCWatchdogTimer});
			$g{tSPCWatchdogTimer} = 0;
		}

		if (defined($g{tPendingActionTimer})) {
			Slim::Utils::Timers::killSpecific($g{tPendingActionTimer});
			$g{tPendingActionTimer} = 0;
		}
	}
}



#This is the main timer routine that checks the various watchdog conditions..
sub SPCWatchdog {
	my ($szTimerName, @args) = @_;
	my $nCurTime = time();
	my $szCommand;
	my $nIdleFailSafe;

	#$g{log}->is_debug && $g{log}->debug("$szTimerName, $param1");

	#Only check watchdogs if we aren't waiting for a cancel action..
	if ( !$g{tPendingActionTimer} || $g{hPendingAction}->{isSleepDefered} ) {

		#clear the previous action..
		$g{hPreviousAction} = ( );

		#Check our OnWakekup conditions..
		if ( $bUseOnWakeupWatchdog ) {
			OnWakeupWatchdog($nCurTime);
		}

		#Check the SleepDone watchdog..
		if ( $g{prefs}->bUseSleepEndWatchdog ) {
			SleepEndWatchdog($nCurTime);
		}

		#Check the End-of-day watchdog..
		if ( $g{prefs}->bUseEODWatchdog && IsInEOD($nCurTime) ) {
			EODWatchdog($nCurTime);
		} else {
		#Check SystemIdleWatchdog..
			#reset the skip flag for next EOD
			$bStartedInEOD = 0;
			#Check the OnIdle watchdog..but not if it's been temporarily disabled..
			if ( $bUseSystemIdleWatchdog ) {
				IdleWatchdog($nCurTime);
			}
		}
	} else {
		#prevent spurious wake-up detects..
		$g{log}->is_debug && $g{log}->debug("Skipped watchdog check..");
		$nLastOnWakeupTimeCheck = $nCurTime;
	}

	#Schedule next check..
	$g{tWatchdogTimer} = Slim::Utils::Timers::setTimer($szTimerName, _OnTheInterval($nCurTime + $g{nWatchdogTimerInterval} - $nSecsOffset) + $nSecsOffset, \&SPCWatchdog, @args, );
}

1;
