#!/bin/sh
# SrvrPowerCtrl inhibit script.

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
# Create the blockfile..
#
set_spc_block(){
	spc_get_slim_pid
	if [ -z "SLIMSERVICEPID" ]; then
		spc_disp_message "Squeezeboxserver is not running..no SrvrPowerCtrl block set."
		return 1
	fi

	if [ -d /run/lock ]; then
		BLOCKFILE='/run/lock/spc-block'
	else
		BLOCKFILE='/var/lock/spc-block'
	fi

	#touch $BLOCKFILE
	echo 'hardblock' >"$BLOCKFILE"

	if [ -f $BLOCKFILE ]; then
		spc_get_slim_username
		if [ $? -eq 0 ]; then
			chown "${SLIMUSERNAME}:${SLIMUSERGROUP}" "$BLOCKFILE"
		fi
		chmod a+rw "$BLOCKFILE"
		spc_disp_message "SrvrPowerCtrl Block file ${BLOCKFILE} created."
	else
		spc_disp_message "Cannot create SrvrPowerCtrl block file ${BLOCKFILE}!"
		exit 1
	fi
}

####################################################################################
# main()
#
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

set_spc_block
exit 0

