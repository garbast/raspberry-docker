#!/bin/bash

echo "Folder with mounted microsd card (/media/[username]) without slash followed and [ENTER]:"
read FOLDER

# add repository for raspbian packages
cat <<EOT >> $FOLDER/writable/etc/apt/sources.list.d/raspbian-buster.list

deb [arch=armhf] http://raspbian.raspberrypi.org/raspbian/ buster main contrib non-free rpi
# Uncomment line below then 'apt-get update' to enable 'apt-get source'
#deb-src [arch=armhf] http://raspbian.raspberrypi.org/raspbian/ buster main contrib non-free rpi
EOT

# add config for usb-tether
echo "dtoverlay=dwc2" >> $FOLDER/system-boot/usercfg.txt
echo "dwc2" > $FOLDER/writable/etc/modules-load.d/dwc2.conf
echo "libcomposite" > $FOLDER/writable/etc/modules-load.d/libcomposite.conf
echo "g_ether" > $FOLDER/writable/etc/modules-load.d/g_ether.conf
echo "usb_f_ecm" > $FOLDER/writable/etc/modules-load.d/usb_f_ecm.conf

cp ./Setup/Configuration/60-netcfg.yaml $FOLDER/writable/etc/netplan/
