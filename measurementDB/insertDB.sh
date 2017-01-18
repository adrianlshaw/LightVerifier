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
# grep cleans all empty string entries
# awk #1 puts SET in front of the data
# awk #2 formats in Redis protocol
# pipe sends data to Redis

PACK=$(mktemp -p ./)
VER=$(mktemp -p ./)
LIST=$(mktemp -p ./)

grep -v "da39a3ee5e6b4b0d3255bfef95601890afd80709" ./shaLog > $LIST

cat $LIST | cut -d " " -f 3 | cut -d "@" -f 2 | cut -d "_" -f 1 > $PACK
cat $LIST | cut -d " " -f 3 | cut -d "@" -f 2 | cut -d "_" -f 2 > $VER

echo "Inserting hashes..."

cat $LIST | awk '{print "SET","\""$1"\"","\""$2"\""}' | awk '{printf "%s\r\n", $0}' | redis-cli -n 10 --pipe

echo "Inserting packages and versions..."

paste $PACK $VER | awk '{print "SADD","\""$1"\"","\""$2"\""}' | awk '{printf "%s\r\n", $0}' | redis-cli -n 11 --pipe

rm $PACK
rm $VER
rm $LIST

rm ./shaLog

