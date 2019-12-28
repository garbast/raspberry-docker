#!/bin/bash
loadkeys de

wget http://archive.raspbian.org/raspbian.public.key -O - | apt-key add -
dpkg --add-architecture armhf
apt update
apt install rpi-eeprom rpi-eeprom-image

apt install git dhcpcd5
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3B4FE6ACC0B21F32
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 871920D1991BC93C

add-apt-repository ppa:ubuntu-raspi2/ppa
sed -i '' 's/eoan/bionic/' /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-eoan.list
mv /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-eoan.list /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-bionic.list
apt install libraspberrypi-bin

cp ./Setup/Configuration/usb.sh /root/
chmod 755 /root/usb.sh

systemctl stop systemd-resolved
systemctl disable systemd-resolved
rm -v /etc/resolv.conf
cp ./Setup/Configuration/resolv.conf /etc/
apt install dnsmasq
cp ./Setup/Configuration/dnsmasq /etc/dnsmasq.d/
echo "denyinterfaces usb0" >> /etc/dhcpcd.conf
systemctl restart dnsmasq

apt update
apt install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
cat <<EOT >> /etc/apt/sources.list.d/docker-ubuntu-disco.list
deb https://download.docker.com/linux/ubuntu disco stable
# deb-src https://download.docker.com/linux/ubuntu disco stable
EOT

apt install docker-ce
usermod -aG docker ubuntu

echo "alias composer='docker run --rm --interactive --tty -u '$UID' -v `pwd`:/app composer --ignore-platform-reqs'" >> '/home/ubuntu/.bashrc'

apt install libffi-dev libssl-dev
apt install -y python python-pip python-dev
apt remove python-configparser
pip install docker-compose

bash ./Setup/argon1.sh
