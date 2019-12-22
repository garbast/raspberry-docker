loadkeys de

add-apt-repository ppa:ubuntu-raspi2/ppa
sed -i '' 's/eoan/bionic/' /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-eoan.list
mv /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-eoan.list /etc/apt/sources.list.d/ubuntu-raspi2-ubuntu-ppa-bionic.list
apt install libraspberrypi-bin git

apt install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb https://download.docker.com/linux/ubuntu disco stable"
apt install docker-ce

apt install libffi-dev libssl-dev
apt install -y python python-pip
apt remove python-configparser
pip install docker-compose

