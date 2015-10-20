####################################################################################
# Helper fuctions for SrvrPowerCtrl scripts MAC VERSION
# 20120717 Gordon Harris
#

LOGGING=0
SERVERLOGGING=0
VERBOSE=0
SPCLOG=
SLIMSERVICENAME=
SLIMSERVICEPID=
SLIMLOGDIR=
SLIMSERVERLOG=
SLIMCACHEDIR=
SLIMUSERNAME=
SLIMUSERGROUP=
ISGIT=0
SLIMLOCALREPO=
SLIMGITLOG=
SCRIPT=$(basename $0)

##############################################################################################################
# realpath() -- get the absolute path of a file.  OS X has no readlink -f
#

realpath(){
	local ABSPATH=`perl -e 'use Cwd "abs_path";print abs_path(shift)' "$1"`
	echo "$ABSPATH"
}


##############################################################################################################
# pgrep() -- OS X & FreeBSD has no pgrep.  Fake it.
#

pgrep(){
	ps -axo pid,command,args | egrep -v 'egrep' | egrep -i "$@" | awk '{ print $1 }'
}

##############################################################################################################
# Better than pgrep
#
psgrep(){
    ps aux | grep -v grep | grep -E $*
}


##############################################################################################################
# Get the service pid
#

spc_get_slim_pid(){
	SLIMSERVICEPID=$(pgrep 'perl.*/squeeze|perl.*/slim|perl.*/logitech')
	local RETVAL=$?
	#echo $SLIMSERVICEPID
	return $RETVAL
}

##########################################################
# Get the service name -- defaults to logitechmediaserver
#

spc_get_slim_service_name(){

	#/Library/PreferencePanes/Squeezebox.prefPane/Contents/server/slimserver.pl
	spc_get_slim_pid

	if [ $? -gt 0 ]; then
		# SBS/LMS not running! Punt!
		SLIMSERVICENAME='Squeezebox'
		return 1
	fi

	SLIMLOCALREPO=$(lsof -a -p $SLIMSERVICEPID -d cwd | egrep -v 'COMMAND' | awk '{print $9}')

	SLIMSERVICENAME=$(echo $SLIMLOCALREPO | sed -e 's:^.*/\([^/]*\)\.prefPane.*$:\1:')

	# If we're running elsewhere than in a preference pane, then the service name the the dirname above 'server'
	if [ -z "$SLIMSERVICENAME" ]; then
		SLIMSERVICENAME=$(echo $SLIMLOCALREPO | sed -e 's:^.*/\([^/]*\)/server.*$:\1:')
	fi

	if [ -z "$SLIMSERVICENAME" ]; then
		# Punt!
		SLIMSERVICENAME='Squeezebox'
		return 1
	fi
	return 0
}

####################################################################################
# Get the service name without using a pid file -- defaults to squeezeboxserver
#
spc_get_slim_servicename_nopid(){
	# No real meaning with OS X
	if [ -z "$SLIMSERVICENAME" ]; then
		spc_get_slim_service_name
	fi
}

spc_stop_slim_service(){
	spc_get_slim_pid
	if [ ! -z "$SLIMSERVICEPID" ]; then
		kill $SLIMSERVICEPID
		return 0
	fi
	return 1
}

####################################################################################
# Test if we're running git code, get the path to the local repo and the git log
#
spc_get_slim_localrepo(){

	#/Library/PreferencePanes/Squeezebox.prefPane/Contents/server/slimserver.pl
	spc_get_slim_pid

	SLIMLOCALREPO=$(lsof -a -p $SLIMSERVICEPID -d cwd | egrep -v 'COMMAND' | awk '{print $9}')

	ISGIT=$(pgrep "perl.*/usr/.*/server/slimserver.pl" | wc -l)

	if [ $ISGIT -gt 0 ]; then
		return 0
	fi

	return 1
}


####################################################################################
# Get the service pid owner account name, group
#
spc_get_slim_username(){
	local RETVAL=0
	SLIMUSERNAME=$(ps aux | egrep 'perl.*slimserver\.pl' | egrep -v 'egrep' | awk '{ print $1 }')
	if [ -z "SLIMUSERNAME" ]; then
		SLIMUSERNAME="$USER"
		RETVAL=1
	fi
	SLIMUSERGROUP=$(id -g -nr "$SLIMUSERNAME")
	return $RETVAL
}

####################################################################################
# Get the cache dir..
#
spc_get_slim_cachedir(){
	if [ -z "$SLIMUSERNAME" ]; then
		spc_get_slim_username
	fi
	if [ -z "$SLIMSERVICENAME" ]; then
		spc_get_slim_service_name
	fi
	SLIMCACHEDIR="/Users/${SLIMUSERNAME}/Library/Caches/${SLIMSERVICENAME}"
	#echo "$SLIMCACHEDIR"
	return 0
}

####################################################################################
# Get the log directory..
#
spc_get_slim_log_dir(){
	if [ -z "$SLIMUSERNAME" ]; then
		spc_get_slim_username
	fi
	if [ -z "$SLIMSERVICENAME" ]; then
		spc_get_slim_service_name
	fi
	SLIMLOGDIR="/Users/${SLIMUSERNAME}/Library/Logs/${SLIMSERVICENAME}"
	#echo "$SLIMLOGDIR"
	return 0
}

####################################################################################
# Get the server log file name..
#
spc_get_slim_server_log(){
	if [ -z "$SLIMLOGDIR" ]; then
		spc_get_slim_log_dir
	fi

	if [ -w "$SLIMLOGDIR" ]; then
		SLIMSERVERLOG="${SLIMLOGDIR}/server.log"
	else
		LOGGING=0
		SLIMSERVERLOG='/dev/null'
		return 1
	fi
	return 0
}


####################################################################################
# Get the git log filename..
#
spc_get_slim_git_log(){
	if [ -z "$SLIMLOGDIR" ]; then
		spc_get_slim_log_dir
	fi

	if [ -w "$SLIMLOGDIR" ]; then
		SLIMGITLOG="${SLIMLOGDIR}/git.log"
	else
		LOGGING=0
		SLIMGITLOG='/dev/null'
		return 1
	fi
	return 0
}

####################################################################################
# Stamp a message with the date and the script name (and process id) using
# the same format as found in the squeezeboxserver server.log
#
date_message(){
	DATE=$(date '+%F %H:%M:%S')
	DATE=${DATE#??}
	DATE="${DATE}.0000"
	echo "[${DATE}] ${SCRIPT} ($$)" $@
}

####################################################################################
# Post a message to the server log..
#
spc_log_slim_git_message(){
	if [ -z "$SLIMGITLOG" ]; then
		spc_get_slim_git_log
	fi

	date_message $@ >> $SLIMGITLOG
}

####################################################################################
# Post a message to the server log..
#
spc_log_slim_message(){
	if [ -z "$SLIMSERVERLOG" ]; then
		spc_get_slim_server_log
	fi

	date_message $@ >> $SLIMSERVERLOG
}

####################################################################################
# Truncate the server log..
#
spc_truncate_slim_server_log(){
	if [ -z "$SLIMSERVERLOG" ]; then
		spc_get_slim_server_log
	fi
	date_message "${SLIMSERVERLOG} truncated." > $SLIMSERVERLOG
}

####################################################################################
# Get the srvrpowerctrl log file name..
#
spc_get_log_file(){
	if [ -z "$SLIMLOGDIR" ]; then
		spc_get_slim_log_dir
	fi
	if [ -w "$SLIMLOGDIR" ]; then
		SPCLOG="${SLIMLOGDIR}/srvrpowerctrl.log"
	else
		LOGGING=0
		SPCLOG='/dev/null'
		return 1
	fi
	return 0
}

####################################################################################
# Post a message to the srvrpowerctrl log..
#
spc_log_message(){
	if [ -z "$SPCLOG" ]; then
		spc_get_log_file
	fi
	if [ -z "$SLIMSERVERLOG" ]; then
		spc_get_slim_server_log
	fi

	if [ $SERVERLOGGING -eq 0 ]; then
		date_message $@ >> $SPCLOG
	else
		date_message $@ >> $SLIMSERVERLOG
	fi
}

####################################################################################
# Post a message to stdout and to the srvrpowerctrl log..
#
spc_disp_message(){
	if [ $VERBOSE -gt 0 ]; then
		echo $@
	fi
	if ([ $LOGGING -gt 0 ] || [ $SERVERLOGGING -gt 0 ]); then
		spc_log_message $@
	fi
}

####################################################################################
# Post a message to stderr and to the srvrpowerctrl log..
#
spc_disp_error_message(){
	echo $@ >&2
	if ([ $LOGGING -gt 0 ] || [ $SERVERLOGGING -gt 0 ]); then
		spc_log_message $@
	fi
}
