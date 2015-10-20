#!/bin/bash
# ===============================================================================================
# Update Operating System and Logitech Media Server
# ===============================================================================================
#Notes:

#Check slim_customize & git customize logic.

#create a git repo status fuction that tests for
#       modified:   Slim/Schema.pm
#       modified:   Slim/Schema/Genre.pm

#unless ! SLIMCUSTOMIZE, if nomods, perform cust.
#if SLIMUPDATE, perform mods on slim..


helper_functions="$(dirname $(readlink -f $0))/spc-functions.sh"

. $helper_functions

# Override helper defaults..
VERBOSE=1
LOGGING=1

#----------------------------------------------------------------
# Vars:
#TMPFILE=$( /bin/mktemp -t )
#APTFILE=$( /bin/mktemp -t )


MYNAME="gharris999@earthlink.net"
MYOS="$(uname -a)"
HOST="$(hostname)"

UDAPSVNLOGFILE='/usr/local/sbin/Net-UDAP/svn.log'

# lms update options..
SLIMGITUPDATE=1
SLIMGITCLEAN=1
SLIMUPDATE=0
SLIMCUSTOMIZE=1
SLIMWIPEDB=0
#UPDATELMS=0

# OS update options..
NOOSUPDATE=0

# Other options..
REBOOT=1
SHUTDOWN=0
RESTARTSERVICE=0
CHKMEDIA=0
DEBUG=1



####################################################################################
# Get the log dir and files..
#
prep_logfiles(){

	if [ -z "$SLIMSERVERLOG" ]; then
		spc_get_slim_server_log
	fi

	# Truncate the server log file
	if [ -w $SLIMSERVERLOG ]; then
		> $SLIMSERVERLOG
	fi

	if [ -z $SLIMGITLOG ]; then
		spc_get_slim_localrepo

	fi

	if [ -z $SPCLOG ]; then
		spc_get_log_file
		spc_log_message
	fi

	spc_log_slim_message 'Started..'
	spc_log_message 'Started..'

}

stop_services(){
	spc_disp_message "Stopping ${SLIMSERVICENAME} and minidlna.."
	spc_stop_slim_service
	service minidlna stop
}

start_services(){
	spc_disp_message "Starting ${SLIMSERVICENAME} and minidlna.."
	service $SLIMSERVICENAME start
	service minidlna start
}

slim_git_inrepo(){
	if [ -z $SLIMLOCALREPO ]; then
		spc_get_slim_localrepo
	fi

	cd "$SLIMLOCALREPO"
	if [ $(pwd) != "$SLIMLOCALREPO" ]; then
		spc_disp_error_message "Error: cannot change to ${SLIMLOCALREPO}.."
		exit 1
	fi
}

slim_git_clean(){
	slim_git_inrepo
	spc_disp_message "Cleaning ${SLIMLOCALREPO}.."
	spc_log_slim_git_message "Cleaning ${SLIMLOCALREPO}.."
	spc_log_slim_git_message "git reset --hard ${SLIMLOCALREPO}"
    git reset --hard | tee --append "$SLIMGITLOG"
	spc_log_slim_git_message "git clean -fd ${SLIMLOCALREPO}"
    git clean -fd | tee --append "$SLIMGITLOG"
}

slim_git_update(){
	slim_git_inrepo
	spc_disp_message "Updating ${SLIMLOCALREPO}.."
	spc_log_slim_git_message "Updating ${SLIMLOCALREPO}.."
	spc_log_slim_git_message "git pull ${SLIMLOCALREPO}"
	git pull | tee --append "$SLIMGITLOG"
}


#################################################################################################
# Call the slim service customization script..
#
slim_customize(){
	if [ -z $SLIMSERVICENAME ]; then
		spc_get_slim_servicename_nopid
	else
		start_services
	fi
	slim_git_inrepo
    spc_disp_message "Customizing ${SLIMLOCALREPO}.."
	/usr/local/sbin/config-lms-customize.sh "$SLIMSERVICENAME" "$ISGIT"
}


#################################################################################################
# Wipe the db files for lms & minidlna..
#
wipe_dbs(){
	if [ -z $SLIMCACHEDIR ]; then
		spc_get_slim_cachedir
	fi

	DBDIR="$SLIMCACHEDIR"
	if [ ! -d "${DBDIR}" ]; then
		DBDIR="/var/lib/squeezeboxserver/cache"
	fi

	if [ -d "${DBDIR}" ]; then
		pushd "${DBDIR}"
		if [ $(pwd) = "$DBDIR" ]; then
			spc_disp_message "Wiping db files from ${DBDIR}"
			rm -f *.db
			popd
		fi
	fi

	DBDIR='/var/lib/minidlna'

	if [ -d "${DBDIR}" ]; then
		pushd "${DBDIR}"
		if [ $(pwd) = "$DBDIR" ]; then
			spc_disp_message "Wiping db files from ${DBDIR}"
			rm -f *.db
			popd
		fi
	fi
}

#################################################
# Check the media drives for errors..
#
fsck_media_drv(){
	#/usr/local/sbin/chkdsk --optimize
	/usr/local/sbin/chkdsk
}

####################################################################################
# Update the operating system..
#
update_os(){

	if [ $NOOSUPDATE -gt 0 ]; then
		return 1
	fi

	if [ $SLIMUPDATE -gt 0 ]; then
		# Enable the repo..
		spc_disp_message "Enabling repo deb http://debian.slimdevices.com testing main"
		sed -i -e 's/^#.*\(deb[[:space:]]*http.* testing .*\)$/\1/' /etc/apt/sources.list
	fi

	#spc_disp_message 'Running apt-get update..'

	#apt-get -qy update

	#spc_disp_message 'Running apt-get dist-upgrade..'
	#apt-get --quiet -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" --force-yes -qfuy dist-upgrade | tee --append "$SPCLOG"

	spc_disp_message 'Running apt-get-security-updates..'

	/usr/local/sbin/apt-get-secruity-updates


	if [ $SLIMUPDATE -gt 0 ]; then
		if [ $ISGIT -gt 0 ]; then
			# disable the service..
			spc_disp_message "Disabling logitechmediaserver service"
			sysv-rc-conf logitechmediaserver off
		fi
		# Disable the repo..
		spc_disp_message "Disabling repo deb http://debian.slimdevices.com testing main"
		sed -i -e 's/^\(deb[[:space:]]*http.* testing .*\)$/#\1/' /etc/apt/sources.list

		# Perform our customization..
			if [ $SLIMCUSTOMIZE -gt 0 ]; then
			spc_disp_message "Customizing stock logitechmediaserver.."
			/usr/local/sbin/config-lms-customize.sh 'squeezeboxserver' 0
		fi
	fi

}

####################################################################################
# Other chores that may need to be done from time to time
#
other_housekeeping(){
	# Fix the tmp directory..
	chown root:root /tmp
	chmod 1777 /tmp

}

####################################################################################
# main()
#

# Process command line..
for ARG in $*
do
case $ARG in
	-h|--help)
		echo "${SCRIPT} [--nochkmedia] [--chkmedia] [--restart] [--shutdown] [--noreboot] [--gitclean] [--gitupdate] [--nogitupdate] [--lmsupdate] [--nolmsupdate] [--nolmscustomize] [--wipedb] [--force] [--noapt] [--debug]"
		exit 0
		;;
	--nochkmedia)
		CHKMEDIA=0
		spc_disp_message 'Media drive WILL NOT be checked for integrity..'
		;;
	--chkmedia)
		CHKMEDIA=1
		spc_disp_message 'Media drive WILL be checked for integrity..'
		;;
	--restart)
		RESTARTSERVICE=1
		REBOOT=0
		spc_disp_message 'System WILL restart services at the conclusion of the update..'
		;;
	--shutdown)
		SHUTDOWN=1
		REBOOT=0
		spc_disp_message 'System WILL shutdown at the conclusion of the update..'
		;;
	--noreboot)
		REBOOT=0
		spc_disp_message 'System WILL NOT reboot..'
		;;
	--gitclean)
		SLIMGITCLEAN=1
		SLIMGITUPDATE=1
		spc_disp_message 'LMS git repo will be cleaned..'
		;;
	--gitupdate)
		SLIMGITUPDATE=1
		spc_disp_message 'LMS git repo will be updated..'
		;;
	--nogitupdate)
		SLIMGITUPDATE=0
		spc_disp_message 'LMS git repo WILL NOT be updated..'
		;;
	--lmsupdate)
		SLIMUPDATE=1
		spc_disp_message 'LogitechMediaServer WILL BE updated via apt-get..'
		;;
	--nolmsupdate)
		SLIMUPDATE=0
		spc_disp_message 'LogitechMediaServer WILL NOT BE updated via apt-get..'
		;;
	--nolmscustomize)
		SLIMCUSTOMIZE=0
		;;
	--wipedb)
		SLIMWIPEDB=1
		spc_disp_message 'LMS and minidlna db files WILL BE wiped..'
		;;
	--force)
		SLIMUPDATE=1
		SLIMGITCLEAN=1
		spc_disp_message 'LogitechMediaServer WILL BE updated via apt-get..'
		spc_disp_message 'LMS git repo will be cleaned..'
		;;
	--noapt)
		NOOSUPDATE=1
		spc_disp_message 'No OS apt-get update / upgrade..'
		;;
	--debug)
		DEBUG=1
		echo 'Debugging ON..'
		;;
	*)
esac
done

if [ $REBOOT -gt 0 ]; then
  spc_disp_message 'System WILL reboot at the conclusion of the update..'
fi

# Get service info
spc_get_slim_service_name
spc_get_slim_username
spc_get_slim_localrepo
spc_get_slim_cachedir
spc_get_slim_server_log
spc_get_slim_git_log
spc_get_log_file

# Prep logs
prep_logfiles

if [ $DEBUG -gt 0 ]; then
  echo "Service: ${SLIMSERVICENAME}"
  echo "User:    ${SLIMUSERNAME}"
  echo "Group:   ${SLIMUSERGROUP}"
  echo "IsGIT:   ${ISGIT}"
  echo "Repo:    ${SLIMLOCALREPO}"
  echo "LogDir:  ${SLIMLOGDIR}"
  echo "Cache:   ${SLIMCACHEDIR}"
  echo "SrvrLog: ${SLIMSERVERLOG}"
  echo "GitLog:  ${SLIMGITLOG}"
  echo "SPCLog:  ${SPCLOG}"
  #exit 1
fi

# Shutdown services..
stop_services

# Update operating system..
if [ $NOOSUPDATE -lt 1 ]; then
	update_os
fi

# Update the LMS git repo..
if [ $ISGIT -gt 0 ]; then
	if [ $SLIMGITCLEAN -gt 0 ]; then
		# Clean the LMS git repo..
		slim_git_clean
	fi
	if [ $SLIMGITUPDATE -gt 0 ]; then
		slim_git_update
	fi
	if ([ $SLIMCUSTOMIZE -gt 0 ] && [ $SLIMGITCLEAN -gt 0 ]); then
		# Install LMS customizations..
		#/usr/local/sbin/config-lms-customize.sh "$SLIMSERVICENAME" $ISGIT
		slim_customize
	fi
fi

# Perform other housekeeping..
other_housekeeping

if [ $SLIMWIPEDB -gt 0 ]; then
	wipe_dbs
fi

if [ $CHKMEDIA -gt 0 ]; then
	fsck_media_drv
fi

#restart the system
if [ $REBOOT -gt 0 ]; then
  spc_disp_message 'Waiting 60 seconds to reboot the system..'
  /sbin/shutdown -r +1
  exit 0
fi

#shutdown the system
if [ $SHUTDOWN -gt 0 ]; then
  spc_disp_message 'Waiting 60 seconds to shutdown the system..'
  /sbin/shutdown -h +1
  exit 0
fi


if [ $RESTARTSERVICE -gt 0 ]; then
	start_services
fi

spc_disp_message 'Finished..'


exit 0

