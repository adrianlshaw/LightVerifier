#!/bin/bash
#
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

display_usage() { 
	echo "store-ppa, a non-interactive PPA downloader for Debian packages"
        echo "and stores the download list to an output file. That file can then "
	echo "be passed to the measureme-executables utility."	
	echo -e "\nUsage:\nstore-ppa <http_ppa_url> <output_file> \n" 
} 

# if less than two arguments supplied, display usage 
if [[ $# -le 1 || ( $# == "--help") ||  $# == "-h" ]]
then 
	display_usage
	exit 1
fi 
 
wget --mirror --convert-links --accept "*.deb" $1 && \
find . -name \*.deb -print > $2
