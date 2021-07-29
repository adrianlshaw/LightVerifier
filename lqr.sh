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
export TPM2=1

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

extend_pcr(){
	echo -n "$1$2" | xxd -r -p | sha1sum | tr -d '-'
}

check_log_corruption(){
	echo "Sanity checking template entries"
	while read line; do
		FILE=$(mktemp)
		printf '\32\0\0\0' > $FILE
		printf "sha1:\0" >> $FILE # Alg + colon and nul byte
		echo $line | cut -d ' ' -f4 | cut -d ':' -f2 | xxd -r -p >> $FILE # File digest
		FILEPATHLEN=$(echo $line | cut -d ' ' -f5 | wc -c)
		printf "%08x" $FILEPATHLEN | tac -rs .. |  xxd -r -p >> $FILE
		echo -n $line | cut -d ' ' -f5 | tr -d "\n" >> $FILE # File 
		printf "\0" >> $FILE
		#echo "Comparing  $(echo $line | cut -d ' ' -f2) with $(sha1sum $FILE)"
		EXPECTEDPCR=$(echo $line | cut -d ' ' -f2)
		CALCULATEDPCR=$(sha1sum $FILE | cut -d ' ' -f1)
		rm -f $FILE
		if [ "$EXPECTEDPCR" != "$CALCULATEDPCR" ]; then
			echo "Aborting. Template hash is incorrect on line $line"
			return 1
		fi
	done <$1
	return 0
}

if [ -z "$AIKDIR" ]; then
	echo "You haven't specified the AIKDIR shell variable."
	echo "Please set it to a writeable directory, e.g. export AIKDIR=/tmp/"
	exit 1
fi

TESTMODE=0
START=$(date +%s%N)

if [ $# -lt 2 ]
then
        echo "Usage: lqr.sh <hostname> <port>"
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

# Redis DB numbers
REDIS_MEASUREMENTS=10
REDIS_AIK=13
REDIS_AIK_INFO=15

# Get AIK from redis based on the hostname
HASHAIK=$(redis-cli --raw -n $REDIS_AIK get "$1")

if [ ! -d "$AIKDIR/$HASHAIK" ]
then
	EXISTS=$(redis-cli --raw -n $REDIS_AIK_INFO exists "$HASHAIK")
	if [ $EXISTS -eq 1 ]
	then
		mkdir "$AIKDIR/$HASHAIK"
	else
		echo "This hostname isn't known to the verifier. Aborting..."
		exit 3
	fi
fi

# Check if files are already cached, otherwise get them from Redis
if [ ! -f "$AIKDIR/$HASHAIK/refLog" ]
then
	redis-cli --raw -n $REDIS_AIK_INFO LINDEX "$HASHAIK" '0' | base64 -d > "$AIKDIR/$HASHAIK/refLog"
fi

if [ ! -f "$AIKDIR/$HASHAIK/hashPCR" ]
then
	redis-cli --raw -n $REDIS_AIK_INFO LINDEX "$HASHAIK" '1' | base64 -d > "$AIKDIR/$HASHAIK/hashPCR"
fi

if [ ! -f "$AIKDIR/$HASHAIK/pcrValue" ]
then
	redis-cli --raw -n $REDIS_AIK_INFO LINDEX "$HASHAIK" '2' | base64 -d | cut -d 'x' -f2 > "$AIKDIR/$HASHAIK/pcrValue"
fi

if [ ! -f "$AIKDIR/$HASHAIK/pubAIK" ]
then
  redis-cli --raw -n $REDIS_AIK_INFO LINDEX "$HASHAIK" '3' | base64 -d > "$AIKDIR/$HASHAIK/pubAIK"
fi

# Throw an error if we don't have all the right information.
expected=$(ls -l "$AIKDIR/$HASHAIK" | wc -l)
if [ $expected -lt 4 ]
then
	make_term_red
	echo "There seems to be some information missing about the machine"
	echo "Please check that the registration process was successful"
	make_term_normal
	exit 10
fi

# Get reference log line count + 1
COUNT=$(cat "$AIKDIR/$HASHAIK/refLog" | wc -l)
(( COUNT++ ))

# Generate nonce
if [ "$TESTMODE" -eq 1 ]
then
	echo "WARNING: Test mode activated, the nonce is zero, and therefore insecure"
	dd if=/dev/zero bs=1 count=20 of=$NONCE 2>/dev/null
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
	#PARAM="-q 20"
	PARAM=""
fi

RETRY=5
# Request the quote and the log file

echo "$SEND | nc $PARAM $1 $2"
echo "$SEND" | nc $PARAM $1 $2 > $FILE

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
echo $FILE

# Parse the file
./lfp.sh $AIK $QUOTE $LOG $FILE

echo "OUTPUT: $AIK\n $QUOTE \n$LOG"

ls -la $AIK
ls -la $QUOTE
ls -la $LOG

# Get received log line count
END=$(wc -l $LOG | cut -d " " -f 1)

TRUSTED=0
cp "$AIKDIR/$HASHAIK/hashPCR" "$HASHCPY"

PCRVALUE=$(cat "$AIKDIR/$HASHAIK/pcrValue")

HASHSTART=$(date +%s%N)

echo "$PCRVALUE" > $PUSH
RESULT=$(extend_pcr $HASHCPY $PUSH)
echo $RESULT > $NEWHASH
cp $NEWHASH $HASHCPY

HASHEND=$(date +%s%N)
QUOTESTART=$(date +%s%N)

# We need to verify the quote at each entry and see if one fits
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

	if [ -n "$TPM2" ];
	then
		echo "HERE IS TEH QUOTE FILE"
		cat $QUOTE
		cat $QUOTE > debugquote-verifier
		csplit --elide-empty-files --prefix quote $QUOTE  '/DELIMETER/+1' {*}
		sed 's/DELIMETER//g' -i quote0*
		QUOTEDATA=quote00
		QUOTESIG=quote01
		QUOTEPCRS=quote02
		ls -la quote0*
		cat $NONCE > mynonce
		truncate -s -1 $QUOTEDATA
		truncate -s -1 $QUOTESIG
		tpm2_checkquote --public="$AIKDIR/$HASHAIK/pubAIK" --qualification="$NONCE" --message="$QUOTEDATA" --signature="$QUOTESIG" --pcr="$QUOTEPCRS"
	else
		tpm_verifyquote "$AIKDIR/$HASHAIK/pubAIK" $NEWHASH $NONCE $QUOTE 2>/dev/null
	fi
	
	
	TPM_FAIL=$?
	if [ $TPM_FAIL -eq 0 ]
	then
		TRUSTED=1
	else
		if [ ! -s $QUOTE ]
		then
			echo "ERROR: remote party sent a response which didn't include a quote"
		fi
		echo "ERROR: tpm_verifyquote failed with $TPM_FAIL"
		exit 1
	fi
fi

RESULT=$(check_log_corruption $LOG)
if [ $? -eq 1 ]; then
	echo "Log files are corrupt and have no integrity. Bailing."
	exit 2
else
	echo "Template entries verified"
fi

ITER=1
while [ $ITER -le $END ]
do

	LOGVALUE=$(sed "${ITER}q;d" $LOG | cut -d " " -f 2)
	NEWPCR=$(echo "$PCRVALUE$LOGVALUE" | xxd -r -p | sha1sum | cut -d " " -f 1)
	PCRVALUE=$(echo $NEWPCR | tr '[:lower:]' '[:upper:]')
	echo "$PCRVALUE" > $PUSH

	echo "extend_pcr $cat $HASHCPY) $(cat $PUSH) $(cat $NEWHASH)"
	OUTPUT=$(extend_pcr $HASHCPY $PUSH)
	echo $OUTPUT > $NEWHASH
	PCR_FAIL=$?
	if [ $PCR_FAIL -gt 0 ]
	then
		echo "ERROR: Something went wrong when updating the PCR value ($PCR_FAIL)."
		echo "File a bug on http://github.com/adrianlshaw/LightVerifier"
		exit 5
	fi

	cp $NEWHASH $HASHCPY

	TRUSTED=0

	if [ -n "$TPM2" ]; then
		PCRFILE=$(mktemp)
		cat $QUOTE
		cat $QUOTE > debugquote-verifier
		csplit --elide-empty-files --prefix quote $QUOTE  '/DELIMETER/+1' {*}
		sed 's/DELIMETER//g' -i quote0*
		QUOTEDATA=quote00
		QUOTESIG=quote01
		QUOTEPCRS=quote02
		cat $NONCE > mynonce
		truncate -s -1 $QUOTEDATA
		truncate -s -1 $QUOTESIG

		tpm2_checkquote --public="$AIKDIR/$HASHAIK/pubAIK" --qualification="$NONCE" --message="$QUOTEDATA" --signature="$QUOTESIG" --pcr="$QUOTEPCRS"
		TPM_FAIL=$?
		if [ $TPM_FAIL -eq 1 ]; then
			echo "TPM quote failed to verify"
			exit 1
		else
			echo "TPM quote is valid"
			TRUSTED=1
		fi
		
	else
		tpm_verifyquote "$AIKDIR/$HASHAIK/pubAIK" $NEWHASH $NONCE $QUOTE 2>/dev/null
		if [ $TPM_FAIL -eq 1 ]; then
			echo "TPM quote failed to verify"
			exit 1
		else
			TRUSTED=1
		fi
	fi
	if [ $TRUSTED -eq 1 ]
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

	DBENTRIES=$(echo "$CONTENTRIES" | rev | cut -d " " -f 2 | rev \
		| cut -d ":" -f 2 | xargs redis-cli --raw -n $REDIS_MEASUREMENTS mget | \
		awk 'NF == 0 { print "@@@";next};{ print $0}')

	DBENT=$(echo "$DBENTRIES" | awk '$0 == "@@@" { next };{ print $0 }')
	ENTRYCOUNT=$(echo "$CONTENTRIES" | wc -l)
	VALIDCOUNT=$(echo "$DBENTRIES" | grep -c "@@@")
	VALIDCOUNT=$((ENTRYCOUNT-VALIDCOUNT))

	make_term_green
	echo "Mount path ID: $(echo $container)"
	echo
	make_term_normal
	echo "$VALIDCOUNT/$ENTRYCOUNT binaries found in database"
	echo
	echo "List of binaries not in database:"

	# Change termcolor to red
	make_term_red

	# Print packages out
	NOTIN=$(paste <(echo "$DBENTRIES" ) <(echo "$CONTENTRIES" | rev | cut -d " " -f 1 | rev))

	echo "$NOTIN" | grep @@@ | cut -f 2

	# Change termcolor to default colour
	make_term_normal

	PACKS=$(echo "$DBENT" | rev | cut -d "/" -f 1 | rev | \
				cut -d "@" -f 2 | cut -d "_" -f 1,2 | sort -u)

	echo
	echo "List of detected vulnerable packages:"
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

rm -rf $FILE $QUOTE $LOG $AIK $NEWHASH $PUSH $HASHCPY

exit 0
