#!/bin/sh
#
# SrvrPowerCtrl plugin helper script for linux.
#
# This script will set the system's RTC to wake the system up
# in advance of a programmed Logitech Media Server alarm.
#
# If the system hardware clock is set to UTC, call
# this script from SrvrPowerCtrl with "/usr/local/sbin/scwakeup.sh %d".
#
# If the system hardware clock is set to local time (the default for
# some dual-boot distros) then call this script from
# SrvrPowerCtrl with "/usr/local/sbin/scwakeup.sh %l".
#
# Test this script by setting a wake alarm for 10 minutes in the future:
#
# sudo ./spc-wakeup.sh $(($(date --utc '+%s')+600))
#
# See http://www.mythtv.org/wiki/index.php/ACPI_Wakeup
# for apci wakeup troubleshooting...
#

load_helper_file(){

	FUNCFILE='spc-functions.sh'

	HELPERFILE="$(dirname $(readlink -f $0 2>/dev/null) 2>/dev/null)/${FUNCFILE}"

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
FORCE=1
SHOW=0
CLEAR=0

####################################################################################
# show_rtc_wakealarm( void ) - Shows any existing HWClock RTC wakealarm
#

show_rtc_wakealarm(){

	if [ -f /sys/class/rtc/rtc0/wakealarm ]; then

		CURALARM="$(cat /sys/class/rtc/rtc0/wakealarm)"

		if [ ! -z "$CURALARM" ]; then
			WAKETIME=$(date -u -d "1970-01-01 ${CURALARM} seconds" +"%Y-%m-%d %H:%M:%S")
			SZWAKETIME=$(date -d "${WAKETIME}Z")
			spc_disp_message "Current wake alarm is set for ${CURALARM} (${SZWAKETIME})."
		else
			spc_disp_message "No wake alarm set."
		fi

	elif [ -f /proc/acpi/alarm ]; then
		spc_disp_message "Current wake alarm is set for: $(cat /proc/acpi/alarm)"
	else
		spc_disp_error_message "Error: ${SCRIPT} cannot not read wakealarm on this system."
		return 1
	fi

	if ( [ $VERBOSE -gt 0 ] && [ -f /proc/driver/rtc ] ); then
		echo ' '
		cat /proc/driver/rtc
	fi

	return 0
}


####################################################################################
# clear_rtc_wakealarm( void ) - Clears any existing HWClock RTC wakealarm
#

clear_rtc_wakealarm(){
	if [ -f /sys/class/rtc/rtc0/wakealarm ]; then
		echo 0 >/sys/class/rtc/rtc0/wakealarm
	elif [ -f /proc/acpi/alarm ]; then
		# Try setting a wake alarm for 1 second from now..
		echo "+0000-00-00 00:00:01" > /proc/acpi/alarm
	else
		spc_disp_error_message "Error: ${SCRIPT} cannot clear wakealarm on this system!"
		return 1
	fi
	sleep 1
	return 0
}


####################################################################################
# set_rtc_wakealarm( nEpochWakeTime ) - Set the HWClock RTC wakealarm
#

set_rtc_wakealarm(){
	WAKETIME=$(date -u -d "1970-01-01 $1 seconds" +"%Y-%m-%d %H:%M:%S")
	SZWAKETIME=$(date -d "${WAKETIME}Z")

	#Kernels > 2.6.22 and higher use /sys/class/rtc/rtc0/wakealarm
	if [ -f /sys/class/rtc/rtc0/wakealarm ]; then

		# If not forcing, don't set the wakealarm if there is already an earlier one set..
		if [ $FORCE -lt 1 ]; then

			CURALARM="$(cat /sys/class/rtc/rtc0/wakealarm)"
			NOWTIME="$(date --utc '+%s')"

			if ( [ ! -z "$CURALARM" ] && [ $CURALARM -gt $NOWTIME ] && [ $CURALARM -lt $1 ] ); then
				WAKETIME=$(date -u -d "1970-01-01 ${CURALARM} seconds" +"%Y-%m-%d %H:%M:%S")
				SZWAKETIME=$(date -d "${WAKETIME}Z")

				spc_disp_error_message "Error: a wake alarm for ${CURALARM} (${SZWAKETIME}) is already set."
				exit 1
			fi

		fi

		# Cancel any previous wakealarm..
		clear_rtc_wakealarm

		# Program the RTC wakealarm..
		spc_disp_message "Setting /sys/class/rtc/rtc0/wakealarm to $1 (${SZWAKETIME})"
		echo $1 >/sys/class/rtc/rtc0/wakealarm

	#Kernels < 2.6.21 and lower use /proc/acpi/alarm
	elif [ -f /proc/acpi/alarm ]; then

		spc_disp_message "Setting /proc/acpi/alarm to ${WAKETIME} (${SZWAKETIME})"
		/bin/echo "$WAKETIME" >/proc/acpi/alarm

	else

		spc_disp_error_message "Error: ${SCRIPT} does not support RTC wakeup on this system!"
		exit 1

	fi
	return 0
}


####################################################################################
# disp_help( void ) -- Display use syntax and exit
#

disp_help(){
	spc_disp_error_message	"Usage: ${SCRIPT} [epoch-waketime] [--show] [--clear] [--no-force] [--quiet] [--verbose] [--log] [--serverlog]"
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
	spc_disp_message "Clearing /sys/class/rtc/rtc0/wakealarm"
	clear_rtc_wakealarm
	exit 0
fi

if [ -z "$WAKEUPTIME" ]; then
	spc_disp_error_message "ERROR: epoch-waketime arg required."
	disp_help
fi

set_rtc_wakealarm "$WAKEUPTIME"

exit 0

