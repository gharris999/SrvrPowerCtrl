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
#    Jive.pm -- support for SrvrPowerCtrl on SqueezePlay based players' extras menu
#


package Plugins::SrvrPowerCtrl::Jive;

use base qw(Slim::Plugin::Base);
use strict;

#Global Variables..
use Plugins::SrvrPowerCtrl::Settings ();
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

#remember our state..
my $bHasJiveMenu = 0;
my $clientLast;

##Tack our menu onto 'Extras'
sub addJiveMenu {
	my ($PluginClass) = @_;

	if ($bHasJiveMenu) {
		return;
	}

	#Add our processing functions to the dispatch table..
	#Slim::Control::Request::addDispatch(['jivesrvrpowerctrlmenu'],   [0, 1, 0, \&jiveServerPowerControlMenu]);
	Slim::Control::Request::addDispatch(['jivesrvrpowerctrlmenu', '_index', '_quantity'],  [2, 1, 1, \&jiveServerPowerControlMenu]);
	Slim::Control::Request::addDispatch(['jivesrvrpowerctrlaction', '_action','_message'], [0, 0, 0, \&jiveServerPowerControlAction]);

	# Setup our toplevel menu node..
	my @aMenu = ( {
			stringToken	=> Plugins::SrvrPowerCtrl::Plugin::getDisplayName(),
			text		=> Plugins::SrvrPowerCtrl::Plugin::getDisplayName(),
			weight		=> 100,
			id			=> 'pluginSrvrPowerCtrlMenu',
			'icon-id'	=> Plugins::SrvrPowerCtrl::Plugin::getIcon(),
			node		=> 'extras',
			displayWhenOff => 0,
			window		=> {	titleStyle => 'album',
								'icon-id'	=> Plugins::SrvrPowerCtrl::Plugin::getIcon(),
			},

			actions	=> {
				go 		=> {
								player => 0,
								cmd => [ 'jivesrvrpowerctrlmenu', 'actions' ],
								params => {
									menu     => 1,
								},
				},

			},
	});

	# Tack our node onto the extras menu..
	Slim::Control::Jive::registerPluginMenu(\@aMenu, 'extras');
	$bHasJiveMenu = 1;

	$g{log}->is_debug && $g{log}->debug( "Jive menu added!");
}

sub removeJiveMenu {
	if (!$bHasJiveMenu) {
		return;
	}

	$bHasJiveMenu = 0;
	Slim::Control::Jive::deleteMenuItem('pluginSrvrPowerCtrlMenu', $clientLast);
	Slim::Control::Jive::refreshPluginMenus();

	#Slim::Control::Jive::deleteAllMenuItems($clientLast);
	#Slim::Control::Jive::mainMenu($clientLast);
	$g{log}->is_debug && $g{log}->debug( "Jive menu removed!");

}

## Tack our sub-menu items on too (Thanks to bklass for this code..)
sub jiveServerPowerControlMenu {

	my $request = shift;
	my $weight = 10;
	my @jivemenu;

	$clientLast = $request->client();

	if ($request->isNotQuery([['jivesrvrpowerctrlmenu']])) {
		$g{log}->error( "BadDispatch: $request->{_requeststr} !!!");
		$request->setStatusBadDispatch();
		return;
	}

	$g{log}->is_debug && $g{log}->debug( "Processing jive action items request for " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($clientLast, 'name'));

	# Translate our action item data into something Jive can digest..
	foreach my $item (@{$g{aActions}}) {
		if ($item->{menuindex} ge 0) {
			push (@jivemenu, {
					text    => $item->{'menutext'},
					weight  => $weight,
					#actions => { do => { cmd => [ 'srvrpowerctrl', $item->{'action'}, $item->{'message'}, undef, 1 ],	} },
					actions => { do => { cmd => [ 'jivesrvrpowerctrlaction', $item->{'action'}, $item->{'message'}, undef, 1 ],	} },
				},);
			$weight += 10;
		}
	}

	$request->addResult('count', scalar(@jivemenu));
	$request->addResult('offset', 0);
	for my $i (0..$#jivemenu) {
		$request->setResultLoopHash('item_loop', $i, $jivemenu[$i]);
	}

	$request->setStatusDone();
}

## Process requests from a SBController|SBTouch|SBRadio
sub jiveServerPowerControlAction {
	my ($request) = @_;
	my $action = lc($request->getParam( '_action'));
	my $message = $request->getParam( '_message');

	$clientLast = $request->client();

	$g{log}->is_debug && $g{log}->debug("Request $request->{_requeststr} from " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($clientLast, 'name') . "->\[$action, $message\]");

	# If an action is already pending, then this is a request to cancel...
	if ($g{tPendingActionTimer}) {
		Plugins::SrvrPowerCtrl::Plugin::cancelAction($clientLast);
		#restore our jive menu..
		#$g{log}->is_debug && $g{log}->debug("Restoring our jive menu");
		#&addJiveMenu();
		$request->setStatusDone();
		return;
	}

	# Check that this is a valid request
	if( $request->isNotCommand( [['jivesrvrpowerctrlaction']])) {
		$g{log}->error( "BadDispatch: $request->{_requeststr} !!!");
		$request->setStatusBadDispatch();
		return;
	}

	# Check for other allowed action items..
	my $item = Plugins::SrvrPowerCtrl::Menu::findActionItem($action);
	if (!defined($item)) {
		$g{log}->error( "BadParam: $action");
		$request->addResult('_badparam', "BadParam:$action"  );
		$request->setStatusBadParams();
		return;
	}

	#OK, this is a valid request..let's proceed..
	$request->setStatusProcessing();

	#cue up the action..
	if (!Plugins::SrvrPowerCtrl::Plugin::prepareAction($clientLast, $item, 0, 1)) {
		$request->addResult('_action', "$action is blocked.\n");
		$request->setStatusDone();
		return;
	}

	$request->addResult('_action', $action . " in " . $item->{cancelwait} . " seconds.\n");
	$request->setStatusDone();

}


1;
