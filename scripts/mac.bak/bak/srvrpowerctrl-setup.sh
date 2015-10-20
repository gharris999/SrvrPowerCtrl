#!/bin/sh
# OSX setup script for the SrvrPowerCtrl plugin
#

echo 'Setting up OSX helper scripts for the SrvrPowerCtrl plugin..'

# dash doesn't like [[ $x =~ $y ]] so use this function instead..
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
# Make sure that this script is running under the correct credentials AND from the correct location..
#
#

if [ $(whoami) != "root" ]; then
    echo 'Error: This script needs to be run with root credentials,'
    echo "either via # sudo $0"
    echo 'or under su.'
    exit
fi

if [ ! -z "$1" ]; then
    SBSUSER="$1"
  else
    SBSUSER=`/usr/bin/logname`
fi

if [ "$SBSUSER" == "$user" ]; then
    echo 'Error: user name required!  Run this script'
    echo "via # sudo $0 \$USER"
    exit
fi

if [ -z "$SBSUSER" ]; then
    echo 'Error: user name required!  Run this script via:'
    echo "# sudo $0 \$USER"
    exit
fi

#Which version are we working with here, SC7.3.x or SBS7.4?
SBSVER='Squeezebox'

#/Users/$USER/Library/Caches/Squeezebox/InstalledPlugins/Plugins/SrvrPowerCtr
if [ ! -d "/Users/$SBSUSER/Library/Caches/Squeezebox" ]
  then
    SBSVER='SqueezeCenter'
fi


#Target dir we're copying scripts into..
TRG_SCRIPT_DIR='/usr/local/sbin'

# Snow leopard: /usr/local may not exist!
if [ ! -d "$TRG_SCRIPT_DIR" ]
  then
    echo "Creating dir $TRG_SCRIPT_DIR"
    mkdir -pv "$TRG_SCRIPT_DIR"
fi


#Change to the source script directory..
SRC_SCRIPT_DIR=`dirname "$0"`
cd "$SRC_SCRIPT_DIR"

echo "Installing for $SBSVER from $SRC_SCRIPT_DIR.."

#####################################################################################################
#
# Allow the SC/SBS user to use the 'shutdown' command..
#
#ALLOW='/etc/shutdown.allow'
#FOUNDSTR=`/usr/bin/egrep "$SBSUSER" "$ALLOW"`
#if [ "$FOUNDSTR" = "" ]
#  then
#    echo "Adding $SBSUSER to $ALLOW file.."
#    touch "$ALLOW"
#    echo "$SBSUSER" >>"$ALLOW"
#fi

#####################################################################################################
#
# Make modifications to /etc/sudoers...tell sudo that the user has permissions to run
# these commands without raising a password prompt..
#
#

#File we will be modifying..
SUDOERS='/etc/sudoers'
HOST=`/bin/hostname`

MADECHANGES=0

#Make a backup of the sudoers file..
if [ ! -f "${SUDOERS}.org" ]; then
  echo "Backing up up ${SUDOERS} to ${SUDOERS}.org.."
  cp -f "$SUDOERS" "${SUDOERS}.org"
fi
cp -f "$SUDOERS" "${SUDOERS}.bak"

#Remove the requiretty directive if present so that the squeezecenter user
# can run commands and scripts without being logged into a console..

EXPR='^\#Defaults[[:blank:]]*requiretty'
#EXPR='^\#Defaults\s*requiretty'
FOUNDSTR=`/usr/bin/egrep "$EXPR" "$SUDOERS"`

if [ "$FOUNDSTR" = "" ]
  then
    echo "Disabling $SUDOERS requiretty option.."
    sed -i -e 's/\s*Defaults\s*requiretty$/#Defaults    requiretty/' $SUDOERS
    #sed -i -e 's/\s*Defaults *requiretty$/#Defaults    requiretty/' $SUDOERS
    MADECHANGES=1
  else
    echo "Option 'requiretty' already disabled.."
fi

#Tack on permission to run these commands sans password prompt..

#           Shutdown/etc.
#for CMD in '/sbin/shutdown*' '/usr/bin/pmset*' '/sbin/SystemStarter*'
for CMD in "$(which shutdown)*" "$(which pmset)*" "$(which SystemStarter)*" "$(which crontab) -l"
do

  #EXPR="$SBSUSER ALL=NOPASSWD:$CMD"
  EXPR="$SBSUSER.*$CMD"
  FOUNDSTR=`/usr/bin/egrep "$EXPR" "$SUDOERS"`

  if [ "$FOUNDSTR" = "" ]
    then
      echo "Modifying $SUDOERS to allow user $SBSUSER to run $CMD.."
      #ALL hosts vs specific host..
      echo "$SBSUSER ALL=NOPASSWD:$CMD" >>$SUDOERS
      #echo "$SBSUSER $HOST=NOPASSWD:$CMD" >>$SUDOERS
      MADECHANGES=1
    else
      echo "User $SBSUSER already has permissions to run $CMD.."
  fi

done

#####################################################################################################
#
# Copy our helper scripts to the target dir and make them executable and add permissions to sudoers
#
#

for scriptnm in spc-*.sh
do
  if [ ! -e "$TRG_SCRIPT_DIR/$scriptnm" ]
    then
      echo "Installing $scriptnm to $TRG_SCRIPT_DIR"
      cp "$scriptnm" "$TRG_SCRIPT_DIR/$scriptnm"
      #fixup the log paths in the scripts..
      sed -i -e "s/USERNAME/$SBSUSER/" "$TRG_SCRIPT_DIR/$scriptnm"
      sed -i -e "s/SBSVERSION/$SBSVER/g" "$TRG_SCRIPT_DIR/$scriptnm"
      #delete the backup..
      rm "$TRG_SCRIPT_DIR/$scriptnm-e"
      #fix permissions on the scripts..
      chmod 755 "$TRG_SCRIPT_DIR/$scriptnm"
      chown  root:wheel "$TRG_SCRIPT_DIR/$scriptnm"
  fi

  #EXPR="$SBSUSER ALL=NOPASSWD:$CMD"
  EXPR="$SBSUSER.*$TRG_SCRIPT_DIR/$scriptnm"
  FOUNDSTR=`/usr/bin/egrep "$EXPR" "$SUDOERS"`

  if [ "$FOUNDSTR" = "" ]
    then
      echo "Modifying $SUDOERS to allow user $SBSUSER to run $TRG_SCRIPT_DIR/$scriptnm.."
      #ALL hosts vs specific host..
      echo "$SBSUSER ALL=NOPASSWD:$TRG_SCRIPT_DIR/$scriptnm*" >>$SUDOERS
      #echo "$SBSUSER $HOST=NOPASSWD:$TRG_SCRIPT_DIR/$scriptnm*" >>$SUDOERS
      MADECHANGES=1
    else
      echo "User $SBSUSER already has permissions to run $CMD.."
  fi
done

####################################################################################################
#
# OSX has no /var/lock directory for lock files...create one.
#

if [ ! -d /var/lock ]
  then
    mkdir /var/lock
fi

# Make /var/lock accessible to SrvrPowerCtrl..
chmod 777 /var/lock

####################################################################################################
#
# Create the log file...
#
log_file="/Users/$SBSUSER/Library/Logs/$SBSVER/srvrpowerctrl.log"
touch "$log_file"
chmod 777 "$log_file"


#####################################################################################################
#
# Setup finish..
#

if [ $MADECHANGES = 1 ]
  then
    echo "Done!  Helper scripts installed to $TRG_SCRIPT_DIR and $SUDOERS has been updated."
    exit 0
  else
    echo "No modifications made to $SUDOERS"
    exit 1
fi
