####################################################################################
# Helper fuctions for SrvrPowerCtrl scripts
# 20120525 Gordon Harris
#

USE_UPSTART=0
USE_SYSTEMD=0
USE_SYSV=1

IS_DEBIAN="$(which apt-get 2>/dev/null | wc -l)"
# https://ask.fedoraproject.org/en/question/49738/how-to-check-if-system-is-rpm-or-debian-based/
/usr/bin/rpm -q -f /usr/bin/rpm >/dev/null 2>&1
[ $? -eq 0 ] && IS_FEDORA=1 || IS_FEDORA=0

IS_UPSTART=$(initctl version 2>/dev/null | grep -c 'upstart')
IS_SYSTEMD=$(systemctl --version 2>/dev/null | grep -c 'systemd')

# Prefer upstart to systemd if both are installed..

if [ $(ps -eaf | grep -c [u]pstart) -gt 1 ]; then
	USE_UPSTART=1
	USE_SYSTEMD=0
	USE_SYSV=0
elif [ $(ps -eaf | grep -c [s]ystemd) -gt 2 ]; then
	USE_UPSTART=0
	USE_SYSTEMD=1
	USE_SYSV=0
else
	USE_UPSTART=0
	USE_SYSTEMD=0
	USE_SYSV=1
fi



ISDEBIAN="$(which apt-get 2>/dev/null | wc -l)"
ISSYSTEMD="$(which systemctl 2>/dev/null | wc -l)"
USESYSTEMD=0
if ([ $ISDEBIAN -eq 0 ] && [ $ISSYSTEMD -gt 0 ]); then
	USESYSTEMD=1
fi



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
# Better than pgrep
#
psgrep(){
    ps aux | grep -v grep | grep -E $*
}

##############################################################################################################
# Get the service pid
#
spc_get_slim_pid(){
	SLIMSERVICEPID=$(pgrep -fn 'perl.*/squeeze|perl.*/slim|perl.*/logitech')
	RETVAL=$?
	#echo $SLIMSERVICEPID
	return $RETVAL
}

##########################################################
# Get the service name -- defaults to logitechmediaserver
#

spc_get_slim_service_name(){
	# First, look for a pid file..
	PIDFILE=$(ls -1 /var/run/*.pid | egrep 'logitech|squeeze' | sed -n -e 's#^\(.*\.pid\)\.*$#\1#p')
	if [ ! -z "$PIDFILE" ]; then
		PID=$(cat "$PIDFILE")
		ISRUNNING=$(ps $PID | grep -v 'PID')
		if [ ! -z "$ISRUNNING" ]; then
		    SLIMSERVICENAME=$(echo "$PIDFILE" | sed -n -e 's#^.*/\([^/]*\)\.pid#\1#p')
		fi
	fi

	# If we can't get the service name from a pid file, then get it from the process..
	if [ -z "$SLIMSERVICENAME" ]; then
		SLIMSERVICENAME=$(psgrep 'perl.*/squeeze|perl.*/slim|perl.*/logitech' | sed -e 's#^.*/share/\([^/]*\).*$#\1#' -e 's#^.*/usr/sbin/\([^ ]*\).*$#\1#')
	fi

	# punt!
	if [ -z "$SLIMSERVICENAME" ]; then
		SLIMSERVICENAME='logitechmediaserver'
	fi
}

####################################################################################
# Get the service name without using a pid file -- defaults to squeezeboxserver
#
spc_get_slim_servicename_nopid(){
	# Don't use the pid file method.  We'll kill squeezeboxserver_safe instead of service logitechmediaserver stop..
	SLIMSERVICENAME=$(psgrep 'perl.*/squeeze|perl.*/slim|perl.*/logitech' | sed -e 's#^.*/share/\([^/]*\).*$#\1#' -e 's#^.*/usr/sbin/\([^ ]*\).*$#\1#')

	# punt!
	if [ -z "$SLIMSERVICENAME" ]; then
		SLIMSERVICENAME='squeezeboxserver'
	fi
}

spc_stop_slim_service(){

	SLIMSERVICEPROC=$(pgrep -fln 'perl.*/squeeze|perl.*/slim|perl.*/logitech' | sed -e 's#^.*/share/\([^/]*\).*$#\1#' -e 's#^.*/usr/sbin/\([^ ]*\).*$#\1#')
	SLIMSERVICESAFEPID=$(pgrep -f "sh.*/sbin/${SLIMSERVICEPROC}_safe|sh.*/sbin/squeeze.*_safe|sh.*/sbin/logitech.*_safe")

	# Kill the safe script..
	if [ ! -z "$SLIMSERVICESAFEPID" ]; then
		spc_disp_message "Stopping ${SLIMSERVICEPROC}_safe"
		kill $SLIMSERVICESAFEPID
		sleep 3
	fi

	# This should stop the perl script, if the safe_script hasn't alreay..
	spc_get_slim_pid

	if [ ! -z "$SLIMSERVICEPID" ]; then
		spc_disp_message "Stopping ${SLIMSERVICEPROC}"
		kill $SLIMSERVICEPID
		return $?
	fi

	return 0
}

####################################################################################
# Test if we're running git code, get the path to the local repo and the git log
#
spc_get_slim_localrepo(){
	if [ -z "$SLIMSERVICENAME" ]; then
		spc_get_slim_servicename_nopid
	fi

	ISGIT=$(pgrep -fn "perl.*/share/${SLIMSERVICENAME}/server/slim" | wc -l)

	if [ $ISGIT -gt 0 ]; then
		#SLIMLOCALREPO="/usr/share/${SLIMSERVICENAME}/server"
		SLIMLOCALREPO=$(psgrep 'perl.*/squeeze|perl.*/slim|perl.*/logitech' | sed -n -e 's#^.*perl \([^ ]*\)/slimserver\.pl.*$#\1#p')
		return 0
	fi

	return 1
}


####################################################################################
# Get the service pid owner account name, group
#
spc_get_slim_username(){
	spc_get_slim_pid
	if [ ! -z "$SLIMSERVICEPID" ]; then
		SLIMUSERID=$(ps -fp "$SLIMSERVICEPID" | grep -v 'UID' | sed -n -e 's/^\([[:alnum:]]*\)[[:blank:]]*.*$/\1/p')
	fi

	if [ ! -z "$SLIMUSERID" ]; then
		SLIMUSERNAME=$(getent passwd "$SLIMUSERID" | sed -n -e 's/^\([[:alnum:]]*\):.*$/\1/p')
	else
		SLIMUSERNAME='squeezeboxserver'
	fi

	# Test to see that this is a valid user..
	id -u "$SLIMUSERNAME" > /dev/null 2>&1

	if [ $? -gt 0 ]; then
		SLIMUSERNAME=
		return 1
	fi

	SLIMUSERGROUP=$(id -ng $SLIMUSERNAME)
	return 0
}

####################################################################################
# Get the cache dir..
#
spc_get_slim_cachedir(){
	SLIMCACHEDIR=$(psgrep 'perl.*/squeeze|perl.*/slim|perl.*/logitech' | sed -n -e 's#^.*--cachedir[=]*[[:space:]]*\([^[:space:]]*\).*$#\1#p')

	# Punt
	if ([ -z "$SLIMCACHEDIR" ] || [ ! -d "$SLIMCACHEDIR" ]); then
		SLIMCACHEDIR='/var/lib/squeezeboxserver/cache'
	fi

	if [ ! -d "$SLIMCACHEDIR" ]; then
		SLIMCACHEDIR='/dev/null'
		return 1
	fi
	#echo "$SLIMCACHEDIR"
	return 0
}

####################################################################################
# Get the log directory..
#
spc_get_slim_log_dir(){
	SLIMLOGDIR=$(psgrep 'perl.*/squeeze|perl.*/slim|perl.*/logitech' | sed -n -e 's#^.*--logdir[=]*[[:space:]]*\(/[^ ]*\).*$#\1#p')
	SLIMLOGDIR=${SLIMLOGDIR%/}

	# Punt
	if ([ -z "$SLIMLOGDIR" ] || [ ! -d "$SLIMLOGDIR" ]); then
		SLIMLOGDIR='/var/log/squeezeboxserver'
	fi

	if [ ! -w "$SLIMLOGDIR" ]; then
		return 1
	fi
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
	DATE=$(date '+%F %H:%M:%S.%N')
	DATE=${DATE#??}
	DATE=${DATE%?????}
	echo "[${DATE}] ${SCRIPT} ($$)" $@
	#echo "[${DATE}] ${SCRIPT} ($LINENO)" $@
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
