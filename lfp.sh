#!/bin/sh

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
# LFP stands for Lightweight File Parser: it parses quotes (and logs !) files

if [ $# -lt 3 ]
then
	echo "Usage : lfp.sh pubaikhash quote logfile [input]"
	echo "If not specified, input will be read from STDIN"
	exit 1
fi

if [ $# -ge 4 -a -f "$4" ]
then
	INPUT="$4"
else
	INPUT="-"
fi

BUFFER=$(cat $INPUT)

echo "$BUFFER" | awk '/##SHA1 pubAIK##/{flag=1;next}/##Base64 encoded quote##/{flag=0}flag' > $1
echo "$BUFFER" | awk '/##Base64 encoded quote##/{flag2=1;next}/##IMA ASCII log file##/{flag2=0}flag2' | base64 -d > $2
echo "$BUFFER" | awk '/##IMA ASCII log file##/{flag3=1;next}/END/{flag3=0}flag3' > $3

exit 0
