#!/bin/bash
# Name : setup.sh
# Author : Phil Cryer <phil@cryer.us>
# Site : http://github.com/philcryer/lipsync
# Desc : This script sets up the lipsync service

clear
stty erase '^?'
echo "lipsync setup script"


###############################################################################
# Check if the user is root, or if they have user has sudo privileges
###############################################################################
echo -n "* Checking that user is root or has sudo access..."
if [ "$(id -u)" != "0" ]; then 
	sudo -v >/dev/null 2>&1 || { echo; echo "	ERROR: User $(whoami) is not root, and does not have sudo privileges" ; exit 1; }
else
	echo "ok"
fi
###############################################################################


###############################################################################
# Checking if this system is either Debian or Ubuntu
###############################################################################
echo -n "* Checking if the installer supports this system..."
if [ `cat /etc/issue.net | cut -d' ' -f1` == "Debian" ] || [ `cat /etc/issue.net | cut -d' ' -f1` == "Ubuntu" ];then
	echo "ok"
else
	echo; echo "	ERROR: this installer currently does not support your system,"
	echo       "	but you can try, it could work (tm) - let us know if it does"
fi
###############################################################################


###############################################################################
# Test if required applications are installed, die if not
###############################################################################
echo -n "* Checking that required software is installed..."
type -P ssh &>/dev/null || { echo; echo "	ERROR: lipsync requires ssh-client but it's not installed" >&2; exit 1; }
type -P ssh-copy-id &>/dev/null || { echo; echo "	ERROR: lipsync requires ssh-copy-id but it's not installed" >&2; exit 1; }
type -P rsync &>/dev/null || { echo; echo "	ERROR: lipsync requires rsync but it's not installed" >&2; exit 1; }
type -P lsyncd &>/dev/null || { echo; echo "	ERROR: lipsync requires lsyncd but it's not installed" >&2; exit 1; }
type -P unison &>/dev/null || { echo; echo "	ERROR: lipsync requires unison but it's not installed" >&2; exit 1; }
echo "ok"
###############################################################################


###############################################################################
# Define functions
###############################################################################
questions(){
	echo -n "	- IP or domainname for server: "
	read remote_server

	echo -n "	- SSH port on server (default is 22): "
	read port
	if [ -z "$port" ]
	then
	  port="22"
	fi
	
	echo -n "	- username (must exist on the client and server): "
    	read username
    
	echo -n "	- local directory to be synced (default is /home/$username/sync): "
	read lipsync_dir_local
	if [ -z "$lipsync_dir_local" ]
	then
	  lipsync_dir_local="/home/$username/sync"
	fi

	echo -n "	- remote directory to be synced (default is /home/$username/sync): "
	read lipsync_dir_remote
	if [ -z "$lipsync_dir_remote" ]
	then
	  lipsync_dir_remote="/home/$username/sync"
	fi
}

ssh.keygen(){
	if [ -f '/home/${username}/.ssh/id_dsa' ]; then
		echo "* Existing SSH key found for ${username} backing up..."
		mv /home/${username}/.ssh/id_dsa /home/${username}/.ssh/id_dsa-OLD
		if [ $? -eq 0 ]; then
			echo "done"
		else
			echo; echo "	ERROR: there was an error backing up the SSH key"; exit 1
		fi
	fi
	echo -n "* Creating new SSH key for ${username}..."
	ssh-keygen -q -N '' -f /home/${username}/.ssh/id_dsa
	if [ $? -eq 0 ]; then
		chown -R $username:$username /home/${username}/.ssh
		echo "done"
	else
		echo; echo "	ERROR: there was an error generating the ssh key"; exit 1
	fi
	
	echo "* Transferring ssh key for ${username} to ${remote_server} on port ${port} (login as $username now)..."; 
	#echo -n "	NOTE: you will be prompted to login..."
	#su ${username} -c "ssh-copy-id ${remote_server}" >> /dev/null

	# ssh-copy-id -i  id_rsa.pub terry@host2
	su ${username} -c "ssh-copy-id -i /home/${username}/.ssh/id_dsa.pub '-p ${port} ${username}@${remote_server}'" >> /dev/null

	# ssh-copy-id ${remote_server}
	if [ $? -eq 0 ]; then
		X=0	#echo "done"
	else
		echo; echo "	ERROR: there was an error transferring the ssh key"; exit 1
	fi
	echo -n "* Setting permissions on the ssh key for ${username} on ${remote_server} on port ${port}..."; 
	#echo -n "	NOTE: you should not be prompted to login..."
	su ${username} -c "SSH_AUTH_SOCK=0 ssh ${remote_server} -p ${port} 'chmod 700 .ssh'"
	#ssh ${remote_server} 'chmod 700 .ssh'
	if [ $? -eq 0 ]; then
		echo "done"
	else
		echo; echo "	ERROR: there was an error setting permissions on the ssh key for ${username} on ${remote_server} on port ${port}..."; exit 1
	fi
}

create.group(){
	echo -n "* Creating group lipsync..."
	grep lipsync /etc/group >>/dev/null
	if [ $? -eq 0 ]; then
		echo; echo "	NOTICE: existing group lipsync found, not creating"
	else
		groupadd lipsync
		echo "done"
	fi
}

create.user(){
	echo -n "* Creating user lipsync..."
	grep lipsync /etc/passwd
	if [ $? -eq 0 ]; then
		echo; echo "	NOTICE: existing user lipsync found, not creating"
	else
		useradd -g lipsync -s /bin/false lipsync
		echo "done"
	fi
}

build.conf(){
	echo -n "* Creating lipsyncd.conf.xml for ${username}..."
	sed 's|LSLOCDIR|'$lipsync_dir_local/'|g' etc/lipsyncd.conf.xml > /tmp/lipsyncd.conf.xml.01
	sed 's|LSUSER|'$username'|g' /tmp/lipsyncd.conf.xml.01 > /tmp/lipsyncd.conf.xml.02
	sed 's|LPORT|'$port'|g' /tmp/lipsyncd.conf.xml.02 > /tmp/lipsyncd.conf.xml.03
	sed 's|LSREMSERV|'$remote_server'|g' /tmp/lipsyncd.conf.xml.03 > /tmp/lipsyncd.conf.xml.04
	sed 's|LSREMDIR|'$lipsync_dir_remote'|g' /tmp/lipsyncd.conf.xml.04 > /tmp/lipsyncd.conf.xml
	echo "done"
}

deploy(){
	#echo -n "* Enabling lipsync for $username..."
	#touch /home/$username/.lipsyncd; chown $username:$username /home/$username/.lipsyncd
	#echo "done"
	echo -n "* Adding new lipsync user to lipsync group..."
	adduser $username lipsync >> /dev/null
	echo "done"
########################
	echo "* Deploying lipsync..."
	echo -n "	> installing /usr/bin/lipsync..."
	cp usr/bin/lipsync /usr/bin; chown root:root /usr/bin/lipsync; chmod 755 /usr/bin/lipsync
	echo "done"
########################
	echo -n "	> installing /usr/bin/lipsyncd..."
	cp usr/bin/lipsyncd /usr/bin; chown root:root /usr/bin/lipsyncd; chmod 755 /usr/bin/lipsyncd
	echo "done"
########################
	echo -n "	> installing /etc/init.d/lipsyncd..."
	sed 's|LSUSER|'$username'|g' etc/init.d/lipsyncd > /etc/init.d/lipsyncd; chown root:root /etc/init.d/lipsyncd; chmod 755 /etc/init.d/lipsyncd
	echo "done"
########################
	echo -n "	> installing /etc/cron.d/lipsync..."
	sed 's|LSUSER|'$username'|g' etc/cron.d/lipsync > /etc/cron.d/lipsync
	#sed 's|PORT|'$port'|g' /tmp/lipsync.01 > /tmp/lipsync.02
	#sed 's|LSLOCDIR|'$lipsync_dir_local'|g' /tmp/lipsync.01 > /tmp/lipsync.02
	#sed 's|LSREMDIR|'$lipsync_dir_remote'|g' /tmp/lipsync.02 > /tmp/lipsync.03
	#sed 's|LSREMSERV|'$remote_server'|g' /tmp/lipsync.03 > /etc/cron.d/lipsync
	#rm /tmp/lipsync.*
	echo "done"
########################
	echo -n "	> installing /etc/lipsyncd.conf.xml..."
	mv /tmp/lipsyncd.conf.xml /etc
	rm /tmp/lipsyncd.conf.*
	echo "done"
########################
	echo -n "	> installing docs /usr/share/doc/lipsync..."
	mkdir /usr/share/doc/lipsync
	cp README* INSTALL* LICENSE /usr/share/doc/lipsync
	echo "done"
########################
	echo -n "	> preparing logfile /var/log/lipsyncd.log..."
	touch /var/log/lipsyncd.log
#	chmod 640 /var/log/lipsyncd.log
	chmod g+w /var/log/lipsyncd.log
	chown lipsync:lipsync /var/log/lipsyncd.log
	echo "done"
########################
	echo -n "	> enabling unison for $username..."
	sed 's|LSLOCDIR|'$lipsync_dir_local/'|g' unison/lipsync.prf > /tmp/lipsync.prf.01
	sed 's|LSUSER|'${username}'|g' /tmp/lipsync.prf.01 > /tmp/lipsync.prf.02
	sed 's|LSREMDIR|'$lipsync_dir_remote'|g' /tmp/lipsync.prf.02 > /tmp/lipsync.prf.03
	sed 's|LPORT|'$port'|g' /tmp/lipsync.prf.03 > /tmp/lipsync.prf.04
	sed 's|LSREMSERV|'$remote_server'|g' /tmp/lipsync.prf.04 > /tmp/lipsync.prf
	if [ ! -d "/home/${username}/.unison" ]; then
		mkdir /home/${username}/.unison
	else
		mv /home/${username}/.unison /home/${username}/.unison-old
		mkdir /home/${username}/.unison
	fi
	cp /tmp/lipsync.prf /home/${username}/.unison/
	chown -R ${username}:${username} /home/${username}/.unison/
	rm /tmp/lipsync.*
	echo "done"
########################
	echo "lipsync installed `date`" > /var/log/lipsyncd.log
}

uninstall(){
	echo -n "	NOTICE: stopping lipsync service..."
	/etc/init.d/lipsyncd stop >> /dev/null 
	echo "done"
	
	echo -n "	NOTICE: disabling lipsync for user..."
	rm -f /home/$username/.unison
	echo "done"

	echo -n "	NOTICE: removing lipsync user and group..."
	userdel lipsync
	groupdel lipsync
	echo "done"

	echo -n " 	NOTICE: removing lipsync files..."
	rm -rf /etc/init.d/lipsyncd
	rm -rf /etc/lipsyncd.conf.xml
	rm -rf /usr/bin/lipsync*
	rm -rf /var/log/lipsync*
	rm -rf /usr/share/doc/lipsync
	echo "done"
}
###############################################################################


###############################################################################
# Install or uninstall the lipsync service
###############################################################################
if [ "${1}" = "uninstall" ]; then
	echo "	ALERT: Uninstall option chosen, all lipsync files and configuration will be purged!"
	echo -n "	ALERT: To continue press enter to continue, otherwise hit ctrl-c now to bail..."
	read continue
	uninstall
	exit 0
else
	questions
	ssh.keygen
	create.group
	create.user
	build.conf
	deploy
fi
###############################################################################


###############################################################################
# Startup lipsync and exit
###############################################################################
#echo -n "lipsync setup complete, starting lipsync..."
echo "lipsync setup complete, starting lipsync..."
/etc/init.d/lipsyncd start
#	echo "done"
if [ -f /var/run/lipsyncd.pid ]; then
	echo "	NOTICE: lipsyncd is running as pid `cat /var/run/lipsyncd.pid`"
	echo "	Check /var/log/lipsyncd.log for details"
else
	echo "	NOTICE: lipsyncd failed to start..."
	echo "	Check /var/log/lipsyncd.log for details"
fi
###############################################################################

exit 0
