#!/bin/bash

# Script to force a MiniDLNA rescan of the system..

. /usr/local/sbin/systype


SOURCE_MOUNT='/mnt/GaryMedia'
TARGET_MOUNT='/mnt/Media'

export SOURCE="${SOURCE_MOUNT}/Videos"
export TARGET="${TARGET_MOUNT}Videos"

export DEBUG=0
export QUIET=0
export VERBOSE=0

link_dir() {

	TRGTPATH=$(readlink -f "$1")
	LINKPATH="${TARGET}${TRGTPATH#${SOURCE}}"

	if [ $VERBOSE -gt 0 ]; then
		echo "SOURCE == ${TRGTPATH}"
		echo "TARGET == ${LINKPATH}"
	fi

	# Create a symbolic link to the directory only if the path does not exist and if the link does not exist..
	if [ ! -d "$LINKPATH" ]; then
		if [ ! -h "$LINKPATH" ]; then
			if [ ! -L "$LINKPATH" ]; then
				if [ $QUIET -lt 1 ]; then
					echo "Linking ${TRGTPATH}"
					echo " --to-- ${LINKPATH}"
				fi
				if [ $DEBUG -lt 1 ]; then
					ln -s "$TRGTPATH" "$LINKPATH"
					chown -h daadmin:daadmin "$LINKPATH"
				else
					echo ln -s "$TRGTPATH" "$LINKPATH"
					echo chown -h daadmin:daadmin "$LINKPATH"
				fi
			fi
		fi
	fi

}

link_file() {

	TRGTPATH=$(readlink -f "$1")
	LINKPATH="${TARGET}${TRGTPATH#${SOURCE}}"

	#Check for a filename with a different extension...
	CHKPATH="$(dirname "$LINKPATH")"
	CHKFILE="$(basename "$LINKPATH")"
	CHKFILE="${CHKFILE%%.*}*"

	#echo "Checking for dup '${CHKFILE}' in '${CHKPATH}'"
	DUPCOUNT=$(find "$CHKPATH" -type f -name "$CHKFILE" | wc -l)
	#echo "Found: $DUPCOUNT"
	if [ $VERBOSE -gt 0 ]; then
		echo "SOURCE == ${TRGTPATH}"
		echo "TARGET == ${LINKPATH}"
	fi

	# Create a symbolic link to the file only if no file with that name with any extension exists,
	# AND if the file does not already exist,
	# AND if there isn't alreay a symbolic link present..
	if [ $DUPCOUNT -lt 1 ]; then
		if [ ! -f "$LINKPATH" ]; then
			if [ ! -h "$LINKPATH" ]; then
				if [ ! -L "$LINKPATH" ]; then
					[ $QUIET -lt 1 ] && echo "Linking ${TRGTPATH}"
					[ $QUIET -lt 1 ] && echo " --to-- ${LINKPATH}"
					if [ $DEBUG -lt 1 ]; then
						ln -s "$TRGTPATH" "$LINKPATH"
						chown -h daadmin:daadmin "$LINKPATH"
					else
						echo ln -s "$TRGTPATH" "$LINKPATH"
						echo chown -h daadmin:daadmin "$LINKPATH"
					fi
				fi
			fi
		fi
	fi
}

export -f link_dir
export -f link_file


disp_syntax(){
	echo $(basename $0) [--debug] [--quiet] [--verbose] [--no-rescan]
	exit 0
}

##########################################################################################
#
# main()
#
# args: [-h|--help] [-d|--debug] [-q|--quiet] [-v|--verbose] [-n|--no-rescan]
#
##########################################################################################

BLOCKFILE='/run/lock/spc-block'
NO_RESCAN=0

# Process args

ARGS=$(getopt -o hdqvVn -l help,debug,quiet,verbose,no-rescan,source:,target: -n "$(basename $0)" -- "$@")

eval set -- "$ARGS"

while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help)
			disp_syntax
			;;
		-d|--debug)
			DEBUG=1
			;;
		-q|--quiet)
			QUIET=1
			;;
		-v|-V|--verbose)
			QUIET=0
			VERBOSE=1
			;;
		-n|--no-rescan)
			NO_RESCAN=1
			;;
		--source)
			shift
			if [ -d "${1}" ]; then
				SOURCE_MOUNT="${1}"
			fi
			;;
		--target)
			shift
			if [ -d "${1}" ]; then
				TARGET_MOUNT="${1}"
			fi
			;;
		*)
			if [ -d "${1}" ]; then
				if [ -z "$SOURCE_MOUNT" ]; then
					SOURCE_MOUNT="${1}"
				elif [ -z "$TARGET_MOUNT" ]; then
					TARGET_MOUNT="${1}"
				fi
			fi
			;;
	esac
	shift
done

# Error checking..

if [ ! -d "$TARGET_MOUNT" ]; then
	echo "Error: target mount point ${SOURCE_MOUNT} not found."
	disp_syntax
fi

# Set the srvrpowerctrl block..
touch "$BLOCKFILE"

[ $QUIET -lt 1 ] && echo '============================================================================'

# stop minidlna so it doesn't start a rescan while we're creating links..
if [ $NO_RESCAN -lt 1 ]; then

	if [ $USE_SYSTEMD -gt 0 ]; then
		systemctl stop minidlna
	elif [ $USE_UPSTART -gt 0 ]; then
		initctl stop minidlna
	else
		service minidlna stop
	fi
fi

# For each type of Media Dir we want to link..
for MEDIA_DIR in Pictures Videos
do
	SOURCE="${SOURCE_MOUNT}/${MEDIA_DIR}"
	TARGET="${TARGET_MOUNT}/${MEDIA_DIR}"

	# Print broken links
	[ $QUIET -lt 1 ] && echo '============================================================================'
	[ $QUIET -lt 1 ] && echo "Searching for broken links in ${TARGET}.."
	[ $QUIET -lt 1 ] && find -L "$TARGET" -type l

	# Delete broken links
	[ $QUIET -lt 1 ] && echo '============================================================================'
	[ $QUIET -lt 1 ] && echo "Deleating broken links in ${TARGET}.."
	if [ $DEBUG -gt 0 ]; then
		echo find -L "$TARGET" -type l -delete -print
	else
		if [ $QUIET -lt 1 ]; then
			find -L "$TARGET" -type l -delete -print
		else
			find -L "$TARGET" -type l -delete
		fi
	fi

	if [ -d "$SOURCE" ]; then
		# Create links to new directories..
		[ $QUIET -lt 1 ] && echo '============================================================================'
		[ $QUIET -lt 1 ] && echo "Creating links to ${SOURCE} directories.."
		find "$SOURCE" -type d -exec bash -c 'link_dir '\"'{}'\"'' \;

		# Create links to new files..
		[ $QUIET -lt 1 ] && echo '============================================================================'
		[ $QUIET -lt 1 ] && echo "Creating links to ${SOURCE} files.."
		find "$SOURCE" -type f -exec bash -c 'link_file '\"'{}'\"'' \;
	fi

done


# Restart minidlna and force new scan..
if [ $NO_RESCAN -lt 1 ]; then
	[ $QUIET -lt 1 ] && echo '============================================================================'

	if [ $IS_DEBIAN -gt 0 ]; then
		ENV_FILE='/etc/default/minidlna'
	else
		ENV_FILE='/etc/sysconfig/minidlna'
	fi

	# Modify the service env vars file to include the rescan option
	sed -i -e 's/^MDLNA_ROPTIONS=.*$/MDLNA_ROPTIONS="-R"/' "$ENV_FILE"
	[ $QUIET -lt 1 ] && echo "Rescan option in ${ENV_FILE} now set to: $(egrep 'MDLNA_ROPTIONS' "$ENV_FILE")"

	if [ $(pgrep -f minidlnad | wc -l) -gt 0 ]; then
		[ $QUIET -lt 1 ] && echo "Restarting minidlna.."
		if [ $USE_SYSTEMD -gt 0 ]; then
			systemctl restart minidlna.service
		elif [ $USE_UPSTART -gt 0 ]; then
			initctl restart minidlna
		else
			service minidlna rescan
		fi

	else
		[ $QUIET -lt 1 ] && echo "Starting minidlna.."
		if [ $USE_SYSTEMD -gt 0 ]; then
			systemctl start minidlna.service
		elif [ $USE_UPSTART -gt 0 ]; then
			initctl start minidlna
		else
			service minidlna rescan
		fi
	fi

	[ $QUIET -lt 1 ] && echo "MiniDLNA now rescanning content in ${TARGET}.."
	sleep 5

	# Remove the rescan option from the service env vars file
	sed -i -e 's/^MDLNA_ROPTIONS=.*$/MDLNA_ROPTIONS=/' "$ENV_FILE"
	[ $QUIET -lt 1 ] && echo "Rescan option in ${ENV_FILE} reset to: $(egrep 'MDLNA_ROPTIONS' "$ENV_FILE")"

fi

# Remove the srvrpowerctrl blockfile..
rm "$BLOCKFILE"

[ $QUIET -lt 1 ] && echo 'Done.'

exit 0
