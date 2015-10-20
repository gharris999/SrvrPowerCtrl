#!/bin/sh

# SrvrPowerCtrl plugin helper script for OS X.
#
# This script will restart the Squeezebox 'service'.
#
# Note that with SBS 7.4 and later, this script is not needed.
# The 'restartserver' cli command serves the same purpose.
# I.e echo restartserver | nc -w3 localhost 9090
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

restart_server(){
	spc_get_slim_service_name
	SERVICE_SCRIPT="/Library/StartupItems/${SLIMSERVICENAME}/${SLIMSERVICENAME}"
	if [ -x "$SERVICE_SCRIPT" ]; then
		spc_disp_message "Restarting ${SLIMSERVICENAME}.."
		"$SERVICE_SCRIPT" restart
	else
		spc_disp_error_message "Error: I don't know how to restart ${SLIMSERVICENAME}"
		spc_disp_error_message "       Cannot find ${SERVICE_SCRIPT}."
		spc_disp_error_message "       Attempting to restart via SystemStarter ${SLIMSERVICENAME}."

		# This might work with old squeezecenter versions..
		SystemStarter stop "$SLIMSERVICENAME"
		sleep 10
		SystemStarter start "$SLIMSERVICENAME"
	fi
}



####################################################################################
# disp_help( void ) -- Display use syntax and exit
#

disp_help(){
	spc_disp_error_message	"Usage: ${SCRIPT} [--quiet] [--verbose] [--log] [--serverlog]"
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
	*)
		disp_help
		;;
esac
done

restart_server

