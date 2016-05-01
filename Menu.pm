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
#    Menu.pm -- Menu init, display & action routines..
#


package Plugins::SrvrPowerCtrl::Menu;

use base qw(Slim::Plugin::Base);
use strict;

use Slim::Utils::Strings qw(string);

#Global Variables..
use Plugins::SrvrPowerCtrl::Settings ();
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

sub max ($$) { $_[$_[0] < $_[1]] }

# Initialize the menu array var..
# -------------------------------
sub initActionItems {

   my $menuindex = 0;

   #$g{log}->is_debug && $g{log}->debug( "Initializing ActionItems.  Squeezecenter version is $g{nSCVersion}");

   #clear the arrays;
   @{ $g{aActions} } = ();

   #############################################################################
   # Std menu items..
   #############################################################################

   push ( @{$g{aActions}}, {
	  action			    => 'shutdown',
	  actionid			    => 0x00000001,
	  menuindex			    => ($g{prefs}->bInclude_Shutdown ? $menuindex++ : -1),
	  menutext			    => string('PLUGIN_SRVRPOWERCTRL_SHUTDOWN'),
	  message			    => string('PLUGIN_SRVRPOWERCTRL_SHUTDOWN_MSG'),
	  messagedone           => string('PLUGIN_SRVRPOWERCTRL_SHUTDOWN_DONE_MSG'),
	  dispblock             => 1,
	  #
	  #getcommandargcoderef -- executed in Plugins::SrvrPowerCtrl::Plugin::performAction
	  #	Args to the coderef will be: ($client $item)
	  #	..should return one of the following:
	  #	undef == no cmd line args to feed to the script;
	  #	-1 == error: don't execute the $item->{command};
	  #	anythihng else: is a cmd line arg to pass on to $item->{command}.
	  #	For testing, use:
	  #getcommandargcoderef	=> \&Plugins::SrvrPowerCtrl::Util::TestCoderefFail,
	  #
	  getcommandargcoderef  => undef,
	  poweroffplayers       => $g{prefs}->bPowerOffPlayers,
	  push2as               => 0,
	  checkblock            => 1,
	  cancelwait			=> $g{prefs}->nRegretDelay,
	  cmdwait				=> 5,
	  refreshwait			=> -1,
	  stopsc				=> 1,
	  setrtcwakeup			=> Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup(),
	  isSleepDefered		=> 0,
	  command				=> $g{prefs}->szShutdown_cmd,
   }, );

   push ( @{$g{aActions}}, {
	  action				=> 'suspend',
	  actionid				=> 0x00000004,
	  menuindex				=> ($g{prefs}->bInclude_Suspend ? $menuindex++ : -1),
	  menutext				=> string('PLUGIN_SRVRPOWERCTRL_SUSPEND'),
	  message				=> string('PLUGIN_SRVRPOWERCTRL_SUSPEND_MSG'),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_SUSPEND_DONE_MSG'),
	  dispblock				=> 1,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> $g{prefs}->bPowerOffPlayers,
	  push2as				=> 0,
	  checkblock			=> 1,
	  cancelwait			=> $g{prefs}->nRegretDelay,
	  cmdwait				=> 5,
	  refreshwait			=> -1,
	  stopsc				=> 0,
	  setrtcwakeup			=> Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup(),
	  isSleepDefered		=> 0,
	  command				=> $g{prefs}->szSuspend_cmd,
   }, );

   push ( @{$g{aActions}}, {
	  action				=> 'hibernate',
	  actionid				=> 0x00000008,
	  menuindex				=> ($g{prefs}->bInclude_Hibernate ? $menuindex++ : -1),
	  menutext				=> string('PLUGIN_SRVRPOWERCTRL_HIBERNATE'),
	  message				=> string('PLUGIN_SRVRPOWERCTRL_HIBERNATE_MSG'),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_HIBERNATE_DONE_MSG'),
	  dispblock				=> 1,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> $g{prefs}->bPowerOffPlayers,
	  push2as				=> 0,
	  checkblock			=> 1,
	  cancelwait			=> $g{prefs}->nRegretDelay,
	  cmdwait				=> 5,
	  refreshwait			=> -1,
	  stopsc				=> 0,
	  setrtcwakeup			=> Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup(),
	  isSleepDefered		=> 0,
	  command				=> $g{prefs}->szHibernate_cmd,
   }, );


   push ( @{$g{aActions}}, {
	  action				=> 'shutdown2as',
	  actionid				=> 0x00000101,
	  menuindex				=> ($g{prefs}->bInclude_Shutdown2AS ? $menuindex++ : -1),
	  menutext				=> sprintf(string('PLUGIN_SRVRPOWERCTRL_SHUTDOWN2AS'), $g{prefs}->szAltServerName),
	  message				=> sprintf(string('PLUGIN_SRVRPOWERCTRL_SHUTDOWN2AS_MSG'), $g{prefs}->szAltServerName),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_SHUTDOWN2AS_DONE_MSG'),
	  dispblock				=> 1,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> $g{prefs}->bPowerOffPlayers,
	  push2as				=> 1,
	  checkblock			=> 1,
	  cancelwait			=> $g{prefs}->nRegretDelay,
	  cmdwait				=> $g{prefs}->nAltServerPostPushDelay,
	  refreshwait			=> $g{prefs}->nAltServerPostPushDelay,
	  stopsc				=> 1,
	  setrtcwakeup			=> Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup(),
	  isSleepDefered		=> 0,
	  command				=> $g{prefs}->szShutdown_cmd,
   }, );

   push ( @{$g{aActions}}, {
	  action				=> 'suspend2as',
	  actionid				=> 0x00000104,
	  menuindex				=> ($g{prefs}->bInclude_Suspend2AS ? $menuindex++ : -1),
	  menutext				=> sprintf(string('PLUGIN_SRVRPOWERCTRL_SUSPEND2AS'), $g{prefs}->szAltServerName),
	  message				=> sprintf(string('PLUGIN_SRVRPOWERCTRL_SUSPEND2AS_MSG'), $g{prefs}->szAltServerName),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_SUSPEND2AS_DONE_MSG'),
	  dispblock				=> 1,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> $g{prefs}->bPowerOffPlayers,
	  push2as				=> 1,
	  checkblock			=> 1,
	  cancelwait			=> $g{prefs}->nRegretDelay,
	  #cmdwait				=> ( $g{prefs}->bAltServerPowerOffPlayers ? max(30,$g{prefs}->nAltServerPostPushDelay) : $g{prefs}->nAltServerPostPushDelay ),
	  cmdwait				=> $g{prefs}->nAltServerPostPushDelay,
	  refreshwait			=> $g{prefs}->nAltServerPostPushDelay,
	  stopsc				=> 0,
	  setrtcwakeup			=> Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup(),
	  isSleepDefered		=> 0,
	  command				=> $g{prefs}->szSuspend_cmd,
   }, );

   push ( @{$g{aActions}}, {
	  action				=> 'hibernate2as',
	  actionid				=> 0x00000108,
	  menuindex				=> ($g{prefs}->bInclude_Hibernate2AS ? $menuindex++ : -1),
	  menutext				=> sprintf(string('PLUGIN_SRVRPOWERCTRL_HIBERNATE2AS'), $g{prefs}->szAltServerName),
	  message				=> sprintf(string('PLUGIN_SRVRPOWERCTRL_HIBERNATE2AS_MSG'), $g{prefs}->szAltServerName),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_HIBERNATE2AS_DONE_MSG'),
	  dispblock				=> 1,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> $g{prefs}->bPowerOffPlayers,
	  push2as				=> 1,
	  checkblock			=> 1,
	  cancelwait			=> $g{prefs}->nRegretDelay,
	  #cmdwait				=> ( $g{prefs}->bAltServerPowerOffPlayers ? max(30,$g{prefs}->nAltServerPostPushDelay) : $g{prefs}->nAltServerPostPushDelay ),
	  cmdwait				=> $g{prefs}->nAltServerPostPushDelay,
	  refreshwait			=> $g{prefs}->nAltServerPostPushDelay,
	  stopsc				=> 0,
	  setrtcwakeup			=> Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup(),
	  isSleepDefered		=> 0,
	  command				=> $g{prefs}->szHibernate_cmd,
   }, );

   push ( @{$g{aActions}}, {
	  action				=> 'reboot',
	  actionid				=> 0x00000002,
	  menuindex				=> ($g{prefs}->bInclude_Reboot ? $menuindex++ : -1),
	  menutext				=> string('PLUGIN_SRVRPOWERCTRL_REBOOT'),
	  message				=> string('PLUGIN_SRVRPOWERCTRL_REBOOT_MSG'),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_REBOOT_DONE_MSG'),
	  dispblock				=> 1,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> 0,
	  push2as				=> 0,
	  checkblock			=> 1,
	  cancelwait			=> $g{prefs}->nRegretDelay,
	  cmdwait				=> 5,
	  refreshwait			=> 90,
	  stopsc				=> 0,
	  setrtcwakeup			=> 0,
	  isSleepDefered		=> 0,
	  command				=> $g{prefs}->szReboot_cmd,
   }, );

   push ( @{$g{aActions}}, {
	  action				=> 'screstart',
	  actionid				=> 0x80000000,
	  menuindex				=> ($g{prefs}->bInclude_SCRestart ? $menuindex++ : -1),
	  menutext				=> string('PLUGIN_SRVRPOWERCTRL_SCRESTART'),
	  message				=> string('PLUGIN_SRVRPOWERCTRL_SCRESTART_MSG'),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_SCRESTART_DONE_MSG'),
	  dispblock				=> 1,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> 0,
	  push2as				=> 0,
	  checkblock			=> 1,
	  cancelwait			=> $g{prefs}->nRegretDelay,
	  cmdwait				=> 5,
	  refreshwait			=> 60,
	  stopsc				=> 0,	#let the script stop the service!
	  setrtcwakeup			=> 0,
	  isSleepDefered		=> 0,
	  command				=> $g{prefs}->szSCRestart_cmd,
   }, );


   #############################################################################
   # Custom commands..
   #############################################################################

   my $aCustCommands = $g{prefs}->get('aCustCmds');

   if ( ref($aCustCommands) eq 'ARRAY') {
	  my $n = 0;

	  foreach my $custcmd (@$aCustCommands) {
		 if ( $custcmd->{'command'} ) {
			#custcmds with labels starting with '.' are hidden..
			my $bNoDispMenuText = $custcmd->{'label'} =~ m/^\..*$/;

			#$g{log}->is_debug && $g{log}->debug("Adding custom command # $n : $custcmd->{'label'} : $custcmd->{'command'} ");

			push ( @{$g{aActions}}, {
			   action				=> "customcmd$n",
			   actionid				=> 0x00040000 + $n,
			   #menuindex			=> (substr($custcmd->{'label'}, 0, 1) eq "\." ? -1 : $menuindex++),
			   menuindex			=> ($bNoDispMenuText ? -1 : $menuindex++),
			   menutext				=> $custcmd->{'label'},
			   message				=> string('PLUGIN_SRVRPOWERCTRL_CUSTOMCMD_MSG') . ' ' . $custcmd->{'label'},
			   messagedone			=> string('PLUGIN_SRVRPOWERCTRL_CUSTOMCMD_DONE_MSG'),
			   messagetime			=> ($bNoDispMenuText ? 0 : undef), 			#Also, hidden custcmds don't display player messages..
			   dispblock			=> 1,
			   getcommandargcoderef	=> undef,
			   poweroffplayers		=> 0,
			   push2as				=> 0,
			   checkblock			=> 1,
			   cancelwait			=> $g{prefs}->nRegretDelay,
			   cmdwait				=> 5,
			   refreshwait			=> 60,
			   stopsc				=> 0,
			   setrtcwakeup			=> 0,
			   isSleepDefered		=> 0,
			   command				=> $custcmd->{'command'},
			}, );
			$n++;
		 }
	  }
   }

   #############################################################################
   # CLI only actions..
   #############################################################################

   push ( @{$g{aActions}}, {
	  action				=> 'pushtoas',
	  actionid				=> 0x00000200,
	  menuindex				=> -1,		#Just a CLI action..not on any menus..
	  menutext				=> "",
	  message				=> string('PLUGIN_SRVRPOWERCTRL_PUSH2AS_MSG'),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_PUSH2AS_DONE_MSG'),
	  dispblock				=> 0,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> 0,	# Taken care of in PushToAltServer			$g{prefs}->bPowerOffPlayers,
	  push2as				=> 1,
	  checkblock			=> 0,
	  cancelwait			=> 0,
	  cmdwait				=> 1,
	  refreshwait			=> 1,
	  stopsc				=> 0,
	  setrtcwakeup			=> 0,
	  isSleepDefered		=> 0,
	  #command				=> \&Plugins::SrvrPowerCtrl::AltServer::PushToAltServer,
	  command				=> sub { return 0; },
   }, );

   push ( @{$g{aActions}}, {
	  action				=> 'pullfromas',
	  actionid				=> 0x00000400,
	  menuindex				=> -1,		#Just a CLI action..not on any menus..
	  menutext				=> "",
	  message				=> string('PLUGIN_SRVRPOWERCTRL_GETFROMSN_MSG'),
	  messagedone			=> string('PLUGIN_SRVRPOWERCTRL_GETFROMSN_DONE_MSG'),
	  dispblock				=> 0,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> 0,
	  push2as				=> 0,
	  checkblock			=> 0,
	  cancelwait			=> 0,
	  cmdwait				=> 1,
	  refreshwait			=> 1,
	  stopsc				=> 0,
	  setrtcwakeup			=> 0,
	  isSleepDefered		=> 0,
	  command				=> \&Plugins::SrvrPowerCtrl::AltServer::PullFromAltServer,
   }, );

   if ( $g{log}->is_debug ) {

	  push ( @{$g{aActions}}, {
		 action				=> 'test',
		 actionid				=> 0x00008000,
		 menuindex				=> -1,		#Just a CLI action..not on any menus..
		 menutext				=> "",
		 message				=> "Initiating Test!",
		 messagedone			=> "Test! is done!",
		 dispblock				=> 1,
		 getcommandargcoderef	=> undef,
		 poweroffplayers		=> 0,
		 push2as					=> 0,
		 checkblock				=> 0,
		 cancelwait				=> 0,
		 cmdwait				=> 1,
		 refreshwait			=> 1,
		 stopsc					=> 0,
		 setrtcwakeup			=> Plugins::SrvrPowerCtrl::Alarms::ShouldSetRTCWakeup(),
		 isSleepDefered			=> 0,
		 command				=> \&Plugins::SrvrPowerCtrl::Util::test,
	  }, );

   }

   #############################################################################
   # Block / Unblock
   #############################################################################
   #$g{log}->is_debug && $g{log}->debug("Adding block-unblock menu item");
   if ( ! Plugins::SrvrPowerCtrl::Block::IsBlocked() ) {
	  push ( @{$g{aActions}}, {
		 action				=> 'setblock',
		 actionid				=> 0x00010000,
		 menuindex				=> $menuindex++,
		 menutext				=> string('PLUGIN_SRVRPOWERCTRL_SETBLOCK'),
		 message				=> string('PLUGIN_SRVRPOWERCTRL_SETBLOCK_MSG'),
		 messagedone			=> string('PLUGIN_SRVRPOWERCTRL_SETBLOCK_DONE_MSG'),
		 dispblock				=> 0,
		 getcommandargcoderef	=> undef,
		 poweroffplayers		=> 0,
		 push2as					=> 0,
		 checkblock				=> 0,
		 cancelwait				=> 0,
		 cmdwait				=> 2,
		 refreshwait			=> 15,
		 stopsc					=> 0,
		 setrtcwakeup			=> 0,
		 isSleepDefered			=> 0,
		 command				=> \&Plugins::SrvrPowerCtrl::Block::SetBlock,
	  }, );

   } else {
	  push ( @{$g{aActions}}, {
		 action					=> 'clearblock',
		 actionid				=> 0x00020000,
		 menuindex				=> $menuindex++,
		 menutext				=> string('PLUGIN_SRVRPOWERCTRL_CLEARBLOCK'),
		 message				=> string('PLUGIN_SRVRPOWERCTRL_CLEARBLOCK_MSG'),
		 messagedone			=> string('PLUGIN_SRVRPOWERCTRL_CLEARBLOCK_DONE_MSG'),
		 dispblock				=> 0,
		 getcommandargcoderef	=> undef,
		 poweroffplayers		=> 0,
		 push2as					=> 0,
		 checkblock				=> 0,
		 cancelwait				=> 0,
		 cmdwait				=> 2,
		 refreshwait			=> 15,
		 stopsc					=> 0,
		 setrtcwakeup			=> 0,
		 isSleepDefered			=> 0,
		 command				=> \&Plugins::SrvrPowerCtrl::Block::ClearBlock,
	  }, );
   }

   push ( @{$g{aActions}}, {
	  action				=> 'noaction',
	  actionid				=> 0x00000000,
	  menuindex				=> -1,		#Just a CLI action..not on any menus..
	  menutext				=> string('PLUGIN_SRVRPOWERCTRL_NOACTION'),
	  message				=> string('PLUGIN_SRVRPOWERCTRL_NOACTION'),
	  messagetime			=> 0,
	  messagedone			=> "",
	  dispblock				=> 0,
	  getcommandargcoderef	=> undef,
	  poweroffplayers		=> 0,
	  push2as				=> 0,
	  checkblock			=> 0,
	  cancelwait			=> 0,
	  cmdwait				=> 0,
	  refreshwait			=> -1,
	  stopsc				=> 0,
	  setrtcwakeup			=> 0,
	  isSleepDefered		=> 0,
	  command				=> sub { return 0; },
   }, );

   #$g{log}->is_debug && $g{log}->debug("Action Items: ". Data::Dump::dump($g{aActions}));



}


# Called from CLI..return the whole menuitem
# from the actionitem string..
# --------------------------------------------
sub findActionItem {
	my $szAction = shift || return undef;

	$szAction = lc($szAction);

	foreach my $actionItem (@{$g{aActions}}) {
	  if ($actionItem->{'action'} eq $szAction) {
		 return $actionItem;
	  }
	}

	return undef;
}

#Used for finding 'hidden' custcmd action items..
sub findActionItemByMenuText {
	my $szActionLabel = shift || return undef;

	$szActionLabel = lc($szActionLabel);

	foreach my $actionItem (@{$g{aActions}}) {
	  if (lc($actionItem->{'menutext'}) eq $szActionLabel) {
		 return $actionItem;
	  }
	}

	return undef;
}

sub findActionItemByMenuIndex {
	my $nIndex = shift;

	foreach my $actionItem (@{$g{aActions}}) {
	  if ($actionItem->{'menuindex'} eq $nIndex) {
		 return $actionItem;
	  }
	}

	return undef;
}

sub findActionItemNum {
	my $szAction = shift;
	my $nItem = 0;

	if (!defined($szAction)) {
	return -1;
	}

	$szAction = lc($szAction);

	foreach my $actionItem (@{$g{aActions}}) {
	  if ($actionItem->{'action'} eq $szAction) {
		 return $nItem;
	  }
	$nItem++;
	}

	return -1;
}

# Player plugin menu IR remote right or left..
# Set in Plugin::setMode
# --------------------------------------------
sub doInputListCallback {
   my ($client, $keypress) = @_;
   my $listIndex;
   my $action;
   my $item;
   my $message;
   my $timeoutmsg;
   my $nDeferTime;

   if ($keypress eq 'right') {

	  # carry out actions
	  $listIndex = $client->modeParam('listIndex');
	  $g{log}->is_debug && $g{log}->debug("listIndex == $listIndex..");

	  $item = findActionItemByMenuIndex($listIndex);

	  if (defined($item)) {
		 Plugins::SrvrPowerCtrl::Plugin::prepareAction($client, $item, 0);
	  } else {
		 $g{log}->error("Could not find action item # $listIndex..");
	  }

   } elsif ($keypress eq 'left') {
	  Slim::Buttons::Common::popModeRight($client);

	  if ( $g{tPendingActionTimer} ) {
	  #This is a cancel request..
		 Plugins::SrvrPowerCtrl::Plugin::cancelAction($client);
	  }

   } else {
   $g{log}->warn( "Unhandled callback item = $keypress");
   }
}

# Player plugin menu IR remote up or down..
# Set in Plugin::setMode
# -----------------------------------------
sub doInputListChange {
	my ($client, $item) = @_;
	$g{log}->is_debug && $g{log}->debug( "$item...");
}

1;
