#!/bin/bash
# Unix/Linux (Redhat, Fedora, Debian, Ubuntu, etc.) setup script for the SrvrPowerCtrl plugin.
# Version 20120714
#

#####################################################################################################
#
# Make sure that this script is running under the correct credentials..
#
#

if [ $(whoami) != "root" ]; then
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
	SOURCE_DIR=$(dirname "$(readlink -f $0)")

	cd "$SOURCE_DIR"
	CWD=$(pwd)

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

	# Get the plugin directory..
	PLUGIN_DIR=$(dirname $(readlink -f $0))
	PLUGIN_DIR=${PLUGIN_DIR%%/scripts*}
	PARENT_DIR=${PLUGIN_DIR%%/SrvrPowerCtrl*}

	# We don't need to fixup permissions if we've
	# been installed via the Extension Downloader..
    if  ( _index "$PARENT_DIR" 'InstalledPlugins' ); then
		return 1
	fi

	# Check to make sure we're at least directory levels deep..
	DEPTH=$(echo "$PLUGIN_DIR" | egrep -o '/' | wc -l)
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
	FOUNDSTR=$(egrep "$RE" "$SUDOERS")

	if [ -z "$FOUNDSTR" ]; then
		spc_disp_message "Disabling ${SUDOERS} requiretty option.."
		sed -i -e 's/\s*Defaults\s*requiretty.*$/#Defaults    requiretty/' $SUDOERS
		MADECHANGES=1
	fi

	#Tack on permission for the lms user to run these commands sans password prompt..
	for CMD in "$(which shutdown)*" "$(which pm-suspend)*" "$(which pm-hibernate)*" "$(which pm-powersave)*" "$(which crontab) -l"
	do
		RE="${SLIMUSERNAME}.*${CMD}"
		FOUNDSTR=$(egrep "$RE" "$SUDOERS")

		if [ -z "$FOUNDSTR" ]; then
			spc_disp_message "Modifying ${SUDOERS} to allow user ${SLIMUSERNAME} to run ${CMD}.."
			#ALL hosts vs specific host..
			echo "${SLIMUSERNAME} ALL = NOPASSWD: ${CMD}" >>$SUDOERS
			MADECHANGES=1
		else
			spc_disp_message "User ${SLIMUSERNAME} already has permissions to run ${CMD}.."
		fi

	done

	return 0
}


#####################################################################################################
#
# Install our scripts to /usr/local/sbin. Fixup permissions on the scripts..
#

install_scripts(){

	SUDOERS='/etc/sudoers'
	HOST=`hostname`


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
		FOUNDSTR=$(egrep "$RE" "$SUDOERS")

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












































#####################################################################################################
#
# Change to the source script dir.  Get our source & target dirs..
#


#Change to the source script directory..
REL_DIR=$(readlink -f $0)
SOURCE_DIR=$(dirname "$REL_DIR")
#PLUGINS_DIR=`echo "$SOURCE_DIR" | sed -n -e 's#^\(.*/Plugins\)/.*$#\1#p'`
PLUGINS_DIR=`echo "$SOURCE_DIR" | sed -n -e 's#^\(.*/SrvrPowerCtrl\)/.*$#\1#p'`

cd "$SOURCE_DIR"
CWD_DIR=$(pwd)

if [ ! "$SOURCE_DIR" = "$CWD_DIR" ]; then
  echo "Error: could not change to directory ${SOURCE_DIR}...exiting!"
  echo "${SOURCE_DIR} != ${CWD_DIR}"
  exit 1
fi

#Target dir we're copying scripts into..
TARGET_DIR='/usr/local/sbin'


# SBSVER is used in the utiltiy scripts to find the proper log file..
# Can we assume that LMS is installed off of /var/lib?  That will be the usual case..
#SBSVER=`echo "$SOURCE_DIR" | sed -n -e 's#^/var/lib/\([^/]*\)/.*$#\1#p'`

if [ -z "$SBSVER" ]; then
  # Just get the 3rd level directory name..
  # Works for both /var/lib/squeezeboxserver and /usr/share/squeezeboxserver
  SBSVER=${SOURCE_DIR#/*/*/}
  SBSVER=${SBSVER%%/*}
fi


echo "Installing for ${SLIMSERVICENAME_UC}, user ${SLIMUSERNAME}:${SLIMUSERGROUP}"
echo "  from ${SOURCE_DIR} to ${TARGET_DIR}"


#####################################################################################################
#
# Fixup permissions on our plugin directory.
#
# Are we where we think we need to be??
#
# Because the following permissions fix-up uses relative paths, it is potentially
# dangerious if the script is located in the wrong location, e.g. /home/user.
# So..test that the script is at least located off of a 'squeezecenter' or
# 'squeezeboxserver' dir.  Also..we don't need to fixup permissions if we've
# been installed via the Extension Downloader..
#





#SBSUSER='squeezeboxserver'
# Get the service user by looking at the owner of the Plugins dir..
# If LMS is being run from svn code AND if the user hasn't replaced the
# server/Plugins directory to a link to /var/lib/squeezeboxserver/Plugins, then
# this code will fail.
if [ ! -z "$PLUGINS_DIR" ]; then
  SBSUSER=`stat -c %U "$PLUGINS_DIR"`
else
  SBSUSER=`stat -c %U "$0"`
fi


SBSGROUP=`id -ng $SBSUSER`


#####################################################################################################
#
# Start processing..
#




#####################################################################################################
#
# Fixup permissions on our plugin directory.
#
# Are we where we think we need to be??
#
# Because the following permissions fix-up uses relative paths, it is potentially
# dangerious if the script is located in the wrong location, e.g. /home/user.
# So..test that the script is at least located off of a 'squeezecenter' or
# 'squeezeboxserver' dir.  Also..we don't need to fixup permissions if we've
# been installed via the Extension Downloader..
#

CUR_DIR=`pwd`
DIR_TEST2='InstalledPlugins'

for DIR_TEST1 in 'squeezecenter' 'squeezeboxserver'
do
	if ( _index "$CUR_DIR" "$DIR_TEST1" )
	  then
	    if  ( ! _index "$CUR_DIR" "$DIR_TEST2" )
	      then
	        REL_DIR=`readlink -f ../../.`
            if [ "$REL_DIR" != "/" ]; then
	          echo "Fixing up permissions on ${REL_DIR}"
	          chown -R "${SBSUSER}:${SBSGROUP}" "$REL_DIR"
            fi
			break
	    fi
	fi
done

#####################################################################################################
#
# Allow the SC/SBS user to use the 'shutdown' command..
#
#ALLOW='/etc/shutdown.allow'
#FOUNDSTR=`egrep "$SBSUSER" "$ALLOW"`
#if [ -z "$FOUNDSTR" ]; then
#  echo "Adding ${SBSUSER} to ${ALLOW} file.."
#  touch "$ALLOW"
#  echo "$SBSUSER" >>"$ALLOW"
#fi

#####################################################################################################
#
# Make modifications to /etc/sudoers...tell sudo that the user has permissions to run
# these commands without raising a password prompt..
#
#

#File we will be modifying..
SUDOERS='/etc/sudoers'
HOST=`hostname`

MADECHANGES=0

#Make a backup of the sudoers file..
if [ ! -f "${SUDOERS}.org" ]; then
  echo "Backing up up ${SUDOERS} to ${SUDOERS}.org.."
  cp --force $SUDOERS "${SUDOERS}.org"
fi

echo "Backing up up ${SUDOERS} to ${SUDOERS}.bak.."
cp --force $SUDOERS "${SUDOERS}.bak"

#Remove the requiretty directive if present so that the squeezecenter user
# can run commands and scripts without being logged into a console..

EXPR='^\#Defaults[[:blank:]]*requiretty'
FOUNDSTR=`egrep "$EXPR" "$SUDOERS"`

if [ -z "$FOUNDSTR" ]; then
  echo "Disabling ${SUDOERS} requiretty option.."
  sed -i -e 's/\s*Defaults\s*requiretty$/#Defaults    requiretty/' $SUDOERS
  MADECHANGES=1
else
  echo "Option 'requiretty' already disabled.."
fi

#Tack on permission for the lms user to run these commands sans password prompt..
for CMD in "$(which shutdown)*" "$(which pm-suspend)*" "$(which pm-hibernate)*" "$(which pm-powersave)*" "$(which crontab) -l"
do
  EXPR="${SBSUSER}.*${CMD}"
  FOUNDSTR=`egrep "$EXPR" "$SUDOERS"`

  if [ -z "$FOUNDSTR" ]; then
    echo "Modifying ${SUDOERS} to allow user ${SBSUSER} to run ${CMD}.."
    #ALL hosts vs specific host..
    echo "${SBSUSER} ALL = NOPASSWD: ${CMD}" >>$SUDOERS
    MADECHANGES=1
  else
    echo "User ${SBSUSER} already has permissions to run ${CMD}.."
  fi

done

#####################################################################################################
#
# Copy our helper scripts to the target dir, fixup logpaths, make them executable, add permissions to sudoers
#
#

for SCRIPTNAME in spc-*.sh
do
  if [ -e "${TARGET_DIR}/${SCRIPTNAME}" ]; then
    mv -f -u "${TARGET_DIR}/${SCRIPTNAME}" "${TARGET_DIR}/${SCRIPTNAME}.bak"
  fi

  echo "Installing ${SCRIPTNAME} to ${TARGET_DIR}"
  cp -f "$SCRIPTNAME" "${TARGET_DIR}/${SCRIPTNAME}"

  # Fixup the reference to the srvrpowerctrl.log file location in the script..
  sed -i -e "s/SBSVERSION/${SBSVER}/g" "${TARGET_DIR}/${SCRIPTNAME}"

  # Fixup permissions
  chown root:root "${TARGET_DIR}/${SCRIPTNAME}"
  chmod 755 "${TARGET_DIR}/${SCRIPTNAME}"

  EXPR="${SBSUSER}.*${TARGET_DIR}/${SCRIPTNAME}"
  FOUNDSTR=`egrep "$EXPR" "$SUDOERS"`

  if [ -z "$FOUNDSTR" ]; then
    echo "Modifying ${SUDOERS} to allow user ${SBSUSER} to run ${TARGET_DIR}/${SCRIPTNAME}"
    #ALL hosts vs specific host..
    echo "${SBSUSER} ALL = NOPASSWD: ${TARGET_DIR}/${SCRIPTNAME}*" >>$SUDOERS
    MADECHANGES=1
  else
    echo "User ${SBSUSER} already has permissions to run ${TARGET_DIR}/${SCRIPTNAME}"
  fi

done



#####################################################################################################
#
# Setup finish..
#

if [ $MADECHANGES -gt 0 ]; then
  echo "Done!  Helper scripts installed to ${TARGET_DIR} and ${SUDOERS} has been updated."
  exit 0
else
  echo "No modifications made to ${SUDOERS}"
  exit 1
fi
