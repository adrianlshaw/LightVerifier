#!/bin/bash
#
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

DEBIAN="rsync://ftp.uk.debian.org/debian/"
UBUNTU="rsync://archive.ubuntu.com/ubuntu/"

# Default distro to sync is Debian
DISTRO=$DEBIAN

rsync -aiz --ignore-existing --include="*/" --include="*i386.deb" --include="*amd64.deb" --exclude="*" $DISTRO ./packages | egrep '^>' | cut -d " " -f 2 >> scan_files

# Sort the files to be hashed
sort -u scan_files > scn
mv scn scan_files
