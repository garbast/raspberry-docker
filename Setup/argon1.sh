#!/bin/bash

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run with sudo"
  exit 1
fi

readonly USERNAME="pi"
readonly DAEMONNAME="argononed"

function argon::create_file() {
  local file=$1
  if [[ -f ${file} ]]; then
    rm ${file}
  fi
  touch ${file}
  chmod 666 ${file}
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
    #apt-get install -y ${package_name}
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

function argon::create_config_file() {
  local daemonconfigfile=$1
  if [[ ! -f ${daemonconfigfile} ]]; then
    # config file for fan speed
    argon::create_file ${daemonconfigfile}

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
  shutdownscript=$1
  argon::create_file ${shutdownscript}

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
  chmod 755 ${shutdownscript}
}

# Generate script to monitor shutdown button
function argon::create_powerbutton_script() {
  local powerbuttonscript=$1
  local daemonconfigfile=$2
  argon::create_file ${powerbuttonscript}

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
  chmod 755 ${powerbuttonscript}
}

# Fan Daemon
function argon::create_fan_service() {
  daemonfanservice=$1
  powerbuttonscript=$2
  argon::create_file ${daemonfanservice}

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
  chmod 644 ${daemonfanservice}
}

function main() {
  local daemonconfigfile="/etc/${DAEMONNAME}.conf"
  local shutdownscript="/lib/systemd/system-shutdown/${DAEMONNAME}-poweroff.py"
  local powerbuttonscript="/usr/bin/${DAEMONNAME}.py"
  local daemonfanservice="/lib/systemd/system/${DAEMONNAME}.service"

  argon::install_required_packages
  argon::change_raspi_config
  argon::create_config_file ${daemonconfigfile}
  argon::create_shutdown_script ${shutdownscript}
  argon::create_powerbutton_script ${powerbuttonscript} ${daemonconfigfile}
  argon::create_fan_service ${daemonfanservice} ${powerbuttonscript}
}
main;
exit

powerbuttonscript=/usr/bin/${DAEMONNAME}.py
daemonconfigfile=/etc/${DAEMONNAME}.conf
configscript=/usr/bin/argonone-config
removescript=/usr/bin/argonone-uninstall
daemonfanservice=/lib/systemd/system/${DAEMONNAME}.service

argon::create_file $removescript

# Uninstall Script
echo '#!/bin/bash' >> $removescript
echo 'echo "-------------------------"' >> $removescript
echo 'echo "Argon One Uninstall Tool"' >> $removescript
echo 'echo "-------------------------"' >> $removescript
echo 'echo -n "Press Y to continue:"' >> $removescript
echo 'read -n 1 confirm' >> $removescript
echo 'echo' >> $removescript
echo 'if [ "$confirm" = "y" ]' >> $removescript
echo 'then' >> $removescript
echo '	confirm="Y"' >> $removescript
echo 'fi' >> $removescript
echo '' >> $removescript
echo 'if [ "$confirm" != "Y" ]' >> $removescript
echo 'then' >> $removescript
echo '	echo "Cancelled"' >> $removescript
echo '	exit' >> $removescript
echo 'fi' >> $removescript
echo 'if [ -d "/home/$USERNAME/Desktop" ]; then' >> $removescript
echo '	sudo rm "/home/$USERNAME/Desktop/argonone-config.desktop"' >> $removescript
echo '	sudo rm "/home/$USERNAME/Desktop/argonone-uninstall.desktop"' >> $removescript
echo 'fi' >> $removescript
echo 'if [ -f '$powerbuttonscript' ]; then' >> $removescript
echo '	sudo systemctl stop '$DAEMONNAME'.service' >> $removescript
echo '	sudo systemctl disable '$DAEMONNAME'.service' >> $removescript
echo '	sudo /usr/bin/python3 '$shutdownscript' uninstall' >> $removescript
echo '	sudo rm '$powerbuttonscript >> $removescript
echo '	sudo rm '$shutdownscript >> $removescript
echo '	sudo rm '$removescript >> $removescript
echo '	echo "Removed Argon One Services."' >> $removescript
echo '	echo "Cleanup will complete after restarting the device."' >> $removescript
echo 'fi' >> $removescript

chmod 755 $removescript

argon::create_file $configscript

# Config Script
echo '#!/bin/bash' >> $configscript
echo 'daemonconfigfile=/etc/'$DAEMONNAME'.conf' >> $configscript
echo 'echo "--------------------------------------"' >> $configscript
echo 'echo "Argon One Fan Speed Configuration Tool"' >> $configscript
echo 'echo "--------------------------------------"' >> $configscript
echo 'echo "WARNING: This will remove existing configuration."' >> $configscript
echo 'echo -n "Press Y to continue:"' >> $configscript
echo 'read -n 1 confirm' >> $configscript
echo 'echo' >> $configscript
echo 'if [ "$confirm" = "y" ]' >> $configscript
echo 'then' >> $configscript
echo '	confirm="Y"' >> $configscript
echo 'fi' >> $configscript
echo '' >> $configscript
echo 'if [ "$confirm" != "Y" ]' >> $configscript
echo 'then' >> $configscript
echo '	echo "Cancelled"' >> $configscript
echo '	exit' >> $configscript
echo 'fi' >> $configscript
echo 'echo "Thank you."' >> $configscript

echo 'get_number () {' >> $configscript
echo '	read curnumber' >> $configscript
echo '	re="^[0-9]+$"' >> $configscript
echo '	if [ -z "$curnumber" ]' >> $configscript
echo '	then' >> $configscript
echo '		echo "-2"' >> $configscript
echo '		return' >> $configscript
echo '	elif [[ $curnumber =~ ^[+-]?[0-9]+$ ]]' >> $configscript
echo '	then' >> $configscript
echo '		if [ $curnumber -lt 0 ]' >> $configscript
echo '		then' >> $configscript
echo '			echo "-1"' >> $configscript
echo '			return' >> $configscript
echo '		elif [ $curnumber -gt 100 ]' >> $configscript
echo '		then' >> $configscript
echo '			echo "-1"' >> $configscript
echo '			return' >> $configscript
echo '		fi	' >> $configscript
echo '		echo $curnumber' >> $configscript
echo '		return' >> $configscript
echo '	fi' >> $configscript
echo '	echo "-1"' >> $configscript
echo '	return' >> $configscript
echo '}' >> $configscript
echo '' >> $configscript

echo 'loopflag=1' >> $configscript
echo 'while [ $loopflag -eq 1 ]' >> $configscript
echo 'do' >> $configscript
echo '	echo' >> $configscript
echo '	echo "Select fan mode:"' >> $configscript
echo '	echo "  1. Always on"' >> $configscript
echo '	echo "  2. Adjust to temperatures (55C, 60C, and 65C)"' >> $configscript
echo '	echo "  3. Customize behavior"' >> $configscript
echo '	echo "  4. Cancel"' >> $configscript
echo '	echo "NOTE: You can also edit $daemonconfigfile directly"' >> $configscript
echo '	echo -n "Enter Number (1-4):"' >> $configscript
echo '	newmode=$( get_number )' >> $configscript
echo '	if [[ $newmode -ge 1 && $newmode -le 4 ]]' >> $configscript
echo '	then' >> $configscript
echo '		loopflag=0' >> $configscript
echo '	fi' >> $configscript
echo 'done' >> $configscript

echo 'echo' >> $configscript
echo 'if [ $newmode -eq 4 ]' >> $configscript
echo 'then' >> $configscript
echo '	echo "Cancelled"' >> $configscript
echo '	exit' >> $configscript
echo 'elif [ $newmode -eq 1 ]' >> $configscript
echo 'then' >> $configscript
echo '	echo "#" > $daemonconfigfile' >> $configscript
echo '	echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile' >> $configscript
echo '	echo "#" >> $daemonconfigfile' >> $configscript
echo '	echo "# Min Temp=Fan Speed" >> $daemonconfigfile' >> $configscript
echo '	echo 1"="100 >> $daemonconfigfile' >> $configscript
echo '	sudo systemctl restart '$DAEMONNAME'.service' >> $configscript
echo '	echo "Fan always on."' >> $configscript
echo '	exit' >> $configscript
echo 'elif [ $newmode -eq 2 ]' >> $configscript
echo 'then' >> $configscript
echo '	echo "Please provide fan speeds for the following temperatures:"' >> $configscript
echo '	echo "#" > $daemonconfigfile' >> $configscript
echo '	echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile' >> $configscript
echo '	echo "#" >> $daemonconfigfile' >> $configscript
echo '	echo "# Min Temp=Fan Speed" >> $daemonconfigfile' >> $configscript
echo '	curtemp=55' >> $configscript
echo '	while [ $curtemp -lt 70 ]' >> $configscript
echo '	do' >> $configscript
echo '		errorfanflag=1' >> $configscript
echo '		while [ $errorfanflag -eq 1 ]' >> $configscript
echo '		do' >> $configscript
echo '			echo -n ""$curtemp"C (0-100 only):"' >> $configscript
echo '			curfan=$( get_number )' >> $configscript
echo '			if [ $curfan -ge 0 ]' >> $configscript
echo '			then' >> $configscript
echo '				errorfanflag=0' >> $configscript
echo '			fi' >> $configscript
echo '		done' >> $configscript
echo '		echo $curtemp"="$curfan >> $daemonconfigfile' >> $configscript
echo '		curtemp=$((curtemp+5))' >> $configscript
echo '	done' >> $configscript

echo '	sudo systemctl restart '$DAEMONNAME'.service' >> $configscript
echo '	echo "Configuration updated."' >> $configscript
echo '	exit' >> $configscript
echo 'fi' >> $configscript

echo 'echo "Please provide fan speeds and temperature pairs"' >> $configscript
echo 'echo' >> $configscript

echo 'loopflag=1' >> $configscript
echo 'paircounter=0' >> $configscript
echo 'while [ $loopflag -eq 1 ]' >> $configscript
echo 'do' >> $configscript
echo '	errortempflag=1' >> $configscript
echo '	errorfanflag=1' >> $configscript
echo '	while [ $errortempflag -eq 1 ]' >> $configscript
echo '	do' >> $configscript
echo '		echo -n "Provide minimum temperature (in Celsius) then [ENTER]:"' >> $configscript
echo '		curtemp=$( get_number )' >> $configscript
echo '		if [ $curtemp -ge 0 ]' >> $configscript
echo '		then' >> $configscript
echo '			errortempflag=0' >> $configscript
echo '		elif [ $curtemp -eq -2 ]' >> $configscript
echo '		then' >> $configscript
echo '			errortempflag=0' >> $configscript
echo '			errorfanflag=0' >> $configscript
echo '			loopflag=0' >> $configscript
echo '		fi' >> $configscript
echo '	done' >> $configscript
echo '	while [ $errorfanflag -eq 1 ]' >> $configscript
echo '	do' >> $configscript
echo '		echo -n "Provide fan speed for "$curtemp"C (0-100) then [ENTER]:"' >> $configscript
echo '		curfan=$( get_number )' >> $configscript
echo '		if [ $curfan -ge 0 ]' >> $configscript
echo '		then' >> $configscript
echo '			errorfanflag=0' >> $configscript
echo '		elif [ $curfan -eq -2 ]' >> $configscript
echo '		then' >> $configscript
echo '			errortempflag=0' >> $configscript
echo '			errorfanflag=0' >> $configscript
echo '			loopflag=0' >> $configscript
echo '		fi' >> $configscript
echo '	done' >> $configscript
echo '	if [ $loopflag -eq 1 ]' >> $configscript
echo '	then' >> $configscript
echo '		if [ $paircounter -eq 0 ]' >> $configscript
echo '		then' >> $configscript
echo '			echo "#" > $daemonconfigfile' >> $configscript
echo '			echo "# Argon One Fan Speed Configuration" >> $daemonconfigfile' >> $configscript
echo '			echo "#" >> $daemonconfigfile' >> $configscript
echo '			echo "# Min Temp=Fan Speed" >> $daemonconfigfile' >> $configscript
echo '		fi' >> $configscript
echo '		echo $curtemp"="$curfan >> $daemonconfigfile' >> $configscript
echo '		' >> $configscript
echo '		paircounter=$((paircounter+1))' >> $configscript
echo '		' >> $configscript
echo '		echo "* Fan speed will be set to "$curfan" once temperature reaches "$curtemp" C"' >> $configscript
echo '		echo' >> $configscript
echo '	fi' >> $configscript
echo 'done' >> $configscript
echo '' >> $configscript
echo 'echo' >> $configscript
echo 'if [ $paircounter -gt 0 ]' >> $configscript
echo 'then' >> $configscript
echo '	echo "Thank you!  We saved "$paircounter" pairs."' >> $configscript
echo '	sudo systemctl restart '$DAEMONNAME'.service' >> $configscript
echo '	echo "Changes should take effect now."' >> $configscript
echo 'else' >> $configscript
echo '	echo "Cancelled, no data saved."' >> $configscript
echo 'fi' >> $configscript

chmod 755 $configscript


systemctl daemon-reload
systemctl enable $DAEMONNAME.service

systemctl start $DAEMONNAME.service

if [[ -d "/home/$USERNAME/Desktop" ]]; then
  wget http://download.argon40.com/ar1config.png -O /usr/share/pixmaps/ar1config.png
  wget http://download.argon40.com/ar1uninstall.png -O /usr/share/pixmaps/ar1uninstall.png

  # Create Shortcuts
  shortcutfile="/home/$USERNAME/Desktop/argonone-config.desktop"
  echo "[Desktop Entry]" > $shortcutfile
  echo "Name=Argon One Configuration" >> $shortcutfile
  echo "Comment=Argon One Configuration" >> $shortcutfile
  echo "Icon=/usr/share/pixmaps/ar1config.png" >> $shortcutfile
  echo 'Exec=lxterminal -t "Argon One Configuration" --working-directory=/home/$USERNAME/ -e '$configscript >> $shortcutfile
  echo "Type=Application" >> $shortcutfile
  echo "Encoding=UTF-8" >> $shortcutfile
  echo "Terminal=false" >> $shortcutfile
  echo "Categories=None;" >> $shortcutfile
  chmod 755 $shortcutfile

  shortcutfile="/home/$USERNAME/Desktop/argonone-uninstall.desktop"
  echo "[Desktop Entry]" > $shortcutfile
  echo "Name=Argon One Uninstall" >> $shortcutfile
  echo "Comment=Argon One Uninstall" >> $shortcutfile
  echo "Icon=/usr/share/pixmaps/ar1uninstall.png" >> $shortcutfile
  echo 'Exec=lxterminal -t "Argon One Uninstall" --working-directory=/home/$USERNAME/ -e '$removescript >> $shortcutfile
  echo "Type=Application" >> $shortcutfile
  echo "Encoding=UTF-8" >> $shortcutfile
  echo "Terminal=false" >> $shortcutfile
  echo "Categories=None;" >> $shortcutfile
  chmod 755 $shortcutfile
fi


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
