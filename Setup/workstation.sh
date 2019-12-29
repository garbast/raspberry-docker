#!/bin/bash

# add repository for raspbian packages
function create_raspbian_sourcelistfile() {
  local folder=$1

  cat <<EOT >> ${folder}/writable/etc/apt/sources.list.d/raspbian-buster.list
	deb [arch=armhf] http://raspbian.raspberrypi.org/raspbian/ buster main contrib non-free rpi
	# Uncomment line below then 'apt-get update' to enable 'apt-get source'
	#deb-src [arch=armhf] http://raspbian.raspberrypi.org/raspbian/ buster main contrib non-free rpi
EOT
}

# add modules for usb-tether
function config_modules() {
  local folder=$1

  echo "dtoverlay=dwc2" >> ${folder}/system-boot/usercfg.txt
  echo "dwc2" > ${folder}/writable/etc/modules-load.d/dwc2.conf
  echo "libcomposite" > ${folder}/writable/etc/modules-load.d/libcomposite.conf
  echo "g_ether" > ${folder}/writable/etc/modules-load.d/g_ether.conf
  echo "usb_f_ecm" > ${folder}/writable/etc/modules-load.d/usb_f_ecm.conf
}

function copy_network_configuration() {
  local folder=$1

  cp ./Setup/Configuration/60-netcfg.yaml ${folder}/writable/etc/netplan/
}

function main() {
  echo -n "Folder with mounted microsd card (/media/[username]) without slash followed and [ENTER]: "
  read folder

  create_raspbian_sourcelistfile ${folder}
  config_modules ${folder}
  copy_network_configuration ${folder}
}
main
