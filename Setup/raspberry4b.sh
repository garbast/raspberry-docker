#!/bin/bash

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

  cp ./Setup/Configuration/usb.sh /root/
  chmod 755 /root/usb.sh
}

function install_dnsmasq() {
  systemctl stop systemd-resolved
  systemctl disable systemd-resolved
  systemctl mask systemd-resolved

  rm -v /etc/resolv.conf
  cp ./Setup/Configuration/resolv.conf /etc/

  apt install git dhcpcd5
  echo 'denyinterfaces usb0' >> /etc/dhcpcd.conf

  apt install dnsmasq
  cp ./Setup/Configuration/dnsmasq /etc/dnsmasq.d/
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

function add_composer_alias() {
  echo "alias composer='[ -d ~/.composer ] || mkdir ~/.composer; docker run --rm --interactive --tty -u $UID -v `pwd`:/app -v ~/.composer:/tmp/.composer -e COMPOSER_HOME=/tmp/.composer composer --ignore-platform-reqs'" >> '/home/ubuntu/.bashrc'
}

function main() {
  loadkeys de

  add_missing_repository_keys
  install_raspberry_components
  install_dnsmasq
  install_docker
  install_docker_compose
  add_composer_alias
}
main
