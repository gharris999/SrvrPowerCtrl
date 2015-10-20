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
#    Alarms.pm -- support for setting RTC to wake up server for next alarm
#


package Plugins::SrvrPowerCtrl::Alarms;

use base qw(Slim::Plugin::Base);
use strict;

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Time::Local;
use Time::Zone;

use Plugins::SrvrPowerCtrl::lib::CronEvents;


#Global Variables..
use Plugins::SrvrPowerCtrl::Settings ();
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;


sub getClientAlarms {
	my $clientmac = shift;
	my $prefname;
	my $serverprefs;
	my $clientprefs;
	my $alarms;			#reference to hash of alarms..
	my $num = 0;

	#not sure why we need to do this...
	$serverprefs = preferences('server');

	$prefname = "_client:" . $clientmac;

	#$g{log}->is_debug && $g{log}->debug("Loading saved alarms from prefs for $prefname..");
	$clientprefs = $serverprefs->get($prefname);

	if (!defined($clientprefs)) {
		$g{log}->error("Can not get prefs for client $clientmac..");
		return undef;
	}

	$alarms = $clientprefs->{'alarms'};

	if (!defined($alarms)){
		$g{log}->is_debug && $g{log}->debug("No alarms for $clientmac..");
		return undef;
	} else {
		#$g{log}->is_debug && $g{log}->debug("Alarms loaded for $clientmac..");
		#This seems to be important...don't know why, though..
		while( my ($k, $v) = each %$alarms) {
			$num++;
		}

	}

	return $alarms;
}

sub getNextAlarmTime {
	my $alarms = shift;			#reference to hash of alarms..
	my $baseTime = shift;
	my $alarmOwner = shift;
	my $alarmID;
	my $alarm;
	my $nAlarmTime;
	my $nNextAlarmTime;

	$nAlarmTime = 0;
	$nNextAlarmTime = 0;

	#$g{log}->is_debug && $g{log}->debug("Calculating next alarm time for $alarmOwner..");

	while ($alarmID = each %$alarms) {
		#$g{log}->is_debug && $g{log}->debug("Trying to get alarmID $alarmID..");
		$alarm = $alarms->{$alarmID};

		if (!defined($alarm)){
			$g{log}->error("Can't get alarm for alarmID $alarmID..");
			next;
		}

		#adapted from Max's Slim::Utils::Alarms code..
		if (defined $alarm->{_days}) {

			# Convert base time into a weekday number and time
			my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)  = localtime($baseTime);

			# Find the first enabled alarm starting at baseTime's day num
			my $day = $wday;

			for (my $i = 0; $i < 7; $i++) {
				if ($alarm->{_days}[$day]) {
					# alarm is enabled for this day, which is $day days away from $baseTime

					# work out how far $baseTime is from midnight on that day
					my $baseTimeSecs = $min * 60 + $hour * 3600;
					# alarm is next if it's not in the same day as base time or is >= basetime
					if ($i > 0 || $baseTimeSecs <= $alarm->{_time}) {
						# alarm time in seconds since midnight on base time's day
						my $relAlarmTime = $alarm->{_time} + $i * 86400;
						my $absAlarmTime = $baseTime - $baseTimeSecs + $relAlarmTime;

						#$g{log}->is_debug && $g{log}->debug("Potential next time found: $absAlarmTime..");

						if (!$nAlarmTime || $nAlarmTime > $absAlarmTime) {
							$nAlarmTime = $absAlarmTime;

						}
					}
				}
				# Move on to the next day, wrapping round to the start of the week as necessary
				$day = ($day + 1) % 7;
			}

		} else {
		# This is a calendar alarm so _time is already absolute
			$nAlarmTime = $alarm->{_time};
		}

		#$g{log}->is_debug && $g{log}->debug("Next alarm time for alarm $alarmID == $nAlarmTime..");

		if (!$nNextAlarmTime || $nNextAlarmTime > $nAlarmTime){
			$nNextAlarmTime = $nAlarmTime;
		}

	}

	#$g{log}->is_debug && $g{log}->debug("Next alarm time for $alarmOwner == $nNextAlarmTime..");

	return $nNextAlarmTime;
}




sub IsDSTChangePending {
	my ($nStartDate, $nEndDate) = @_;

	my $isdst1 = (localtime($nStartDate))[8];
	my $isdst2 = (localtime($nEndDate))[8];

	if ($isdst1 != $isdst2) {
		$g{log}->is_debug && $g{log}->debug ( "DST change is pending! $nStartDate isDST: $isdst1 vs. $nEndDate isDST: $isdst2");
		if ($isdst2) {
			return 1;	#Spring ahead..
		} else {
			return -1;	#Fall back...
		}
	}
	return 0;
}

sub GetNextAlarm {
	my $alarms;		#hash referenct to the alarms..
	#my $curAlarm;
	my $nAlarmTime;
	my $szAlarmClientID;
	my $szAlarmClientName;
	my $nNextAlarmTime;
	my $szNextAlarmClientID;
	my $szNextAlarmClientName;
	my $nTime = time();

#	$g{log}->is_debug && $g{log}->debug ( "The current time is: " . $nTime . " == " . Slim::Utils::DateTime::shortDateF($nTime) . " " . Slim::Utils::DateTime::timeF($nTime) . "..");

	$nAlarmTime = 0;
	$nNextAlarmTime = 0;

	# Work out current time rounded down to the nearest minute
	$nTime = $nTime - $nTime % 60;

	#Alarms for connected players..
	foreach my $client (Slim::Player::Client::clients()) {

		$szAlarmClientID = eval{$client->id()} || 'no id';
		$szAlarmClientName = eval{$client->name()} || 'no client';

		my $curAlarm = Slim::Utils::Alarm->getNextAlarm($client, 1);
		if (defined($curAlarm)){

			$nAlarmTime = $curAlarm->findNextTime($nTime);
			#$g{log}->is_debug && $g{log}->debug("$szAlarmClientName:$szAlarmClientID next alarm time == $nAlarmTime..");

			if ( $nAlarmTime && ((!$nNextAlarmTime) || ($nNextAlarmTime > $nAlarmTime)) ) {
				$nNextAlarmTime = $nAlarmTime;
				$szNextAlarmClientID = $szAlarmClientID;
				$szNextAlarmClientName = $szAlarmClientName;
			}
		}
	}


	#check the SqueezeNetwork connected players too..
	my @aSNPlayers = Slim::Networking::SqueezeNetwork::Players->get_players();
	foreach my $player (@aSNPlayers ) {

		$szAlarmClientID = $player->{mac};
		$szAlarmClientName = $player->{name};

		$alarms = getClientAlarms($szAlarmClientID);
		if (defined($alarms)){

			$nAlarmTime = getNextAlarmTime($alarms, $nTime, $szAlarmClientName);
			$g{log}->is_debug && $g{log}->debug("SN $szAlarmClientName next alarm time == $nAlarmTime..");

			#if ( (!$nNextAlarmTime) || ($nNextAlarmTime > $nAlarmTime) ) {
			if ( $nAlarmTime && ((!$nNextAlarmTime) || ($nNextAlarmTime > $nAlarmTime)) ) {
				$nNextAlarmTime = $nAlarmTime;
				$szNextAlarmClientID = $szAlarmClientID;
				$szNextAlarmClientName = $szAlarmClientName;
			}
		}
	}


	if ($nNextAlarmTime) {
		$g{log}->is_debug && $g{log}->debug ( "The next alarm belongs to $szNextAlarmClientName:$szNextAlarmClientID scheduled for $nNextAlarmTime [" . Slim::Utils::DateTime::shortDateF($nNextAlarmTime) . " " . Slim::Utils::DateTime::timeF($nNextAlarmTime) . "]");
	} else {
		$g{log}->is_debug && $g{log}->debug ( "No alarms pending..");
	}

	#return the alarm time of the next alarm and the mac address of it's owner..
	return $nNextAlarmTime, $szNextAlarmClientID;
}


# GetRescanTime:  returns the number of seconds until the next scheduled library rescan
#  as set by the Rescan Music Library plugin. We treat any enabled, scheduled rescans
#  as an alarm for which we need to wake.

sub GetRescanTime {
	my $nCurTime = shift || time();
	my ($lt_sec,$lt_min,$lt_hour) = localtime($nCurTime);
	my $nNowSeconds;
	my $nNextScanTime;
	my $prefsRescan;

	$prefsRescan = preferences('plugin.rescan');

	#Any rescan scheduled?
	if ( !$prefsRescan->get('scheduled') ) {
		return 0;
	}

	#get the seconds since last midnight..
	$nNowSeconds = $lt_sec + ($lt_min * 60) + ($lt_hour * 3600);

	#get the next scan time
	$nNextScanTime =  $prefsRescan->get('time');
	if (!$nNextScanTime) {
		return 0;
	}

	#if we are past start of the scheduled rescan today..
	if ($nNowSeconds > $nNextScanTime) {
		return 86400 - $nNowSeconds + $nNextScanTime;
	} else {
		return $nNextScanTime - $nNowSeconds;
	}

	return 0;
}

sub GetCronEventTime {
	my $nCurTime = shift || time();

    my $bHasFuture = 0;
    my $nNextEpoch = 9999999999;
    my $szNextDate;
    my $szLine;
    my $szCmd;

    # sbs user must have permissions to list root's crontab in /etc/sudoers
    # squeezeboxserver ALL = NOPASSWD: /usr/bin/crontab -l

    my @crontab = `sudo crontab -l`;

    foreach my $line (@crontab) {

        my $obj = Plugins::SrvrPowerCtrl::lib::CronEvents->new($line) || next;

        $obj->setCounterToNow();

        my @event = ($obj->nextEvent);

        my $epoch = timelocal(@event);

        if ($epoch < $nNextEpoch) {
            $bHasFuture = 1;
            $szLine = $line;
            $nNextEpoch = $epoch;
            $szNextDate = localtime( timelocal(@event) );
            $szCmd = $obj->commandLine;
            $g{log}->is_debug && $g{log}->debug ( "Found crontab event $line -- scheduled for $nNextEpoch, $szNextDate");
        }

        $obj->resetCounter;

    }

    if ($bHasFuture) {
		$g{log}->is_debug && $g{log}->debug ( "Crontab $szLine scheduled for $nNextEpoch, $szNextDate");
        return $nNextEpoch;
    }

	$g{log}->is_debug && $g{log}->debug ( "No root crontab events..");
    return 0;
}

sub GetRTCWakeupTime {
	my $nCurTime = shift || time();
	my $nEODStartTime;
	my $nRescanTime;
    my $nCrontabTime;
	my $bNeedDSTAdjustment;
    my $nRTCWakeupTime = 0;
    my $szOwnerID;

	# Get the next alarm time..
    if ($g{prefs}->bSetRTCWakeForAlarm) {
        ($nRTCWakeupTime, $szOwnerID) = GetNextAlarm();
    }

	# Check to see if we are monitoring EOD..
	if ($g{prefs}->bUseEODWatchdog && $g{prefs}->bSetRTCWakeForEOD) {
		#Check the EOD action: if it's a custom script OR if NOT idle monitoring OR if the EOD on-idle action != the regular on-idle action, then treat the EOD as an alarm..
		#Change prompted by discussion with rickwookie about eliminating useless wake-ups..
		if ( (defined($g{prefs}->szEODWatchdog_cmd) && length($g{prefs}->szEODWatchdog_cmd) > 0) ||
			 (!Plugins::SrvrPowerCtrl::Watchdog::ShouldMonitorSystem() ? 1 : ($g{prefs}->szEODWatchdogAction ne $g{prefs}->szIdleWatchdogAction)) ) {

			$nEODStartTime = $nCurTime + Plugins::SrvrPowerCtrl::Watchdog::TimeToStartOfEOD($nCurTime);

			if (!$nRTCWakeupTime || $nEODStartTime < $nRTCWakeupTime) {
				$g{log}->is_debug && $g{log}->debug ( "EOD start at $nEODStartTime == " . Slim::Utils::DateTime::shortDateF($nEODStartTime) . " " . Slim::Utils::DateTime::timeF($nEODStartTime) . " will be used as next alarm time..");
				$nRTCWakeupTime = $nEODStartTime;
			}

		}
	}

	# Check the rescan.prefs file for scheduled rescans...wake up for that too..
    if ($g{prefs}->bSetRTCWakeForRescan) {
        $nRescanTime = GetRescanTime($nCurTime);
        if ($nRescanTime) {
            $nRescanTime += $nCurTime;
            if (!$nRTCWakeupTime || $nRescanTime < $nRTCWakeupTime) {
                $g{log}->is_debug && $g{log}->debug ( "Rescan scheduled for $nRescanTime == " . Slim::Utils::DateTime::shortDateF($nRescanTime) . " " . Slim::Utils::DateTime::timeF($nRescanTime) . " will be used as next alarm time..");
                $nRTCWakeupTime = $nRescanTime;
            }
        }
    }

    # Finally, check the crontab for an event to wake up for..
    if ($g{prefs}->bSetRTCWakeForCrontab) {
        $nCrontabTime = GetCronEventTime($nCurTime);
        if ($nCrontabTime) {
            if (!$nRTCWakeupTime || $nCrontabTime < $nRTCWakeupTime) {
                $g{log}->is_debug && $g{log}->debug ( "Crontab event scheduled for $nCrontabTime == " . Slim::Utils::DateTime::shortDateF($nRescanTime) . " " . Slim::Utils::DateTime::timeF($nCrontabTime) . " will be used as next alarm time..");
                $nRTCWakeupTime = $nCrontabTime;
            }
        }
    }

	if (!$nRTCWakeupTime) {
		return 0;
	}


	# Adjust for daylight savings time change...should only happen twice a year..
	$bNeedDSTAdjustment = IsDSTChangePending($nCurTime, $nRTCWakeupTime);

	if ($bNeedDSTAdjustment > 0) {
		#Spring ahead: night is 1 hour shorter, so wake up an hour earlier..
		$g{log}->is_debug && $g{log}->debug ( "Spring ahead: adjusting wakeup time to an hour earlier..");
		$nRTCWakeupTime -= 3600;
	} elsif ($bNeedDSTAdjustment < 0) {
		#Fall back: night is 1 hour longer, so wake up an hour later..

		#If the next alarm is between 24 hours and 23 hours in the future..
		#..schedule wakeup for today instead.
		if ( ($nRTCWakeupTime <= ($nCurTime + 86400)) &&
		     ($nRTCWakeupTime >  ($nCurTime + 82800)) ) {
			$nRTCWakeupTime -= 86400;
		}

		$g{log}->is_debug && $g{log}->debug ( "Fall Back: adjusting wakeup time to an hour later..");
		$nRTCWakeupTime += 3600;
	}

	#Shave time off the advance time for our wakeup time..
	$nRTCWakeupTime -= $g{prefs}->{nRTCWakeupAdvance} * 60;

	# Round down to the nearest minute
	$nRTCWakeupTime -= $nRTCWakeupTime % 60;

	return $nRTCWakeupTime;
}

sub ShouldSetRTCWakeup {
    return ( $g{prefs}->bSetRTCWakeForAlarm | $g{prefs}->bSetRTCWakeForEOD | $g{prefs}->bSetRTCWakeForRescan | $g{prefs}->bSetRTCWakeForCrontab );
}

sub SetRTCWakeup {
	$g{log}->is_debug && $g{log}->debug ( "SetRTCWakeForAlarm called..");
	my $nTime = time();

	my $nRTCWakeupTime = shift || GetRTCWakeupTime($nTime);
	my $nRet = 0;
	my $szCommand;

	#No alarms pending?
	if (!$nRTCWakeupTime) {
		$g{log}->is_debug && $g{log}->debug ( "No alarms pending..");
		return 0;
	}

	# If for whatever reason our pending wakeup time is in the past..
	if ($nRTCWakeupTime <= $nTime) {
		$g{log}->is_debug && $g{log}->debug ( "Alarm time of $nRTCWakeupTime (" . Slim::Utils::DateTime::timeF($nRTCWakeupTime, "%Y-%m-%d %H:%M:%S") . ") is already in the past!  It is now $nTime (" . Slim::Utils::DateTime::timeF($nTime, "%Y-%m-%d %H:%M:%S") . ") ..");

		# If the pending action isn't something that we can immediatly return from, cancel the action..
		if ($g{tPendingActionTimer} && $g{hPendingAction} && $g{hPendingAction}->{action} =~ m/^\w+(shutdown|suspend|hibernate).*$/) {
			$g{log}->is_debug && $g{log}->debug ( "Canceling pending action: " . $g{hPendingAction}->{action} . " " . $g{hPendingAction}->{menutext});
			Slim::Utils::Timers::killSpecific($g{tPendingActionTimer});
			$g{tPendingActionTimer} = 0;
			$g{hPendingAction} = 0;
		}

		return 0;
	}

	$szCommand = $g{prefs}->szSetRTCWake_cmd;

	if (defined($szCommand)) {
		$g{log}->is_debug && $g{log}->debug ( "Setting system wakeup for $nRTCWakeupTime -- " . Slim::Utils::DateTime::timeF($nRTCWakeupTime, "%Y-%m-%d %H:%M:%S") );
		$nRet = Plugins::SrvrPowerCtrl::Util::SystemExecCmd(undef, $szCommand, $nRTCWakeupTime);
	}

	return $nRTCWakeupTime ;
}


1;
