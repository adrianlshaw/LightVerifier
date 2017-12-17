#!/bin/sh

# (c) Copyright 2017 Adrian L. Shaw
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

VERSION=1

if grep -sq 2.0 /sys/class/tpm/tpm0/device/description; then
	VERSION=2
else
    	VERSION=1
fi
