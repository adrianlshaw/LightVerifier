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

trap exitIt INT

TESTMODE=0

if [ $# -lt 4 ]
then
        echo "Usage: ra-agent.sh <aik.pub> <aik.uuid> <port> <PCR numbers ...>"
	exit 1
else
	if [ "$2" == "--testmode" ]
	then
		echo "WARNING: Test mode enabled"
		TESTMODE=1
	fi
fi

PGID=$(ps -o pgid= $$ | grep -o '[0-9]*')
PAIK=$1
UUID=$2
PORT=$3
shift
shift
shift
PCRS="$@"

exitIt(){
	# Some temporary files may remain...
	kill -- -$PGID
	exit 0
}

mainRun(){
	# Store parameters
	PAIK=$1
	UUID=$2
	PORT=$3
	shift
	shift
	shift
	PCRS="$@"

	# Detect netcat version
	PARAM=""
	VERSION=$(dpkg-query -f '${binary:Package}\n' -W | grep netcat)
	echo $VERSION | grep traditional > /dev/null
	if [ $? -eq 0 ]
	then
		PARAM="-p"
	fi

	# Create temporary files
	FIFO=$(mktemp -u)
	mkfifo $FIFO
	FILE=$(mktemp)
	NONCE=$(mktemp)
	QUOTE=$(mktemp)
	OUTFILE=$(mktemp)

	# Open netcat connection for listening
	cat $FIFO | nc -q 0 -l $PARAM $PORT > $FILE &
	echo "Waiting for connection..."
	while ! [ -s $FILE ]
	do
		sleep 0.1
	done
	echo "Connected"

	# Spawn a new instance for the next connection
	mainRun $PAIK $UUID $PORT $PCRS &

	# BASE64 decode nonce and store
	cat $FILE | cut -d " " -f 1 | base64 -d > $NONCE

	# Store line count for diff transfer
	LINE=$(cat $FILE | cut -d " " -f 2)

	# Compute the quote with received nonce, but only after everyone
  	# has finished with tpm_getquote.
	# Mutex prevents parallel execution of tpm_getquote
	if [ "$TESTMODE" -eq 0 ]
	then
		echo "Computing quote..."
		flock /var/lock/tmp_quote_sender tpm_getquote $UUID $NONCE $QUOTE $PCRS
		echo "Done"

		echo "Formatting..."
		# Fetch IMA measurements
		IMA=$(tail -n +$LINE /sys/kernel/security/ima/ascii_runtime_measurements)
	else
		# If we are running with the --testmode flag then we 
		# assume that the verifier is also running with the --testmode flag.
		# Since there is no IMA or TPM in a CI service like Travis, then
		# we use TPM quotes we have prepared earlier...
		cp tests/client_tpm12_test_quote $QUOTE
		IMA=$(tail -n +$LINE tests/client_test_log)
	fi

	# Base64 encoding of the quote (to avoid getting stray EOF everywhere)
	B64=$(base64 $QUOTE)

	# Generate SHA1 of the public part of the AIK
	HASH=$(sha1sum $PAIK | cut -d " " -f 1)

	# Fancy formatting

	echo "##SHA1 pubAIK##" > $OUTFILE
	echo "$HASH" >> $OUTFILE
	echo "##Base64 encoded quote##" >> $OUTFILE
	echo "$B64" >> $OUTFILE
	echo "##IMA ASCII log file##" >> $OUTFILE
	echo "$IMA" >> $OUTFILE

	echo "Ready to send!"

	# Send the file through the pipe
	cat $OUTFILE > $FIFO

	# Cleanup
	rm $FIFO
	rm $FILE
	rm $NONCE
	rm $QUOTE
	rm $OUTFILE

	exit 0
}

mainRun $PAIK $UUID $PORT $PCRS &
echo "Ctrl+C will stop the script"
while true; do sleep 60; done
