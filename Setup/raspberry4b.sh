#!/bin/bash

readonly BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." > /dev/null 2>&1 && pwd )"

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

  cp "${BASE_DIR}/Setup/Configuration/usb.sh" /root/
  chmod 755 /root/usb.sh
}

function install_dnsmasq() {
  systemctl stop systemd-resolved
  systemctl disable systemd-resolved
  systemctl mask systemd-resolved

  rm -v /etc/resolv.conf
  cp "${BASE_DIR}/Setup/Configuration/resolv.conf" /etc/

  apt install git dhcpcd5
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
}

function add_composer_alias() {
  echo "alias composer='[ -d ~/.composer ] || mkdir ~/.composer; docker run --rm --interactive --tty -u $UID -v `pwd`:/app -v ~/.composer:/tmp/.composer -e COMPOSER_HOME=/tmp/.composer composer --ignore-platform-reqs'" >> '/home/ubuntu/.bashrc'
}

function set_access_rights() {
  chmod -R 2775 "${BASE_DIR}/Projects/"
  chgrp -R 66 "${BASE_DIR}/Projects/"
}

function main() {
  loadkeys de

  add_missing_repository_keys
  install_raspberry_components
  install_dnsmasq
  install_docker
  install_docker_compose
  install_samba
  add_composer_alias
  set_access_rights
}
main
