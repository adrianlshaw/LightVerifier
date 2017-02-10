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

# Debian-based distributions
DEBIAN="rsync://ftp.uk.debian.org/debian/"
UBUNTU="rsync://archive.ubuntu.com/ubuntu/"

# RPM-based distributions, with an example mirror
CENTOS7="rsync://anorien.csc.warwick.ac.uk/CentOS/7/"

# Default distro to sync is Debian
DISTRO=$DEBIAN

rsync --archive --itemize-changes --compress --ignore-existing \
	--include="*/" \
	--include="*noarch*" \
	--include="*i386.deb" \
	--include="*amd64.deb*" \
	--include="*x86-64.rpm*" \
	--include="*x86_64.rpm*" \
	--exclude "*" \
	$DISTRO ./packages | egrep '^>' | cut -d " " -f 2 >> scan_files

# Sort the files to be hashed
sort -u scan_files > scn
mv scn scan_files
