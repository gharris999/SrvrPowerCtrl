#!/bin/bash
# Unix/Linux (Redhat, Fedora, Debian, Ubuntu, etc.) setup script for the SrvrPowerCtrl plugin
# Version 20120714
#


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

PLUGIN_DIR=$(dirname $(readlink -f $0))
PLUGIN_DIR=${PLUGIN_DIR%%/scripts*}

echo "PLUGIN_DIR == ${PLUGIN_DIR}"

