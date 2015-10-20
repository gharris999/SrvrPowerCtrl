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
	echo "$(perl -e 'use Cwd "abs_path";print abs_path(shift)' $0)"
}


load_helper_file(){

	FUNCFILE='spc-functions.sh'

	HELPERFILE="$(dirname $(myrealpath $0))/${FUNCFILE}"

	if [ ! -f "$HELPERFILE" ]; then
		HELPERFILE="${0%$(basename $0)*}/${FUNCFILE}"
	fi

	if [ -f "$HELPERFILE" ]; then
		. $HELPERFILE
	else
		echo "Error: could not find ${HELPERFILE}."
	fi

}

load_helper_file

VERBOSE=1
WAKEUPTIME=
WAKEUPMODE=
FORCE=1
SHOW=0
CLEAR=0

####################################################################################
# show_rtc_wakealarm( void ) - Shows any existing pmset scheduled wake events
#

show_rtc_wakealarm(){
	RETVAL=0
	IFS_BAK=$IFS
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
	SILENT=$1
	if [ -z "$SILENT" ]; then
		SILENT=0
	fi
	RETVAL=0
	IFS_BAK=$IFS
	IFS=$'\n'
	SCHEDULES=$(pmset -g sched | egrep 'wake|poweron')

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
	RETVAL=0
	EARLIEST=2147508848
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

	# date/time - "MM/dd/yy HH:mm:ss" (in 24 hour format; must be in quotes)
	DATE_TIME="$(date -r "$1" '+%m/%d/%Y %H:%M:%S')"

	WAKE_MODE="$2"

	if [ -z "$WAKE_MODE" ]; then
		WAKE_MODE='wakeorpoweron'
	fi

	# If not forcing, don't set the wakealarm if there is already an earlier one set..
	if [ $FORCE -lt 1 ]; then
		NOWTIME="$(date -u '+%s')"

		NEXT_WAKE=$(get_next_wakealarm)

		if ( [ ! -z "$NEXT_WAKE" ] && [ $NEXT_WAKE -gt $NOWTIME ] && [ $NEXT_WAKE -lt $1 ] ); then
			SZWAKETIME=$(date -r "$NEXT_WAKE" +"%Y-%m-%d %H:%M:%S")
			spc_disp_error_message "Error: a wake alarm for ${NEXT_WAKE} (${SZWAKETIME}) is already set."
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
	spc_disp_error_message	"Usage: ${SCRIPT} [epoch-waketime|+nSeconds] [wake|poweron|wakeorpoweron] [--show] [--clear] [--no-force] [--quiet] [--verbose] [--log] [--serverlog]"
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
