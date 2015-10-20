#!/bin/bash
# SrvrPowerCtrl example of a custom idle check script.
#
# This returns the number of user log-ins plus the number
# of active samba locks and can be used to prevent
# SrvrPowerCtrl on-idle actions.
#
# Configure SrvrPowerCtrl's "Custom Idle check command" to
# call this script.
#
# Note: the latest version of SrvrPowerCtrl already
#       incorporates these checks nativly.
#

DEBUG=0

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

spc_get_slim_server_log

# Process command line..
for ARG in $*
do
case $ARG in
	--help)
		echo "${SCRIPT} [--log] [--serverlog] [--verbose]"
		exit 0
		;;
	--log)
		LOGGING=1
		;;
	--serverlog)
		SERVERLOGGING=1
		;;
	--verbose)
		VERBOSE=1
		;;
	--debug)
		DEBUG=1
		;;
esac
done

if [ ! -z "$SLIMSERVERLOG" ]; then
	LOGFILE="$SLIMSERVERLOG"
else
	LOGFILE="$(mktemp)"
fi

echo '===============================================================================' >>"$LOGFILE"
sensors -f >>"$LOGFILE"
echo '===============================================================================' >>"$LOGFILE"
blkid >>"$LOGFILE"
echo '===============================================================================' >>"$LOGFILE"
mount -l >>"$LOGFILE"
echo '===============================================================================' >>"$LOGFILE"
hddtemp -u F /dev/sd[b-z] >>"$LOGFILE"
for DEV in /dev/sd[a-z]
do
	echo '-------------------------------------------------------------------------------' >>"$LOGFILE"
	echo "Smart status of ${DEV}:" >>"$LOGFILE"
	smartctl -i "$DEV" >>"$LOGFILE"
	smartctl -H "$DEV" >>"$LOGFILE"
	#smartctl -a "$DEV" >>"$LOGFILE"
done
#smartctl -i /dev/sd[a-z] >>"$LOGFILE"
#smartctl -a /dev/sd[a-z] >>"$LOGFILE"
echo '===============================================================================' >>"$LOGFILE"
/sbin/apcaccess >>"$LOGFILE"
echo '===============================================================================' >>"$LOGFILE"
echo '===============================================================================' >>"$LOGFILE"


