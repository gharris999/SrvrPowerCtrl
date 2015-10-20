#!/bin/sh
#
# SrvrPowerCtrl plugin helper script for OS X.
#
# This script will set a system wakeup event using pmset.
#
# Call this script from SrvrPowerCtrl with "sudo /usr/local/sbin/spc-wakeup.sh %d".
#
# Test this script by setting scheduling a system wakeup for 10 minutes in the future:
#
# sudo ./spc-wakeup.sh $(($(date -u '+%s')+600))
#
# See http://developer.apple.com/library/mac/#documentation/Darwin/Reference/ManPages/man1/pmset.1.html


myrealpath(){
	local ABSPATH=`perl -e 'use Cwd "abs_path";print abs_path(shift)' "$1"`
	echo "$ABSPATH"
}

load_helper_file(){

	local SOURCEDIR=`myrealpath "$0"`
	SOURCEDIR=`dirname "$SOURCEDIR"`

	local helper_functions="${SOURCEDIR}/spc-functions.sh"

	if [ ! -f "$helper_functions" ]; then
		echo "ERROR: Cannot find ${helper_functions}"
		exit 1
	fi

	. "$helper_functions"

}

load_helper_file

VERBOSE=1
WAKEUPTIME=
WAKEUPMODE=
# By default, clear any earlier wake alarm..
FORCE=1
SHOW=0
CLEAR=0
ISLOCAL=0


####################################################################################
# get_tz_offset( void ) - Get the difference in local time to UTC in seconds (+/-)
#

get_tz_offset(){
	szLocalOffset=$(date '+%z')

	if [ $(echo "$szLocalOffset" | egrep '\+' | wc -l) -gt 0 ]; then
		IsWest=0
	else
		IsWest=1
	fi

	szLocalOffsetHours="${szLocalOffset:1:2}"
	szLocalOffsetHours=$((10#$szLocalOffsetHours*3600))
	szLocalOffsetMinutes="${szLocalOffsetStr:3:2}"
	szLocalOffsetMinutes=$((10#$szLocalOffsetMinutes*60))
	szLocalOffsetSeconds=$((10#$szLocalOffsetHours+10#$szLocalOffsetMinutes))

	if [ $IsWest -gt 0 ]; then
		szLocalOffsetSeconds=-$szLocalOffsetSeconds
	fi

	echo "$szLocalOffsetSeconds"
}


####################################################################################
# show_rtc_wakealarm( void ) - Shows any existing pmset scheduled wake events
#

show_rtc_wakealarm(){
	local SCHEDULES=
	local SCHED=
	local DATE_TIME=
	local EPOCH_TIME=
	local WHAT=
	local RETVAL=0
	local IFS_BAK=$IFS
	IFS=$'\n'

	SCHEDULES=$(pmset -g sched | egrep 'wake|poweron')

	if [ -z "$SCHEDULES" ]; then
		spc_disp_error_message "Error: no wake events scheduled."
		RETVAL=1
	fi

	for SCHED in $SCHEDULES; do
		#echo "SCHED: ${SCHED}"
		# date/time - "MM/dd/yy HH:mm:ss" (in 24 hour format; must be in quotes)
		DATE_TIME=$(echo $SCHED | sed -e 's/^.* at \(.*\)$/\1/')
		EPOCH_TIME=$(date -j -f '%m/%d/%y %H:%M:%S' "$DATE_TIME" '+%s')

		if [ $ISLOCAL -gt 0 ]; then
			OFFEST=$(get_tz_offset)
			echo "Adjusting ${EPOCH_TIME} by ${OFFEST}."
			EPOCH_TIME=$(($EPOCH_TIME+$OFFEST))
			DATE_TIME=$(date -j -f '%s' "$EPOCH_TIME" '+%m/%d/%y %H:%M:%S')
		fi

		WHAT=$(echo $SCHED | sed -e 's/^.*\] *\(.*\) at .*$/\1/')
		if ([ ! -z "$WHAT" ] && [ ! -z "$DATE_TIME" ]); then
			spc_disp_message "System ${WHAT} is scheduled for ${EPOCH_TIME} (${DATE_TIME})."
		fi
	done
	IFS=$IFS_BAK
	return $RETVAL
}


####################################################################################
# clear_rtc_wakealarm( void ) - Clears any existing pmset scheduled wake events
#

clear_rtc_wakealarm(){
	local SILENT=$1
	local SCHEDULES=
	local SCHED=
	local DATE_TIME=
	local WHAT=
	local RETVAL=0
	if [ -z "$SILENT" ]; then
		SILENT=0
	fi
	local IFS_BAK=$IFS
	IFS=$'\n'
	SCHEDULES=$(pmset -g sched | egrep 'wake|poweron')
	SCHED=

	if [ -z "$SCHEDULES" ]; then
		RETVAL=1
		if [ $SILENT -lt 1 ]; then
			spc_disp_error_message "Error: no wake events scheduled."
		fi
	fi

	for SCHED in $SCHEDULES; do
		DATE_TIME=$(echo $SCHED | sed -e 's/^.* at \(.*\)$/\1/')
		WHAT=$(echo $SCHED | sed -e 's/^.*\] *\(.*\) at .*$/\1/')
		if ([ ! -z "$WHAT" ] && [ ! -z "$DATE_TIME" ]); then
			if [ $SILENT -lt 1 ]; then
				spc_disp_message "Clearing ${WHAT} scheduled for ${DATE_TIME}."
			fi
			pmset sched cancel "$WHAT" "$DATE_TIME"
		fi
	done
	IFS=$IFS_BAK
	return $RETVAL
}


####################################################################################
# get_next_wakealarm( void ) - return the next pmset scheduled wake event
#

get_next_wakealarm(){
	local SCHEDULES=
	local SCHED=
	local DATE_TIME=
	local EPOCH_TIME=
	local WHAT=
	local EARLIEST=2147508848
	local RETVAL=0
	local IFS_BAK=$IFS
	IFS_BAK=$IFS
	IFS=$'\n'
	SCHEDULES=$(pmset -g sched | egrep 'wake|poweron')

	if [ -z "$SCHEDULES" ]; then
		RETVAL=1
	fi

	for SCHED in $SCHEDULES; do
		#echo "SCHED: ${SCHED}"
		# date/time - "MM/dd/yy HH:mm:ss" (in 24 hour format; must be in quotes)
		DATE_TIME=$(echo $SCHED | sed -e 's/^.* at \(.*\)$/\1/')
		EPOCH_TIME=$(date -j -f '%m/%d/%y %H:%M:%S' "$DATE_TIME" '+%s')
		if [ $EPOCH_TIME -lt $EARLIEST ]; then
			EARLIEST=$EPOCH_TIME
		fi
		#At 03:14:08 UTC on 19 January 2038, 32-bit versions
		#date -j -f '%m/%d/%y %H:%M:%S' "01/19/38 03:14:08" '+%s'

	done
	IFS=$IFS_BAK
	echo "$EARLIEST"
	return $RETVAL
}


####################################################################################
# set_rtc_wakealarm( nEpochWakeTime ) - pmset schedule a wake event
#

set_rtc_wakealarm(){
	local DATE_TIME=
	local EPOCH_TIME="$(date -u '+%s')"
	local WAKE_MODE="$2"
	local NEXT_WAKE=

	# date/time - "MM/dd/yy HH:mm:ss" (in 24 hour format; must be in quotes)
	DATE_TIME=$(date -j -f '%s' "$1" '+%m/%d/%y %H:%M:%S')
	#echo "DATE_TIME 2 = ${DATE_TIME}"

	if [ $1 -lt $(($EPOCH_TIME+120)) ]; then
		spc_disp_error_message "Error: Requested wake time ${1} (${DATE_TIME}) is in the past or less than two minutes from now."
		exit 1
	fi

	if [ -z "$WAKE_MODE" ]; then
		WAKE_MODE='wakeorpoweron'
	fi

	# If not forcing, don't set the wakealarm if there is already an earlier one set..
	if [ $FORCE -lt 1 ]; then
		NEXT_WAKE=$(get_next_wakealarm)

		if ( [ ! -z "$NEXT_WAKE" ] && [ $NEXT_WAKE -gt $EPOCH_TIME ] && [ $NEXT_WAKE -lt $1 ] ); then
			DATE_TIME=$(date -r "$NEXT_WAKE" +"%Y-%m-%d %H:%M:%S")
			spc_disp_error_message "Error: a wake alarm for ${NEXT_WAKE} (${DATE_TIME}) is already set."
			exit 1
		fi

	else
		clear_rtc_wakealarm 1
	fi

	spc_disp_message "Setting system to ${WAKE_MODE} at ${1} (${DATE_TIME})"

	pmset schedule "$WAKE_MODE" "$DATE_TIME"

	return 0
}


####################################################################################
# disp_help( void ) -- Display use syntax and exit
#

disp_help(){
	spc_disp_error_message	"Usage: ${SCRIPT} [epoch-waketime|+nSeconds] [local] [wake|poweron|wakeorpoweron] [--show] [--clear] [--no-force] [--quiet] [--verbose] [--log] [--serverlog]"
	exit 1
}


####################################################################################
# main() - Process command line..
#

for ARG in $*
do
case $ARG in
	--help)
		disp_help
		;;
	--quiet)
		VERBOSE=0
		;;
	--verbose)
		VERBOSE=1
		;;
	--log)
		LOGGING=1
		spc_get_log_file
		;;
	--serverlog)
		LOGGING=1
		SERVERLOGGING=1
		spc_get_slim_server_log
		;;
	--local)
		ISLOCAL=1
		;;
	--force)
		FORCE=1
		;;
	--no-force)
		FORCE=0
		;;
	--show)
		SHOW=1
		;;
	--clear)
		CLEAR=1
		;;
	*)
		if [ -z "$WAKEUPTIME" ]; then
			WAKEUPTIME=$ARG
		elif [ -z "$WAKEUPMODE" ]; then
			WAKEUPMODE="$ARG"
		fi
		;;
esac
done

# Just show the currently set wakealarm..
if [ $SHOW -gt 0 ]; then
	show_rtc_wakealarm
	exit 0
fi

# Clear any set wakealarm..
if [ $CLEAR -gt 0 ]; then
	clear_rtc_wakealarm
	exit 0
fi

if [ -z "$WAKEUPTIME" ]; then
	spc_disp_error_message "ERROR: epoch-waketime arg required."
	disp_help
fi

WAKEUPMODE=$(echo "$WAKEUPMODE" | egrep '^wake$|^wakeorpoweron$|^poweron$')

if [ -z "$WAKEUPMODE" ]; then
	WAKEUPMODE='wakeorpoweron'
fi

# If our WAKEUPTIME is in the form +nnn, e.g. '+120' for two minutes in the future..
if [ $(echo $WAKEUPTIME | egrep '^\+[[:digit:]]*$' | wc -l) -gt 0 ]; then
	WAKEUPTIME=$(($(date -u '+%s')${WAKEUPTIME}))
fi

set_rtc_wakealarm "$WAKEUPTIME" "$WAKEUPMODE"

exit 0
