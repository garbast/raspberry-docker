#!/bin/bash

RASPBERRY_IP="192.168.20.40"

# add repository for raspbian packages
function create_raspbian_sourcelistfile() {
  local folder=$1

  cat <<EOT >> ${folder}/writable/etc/apt/sources.list.d/raspbian-buster.list
	deb [arch=armhf] http://raspbian.raspberrypi.org/raspbian/ buster main contrib non-free rpi
	# Uncomment line below then 'apt-get update' to enable 'apt-get source'
	#deb-src [arch=armhf] http://raspbian.raspberrypi.org/raspbian/ buster main contrib non-free rpi
EOT
  echo "[ Add raspbian-buster repository"
}

# add modules for usb-tether
function config_modules() {
  local folder=$1

  echo "dtoverlay=dwc2" >> ${folder}/system-boot/usercfg.txt
  echo "dwc2" > ${folder}/writable/etc/modules-load.d/dwc2.conf
  echo "libcomposite" > ${folder}/writable/etc/modules-load.d/libcomposite.conf
  echo "g_ether" > ${folder}/writable/etc/modules-load.d/g_ether.conf
  echo "usb_f_ecm" > ${folder}/writable/etc/modules-load.d/usb_f_ecm.conf
  echo "[ Kernel modules configured"
}

# needed to be able to connect via network
# change 60-netcfg.yaml before running this script
function copy_network_configuration() {
  local folder=$1

  cp ./Setup/Configuration/60-netcfg.yaml ${folder}/writable/etc/netplan/
  echo "[ Network configuration copied to '${folder}/writable/etc/netplan/'"
}

function create_filemount() {
  echo -n 'Do you want to use nfs or samba? [N,s] '
  read -n1 type

  if [[ ${type} == 's' || ${type} == 'S' ]]; then
    create_samba_filemount
  else
    create_nfs_filemount
  fi
}

function create_samba_filemount() {
  local user=$(who am i | awk '{print $1}')
  local home_dir=$( getent passwd "${user}" | cut -d: -f6 )
  local credentials_file="${home_dir}/.smbraspberrypi"
  local mount_dir='/media/raspberrypi'

  mkdir -p ${mount_dir}
  chgrp users ${mount_dir}

  apt install cifs-utils

  echo 'The following password should be set via passwd on the Raspberry Pi.'
  echo -n 'Please enter the password for the file mount of the Raspberry Pi: '
  read password

  touch ${credentials_file}
  echo 'username=ubuntu' > ${credentials_file}
  echo "password=${password}" >> ${credentials_file}
  chmod 600 ${credentials_file}

  mount -t cifs -o credentials=${credentials_file} //${RASPBERRY_IP}/ubuntu ${mount_dir}
  echo "//${RASPBERRY_IP}/ubuntu ${mount_dir} cifs credentials=${credentials_file},user,noperm,noauto,_netdev 0 0" >> /etc/fstab
  echo "[ Samba mount configured"
}

function create_nfs_filemount() {
  local user=$(who am i | awk '{print $1}')
  local home_dir=$( getent passwd "${user}" | cut -d: -f6 )
  local mount_dir='/media/raspberrypi'

  mkdir -p ${mount_dir}
  chgrp users ${mount_dir}

  apt install nfs-common

  mount -t nfs //${RASPBERRY_IP}:/ubuntu ${mount_dir}
  echo "${RASPBERRY_IP}:/home ${mount_dir} nfs noauto,user,rw 0 0" >> /etc/fstab
  echo "[ NFS mount configured"
}

function activate_ssh() {
  local folder=$1

  touch ${folder}/system-boot/ssh
  echo "[ Activate sshd"
}

function main() {
  local currentFolder="/media/$(logname)"
  echo -n "Folder with mounted microsd card (/media/[username]) without slash followed or leave empty for default (${currentFolder}) and [ENTER]: "
  read folder
  if [[ -z ${folder} ]]; then
    folder=${currentFolder}
  fi

  #create_raspbian_sourcelistfile ${folder}
  config_modules ${folder}
  copy_network_configuration ${folder}
  create_filemount
  activate_ssh ${folder}
}
main
