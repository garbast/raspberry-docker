# WORK IN PROGRESS

USB tether is not working by now so WIFI connect is needed until this is solved. https://www.reddit.com/r/raspberry_pi/comments/edsf7q/ubuntu_server_on_raspberry_pi4b_and_two_problems/

Resolve does not get IPs on my machine

- not working nslookup php73.dev.local
- working nslookup php73.dev.local 192.168.20.40

That's why i add the domains to the /etc/hosts file on my machine

## Development environment

The environment contains the following packages

- PHP 7.2 - php:7.2-fpm-alpine
- PHP 7.3 - php:7.3-fpm-alpine
- MariaDB - mariadb:10.4
- Apache2.4 - httpd:2.4-alpine

Concrete configuration you can find in the Dockerfiles and docker-compose.yml

## Getting started

- first write the Ubuntu Server image to the microsd-card (https://ubuntu.com/download/raspberry-pi) with Balena Edger (https://www.balena.io/etcher/)
- eject and reinsert the card
- then clone this repository and change into the folder
- modify the MariaDB root password in docker-compose.yml
- modify the WIFI settings in ./Setup/Configuration/60-netcfg.yaml
- run and follow the questions ./Setup/workstation.sh
- insert the card in the raspberry and start it up
- connect to the Raspberry PI via ssh
- clone the repository in /home/ubuntu and change into the folder
- run ./Setup/raspberry4b.sh
- IF you have an Argon One Case run ./Setup/argon1.sh to install control scripts
- run docker-compose up -d

## After installation

| Folder      | Description                                                                                                                                   |
|-------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| ./Databases | contains the databases for the individual projects                                                                                            |
| ./Logs      | contains the accumulated log files                                                                                                            |
| ./Projects  | contains example vhosts and could contain your projects.Important is, that the vhost always point to the public folder inside of the project. | 

## Create new project

Use the script ./Setup/create_project.sh [your_project_name]

Afterwards the project is available via http://**your_project_name**.dev.local/ or via ssh
the folder ./Projects/**your_project_name**
