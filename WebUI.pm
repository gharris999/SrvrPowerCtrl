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
#    Webmenu.pm -- handler for SrvrPowerCtrl actions initiated via the SC web UI..
#                  Thanks to indifference_engine for suggesting this.
#


package Plugins::SrvrPowerCtrl::WebUI;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Validate;
use Slim::Utils::OSDetect;
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Strings qw(string);
use URI::Escape;


#Global Variables..
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;


my $plugin; # the main plugin class

sub new {
	my $class = shift;
	$plugin   = shift;

	#$g{log}->is_debug && $g{log}->debug("Called!");
	$class->SUPER::new($plugin);
}

# ----------------------------------------------------------------------------------------
# Show the SrvrPowerCtrl menu on the SC web UI home 'Extras' menu

sub EscapeURL {
	my ($url, $addendum) = @_;

	#$g{log}->is_debug && $g{log}->debug("url before: $url");

	#$url = uri_escape($url);

	#escape the '/' elements..
	$url =~ s!\/!\\/!g;
	#escape the dot..
	$url =~ s!([.])!\\\.!g;
	#add on any parameters
	$url = "${url}\.*";

	#$g{log}->is_debug && $g{log}->debug("url after: $url");

	return $url;
}

my $bWebUIIsActive = 0;

sub ActivateWebUI {
	my $bEnable = shift;

	my $urlWebUI  = 'plugins/SrvrPowerCtrl/webui.html';
	my $urlAction = 'plugins/SrvrPowerCtrl/action.html';
	my $urlActionDone = 'plugins/SrvrPowerCtrl/completed.html';
	my $urlActionCanceled = 'plugins/SrvrPowerCtrl/canceled.html';
	my $urlPrefix = "\\/";
	#my $urlSuffix = "\\.*";


	if ($bEnable) {
		#Don't re-activate if already active..
		if (!$bWebUIIsActive) {
			#Tack our menu onto the Extras menu..
			Slim::Web::Pages->addPageLinks("plugins", { $plugin->getDisplayName() => $urlWebUI });
			Slim::Web::Pages->addPageLinks("icons", { $plugin->getDisplayName() => $plugin->_pluginDataFor('icon') });

			#Provide CSRF protection for the page and set the reference to the page's pre-processing handler..
			$urlWebUI = EscapeURL($urlWebUI);
			$urlAction = EscapeURL($urlAction, ".*");
			$urlActionDone = EscapeURL($urlActionDone, "\.*");
			$urlActionCanceled = EscapeURL($urlActionCanceled, ".*");

			#for SBS 7.4 and later..
			#if ( $g{nSCVersion} >= 7.4 ) {
			#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
			if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') >= 0) {
				Slim::Web::Pages->addPageFunction($urlWebUI, \&RenderWebUIMenu);
				Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlWebUI);

				Slim::Web::Pages->addPageFunction( $urlAction, \&RenderActionPage);
				Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlAction);

				Slim::Web::Pages->addPageFunction( $urlActionDone, \&RenderActionDonePage);
				#Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlActionDone);

				Slim::Web::Pages->addPageFunction($urlActionCanceled, \&RenderActionCanceledPage);
				#Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlActionCanceled);

			} else {	#for SC 7.3.x and earlier..
				Slim::Web::HTTP::addPageFunction($urlWebUI, \&RenderWebUIMenu);
				Slim::Web::HTTP::protect($urlPrefix . $urlWebUI);

				Slim::Web::HTTP::addPageFunction( $urlAction, \&RenderActionPage);
				Slim::Web::HTTP::protect($urlPrefix . $urlAction);

				Slim::Web::HTTP::addPageFunction( $urlActionDone, \&RenderActionDonePage);
				#Slim::Web::HTTP::protect($urlPrefix . $urlActionDone);
				Slim::Web::HTTP::addPageFunction($urlActionCanceled, \&RenderActionCanceledPage);
				#Slim::Web::HTTP::protect($urlPrefix . $urlActionCanceled);

			}
			$bWebUIIsActive = 1;
		}
	} else {
		if ($bWebUIIsActive) {
			#Kill our menu on the Extras menu..
			Slim::Web::Pages->addPageLinks("plugins", { $plugin->getDisplayName() => undef });
			$bWebUIIsActive = 0;
		}
	}

	$g{log}->is_debug && $g{log}->debug('WebUI ' . (($bEnable && $bWebUIIsActive) ? '' : 'de-') . 'activated!');


	return ($bEnable && $bWebUIIsActive);
}


# Draws the plugin's web ui page off the extras menu..
sub RenderWebUIMenu {
	my ($client, $params) = @_;
	my @actions = ();
	my $action;

	#$g{log}->is_debug && $g{log}->debug("Called! params == " . Data::Dump::dump($params));

	#Rebuild the action items every time?
	Plugins::SrvrPowerCtrl::Menu::initActionItems();

	foreach my $item (@{$g{aActions}}) {
		if ($item->{menuindex} ge 0) {
			$action = ();
			$action = {
				'action'	=> uc($item->{'action'}),
				'menutext' => $item->{'menutext'},
			};
			push (@actions, $action);
		}
	}

	$params->{actionlist} = \@actions;

	$params->{srvrpowerctrl_stats} = Plugins::SrvrPowerCtrl::Util::SrvrPowerCtrlStats();

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}


# Draws the action page..
sub RenderActionPage {
	my ($client, $params) = @_;
	my $n;
	my $action;
	my $item;
	my $nDeferTime;
	my $timeoutmsg;
	my $message;

	#$g{log}->is_debug && $g{log}->debug("Called! client == " . $client->name() || 'no client' . ", param == " . Data::Dump::dump($params));

	$nDeferTime = 0;
	#add sleep-playing time to defer time??

	$action = $params->{url_query};
	$action = lc(substr($action, 7));
	$n = index($action, "&");
	if ($n > 0) {
		$action = substr($action, 0, $n);
	}


	$g{log}->is_debug && $g{log}->debug("action == $action");
	$item = Plugins::SrvrPowerCtrl::Menu::findActionItem($action);

	if (defined($item)) {

		#Check to see if there is already a pending action..
		if (!$g{tPendingActionTimer}) {
			#cue up the action..
			$g{log}->is_debug && $g{log}->debug("Cueing up action $action");

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

			# Prepare the action for execution...the action is only cancelable from the web page..
			if (Plugins::SrvrPowerCtrl::Plugin::prepareAction($client, $item, 1)) {
				$timeoutmsg = string( 'PLUGIN_SRVRPOWERCTRL_TIMEOUT_MSG' );
				$timeoutmsg = sprintf($timeoutmsg, $nDeferTime);
				$params->{refreshurl} = "plugins/SrvrPowerCtrl/completed.html";
				$message = $item->{'message'} . ' ' . $timeoutmsg;

			} else {
				#we're blocked...why?
				$params->{refreshurl} = "plugins/SrvrPowerCtrl/canceled.html";
				$message = Plugins::SrvrPowerCtrl::Block::GetBlockReasonMessage($action);
				$nDeferTime = $g{prefs}->nRegretDelay;
			}

		} else {
			# Already a pending action...just report on it..
			$nDeferTime = $g{hPendingAction}->{exeTime} - time();
			$message = Plugins::SrvrPowerCtrl::Plugin::GetPendingActionMessage($action);
			$timeoutmsg = string( 'PLUGIN_SRVRPOWERCTRL_TIMEOUT_MSG' );
			$timeoutmsg = sprintf($timeoutmsg, $nDeferTime);
			$params->{refreshurl} = "plugins/SrvrPowerCtrl/completed.html";
			$message = $message . ' ' . $timeoutmsg;
		}

	} else {
		# We don't know about this action....
		$params->{refreshurl} = "plugins/SrvrPowerCtrl/canceled.html";
		$nDeferTime += $g{prefs}->nRegretDelay;
		$message = "Bad action: $action";
	}

	$g{log}->is_debug && $g{log}->debug("$message");

	$params->{refreshtime} = $nDeferTime;
	$params->{actionmessage} = $message;
	$params->{action} = $action;

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}

sub RenderActionCanceledPage {
	my ($client, $params) = @_;
	my $message;
	my $nDeferTime;

	#$g{log}->is_debug && $g{log}->debug("Called! client == " . $client->name() || 'no client' . ", param == " . Data::Dump::dump($params));

	$nDeferTime = $g{prefs}->nRegretDelay;

	if (!$g{tPendingActionTimer}) {
		$message = string('PLUGIN_SRVRPOWERCTRL_BLOCKED_MSG');
	} else {
		$message = string('PLUGIN_SRVRPOWERCTRL_CANCELED_MSG');
		Plugins::SrvrPowerCtrl::Plugin::cancelAction($client);
	}

	$g{log}->is_debug && $g{log}->debug("$message");
	$params->{actionmessage} = $message;
	$params->{refreshtime} = $nDeferTime;
	$params->{refreshurl} = "home.html";

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}


# Draws the action done page..
sub RenderActionDonePage {
	my ($client, $params) = @_;
	my $n;
	my $action;
	my $item;
	my $message;
	my $confmessage;
	my $nDeferTime;

	#$g{log}->is_debug && $g{log}->debug("Called! client == " . $client->name() || 'no client' . ", param == " . Data::Dump::dump($params));

	$params->{refreshurl} = "";

	$action = $params->{url_query};
	$action = lc(substr($action, 7));
	#strip out any other parameters..
	#suspend2AS&player=00%3a04%3a20%3a06%3a9e%3a70
	$n = index($action, "&");
	if ($n > 0) {
		$action = substr($action, 0, $n);
	}

	$g{log}->is_debug && $g{log}->debug("action == $action");
	$item = Plugins::SrvrPowerCtrl::Menu::findActionItem($action);

	if (defined($item)) {
		$message = $item->{'message'} . "..";
		#$confmessage = string('PLUGIN_SRVRPOWERCTRL_' . uc($action) . '_DONE_MSG') . "..";
		$confmessage = $item->{'messagedone'} . "..";
		$nDeferTime = $item->{refreshwait};

		if ( $item->{'push2as'} &&
			$g{prefs}->szAltServerName eq Slim::Networking::SqueezeNetwork->get_server('sn') &&
			!$g{prefs}->{bNoWebUIRedirect2SN} ) {
			$params->{refreshurl} = 'http://' . Slim::Networking::SqueezeNetwork->get_server('sn') . '/player/playerControl';
			$nDeferTime = 5;
		} else {
			$params->{refreshurl} = "home.html";
		}
	} else {
		$message = "Bad action: $action";
		$confmessage = $message;
		$params->{refreshurl} = "home.html";
		$nDeferTime = 15;
	}


	$params->{refreshtime} = $nDeferTime;
	$params->{actionmessage} = $message;
	$params->{confirmedmessage} = $confmessage;

	#$g{log}->is_debug && $g{log}->debug("params == " . Data::Dump::dump(($params));

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}


1;

__END__
