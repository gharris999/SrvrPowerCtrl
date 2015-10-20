#!/bin/sh
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

USERCOUNT=0
SAMBALOCKS=0
DEBUG=0
SERVERLOG=0
CHECKSAMBA=$(which smbd | wc -l)

####################################################################################
# Check for active login sessions..
#
check_logins(){
	USERCOUNT=$(who -u | wc -l)
}

####################################################################################
# Check for active samba connections..
#
check_samba_connections(){
	SAMBALOCKS=$(smbstatus -L | egrep '^[0-9]* .*$' | wc -l)
}

####################################################################################
# main()
#

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

check_logins

if [ $CHECKSAMBA -gt 0 ]; then
	check_samba_connections
fi

spc_disp_message "User session count: ${USERCOUNT}, Samba connections: ${SAMBALOCKS}"

exit $(($USERCOUNT+$SAMBALOCKS))
