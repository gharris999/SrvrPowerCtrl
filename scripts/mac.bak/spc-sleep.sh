#!/bin/sh
#!/bin/sh
#
# SrvrPowerCtrl plugin helper script for OS X.
#
# This script will set a system wakeup event using pmset.
#
# Call this script from SrvrPowerCtrl with "sudo /usr/local/sbin/spc-sleep.sh %d".
#

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
SLEEPMODE=0
JUST_SHOW=0

aMODE[0]='sleep'
aMODE[1]='old-hibernation'
aMODE[3]='safe-sleep'
aMODE[25]='suspend/hibernation'

show_current_mode(){
	# get the current mode
	CURRENTMODE=$(pmset -g | grep 'hibernatemode' | sed -e 's/^[^[:digit:]]*\([[:digit:]]*\)[^[:digit:]]*$/\1/')
	spc_disp_message "System is currently configured for ${aMODE[$CURRENTMODE]}."
}

system_sleep(){
	HIBERNATEMODE="$1"
	# Default to sleep
	if [ -z "$HIBERNATEMODE" ]; then
		HIBERNATEMODE=0
	fi

	# From man pmset:
	#
	# We do not recommend modifying hibernation settings. Any changes you make are not
	# supported. If you choose to do so anyway, we recommend using one of these three
	# settings. For your sake and mine, please don't use anything other 0, 3, or 25.

	# hibernatemode 0 == sleep, 								ie 0b0000 0000
	# hibernatemode 3 == safe sleep, i.e sleep+hibernation,		ie 0b0000 0011
	# hibernatemode 25 == hibernation (called 'suspend'),		ie 0b0001 0001

	# See also:
	# http://www.tuaw.com/2011/08/22/why-hibernate-or-safe-sleep-mode-is-no-longer-necessary-in-os/
	# http://developer.apple.com/library/mac/#documentation/Darwin/Reference/ManPages/man1/pmset.1.html
	#
	# OS X version variations:
	# 10.4.1 (intel Tiger) no mention of hibernatemode
	# 10.5 (Leopard) only mentions bits 0 & 1,
	# 10.6 (Snow Leopard) bits 0,1,3,4
	# 10.7.4 (Lion) bits 0,1,3,4

	# get the current mode
	CURRENTMODE=$(pmset -g | grep 'hibernatemode' | sed -e 's/^[^[:digit:]]*\([[:digit:]]*\)[^[:digit:]]*$/\1/')

	# Older versions of OS X (Jaguar, Panther, Tiger) won't have a 'hibernatemode' setting, so
	# don't even try to change the mode..
	if ([ ! -z "$CURRENTMODE" ] && [ $CURRENTMODE -ne $HIBERNATEMODE ]); then
		spc_disp_message "Changing the system hibernatemode to ${aMODE[$HIBERNATEMODE]}."
		pmset -a hibernatemode $HIBERNATEMODE
		if [ $? -eq 0 ]; then
			CURRENTMODE=$HIBERNATEMODE
		fi
		# Wait 3 seconds to let the setting settle..
		sleep 3
	fi

	# Sleep the system..
	spc_disp_message "Putting the system into ${aMODE[$CURRENTMODE]} mode now."
	shutdown -s now
	exit $?
}

disp_help(){
	spc_disp_error_message	"Usage: ${SCRIPT} [--sleep|--safesleep|--hibernate] [--show] [--quiet] [--verbose] [--log] [--serverlog]"
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
	--show)
		JUST_SHOW=1
		;;
	--sleep|sleep|0)
		SLEEPMODE=0
		;;
	--safesleep|safesleep|3)
		SLEEPMODE=3
		;;
	# OS X refers to hibernation as 'suspend'
	--hibernate|hibernate|suspend|1|25)
		SLEEPMODE=25
		;;
	*)
		disp_help
		;;
esac
done

if [ $JUST_SHOW -gt 0 ]; then
	show_current_mode
	exit 0
fi

system_sleep $SLEEPMODE
exit $?
