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
#    Help.pm -- handler functions for SrvrPowerCtrl help pages..
#


package Plugins::SrvrPowerCtrl::Help;


use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Utils::Validate;
use Slim::Utils::OSDetect;
use File::Spec::Functions qw(:ALL);

use Slim::Utils::Strings qw(string);


if ($^O =~ /^m?s?win/i) {		## Are we running windows?
	eval {
	require Win32;
	import Win32;
	} ;
}

#Global Variables..
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

my $hOSs = ();

my $plugin; # the main plugin class

sub new {
	my $class = shift;
	$plugin   = shift;
	my $urlPrefix = "\\/";
	my $urlRedirectHelp	= 'plugins/SrvrPowerCtrl/html/helpredir.html';
	my $urlMainHelp		= 'plugins/SrvrPowerCtrl/html/help.html';
	my $urlTSHelp		= 'plugins/SrvrPowerCtrl/html/troubleshooting.html';
	my $urlLogInfo		= 'plugins/SrvrPowerCtrl/html/loginfo.html';
	my $urlLog			= 'plugins/SrvrPowerCtrl/html/log.html';
	my $urlPrefs		= 'plugins/SrvrPowerCtrl/html/prefs.html';
	my $urlOSHelp;

	#OSs we know how to setup..
	my @aOSs = ('win', 'unix', 'mac');

	#Flag the OSs we know how to setup up..
    for (@aOSs) { $hOSs->{$_} = 1; }

	#$g{log}->is_debug && $g{log}->debug("aOSs: " . Data::Dump::dump(@aOSs));

	#Provide CSRF protection for the page and set the reference to the page's pre-processing handler..
	$urlRedirectHelp	= Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlRedirectHelp);
	$urlMainHelp		= Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlMainHelp);
	$urlTSHelp			= Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlTSHelp);
	$urlLogInfo			= Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlLogInfo);
	$urlLog				= Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlLog);
	$urlPrefs			= Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlPrefs);

	#for SBS 7.4 and later..
	#if ( $g{nSCVersion} >= 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') >= 0) {

		Slim::Web::Pages->addPageFunction($urlRedirectHelp, \&RenderRedirectHelpPage);
		Slim::Web::Pages->addPageFunction($urlMainHelp, \&RenderHelpPage);
		Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlMainHelp);

		Slim::Web::Pages->addPageFunction($urlTSHelp, \&RenderTSHelpPage);
		Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlTSHelp);

		Slim::Web::Pages->addPageFunction($urlLogInfo, \&RenderLogInfoPage);
		Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlLogInfo);

		Slim::Web::Pages->addPageFunction($urlLog, \&RenderLogPage);
		Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlLog);

		Slim::Web::Pages->addPageFunction($urlPrefs, \&RenderPrefsPage);
		Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlPrefs);

		foreach my $szOS (@aOSs) {
			$urlOSHelp = 'plugins/SrvrPowerCtrl/html/' . $szOS . '-help.html';
			$urlOSHelp = Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlOSHelp);
			Slim::Web::Pages->addPageFunction($urlOSHelp, \&RenderOSHelpPage);
			Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlOSHelp);
			#$g{log}->is_debug && $g{log}->debug("$urlOSHelp");
		}

		# Unsupported OS..
		$urlOSHelp = 'plugins/SrvrPowerCtrl/html/' . 'unsuppos-help.html';
		$urlOSHelp = Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlOSHelp);
		Slim::Web::Pages->addPageFunction($urlOSHelp, \&RenderOSHelpPage);
		Slim::Web::HTTP::CSRF->protect($urlPrefix . $urlOSHelp);

	#for SC 7.3.4 and earlier..
	} else {

		Slim::Web::HTTP::addPageFunction($urlRedirectHelp, \&RenderRedirectHelpPage);
		Slim::Web::HTTP::addPageFunction($urlMainHelp, \&RenderHelpPage);
		Slim::Web::HTTP::protect($urlPrefix . $urlMainHelp);

		Slim::Web::HTTP::addPageFunction($urlTSHelp, \&RenderTSHelpPage);
		Slim::Web::HTTP::protect($urlPrefix . $urlTSHelp);

		Slim::Web::HTTP::addPageFunction($urlLogInfo, \&RenderLogInfoPage);
		Slim::Web::HTTP::protect($urlPrefix . $urlLogInfo);

		Slim::Web::HTTP::addPageFunction($urlLog, \&RenderLogPage);
		Slim::Web::HTTP::protect($urlPrefix . $urlLog);

		Slim::Web::HTTP::addPageFunction($urlPrefs, \&RenderPrefsPage);
		Slim::Web::HTTP::protect($urlPrefix . $urlPrefs);

		# Supported OSs..
		foreach my $szOS (@aOSs) {
			$urlOSHelp = 'plugins/SrvrPowerCtrl/html/' . $szOS . '-help.html';
			$urlOSHelp = Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlOSHelp);
			Slim::Web::HTTP::addPageFunction($urlOSHelp, \&RenderOSHelpPage);
			Slim::Web::HTTP::protect($urlPrefix . $urlOSHelp);
			#$g{log}->is_debug && $g{log}->debug("$urlOSHelp");
		}

		# Unsupported OS..
		$urlOSHelp = 'plugins/SrvrPowerCtrl/html/' . 'unsuppos-help.html';
		$urlOSHelp = Plugins::SrvrPowerCtrl::WebUI::EscapeURL($urlOSHelp);
		Slim::Web::HTTP::addPageFunction($urlOSHelp, \&RenderOSHelpPage);
		Slim::Web::HTTP::protect($urlPrefix . $urlOSHelp);


	}

	$class->SUPER::new($plugin);

	$g{log}->is_debug && $g{log}->debug("HelpUI is activated!");
}

sub RenderRedirectHelpPage {
	my ($client, $params) = @_;
	my $szOSHelpFile;

	$g{log}->is_debug && $g{log}->debug('Called!'); #client == ' . ( eval{$client->name()} || 'no client' ) . ", param == " . Data::Dump::dump($params));

	if ( $hOSs->{"$g{szOS}"} ) {
		$szOSHelpFile = 'plugins/SrvrPowerCtrl/html/' . $g{szOS} . '-help.html';
	# Unsupported OS or distro..
	} else {
		$szOSHelpFile = 'plugins/SrvrPowerCtrl/html/unsuppos-help.html';
	}

	$params->{path} = $szOSHelpFile;
	return RenderOSHelpPage($client, $params);
}

sub RenderHelpPage {
	my ($client, $params) = @_;
	my $szOSHelpLink;
	my $szSBSUser;
	my $szServerName;
	my $szPluginPath;

	#$g{log}->is_debug && $g{log}->debug('Called!'); # client == ' . ( eval{$client->name()} || 'no client' ) . ", param == " . Data::Dump::dump($params));

	$szPluginPath = $g{szAppPath};

	#if ( $g{nSCVersion} < 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	#if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') < 0) {
	#	$szServerName = string('SQUEEZECENTER');
	#} else {
	#	$szServerName = string('SQUEEZEBOX_SERVER');
	#}
	
	$szServerName = Plugins::SrvrPowerCtrl::Util::GetSCName();
	$szSBSUser = $g{szSCUser};

	if ( $hOSs->{"$g{szOS}"} ) {
		$szOSHelpLink = "<a href=\"/plugins/SrvrPowerCtrl/html/$g{szOS}-help.html\" ><h4>" . string("PLUGIN_SRVRPOWERCTRL_" . uc($g{szOS}) . "_HELP_PAGE") . '</h4></a>' ;
	# Unsupported OS or distro..
	} else {
		$szOSHelpLink = "<a href=\"/plugins/SrvrPowerCtrl/html/unsuppos-help.html\" ><h4>" . string('PLUGIN_SRVRPOWERCTRL_UNSUPPOS_HELP_PAGE') . '</h4></a>' ;
	}

	$params->{distro} 			= $g{szDistro};		# [% distro %]
	$params->{setuplink} 		= $szOSHelpLink;	# [% setuplink %]
	$params->{sbsuser} 			= $szSBSUser;		# [% sbsuser %]
	$params->{sbsservername}	= $szServerName;	# [% sbsservername %]
	$params->{pluginpath} 		= $szPluginPath;	# [% pluginpath %]

	#$g{log}->is_debug && $g{log}->debug('params == ' . Data::Dump::dump($params));

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}

sub MyFindInPATH {
    my $file = shift;
    #return $file if -e $file;
    foreach (split ';',$ENV{PATH}) {
        return $_.'\\'.$file if -e $_.'/'.$file;
    }
    return undef;
}



sub IsHelperUtilInstalled {
	my $szCheckFile;

	#Check to see if we're already enabled by looking for file..
	# Windows..
 	if ($g{szOS} eq 'win') {
		$szCheckFile = "SCPowerTool.exe";
		$szCheckFile = MyFindInPATH($szCheckFile);
		$g{log}->is_debug && $g{log}->debug("MyFindInPATH found " . ($szCheckFile ? $szCheckFile : 'nada') );
	# Various linux distros..
	} elsif ( $g{szOS} eq 'unix' || $g{szOS} eq 'mac' ) {
		#Path to one of our scripts..if we're already setup..
		$szCheckFile = '/usr/local/sbin/spc-wakeup.sh';
	} else {
		return (0, undef);
	}

	if (-e $szCheckFile) {
		return (1, $szCheckFile);
	}

	return (0, undef);
}

sub RenderUnsuppOSHelpPage {
	my ($client, $params) = @_;
	my $szDistro = $g{szDistro};
	my $szWarning;
	my $szServerName;
	my $szSBSUser;

	#Get the SC/SBS username..(NA for windows & mac)
	#if ( $g{nSCVersion} < 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	#if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') < 0) {
	#	$szServerName = string('SQUEEZECENTER');
	#} else {
	#	$szServerName = string('SQUEEZEBOX_SERVER');
	#}

	$szServerName = Plugins::SrvrPowerCtrl::Util::GetSCName();
	$szSBSUser = $g{szSCUser};

	# Unsupported OS?
	if ( ! $hOSs->{"$g{szOS}"} ) {
		$szDistro = $g{szOS} . ':' . $g{szDistro};
		$szWarning = sprintf('<H3>' . string('PLUGIN_SRVRPOWERCTRL_UNSUPPOS_HELP_MSG') . '</H3>', $szDistro);
	}

	#$g{log}->is_debug && $g{log}->debug("$message");
	$params->{distro} 			= $g{szDistro};		# [% distro %]
	$params->{warning}			= $szWarning;		# [% warning %]
	$params->{sbsuser} 			= $szSBSUser;		# [% sbsuser %]
	$params->{sbsservername}	= $szServerName;	# [% sbsservername %]

	#$g{log}->is_debug && $g{log}->debug('params == ' . Data::Dump::dump($params));

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}



sub RenderOSHelpPage {
	my ($client, $params) = @_;
	my $szDistro = $g{szDistro};
	my $szWarning;
	my $szCheckFile = '';
	my $bCheckFilePresent;
	my $szPluginPath;
	my $szSBSUser;
	my $szServerName;

	#$g{log}->is_debug && $g{log}->debug('Called!'); # client == ' . ( eval{$client->name()} || 'no client' ) . ", param == $params");

	$szPluginPath = $g{szAppPath};

	#Get the SC/SBS username..(NA for windows & mac)
	#if ( $g{nSCVersion} < 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	#if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') < 0) {
	#	$szServerName = string('SQUEEZECENTER');
	#} else {
	#	$szServerName = string('SQUEEZEBOX_SERVER');
	#}

	$szServerName = Plugins::SrvrPowerCtrl::Util::GetSCName();
	$szSBSUser = $g{szSCUser};

	# Unsupported OS?
	if ( ! $hOSs->{"$g{szOS}"} ) {
		$szDistro = $g{szOS} . ':' . $g{szDistro};
		$szWarning = sprintf('<H3>' . string('PLUGIN_SRVRPOWERCTRL_UNSUPPOS_HELP_MSG') . '</H3>', $szDistro);
	}

	#Check to see if we're already enabled by looking for a helper file..
	($bCheckFilePresent, $szCheckFile) = IsHelperUtilInstalled();
	$g{log}->is_debug && $g{log}->debug("Checkfile $szCheckFile " . ($bCheckFilePresent ? ' found.' : ' not found.') );

	#we don't worry about different versions of windows..
	if ($g{szOS} eq 'win') {
		if ( index( $params->{path}, 'Windows' ) == -1 ) {
			$szDistro = $g{szOS} . ':' . $g{szDistro};
			$szWarning = sprintf('<H3>' . string('PLUGIN_SRVRPOWERCTRL_WRONGDISTRO_HELP_MSG') . '</H3>', $szDistro);
			$szPluginPath = '/path/for/example/only';
		} elsif ($bCheckFilePresent) {
			#Already set up..
			$szWarning = '<p>' . string('PLUGIN_SRVRPOWERCTRL_ALREADYSETUPWIN_HELP_MSG') . '</p>';
			$szWarning = sprintf($szWarning, $szCheckFile);
		} else {
			$szWarning = '<p>' . string('PLUGIN_SRVRPOWERCTRL_NEEDSSETUP_HELP_MSG') . '</p>';
		}
	} else {
		#Check to see if the help file being loaded matches our OS..
		my $n = index( $params->{path}, $g{szOS} );
		$g{log}->is_debug && $g{log}->debug("index( $params->{path}, $g{szOS} ) == $n");

		if ( index( $params->{path}, $g{szOS} ) == -1 ) {
			$szDistro = $g{szOS} . ':' . $g{szDistro};
			$szWarning = sprintf('<H3>' . string('PLUGIN_SRVRPOWERCTRL_WRONGDISTRO_HELP_MSG') . '</H3>', $szDistro);
			$szPluginPath = '/path/for/example/only';
		} elsif ($bCheckFilePresent) {
			#Already set up..
			$szWarning = '<p>' . string('PLUGIN_SRVRPOWERCTRL_ALREADYSETUP_HELP_MSG') . '</p>';
		} else {
			#Need to set up..
			$szWarning = '<p>' . string('PLUGIN_SRVRPOWERCTRL_NEEDSSETUP_HELP_MSG') . '</p>';
		}
	}

	#$g{log}->is_debug && $g{log}->debug("$message");
	$params->{distro} 			= $g{szDistro};		# [% distro %]
	$params->{warning}			= $szWarning;		# [% warning %]
	$params->{sbsuser} 			= $szSBSUser;		# [% sbsuser %]
	$params->{sbsservername}	= $szServerName;	# [% sbsservername %]
	$params->{pluginpath} 		= $szPluginPath;	# [% pluginpath %]
	$params->{foundfile}		= $szCheckFile;		# [% foundfile %]

	#$g{log}->is_debug && $g{log}->debug('params == ' . Data::Dump::dump($params));

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}


sub RenderLogPage {
	my ($client, $params) = @_;

	$g{log}->is_debug && $g{log}->debug('Called!'); # . " params == " . Data::Dump::dump($params));

	$params->{srvrpowerctrl_logdata} = Plugins::SrvrPowerCtrl::Util::ListOurLogEntries(1);

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);

}

sub RenderPrefsPage {
	my ($client, $params) = @_;

	$g{log}->is_debug && $g{log}->debug('Called!'); # . " params == " . Data::Dump::dump($params));

	$params->{srvrpowerctrl_prefsdata} = Plugins::SrvrPowerCtrl::Settings::ListPrefs(1);

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);

}

sub RenderLogInfoPage {
	my ($client, $params) = @_;

	#$g{log}->is_debug && $g{log}->debug('Called!'); # . " params == " . Data::Dump::dump($params));

	$params->{srvrpowerctrl_urlsuffix} = time();

	$params->{srvrpowerctrl_logLevel} = Plugins::SrvrPowerCtrl::Settings::GetCurrentLogLevel();

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}

#Trouble-shooting help page
sub RenderTSHelpPage {
	my ($client, $params) = @_;
	my $szCacheDir;
	my $szPluginsDir;
	my $szSBSUser;
	my $szServerName;

	#$g{log}->is_debug && $g{log}->debug('Called!'); # client == ' . ( eval{$client->name()} || 'no client' ) . ", param == $params");

	#Get the SC/SBS username..(NA for windows & mac)
	#if ( $g{nSCVersion} < 7.4 ) {
	#compareVersions Returns: 1 if $left > $right, 0 if $left == $right, -1 if $left < $right
	#if (Slim::Utils::Versions::compareVersions($::VERSION , '7.4') < 0) {
	#	$szServerName = string('SQUEEZECENTER');
	#} else {
	#	$szServerName = string('SQUEEZEBOX_SERVER');
	#}

	$szServerName = Plugins::SrvrPowerCtrl::Util::GetSCName();
	$szSBSUser = $g{szSCUser};

	$szCacheDir   = Slim::Utils::OSDetect::dirsFor('cache');
	$szPluginsDir = Slim::Utils::OSDetect::dirsFor('plugins');

	$params->{os} = $g{szOS};
	$params->{distro} = $g{szDistro};
	$params->{macaddress} = $g{szServerMAC};

	$params->{cachedir} = $szCacheDir;
	$params->{pluginsdir}  = $szPluginsDir;
	$params->{sbsuser} = $szSBSUser;
	$params->{sbsservername} = $szServerName;	# [% sbsservername %]

	$params->{srvrpowerctrl_urlsuffix} = time();

	#$g{log}->is_debug && $g{log}->debug('params == ' . Data::Dump::dump($params));

	return Slim::Web::HTTP::filltemplatefile($params->{path}, $params);
}

1;

__END__
