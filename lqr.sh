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
# LQR stands for Lightweight Quote Requester

# Function declarations
make_term_red(){
	RED='\033[0;31m'
	printf "${RED}"
}

make_term_green(){
        GREEN='\033[0;32m'
        printf "${GREEN}"
}

make_term_blue(){
        BLUE='\033[0;34m'
        printf "${BLUE}"
}

make_term_normal(){
	NC='\033[0m' # No Color
	printf "${NC}"
}

if [ -z "$AIKDIR" ]; then
	echo "You haven't specified the AIKDIR directory"
	exit 1
fi

TESTMODE=0
START=$(date +%s%N)

if [ $# -lt 2 ]
then
        echo "Usage: lqr.sh address port"
        exit 1
else
	if [ "$3" == "--testmode" ]
	then
		TESTMODE=1
	fi
fi

# Make the temporary files
FILE=$(mktemp)
QUOTE=$(mktemp)
LOG=$(mktemp)
AIK=$(mktemp)
NEWHASH=$(mktemp)
PUSH=$(mktemp)
HASHCPY=$(mktemp)
NONCE=$(mktemp)

# Get AIK from redis

HASHAIK=$(redis-cli --raw -n 13 get "$1")

if [ ! -d "$AIKDIR/$HASHAIK" ]
then
	EXISTS=$(redis-cli --raw -n 15 exists "$HASHAIK")
	if [ $EXISTS -eq 1 ]
	then
		mkdir "$AIKDIR/$HASHAIK"
	else
		echo "The machine isn't part of the verifier's pool, aborting..."
		exit 3
	fi
fi

# Check if files are here, otherwise get them from the DB

if [ ! -f "$AIKDIR/$HASHAIK/refLog" ]
then
	redis-cli --raw -n 15 LINDEX "$HASHAIK" '0' | base64 -d > "$AIKDIR/$HASHAIK/refLog"
fi

if [ ! -f "$AIKDIR/$HASHAIK/hashPCR" ]
then
	redis-cli --raw -n 15 LINDEX "$HASHAIK" '1' | base64 -d > "$AIKDIR/$HASHAIK/hashPCR"
fi

if [ ! -f "$AIKDIR/$HASHAIK/pcrValue" ]
then
	redis-cli --raw -n 15 LINDEX "$HASHAIK" '2' | base64 -d > "$AIKDIR/$HASHAIK/pcrValue"
fi

if [ ! -f "$AIKDIR/$HASHAIK/pubAIK" ]
then
        redis-cli --raw -n 15 LINDEX "$HASHAIK" '3' | base64 -d > "$AIKDIR/$HASHAIK/pubAIK"
fi

expected=$(ls -l "$AIKDIR/$HASHAIK" | wc -l)
if [ $expected -lt 4 ]
then
	echo "There seems to be some information missing about the machine"
	echo "Please check that the registration process was successful"
	exit 10
fi

# Get reference log line count + 1
COUNT=$(cat "$AIKDIR/$HASHAIK/refLog" | wc -l)
(( COUNT++ ))

# Generate nonce
if [ "$TESTMODE" -eq 1 ]
then
	echo "WARNING: Test mode activated, the nonce is zero, and therefore insecure"
	dd if=/dev/zero bs=1 count=20 of=$NONCE
else
	openssl rand 20 > $NONCE
fi

# Add the line number after the nonce to only get the new log part
SEND=$(echo "$(cat $NONCE | base64) $COUNT")

# Detect netcat version
PARAM=""
VERSION=$(dpkg-query -f '${binary:Package}\n' -W | grep netcat)
echo $VERSION | grep traditional > /dev/null
if [ $? -eq 1 ]
then
	PARAM="-q 20"
fi

RETRY=5
# Request the quote/log file
echo "$SEND" | nc.traditional $PARAM $1 $2 > $FILE

while [ $? -ne 0 ]
do
	if [ $RETRY -gt 0 ]
	then
		echo "Bad connection, retrying... ($(echo $RETRY) left)"
		RETRY=$((RETRY-1))
		sleep $(echo 1.$RANDOM)
		echo "$SEND" | nc $PARAM $1 $2 > $FILE
	else
		echo "Connection failed! Aborting now..."
		exit 2
	fi
done

TRANSFER=$(date +%s%N)

echo "Parsing quote"
# Parse the file
./lfp.sh $AIK $QUOTE $LOG $FILE
## We need to verify the quote for every entry and see if one fits


# Get received log line count
END=$(wc -l $LOG | cut -d " " -f 1)

TRUSTED=0
cp "$AIKDIR/$HASHAIK/hashPCR" "$HASHCPY"

#PCRVALUE="0000000000000000000000000000000000000000"

PCRVALUE=$(cat "$AIKDIR/$HASHAIK/pcrValue")

HASHSTART=$(date +%s%N)
# Recompute hash value (CAN BE AVOIDED BY STORING OLD HASH)
#for i in $(eval echo {1..$((COUNT-1))})
#do
#	LOGVALUE=$(sed "${i}q;d" "$AIKDIR/$HASHAIK/refLog' | cut -d " " -f 2)
#	NEWPCR=$(echo "$PCRVALUE$LOGVALUE" | xxd -r -p | sha1sum | cut -d " " -f 1)
#	PCRVALUE=$NEWPCR

echo "10=$PCRVALUE" > $PUSH
tpm_updatepcrhash $HASHCPY $PUSH $NEWHASH
cp $NEWHASH $HASHCPY

#
#done

HASHEND=$(date +%s%N)
QUOTESTART=$(date +%s%N)

# If the logs have the same size (may want to actually check the quote...)
if [ $END -eq 0 ]
then
        echo "AIKHASH: $(cat $AIKDIR/$HASHAIK/pubAIK | base64)"
        echo ""
        echo "NEWHASH: $(cat $NEWHASH | base64)"
        echo ""
        echo "NONCE: $(cat $NONCE | base64)"
        echo ""
        echo "QUOTE: $(cat $QUOTE | base64)"

	tpm_verifyquote "$AIKDIR/$HASHAIK/pubAIK" $NEWHASH $NONCE $QUOTE 2>/dev/null
	FAIL=$?
	if [ $FAIL -eq 0 ]
	then
		#echo "Found"
		TRUSTED=1
	else
		echo "tpm_verifyquote failed with $FAIL"
	fi
fi

ITER=1
while [ $ITER -le $END ]
do

	LOGVALUE=$(sed "${ITER}q;d" $LOG | cut -d " " -f 2)
	NEWPCR=$(echo "$PCRVALUE$LOGVALUE" | xxd -r -p | sha1sum | cut -d " " -f 1)
	PCRVALUE=$(echo $NEWPCR | tr '[:lower:]' '[:upper:]')
	echo "10=$PCRVALUE" > $PUSH

	tpm_updatepcrhash $HASHCPY $PUSH $NEWHASH
	cp $NEWHASH $HASHCPY

	tpm_verifyquote "$AIKDIR/$HASHAIK/pubAIK" $NEWHASH $NONCE $QUOTE 2>/dev/null

	if [ $? -eq 0 ]
	then
		TRUSTED=1
		cp $NEWHASH "$AIKDIR/$HASHAIK/hashPCR"
		cat "$AIKDIR/$HASHAIK/refLog" $LOG > $PUSH
		echo $PCRVALUE > "$AIKDIR/$HASHAIK/pcrValue"
		mv $PUSH "$AIKDIR/$HASHAIK/refLog"
		break
	fi
	(( ITER++ ))
done
# Assess situation
if [ $TRUSTED -eq 0 ]
then
	make_term_red
	echo "Bad configuration, system integrity is not guaranteed (maybe the machine rebooted, try again)"
	rm "$AIKDIR/$HASHAIK/hashPCR"
	rm "$AIKDIR/$HASHAIK/refLog"
	rm "$AIKDIR/$HASHAIK/pcrValue"
	make_term_normal
	exit 1
fi

QUOTEEND=$(date +%s%N)
FORMATSTART=$(date +%s%N)

make_term_blue
echo "Machine's public AIK SHA1 hash:"
echo $HASHAIK
echo
make_term_normal

# This detects whether the template is IMA-NG or IMA-CONT-ID
cat "$AIKDIR/$HASHAIK/refLog" | grep 'ima-ng' >/dev/null
NGMODE=$?

cat "$AIKDIR/$HASHAIK/refLog" | grep 'ima-cont-id ' >/dev/null
CONTMODE=$?

cat "$AIKDIR/$HASHAIK/refLog" | grep 'ima-cont-id-subj ' >/dev/null
SUBJMODE=$?

LIST=$(cat "$AIKDIR/$HASHAIK/refLog" | tail -n +2)

if [ $NGMODE -eq 0 ]
then
	CONTAINERLIST="ima-ng"
else if [ $CONTMODE -eq 0 ]
then
	CONTAINERLIST=$(echo "$LIST" | cut -d " " -f 4 | sort -u)

else if [ $SUBJMODE -eq 0 ]
then
	CONTAINERLIST=$(echo "$LIST" | cut -d " " -f 4 | sort -u)
	LIST=$(echo "$LIST" | grep 'ACT=*x*&')
fi
fi
fi

for container in $CONTAINERLIST
do
	if [ $NGMODE -eq 0 ]
	then
		CONTENTRIES=$LIST
	else if [ $CONTMODE -eq 0 ]
	then
		CONTENTRIES=$(echo "$LIST" | awk '$4 == '"\"$(echo $container)\""' { print $0 }')
	else if [ $SUBJMODE -eq 0 ]
	then
		CONTENTRIES=$(echo "$LIST" | awk '$4 == '"\"$(echo $container)\""' { print $0 }')
	fi
	fi
	fi
	DBENTRIES=$(echo "$CONTENTRIES" | rev | cut -d " " -f 2 | rev | cut -d ":" -f 2 | xargs redis-cli --raw -n 10 mget | awk 'NF == 0 { print "@@@";next};{ print $0}')
	DBENT=$(echo "$DBENTRIES" | awk '$0 == "@@@" { next };{ print $0 }')
	ENTRYCOUNT=$(echo "$CONTENTRIES" | wc -l)
	VALIDCOUNT=$(echo "$DBENTRIES" | grep -c "@@@")
	VALIDCOUNT=$((ENTRYCOUNT-VALIDCOUNT))
	make_term_green
	echo 'Container ID :'
	echo "$container"
	echo
	make_term_normal
	echo "$VALIDCOUNT/$ENTRYCOUNT binaries found in database"
	#echo "List of binaries in database :"
	#echo "$DBENTRIES"
	echo
	echo "List of binaries not in database:"

	# Change termcolor to red
	make_term_red

	# Print packages out
	NOTIN=$(paste <(echo "$DBENTRIES" ) <(echo "$CONTENTRIES" | rev | cut -d " " -f 1 | rev))

	echo "$NOTIN" | grep @@@ | cut -f 2

	# Change termcolor to default colour
	make_term_normal

	PACKS=$(echo "$DBENT" | rev | cut -d "/" -f 1 | rev | cut -d "@" -f 2 | cut -d "_" -f 1,2 | sort -u)

	echo
	echo "List of detected vulnerable packages :"
	echo
	for packid in $PACKS
	do

		RESULT=$(redis-cli --raw -n 12 exists "$packid")
		if [ $RESULT -eq 1 ]
		then
			echo "Package name :"
			echo $packid
			echo "Severity of CVEs :"
			redis-cli --raw -n 12 smembers "$packid"
			echo
		fi
	done
done

FORMATEND=$(date +%s%N)

FINISH=$(date +%s%N)
echo

echo "$END lines processed"

echo

echo "Download time : $(( ($TRANSFER - $START)/1000000 )) ms"
echo "Processing time : $(( ($FINISH - $TRANSFER)/1000000 )) ms"

echo "Hash time : $(( ($HASHEND - $HASHSTART)/1000000 )) ms"
echo "Quote time : $(( ($QUOTEEND - $QUOTESTART)/1000000 )) ms"
echo "Format time : $(( ($FORMATEND - $FORMATSTART)/1000000 )) ms"

echo "Total time : $(( ($FINISH - $START)/1000000 )) ms"

rm $FILE
rm $QUOTE
rm $LOG
rm $AIK
rm $NEWHASH
rm $PUSH
rm $HASHCPY

exit 0
