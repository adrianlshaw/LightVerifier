#!/bin/bash

# (c) Copyright 2016-2017 Hewlett Packard Enterprise Development LP
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License, version 2, as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
# License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Authors:	Victor Sallard
#		Adrian L. Shaw <adrianlshaw@acm.org>
#

# This is a wrapper to ease the use of the requester
# $1 is the target, $2 is the port
# AIKDIR specifies where the machine information is

TTL=5
export AIKDIR="./"

if [ $# -lt 2 ]
then
        echo "Usage: verify.sh <hostname> <port>"
        exit 1
else
	if [ "$3" == "--testmode" ]
	then
		echo "Unimplemented: Activating testmode"
	fi
fi

redis-cli ping >/dev/null 2>&1 || { echo >&2 "Redis CLI not installed. Aborting."; exit 1; }

KNOWN=$(redis-cli --raw -n 13 exists "$1")
if [ "$KNOWN" -eq 0 ]
then
	# Generate nonce
	NONCE=$(openssl rand 20)

	# Add the line number after the nonce to only get the new log part
	SEND=$(echo $(echo "$NONCE" | base64) "1")

	# Detect netcat version
	PARAM=""
	VERSION=$(dpkg-query -f '${binary:Package}\n' -W | grep netcat)
	echo "$VERSION" | grep traditional > /dev/null
	if [ $? -eq 1 ]
	then
        	PARAM="-q 20"
	fi
	# Request the pubAIK/quote/log file
	PUBAIK=$(echo "$SEND" | nc "$PARAM" $1 $2)

	if [ $? -ne 0 ]
	then
		echo "Connection error."
		exit 3
	fi

	PUBAIK=$(echo "$PUBAIK" | sed '2q;d')

	redis-cli --raw -n 13 set "$1" "$PUBAIK" >/dev/null
else
	PUBAIK=$(redis-cli --raw -n 13 get "$1")
fi

if [ ! -d "$AIKDIR/$PUBAIK" ]
then
	mkdir "$AIKDIR/$PUBAIK"
fi

REPORT="$AIKDIR/$PUBAIK/report.log"

EXISTS=$(redis-cli --raw -n 14 exists "$PUBAIK")
if [ $EXISTS -eq 0 ]
then
	flock /var/lock/tpm_request_$PUBAIK ./lqr.sh $1 $2 > $REPORT
	EXITCODE=$?

	if [ $EXITCODE -eq 2 ]
	then
		echo "Bad connection"
                exit 2
	else
		if [ $EXITCODE -eq 3 ]
		then
			echo "The machine is not known to the verifier. Did you register the machine?"
			echo "See the register.sh script."
	                exit 3
		else
			if [ $EXITCODE -ne 0 ]
			then
				echo "The machine cannot be trusted (try again if machine rebooted)"
				exit 1
			fi
		fi
	fi

	echo >> "$REPORT"
	echo "Log generation time :" >> "$REPORT"
	date >> "$REPORT"
	echo "Log TTL :" >> "$REPORT"
	echo "$TTL" >> "$REPORT"

	# This will create an entry valid for $TTL seconds
	redis-cli --raw -n 14 set "$PUBAIK" TRUST EX "$TTL" >/dev/null
fi

STATS=$(tail -n 13 "$REPORT" | head -n 8)

CSV=$(echo "$STATS" | head -n 1 | cut -d " " -f 1)","$(echo "$STATS" | tail -n +3 | cut -d " " -f 4 | paste -sd,)

echo "$CSV" >> ./statistics.csv

cat "$REPORT"

exit 0
