#!/bin/bash
# Unix/Linux (Redhat, Fedora, Debian, Ubuntu, etc.) setup script for the SrvrPowerCtrl plugin.
# Version 20120714
#

#####################################################################################################
#
# Make sure that this script is running under the correct credentials..
#
#

if [ "$(whoami)" != "root" ]; then
	echo 'Error: This script needs to be run with root credentials,'
	echo "either via # sudo $0"
	echo 'or under su.'
	exit 1
fi

#####################################################################################################
#
# Load the helper functions..
#

helper_functions="$(dirname $(readlink -f $0))/spc-functions.sh"

if [ ! -f "$helper_functions" ]; then
	echo "ERROR: Cannot find ${helper_functions}"
	exit 1
fi

. $helper_functions

#####################################################################################################
#
# Important variables -- log our actions to the server log..
#
#

SERVERLOGGING=1
LOGGING=1
VERBOSE=1
SPCLOG=1
SLIMSERVICENAME=
SLIMSERVICEPID=
SLIMUSERNAME=
SLIMUSERGROUP=
REALUSER=
MADECHANGES=0

TARGET_DIR='/usr/local/sbin'
SUDOERS='/etc/sudoers'
HOST=$(hostname)


#####################################################################################################
#
# LMS can't run under root, so any modifications we'd make to sudoers
# as root would be meaningless.
#

chk_real_user(){
	REALUSER=$(who am i | sed -n -e 's/^\([^[:space:]]*\).*$/\1/p')
	if ( [ "$REALUSER" = 'root' ] || [ "$SLIMUSERNAME" = 'root' ] ); then
		spc_disp_error_message "Error: logitechmediaserver/squeezeboxserver needs to be running"
		spc_disp_error_message "       in order for this setup script to install properly."
		spc_disp_error_message "       Additionally, this script needs to be run via"
		spc_disp_error_message "       sudo and not directly by user root."
		exit 1
	fi
}


#####################################################################################################
#
# Change to the directory containing this script..
#

cd_to_script_dir(){
	#Change to the source script directory..
	SOURCE_DIR="$(dirname "$(readlink -f $0)")"

	cd "$SOURCE_DIR"
	CWD="$(pwd)"

	if [ ! "$SOURCE_DIR" = "$CWD" ]; then
		echo "Error: could not change to directory ${SOURCE_DIR}...exiting!"
		echo "${SOURCE_DIR} != ${CWD}"
		exit 1
	fi
	return 0
}


#####################################################################################################
#
# _index() see if a string contains a substring.  Useful bashism workaround.
#
#

_index()
{
  case $1 in
    *$2*)
    idx=${1%%$2*}
    _INDEX=$(( ${#idx} + 1 )) ;;
    *) _INDEX=0; return 1 ;;
  esac
}


#####################################################################################################
#
# Make sure the plugin directory has the SLIMUSERNAME permissions.
# If a manual install has been performed, the permissions could be anything.
#

fix_plugin_permissions(){
	# Get the sbs/lms username & group..
	if [ -z "$SLIMUSERNAME" ]; then
		spc_get_slim_username
	fi

	# Get the plugin directory..
	PLUGIN_DIR=$(dirname $(readlink -f $0))
	PLUGIN_DIR=${PLUGIN_DIR%%/scripts*}
	PARENT_DIR=${PLUGIN_DIR%%/SrvrPowerCtrl*}

	# We don't need to fixup permissions if we've
	# been installed via the Extension Downloader..
    if  ( _index "$PARENT_DIR" 'InstalledPlugins' ); then
		return 1
	fi

	# Check to make sure we're at least 4 directory levels deep..
	DEPTH=$(echo "$PLUGIN_DIR" | grep -o '/' | wc -l)
	if [ $DEPTH -lt 4 ]; then
		spc_disp_error_message "Error: cannot fix permissions on ${PLUGIN_DIR}."
		return 1
	fi

	# Check to see that the parent dir is owned by the LMS user..
	USER=$(stat -c %U "$PARENT_DIR")
	if [ ! "$USER" = "$SLIMUSERNAME" ]; then
		spc_disp_error_message "Warning: ${PARENT_DIR} is not owned by ${SLIMUSERNAME}."
		return 1
	fi

	# Fix the permissions
	spc_disp_message "Fixing permissions for ${PLUGIN_DIR}.."
	chown -R "${SLIMUSERNAME}:${SLIMUSERGROUP}" "$PLUGIN_DIR"

	return 0
}


#####################################################################################################
#
# Add permissions for SLIMUSERNAME to perform certin actions to /etc/sudoers
#

fixup_sudoers(){

	# Make a backup of the sudoers file..
	if [ ! -f "${SUDOERS}.org" ]; then
		cp --force $SUDOERS "${SUDOERS}.org"
	fi

	cp --force $SUDOERS "${SUDOERS}.bak"

	#Remove the requiretty directive if present so that the squeezecenter user
	# can run commands and scripts without being logged into a console..

	RE='^\#Defaults[[:blank:]]*requiretty'
	FOUNDSTR=$(grep -E "$RE" "$SUDOERS")

	if [ -z "$FOUNDSTR" ]; then
		spc_disp_message "Disabling ${SUDOERS} requiretty option.."
		sed -i -e 's/\s*Defaults\s*requiretty.*$/#Defaults    requiretty/' $SUDOERS
		MADECHANGES=1
	fi

	#Tack on permission for the lms user to run these commands sans password prompt..
	if [ $(systemctl 2>&1 | grep -c '\-\.mount') -gt 0 ]; then	
		SYSTEMCTL="$(which systemctl)"
		for CMD in "${SYSTEMCTL} poweroff" "${SYSTEMCTL} suspend" "${SYSTEMCTL} hibernate" "${SYSTEMCTL} hibrid-sleep" "${SYSTEMCTL} reboot" "$(which crontab) -l"
		do
			RE="${SLIMUSERNAME}.*${CMD}"
			FOUNDSTR=$(grep -E "$RE" "$SUDOERS")

			if [ -z "$FOUNDSTR" ]; then
				spc_disp_message "Modifying ${SUDOERS} to allow user ${SLIMUSERNAME} to run ${CMD}.."
				#ALL hosts vs specific host..
				echo "${SLIMUSERNAME} ALL = NOPASSWD: ${CMD}" >>$SUDOERS
				MADECHANGES=1
			else
				spc_disp_message "User ${SLIMUSERNAME} already has permissions to run ${CMD}.."
			fi

		done
		
	else
		for CMD in "$(which shutdown)*" "$(which pm-suspend)*" "$(which pm-hibernate)*" "$(which pm-powersave)*" "$(which crontab) -l"
		do
			RE="${SLIMUSERNAME}.*${CMD}"
			FOUNDSTR=$(grep -E "$RE" "$SUDOERS")

			if [ -z "$FOUNDSTR" ]; then
				spc_disp_message "Modifying ${SUDOERS} to allow user ${SLIMUSERNAME} to run ${CMD}.."
				#ALL hosts vs specific host..
				echo "${SLIMUSERNAME} ALL = NOPASSWD: ${CMD}" >>$SUDOERS
				MADECHANGES=1
			else
				spc_disp_message "User ${SLIMUSERNAME} already has permissions to run ${CMD}.."
			fi

		done
	fi
	
	
	return 0
}


#####################################################################################################
#
# Install our scripts to /usr/local/sbin. Fixup permissions on the scripts..
#

install_scripts(){

	SUDOERS='/etc/sudoers'
	HOST=$(hostname)


	# Newer versions of OS X don't have this directory!
	if [ ! -d "$TARGET_DIR" ]; then
		spc_disp_message "Creating ${TARGET_DIR}.."
		mkdir -p "$TARGET_DIR"
	fi

	for SCRIPTNAME in spc-*.sh
	do
		if [ -e "${TARGET_DIR}/${SCRIPTNAME}" ]; then
			mv -f -u "${TARGET_DIR}/${SCRIPTNAME}" "${TARGET_DIR}/${SCRIPTNAME}.bak"
		fi

		spc_disp_message "Installing ${SCRIPTNAME} to ${TARGET_DIR}"
		cp -f "$SCRIPTNAME" "${TARGET_DIR}/${SCRIPTNAME}"

		# Fixup permissions
		chown root:root "${TARGET_DIR}/${SCRIPTNAME}"
		chmod 755 "${TARGET_DIR}/${SCRIPTNAME}"

		RE="${SLIMUSERNAME}.*${TARGET_DIR}/${SCRIPTNAME}"
		FOUNDSTR=$(grep -E "$RE" "$SUDOERS")

		if [ -z "$FOUNDSTR" ]; then
			spc_disp_message "Modifying ${SUDOERS} to allow user ${SLIMUSERNAME} to run ${TARGET_DIR}/${SCRIPTNAME}"
			#ALL hosts vs specific host..
			#echo "${SLIMUSERNAME} ${HOST} = NOPASSWD: ${TARGET_DIR}/${SCRIPTNAME}*" >>$SUDOERS
			echo "${SLIMUSERNAME} ALL = NOPASSWD: ${TARGET_DIR}/${SCRIPTNAME}*" >>$SUDOERS
			MADECHANGES=1
		else
			spc_disp_message "User ${SLIMUSERNAME} already has permissions to run ${TARGET_DIR}/${SCRIPTNAME}"
		fi

	done


	return 0
}

create_log(){
	# Get the srvrpowerctrl.log file..
	spc_get_log_file
	touch "$SPCLOG"
	# Get the user & group
	spc_get_slim_username
	chown "${SLIMUSERNAME}:${SLIMUSERGROUP}" "$SPCLOG"

}

#####################################################################################################
#
# main()
#

# Make sure SBS/LMS is running..
spc_get_slim_pid

if [ -z "$SLIMSERVICEPID" ]; then
	echo "Error: squeezeboxserver/logitechmediaserver must be running for this"
	echo "       setup script to function."
	exit 1
fi

# Create our log file..
create_log

# Get the running service name..
spc_get_slim_servicename_nopid

# Get the user & group
spc_get_slim_username

# Check to see that SBS/LMS isn't running as root
chk_real_user

# Change to the directory containing this script..
cd_to_script_dir

echo 'Setting up SrvrPowerCtrl plugin helper scripts for Unix/Linux..'

# Fix permissions on the plugin folder (in case of a manual install..)
fix_plugin_permissions

# Give the LMS user permissions to run shutdown, pm-suspend, etc..
fixup_sudoers

# Install our helper scripts and give the LMS user permission to run them..
install_scripts

if [ $MADECHANGES -gt 0 ]; then
	spc_disp_message "Done!  Helper scripts installed to ${TARGET_DIR} and ${SUDOERS} has been updated."
else
	spc_disp_message "No modifications made to ${SUDOERS}"
	exit 1
fi

exit 0
