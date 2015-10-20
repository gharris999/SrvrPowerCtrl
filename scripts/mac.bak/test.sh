#!/bin/sh

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
LOGGING=1
SERVERLOGGING=1

spc_disp_message "This is a test message"

echo '==================================================================================================================================='
cat "$SLIMSERVERLOG"
echo '==================================================================================================================================='
cat "$SPCLOG"
