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
#    AltServer.pm -- Routines for pushing and pulling players to other servers
#
package Plugins::SrvrPowerCtrl::AltServer;

use base qw(Slim::Plugin::Base);
use strict;

use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Strings qw(string);

#Global Variables..
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

sub GetAltServerList {
	my $bSaveList = shift || 0;

	# Start with mysb.com...
	my $altserver   = Slim::Networking::SqueezeNetwork->get_server('sn');

	#mysb.com doesn't get an IP because we treat it differently..
	my $server = {
		'serverName'			=> "$altserver",
		'serverIP'			=> "$altserver",
		#serverIsTinySC		=> 0,
		};

	my @otherservers;
	push ( @otherservers, $server );

	#Our server ip
	my $my_ip = Slim::Utils::Network::serverAddr();

	#Hash of all SBSs found...including us..
	my $other_servers = Slim::Networking::Discovery::Server::getServerList();
	#$g{log}->is_debug && $g{log}->debug("Other Servers:" . Data::Dump::dump($other_servers));

	while( my ($serverName, $serverHash) = each %$other_servers ) {
		$server = {};
		#If this is not us..
		if ($other_servers->{$serverName}->{IP} ne $my_ip) {
			$server = {
				'serverName'		=> "$other_servers->{$serverName}->{NAME}",
				'serverIP'			=> "$other_servers->{$serverName}->{IP}",
				#serverIsTinySC		=> 0,
				};
			push ( @otherservers, $server );
		}
	}

	#$g{log}->is_debug && $g{log}->debug("Other Servers:\n" . Data::Dump::dump(@otherservers));

	if ($bSaveList) {
		$g{prefs}->set('aAltServerList', \@otherservers);
		#my $blip = $g{prefs}->get('aAltServerList');
		#$g{log}->is_debug && $g{log}->debug("Other Servers:\n" . Data::Dump::dump($blip));
	}

	return \@otherservers;
}

sub SaveAltServerList {
	return GetAltServerList(1);
}


#Get AltServerPlayers based on name or ip of the AltServer..

sub GetAltServerPlayers {
	my $szAltServerName = shift;
	my $szAltServerIP = shift;
	my $szSNServer = shift || Slim::Networking::SqueezeNetwork->get_server('sn');
	my @otherplayers = ();
	my $player = {};

	#Who are we looking for?
	$g{log}->debug( "Trying to get list of players from $szAltServerName ($szAltServerIP).." );

	if (!defined($szAltServerName) && !defined($szAltServerIP)) {
		$szAltServerName = $szSNServer;
		$szAltServerIP = $szSNServer;
	}

	#If we're asking for mysb.com players..
	if ($szAltServerName eq $szSNServer || $szAltServerIP eq $szSNServer) {
		if ($szAltServerName ne $szSNServer) {
			$szAltServerName = $szSNServer;
		}

		#We won't have the new players in time..but so what..
		Slim::Networking::SqueezeNetwork::Players::fetch_players();

		$player = {};

		my @sn_players_raw = Slim::Networking::SqueezeNetwork::Players->get_players();
		foreach my $sn_player (@sn_players_raw) {
			$player = {	playerID		=>	$sn_player->{mac},
						playerModel		=>	$sn_player->{model},
						playerName		=>	$sn_player->{name},
						};
			push (@otherplayers, $player);
		}
		$g{log}->debug( "Other players on $szAltServerName ($szAltServerIP): " . Data::Dump::dump(@otherplayers));
		return \@otherplayers;
	}

	#Hash of all SBSs found...including us..
	my $other_servers = Slim::Networking::Discovery::Server::getServerList();
	#$g{log}->is_debug && $g{log}->debug("Other Servers:" . Data::Dump::dump($other_servers));

	#Hash of all local players attached to all local SBSs...
	my $other_players = Slim::Networking::Discovery::Players::getPlayerList();
	#$g{log}->debug( "Other players discovered: " . Data::Dump::dump($other_players));

	while( my ($serverName, $serverHash) = each %$other_servers ) {
		$player = {};

		#If this is who we're looking for..
		if ( (defined($szAltServerName) && $szAltServerName eq $other_servers->{$serverName}->{NAME}) ||
			 (defined($szAltServerIP) && $szAltServerIP eq $other_servers->{$serverName}->{IP}) ) {

			while( my ($player, $playerHash) = each %$other_players ) {
				if ($playerHash->{server} eq $other_servers->{$serverName}->{NAME}) {
					$player = {	playerID	=>	$player,
								playerModel	=>	$playerHash->{model},
								playerName	=>	$playerHash->{name},
								};
					push (@otherplayers, $player);
				}
			}

			#$g{log}->debug( "Other players on $szAltServerName ($szAltServerIP): " . Data::Dump::dump(@otherplayers));

			return \@otherplayers;
		}
	}

	return \@otherplayers;
}


# PushToAltServer([$client]); #Pushes connected players to the alternate server (or mysb.com);
sub PushToAltServer {
	my ($client) = @_;

	if (!Plugins::SrvrPowerCtrl::Util::IsValidClient($client)) {
		$client = undef;
	}

	$g{log}->is_debug && $g{log}->debug( "client == " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'modelName') . "::" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'model') . "::\'" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'name') . "\'--\>" . Plugins::SrvrPowerCtrl::Util::ClientAttribute($client, 'id'));

	#####################################################################################################
	# Whom to push??
	#####################################################################################################

	my %hPushClientMAC;		#client IDs of players from the user defined push list
	my %hSkipClientMAC;		#client IDs of players NOT to push from the user defined pushlist
	my %hClientsToPush;		#who we end up pushing..
	my @aConnectedClients =  Slim::Player::Client::clients();
	#Check to see who owns the next scheduled alarm.
	my ($nRTCWakeupTime, $szNextAlarmClientMAC) = Plugins::SrvrPowerCtrl::Alarms::GetNextAlarm();

	#Specific players to push or skip?
	if ( $g{prefs}->szAltServerPushMACs ) {
		my @aMACs = split(/[\;\,\s]/, $g{prefs}->szAltServerPushMACs );
		#if a mac address starts with '!', record that as a player to skip, not push..
		for(@aMACs) {
			#Is this a push or a skip mac?
			if (substr($_,0,1) eq '!') {
				$hSkipClientMAC{substr($_,1)} = 1;
			} else {
				$hPushClientMAC{$_} = 1;
			}
		}
	}

	#Who are we pushing?

	#If the user has entered mac addresses, these take presidence over ALL..
	if (keys %hPushClientMAC) {
		%hClientsToPush = %hPushClientMAC;

	#else if All are selected..
	} elsif ($g{prefs}->bAltServerPushAll) {
		for (@aConnectedClients) {
			$hClientsToPush{$_->id()} = 1;
		}

	#else if the request came from a single client..
	} elsif (Plugins::SrvrPowerCtrl::Util::IsValidClient($client)) {
		$hClientsToPush{$client->id()} = 1;

	#else how did we get here??
	} else {
		$g{log}->error( "No client to push!");
		return 0;

	}

	#Now backout anybody on the black list..
	for my $clientid (keys %hSkipClientMAC) {
		$hClientsToPush{$clientid} = 0;
	}

	$g{log}->is_debug && $g{log}->debug( "Clients to push: " . Data::Dump::dump( \%hClientsToPush ) );

	#########################################################################################################
	# Where to push to?
	#########################################################################################################
	# Alternate server: $g{prefs}->szAltServerName
	# If alt server not resolvable or pingable, then mysb.com
	#
	my $szSNAddr = Slim::Networking::SqueezeNetwork->get_server('sn');
	my $szAltServer = $g{prefs}->szAltServerName;
	my $szAltServerIP;

	#Get the IP of the AltServer by name..
	if ($szAltServer) {
		for (@{GetAltServerList()}) {
			if ( $_->{serverName} eq $szAltServer ) {
				$szAltServerIP = $_->{serverIP};
				last;
			}
		}
	} else {
		$szAltServer = 	$szSNAddr;
	}

	#If we didn't find the IP, fallback to mysb.com..
	if (!defined($szAltServerIP)) {
		$szAltServerIP = $szSNAddr;
	}


	#########################################################################################################
	# Delete our menu from the calling jive..
	#########################################################################################################
	#if (defined($client) && $hClientsToPush{$client->id()}) {
	#	Slim::Control::Jive::deleteMenuItem('pluginSrvrPowerCtrlMenu', $client);
	#	Slim::Control::Jive::mainMenu($client);
	#}

	#########################################################################################################
	# Push the clients..
	#########################################################################################################

	#Save the sync groups..
	if ($g{prefs}->bAltServerUnSyncLocal) {
		SaveSyncGroups();
	}

	my @aPushedClientMACs;

	my $nDelay = 15;
	foreach my $curclient (@aConnectedClients) {
		#is this client on the list?
		#if ($hClientsToPush{$curclient->id()}) {
		if ($hClientsToPush{$curclient->id()} || $hClientsToPush{$curclient->name()}) {

			#Only power-off players that we actually push..
			if ($g{prefs}->bPowerOffPlayers) {
				if ( $curclient->canPowerOff() && $curclient->power() ) {
					$g{log}->is_debug && $g{log}->debug( "Powering off " . $curclient->modelName() . ": " . $curclient->name());
					$curclient->execute(['power', '0']);
				}

				$g{log}->is_debug && $g{log}->debug( "Powering off " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'name') . '(' . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'modelName') . ')-->' . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'id'));
				$curclient->execute(['power', '0']);
			}

			#Unsync the player before pushing..
			if ($g{prefs}->bAltServerUnSyncLocal) {
				$g{log}->is_debug && $g{log}->debug( "   Unsyncing " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'name') . '(' . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'modelName') . ')-->' . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'id'));
				$curclient->execute(['sync', '-']);
			}

			#Push the player onto the remote server..
			$g{log}->is_debug && $g{log}->debug( "     Pushing " . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'name') . '(' . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'modelName') . ')-->' . Plugins::SrvrPowerCtrl::Util::ClientAttribute($curclient, 'id') . " to $szAltServerIP..");
			$curclient->execute(['connect', $szAltServerIP]);

			#Ask the remote server to power-off & unsync the player..but give it some time to get there first..
			if ($g{prefs}->bAltServerPowerOffPlayers) {
				Slim::Utils::Timers::setTimer( undef, time() + $nDelay, \&RemotePlayerRequest, ($curclient->id(), $szAltServerIP, ['power', '0']) );
				#RemotePlayerRequest(undef, $curclient->id(), $szAltServerIP, ['power', '0']);

				if ($g{prefs}->bAltServerUnSyncLocal) {
					$nDelay += 2;
					Slim::Utils::Timers::setTimer( undef, time() + $nDelay, \&RemotePlayerRequest, ($curclient->id(), $szAltServerIP, ['sync', '-']) );
					#RemotePlayerRequest(undef, $curclient->id(), $szAltServerIP, ['sync', '-']);
				}

				$nDelay += 4;
			}

			push (@aPushedClientMACs, $curclient->id());

		}
	}

	#####################################################################################################
	# Make sure the owner of the next alarm is on the list to fetch back..
	#####################################################################################################

	#Check the mac of the next alarm..  If it's not in our list, then the player was already on SN.
	foreach my $szCurMAC (@aPushedClientMACs) {
		if ( lc($szCurMAC) eq lc($szNextAlarmClientMAC) ) {
			$szNextAlarmClientMAC = undef;
		}
	}

	#Add that mac to our list of players to be pulled back on wakeup..
	if (defined($szNextAlarmClientMAC)) {
		$g{log}->is_debug && $g{log}->debug( "Adding $szNextAlarmClientMAC to our list of pushed players because it has an alarm scheduled..");
		push( @aPushedClientMACs, $szNextAlarmClientMAC );
	}

	#########################################################################################################
	# Save who we've pushed, and to where..
	#########################################################################################################
	$g{prefs}->set('szPushedAltServerName', $szAltServer);
	$g{prefs}->set('aPushedAltServerPlayers',	\@aPushedClientMACs );


	if ($szAltServerIP eq $szSNAddr) {
		#Refresh the list of players..
		Slim::Utils::Timers::setTimer( undef, time() + $nDelay, \&Slim::Networking::SqueezeNetwork::Players::fetch_players, );
	}

	#Return the number of clients pushed and how long to wait for the queued json requests to complete...
	return (scalar(@aPushedClientMACs), $nDelay);
}


sub _ReportSyncGroups {
	my $szPrefix = shift | "";
	my $res = Slim::Control::Request::executeRequest(undef, [ 'syncgroups', '?' ]);
	$g{log}->debug($szPrefix . 'syncgroups ? == ' . Data::Dump::dump($res->{_results}));
}

sub SaveSyncGroups {
	my $request = Slim::Control::Request::executeRequest(undef, [ 'syncgroups', '?' ]);

	my $aSyncGroups = $request->{_results}->{syncgroups_loop};

	if (ref($aSyncGroups) ne 'ARRAY') {
		$aSyncGroups = [];
	}

	$g{log}->is_debug && $g{log}->debug('Saving syncgroups: ' . Data::Dump::dump($aSyncGroups));

	$g{prefs}->set('aSyncGroups', $aSyncGroups);

	return scalar(@{$aSyncGroups});
}

sub RestoreSyncGroups {
	my $aSyncGroups = $g{prefs}->get('aSyncGroups');
	my $nSynced = 0;

	if ( ref($aSyncGroups) ne 'ARRAY' ) {
		$aSyncGroups = [];
	}

	$g{log}->is_debug && $g{log}->debug('Restoring syncgroups: ' . Data::Dump::dump($aSyncGroups));

	foreach my $syncgroup (@$aSyncGroups) {
		my @aSyncMembers = split(/[\,]/, $syncgroup->{sync_members} );
		my $clientSyncMaster = Slim::Player::Client::getClient(shift(@aSyncMembers));
		foreach my $szSyncSlave (@aSyncMembers) {
			if (defined($clientSyncMaster)) {
				$nSynced++;
				$clientSyncMaster->execute(['sync', $szSyncSlave]);
			}
		}
	}

	$aSyncGroups = [];
	$g{prefs}->set('aSyncGroups', $aSyncGroups);
	return $nSynced;
}

sub UnSyncAllLocalPlayers {
	foreach my $client (Slim::Player::Client::clients()) {
		$g{log}->debug('Attempting to unsync ' . $client->name());
		$client->execute(['sync', '-' ]);
	}
	$g{log}->debug('Done!');
	return 1;
}


sub PowerOffAllRemotePlayers {
	my $szAltServer = shift;
	my $szAltServerIP = shift;
	my $szSNAddr = shift || Slim::Networking::SqueezeNetwork->get_server('sn');

	my $aAltServerPlayers = GetAltServerPlayers($szAltServer, $szAltServerIP, $szSNAddr);

	if (!$szAltServerIP) {
		$szAltServerIP = $szSNAddr;
	}

	foreach my $player (@{$aAltServerPlayers}) {
		RemotePlayerRequest(undef, $player->{playerID}, $szAltServerIP, ['power', '0']);
	}
	return scalar (@{$aAltServerPlayers});
}

sub UnSyncAllRemotePlayers {
	my $szAltServer = shift;
	my $szAltServerIP = shift;
	my $szSNAddr = shift || Slim::Networking::SqueezeNetwork->get_server('sn');

	my $aAltServerPlayers = GetAltServerPlayers($szAltServer, $szAltServerIP, $szSNAddr);

	if (!$szAltServerIP) {
		$szAltServerIP = $szSNAddr;
	}

	foreach my $player (@{$aAltServerPlayers}) {
		RemotePlayerRequest(undef, $player->{playerID}, $szAltServerIP, ['sync', '-']);
	}
	return scalar (@{$aAltServerPlayers});
}


#this should work whether the AltServer is a local server or mysb.com...
sub PullFromAltServer {
	my $bForce = $g{prefs}->bOnWakeupFetchPlayersForce;
	#Lookup what we did before..
	my $aPushedClientMACs = $g{prefs}->get('aPushedAltServerPlayers');
	my $szAltServer = $g{prefs}->get('szPushedAltServerName');
	my $szSNAddr = Slim::Networking::SqueezeNetwork->get_server('sn');
	my $szAltServerIP;

	#########################################################################################################
	# Where to fetch from?
	#########################################################################################################

	if ($szAltServer ne $szSNAddr) {

		#Get the IP of the AltServer by name..
		if ($szAltServer) {
			for (@{GetAltServerList()}) {
				if ( $_->{serverName} eq $szAltServer ) {
					$szAltServerIP = $_->{serverIP};
					last;
				}
			}
		} else {
			$szAltServer = 	$szSNAddr;
		}
	}

	#If we didn't find the IP, default to mysb.com..
	if (!defined($szAltServerIP)) {
		$szAltServerIP = $szSNAddr;
	}

	$g{log}->is_debug && $g{log}->debug("Fetching from $szAltServer ($szAltServerIP): " . Data::Dump::dump($aPushedClientMACs));

	#########################################################################################################
	# Whom to fetch?
	#########################################################################################################
	if ( ref($aPushedClientMACs) ne 'ARRAY' ) {
		$aPushedClientMACs = [];
	}

	my %hFetchClientMAC;		#client IDs of players to fetch..
	my %hSkipClientMAC;
	my @aConnectedClients =  Slim::Player::Client::clients();

	#Specific players to fetch or skip?
	if ( $g{prefs}->szOnWakeupFetchPlayersMACs ) {
		my @aMACs = split(/[\;\,\s]/, $g{prefs}->szOnWakeupFetchPlayersMACs );
		#if a mac address starts with '!', record that as a player to skip, not push..
		for(@aMACs) {
			#Is this a push or a skip mac?
			if (substr($_,0,1) eq '!') {
				$hSkipClientMAC{substr($_,1)} = 1;
			} else {
				$hFetchClientMAC{$_} = 1;
			}
		}
	}

	#Add specific Macs to the fetch list if they're not there alreay...
	#Get the list of players currently on the alternate server, finding the server by name..
	my $aAltServerPlayers = GetAltServerPlayers($szAltServer, $szAltServerIP, $szSNAddr);
	#$g{log}->is_debug && $g{log}->debug("Other Players on $szAltServer ($szAltServerIP): " . Data::Dump::dump($aAltServerPlayers));

	#If the list of players on $szAltServerIP is empty, should we check at mysb.com too?
	if ( (!defined(${$aAltServerPlayers}[0])  || !@$aAltServerPlayers) && ($szAltServerIP ne $szSNAddr) ) {
		$g{log}->is_debug && $g{log}->debug("No players on $szAltServerIP...trying $szSNAddr too..");
		$szAltServer = $szSNAddr;
		$szAltServerIP = $szSNAddr;
		$aAltServerPlayers = GetAltServerPlayers(undef, undef, $szSNAddr);
		#$g{log}->is_debug && $g{log}->debug("Other Players on $szAltServerIP: " . Data::Dump::dump($aAltServerPlayers));
	}

	#my $nDelay = 1;
	#Do we want to fetch all players, even if we don't remember pushing them??
	if ($bForce) {
		foreach my $player (@$aAltServerPlayers) {
			if (defined($player) && !$hSkipClientMAC{$player->{playerID}}) {
				#Slim::Utils::Timers::setTimer( undef, time() + $nDelay, \&RemotePlayerRequest, ($player->{playerID}, $szAltServerIP, ['connect', Slim::Utils::Network::serverAddr()]) );
				RemotePlayerRequest(undef, $player->{playerID}, $szAltServerIP, ['connect', Slim::Utils::Network::serverAddr()]);
				#$nDelay += 2;

			}
		}
	} else {
		foreach my $pushedMAC (@$aPushedClientMACs) {
			foreach my $player (@$aAltServerPlayers) {
				if (defined($player) && $pushedMAC eq $player->{playerID} && !$hSkipClientMAC{$player->{playerID}}) {
					#Slim::Utils::Timers::setTimer( undef, time() + $nDelay, \&RemotePlayerRequest, ($player->{playerID}, $szAltServerIP, ['connect', Slim::Utils::Network::serverAddr()]) );
					RemotePlayerRequest(undef, $player->{playerID}, $szAltServerIP, ['connect', Slim::Utils::Network::serverAddr()]);
					#$nDelay += 2;
				}
			}
		}
	}

	#Restore the sync groups..give the players some time to arrive..
	if ($g{prefs}->bAltServerUnSyncLocal) {
		#Slim::Utils::Timers::setTimer( undef, time() + $nDelay + 10, \&RestoreSyncGroups, );
		Slim::Utils::Timers::setTimer( undef, time() + 20, \&RestoreSyncGroups, );
	}

	#Erase the list of pushed players..
	$g{prefs}->set('aPushedAltServerPlayers', '');
	$g{prefs}->get('szPushedAltServerName', '');

	#If we've pulled from mysb.com, update the player list there..
	if ($szAltServerIP eq $szSNAddr) {
		#Refresh the list of players..
		Slim::Utils::Timers::setTimer( undef, time() + 25, \&Slim::Networking::SqueezeNetwork::Players::fetch_players, );
	}


	return 1;
}


sub _json_done {
	my $http    = shift;
	my $res = eval { from_json( $http->content ) };
	if ( $@ || ref $res ne 'HASH' ) {
		$http->error( $@ || 'Invalid JSON response' );
		return _json_error( $http );
	}

	if ( $res->{error} ) {
		$http->error( $res->{error} );
		return _json_error( $http );
	}

	#$g{log}->is_debug && $g{log}->debug( "Remote player request response: " . Data::Dump::dump( $res ) );
	$g{log}->is_debug && $g{log}->debug( "Remote player request succeeded..");

}

sub _json_error {
	my $http    = shift;
	my $error   = $http->error;

	$g{log}->error( "Remote player request error: $error" );

}

sub RemotePlayerRequest {
	my $client = shift;
	my $client_id;

	if (!$client) {
		$client_id = shift;
	} else {
		$client_id = $client->id();
	}
	my $server = shift;

	#the requests are passed in via an array ref..
	my $args = shift;

	$server ||= Slim::Networking::SqueezeNetwork->get_server('sn');

	#$g{log}->is_debug && $g{log}->debug("Attempting to send request @args for $client_id on $server");

	if (!$client_id) {
		return;
	}

	my $http;

	# If mysb.com..
	if ( $server =~ /^www.(?:squeezenetwork|mysqueezebox).com$/i || $server =~ /^www.test.(?:squeezenetwork|mysqueezebox).com$/i ) {

		$http = Slim::Networking::SqueezeNetwork->new(
			\&_json_done,
			\&_json_error,
		);

	} else {

		$server = Slim::Networking::Discovery::Server::getWebHostAddress($server);
		chop($server);

		$http = Slim::Networking::SimpleAsyncHTTP->new(
			\&_json_done,
			\&_json_error,
			{
				timeout	=> 30,
			}
		);

	}

	my $postdata = to_json({
		id     => 1,
		method => 'slim.request',
		params => [ $client_id, $args ]
	});

	my $url = ($http->url() ? $http->url() : $server) . '/jsonrpc.js';

	$g{log}->is_debug && $g{log}->debug("Sending request: $url?$postdata");

	$http->post( $url, $postdata);

}



1;
