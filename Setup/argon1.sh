#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run with sudo"
  exit 1
fi

readonly USERNAME="ubuntu"
readonly DAEMONNAME="argononed"

function argon::create_file() {
  local file=$1
  local accessmask=$2
  if [[ -f ${file} ]]; then
    rm ${file}
  fi
  touch ${file}
  chmod ${accessmask} ${file}
}

function argon::check_pkg() {
  local package_name=$1
  result=$(dpkg-query -W -f='${Status}\n' "${package_name}" 2> /dev/null | grep "installed")
  [[ "${result}" != "" ]] && echo "ok"
  false
}

function argon::install_required_packages() {
  # package_list=(raspi-gpio python-rpi.gpio python3-rpi.gpio python-smbus python3-smbus i2c-tools)
  local package_list=(python-rpi.gpio python3-rpi.gpio python3-smbus i2c-tools)
  pip install RPi.GPIO
  pip install smbus
  for package_name in ${package_list[@]}; do
    apt-get install -y ${package_name}
    if [[ ! $(argon::check_pkg ${package_name}) ]]; then
      cat <<-EOT
			********************************************************************
			Please also connect device to the internet and restart installation.
			********************************************************************
EOT
      exit
    fi
  done
}

function argon::change_raspi_config() {
  raspi-config nonint do_i2c 0
  raspi-config nonint do_serial 0
}

function argon::create_daemonconfig_file() {
  local daemonconfigfile=$1
  if [[ ! -f ${daemonconfigfile} ]]; then
    # config file for fan speed
    argon::create_file ${daemonconfigfile} 666

    cat <<-EOT > ${daemonconfigfile}
		#
		# Argon One Fan Configuration
		#
		# List below the temperature (Celsius) and fan speed (in percent) pairs
		# Use the following form:
		# min.temperature=speed
		#
		# Example:
		# 55=10
		# 60=55
		# 65=100
		#
		# Above example sets the fan speed to
		#
		# NOTE: Lines beginning with # are ignored
		#
		# Type the following at the command line for changes to take effect:
		# sudo systemctl restart ${DAEMONNAME}.service
		#
		# Start below:
		55=10
		60=55
		65=100
EOT
  fi
}

# Generate script that runs every shutdown event
function argon::create_shutdown_script() {
  local shutdownscript=$1
  argon::create_file ${shutdownscript} 755

  cat <<-EOT > ${shutdownscript}
		#!/usr/bin/python
		import sys
		import smbus
		import RPi.GPIO as GPIO

		rev = GPIO.RPI_REVISION
		if rev == 2 or rev == 3:
		    bus = smbus.SMBus(1)
		else:
		    bus = smbus.SMBus(0)

		if len(sys.argv)>1:
		    bus.write_byte(0x1a,0)
		    if sys.argv[1] == "poweroff" or sys.argv[1] == "halt":
		        try:
		            bus.write_byte(0x1a,0xFF)
		        except:
		            rev=0"
EOT
}

# Generate script to monitor shutdown button
function argon::create_powerbutton_script() {
  local powerbuttonscript=$1
  local daemonconfigfile=$2
  argon::create_file ${powerbuttonscript} 755

  cat <<-EOT > ${powerbuttonscript}
	#!/usr/bin/python
	import smbus
	import RPi.GPIO as GPIO
	import os
	import time
	from threading import Thread
	rev = GPIO.RPI_REVISION
	if rev == 2 or rev == 3:
	    bus = smbus.SMBus(1)
	else:
	    bus = smbus.SMBus(0)
	GPIO.setwarnings(False)
	GPIO.setmode(GPIO.BCM)
	shutdown_pin=4
	GPIO.setup(shutdown_pin, GPIO.IN,  pull_up_down=GPIO.PUD_DOWN)
	def shutdown_check():
	    while True:
	        pulsetime = 1
	        GPIO.wait_for_edge(shutdown_pin, GPIO.RISING)
	        time.sleep(0.01)
	        while GPIO.input(shutdown_pin) == GPIO.HIGH:
	            time.sleep(0.01)
	            pulsetime += 1
	        if pulsetime >=2 and pulsetime <=3:
	            os.system("reboot")
	        elif pulsetime >=4 and pulsetime <=5:
	            os.system("shutdown now -h")
	def get_fanspeed(tempval, configlist):
	    for curconfig in configlist:
	        curpair = curconfig.split("=")
	        tempcfg = float(curpair[0])
	        fancfg = int(float(curpair[1]))
	        if tempval >= tempcfg:
	            return fancfg
	    return 0
	def load_config(fname):
	    newconfig = []
	    try:
	        with open(fname, "r") as fp:
	            for curline in fp:
	                if not curline:
	                    continue
	                tmpline = curline.strip()
	                if not tmpline:
	                    continue
	                if tmpline[0] == "#":
	                    continue
	                tmppair = tmpline.split("=")
	                if len(tmppair) != 2:
	                    continue
	                tempval = 0
	                fanval = 0
	                try:
	                    tempval = float(tmppair[0])
	                    if tempval < 0 or tempval > 100:
	                        continue
	                except:
	                    continue
	                try:
	                    fanval = int(float(tmppair[1]))
	                    if fanval < 0 or fanval > 100:
	                        continue
	                except:
	                    continue
	                newconfig.append( "{:5.1f}={}".format(tempval,fanval))
	        if len(newconfig) > 0:
	            newconfig.sort(reverse=True)
	    except:
	        return []
	    return newconfig
	def temp_check():
	    fanconfig = ["65=100", "60=55", "55=10"]
	    tmpconfig = load_config("${daemonconfigfile}")
	    if len(tmpconfig) > 0:
	        fanconfig = tmpconfig
	    address=0x1a
	    prevblock=0
	    while True:
	        temp = os.popen("vcgencmd measure_temp").readline()
	        temp = temp.replace("temp=","")
	        val = float(temp.replace("'C",""))
	        block = get_fanspeed(val, fanconfig)
	        if block < prevblock:
	            time.sleep(30)
	        prevblock = block
	        try:
	            bus.write_byte(address,block)
	        except IOError:
	            temp=""
	        time.sleep(30)
	try:
	    t1 = Thread(target = shutdown_check)
	    t2 = Thread(target = temp_check)
	    t1.start()
	    t2.start()
	except:
	    t1.stop()
	    t2.stop()
	    GPIO.cleanup()
EOT
}

# Fan Daemon
function argon::create_fan_service() {
  daemonfanservice=$1
  powerbuttonscript=$2
  argon::create_file ${daemonfanservice} 644

  cat <<-EOT > ${daemonfanservice}
[Unit]
Description=Argon One Fan and Button Service
After=multi-user.target
[Service]
Type=simple
Restart=always
RemainAfterExit=true
ExecStart=/usr/bin/python3 ${powerbuttonscript}
[Install]
WantedBy=multi-user.target
EOT
}

# Uninstall Script
function argon::create_uninstall_script() {
  local removescript=$1
  local powerbuttonscript=$2
  local shutdownscript=$3
  argon::create_file ${removescript} 755

  cat <<-EOT > ${removescript}
	#!/bin/bash
	echo "-------------------------"
	echo "Argon One Uninstall Tool"
	echo "-------------------------"
	echo -n "Press Y to continue:"
	read -n 1 confirm
	echo
	if [ "\$confirm" = "y" ]
	then
	    confirm="Y"
	fi

	if [ "\$confirm" != "Y" ]
	then
	    echo "Cancelled"
	    exit
	fi
	if [ -d "/home/${USERNAME}/Desktop" ]; then
	    sudo rm "/home/${USERNAME}/Desktop/argonone-config.desktop"
	    sudo rm "/home/${USERNAME}/Desktop/argonone-uninstall.desktop"
	fi
	if [ -f ${powerbuttonscript} ]; then
	    sudo systemctl stop ${DAEMONNAME}.service
	    sudo systemctl disable ${DAEMONNAME}.service
	    sudo /usr/bin/python3 ${shutdownscript} uninstall
	    sudo rm ${powerbuttonscript}
	    sudo rm ${shutdownscript}
	    sudo rm ${removescript}
	    echo "Removed Argon One Services."
	    echo "Cleanup will complete after restarting the device."
	fi
EOT
}

# Config Script
function argon::create_config_script() {
  local configscript=$1
  local daemonconfigfile=$2
  argon::create_file ${configscript} 755

  cat <<-EOT > ${configscript}
	#!/bin/bash
	daemonconfigfile=/etc/${DAEMONNAME}.conf
	echo "--------------------------------------"
	echo "Argon One Fan Speed Configuration Tool"
	echo "--------------------------------------"
	echo "WARNING: This will remove existing configuration."
	echo -n "Press Y to continue:"
	read -n 1 confirm
	echo
	if [ "\$confirm" = "y" ]
	then
	    confirm="Y"
	fi

	if [ "\$confirm" != "Y" ]
	then
	    echo "Cancelled"
	    exit
	fi
	echo "Thank you."

	get_number () {
	    read curnumber
	    re="^[0-9]+$"
	    if [ -z "\$curnumber" ]
	    then
	        echo "-2"
	        return
	    elif [[ \$curnumber =~ ^[+-]?[0-9]+$ ]]
	    then
	        if [ \$curnumber -lt 0 ]
	        then
	            echo "-1"
	            return
	        elif [ \$curnumber -gt 100 ]
	        then
	            echo "-1"
	            return
	        fi
	        echo \$curnumber
	        return
	    fi
	    echo "-1"
	    return
	}


	loopflag=1
	while [ \$loopflag -eq 1 ]
	do
	    echo
	    echo "Select fan mode:"
	    echo "  1. Always on"
	    echo "  2. Adjust to temperatures (55C, 60C, and 65C)"
	    echo "  3. Customize behavior"
	    echo "  4. Cancel"
	    echo "NOTE: You can also edit ${daemonconfigfile} directly"
	    echo -n "Enter Number (1-4):"
	    newmode=\$( get_number )
	    if [[ \$newmode -ge 1 && \$newmode -le 4 ]]
	    then
	        loopflag=0
	    fi
	done

	echo
	if [ \$newmode -eq 4 ]
	then
	    echo "Cancelled"
	    exit
	elif [ \$newmode -eq 1 ]
	then
	    echo "#" > ${daemonconfigfile}
	    echo "# Argon One Fan Speed Configuration" >> ${daemonconfigfile}
	    echo "#" >> ${daemonconfigfile}
	    echo "# Min Temp=Fan Speed" >> ${daemonconfigfile}
	    echo 1"="100 >> ${daemonconfigfile}
	    sudo systemctl restart ${DAEMONNAME}.service
	    echo "Fan always on."
	    exit
	elif [ \$newmode -eq 2 ]
	then
	    echo "Please provide fan speeds for the following temperatures:"
	    echo "#" > ${daemonconfigfile}
	    echo "# Argon One Fan Speed Configuration" >> ${daemonconfigfile}
	    echo "#" >> ${daemonconfigfile}
	    echo "# Min Temp=Fan Speed" >> ${daemonconfigfile}
	    curtemp=55
	    while [ \$curtemp -lt 70 ]
	    do
	        errorfanflag=1
	        while [ \$errorfanflag -eq 1 ]
	        do
	            echo -n ""\$curtemp"C (0-100 only):"
	            curfan=\$( get_number )
	            if [ \$curfan -ge 0 ]
	            then
	                errorfanflag=0
	            fi
	        done
	        echo \$curtemp"="\$curfan >> ${daemonconfigfile}
	        curtemp=\$((curtemp+5))
	    done

	    sudo systemctl restart ${DAEMONNAME}.service
	    echo "Configuration updated."
	    exit
	fi

	echo "Please provide fan speeds and temperature pairs"
	echo

	loopflag=1
	paircounter=0
	while [ \$loopflag -eq 1 ]
	do
	    errortempflag=1
	    errorfanflag=1
	    while [ \$errortempflag -eq 1 ]
	    do
	        echo -n "Provide minimum temperature (in Celsius) then [ENTER]:"
	        curtemp=\$( get_number )
	        if [ \$curtemp -ge 0 ]
	        then
	            errortempflag=0
	        elif [ \$curtemp -eq -2 ]
	        then
	            errortempflag=0
	            errorfanflag=0
	            loopflag=0
	        fi
	    done
	    while [ \$errorfanflag -eq 1 ]
	    do
	        echo -n "Provide fan speed for "\$curtemp"C (0-100) then [ENTER]:"
	        curfan=\$( get_number )
	        if [ \$curfan -ge 0 ]
	        then
	            errorfanflag=0
	        elif [ \$curfan -eq -2 ]
	        then
	            errortempflag=0
	            errorfanflag=0
	            loopflag=0
	        fi
	    done
	    if [ \$loopflag -eq 1 ]
	    then
	        if [ \$paircounter -eq 0 ]
	        then
	            echo "#" > ${daemonconfigfile}
	            echo "# Argon One Fan Speed Configuration" >> ${daemonconfigfile}
	            echo "#" >> ${daemonconfigfile}
	            echo "# Min Temp=Fan Speed" >> ${daemonconfigfile}
	        fi
	        echo \$curtemp"="\$curfan >> ${daemonconfigfile}

	        paircounter=\$((paircounter+1))

	        echo "* Fan speed will be set to "\$curfan" once temperature reaches "\$curtemp" C"
	        echo
	    fi
	done

	echo
	if [ \$paircounter -gt 0 ]
	then
	    echo "Thank you!  We saved "\$paircounter" pairs."
	    sudo systemctl restart ${DAEMONNAME}.service
	    echo "Changes should take effect now."
	else
	    echo "Cancelled, no data saved."
	fi
EOT
}

function argon::start_deamon() {
  systemctl daemon-reload
  systemctl enable ${DAEMONNAME}.service
  systemctl start ${DAEMONNAME}.service
}

# Create Shortcuts
function argon::create_desktop_shortcut() {
  local configscript=$1
  local removescript=$2
  if [[ -d "/home/${USERNAME}/Desktop" ]]; then
    wget http://download.argon40.com/ar1config.png -O /usr/share/pixmaps/ar1config.png
    wget http://download.argon40.com/ar1uninstall.png -O /usr/share/pixmaps/ar1uninstall.png

    local configshortcutfile="/home/${USERNAME}/Desktop/argonone-config.desktop"
    argon::create_file ${configshortcutfile} 755

    cat <<-EOT > ${configshortcutfile}
		[Desktop Entry]
		Name=Argon One Configuration
		Comment=Argon One Configuration
		Icon=/usr/share/pixmaps/ar1config.png
		Exec=lxterminal -t "Argon One Configuration" --working-directory=/home/${USERNAME}/ -e ${configscript}
		Type=Application
		Encoding=UTF-8
		Terminal=false
		Categories=None;
EOT

    local uninstallshortcutfile="/home/${USERNAME}/Desktop/argonone-uninstall.desktop"
    argon::create_file ${uninstallshortcutfile} 755

    cat <<-EOT > ${uninstallshortcutfile}
		[Desktop Entry]
		Name=Argon One Uninstall
		Comment=Argon One Uninstall
		Icon=/usr/share/pixmaps/ar1uninstall.png
		Exec=lxterminal -t "Argon One Uninstall" --working-directory=/home/${USERNAME}/ -e ${removescript}
		Type=Application
		Encoding=UTF-8
		Terminal=false
		Categories=None;
EOT
  fi
}

function argon::finish_message() {
  echo <<EOT
	****************************
	 Argon One Setup Completed.
	****************************
EOT
  if [[ -d "/home/$USERNAME/Desktop" ]]; then
    echo Shortcuts created in your desktop.
  else
    echo Use 'argonone-config' to configure fan
    echo Use 'argonone-uninstall' to uninstall
  fi
  echo
}

function main() {
  local daemonconfigfile="/etc/${DAEMONNAME}.conf"
  local shutdownscript="/lib/systemd/system-shutdown/${DAEMONNAME}-poweroff.py"
  local powerbuttonscript="/usr/bin/${DAEMONNAME}.py"
  local daemonfanservice="/lib/systemd/system/${DAEMONNAME}.service"
  local removescript="/usr/bin/argonone-uninstall"
  local configscript="/usr/bin/argonone-config"

  argon::install_required_packages
  argon::change_raspi_config
  argon::create_daemonconfig_file ${daemonconfigfile}
  argon::create_shutdown_script ${shutdownscript}
  argon::create_powerbutton_script ${powerbuttonscript} ${daemonconfigfile}
  argon::create_fan_service ${daemonfanservice} ${powerbuttonscript}
  argon::create_uninstall_script ${removescript} ${powerbuttonscript} ${shutdownscript}
  argon::create_config_script ${configscript} ${daemonconfigfile}
  argon::start_deamon
  argon::create_desktop_shortcut ${configscript} ${removescript}
  argon::finish_message
}
main
