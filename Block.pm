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
#    Block.pm -- support for external blocking..
#


package Plugins::SrvrPowerCtrl::Block;

use base qw(Slim::Plugin::Base);
use strict;

use Slim::Utils::Strings qw(string);
use Slim::Utils::OSDetect;


#Global Variables..
use Plugins::SrvrPowerCtrl::Settings ();
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

sub GetBlockFileName {
	my $blockfilename;

	#Look for a blockfile:
  	if ($g{szOS} eq 'win') {
		my $szDistro = Slim::Utils::OSDetect::getOS()->{osDetails}->{osName};
		if ($szDistro eq 'Windows 7' || $szDistro eq 'Windows Vista') {
			$blockfilename = $ENV{'ProgramData'} . "\\TEMP\\spc-block";
		} else {
			$blockfilename = $ENV{'WINDIR'} . "\\temp\\spc-block";
		}
	} else {
		if ( -d "/run/lock" ) {
			$blockfilename = "/run/lock/spc-block";
		} else {
			$blockfilename = "/var/lock/spc-block";
		}
	}
	return $blockfilename;
}

sub BlockFileExists {
	my $blockfile = GetBlockFileName();

	if ( -e $blockfile ) {
		$g{log}->is_debug && $g{log}->debug("Blocking file $blockfile found..");
		return 1;
	}

	return 0;
}

sub CreateBlockFile {
	my $blockfile = GetBlockFileName();

	open(my $handle, '>', $blockfile);

	close($handle);

	return BlockFileExists();
}

sub DeleteBlockFile {
	my $blockfile = GetBlockFileName();
	my $bRet = unlink("$blockfile");
	$g{log}->is_debug && $g{log}->debug("unlink $blockfile returned $bRet");
	return !BlockFileExists();
}

sub IsSoftBlockFile {
	my $blockfile = GetBlockFileName();

	if (! -e $blockfile || !open(SBF, "<$blockfile")) {
		return 0;
	}

	my @contents = <SBF>;
	close(SBF);

	if ($contents[0] =~ m/^softblock$/i) {
		return 1;
	}

	return 0;

}

sub IsBlocked {

	if (BlockFileExists()){
		if (IsSoftBlockFile()) {
			if ( (caller)[0] =~ /(Watchdog)/) {
				$g{log}->is_debug && $g{log}->debug("Enforcing file soft-block for $1..");
				return 1;
			}
		} else {
			return 1;
		}
	}

	#if (!defined(@{$g{aBlockAction}}) ) {
	if (!(@{$g{aBlockAction}}) ) {
		#$g{log}->is_debug && $g{log}->debug("No blocks..");
		return 0;
	}

	foreach my $element (@{$g{aBlockAction}}) {
		if ( defined($element->{'caller'}) ) {

			if ($element->{'caller'} =~ m/^softblock$/i) {
				if ( (caller)[0] =~ /(Watchdog)/) {
					$g{log}->is_debug && $g{log}->debug("Enforcing memory soft-block for $1..");
					return 1;
				}
			} else {
				$g{log}->is_debug && $g{log}->debug("Found a block set by $element->{'caller'} ..");
				return 1;
			}
		}
	}


	#$g{log}->is_debug && $g{log}->debug("No blocks..(or softblock)");
	return 0;
}

sub SetBlock {
	my ($client, $item) = @_;
	my $message;
	my $bNeedMenuInit = 0;
	$g{log}->is_debug && $g{log}->debug("Setting block from " . ( eval{$client->name()} || 'no client' ) . " " . $item->{message} . "..");

	#if we're not already blocked, re-initialize the menu to include Clear Block..
	if (!IsBlocked()){
		$bNeedMenuInit = 1;
	}

	Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage(undef, $item->{message}, 10);

	Plugins::SrvrPowerCtrl::Plugin::blockAction($client, 'set', ($g{prefs}->get('bUseSoftBlocks') ? 'softblock' : 'viacli'), $item->{message});
	if ($bNeedMenuInit) {
		Plugins::SrvrPowerCtrl::Menu::initActionItems();
	}
}

sub ClearBlock {
	my ($client, $item) = @_;
	my $bRet = 0;

	$g{log}->is_debug && $g{log}->debug('Clearing block from ' . ( eval{$client->name()} || 'no client' ) . ': ' . $item->{message} . '..');

	Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage(undef, $item->{message}, 10);

	#Block files take precidence, so they should be cleared first..
	if ( BlockFileExists() ) {
		$bRet = DeleteBlockFile();
	} else {
		$bRet = Plugins::SrvrPowerCtrl::Plugin::blockAction($client, 'clear', ($g{prefs}->get('bUseSoftBlocks') ? 'softblock' : 'viacli'), $item->{message});
	}

	if (!IsBlocked()){
		Plugins::SrvrPowerCtrl::Menu::initActionItems();
	}

	return $bRet;
}

sub CountBlocks {
	my $nBlocks = 0;
	if ( BlockFileExists() ) {
		$nBlocks++;
	}

	foreach my $element (@{$g{aBlockAction}}) {
		if ( defined($element->{'caller'}) ) {
			$nBlocks++;
		}
	}

	return $nBlocks;

}

#proper case..
sub pc {
	my $str = shift;
	return ucfirst(lc($str));
}

sub GetBlockReasonMessage {
	my $action = shift;
	my $blockowner;
	my $reason;
	my $blockmsg;

	if (BlockFileExists()){
		my $blockfilename = GetBlockFileName();
		#Proper-case the action..
		$action = ucfirst(lc($action));
		$blockmsg = sprintf( string('PLUGIN_SRVRPOWERCTRL_BLOCKFILE_MSG'), $action, $blockfilename );
		return $blockmsg;
	}

	foreach my $element (@{$g{aBlockAction}}) {
		if ( defined($element->{'caller'}) ) {

			#Proper-case the action..
			$action = pc($action);

			#Proper-case the block owner..
			$blockowner = pc($element->{'caller'});

			#fixup the reason..change underscores to spaces..
			$reason = $element->{'reason'};
			$reason =~ s/_/ /sig;

			$blockmsg = sprintf( string('PLUGIN_SRVRPOWERCTRL_BLOCKEDACTION_MSG'), $action, $blockowner, $reason );

			return $blockmsg;
		}
	}


	return "";
}

sub DispBlockedMessage {
	my $client = shift;
	my $action = shift;
	my $nDelay = shift;
	my $nDuration = shift;
	my $blockmsg;

	$blockmsg = GetBlockReasonMessage($action);

	if (BlockFileExists()){

		if (!defined($nDuration)) {
			$nDuration = 25;
		}

		if (Plugins::SrvrPowerCtrl::Util::IsValidClient($client)) {

			if (defined($nDelay)) {
				Slim::Utils::Timers::setTimer( $client, time() + $nDelay, sub {
					Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage($client, $blockmsg, $nDuration, undef);
					}, );
			} else {
				Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage($client, $blockmsg, $nDuration, undef);
			}

		} else {
			#warn all the clients..
			Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage (undef, $blockmsg, $nDuration );
		}
		return 1;
	}


	foreach my $element (@{$g{aBlockAction}}) {
		if ( defined($element->{'caller'}) ) {

			if (!defined($nDuration)) {
				$nDuration = 25;
			}

			if (Plugins::SrvrPowerCtrl::Util::IsValidClient($client)) {

				if (defined($nDelay)) {
					Slim::Utils::Timers::setTimer( $client, time() + $nDelay, sub {
						Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage($client, $blockmsg, $nDuration, undef);
						}, );
				} else {
					Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage($client, $blockmsg, $nDuration, undef);
				}

			} else {
				#warn all the clients..
				Plugins::SrvrPowerCtrl::Util::DisplayPlayerMessage (undef, $blockmsg, $nDuration );
			}
			return 1;
		}
	}
}

1;
