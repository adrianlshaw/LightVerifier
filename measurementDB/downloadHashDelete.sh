#! /usr/bin/env bash
# 
# (c) Copyright 2018 Adrian L. Shaw
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

echo "Downloading latest files..."

FILES=$(rsync --dry-run  --archive --itemize-changes --compress --ignore-existing --include="*/" --include="*noarch*" --include="*i386.deb" --include="*amd64.deb*" --include="*x86-64.rpm*" --include="*x86_64.rpm*" --exclude "*" rsync://ftp.uk.debian.org/debian/  | cut -d ':' -f3 | cut -d ' ' -f2 | grep -E '.deb$|.rpm$')


foo() {
	DISTRO="rsync://ftp.uk.debian.org/debian/"
	DISTRO="${DISTRO/rsync/"http"}"
	URL="$DISTRO$1"
	#echo "DEBUG $URL"
	wget "$URL" -P /tmp/
	dlfile="/tmp/$(basename $URL)"
	#echo "DLFILE IS $dlfile"
	TEMP=$(mktemp -d --tmpdir=/tmp)
	dpkg -x $dlfile $TEMP >/dev/null 2>&1
	find "$TEMP" -type f ! -empty | sed '/^\s*$/d' | xargs file | egrep -i "ELF|script"  | cut -d ":" -f 1 | xargs sha1sum | sed "s/$/@$(basename $dlfile | sed -e 's/[\/&]/\\&/g')/g" >> hashes
	
	rm -rf "$TEMP" # remove extracted files
	rm "$dlfile" # remove downloaded archive
}

export -f foo

rm -f hashes
echo $FILES | tr " " "\n" | parallel foo {} #>> hashes
