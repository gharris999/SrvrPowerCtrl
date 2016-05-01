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
#    Plugin.pm -- main routines for SrvrPowerCtrl
#

package Plugins::SrvrPowerCtrl::Plugin;

use base qw(Slim::Plugin::Base);
use strict;
use Slim::Utils::Misc;
use File::Spec::Functions qw(:ALL);
use File::Basename;
use FindBin qw($Bin);
#use Slim::Utils::Log;
#use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use Slim::Player::Client;


#Global Variables..
use Plugins::SrvrPowerCtrl::Settings;
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

use Plugins::SrvrPowerCtrl::Alarms;
use Plugins::SrvrPowerCtrl::AltServer;
use Plugins::SrvrPowerCtrl::Block;
use Plugins::SrvrPowerCtrl::CLI;
use Plugins::SrvrPowerCtrl::Help;
use Plugins::SrvrPowerCtrl::Jive;
use Plugins::SrvrPowerCtrl::Menu;
use Plugins::SrvrPowerCtrl::SleepButton;
use Plugins::SrvrPowerCtrl::Util;
use Plugins::SrvrPowerCtrl::Watchdog;
use Plugins::SrvrPowerCtrl::WebUI;
#use Plugins::SrvrPowerCtrl::bQueue;
#use Plugins::SrvrPowerCtrl::Stats;

my $apiVersion = $g{nAppVersion};

#public $apiVersion;


# --------------------------------------
# Called by the server on plugin startup

sub initPlugin {
	my ($class) = @_;

	#Initialize global vars, prefs, log, etc..
	Plugins::SrvrPowerCtrl::Settings->new($class);

	$class->SUPER::initPlugin();

	# Register our CLI command
	Slim::Control::Request::addDispatch(['srvrpowerctrl','_action','_message', '_switchclient', '_fromjive'], [0, 0, 0, \&Plugins::SrvrPowerCtrl::CLI::pluginCLI]);

	# Protect against CSRF attack
	#for SBS 7.4 and later..
	#if ( $g{nSCVersion} >= 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') >= 0) {
		Slim::Web::HTTP::CSRF->protectCommand('srvrpowerctrl');
		Slim::Web::HTTP::CSRF->protectCommand('jivesrvrpowerctrlmenu');
	} else {
		Slim::Web::HTTP::protectCommand('srvrpowerctrl');
		Slim::Web::HTTP::protectCommand('jivesrvrpowerctrlmenu');
	}

	# Hook the sleep button on the IR remote..
	if ($g{prefs}->bHookSleepButton) {
		Plugins::SrvrPowerCtrl::SleepButton::HookSleepButton($g{prefs}->bHookSleepButton);
	}

	# Prep the various watchdogs...
	Plugins::SrvrPowerCtrl::Watchdog::ActivateWatchdogs();

	#Initialize our action items..
	Plugins::SrvrPowerCtrl::Menu::initActionItems();

	# Add the Jive menu
	Plugins::SrvrPowerCtrl::Jive::addJiveMenu($class);

	# Tack our menu onto the SC WebUI home page Extras menu..
	Plugins::SrvrPowerCtrl::WebUI->new($class);
	Plugins::SrvrPowerCtrl::WebUI::ActivateWebUI($g{prefs}->bInclude_WebInterface);

	# Setup page handlers for the help pages..
	Plugins::SrvrPowerCtrl::Help->new($class);

	# Start the watchdogs' timer
	Plugins::SrvrPowerCtrl::Watchdog::ActivateSPCWatchdog(1, -1);

	# Pull back any players from SqueezeNetwork that we want..
	if ($g{prefs}->bOnWakeupFetchPlayers) {
		$g{tPendingPullFromASTimer} = Slim::Utils::Timers::setTimer(undef, time() + $g{prefs}->nOnWakeupFetchPlayersDelay, \&Plugins::SrvrPowerCtrl::AltServer::PullFromAltServer, );
	}

	# Execute the .autoexec item (if any)..
	my $item = Plugins::SrvrPowerCtrl::Menu::findActionItemByMenuText('.autoexec');

	if (defined($item)) {
		$g{tPendingActionTimer} = Slim::Utils::Timers::setTimer( undef, time() + ($g{prefs}->nOnWakeupFetchPlayersDelay + 30), \&performAction, ( $item ) );
		if ($g{tPendingActionTimer}) {
			#$g{log}->is_debug && $g{log}->debug("Timer # $g{tPendingActionTimer} created.  Action " . $item->{action} . " is pending in $nWatchdogActionDelay seconds..");
			$item->{exeTime} = time() + ($g{prefs}->nOnWakeupFetchPlayersDelay + 15);
			$g{hPendingAction} = $item;
			$g{log}->is_debug && $g{log}->debug("Pending Action: " . Data::Dump::dump($g{hPendingAction}) );
		}
	}

	$g{log}->is_debug && $g{log}->debug( "$class done initializing.");
}


sub shutdownPlugin {
	my ($class) = @_;

	# Are we here becuase of an external event?
	if ( ! $g{hPreviousAction} || $g{hPreviousAction}->{exeTime} < time() - $g{prefs}->{nAltServerPostPushDelay}) {
		#Plugin is shutting down because of some external cause...so take these actions..
		$g{log}->is_debug && $g{log}->debug( "$class externally initiated shutdown.");

		#Set rtc wake alarm
		if ( Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup() ) {
			Plugins::SrvrPowerCtrl::Alarms::SetRTCWakeup();
		}

		#Turn off players...
		if ( $g{prefs}->bPowerOffPlayers ) {
			Plugins::SrvrPowerCtrl::Util::PowerOffPlayer();
		}

		#Send players to SqueezeNetwork..
		if ( $g{prefs}->{bAltServerPushOnXShutdown} ) {
			$g{log}->is_debug && $g{log}->debug( "Attempting to push players to $g{prefs}->{szAltServerName}..");
			Plugins::SrvrPowerCtrl::AltServer::PushToAltServer();
		}

		#Perform the xCmd:
		if ( $g{prefs}->{szOnXShutdown_cmd} ) {
			Plugins::SrvrPowerCtrl::Util::SystemExecCmd(undef, $g{prefs}->{szOnXShutdown_cmd} );
		}

	} else {
		# Nope, we're here because of one of our actions..
		$g{log}->is_debug && $g{log}->debug( "$class self initiated " . Data::Dump::dump( $g{hPreviousAction} ) );
	}

	# Remove our jive menu..
	#Plugins::SrvrPowerCtrl::Jive::removeJiveMenu();

	# Kill the watchdogs' timer
	Plugins::SrvrPowerCtrl::Watchdog::ActivateSPCWatchdog(0);
}

sub getIcon {
	my ( $class, $url ) = @_;

	return Plugins::SrvrPowerCtrl::Plugin->_pluginDataFor('icon');
}


# ------------------------------------------------------------------
# This is called by the server when the user presses the right arrow
# on the Extras menu and this plugin is selected as a mode.

sub setMode {
	my ($class, $client, $method) = @_;

	#$g{log}->is_debug && $g{log}->debug("class == " . $class . "; client == " . ( eval {$client->name()} || 'no client' ) . "; method == " . $method );

	my @lines;

	if ($method eq 'pop') {
		# Pop the current mode off the mode stack and restore the previous one
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# list of actions for INPUT.List

	# menu items for the above node..
	foreach my $item (@{$g{aActions}}) {
		if ($item->{menuindex} ge 0) {
			push (@lines, $item->{'menutext'});
		}
	}

	# INPUT.List takes several parameters, which are passed to it via a hash reference.
	my %params = (
		stringHeader	=> 1,
		header			=> 'PLUGIN_SRVRPOWERCTRL_MODULE_NAME',
		listRef			=> \@lines,
		onChange		=> \&Plugins::SrvrPowerCtrl::Menu::doInputListChange,
		callback		=> \&Plugins::SrvrPowerCtrl::Menu::doInputListCallback,
		overlayRef		=> sub { return ( undef, $client->symbols('rightarrow') ); },
	);

	# start the new mode....
	$g{log}->is_debug && $g{log}->debug($client->name() . " method: " . $method . " starting new mode..");
	Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
}

sub GetPendingActionMessage {
	my $action = shift;
	my $message = "";
	#OK, we're not blocked..maybe there's a pending action...
	if ($g{tPendingActionTimer}) {
		$g{log}->is_debug && $g{log}->debug("Timer # $g{tPendingActionTimer} already pending.  Action " . $g{hPendingAction}->{action} . " ignored..");
		$message = sprintf( string('PLUGIN_SRVRPOWERCTRL_PENDINGACTION_MSG'),  ucfirst(lc($action)), ucfirst(lc($g{hPendingAction}->{action})) );
	}
	return $message;
}

sub prepareAction {
	my ($client, $item, $nocancelmsg, $fromJive) = @_;
	my $nDeferTime = 0;
	my $timeoutmsg;
	my $message;
	my $jivemessage;

	#Don't prepare an action if one is already pending..
	if ($g{tPendingActionTimer}) {
		$g{log}->is_debug && $g{log}->debug("Timer # $g{tPendingActionTimer} already pending.  Action " . $item->{action} . " ignored..");
		return 0;
	}

	if ($item->{checkblock}) {
		#If a action block has been set...display the message and do nothing..
		if ( Plugins::SrvrPowerCtrl::Block::IsBlocked() ) {
			if ($client) {
				if (! ($client->deviceid eq 7 || $client->deviceid eq 9) ) {
					Slim::Buttons::Common::popModeRight($client);
				}
			}
			$g{log}->is_debug && $g{log}->debug("Trying to warn about block condition..");
			Plugins::SrvrPowerCtrl::Block::DispBlockedMessage($client, $item->{'action'}, 3);
			return 0;
		}
	}

	#Auto-add sleep defer time...
	$nDeferTime = Plugins::SrvrPowerCtrl::SleepButton::GetSleepTime();
	#if we are sleep-playing..
	if ($nDeferTime > 0) {
		$g{log}->is_debug && $g{log}->debug("Deferring action " . $item->{action} . " for $nDeferTime while sleep-playing..");
		$item->{isSleepDefered} = 1;
		#Activate the sleep monitor
		Plugins::SrvrPowerCtrl::Watchdog::ActivateSleepRequestMonitor(1);
	}

	$nDeferTime += $item->{cancelwait};

	#warn all the clients..
	if ($nDeferTime > 59) {
		#display the timeout in minutes..
		$timeoutmsg = sprintf(string('PLUGIN_SRVRPOWERCTRL_SLEEP_TIMEOUT_MSG'), ($nDeferTime/60 + 0.5));
	} else {
		#display the timeout in seconds..
		$timeoutmsg = sprintf(string('PLUGIN_SRVRPOWERCTRL_TIMEOUT_MSG'), $nDeferTime);
	}
	$message = $item->{'message'} . ' ' . $timeoutmsg;
	$jivemessage = $message;

	#warn all clients except this one..
	Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage (undef, $message, $nDeferTime, $client);

	#warn this client..
	if ($client) {
		#$message = $item->{'message'};

		#display the 'how to cancel' message..
		if (!$nocancelmsg) {
			if ($fromJive) {
				$jivemessage = $jivemessage . '...' . (Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'model') eq 'controller' ? string('PLUGIN_SRVRPOWERCTRL_CANCELJIVE_MSG') : string('PLUGIN_SRVRPOWERCTRL_CANCELTOUCH_MSG'));
			} else {
				$message = $message . '...' . string('PLUGIN_SRVRPOWERCTRL_CANCEL_MSG');
			}
		}

		Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage ($client, $message, $nDeferTime, undef, $jivemessage);
	}


	#set a timer to perform the action...
	$g{tPendingActionTimer} = Slim::Utils::Timers::setTimer( $client, time() + $nDeferTime, \&performAction, ( $item ) );

	if ($g{tPendingActionTimer}) {
		$g{log}->is_debug && $g{log}->debug("Timer # $g{tPendingActionTimer} created.  Action " . $item->{action} . " is pending in $nDeferTime seconds..");
		$item->{exeTime} = time() + $nDeferTime;
		$g{hPendingAction} = $item;
		$g{log}->is_debug && $g{log}->debug("Pending Action: " . Data::Dump::dump($g{hPendingAction}) );
		return 1;
	}
	return 0;
}


sub resecheduleAction {
	my ($client, $item) = @_;
	my $nDeferTime = 0;

	#Auto-add sleep defer time...
	$nDeferTime = Plugins::SrvrPowerCtrl::SleepButton::GetSleepTime();
	#if we are sleep-playing..
	if ($nDeferTime > 0) {
		$g{log}->is_debug && $g{log}->debug("Deferring action " . $item->{action} . " for $nDeferTime while sleep-playing..");
		$item->{isSleepDefered} = 1;
		#Activate the sleep monitor
		Plugins::SrvrPowerCtrl::Watchdog::ActivateSleepRequestMonitor(1);
	}

	$nDeferTime += $item->{cancelwait};

	$g{log}->is_debug && $g{log}->debug("Killing timer # $g{tPendingActionTimer}..");
	Slim::Utils::Timers::killSpecific($g{tPendingActionTimer});
	$g{tPendingActionTimer} = 0;

	#set a timer to perform the action...
	$g{tPendingActionTimer} = Slim::Utils::Timers::setTimer( $client, time() + $nDeferTime, \&performAction, ( $item ) );

	if ($g{tPendingActionTimer}) {
		$g{log}->is_debug && $g{log}->debug("Timer # $g{tPendingActionTimer} rescheduled.  Action " . $item->{action} . " is pending in $nDeferTime seconds..");
		$item->{exeTime} = time() + $nDeferTime;
		$g{hPendingAction} = $item;
		$g{log}->is_debug && $g{log}->debug("Pending Action: " . Data::Dump::dump($g{hPendingAction}) );
		return 1;
	}
	return 0;


}

# -------------------------------------------------------------------------
# This is the sub which executes the shutdown/restart/suspend/etc. commands

sub performAction {
	my ($client, $item) = @_;
	my $nPushed = 0;
	my $nDelay = 0;

	#Power Off all clients unless we're going to SN..
	if ( $item->{poweroffplayers} ) {
		Plugins::SrvrPowerCtrl::Util::PowerOffPlayer();
	} elsif ( Plugins::SrvrPowerCtrl::Util::IsValidClient($client) )  {
		#Force the player to the home page.  Makes resuming from suspend/hibernation less messy.  Suggested by Wirrunna.
		$client->execute(['button', 'home']);
	}

	# point of no return, block further updates to display..
	Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage(undef, $item->{message}, $item->{messagetime}, undef, undef, 1);	#blocking message..

	#Switch the calling player to SqueezeNetwork..
	if ($item->{'push2as'}) {
		($nPushed, $nDelay) = Plugins::SrvrPowerCtrl::AltServer::PushToAltServer($client);
	}

	#cue up our action command to execute in the near future..
	$g{tPendingActionTimer} = Plugins::SrvrPowerCtrl::Util::ScheduleCommand($client, $item, $nDelay);



	return 1;
}

sub cancelAction {
	my ($client, $item) = @_;
	my $message;

	if (!$g{tPendingActionTimer}) {
		return 0;
	}

	$g{log}->is_debug && $g{log}->debug("Killing timer # $g{tPendingActionTimer}..");
	Slim::Utils::Timers::killSpecific($g{tPendingActionTimer});
	$g{tPendingActionTimer} = 0;

	#Action is no longer pending..
	if (defined($item)) {
		$item->{isSleepDefered} = 0;
	}
	$g{hPendingAction} = { };

	#desplay the cancel message on all players..
	$message = string('PLUGIN_SRVRPOWERCTRL_CANCELED_MSG');
	Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage (undef, $message, 3);

	$g{log}->is_debug && $g{log}->debug( "$message");
	return 1;
}


sub blockAction {
	my ($client, $set, $caller, $reason) = @_;
	my $blockcode;
	my $element;
	my $num;
	my $nCurrentBlocks;
	my $nBlockCount = 0;
	my $numremain = 0;

	if (!defined($set)) {
		$g{log}->is_debug && $g{log}->debug("blockAction: bad param!");
		return 0;
	}

	#$nCurrentBlocks = (defined(@{$g{aBlockAction}}) ? (@{$g{aBlockAction}}) : 0);
	$nCurrentBlocks = (@{$g{aBlockAction}});

	$g{log}->is_debug && $g{log}->debug("Begin: there are $nCurrentBlocks blockactions set.");

	if ($set eq 'set') {

		if ( $caller eq 'viacli' && $reason eq 'blockfile') {
			Plugins::SrvrPowerCtrl::Block::CreateBlockFile();
			$blockcode = Plugins::SrvrPowerCtrl::Block::GetBlockFileName();
			return $blockcode;
		}

		$blockcode = int(rand(999999)) + 1;

		$g{log}->is_debug && $g{log}->debug("Pushing blockAction caller: $caller, reason: $reason, blockcode: $blockcode");

		push ( @{$g{aBlockAction}},
			{
				client		=> $client,
				caller		=> $caller,
				reason		=> $reason,
				blockcode	=> $blockcode,
			} );

		#re-initialize the menu..
		Plugins::SrvrPowerCtrl::Menu::initActionItems();
		return $blockcode;

	} elsif ($set eq 'count' ) {
		$nBlockCount = 0;
		if (Plugins::SrvrPowerCtrl::Block::BlockFileExists()) {
			$nBlockCount++;
		}

		#count the valid blocks..
		foreach my $element (@{$g{aBlockAction}}) {
			#skip empty block elements..
			if ( defined($element->{'caller'}) ) {
				$nBlockCount++;
			}
		}
		return $nBlockCount;

	} elsif ($set eq 'clear' ) {
		$nBlockCount = 0;
		my $bBlockfileExists = Plugins::SrvrPowerCtrl::Block::BlockFileExists();

		if ($bBlockfileExists) {
			$nBlockCount++;
		}

		#count the valid blocks..
		foreach my $element (@{$g{aBlockAction}}) {
			#skip empty block elements..
			if ( defined($element->{'caller'}) ) {
				$nBlockCount++;
			}
		}

		if ( $caller eq 'viacli' && $reason eq 'blockfile' && $bBlockfileExists) {
			if ( Plugins::SrvrPowerCtrl::Block::DeleteBlockFile() ) {
				return --$nBlockCount;
			} else {
				return -1;
			}
		}


		$num = 0;

		foreach my $element (@{$g{aBlockAction}}) {
			#skip empty block elements..
			if ( defined($element->{'caller'}) ) {
				#Don't worry about blockcode security if the caller is viacli or softblock..
				if ( $caller  =~ m/^viacli$/i && ($element->{'caller'} eq $caller) ||
					 $caller =~ m/^softblock$/i && ($element->{'caller'} eq $caller)) {
					$g{log}->is_debug && $g{log}->debug("Deleting blockAction[$num] caller: $caller, reason: $reason");
					#delete $g{aBlockAction}[$num];
					splice @{$g{aBlockAction}}, $num, 1;
					#re-initialize the menu..
					Plugins::SrvrPowerCtrl::Menu::initActionItems();
					return --$nBlockCount;
				} elsif ( ($element->{'caller'} eq $caller) && ($element->{'blockcode'} eq $reason) ) {
					$g{log}->is_debug && $g{log}->debug("Deleting blockAction[$num] caller: $caller, reason: $reason, blockcode: $element->{'blockcode'}");
					#delete $g{aBlockAction}[$num];
					splice @{$g{aBlockAction}}, $num, 1;
					#re-initialize the menu..
					Plugins::SrvrPowerCtrl::Menu::initActionItems();
					return --$nBlockCount;
				}
			}
			$num++;
		}
	}



	$g{log}->is_debug && $g{log}->debug("End: there are " . (@{$g{aBlockAction}}) . " blockactions set.");
	$g{log}->is_debug && $g{log}->debug("blockAction $set: no action taken!..");

	return -1;
}


# ----------------------------
# thanks to mavit for this..
our %menuFunctions = (
	# normal up/right/left/down navigation:
	# all we offer is a way to exit this mode
	'left' => sub  {
		my $client = shift;
		my $button = shift;
		my $id = $client->id();
		Slim::Buttons::Common::popModeRight($client);
        },
	# and the function that does the work
	'ourSleepHoldButtonHandler' => sub {
		my $client = shift;
		&Plugins::SrvrPowerCtrl::SleepButton::ourSleepHoldButtonHandler($client);
	},
);


# ---------------------------------------------------
# This is called by the server to work out what to do
# when the user presses buttons on the remote.

sub getFunctions {

	return \%menuFunctions;
}

# ----------------------------------------------------------------------------------------
# Return the language independent string for the plugin name.  This will be passed through
# the strings function to get the appropriate language version.

sub getDisplayName {

	return 'PLUGIN_SRVRPOWERCTRL_MODULE_NAME';
}


1;

__END__
