#!/usr/bin/env bash

# (c) Copyright 2018 Adrian L. Shaw <adrianlshaw@acm.org>
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

if [ $# -eq 0 ]; then
	echo "read_registration <hostname>>"
	exit 1;
fi

REDIS_AIK_INFO=15
REDIS_AIK_DB=13
HASHAIK=$(redis-cli --raw -n $REDIS_AIK_DB get "$1")

echo "AIK hash: $HASHAIK"
echo "Boot aggregate: $(redis-cli --raw -n $REDIS_AIK_INFO LINDEX "$HASHAIK" '0' | base64 -d)"
echo "PCR10: $(redis-cli --raw -n $REDIS_AIK_INFO LINDEX "$HASHAIK" '2' | base64 -d)"
echo "Reflog (base64): $(redis-cli --raw -n $REDIS_AIK_INFO LINDEX "$HASHAIK" '1')"
