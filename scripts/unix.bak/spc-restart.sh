#!/bin/sh
#
# SrvrPowerCtrl plugin helper script for Debian.
#
# This script restarts the SqueezeCenter service.
#
# Note: For SqueezeCenter 7.0 - 7.3.  SqueezeBoxServer 7.4 and later have their own facility for doing this.
#
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

restart_slim(){
	spc_get_slim_servicename_nopid

	#if a bash safe script is running, kill the perl process and allow the safe script to restart it.
	if [ $(pgrep -f "bash.*/sbin/${SLIMSERVICENAME}_safe|bash.*/sbin/squeeze.*_safe|bash.*/sbin/logitech.*_safe") ]; then
		spc_disp_message "Asking safe script to restart ${SLIMSERVICENAME}"
		pkill -f 'perl.*/usr/sbin/squeeze|perl.*/usr/share/.*/slim|perl.*/usr/sbin/logitech'
	else
		spc_disp_message "Restarting ${SLIMSERVICENAME}.."
		service $SLIMSERVICENAME restart
		if [ $? -gt 0 ]; then
			SLIMSERVICENAME='logitechmediaserver'
			service $SLIMSERVICENAME restart
		fi
	fi
}

# Process command line..
for ARG in $*
do
case $ARG in
	--help)
		echo "${SCRIPT} [--quiet] [--log] [--serverlog]"
		exit 0
		;;
	--quiet)
		VERBOSE=0
		;;
	--log)
		LOGGING=1
		;;
	--serverlog)
		LOGGING=1
		SERVERLOGGING=1
		;;
esac
done

restart_slim
