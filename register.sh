#!/bin/bash
set -x
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
# Authors:	Adrian L. Shaw <adrianlshaw@acm.org>

extend_pcr(){
        echo -n "$1$2" | xxd -r -p | sha1sum | tr -d '-'
}


if [ $# -lt 3 ]
then
	echo "Usage: register <aik.pub> <aik.uuid> <verifier_db_host>"
	exit 1
fi

if [[ $EUID -ne 0 ]]; then
	echo "This program needs access to privileged information.You must be a root user" 2>&1
	exit 1
fi

# Parameters
AIKPUB=$1
AIKUUID=$2
VERIFIER=$3
HOSTNAME=$(hostname)

# Redis database number
REDIS_DB_NUM=15
TEMPDIR=$(mktemp -d)
LOG=$(head --lines 1 /sys/kernel/security/ima/ascii_runtime_measurements)
REFLOG=$(echo $LOG | base64)
if [[ -z "$REFLOG" ]]
then
	echo $REFLOG
	echo "Could not read the IMA boot aggregate, aborting."
	echo "Is IMA and securityfs enabled?"
	exit 1
fi

if [ -n "$TPM2" ];
then
	PCRHASH=$(echo $LOG | cut -d ' ' -f2)
	RESULT=$(extend_pcr 0000000000000000000000000000000000000000 $PCRHASH)
	echo $RESULT
	TPM_ERROR=$(echo $RESULT > $TEMPDIR/aik.pcrval)
else
	TPM_ERROR=$(tpm_getpcrhash $AIKUUID $TEMPDIR/aik.pcrhash $TEMPDIR/aik.pcrval 10 2>&1 | grep Error)
fi


if [[ -n "$TPM_ERROR" ]]
then
	echo "TPM error, aborting: $TPM_ERROR"
	exit 1
fi

PCRHASHBIN=$(cat $TEMPDIR/aik.pcrhash | base64)
PCRHASHASCII=$(cat $TEMPDIR/aik.pcrval | cut -d '=' -f 2 | base64)

PUBAIKHASH=$(sha1sum $AIKPUB | cut -d ' ' -f 1)
ENCPUBAIK=$(cat $AIKPUB | base64)

echo "PUBAIKHASH is $PUBAIKHASH"
echo "REFLOG is $REFLOG"
echo "PCRHASHBIN is $PCRHASHBIN"
echo "PCRHASHASCII is $PCRHASHASCII"

# Register hostname-to-AIK mapping
redis-cli -h $VERIFIER -n 13 set "$HOSTNAME" "$PUBAIKHASH"

# Delete existing host information
redis-cli -h $VERIFIER -n $REDIS_DB_NUM del "$PUBAIKHASH"

# Put the host information in the DB
redis-cli -h $VERIFIER -n $REDIS_DB_NUM RPUSH "$PUBAIKHASH" "$REFLOG"
redis-cli -h $VERIFIER -n $REDIS_DB_NUM RPUSH "$PUBAIKHASH" "$PCRHASHBIN"
redis-cli -h $VERIFIER -n $REDIS_DB_NUM RPUSH "$PUBAIKHASH" "$PCRHASHASCII"
redis-cli -h $VERIFIER -n $REDIS_DB_NUM RPUSH "$PUBAIKHASH" "$ENCPUBAIK"

rm -r $TEMPDIR
echo "Registered $HOSTNAME"
