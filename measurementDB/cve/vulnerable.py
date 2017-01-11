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

# This python script will get the latest CVE list from Debian and parse it to find vulnerable versions of packages
# These versions will be referenced in the Redis database containing the versions of packages already stored for trusted purposes

# Import json
import json
# Import urllib2 to download the file
import urllib2

# Download the file
response = urllib2.urlopen('https://security-tracker.debian.org/tracker/data/json')

# Load and parse the data in memory
data = json.load(response)

# for each package_version listed in the CVE file, print its vulnerabilities
for package in data.keys():
	for cve in data[package].keys():
		for release in data[package][cve]['releases'].keys():
			if data[package][cve]['releases'][release]['status']=='resolved':
				print " SADD " + "\"" + package + "_" + data[package][cve]['releases'][release]['fixed_version'] + "\" \"" + cve + "_" + data[package][cve]['releases'][release]['urgency'] + "\"\r\n\n"
			else:
				for repos in data[package][cve]['releases'][release]['repositories'].keys():
					 print " SADD " + "\"" + package + "_" + data[package][cve]['releases'][release]['repositories'][repos] + "\" \"" + cve + "_" + data[package][cve]['releases'][release]['urgency'] + "\"\r\n\n"
