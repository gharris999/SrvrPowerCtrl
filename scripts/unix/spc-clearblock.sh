#!/bin/sh
# SrvrPowerCtrl clear inhibit script.

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

####################################################################################
# clear_spc_block() - Delete the block file..
#

clear_spc_block(){
	if [ -d /run/lock ]; then
		BLOCKFILE='/run/lock/spc-block'
	else
		BLOCKFILE='/var/lock/spc-block'
	fi

	if [ -f $BLOCKFILE ]; then
		rm --force "$BLOCKFILE"
	else
		spc_disp_message "No SrvrPowerCtrl block file ${BLOCKFILE} to clear!"
		exit 0
	fi

	if [ -f $BLOCKFILE ]; then
		spc_disp_message "Cannot clear SrvrPowerCtrl block file ${BLOCKFILE}!"
		exit 1
	else
		spc_disp_message "SrvrPowerCtrl block file ${BLOCKFILE} cleared."
	fi
}

####################################################################################
# main() - Process command line..
#

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

clear_spc_block
exit 0
