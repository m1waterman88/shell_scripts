#!/bin/bash

########################################################################################
# Helper script to install packages and setup some configs for a fresh Debian-based OS
#
# This isn't ready to be straight-up run. There are dependency issues that need to be
# addressed... when I wanna. For now, having the commands at-the-ready is still
# beneficial.
########################################################################################

# Prevent multiple executions: check if the build script was run previously.
if [ -f /opt/$USER/no_repeat.txt ]; then
	exit
fi

# Report the start time to a logfile.
echo $(date -u)": System provisioning started." >> /opt/$USER/build_workstation.log

# apt helper functions - https://github.com/vultr/vultr-marketplace/blob/main/helper-scripts/vultr-helper.sh
function wait_on_apt_lock() {
	until ! lsof -t /var/cache/apt/archives/lock /var/lib/apt/lists/lock /var/lib/dpkg/lock >/dev/null 2>&1
	do
		echo "Waiting 3 for apt lock currently held by another process."
		sleep 3
	done
}

function apt_safe() {
	wait_on_apt_lock
	sudo apt install -y "$@"
}

function apt_update_safe() {
	wait_on_apt_lock
	sudo apt update -y
}

function apt_upgrade_safe() {
	wait_on_apt_lock
	DEBIAN_FRONTEND=noninteractive apt upgrade -y
}

function apt_clean_safe() {
	wait_on_apt_lock
	sudo apt autoremove -y

	wait_on_apt_lock
	sudo apt autoclean -y
}

function update_and_clean_packages() {
	apt_update_safe
	apt_upgrade_safe
	apt_clean_safe
}

BASE_DIR=~/src/settings

# Change the hostname to "vultr-" followed by the last five chars of the machine's SN
hostnamectl set-hostname "vultr-nhql3"

# profile, bashrc, and bash_aliases additions/changes
cat .profile >> ~/.profile
# TODO: sed for bashrc (PS1)
cat .bash_aliases > ~/.bash_aliases
. ~/.profile

# ssh prep
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# apt - General
update_and_clean_packages
apt_safe \
	apt-transport-https \
	ca-certificates \
	curl \
	flameshot \
	git \
	gnupg \
	gpg \
	htop \
	ipcalc \
	jq \
	lsb-release \
	mysql-client-8.0 \
	nmap \
	peek \
	python3-pip \
	vim \
	wget \
	wireshark \
	whois

# Source /etc/os-release to get os-release values in variables
. /etc/os-release

if [ $ID == 'pop' ]; then
	# flatpak is installed by default
	flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
	flatpak update -y

	FLATPACK_PACKAGES=(
		com.jgraph.drawio.desktop
		org.signal.Signal
	)

	for PACKAGE in ${FLATPACK_PACKAGES[@]}; do
		flatpak install -y $PACKAGE
	done

	flatpak uninstall --unused -y
else if [ $ID == 'ubuntu' ]; then
	# Snap is installed by default
	sudo snap refresh
	sudo snap install \
		drawio \
		signal-desktop

	cp $BASE_DIR/shell_scripts/remove_disabled_snaps ~/bin/shell_scripts/remove_disabled_snaps
else
	echo "WARNING: Unknown operating system: $ID. pop or ubuntu expected."
fi

# Firewall: enable and allow for Xdebug to pass through via docker-local
sudo ufw enable
sudo ufw allow from 172.16.0.2 to any port 9003

# VPN
# TODO: Update VPN information when directions are more mature: https://vultr.atlassian.net/wiki/spaces/CORPIT/pages/58064905/Global+Protect+VPN+on+Ubuntu+Linux
apt_update_safe
apt_safe libqt5webkit5
cp $BASE_DIR/shell_scripts/vultr_vpn ~/bin/shell_scripts/vultr_vpn

# git
git config --global user.name "Michael Waterman"
git config --global user.email "$USER@vultr.com"
git config --global pull.rebase true
git config --global core.editor vim

mkdir -p ~/src/git/hooks
cp $BASE_DIR/prepare-commit-msg ~/src/git/hooks
git config --global core.hooksPath /home/$USER/src/git/hooks
chmod 764 ~/src/git/hooks/prepare-commit-msg

# PHP
PHP_VERSION="php8.1"
apt_update_safe
apt_safe \
	$PHP_VERSION \
	$PHP_VERSION-cli \
	$PHP_VERSION-common \
	$PHP_VERSION-curl \
	$PHP_VERSION-gmp \
	$PHP_VERSION-mbstring \
	$PHP_VERSION-mysql \
	$PHP_VERSION-xml

# Composer - https://getcomposer.org/doc/faqs/how-to-install-composer-programmatically.md
EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
	>&2 echo 'ERROR: Invalid installer checksum'
else
	php composer-setup.php --quiet
	sudo mv composer.phar /usr/local/bin/composer
fi

rm composer-setup.php
composer global require "squizlabs/php_codesniffer=*"

# PHPUnit since some projects require the local binary
composer global require --dev phpunit/phpunit

# Docker and Docker Compose - https://docs.docker.com/engine/install/#server
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt_update_safe
apt_safe \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-compose-plugin

# Grant your user access to Docker so root isn't required - https://docs.docker.com/engine/install/linux-postinstall/
sudo groupadd docker
sudo usermod -aG docker $USER

# Brave browser - https://brave.com/linux/
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main"|sudo tee /etc/apt/sources.list.d/brave-browser-release.list
apt_update_safe
apt_safe brave-browser

# Mattermost - https://docs.mattermost.com/install/desktop-app-install.html
curl -o- https://deb.packages.mattermost.com/setup-repo.sh | sudo bash
apt_update_safe
apt_safe mattermost-desktop

# VSCode - https://code.visualstudio.com/docs/setup/linux
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg
apt_update_safe
apt_safe code

# Python
python3 -m pip install pydocstyle pipdeptree Jinja2 --user

# DBeaver - https://dbeaver.io/download/
sudo  wget -O /usr/share/keyrings/dbeaver.gpg.key https://dbeaver.io/debs/dbeaver.gpg.key
echo "deb [signed-by=/usr/share/keyrings/dbeaver.gpg.key] https://dbeaver.io/debs/dbeaver-ce /" | sudo tee /etc/apt/sources.list.d/dbeaver.list
apt_update_safe
apt_safe dbeaver-ce

# Teleport - https://goteleport.com/docs/installation/#linux
sudo curl https://apt.releases.teleport.dev/gpg \
  -o /usr/share/keyrings/teleport-archive-keyring.asc

# Need to update manually for each major release
TELEPORT_VERSION='v15'

# Uses source /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.asc] \
  https://apt.releases.teleport.dev/${ID?} ${VERSION_CODENAME?} stable/$TELEPORT_VERSION" \
| sudo tee /etc/apt/sources.list.d/teleport.list > /dev/null
apt_update_safe
apt_safe teleport

# Add a script that uses Teleport
cp $BASE_DIR/shell_scripts/sync_mirrors ~/bin/shell_scripts/sync_mirrors

# Joplin - Create an install/update script and then install
mkdir ~/.joplin
echo "wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash" > ~/.joplin/update_joplin
chmod 744 ~/.joplin/update_joplin
.joplin/update_joplin

# Ubuntu 22.04 comes with libfuse3, but AppImages (like Joplin) need libfuse2 to open
if [ $ID == 'ubuntu' ]; then
	apt_safe libfuse2
fi

# Spotify - https://www.spotify.com/us/download/linux/
curl -sS https://download.spotify.com/debian/pubkey_5E3C45D7B312C643.gpg | sudo apt-key add -
echo "deb [arch=amd64] http://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
apt_update_safe
apt_safe spotify-client

# Zoom - https://zoom.us/download?os=linux
curl -O https://zoom.us/client/latest/zoom_amd64.deb
apt_update_safe
apt_safe ./zoom_amd64.deb
rm zoom_amd64.deb

# Center newly launched windows
gsettings set org.gnome.mutter center-new-windows true

# The apache service will interfere with the local development environment
sudo systemctl disable apache2 --now

# No need for printing
sudo systemctl disable cups --now

# Create a file to check against later to prevent multiple executions.
echo "This file is used to check if the build script has been run to prevent multiple executions" > /opt/$USER/no_repeat.txt

# Report the end time to a logfile.
echo $(date -u)": System provisioning script is complete." >> /opt/$USER/build_workstation.log
