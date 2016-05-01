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
#    Stats.pm -- support for monitoring network, disk and CPU utilization.
#


package Plugins::SrvrPowerCtrl::Stats;

use base qw(Slim::Plugin::Base);
use strict;

#Global Variables..
use Plugins::SrvrPowerCtrl::Settings ();
use vars qw(%g);
*g = \%Plugins::SrvrPowerCtrl::Settings::g;

sub LogonsStat {
	my $os = shift || return 0;
	my @aLogons;
	my $nLogonCount = 0;

	if ($os eq 'win') {
		#Hide the console window..
		eval {
			Win32::SetChildShowWindow(0)
				if defined &Win32::SetChildShowWindow
		} ;

		# Requires psloggedon.exe from SysInternals: http://download.sysinternals.com/files/PSTools.zip
		@aLogons = `psloggedon.exe /l /q 2>NULL | find.exe "\\"`;

	} elsif ($os eq 'unix') {

		@aLogons = `w -h -s`;

	} elsif ($os eq 'mac') {

		@aLogons = `who`;

	}

	$nLogonCount = scalar ( @aLogons );

	$g{log}->is_debug && $g{log}->debug("Logon Sessions: $nLogonCount" . ( $nLogonCount > 0 ? "\nLogons:\n@aLogons" : ""));

	return $nLogonCount;
}

sub IsLogonCountNotIdle {
	return ( LogonsStat($g{szOS}) > 0 );
}

sub SambaStat {
	my $os = shift || return 0;
	my @aSMBStatus;
	my $nSambaCount = 0;

	if ($os eq 'unix') {

		@aSMBStatus = `smbstatus -L | egrep '^[0-9]* .*\$'`;

	} elsif ($os eq 'mac') {

		@aSMBStatus = `smbstatus -L | egrep '^[0-9]* .*$'`;

	}

	$nSambaCount = scalar ( @aSMBStatus );

	$g{log}->is_debug && $g{log}->debug("Samba Lock Count: $nSambaCount" . ($nSambaCount > 0 ? "\nSamba Locks:\n@aSMBStatus" : ""));

	return $nSambaCount;
}


sub IsSambaNotIdle {
	return ( SambaStat($g{szOS}) > 0 );
}


#last net throuput..
my $gLastNetStat = 0;
my $gLastNetStatTime = 0;

# Simple checking of tx rx throughput since last check..
sub NetStat {
	my $os = shift || return 0;
	my $nThisStatTime = shift || time();

	my @netstats;
	my @bytes = ();
	my $ifstats;
	my $throughput;
	my $txrxkbytes = 0;

	if ($os eq 'win') {
		#Hide the console window..
		eval {
			Win32::SetChildShowWindow(0)
				if defined &Win32::SetChildShowWindow
		} ;

		@netstats = `netstat.exe -e`;

		foreach $ifstats (@netstats) {
			push ( @bytes, ( map( /^Bytes   # like
					  \s*(\d*)      # Received
					  \s+(\d*)      # Sent
					 /x,$ifstats) )[0,1] );

		}

	} elsif ($os eq 'unix') {
		#code from epoch1970..
		my $procnetdev = '/proc/net/dev';
		if (! -e $procnetdev || !open(PND, "<$procnetdev")) {
			return 0;
		}

		@netstats = <PND>;
		close(PND);

		foreach $ifstats (@netstats) {
			push ( @bytes, ( map( /^.*?\w+\d{1}:   # like |  en3: ...
					  \s*(\d*)      # rx_bytes in - A real large value collapses with "en3:" above => \s*, not \s+
					  \s+(\d*)      # rx_packets in
					  \s+(\d*)      # rx_errs
					  \s+(\d*)      # rx_drop
					  \s+(\d*)      # rx_fifo
					  \s+(\d*)		# rx_frame
					  \s+(\d*)	    # rx_compressed
					  \s+(\d*)      # rx_multicast
					  \s+(\d*)      # tx_bytes
					  \s+(\d*)      # tx_packets
					  \s+(\d*)      # tx_errs
					  \s+(\d*)      # tx_drop
					  \s+(\d*)      # tx_fifo
					  \s+(\d*)		# tx_frame
					  \s+(\d*)	    # tx_compressed
					  \s+(\d*)      # tx_multicast
					 /x,$ifstats) )[0,8] );

		}

	} elsif ($os eq 'mac') {

		@netstats = `/usr/sbin/netstat -i -b`;

		foreach $ifstats (@netstats) {
			#We're just looking at interfaces with IPv4 addresses here..
			push ( @bytes, ( map( /^\w+\d{1}\s+\d{4}\s+\d{1,3}\.\d{1,3}\.\d{1,3}\s+\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}   # like |  en0   1500   192.168.0     192.168.0.104
					  \s+(\d*)      # Ipkts
					  \s+(\W|\d*)   # Ierrs
					  \s+(\d*)		# Ibytes
					  \s+(\d*)	    # Opkts
					  \s+(\W|\d*)   # Oerrs
					  \s+(\d*)      # Obytes
					  \s+(\d*)      # Coll
					 /x,$ifstats) )[2,5] );

		}


	}

	$txrxkbytes = 0;
	$txrxkbytes += $_ for @bytes;
	$txrxkbytes /= 1024;
	$txrxkbytes = int($txrxkbytes);

	# Net i/o since last check..
	$throughput = $txrxkbytes - (defined($gLastNetStat) ? $gLastNetStat : -1);

	# We don't necessarily check net stats at every watchdog interval..so, if we're more than 10 seconds out of date..
	#if ($gLastNetStatTime && $nThisStatTime > $gLastNetStatTime + $g{nWatchdogTimerInterval} + 10 && ($nThisStatTime - $gLastNetStatTime)) {
	if ($nThisStatTime - $gLastNetStatTime) {
		$throughput *=  ( $g{nWatchdogTimerInterval} / ($nThisStatTime - $gLastNetStatTime) );
	}

	$throughput = int($throughput);

	$g{log}->is_debug && $g{log}->debug("  Net IO: $throughput (kb / $g{nWatchdogTimerInterval} seconds)");

	$gLastNetStat = $txrxkbytes;
	$gLastNetStatTime = $nThisStatTime;

	return $throughput;
}

#ChkNetThroughput: returns 1 == current throughput > threshold, 0 == current throughput < threshold
sub IsNetIfaceNotIdle {
	my $nCurTime = shift || time();
	return ( NetStat($g{szOS}, $nCurTime) >= $g{prefs}->nIdleNetThreshold );
}


my $gLastDiskStat = 0;
my $gLastDiskStatTime = 0;


sub DiskStat {
	my $os = shift || return 0;
	my $nThisStatTime = shift || time();

	my @diskstats = ();
	my @diskios = ();
	my $drivestats;
	my $throughput;
	my $diskio = 0;

	if ($os eq 'win') {
		#Get this info from Win32PerfRawData ??
		return 0;

	} elsif ($os eq 'unix') {
		my $procdiskstats = '/proc/diskstats';
		if (! -e $procdiskstats || !open(PDS, "<$procdiskstats")) {
			return 0;
		}

		@diskstats = <PDS>;
		close(PDS);

		foreach $drivestats (@diskstats) {
		#   8      33 sdc1 330 13934 21574 2052 6791 798665 6443648 1649340 0 51564 1651372
			push ( @diskios, ( map( /^\s+\d+\s+\d+\s+\w{3}\d
					  \s*(\d*)      # number of reads issued
					  \s+(\d*)      # number of reads merged
					  \s+(\d*)      # number of sectors read <==================
					  \s+(\d*)      # number of milliseconds spent reading
					  \s+(\d*)      # number of writes completed
					  \s+(\d*)		# number of writes merged
					  \s+(\d*)	    # number of sectors written <===============
					  \s+(\d*)      # number of milliseconds spent writing
					  \s+(\d*)      # number of IOs currently in progress
					  \s+(\d*)      # number of milliseconds spent doing IOs
					  \s+(\d*)      # weighted number of milliseconds spent doing IOs
					 /x,$drivestats) )[2,6] );

		}

	} elsif ($os eq 'mac') {
		my @diskstat;
		my @disks = `ls -l /dev/disk?`;
		foreach my $disk (@disks) {
			chomp($disk);
			$disk =~ s{^.*/dev/}{};      # removes path
			@diskstat = `/usr/sbin/iostat -d -o -I $disk`;
			push(@diskstats, @diskstat);
		}

		foreach $drivestats (@diskstats) {
			if ($drivestats =~ m/^\s*(\d+)\s+.*$/) {
				push(@diskios, $1);
			}
		}
	}


	$diskio = 0;
	$diskio += $_ for @diskios;

	$throughput = $diskio - (defined($gLastDiskStat) ? $gLastDiskStat : -1);

	#Adjust the throughput value? (Net dev stats aren't necessisarily checked every watchdog interval..)
	if ($gLastDiskStatTime && $nThisStatTime > $gLastDiskStatTime + $g{nWatchdogTimerInterval} + 10 && ($nThisStatTime - $gLastDiskStatTime)) {
		$throughput *=  ( $g{nWatchdogTimerInterval} / ($nThisStatTime - $gLastDiskStatTime) );
	}

	$throughput = int($throughput);

	$g{log}->is_debug && $g{log}->debug("Disk IO: $throughput (sectors / $g{nWatchdogTimerInterval} seconds)");

	$gLastDiskStat = $diskio;
	$gLastDiskStatTime = $nThisStatTime;

	return $throughput;

}


sub IsDiskNotIdle {
	my $nCurTime = shift || time();
	return (DiskStat($g{szOS}, $nCurTime) > $g{prefs}->nIdleDisksThreshold);
}


#http://en.wikipedia.org/wiki/Load_(computing)
sub CPUStat {
	my $os = shift || 'unix';

	my $szRegEx;
	my $cpustats;
	my $cpuload = 0.00;

	if ($os eq 'win') {
		#no real way to check CPU load on windows..
		#typeperf -sc 1 -si 0"processor(_Total)\% Processor Time"
		#...doesn't return a useful value
		#But see: http://msdn.microsoft.com/en-us/library/aa364157(v=vs.85).aspx
		#Example code:
		#But see: http://msdn.microsoft.com/en-us/library/aa371886(v=vs.85).aspx
		return 0;
	} elsif ($os eq 'unix') {
		my $procloadavg = '/proc/loadavg';
		if (! -e $procloadavg || !open(PLA, "<$procloadavg")) {
			return 0;
		}
		$cpustats = <PLA>;
		close(PLA);
		#1.42 1.00 0.84 2/328 2842
		$szRegEx = '^\s*(\d+\.\d+).*$';

	} elsif ($os eq 'mac') {
		$cpustats = `/usr/bin/uptime`;
		$szRegEx = '^.*averages:\s+(\d+\.\d+).*$';
	}

	if ( $cpustats =~ /$szRegEx/ ) {
		$cpuload = $1;
	}

	$g{log}->is_debug && $g{log}->debug("CPU load: $cpuload (last 1 min average)");

	return $cpuload;
}

#IsCPUNotIdle: returns 1 == current load >= threshold, 0 == current load < threshold
sub IsCPUNotIdle {
	return (CPUStat($g{szOS}) >= $g{prefs}->nIdleCPULoadThreshold);
}




1;
