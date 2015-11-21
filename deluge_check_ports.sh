#! /bin/bash

# User Set Variables
USER=$(awk NR==1 /etc/openvpn/pass.txt)
PASS=$(awk NR==2 /etc/openvpn/pass.txt)
TUN="tun0"
DEL_USER_HOME="/home/pi"
DEL_CONF_PATH="/home/pi/.config/deluge"
DEL_CONF_BK_PATH="/home/pi/.config/deluge/config_bak"
LOG_PATH="/var/log/deluge/check_ports.log"
# Script Set Variables
DEL_CONF="$DEL_CONF_PATH/core.conf"
echo "$DEL_CONF"
LOCAL_ADD=$(ifconfig "$TUN" | awk '/inet addr/ {print $2}' | awk 'BEGIN{FS=":"}{print $2}')

# Find the current port
FWD_PORT=$(curl -s -d "user=$USER&pass=$PASS&client_id=$(cat $DEL_USER_HOME/.pia_client_id)&local_ip=$LOCAL_ADD" https://www.privateinternetaccess.com/vpninfo/port_forward_assignment)
# TO DO: fix flags on curl to stop progress info being posted to terminal
PORT=$(echo  ${FWD_PORT:8:5})

# Check we got something, that $PORT has a value:
if [ -n $PORT ]
then
	# Log the port this hour
	echo "$(date +"%D %T"): Current VPN forwarded port is: $PORT" > "$LOG_PATH"
else
	# Stop the script & log the error
	echo "$(date +"%D %T"): ERROR: attempt at getting VPN forwarded port returned nothing" > "$LOG_PATH"
	exit 1
fi

# Check the port in the current config file
DELUGE_START_PORT=$(grep 'listen_ports' -A 2 "$DEL_CONF" | awk 'FNR==2 {print}')
DELUGE_END_PORT=$(grep 'listen_ports' -A 2 "$DEL_CONF" | awk 'FNR==3 {print}')

# The grep command returns three lines:
#	"listen_ports": [
#		port_range_start
#		port_range_stop
# We want to check the 2nd and 3rd lines against $PORT, and then alter the config file if they are different

# Check the deluge port variables were filled by the grep commands; run them again then if they are still empty,
# or not the right length (i.e. we accidently grep'd something else).
# The string should be 9 characters long: 4 spaces and a 5 digit port number
# (start port is 10 or 11 because of the trailing comma and (possible) space)
# exit(2) = deluge_start_port is empty/not the right length
# exit(3) = deluge_end_port is empty/not the right length
if [ ! "${#DELUGE_START_PORT}" == 10 -a ! "${#DELUGE_START_PORT}" == 11 ]
then
	DELUGE_START_PORT=$(grep 'listen_ports' -A 2 "$DEL_CONF" | awk 'FNR==2 {print}')
	if [ ! "${#DELUGE_START_PORT}" == 10 -a ! "${#DELUGE_START_PORT}" == 11 ]
	then
		echo "$(date +"%D %T"): ERROR: Could not obtain the start port of the Deluge incoming port range" >> "$LOG_PATH"
		exit 2
	fi
fi

if [ ! "${#DELUGE_END_PORT}" == 9 ]
then
	DELUGE_END_PORT=$(grep 'listen_ports' -A 2 "$DEL_CONF" | awk 'FNR==3 {print}')
	if [ ! "${#DELUGE_END_PORT}" == 9 ]
	then
		echo "$(date +"%D %T"): ERROR: Could not obtain the finish port of the Deluge incoming port range" >> "$LOG_PATH"
		exit 3
	fi
fi

# Make sure the change variables are set to 0 each run
CHANGE_START="0"
CHNAGE_END="0"

# Now do the comparison (and check it doesn't fail because the variable is empty)
if [ "    $PORT," == "$DELUGE_START_PORT" ]
then
	echo "$(date +"%D %T"): Start port is the same" >> "$LOG_PATH"
else
	echo "$(date +"%D %T"): Start port is: '$DELUGE_START_PORT'" >> "$LOG_PATH"
	echo "$(date +"%D %T"): This is different ..." >> "$LOG_PATH"
	CHANGE_START="1"
fi
if [ "    $PORT" == "$DELUGE_END_PORT" ]
then
	echo "$(date +"%D %T"): End port is the same" >> "$LOG_PATH"
else
	echo "$(date +"%D %T"): End port is: '$DELUGE_END_PORT'" >> "$LOG_PATH"
	echo "$(date +"%D %T"): This is different ..." >> "$LOG_PATH"
	CHANGE_END="1"
fi	
 
if [ "$CHANGE_START" == 1 -o "$CHANGE_END" == 1 ]
then
	echo "$(date +"%D %T"): Changing the port" >> "$LOG_PATH"
	# Stop the deluge-daemon
	service deluge-daemon stop >> "$LOG_PATH"
	# Back up the config file in case something goes wrong
	cp --backup=t "$DEL_CONF" /home/pi/.config/deluge/config_baks/
	# TO DO: add something to clean up the back ups if there's more than 10 say
	# Change the ports as needed:
	if [ "$CHANGE_START" == 1 ]
	then
		sed -i "s/$DELUGE_START_PORT/    $PORT,/" "$DEL_CONF" # Have to add the comma & preserve whitespace
	fi
	if [ "$CHANGE_END" == 1 ]
	then
		sed -i "s/$DELUGE_END_PORT/    $PORT/" "$DEL_CONF" # Preserve whitespace
	fi
	# Restart the daemon
	service deluge-daemon start >> "$LOG_PATH"
fi