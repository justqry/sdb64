#!/bin/bash
#   SD bash install script
#   (c) 2023-2025 Donald Montaine and Mark Buller
#   This software is released under the Blue Oak Model License
#   a copy can be found on the web here: https://blueoakcouncil.org/license/1.0.0
#   
#   rev 0.9-1 Mar 25 mab - generic install
#   rev 0.9.1 Mar 25 mab - add optional install of TAPE / RESTORE subsystem
#   rev 0.9.0 Jan 25 mab - tighten up permissions
#                        - build with embedded python
#                        - sdsys's pri group now sdusers - note require sudo groupdel sdsys in deletesd.sh
#                        - comment define statement in file sdsys/GPL.BP/define_install.h and recompile CPROC at end of install, 
#
# in the install dir?
if test -f "installsd.sh"; then
  echo 
else
  echo "Not in install directory, (sdb64), this is not going to work"
  exit
fi 
# 
if [[ $EUID -eq 0 ]]; then
  echo "This script must NOT be run as root" 1>&2
  exit
fi
if [ -f  "/usr/local/sdsys/bin/sd" ]; then
  echo "A version of sd is already installed"
  echo "Uninstall it before running this script"
  exit
fi
#
tgroup=sdusers
tuser=$USER
cwd=$(pwd)
#
clear 
echo SD installer
echo -----------------------
echo
echo "For this install script to work you must have sudo installed"
echo "and be a member of the sudo group."
echo
echo "Installer tested on Ubuntu 24.04 Desktop & Server, Mint 22 and Fedora 41"
echo
read -p "Continue? (y/N) " yn
case $yn in
    [yY] ) echo;;
    [nN] ) exit;;
    * ) exit ;;
esac
# 
is_ubuntu=0
is_fedora=0

distro=$(lsb_release -is)
#
case $distro in
      "Ubuntu" ) echo "Distro is: Ubuntu"
                 is_ubuntu=1;;
      "Fedora" ) echo "Distro is: Fedora"
                 is_fedora=1;;
      "Raspbian" ) echo "Distro is: Raspbian"
                 is_ubuntu=1;;
      * ) echo "Distro is: " $distro
          echo "Defaulting to Ubuntu, YMMV"
          is_ubuntu=1;;
esac 
echo
echo If requested, enter your account password:
sudo date
clear
echo
#
# package installer is based on distro, clucky but easy to read
if [ $is_ubuntu -eq 1 ]; then
  echo Installing required packages with apt-get
  sudo apt-get install build-essential micro lynx libbsd-dev libsodium-dev openssh-server python3-dev
fi
#
if [ $is_fedora -eq 1 ]; then
  echo Installing required packages with dnf
  sudo dnf -y install make automake gcc gcc-c++ kernel-devel micro lynx libbsd-devel libsodium-devel openssh-server python3-devel
fi 

# rev 0.9.0 need python dev to build, did we get it?
python3 --version
if [ $? -eq 0 ]; then
# got it, what version and where are the include files?
  PY_HDRS=$(python3-config --includes)
# remove the first "-I"
#  and get the first path (for some reason its output twice?
  HDRS_STR="${PY_HDRS%% *}"
  HDRS_STR="${HDRS_STR#-I}"
#
  echo "path to include file: " $HDRS_STR
# now create the includ file we will use
  echo "#include <"$HDRS_STR"/Python.h>" > sd64/gplsrc/sdext_python_inc.h
  
  
else
  echo "Python missing, cannot build"
  exit
fi

cd $cwd/sd64

sudo make 
# rev 0.9.0 if make fails, abort install
if [ $? -eq 0 ]; then
  echo "Successful Build"
else
  echo "Build Failed"
  exit
fi

# Create sd system user and group
echo "Creating group: sdusers"
sudo groupadd --system sdusers
sudo usermod -a -G sdusers root

echo "Creating user: sdsys."
sudo useradd --system sdsys -G sdusers
echo "Setting user: sdsys default group to sdusers."
sudo usermod -g sdusers sdsys

sudo cp -R sdsys /usr/local
# Fool sd's vm into thinking gcat is populated
sudo touch /usr/local/sdsys/gcat/\$CPROC
# create errlog
sudo touch /usr/local/sdsys/errlog

# install TAPE and RESTORE system?
read -p "Install TAPE and RESTORE subsystem (y/N) " yn
case $yn in
    [yY] ) 
        echo "copy TAPE and RESTORE programs to GPL.BP"
        sudo cp tape/GPL.BP/* /usr/local/sdsys/GPL.BP 
        echo "copy TAPE and RESTORE verbs to VOC"
        sudo cp -R tape/VOC/* /usr/local/sdsys/VOC
        echo ;;  
esac

# copy install template
sudo cp -R bin /usr/local/sdsys
sudo cp -R gplsrc /usr/local/sdsys
sudo cp -R gplobj /usr/local/sdsys
sudo mkdir /usr/local/sdsys/gplbld
sudo cp -R gplbld/FILES_DICTS /usr/local/sdsys/gplbld/FILES_DICTS
sudo cp -R terminfo /usr/local/sdsys

# build program objects for bootstrap install
sudo python3 gplbld/bbcmp.py /usr/local/sdsys GPL.BP/BBPROC GPL.BP.OUT/BBPROC
sudo python3 gplbld/bbcmp.py /usr/local/sdsys GPL.BP/BCOMP GPL.BP.OUT/BCOMP
sudo python3 gplbld/bbcmp.py /usr/local/sdsys GPL.BP/PATHTKN GPL.BP.OUT/PATHTKN
sudo python3 gplbld/pcode_bld.py

sudo cp Makefile /usr/local/sdsys
sudo cp gpl.src /usr/local/sdsys
sudo cp terminfo.src /usr/local/sdsys

sudo chown -R sdsys:sdusers /usr/local/sdsys
sudo chown root:root /usr/local/sdsys/ACCOUNTS/SDSYS
sudo chmod 654 /usr/local/sdsys/ACCOUNTS/SDSYS
sudo chown -R sdsys:sdusers /usr/local/sdsys/terminfo

sudo cp sd.conf /etc/sd.conf
sudo chmod 644 /etc/sd.conf
sudo chmod -R 755 /usr/local/sdsys
sudo chmod 775 /usr/local/sdsys/errlog
sudo chmod -R 775 /usr/local/sdsys/prt

#   Add $tuser to sdusers group
sudo usermod -aG sdusers $tuser

# directories for sd accounts
ACCT_PATH=/home/sd
if [ ! -d "$ACCT_PATH" ]; then
   sudo mkdir -p "$ACCT_PATH"/user_accounts
   sudo mkdir "$ACCT_PATH"/group_accounts
   sudo chown sdsys:sdusers "$ACCT_PATH"
   sudo chmod 775 "$ACCT_PATH"
   sudo chown sdsys:sdusers "$ACCT_PATH"/group_accounts
   sudo chmod 775 "$ACCT_PATH"/group_accounts
   sudo chown sdsys:sdusers "$ACCT_PATH"/user_accounts
   sudo chmod 775 "$ACCT_PATH"/user_accounts
fi

sudo ln -s /usr/local/sdsys/bin/sd /usr/local/bin/sd

# Install sd service for systemd
SYSTEMDPATH=/usr/lib/systemd/system

if [ -d  "$SYSTEMDPATH" ]; then
    if [ -f "$SYSTEMDPATH/sd.service" ]; then
        echo "SD systemd service is already installed."
    else
        echo "Installing sd.service for systemd."

        sudo cp usr/lib/systemd/system/* $SYSTEMDPATH

        sudo chown root:root $SYSTEMDPATH/sd.service
        sudo chown root:root $SYSTEMDPATH/sdclient.socket
        sudo chown root:root $SYSTEMDPATH/sdclient@.service

        sudo chmod 644 $SYSTEMDPATH/sd.service
        sudo chmod 644 $SYSTEMDPATH/sdclient.socket
        sudo chmod 644 $SYSTEMDPATH/sdclient@.service
    fi
fi

# Copy saved directories if they exist
if [ -d /home/sd/ACCOUNTS ]; then
  echo Moved existing ACCOUNTS directory
  sudo rm -fr /usr/local/sdsys/ACCOUNTS
  sudo mv /home/sd/ACCOUNTS /usr/local/sdsys
else
  echo Saved Accounts Directory Does Not Exist
fi

cd /usr/local/sdsys

#   Start SD server
echo "Starting SD server."
sudo bin/sd -start
echo
echo "Bootstap pass 1"
sudo bin/sd -i

# files added in pass1 need perm and owner setup
sudo chmod -R 755 /usr/local/sdsys/\$HOLD.DIC
sudo chmod -R 775 /usr/local/sdsys/\$IPC
sudo chmod -R 755 /usr/local/sdsys/\$MAP
sudo chmod -R 755 /usr/local/sdsys/\$MAP.DIC
sudo chmod -R 755 /usr/local/sdsys/ACCOUNTS.DIC
sudo chmod -R 755 /usr/local/sdsys/DICT.DIC
sudo chmod -R 755 /usr/local/sdsys/DIR_DICT
sudo chmod -R 755 /usr/local/sdsys/VOC.DIC
#
sudo chown -R sdsys:sdusers /usr/local/sdsys/\$HOLD.DIC
sudo chown -R sdsys:sdusers  /usr/local/sdsys/\$IPC
sudo chown -R sdsys:sdusers  /usr/local/sdsys/\$MAP
sudo chown -R sdsys:sdusers  /usr/local/sdsys/\$MAP.DIC
sudo chown -R sdsys:sdusers  /usr/local/sdsys/ACCOUNTS.DIC
sudo chown -R sdsys:sdusers  /usr/local/sdsys/DICT.DIC
sudo chown -R sdsys:sdusers  /usr/local/sdsys/DIR_DICT
sudo chown -R sdsys:sdusers  /usr/local/sdsys/VOC.DIC

echo "Bootstap pass 2"
sudo bin/sd -internal SECOND.COMPILE
echo "Bootstap pass 3"
sudo bin/sd RUN GPL.BP WRITE_INSTALL_DICTS NO.PAGE
echo "Compile C and I type dictionaries"
sudo bin/sd THIRD.COMPILE

echo "Compile CPROC without IS_INSTALL defined"
sudo bash -c 'echo "*comment out * $define IS_INSTALL" > /usr/local/sdsys/GPL.BP/define_install.h'
sudo bin/sd -internal BASIC GPL.BP CPROC
sudo chmod -R 755 /usr/local/sdsys/gcat

#  create a user account for the current user
echo
echo
if [ ! -d /home/sd/user_accounts/$tuser ]; then 
    echo "Creating a user account for" $tuser
    sudo bin/sd create-account USER $tuser no.query
fi

echo
echo Stopping sd
sudo sd -stop

echo
echo Enabling services
sudo systemctl start sd.service
sudo systemctl start sdclient.socket
sudo systemctl enable sd.service
sudo systemctl enable sdclient.socket

sudo sd -stop
sudo sd -start
sudo sd -stop

cd $cwd/sd64
echo
echo Compiling terminfo database
sudo bin/sdtic -v ./terminfo.src
echo Terminfo compilation completed
sudo cp terminfo.src /usr/local/sdsys
echo

cd $cwd

echo "Removing binary bits from repository"
sudo rm sd64/gplobj/*.o
sudo rm sd64/bin/sd*
sudo rm sd64/bin/*.so
sudo rm sd64/pass1
sudo rm sd64/pass2
sudo rm sd64/pcode_bld.log


# display end of script message
echo
echo
echo -----------------------------------------------------
echo "The SD server is installed."
echo
echo "The /home/sd directory has been created."
echo "User directories are created under /home/sd/user_accounts."
echo "Group directories are created under /home/sd/group_accounts."
echo "Accounts are only created using CREATE-ACCOUNT in SD."
echo
echo "Reboot to assure that group memberships are updated"
echo "and the APIsrvr Service is enabled."
echo
echo "After rebooting, open a terminal and enter 'sd' "
echo "to connect to your sd home directory."
echo
echo "To completely delete SD, run the" 
echo "deletesd.sh bash script provided."
echo
echo -----------------------------------------------------
echo
read -p "Restart computer now? (y/N) " yn
case $yn in
    [yY] ) sudo reboot;;
    [nN] ) echo;;
    * ) echo ;;
esac
exit
