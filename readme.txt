README for SrvrPowerCtrl: a plugin for SqueezeCenter / Squeezebox Server.

= Intro =====================================================================

The SrvrPowerCtrl plugin allows you to shutdown, restart, suspend or hibernate
your SqueezeCenter server hardware using your IR remote or a SqueezeBox Controller.
If you have a SqueezeBox Controller, (SBC, a.k.a. jive) you'll find new menu
items under "Extras->Server Power Control".  On the SB2, SB3 or Transporter
displays and using the IR remote, look for new menu items under
"Extras->Server Power Control."

Additionally, the plugin will allow you to switch the current player
to SqueezeNetwork before the shutdown/suspend/hibernate occurs.

Also, the plugin will optionally wait until all SqueezeCenter 'sleep' timers
have expired.  See SqueezeCenter->Settings->Plugins-Server Power Control Settings
for more info.

Also, the plugin can monitor your attached players and
shutdown/suspend/hibernate the system if they have been idle (not playing)
for a user-settable period of time.  Your SB3/Transporter/SBBoom/SBC includes
a WOL (wake-on-lan) feature and should wake up your server when you next
want to play something when you use your remote.

Finally, you can define an "end of day" period where the plugin will
again monitor for idle players and then perform one of the "stock"
actions or execute a user-definable custom script.

= Extension Downloader Install Notes ========================================

The instructions that follow assume that you've installed SrvrPowerCtrl
"manually"...i.e. not by using the "Extension Downloader" built into
SqueezeCenter.  If you have installed via the Extension Downloader, then the
post install setup scripts that must be run to complete the SrvrPowerCtrl
installation will be in locations other than as described below.

So, if you've installed via the Extension Downloader, please reference these
locations instead:

For OSX: setup_script="/Users/$USER/Library/Caches/SqueezeCenter/InstalledPlugins/Plugins/SrvrPowerCtrl/scripts/MacOSX/srvrpowerctrl-setup.sh"

For Debian/Ubuntu: sudo chmod a+x /var/lib/squeezecenter/cache/InstalledPlugins/Plugins/SrvrPowerCtrl/scripts/Debian/srvrpowerctrl-setup.sh

For Redhat/Fedora/CentOS: sudo chmod a+x /var/lib/squeezecenter/cache/InstalledPlugins/Plugins/SrvrPowerCtrl/scripts/Redhat/srvrpowerctrl-setup.sh


= Windows Installation ======================================================

To install the plugin for windows, copy the plugin files to:
  C:\Program Files\SqueezeCenter\server\Plugins\SrvrPowerCtrl

  Then, you'll need to download SCPowerTool.zip from the same place you downloaded
  SrvrPowerCtrl.  Copy the SCPowerTool.exe file to somewhere in your path, e.g.
  C:\Windows\System32.

  Make sure that the SCPowerTool.exe command operates on your system.  Try:

    Start->Run: cmd /C start /B SCPowerTool.exe --standby --wakeup=-60

  On Windows Vista, try: Goto Start, type cmd in the search box. Do not press ENTER.
  Right click on cmd.exe in the search results area and click Run as Administrator.
  Now type into the DOS box:

    SCPowerTool.exe --standby --wakeup=-60

  That command should send your system into standby and then wake it back up
  again after 60 seconds.

  Assuming that that command worked, you can reboot your server or restart
  the SqueezeCenter service to activate the plugin.

  You can check to see if the plugin is active by browsing SqueezeCenter's
  web UI to the Settings->Plugins->Server Power Control:Settings page.

  If you would like to use the WakeupOnStandBy utility available at
  www.dennisbabkin.com/wosb to set the server wakeup time rather than
  SCPowerTool.exe, set the "Schedule Wakeup Command" in the settings to:

    c:\windows\system32\cmd.exe /C start /B wosb.exe /run /systray dt=%f tm=%t" /ami


= OSX Installation ==========================================================

Requirements: The following commands MUST be available from a terminal prompt:

  sudo
  shutdown
  pmset

To install the plugin for OSX, do the following:

  Make sure that you are logged into your Mac using the same user account that
  you used when you first setup SqueezeCenter.

  Install the contents of the zip file to:

    /Users/$USER/Library/Application Support/SqueezeCenter/Plugins/SrvrPowerCtrl

  ..where $USER is your user account name.

  Run the setup script:  From a terminal window, paste in the following commands,
  one at a time, hitting 'enter' in between:

    # setup_script="/Users/$USER/Library/Application Support/SqueezeCenter/Plugins/SrvrPowerCtrl/scripts/MacOSX/srvrpowerctrl-setup.sh"
    # sudo chmod 755 "$setup_script"
    # sudo "$setup_script" $USER

  -- or, perform the setup manually: --

  Copy the SrvrPowerCtrl scripts to /usr/local/sbin and make them executable:

    # sleep_script="/Users/$USER/Library/Application Support/SqueezeCenter/Plugins/SrvrPowerCtrl/scripts/MacOSX/spc-sleep.sh"
    # hiber_script="/Users/$USER/Library/Application Support/SqueezeCenter/Plugins/SrvrPowerCtrl/scripts/MacOSX/spc-hibernate.sh"
    # wakeu_script="/Users/$USER/Library/Application Support/SqueezeCenter/Plugins/SrvrPowerCtrl/scripts/MacOSX/spc-wakeup.sh"

    # cp "$sleep_script" /usr/local/sbin
    # cp "$hiber_script" /usr/local/sbin
    # cp "$wakeu_script" /usr/local/sbin

  Fixup the log paths in the scripts:

    # sed -i -e "s/usrnm/$USER/" /usr/local/sbin/spc-sleep.sh
    # sed -i -e "s/usrnm/$USER/" /usr/local/sbin/spc-hibernate.sh
    # sed -i -e "s/usrnm/$USER/" /usr/local/sbin/spc-wakeup.sh


    # chmod 755 /usr/local/sbin/spc-sleep.sh
    # chown  root:wheel /usr/local/sbin/spc-sleep.sh
    # chmod 755 /usr/local/sbin/spc-hibernate.sh
    # chown  root:wheel /usr/local/sbin/spc-hibernate.sh
    # chmod 755 /usr/local/sbin/spc-wakeup.sh
    # chown  root:wheel /usr/local/sbin/spc-wakeup.sh

  Allow the user to use the 'shutdown' command..

    # touch /etc/shutdown.allow
    # echo "$USER" >>/etc/shutdown.allow

  Make a backup copy of your sudoers file:
    # cp /etc/sudoers /etc/sudoers.bak

  Now edit the sudoers file either via:
    # sudo visudo
  ..or using a 'friendlier' editor:
    # sudo nano /etc/sudoers

  Make the following changes to /etc/sudoers:

  Mac OSX users should add these lines to the end of the /etc/sudoers file,
  substituting the username under which you installed SqueezeCenter for 'usrnm'
  ------------------------------------------------------------------------------
      usrnm ALL=NOPASSWD:/sbin/shutdown*
      usrnm ALL=NOPASSWD:/usr/bin/pmset*
      usrnm ALL=NOPASSWD:/usr/local/sbin/spc-sleep.sh
      usrnm ALL=NOPASSWD:/usr/local/sbin/spc-hibernate.sh
      usrnm ALL=NOPASSWD:/usr/local/sbin/spc-wakeup.sh*

  If you somehow screw up your /etc/sudoers file (i.e. 'sudo' no longer works..)
  then enable the root user (google OSX how to enable root user) and then restore
  your saved sudoers:

    # su
    # cp /etc/sudoers.bak /etc/sudoers

  On OSX systems, now verify that your user account has permission to shutdown the
  system without being prompted for a password:

    # sudo /sbin/shutdown -k now

  The system should respond with:

    System going down IMMEDIATELY


= Redhat, Fedora, CentOS, Debian, Ubuntu, etc. Linux Installation =============

Requirements: The following commands MUST be available from a terminal prompt:

  sudo
  shutdown

Additionally, to support suspend and hibernation, the pm-utils package must
be installed.  Check to see that these commands are runnable from a
terminal prompt as well:

  pm-suspend
  pm-hibernate

Not all linux distros include those commands in a default installation.
Consult your distro's documentation for adding (if necessary) the sudo,
shutdown and pm-utils packages.

Alternately, your distro may use different commands to initiate a
shutdown/restart/suspend/hibernation.  If so, edit the command lines
on the SqueezeCenter->Settings->Plugins->Server Power Control->Settings
page accordingly.

To install the plugin for linux, as root, do the following:

  Install the contents of the zip file to:
    /var/lib/squeezecenter/Plugins/SrvrPowerCtrl

  Try to avoid unzipping the SrvrPowerCtrl.zip file on a windows machine
  and then transferring the files to your linux server.  Instead, transfer
  the SrvrPowerCtrl.zip file to /var/lib/squeezecenter/Plugins.  Then open
  a terminal window (on the server or remotly via ssh) and become root:

    # su   (you'll be prompted for root's password).

  Unzip the plugin files:

    # cd /var/lib/squeezecenter/Plugins
    # unzip SrvrPowerCtrl.zip
    # rm SrvrPowerCtrl.zip

   (The actual file you downloaded may have a different name.  Fix these
    commands up accordingly.)

  Run the setup script:

  For Debian and Ubuntu and the like:

    # chmod a+x /var/lib/squeezecenter/Plugins/SrvrPowerCtrl/scripts/Debian/srvrpowerctrl-setup.sh
    # /var/lib/squeezecenter/Plugins/SrvrPowerCtrl/scripts/Debian/srvrpowerctrl-setup.sh

  For Redhat, Fedora, CentOS, etc:

    # chmod a+x /var/lib/squeezecenter/Plugins/SrvrPowerCtrl/scripts/Redhat/srvrpowerctrl-setup.sh
    # /var/lib/squeezecenter/Plugins/SrvrPowerCtrl/scripts/Redhat/srvrpowerctrl-setup.sh


  -- or, perform the setup manually: --

  Fix up the permissions to the new plugin files:
    chown -R squeezecenter:squeezecenter /var/lib/squeezecenter/Plugins

  Copy the SqueezeCenter restart script to /usr/local/sbin and make it executable:
    cp /var/lib/squeezecenter/Plugins/SrvrPowerCtrl/scripts/Redhat/spc-restart.sh /usr/local/sbin
    chmod 755 "/usr/local/sbin/spc-restart.sh"
    chown  root:root "/usr/local/sbin/spc-restart.sh"

    cp /var/lib/squeezecenter/Plugins/SrvrPowerCtrl/scripts/Redhat/spc-wakeup.sh /usr/local/sbin
    chmod 755 "/usr/local/sbin/spc-wakeup.sh"
    chown  root:root "/usr/local/sbin/spc-wakeup.sh"

  Add the squeezecenter user to the /etc/shutdown.allow file:
    touch /etc/shutdown.allow
    echo 'squeezecenter' >>/etc/shutdown.allow

  Make a backup copy of your sudoers file:
    # cp /etc/sudoers /etc/sudoers.bak

  Now edit the sudoers file either via:
    # sudo visudo
  ..or using a 'friendlier' editor:
    # sudo nano /etc/sudoers

  Now, make the following changes to /etc/sudoers:

    For Redhat, Fedora & CentOS users, comment out the line with: Defaults requiretty
      so that it reads: #Defaults requiretty
      and add these lines to the end of the /etc/sudoers file:
    ----------------------------------------------------------------------------------
      ## Allows members of the squeezecenter group to shutdown this system
      %squeezecenter ALL=NOPASSWD:/sbin/shutdown
      %squeezecenter ALL=NOPASSWD:/usr/sbin/pm-suspend
      %squeezecenter ALL=NOPASSWD:/usr/sbin/pm-hibernate
      %squeezecenter ALL=NOPASSWD:/usr/local/sbin/spc-restart.sh
      %squeezecenter ALL=NOPASSWD:/usr/local/sbin/spc-wakeup.sh

    Debian and Ubuntu users should add these lines to the end of the /etc/sudoers file:
    ------------------------------------------------------------------------------
      squeezecenter ALL = NOPASSWD: /sbin/shutdown*
      squeezecenter ALL = NOPASSWD: /usr/sbin/pm-suspend*
      squeezecenter ALL = NOPASSWD: /usr/sbin/pm-hibernate
      squeezecenter ALL = NOPASSWD: /usr/local/sbin/spc-wakeup.sh*
      squeezecenter ALL = NOPASSWD: /usr/local/sbin/spc-restart.sh

    Alternatly, you could use these sudoers entries with Debian and Ubuntu:
    ------------------------------------------------------------------------------
      Cmnd_Alias SHUTDOWN_CMDS = /sbin/shutdown, /sbin/reboot, /sbin/halt
      squeezecenter ALL=NOPASSWD:/usr/sbin/pm-suspend*
      squeezecenter ALL=NOPASSWD:/usr/sbin/pm-hibernate
      squeezecenter ALL = NOPASSWD: /usr/local/sbin/spc-wakeup.sh*
      squeezecenter ALL = NOPASSWD: /usr/local/sbin/spc-restart.sh
      squeezecenter ALL=(ALL) NOPASSWD: SHUTDOWN_CMDS

  On Linux systems, verify that the 'squeezecenter' user now has permissions to shutdown
  the system without raising any prompts.  Logged in as root, try executing the following
  command from a terminal window:

     sudo -u squeezecenter sudo /sbin/shutdown -k -h now

  If the command responds with:

    The system is going down for system halt NOW!

  ..then the plugin ought to be able to shutdown/restart/etc your system
  from the squeezecenter service.  But if the command responds with a
  prompt for the squeezecenter user's password, then something is amiss
  with the sudoers file. The whole point is to allow the squeezecenter
  user to shutdown/suspend/hibernate/etc the system WITHOUT requiring
  a password.

  Restarting SqueezeCenter should activate the plugin:

      # /etc/init.d/squeezecenter stop
      # /etc/init.d/squeezecenter start

  You can check to see if the plugin is active by browsing SqueezeCenter's
  web UI to the Settings->Plugins->Server Power Control:Settings page.

= TROUBLESHOOTING ===========================================================

All Operating Systems:

Can't see the SrvrPowerCtrl settings page
-----------------------------------------

If you are unable to "see" SrvrPowerCtrl's setting page, or if the page
returns a 404 file not found error, please try manually rebooting your
server.  If the problem persists, please try the following:

Windows:

Make sure that you've used WinZip to unzip the plugin's
zip file.  The built-in windows zip extraction utility seems to have
problems extracting all the necessary directory names.  With WinZip, make
sure, when extracting, that you are extracting to
"C:\Program Files\SqueezeCenter\server\Plugins" AND that you are extracting
"All files/folders in archive" AND that "Use folder names" is checked.

Linux:

Try to avoid unzipping the plugin's zip distribution file on a Windows
machine and then copying the files over to the linux server.  It's been
my experience that line endings in the plugin's files may get modified
in that process.  Instead, please copy the whole zip to
/var/lib/squeezecenter/Plugins and unzip it there from a terminal window:

# unzip SrvrPowerCtrl.zip


Wake for alarms problems
------------------------

Windows 7 beta:

There may be a problem with the current version of SCPowerTool.exe waking
machines running the Windows 7 beta.  I'll look into this when Windows 7
is released and I have a Win7 development environment configured.

Ubuntu:

Remember that Ubuntu 8.10 and later systems default to keeping the hardware
clock set to local time rather than to UTC.  In order for system wakeup-for-alarms
scheduling to work on these systems, change the "Schedule Wakeup Command" from:

    /usr/local/sbin/scwakeup.sh %d

-- to --

    /usr/local/sbin/scwakeup.sh %l


CentOS:

If you can't get your CentOS machine to wakeup for alarms, check various
scripts (like /etc/rc.d/init.d/halt) for calls to hwclock and comment them
out. Pay special attention to /usr/lib/pm-utils/sleep.d/90clock.  You may
need to comment out the call to /sbin/hwclock in suspend_clock() in order
to get the rtc to wake the machine after suspending.


= WARNING ===================================================================

Warning:  Using the "Shutdown to SqueezeNetwork" and like options with
  a SqueezeBox Receiver (SBR) REQUIRES that you have previously setup
  said SBR and your SBC to connect to SqueezeNetwork.  Don't try using
  this option until you've successfully played content from SqueezeNetwork
  on your SBR/SBC.  See bug 7254 for more information:

	http://bugs.slimdevices.com/show_bug.cgi?id=7254

Also:  When performing a "Shutdown to SqueezeNetwork" from the SBC for a SBR,
  it can take up to a full minute or more for the SBC to "follow along" to SN.
  Be patient.  Let the SBC do it's thing.

  With the Shutdown/Suspend/Hibernate to SqueezeNetwork functions, the plugin
  waits two minutes before initiating the Shutdown/Suspend/Hibernate in order
  to give any connected SBC time to make the switch to SqueezeNetwork.

Also also: the plugin tries to be well behaved and allow you to change your
  mind after initiating an action.  On the remote, a press of the "left" key
  within 15 seconds will cancel the action.  Additionally, on windows machines,
  the psshutdown program will pop up a dialog box allowing you to cancel
  the action.

Also also also: there is a setting in Settings->Plugins->Server Power Control
  that allows you to specify whether or not attached players will turn off
  when shutting down/suspending/hibernating.  This allows other plugins like
  PowerCenter or IRBlaster to work their magic and turn off other devices.


= srvrpowerctrl CLI ==========================================================


This plugin extends SqueezeCenter's CLI with a
'srvrpowerctrl' command:  srvrpowerctrl, action, message, [switchclient]

Allowable actions are: actions, status, shutdown, restart, suspend, hibernate,
shutdown2AS, suspend2AS, hibernate2AS, setblock, clearblock, listblock.

The 'status' action returns 'enabled' if the plugin is installed and enabled.

The 'actions' action returns a list of the enabled actions.

With the '2AS' (to SqueezeNetwork) actions, the 'switchclient' parameter should be
the MAC address of the Squeezebox (Transporter, SBR) player you want to switch to
SqueezeNetwork. For the other allowable actions, the 'switchclient' parameter is
not required.

Example:

echo srvrpowerctrl hibernate2AS Switching_to_SqueezeNetwork '00:04:20:06:29:11' | nc -w 1 127.0.0.1 9090

In the above example, the NetCat (nc) utility sends the CLI request to port 9090 on
the local host.  That command could be used as part of an automated server shutdown
script fired off by cron.  It would have the effect of switching the requested
player over to SqueezeNetwork (where you might have a wake-up alarm set) and
then hibernating the local SqueezeCenter server hardware.


= Blocking SrvrPowerCtrl actions =============================================

SrvrPowerCtrl includes several mechanisms so that other SqueezeCenter plugins or
entities outside of SqueezeCenter (scripts, etc.) can place a "block" on
SrvrPowerCtrl's actions.  Examples of where this might be desirable
include 1). plugins which need to guarantee that they remain running for a
specific period of time or 2). tasks on the server which need to run
through to their completion without risk of interruption.

On linux systems, the easiest way to block SrvrPowerCtrl actions is by simply
creating the file /var/lock/spc-block.  E.G. # touch /var/lock/spc-block
Files in /var/lock don't survive a system restart so there is no need to
delete the block file to clear it if reboot your system.  Otherwise, clear
the block file with # rm --force /var/lock/spc-block.

If you want to be able to clear the block file from the web UI or via the CLI,
you must give the squeezecenter user ownership of the block file and write
permissions to the /var/lock directory.

On windows systems, SrvrPowerCtrl looks for a C:\Windows\temp\spc-block
block file.

The method to set a block in perl is:

    $blockcode = Plugins::SrvrPowerCtrl:Plugins::setBlock($client, 'set', 'BlockerName', 'ReasonForBlockingMessage');

  When a block has been placed and a shutdown/restart/suspend/etc. [action] is
  initiated by SrvrPowerCtrl, the [action] is blocked and a message is displayed
  on the player that initiated the action:

    [action] is unavailable.  [BlockerName] is requesting that the server stay running because [ReasonForBlockingMessage].

  So, if the block was placed with the following call:

    $blockcode = Plugins::SrvrPowerCtrl:Plugins::blockAction($client, 'set', 'The kitchen timer', 'cookies are in the oven');

  .. the message displayed would be:

    Shutdown is unavailable.  The kitchen timer is requesting that the server stay running because cookies are in the oven.

  Multiple blocks may be set by the same or different 'BlockerName's.  blockAction()
  should return a unique $blockcode for each block.  A return value of -1 indicates an error.

Blocks may be cleared (allowing SrvrPowerCtrl actions to resume) via a call to:

    $retcode = Plugins::SrvrPowerCtrl:Plugins::setBlock($client, 'clear', 'BlockerName', $blockcode);

  In the call above, the 'BlockerName' must be the same as that used in the previous
  'set' call.  The $blockcode must be the blockcode returned by the blockAction()
  in that 'set' call.  If the 'clear' action succeeds, blockAction() returns the
  remaining number of blocks.  If it fails, it returns -1.

You may also place and clear blocks via the CLI:

  From within a SC plugin:
	$client->execute(['srvrpowerctrl', 'setblock', 'My reason for blocking msg', 'blockername']);

  Or external to SC, eg from a script:
	#!/bin/sh
	echo srvrpowerctrl setblock Im_busy_dont_bother_me_kid blockername | nc -w 1 your_sc_ip 9090

  In both cases, if the CLI call succeeds, the CLI returns a blockcode, otherwise, it
  returns -1.

  Blocks may be cleared via the CLI as well:

	$client->execute(['srvrpowerctrl', 'clearblock', $blockcode, 'blockername']);

    -or-

	#!/bin/sh
	echo srvrpowerctrl clearblock blockcode blockername | nc -w 1 127.0.0.1 9090


  Again, if the clear action succeeds, the CLI return the remaining number of extant blocks, or -1 if it fails.

  A special case is made if the 'blockername' is "viacli".  In that case, the
  the blockcode is not required to clear the block:

	$client->execute(['srvrpowerctrl', 'clearblock', undef, 'viacli']);

    -or-

	#!/bin/sh
	echo srvrpowerctrl clearblock nada viacli | nc -w 1 127.0.0.1 9090

Finally, you may use the CLI to list all the existing blocks:

	$client->execute(['srvrpowerctrl', 'listblock', 'nada', 'blockername']);

    -or-

	#!/bin/sh
	echo srvrpowerctrl listblock nada blockername | nc -w 1 127.0.0.1 9090

  SrvrPowerCtrl returns the list of blockcodes, blockowners and blocking reasons
  in the form:
    blockcode1%7blockowner%7blockreason%0A blockcode2%7blockowner%7blockreason%0A

= Please Report Bugs ========================================================

Report bugs to the 3rd Party Plugins forum at Slimdevices.com:

  http://forums.slimdevices.com/showthread.php?t=48521


= Acknowledgements ==========================================================

This plugin is a modification of AdrianC's (a.k.a. tenwiseman's)
Server Power Control plugin: http://adrianonline.wordpress.com/
http://forums.slimdevices.com/showthread.php?t=32674

Thanks to bklass for all jive help.

Also thanks to mavit for the sleep button hook.

Also also thanks to peterw for the sleep+hold button hook.

Also thanks to Epoch1970 for testing and ideas.
