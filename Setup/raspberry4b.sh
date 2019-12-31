#!/bin/bash

readonly BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." > /dev/null 2>&1 && pwd )"

function configure_locale() {
  loadkeys de
  echo 'Set keyboard to de for umlauts and special characters'

  rm /etc/localtime
  ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime
  echo 'Set timezone to Europe/Berlin'
  timedatectl

  locale-gen de_DE.UTF-8
  update-locale
}

function add_missing_repository_keys() {
  curl -fsSL http://archive.raspbian.org/raspbian.public.key | apt-key add -

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 871920D1991BC93C

  dpkg --add-architecture armhf
  apt update
}

function install_raspberry_components() {
  apt install rpi-eeprom rpi-eeprom-image

  add-apt-repository ppa:ubuntu-raspi2/ppa
  sed -i '' 's/eoan/bionic/' /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-eoan.list
  mv /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-eoan.list /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-bionic.list
  apt install libraspberrypi-bin

  cp "${BASE_DIR}/Setup/Configuration/otg-network-tether.service" /lib/systemd/system/
  cp "${BASE_DIR}/Setup/Configuration/otg-network-tether" /usr/bin/
  chmod 755 /usr/bin/otg-network-tether
  systemctl enable --now otg-network-tether.service
}

function install_zsh() {
  apt install zsh
  chsh -s /usr/bin/zsh ubuntu

  echo 'Run ./Setup/ohmyz.sh without sudo afterwards'
}

function install_git() {
  apt install git git-flow
}

function install_dnsmasq() {
  systemctl stop systemd-resolved
  systemctl disable systemd-resolved
  systemctl mask systemd-resolved

  rm -v /etc/resolv.conf
  cp "${BASE_DIR}/Setup/Configuration/resolv.conf" /etc/

  apt install dhcpcd5
  echo 'denyinterfaces usb0' >> /etc/dhcpcd.conf

  apt install dnsmasq
  cp "${BASE_DIR}/Setup/Configuration/dnsmasq" /etc/dnsmasq.d/
  systemctl restart dnsmasq
}

function install_docker() {
  cat <<EOT >> /etc/apt/sources.list.d/docker-ubuntu-disco.list
	deb https://download.docker.com/linux/ubuntu disco stable
	# deb-src https://download.docker.com/linux/ubuntu disco stable
EOT

  apt update
  apt install apt-transport-https ca-certificates curl software-properties-common
  apt install docker-ce

  usermod -aG docker ubuntu
  usermod -aG www-data ubuntu
}

function install_docker_compose() {
  apt update
  apt install libffi-dev libssl-dev
  apt install -y python python-pip python-dev
  apt remove python-configparser
  pip install docker-compose
}

function install_samba() {
  apt install samba-common samba
  cp "${BASE_DIR}/Setup/Configuration/smb.conf" /etc/samba/
  systemctl restart smbd
  smbpasswd -a ubuntu
}

function install_nfs() {
  apt install nfs-kernel-server
  cp "${BASE_DIR}/Setup/Configuration/exports" /etc/
  exportfs -a
  systemctl restart nfs-kernel-server
}

function add_composer_alias() {
  echo "alias composer='[ -d ~/.composer ] || mkdir ~/.composer; docker run --rm --interactive --tty -u 1000:33 -v `pwd`:/app -v ~/.composer:/tmp/.composer -e COMPOSER_HOME=/tmp/.composer composer --ignore-platform-reqs'" >> '/home/ubuntu/.bashrc'
}

function set_permissions() {
  local project_folder="${BASE_DIR}/Projects/"

  chgrp -R www-data ${project_folder}
  find ${project_folder} -type d -exec chmod 2775 {} \;
  find ${project_folder} -type f -exec chmod 0664 {} \;
}

function main() {
  configure_locale
  add_missing_repository_keys
  install_raspberry_components
  install_zsh
  install_git
  install_dnsmasq
  install_docker
  install_docker_compose
  install_samba
  install_nfs
  add_composer_alias
  set_permissions
}
main
