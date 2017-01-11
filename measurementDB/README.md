# measurementDB
Creates a reference database for verifying attestations.
Make sure there is plenty of disk space (at least 300GB?).

So far it supports the following OS distributions:
* Debian
* Ubuntu

**Important note:** the database can only be set to one distro at a time.
The current default is Debian. To change this to another distro, change the
"DISTRO" variable in **downloadDeb.sh** and rerun the buildstore.sh script.

## Install dependencies (Ubuntu)

Install Redis and Debmirror:
```bash
# apt-get install redis-server redis-tools debmirror parallel
```

## Building the database for the first time

Then run the builder for the reference database
(e.g. could take a day to download packages from scratch):

```bash
$ ./buildStore.sh
```
This will download the packages into the current working directory.

Make the CVE updater run frequently (e.g. every hour):
```bash
# cp cve/* /etc/cron.hourly/
```

## Replicating an existing database instance

In **/etc/redis/redis.conf** on the main server add the following line to allow
replication on all interfaces:
```
bind 0.0.0.0
```

In **/etc/redis/redis.conf** on the new slave add the hostname and port of the
master database, e.g.:

```
slaveof <your_master_ip_or_hostname> 6379
```
