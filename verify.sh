#!/bin/bash
#set -eu
#set -o pipefail

extend_pcr(){
        echo -n "$1$2" | xxd -r -p | sha1sum | tr -d '-' | xargs
}

split(){
	INPUT=""
	if [ $# -ge 4 -a -f "$4" ];
	then
		INPUT="$4"
	else
		INPUT="-"
	fi

	BUFFER=$(cat $INPUT)

	echo "$BUFFER" | awk '/##SHA1 pubAIK##/{flag=1;next}/##Base64 encoded quote##/{flag=0}flag' > $1
	echo "$BUFFER" | awk '/##Base64 encoded quote##/{flag2=1;next}/##IMA ASCII log file##/{flag2=0}flag2' | base64 -d > $2
	echo "$BUFFER" | awk '/##IMA ASCII log file##/{flag3=1;next}/END/{flag3=0}flag3' > $3
}

if [ ! $# -eq 3 ]
then
        echo "Usage: lqr.sh <hostname> <port> <ak.pub>"
        exit 1
fi

TESTMODE=0
FILE=$(mktemp)
QUOTE=$(mktemp)
LOG=$(mktemp)
AIK=$(mktemp)
NEWHASH=$(mktemp)
NONCE=$(mktemp)
START=$(date +%s%N)
TPM2=1
PCR10=
INITPCR="0000000000000000000000000000000000000000"
PCR="$INITPCR"
TRUSTED=0
AIKPUB=$3
AIKPUBHASH=$(sha1sum "$AIKPUB" | cut -d ' ' -f1)
DIR="/tmp/$AIKPUBHASH/"
COUNT=$(cat "$DIR/lastgoodline" || echo 0)

if [ -f "$DIR/lastgoodpcr" ]; then
	PCR=$(cat "$DIR/lastgoodpcr")
fi

mkdir "$DIR" >/dev/null 2>&1 || true

# Generate nonce
if [ "$TESTMODE" -eq 1 ]
then
        echo "WARNING: Test mode activated, the nonce is zero, and therefore insecure"
        dd if=/dev/zero bs=1 count=20 of="$NONCE" 2>/dev/null
else
        openssl rand 20 > "$NONCE"
fi

# Add the line number after the nonce to only get the new log part
SEND=$(echo $(cat "$NONCE" | base64) "$COUNT")

# Send request
echo "$SEND" | nc "$1" "$2" > "$FILE"

TRANSFER=$(date +%s%N)

# Unmarshal response
split "$AIK" "$QUOTE" "$LOG" "$FILE"

if [ -n "$TPM2" ];
then
                cat $QUOTE > debugquote-verifier
                csplit --elide-empty-files --quiet --prefix quote $QUOTE  '/DELIMETER/+1' {*}
                sed 's/DELIMETER//g' -i quote0*
                QUOTEDATA=quote00
                QUOTESIG=quote01
                QUOTEPCRS=quote02
                truncate -s -1 $QUOTEDATA
                truncate -s -1 $QUOTESIG
                RESULT=$(tpm2_checkquote --public="$AIKPUB" \
			--qualification="$NONCE" \
			--message="$QUOTEDATA" \
			--signature="$QUOTESIG" \
			--pcr="$QUOTEPCRS" )
                TPM_FAIL=$?
		if [ $TPM_FAIL -eq 0 ]; then
			PCR10=$(echo "$RESULT" | grep 10: | cut -d ':' -f2 | xargs | cut -d 'x' -f2 | tr '[:upper:]' '[:lower:]')
                        echo "TPM quote has PCR10 value $PCR10"
		else
			echo "Failed to verify TPM signature"
			exit 1
		fi

else
                tpm_verifyquote "$AIKDIR/$HASHAIK/pubAIK" $NEWHASH $NONCE $QUOTE 2>/dev/null
                TPM_FAIL=$?
fi

# Check if the PCR has changed
if [ "$PCR" == "$PCR10" ]; then
	echo "System has not changed since last integrity check"
	TRUSTED=1
fi

# Check the integrity of the log
LINENUM=$((1 + $COUNT))
while read line; do
                FILE=$(mktemp)
                printf '\32\0\0\0' > "$FILE"
                printf "sha1:\0" >> "$FILE" # Alg + colon and nul byte
                echo $line | cut -d ' ' -f4 | cut -d ':' -f2 | xxd -r -p >> $FILE # File digest
                FILEPATHLEN=$(echo $line | cut -d ' ' -f5 | wc -c)
                printf "%08x" $FILEPATHLEN | tac -rs .. |  xxd -r -p >> $FILE
                echo -n $line | cut -d ' ' -f5 | tr -d "\n" >> $FILE # File 
                printf "\0" >> "$FILE"
                #echo "Comparing  $(echo $line | cut -d ' ' -f2) with $(sha1sum $FILE)"
                EXPECTEDPCR=$(echo "$line" | cut -d ' ' -f2)
                CALCULATEDPCR=$(sha1sum "$FILE" | cut -d ' ' -f1)
                rm -f "$FILE"

		if [ "$EXPECTEDPCR" != "$CALCULATEDPCR" ]; then
                        echo "Aborting. Template hash is incorrect on line $line"
                        return 1
                fi

		NEWPCR=$(extend_pcr "$PCR" "$CALCULATEDPCR")
		PCR=$NEWPCR

		echo "$LINENUM Checking $PCR against $PCR10"

		if [ "$PCR" == "$PCR10" ]; then
			echo Match!
			TRUSTED=1
			(( LINENUM++ ))
			echo $LINENUM > "$DIR/lastgoodline"
			echo "$PCR" > "$DIR/lastgoodpcr"
			break
		fi
		(( LINENUM++ ))
done <"$LOG"

make_term_normal(){
        NC='\033[0m' # No Color
        printf "${NC}"
}

make_term_red(){
	RED='\033[0;31m'
	printf "${RED}"
}

make_term_green(){
        GREEN='\033[0;32m'
        printf "${GREEN}"
}

if [ "$TRUSTED" -eq 0 ]; then
	rm -rf "$DIR"
	make_term_red
	echo Untrusted log
	exit 1
fi

echo Log has integrity. Now checking executables.

ENTRYCOUNT=$(echo "$LOG" | wc -l)
REDIS_MEASUREMENTS=10
DBENTRIES=$(echo "$LOG" | rev | cut -d " " -f 2 | rev | cut -d ":" -f 2 | xargs redis-cli --raw -n 10 mget  | awk 'NF == 0 { print "@@@";next};{ print $0}')

DBENT=$(echo "$DBENTRIES" | awk '$0 == "@@@" { next };{ print $0 }')
ENTRYCOUNT=$(echo "$LOG" | wc -l)
VALIDCOUNT=$(echo "$DBENTRIES" | grep -c "@@@")
VALIDCOUNT=$((ENTRYCOUNT-VALIDCOUNT))

echo "$VALIDCOUNT/$ENTRYCOUNT binaries found in database"

make_term_red # Change termcolor to red

# Print packages out
NOTIN=$(paste <(echo "$DBENTRIES" ) <(echo "$LOG" | rev | cut -d " " -f 1 | rev))

echo "$NOTIN" | grep @@@ | cut -f 2
make_term_normal # Change termcolor to default colour

PACKS=$(echo "$DBENT" | rev | cut -d "/" -f 1 | rev | \
                                cut -d "@" -f 2 | cut -d "_" -f 1,2 | sort -u)

echo
echo "List of detected vulnerable packages:"

for packid in $PACKS
do

	RESULT=$(redis-cli --raw -n 12 exists "$packid")
        if [ "$RESULT" -eq 1 ]
        then
        	echo "Package name :"
                echo "$packid"
                echo "Severity of CVEs :"
                redis-cli --raw -n 12 smembers "$packid"
                echo
        fi
done


FORMATEND=$(date +%s%N)

FINISH=$(date +%s%N)

echo "Download time : $(( ($TRANSFER - $START)/1000000 )) ms"
echo "Processing time : $(( ($FINISH - $TRANSFER)/1000000 )) ms"

#echo "Hash time : $(( ($HASHEND - $HASHSTART)/1000000 )) ms"
#echo "Quote time : $(( ($QUOTEEND - $QUOTESTART)/1000000 )) ms"
#echo "Format time : $(( ($FORMATEND - $FORMATSTART)/1000000 )) ms"

echo "Total time : $(( ($FINISH - $START)/1000000 )) ms"
