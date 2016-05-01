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
#    Settings.pm -- Settings & prefs routines..
#

package Plugins::SrvrPowerCtrl::Settings;


use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Validate;
use Slim::Utils::OSDetect;
use Slim::Utils::Strings qw(string);
use Plugins::SrvrPowerCtrl::Util;


#use File::Spec::Functions qw(:ALL);
#use File::Basename;


if ($^O =~ /^m?s?win/i) {		## Are we running windows?
	eval {
		require Win32;
		import Win32;
		#Hide any child console windows!
		Win32::SetChildShowWindow(0)
			if defined &Win32::SetChildShowWindow
	} ;
}

# Global var hash.  Accessed by all modules in the plugin..

use vars qw(%g);

%g = (
	nAppVersion				=> 20160501.151506,											#version of this code..
	szAppPath				=> Plugins::SrvrPowerCtrl::Util::GetPluginPath(),			#Where the heck are we, anyway?
	nSCVersion				=> Plugins::SrvrPowerCtrl::Util::GetSCVersion(),			#Version of SC/SBS/LMS.
	szSCUser				=> Plugins::SrvrPowerCtrl::Util::GetSCUser(),				#User account we're running under.
	szOS					=> Slim::Utils::OSDetect::OS(),								#Operating system we're running on..
	szDistro				=> Plugins::SrvrPowerCtrl::Util::GetOSDistro(),				#OS sub-type..
	szServerMAC				=> Plugins::SrvrPowerCtrl::Util::GetServerMacAddress(),		#MAC address of the server..
	aBlockAction			=> [ ],														#Array of block action hashes.. [ ] vs. () is important here to reserve the data space, apparently..
	aActions				=> [ ], 													#Array of action/menu/message/command hash items
	hPendingAction			=> ( ),														#Hash of pending action...
	hPreviousAction			=> ( ),														#Previous action...
	log						=> undef,													#log hash
	prefs					=> undef,													#preferences
	nWatchdogTimerInterval	=> 60,														#Watchdog timer fires every x seconds..
	tSPCWatchdogTimer		=>  0,														#our timer ID so we can kill it
	tPendingActionTimer		=>  0,														#timer ID of the pending action...so we can kill it on cancel..
	tPendingPullFromASTimer =>  0,														#timer ID of the pending fetch actcion..
);

#pref names must be in Hungarian notation for generic validation to work.
#pref name prefix == data type and determines type of validation:
#'a' == array
#'b' == boolian (i.e. checkbox value)
#'n' == numeric (i.e. int)
#'sz' == string, null terminated

#my @aPrefNames ;	#Array of pref names -- doesn't include 'hidden' prefs..

#Hash of pref names and default values.  Some values are OS dependent..

my %hPrefDefaults = (

					#Basic Commands---------------------------------------------
						'bInclude_Shutdown'				=>	1,
						'bInclude_Shutdown2AS'			=>	1,
						'szShutdown_cmd'				=>	"",
						'bInclude_Suspend'				=>	1,
						'bInclude_Suspend2AS' 			=>	1,
						'szSuspend_cmd'					=>	"",
						'bInclude_Hibernate'			=>	1,
						'bInclude_Hibernate2AS'			=>	1,
						'szHibernate_cmd'				=>	"",
						'bInclude_Reboot'				=>	1,
						'szReboot_cmd'					=>	"",
						'bInclude_SCRestart'			=>	1,
						'szSCRestart_cmd'				=>	"cli://restartserver",
						'bInclude_WebInterface'			=>	1,

					#Custom Commands:-------------------------------------------
						#'aCustCmds'						=>	"",				#array of user defined commands...

					#Command Tweaks:--------------------------------------------
						'nRegretDelay'					=>	15,
						'szOnXShutdown_cmd'				=>	"",
						'bPowerOffPlayers'				=>	1,

					#Alternate Server:------------------------------------------
						'szAltServerName'				=>	Slim::Networking::SqueezeNetwork->get_server('sn'),
						'nAltServerPostPushDelay'		=>	30,					#amount of time to wait after pushing players before taking action..
						'bAltServerPushAll'				=>	0,					#Push ALL connected players to the alt server
						'bAltServerUnSyncLocal'			=>	1,					#Perform an unsync before pushing to the alternate server..
						'bAltServerPowerOffPlayers'		=>	1,					#Send a json client power 0 request to the alternate server..
						'szAltServerPushMACs'			=>	"",					#Mac addrs of specific players to push..
						'bAltServerPushOnXShutdown'		=>	0,					#Push players on 'external' plugin shutdown..

					#System Idle Monitor----------------------------------------
						'bIdleMonitorSystem'			=>	1,
						'bIdleChkPlayers'				=>	1,
						'bIdleChkLogons'				=>	1,
						'bIdleChkSamba'					=>	1,
						'nIdleNetThreshold'				=>	1024,
						'nIdleDisksThreshold'			=>	0,
						'nIdleCPULoadThreshold'			=>	0,
						'nIdleWatchdogTimeout'			=>	45,
						'szIdleWatchdogAction'			=>	'suspend',
						'szIdleWatchdogCustCheck_cmd'	=>	"",

					#End of Day-------------------------------------------------
						'bUseEODWatchdog'				=>	0,
						'nEODWatchdogTimeout',			=>	10,
						'szEODWatchdogStartTime'		=>	"00:30",
						'szEODWatchdogEndTime'			=>	"05:00",
						'szEODWatchdogAction'			=>	'shutdown',
						'szEODWatchdog_cmd'				=>	"",

					#Sleep Settings---------------------------------------------
						'bHookSleepButton'				=>	1,
						'szSleepButtonAction'			=>	'plugin_menu',
						'bUseSleepEndWatchdog'			=>	1,
						'szSleepEndWatchdogAction'		=>  'suspend',

					#Alarm Interactions-----------------------------------------
						'bSetRTCWakeForAlarm'			=>	1,
						'bSetRTCWakeForEOD'				=>  1,
						'bSetRTCWakeForRescan'			=>	1,
						'bSetRTCWakeForCrontab'			=>	0,
						'nRTCWakeupAdvance'				=>	5,
						'szSetRTCWake_cmd'				=>	"",

					#On-wakeup Actions------------------------------------------
						'bOnWakeupFetchPlayers'			=>	1,					#Fetch players back from Alt Server on wakeup?
						'bOnWakeupFetchPlayersForce'	=>	0,					#Forcefully fetch back players..even if we have no record of pushing them..
						'nOnWakeupFetchPlayersDelay'	=>	30,					#Time to wait before fetching players back..
						'szOnWakeupFetchPlayersMACs'	=>	"",					#Specific players to fetch back
						'szOnWakeup_cmd'				=>	"",

					#Loggin level-----------------------------------------------
						'szLoggingLevel'				=>	'INFO',

		    );



my %hPrefDefaults_win = (

						'bIdleChkLogons'				=>	0,
						'bIdleChkSamba'					=>	0,
						'szShutdown_cmd'				=>	"%s /C start /B scpowertool.exe --shutdown -q \"--log=%s\"",
						'szReboot_cmd'					=>	"%s /C start /B scpowertool.exe --restart -q \"--log=%s\"",
						'szSuspend_cmd'					=>	"%s /C start /B scpowertool.exe --standby -q \"--log=%s\"",
						'szHibernate_cmd'				=>	"%s /C start /B scpowertool.exe --hibernate -q \"--log=%s\"",
						'szSCRestart_cmd'				=>	"%s /C start /B starthidden.exe scpowertool.exe --screstart -q \"--log=%s\"",
						'szSetRTCWake_cmd'				=>	"%s /C start /B starthidden.exe scpowertool.exe --wakeup=%%d -q \"--log=%s\"",
						#Alternate form if using WOSB..
						#'szSetRTCWake_cmd'				=>	"%s /C start /B wosb.exe /run /systray /ami dt=>%f tm=>%t",
						#Deprecated in favor of ReallyPreventStandby plugin..
						#'szOnWakeup_cmd'				=>	"%s /C start /B scpowertool.exe --keep-alive=>20 -q \"--log=%s\"",
			);


my %hPrefDefaults_unix = (
						'szShutdown_cmd'				=>	"%s /sbin/shutdown -h now",
						'szReboot_cmd'					=>	"%s /sbin/shutdown -r now",
						'szSuspend_cmd'					=>	"%s /usr/sbin/pm-suspend",
						'szHibernate_cmd'				=>	"%s /usr/sbin/pm-hibernate",
						'szSCRestart_cmd'				=>	"%s /usr/local/sbin/spc-restart.sh",
						'bSetRTCWakeForCrontab'			=>	1,
						'szSetRTCWake_cmd'				=>	"%s /usr/local/sbin/spc-wakeup.sh " . ($g{szDistro} eq 'Debian' && _DebianHasGUI() ? "%%l" : "%%d" ),
			);

my %hPrefDefaults_unix_systemctl = (
						'szShutdown_cmd'				=>	"%s /bin/systemctl poweroff",
						'szReboot_cmd'					=>	"%s /bin/systemctl reboot",
						'szSuspend_cmd'					=>	"%s /bin/systemctl suspend",
						'szHibernate_cmd'				=>	"%s /bin/systemctl hibernate",
						'szSCRestart_cmd'				=>	"%s /usr/local/sbin/spc-restart.sh",
						'bSetRTCWakeForCrontab'			=>	1,
						'szSetRTCWake_cmd'				=>	"%s /usr/local/sbin/spc-wakeup.sh " . ($g{szDistro} eq 'Debian' && _DebianHasGUI() ? "%%l" : "%%d" ),
			);


my %hPrefDefaults_mac = (
						'szShutdown_cmd'				=>	"%s /sbin/shutdown -h now",
						'szReboot_cmd'					=>	"%s /sbin/shutdown -r now",
						'szSuspend_cmd'					=>	"%s /usr/local/sbin/spc-sleep.sh",
						'szHibernate_cmd'				=>	"%s /usr/local/sbin/spc-hibernate.sh",
						'szSCRestart_cmd'				=>	"%s /usr/local/sbin/spc-restart.sh",
						'bSetRTCWakeForCrontab'			=>	1,
						'szSetRTCWake_cmd'				=>	"%s /usr/local/sbin/spc-wakeup.sh %%f %%t",
			);

#These are 'static' prefs that don't change with settings changes...but can be edited manually in the prefs file..
my %hPrefHiddenDefaults = (
						'nPrefsVersion'					=>  $g{nAppVersion},
						'bUseSoftBlocks'				=>	0,					#Treat block requests from the webUI as softblocks..
						'bNoWebUIRedirect2SN'			=>	0,					#Don't automatically redirect the web-page to mysb.com on a web-action..
						'bNoShowMac'					=>	1,					#Don't automatically expose the server's mac address
			);

my %hLogLevels = (
	0x7FFFFFFF 	=> { logLevel	=>	'OFF',		logName	=>	'Off' 	},
	0x0000C350	=> { logLevel	=>	'FATAL',	logName	=>	'Fatal' },
	0x00009C40	=> { logLevel	=>	'ERROR',	logName	=>	'Error' },
	0x00007530	=> { logLevel	=>	'WARN',		logName	=>	'Warn'  },
	0x00004E20	=> { logLevel	=>	'INFO',		logName	=>	'Info'  },
	0x00002710	=> { logLevel	=>	'DEBUG',	logName	=>	'Debug' },
	);

sub new {
	my $class = shift;
	#my $plugin   = shift;

	#Initialize the log..
	InitLog();

	#Initialize prefs
	InitPrefs();

	#Report our presence in the log..
	$g{log}->info(Plugins::SrvrPowerCtrl::Util::SrvrPowerCtrlStats());

	#Report our prefs..
	$g{log}->is_debug && DispPrefs();

	$class->SUPER::new;
}


sub InitLog {
	if (!defined( $g{log} )) {
		$g{log} = Slim::Utils::Log->addLogCategory({
			'category'     => 'plugin.SrvrPowerCtrl',
			'defaultLevel' => 'INFO',
			'description'  => 'PLUGIN_SRVRPOWERCTRL_MODULE_NAME',
			});
		$g{log}->is_debug && $g{log}->debug("Log initialized..");
	}

	$hPrefDefaults{szLoggingLevel} = GetCurrentLogLevel();
}

sub InitPrefs {
	$g{log}->is_debug && $g{log}->debug("Initializing prefs..");

	if (!defined( $g{prefs} )) {
		$g{prefs} = preferences('plugin.srvrpowerctrl');
	} else {
		$g{log}->is_debug && $g{log}->debug("Prefs already defined!");
	}

	#Report our prefs..
	#$g{log}->is_debug && DispPrefs();

	#why is this necessary?  Shouldn't the prefs be read automatically?
	ReadPrefs();

	#Migrate the prefs...this will set any defaults if they don't exist..
	$g{prefs}->migrate($g{nAppVersion}, \&MigratePrefs);

	#Regularize our prefs..
	FixUpPrefs();

	#set our prefs change handler..
	$g{log}->is_debug && $g{log}->debug("Setting Prefs change handler..");
	$g{prefs}->setChange(\&PrefsChange, keys %hPrefDefaults);

	$g{log}->is_debug && $g{log}->debug("Prefs initialized..");

	return defined($g{prefs});
}

sub ReadPrefs {
	$g{log}->is_debug && $g{log}->debug("Reading prefs..");
	#foreach $prefname (@aPrefNames) {
	foreach my $prefName (keys %hPrefDefaults) {

		# If a pref default is not present, set it..
		if ( ! $g{prefs}->exists($prefName) ) {
			$g{prefs}->set($prefName, $hPrefDefaults{$prefName});
		}

		$g{prefs}->{$prefName} = $g{prefs}->get($prefName);

		#$g{log}->is_debug && $g{log}->debug( "$prefName" . " == " . "$g{prefs}->{$prefName}" );

	}

	foreach my $prefName (keys %hPrefHiddenDefaults) {
		if ( ! $g{prefs}->exists($prefName) ) {
			$g{prefs}->set($prefName, $hPrefHiddenDefaults{$prefName});
		}
		$g{prefs}->{$prefName} = $g{prefs}->get($prefName);
		#$g{log}->is_debug && $g{log}->debug("$prefName" . " => "$g{prefs}->{$prefName}");
	}

}

#Fixup undefined prefs values to "" or 0
sub FixUpPrefs {
	$g{log}->is_debug && $g{log}->debug("Regularizing Prefs..");
	#foreach my $prefName (@aPrefNames) {
	foreach my $prefName (keys %hPrefDefaults, keys %hPrefHiddenDefaults) {
		if ( !defined($g{prefs}->$prefName) ) {
			#Don't set string prefs to 0
			if ( substr($prefName,0,2) eq 'sz' ) {
				$g{prefs}->set($prefName, "");
			#set undefined arrays to an empty ref..
			} elsif ( substr($prefName,0,1) eq 'a' ) {
				$g{prefs}->set($prefName, []);
			} else {
				$g{prefs}->set($prefName, 0);
			}
		} elsif ( $g{prefs}->{$prefName} eq 'on' ) {
			$g{prefs}->set($prefName, 1);
		#fixup non-arrays..
		} elsif (substr($prefName,0,1) eq 'a' && ref($g{prefs}->$prefName) ne 'ARRAY' ) {
			$g{prefs}->set($prefName, []);
		}

	}

	#special fix-up because we can get out of sync here..
	$g{prefs}->set('szLoggingLevel', $hLogLevels{ $g{log}->level }->{logLevel});
}


sub MigratePrefs {

	#Check for stale or missing prefs..reset to defaults if necessary..
	#If the plugin version is > than the prefs file version, reset all the prefs to defaults.

	$g{log}->info("Prefs are out of date: migrating..");

	#Migrate any existing old prefs...

	my %hOldPrefs = (

		#Old pref name					#New pref name
		bInclude_Hibernate2SN		=>	'bInclude_Suspend2AS',
		bInclude_Shutdown2SN		=>	'bInclude_Shutdown2AS',
		bInclude_Suspend2SN			=>	'bInclude_Suspend2AS',

		#Alt Server
		szAltServerAddr				=>	'szAltServerName',
		szAltServerAddr				=>	'szPushedAltServerName',
		szAltServerLbl				=>	0,
		bGotoSNAllPlayers			=>	'bAltServerPushAll',
		bOnXShutdownGotoSN			=>	'bAltServerPushOnXShutdown',
		nGoToSNDelay				=>	'nAltServerPostPushDelay',
		szPushSNPlayerMACs			=>	'szAltServerPushMACs',

		#System Idle Monitor
		bUseIdleWatchdog			=>	'bIdleChkPlayers',
		szNotIdleWatchdog_cmd		=>	'szIdleWatchdogCustCheck_cmd',

		#wakeup
		bRetrievePlayersFromSN		=>	'bOnWakeupFetchPlayers',
		nRetrievePlayersFromSNWait	=>	'nOnWakeupFetchPlayersDelay',
		szPullSNPlayerMACs			=>	'szOnWakeupFetchPlayersMACs',

		#Other changes
		bInclue_Restart				=>	'bInclude_Reboot',
		szRestart_cmd				=>	'szReboot_cmd',

	);

	my $oldPrefValue;
	my $oldPrefName;
	my $newPrefName;
	while ( ($oldPrefName, $newPrefName) = each(%hOldPrefs) ) {
		if ($newPrefName) {
			if (defined($oldPrefValue = $g{prefs}->get($oldPrefName))) {
				$g{log}->info("Migrating $oldPrefName to $newPrefName: $oldPrefValue..");
				$g{prefs}->set($newPrefName, $oldPrefValue);
			}
		}
	}
	#Kill the old prefs..
	while ( ($oldPrefName, $newPrefName) = each(%hOldPrefs) ) {
		$g{prefs}->remove($oldPrefName);
	}

	#ugh
	if ($g{prefs}->get('bIdleChkPlayers')) {
		$g{prefs}->set('bIdleMonitorSystem', 1);
	}

	#szSNPushedPlayers			=>	'aPushedAltServerPlayers',
	$oldPrefName = 'szSNPushedPlayers';
	my $szSNPushedPlayers = $g{prefs}->get($oldPrefName);
	if (defined($szSNPushedPlayers)) {
		#delimiters could be ; , or space
		my @aSNPushedPlayers = split(/[\;\,\s]/, $szSNPushedPlayers );
		my $nSNPushedPlayers = scalar @aSNPushedPlayers || 0;
		if($nSNPushedPlayers) {
			$g{log}->info("Migrating szSNPushedPlayers to  $szSNPushedPlayers..");
			$g{prefs}->set('aPushedAltServerPlayers',	\@aSNPushedPlayers );
		}
	}
	$g{prefs}->remove($oldPrefName);

	#Translate old cust commands into new..
	my $aCustCommands = $g{prefs}->get('aCustCmds');

	#Are we dealing with an empty string??
	if ( ref($aCustCommands) ne 'ARRAY') {
		$g{log}->is_debug && $g{log}->debug("Resetting Custom Commands (1)");
		$aCustCommands = [];
	} elsif ( @$aCustCommands && !${$aCustCommands}[0]{'command'} ) {
		$g{log}->is_debug && $g{log}->debug("Resetting Custom Commands (2)");
		$aCustCommands = [];
	}

	#szCustCmd0_lbl: Scan for New Music
	#szCustCmd0_cmd: cli://rescan
	#szCustCmd1_lbl: Wipe 'n Scan
	#szCustCmd1_cmd: cli://wipecache

	#Migrate only if we have an empty array..
	if (!@$aCustCommands) {
		my $szOldPref_lbl;
		my $szOldPref_cmd;
		my $szCustCmdLabel;
		my $szCustCmdCommand;
		for ( my $n = 0; $n < 4; $n++ ) {
			$szOldPref_lbl = 'szCustCmd' . $n . '_lbl';
			$szOldPref_cmd = 'szCustCmd' . $n . '_cmd';

			$szCustCmdLabel   = $g{prefs}->get($szOldPref_lbl);
			$szCustCmdCommand = $g{prefs}->get($szOldPref_cmd);
			if ( $szCustCmdLabel && $szCustCmdCommand ) {
				$g{log}->is_debug && $g{log}->debug("Migrating $szOldPref_lbl: $szCustCmdLabel: $szCustCmdCommand");
				push(@$aCustCommands, {
					label	=>	$szCustCmdLabel,
					command	=>	$szCustCmdCommand,
				});
			$g{prefs}->remove($szOldPref_lbl);
			$g{prefs}->remove($szOldPref_cmd);
			}
		}
		$g{prefs}->set('aCustCmds', $aCustCommands);
	}

	#Now, set any defaults that are missing..

	#Don't overwrite prefs that already have values..
	SetPrefDefaults( 0 );

	#Fix up the defaults with the OS specific stuff..
	PrepOSSpecificPrefDefaults( 0 );

	FixUpPrefs();
	ReadPrefs();

	$g{log}->is_debug && $g{log}->debug("Prefs migrated..");

	return 1;
}


sub _DebianHasGUI {
	my $szUsers;
	my $szGnomeUser;
	my $szDisplay;

	$szUsers = `/usr/bin/who`;

	#username  tty7         2010-11-23 13:01 (:0)
	if ( $szUsers =~ m/^(\w+)\s.*\((\:\d)\)$/mg ) {
		$szGnomeUser = $1;
		$szDisplay = $2;
	}

	#$g{log}->is_debug && $g{log}->debug( "Has a GUI == " . ( ($szGnomeUser && $szDisplay) ? "TRUE" : "FALSE"));

	return ($szGnomeUser && $szDisplay);
}



sub PrepOSSpecificPrefDefaults {
	my $bForce = shift || 0;
	my $cmd;
	my $logfile;

	$g{log}->info("Setting default prefs for $g{szOS}, $g{szDistro}");

  	if ($g{szOS} eq 'win') {

		$cmd = $ENV{windir} . "\\system32\\cmd.exe";

		#for Windows vista and 7: put the log file somewhere we have write priviliges..
		$logfile =  Slim::Utils::OSDetect::dirsFor('log') . "\\srvrpowerctrl.log";

		foreach my $prefName (keys %hPrefDefaults_win) {

			if ( substr($prefName,0,2) eq 'sz' ) {
				$hPrefDefaults{$prefName} = sprintf($hPrefDefaults_win{$prefName}, $cmd, $logfile);
			}

			$g{prefs}->set( $prefName, $hPrefDefaults{$prefName} );
		}

	## Various linux distros..
	} elsif ($g{szOS} eq 'unix') {
		$cmd = "sudo";
		$logfile =  Slim::Utils::OSDetect::dirsFor('log') . '/srvrpowerctrl.log';
		
		# Test to see if we're running under systemd..
		my $res = `systemctl 2>&1 | grep -c '\\-\\.mount'`;
		
		if ( $res > 0 ) {
			
			warn 'SrvrPowerCtrl configuring for systemctl power management';
			foreach my $prefName (keys %hPrefDefaults_unix_systemctl) {

				if ( substr($prefName,0,2) eq 'sz' ) {
					$hPrefDefaults{$prefName} = sprintf($hPrefDefaults_unix_systemctl{$prefName}, $cmd, $logfile);
				}

				#Don't overwrite the prefs if they're defined...
				if ( $bForce || ! $g{prefs}->exists($prefName) || (substr($prefName,0,2) eq 'sz' && $g{prefs}->{$prefName} eq '') ) {
					$g{prefs}->set( $prefName, $hPrefDefaults{$prefName} );
				}

			}
		} else {
			
			warn 'SrvrPowerCtrl configuring for pm-utils power management';
			foreach my $prefName (keys %hPrefDefaults_unix) {

				if ( substr($prefName,0,2) eq 'sz' ) {
					$hPrefDefaults{$prefName} = sprintf($hPrefDefaults_unix{$prefName}, $cmd, $logfile);
				}

				#Don't overwrite the prefs if they're defined...
				if ( $bForce || ! $g{prefs}->exists($prefName) || (substr($prefName,0,2) eq 'sz' && $g{prefs}->{$prefName} eq '') ) {
					$g{prefs}->set( $prefName, $hPrefDefaults{$prefName} );
				}

			}
		}





	## OSX
	} elsif ($g{szOS} eq 'mac') {
		$cmd = "sudo";
		$logfile =  Slim::Utils::OSDetect::dirsFor('log') . '/srvrpowerctrl.log';

		foreach my $prefName (keys %hPrefDefaults_mac) {

			if ( substr($prefName,0,2) eq 'sz' ) {
				$hPrefDefaults{$prefName} = sprintf($hPrefDefaults_mac{$prefName}, $cmd, $logfile);
			}

			$g{prefs}->set( $prefName, $hPrefDefaults{$prefName} );
		}
	}

	#if we're running on SC 7.4 or above, SCRestart is a cli command..
	#if ( $g{nSCVersion} >= 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') >= 0) {
		$hPrefDefaults{szSCRestart_cmd}		= "cli://restartserver";
		$g{prefs}->set( 'szSCRestart_cmd', $hPrefDefaults{szSCRestart_cmd} );
	}

}



sub SetPrefDefaults {
	my $bForce = shift || 0;
	my $cmd;

	$g{log}->info("Setting prefs to $g{nAppVersion} defaults");
	$g{prefs}->set('nPrefsVersion', $g{nAppVersion} );


	#Write the default values to the prefs file..
	while ( my ($pref, $default) = each(%hPrefDefaults) ) {
		#$g{prefs}->set( $pref, $hPrefDefaults{$pref} );
		if ($bForce) {
			#Don't force overwrite custom commands?
			if ($pref !~ m/^szCustCmd.*/) {
				$g{prefs}->set( $pref, $default );
			}
		}
		#Don't overwrite the prefs if they're defined...
		elsif ( ! defined($g{prefs}->get($pref)) ) {
			$g{prefs}->set( $pref, $default );
		}
    }

	while ( my ($pref, $default) = each(%hPrefHiddenDefaults) ) {
		#$g{prefs}->set( $pref, $hPrefDefaults{$pref} );
		if ($bForce) {
			$g{prefs}->set( $pref, $default );
		}
		#Don't overwrite the prefs if they're defined...
		elsif ( ! defined($g{prefs}->get($pref)) ) {
			$g{prefs}->set( $pref, $default );
		}
    }

}


sub LogGetLevel {
	return $hLogLevels{ $g{log}->level }->{logLevel};

}

sub LogChangeLevel {
	my ($szNewLevel, $bPersistent) = @_;

	#if not asked to change, just return the current logging level
	if (!defined($szNewLevel)) {
		return ( 0, $hLogLevels{ $g{log}->level }->{logLevel} );
	}

	$szNewLevel = uc($szNewLevel);

	my $hValidLogLevels = ();

	for (Slim::Utils::Log::validLevels()) { $hValidLogLevels->{$_} = 1; }

	if (!$hValidLogLevels->{$szNewLevel}) {
		$g{log}->fatal("Invalid logging level: $szNewLevel");
		return ( 0, $hLogLevels{ $g{log}->level }->{logLevel} );
	}

	$g{log}->is_debug && $g{log}->debug("Changing logging level from " . $hLogLevels{ $g{log}->level }->{logLevel} . " to $szNewLevel");

	if ($bPersistent) {
		Slim::Utils::Log->persist(1);
	}

	my $nRet = Slim::Utils::Log->setLogLevelForCategory ('plugin.SrvrPowerCtrl', $szNewLevel);

	if (!$nRet) {
		$g{log}->fatal("Failed to change log level to $szNewLevel");
		return ( 0, $hLogLevels{ $g{log}->level }->{logLevel} );
	}

	#if ($nRet > 0) {
	if ($nRet == 1) {
		Slim::Utils::Log->reInit;
		#Slim::Utils::Log->reInit( {	'logconf' => Slim::Utils::Log->defaultConfigFile()} );
	}

	$g{log} = Slim::Utils::Log::logger('plugin.SrvrPowerCtrl');

	$g{log}->fatal("Logging level now " . $hLogLevels{ $g{log}->level }->{logLevel} );

	#$g{log}->is_debug && $g{log}->debug("log: " . Data::Dump::dump($g{log}));

	return ( 1, $hLogLevels{ $g{log}->level }->{logLevel} );
}


# Prefs change..
# start using routines form Slim::Utils::Validate.pm to validate values: isInt(), numer(), isTime(), etc.

sub PrefsChange {
	my ($pref, $value) = @_;

	#$g{log}->is_debug && $g{log}->debug("PrefsChange1: $pref == $value");

	#validate boolian prefs
	if ( substr($pref, 0, 1) eq 'b' ) {
		if (!defined($value)) {
			#fix up the reference to silence a warning in the log..
			$value = 0;
			@_[1] = $value;
		} elsif ($value eq 'on') {
			$value = 1;
			@_[1] = $value;
		}
	#validate numeric prefs: if the value is not a number, reset it to the default..
	} elsif ( substr($pref, 0, 1) eq 'n' ) {
		if (!Plugins::SrvrPowerCtrl::Util::IsNumeric($value)) {
			$value = $hPrefDefaults{$pref};
			@_[1] = $value;
		}
	#fixup array prefs that aren't..
	} elsif ( substr($pref, 0, 1) eq 'a' ) {
		if (ref($value) ne 'ARRAY') {
			$value = [];
			@_[1] = $value;
		}

	#Fixup any string values
	#} elsif ( substr($pref,0,2) eq 'sz' ) {
	#	if (!defined($value)) {
	#		#fix up the reference to silence a warning in the log..
	#		$value = "";
	#	}
	#g{log}->debug("String translation: $g{prefs}->{$pref} vs. $value..");

	#define any other undefined values..
	} else {
		if (!defined($value)) {
			#fix up the reference to silence a warning in the log..
			$value = "";
			@_[1] = $value;
		}
	}

	#special validations...

	#Logging level change..
	if ( $pref eq 'szLoggingLevel' && $value ne $hLogLevels{ $g{log}->level }->{logLevel} ) {
		LogChangeLevel($value, 1);
	}


	if ( ($pref eq 'szEODWatchdogStartTime') && (!defined(Slim::Utils::Validate::isTime($value))) ) {
		$g{log}->error("$value is not a valid time string!");
		$value = $hPrefDefaults{$pref};
		@_[1] = $value;
		$g{prefs}->set($pref, $value);
	}

	if ( ($pref eq 'szEODWatchdogEndTime') && (!defined(Slim::Utils::Validate::isTime($value))) ) {
		$g{log}->error("$value is not a valid time string!");
		$value = $hPrefDefaults{$pref};
		@_[1] = $value;
		$g{prefs}->set($pref, $value);
	}

	#Inforce a miniumum 30 second action delay if we need to request a remote-server player power-off..

	if ( $pref eq 'bAltServerPowerOffPlayers' && $value && $g{prefs}->nAltServerPostPushDelay < 30 ) {
		$g{prefs}->set('nAltServerPostPushDelay',30);
	}

	if ( $pref eq 'nAltServerPostPushDelay' && $g{prefs}->bAltServerPowerOffPlayers && $value < 30 ) {
		$value = 30;
		@_[1] = $value;
		#$g{prefs}->{$pref} = $value;
		$g{prefs}->set($pref, $value);
	}

	#report the prefs change before acting on them..
	$g{log}->is_debug && $g{log}->debug("PrefsChange: $pref == $value");

	#Actions to take on prefs change..

	#Basic Commands..
	if ( $pref eq 'bInclude_WebInterface' ) {
		Plugins::SrvrPowerCtrl::WebUI::ActivateWebUI($value);

	#Idle and EOD settings..
	} elsif ( $pref =~ m/^\w+(Idle|EOD).*$/ ) {
			Plugins::SrvrPowerCtrl::Watchdog::ActivateWatchdogs();

	#Sleep Settings
	} elsif ( $pref eq 'bHookSleepButton' ) {
		Plugins::SrvrPowerCtrl::SleepButton::HookSleepButton($value);
		Plugins::SrvrPowerCtrl::SleepButton::ChangeSleepHoldButtonHandlers($value);
	} elsif ( $pref eq 'bUseSleepEndWatchdog' ) {
		Plugins::SrvrPowerCtrl::Watchdog::ActivateSleepEndWatchdog($value);

	#On-wakeup Actions..
	} elsif ( $pref eq 'bOnWakeupFetchPlayers' ) {
		Plugins::SrvrPowerCtrl::Watchdog::ActivateOnWakeupWatchdog($value);
	} elsif ( $pref eq 'szOnWakeup_cmd' ) {
		#Plugins::SrvrPowerCtrl::Watchdog::ActivateOnWakeupWatchdog($value);
		Plugins::SrvrPowerCtrl::Watchdog::ActivateOnWakeupWatchdog(!!length($value));
	}

	$g{prefs}->{$pref} = $value;

	#reinitialize the action items..
	Plugins::SrvrPowerCtrl::Menu::initActionItems();

	#$g{log}->is_debug && DispPrefs($pref, "PrefsChange:");

	return $value;
}


# Provide case insensitive help finding a pref name ..
sub FindPrefName {
	my $szSearchPrefName = @_;

	foreach my $szPrefName (keys %hPrefDefaults, keys %hPrefHiddenDefaults) {
		if (lc($szSearchPrefName) eq lc($szPrefName)){
			return $szPrefName;
		}
	}

	return undef;
}

sub ListPrefs {
	my $bAddBR = shift || 0;
	my $szPrefs = "";

	my $szFormat = "%s: %s\n";

	if ($bAddBR) {
		$szFormat =~ s/\n/\<br\>/g;
	}

	foreach my $szPrefName (keys %hPrefDefaults, keys %hPrefHiddenDefaults) {
		$szPrefs .= sprintf($szFormat, $szPrefName, $g{prefs}->get($szPrefName));
	}

	my $aCustCommands = $g{prefs}->get('aCustCmds');

	$szPrefs .= "aCustCmds: \n";

	$szFormat = "  - \n" .
				"    command: %s\n" .
				"    label: %s\n";

	if ($bAddBR) {
		$szFormat =~ s/\n/\<br\>/g;
	}

	foreach my $custcmd (@$aCustCommands) {
		$szPrefs .= sprintf($szFormat, $custcmd->{'label'}, $custcmd->{'command'});
	}

	#$g{log}->is_debug && $g{log}->debug($szPrefs);

	return $szPrefs;
}


sub DispPrefs {
	my $prefShow = shift;
	my $msg = shift;
	my @aPrefNames;
	my $num = 0;
	my $prefLabel;

	if (defined($prefShow)) {
		push (@aPrefNames, $prefShow);
	} else {
		@aPrefNames = (keys %hPrefDefaults, keys %hPrefHiddenDefaults);
	}

	if (!defined($msg)) {
		$msg = " ";
	} else {
		$msg = $msg . " ";
	}

	#get the length of the longest prefname
	foreach my $prefName (@aPrefNames) {
		if ($num < length($prefName)) {
			$num = length($prefName);
		}
	}

	my $n = 0;
	my $aCustCommands = $g{prefs}->get('aCustCmds');
	my $szCustCommandLabel;
	foreach my $custcmd (@$aCustCommands) {
		$szCustCommandLabel = "customcmd$n";
		if ($num < length($szCustCommandLabel)) {
			$num = length($szCustCommandLabel);
		}
		$n++;
	}

	foreach my $prefName (@aPrefNames) {
		$prefLabel = sprintf('%*2$s', (defined($hPrefHiddenDefaults{$prefName}) ? '[' . $prefName . ']' : $prefName), $num);
		$g{log}->is_debug && $g{log}->debug("$msg $prefLabel == $g{prefs}->{$prefName}");
	}

	$n = 0;
	foreach my $custcmd (@$aCustCommands) {
		$szCustCommandLabel = "customcmd$n";
		$prefLabel = sprintf('%*2$s', $szCustCommandLabel, $num);
		$g{log}->is_debug && $g{log}->debug("$msg $prefLabel == $custcmd->{'label'}:$custcmd->{'command'}");
		$n++;
	}


}


#This adds the Name to the Settings->Advanced combobox.
sub name {
	#if ( $g{nSCVersion} >= 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') >= 0) {
		return Slim::Web::HTTP::CSRF->protectName('PLUGIN_SRVRPOWERCTRL_MODULE_NAME');
	} else {
		return Slim::Web::HTTP::protectName('PLUGIN_SRVRPOWERCTRL_MODULE_NAME');
	}
}


sub page {
	my $urlSettings = 'plugins/SrvrPowerCtrl/settings/basic.html';
	#my $urlPrefix = "\\/";
	my $urlPrefix = "";

	#$urlSettings = Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlSettings);

	#for SBS 7.4 and later..
	#if ( $g{nSCVersion} >= 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') >= 0) {
		return Slim::Web::HTTP::CSRF->protectURI($urlPrefix . $urlSettings);
	} else {
		return Slim::Web::HTTP::protectURI($urlPrefix . $urlSettings);
	}
}

sub prefs {
	#return ($g{prefs}, @aPrefNames );
	return ($g{prefs}, keys %hPrefDefaults );
}

#sub getPrefs {
#	return $g{prefs};
#}

sub needsClient {
	return 0;
}

sub handler {
	#my ($class, $client, $params) = @_;
	my ($class, $client, $params, $callback, @args) = @_;
	my $action;
	my $item;

	#$g{log}->is_debug && $g{log}->debug("Start..");

	#reset all prefs to defaults..
	if ($params->{'resetSettings'}) {
		$g{log}->is_debug && $g{log}->debug("Resetting prefs..");
		#Fix up the defaults with the OS specific stuff..
		PrepOSSpecificPrefDefaults(1);
		#Force the prefs back to the defaults..
		SetPrefDefaults(1);
		$g{log}->is_debug && DispPrefs();
	}

	if ($params->{'saveSettings'}) {
		$g{log}->is_debug && $g{log}->debug("Saving prefs..");
		#Save the settings..
		my @custcmds;
		my $i = 0;

		while (defined $params->{"spccustcmdcommand$i"}) {

			if ( $params->{"spccustcmdcommand$i"} ne "" && $params->{"spccustcmdcommand$i"} ne string('PLUGIN_SRVRPOWERCTRL_CUSTOMCMD_CMD_DEF') ) {

				my $custcmd = {
					'label'		=> $params->{"spccustcmdlabel$i"},
					'command'	=> $params->{"spccustcmdcommand$i"},
				};

				push @custcmds, $custcmd;
			}
			$i++;
		}

		#$g{log}->is_debug && $g{log}->debug("Saving custom commands: " . Data::Dump::dump(@custcmds));

		$g{prefs}->set('aCustCmds', \@custcmds);

	}

	_pushSettings($class, $client, $params, $callback, \@args);

	#$g{log}->is_debug && $g{log}->debug("Done..");
	return $class->SUPER::handler($client, $params);

}


sub GetCurrentLogLevel {
	return $hLogLevels{ $g{log}->level }->{logLevel};
}

sub _pushSettings {
	my ($class, $client, $params, $callback, $args) = @_;

	$g{log}->is_debug && $g{log}->debug("Start..");

	############################################################################
	# Log levels..
	############################################################################

	#determine the current log level, pass that in params..

	#$params->{srvrpowerctrl_logLevel} = $hLogLevels{ $g{log}->level }->{logLevel};

	$params->{sbsservername} = Plugins::SrvrPowerCtrl::Util::GetSCName();

	#Pass the log levels array iln params..
	$params->{srvrpowerctrl_logLevels} = [];

	foreach my $logLevel (reverse sort { $a <=> $b } keys %hLogLevels) {
		push( @{$params->{srvrpowerctrl_logLevels}}, { logLevel => $hLogLevels{ $logLevel }->{logLevel}, logName => $hLogLevels{ $logLevel }->{logName} } );
	}

	#Make sure the loginfo page isn't loaded from the cache..
	$params->{srvrpowerctrl_urlsuffix} = time();



	my ($bCheckFilePresent, $szCheckFile) = Plugins::SrvrPowerCtrl::Help::IsHelperUtilInstalled();
	$params->{srvrpowerctrl_warn} = ( $bCheckFilePresent ? '' : string('PLUGIN_SRVRPOWERCTRL_NEEDSSETUP_HELP_MSG2') );

	$params->{srvrpowerctrl_stats} = Plugins::SrvrPowerCtrl::Util::SrvrPowerCtrlStats();

	#OS is used to hide some controls on settings page..
	$params->{srvrpowerctrl_os} = $g{szOS};

	############################################################################
	# Server Names..
	############################################################################

	$params->{srvrpowerctrl_altservers} = [];

	for (@{Plugins::SrvrPowerCtrl::AltServer::GetAltServerList()}) {
		push( @{$params->{srvrpowerctrl_altservers}}, $_ );
	}

	############################################################################
	# Action list..
	############################################################################

	#Rebuild the action items every time?
	Plugins::SrvrPowerCtrl::Menu::initActionItems();

	$params->{srvrpowerctrl_actionlist} = [];

	foreach my $item (@{$g{aActions}}) {
		#Anything with menutext goes on the list..
		if (length($item->{menutext})) {
			push( @{$params->{srvrpowerctrl_actionlist}},
			#push (@actions,
				{
				'action'	=> $item->{action},
				'menutext'	=> $item->{menutext},
				});
		}
	}


	############################################################################
	# Custom Commands..
	############################################################################

	$params->{srvrpowerctrl_custcmds} = [];

	my $aCustCommands = $g{prefs}->get('aCustCmds');

	#Are we dealing with a non arrary or an empty one?
	if ( (ref($aCustCommands) ne 'ARRAY') || ( @$aCustCommands && !${$aCustCommands}[0]{'command'} ) ) {
		$aCustCommands = [];
	}


	my $custcmd;

	foreach $custcmd (@$aCustCommands) {
		if ( $custcmd->{'command'} ) {
			#$g{log}->is_debug && $g{log}->debug("Pushing custom command: " . Data::Dump::dump($custcmd));
			push( @{$params->{srvrpowerctrl_custcmds}}, $custcmd );
			#push( @{$params->{srvrpowerctrl_custcmdlabels}}, $custcmd->{label} );
		}
	}

	# New 'blank' custcommand
	$custcmd = {
		label	=>	string('PLUGIN_SRVRPOWERCTRL_CUSTOMCMD_LABEL_DEF'),
		command	=>	string('PLUGIN_SRVRPOWERCTRL_CUSTOMCMD_CMD_DEF'),
		};

	push( @{$params->{srvrpowerctrl_custcmds}}, $custcmd );

	#$g{log}->is_debug && $g{log}->debug("params: " . Data::Dump::dump($params));

	$callback->($client, $params, $class->SUPER::handler($client, $params), @$args);

}





1;

__END__
