# LightVerifier [![Build Status](https://travis-ci.org/adrianlshaw/LightVerifier.svg?branch=master)](https://travis-ci.org/adrianlshaw/LightVerifier)

LightVerifier is a small set of tools to remotely verify the integrity of Linux systems. 
In essence, it uses a computer’s Trusted Platform Module (TPM) and some Linux kernel features to track what programs execute, 
in such a way that the software on the machine cannot lie about what’s running. Through cryptography, a measurement list is 
signed by the TPM and checked against a database of known good software measurements. 
This is known as a hardware-based remote attestation. 
Therefore, unauthorised software modifications or execution can be detected.

This project consists of a client (ra-agent) and server (verifier).
**Important note**:
This project currently only works with TPM 1.2, but 2.0 should be easy to incorporate.

```bash
$ apt-get install tpm-quote-tools netcat-traditional tpm-tools redis-tools \
		libtspi-dev autoconf make gcc
```

Once this depedency is installed on both client and server, 
you can start to install the LightVerifier tools.


## Setting up the verifier database

Choose a trusted and secure server for deploying the verifier. 
Install the dependencies for Debian:

```bash
$ apt-get install redis-server redis-tools debmirror parallel rpm2cpio
```

The measurementDB currently supports the creation of reference 
measurements for a few Linux distributions, including:

* Debian
* Ubuntu 
* CentOS 7

It would be nice to support a few LTS distributions, including 
RH-like distributions like CentOS. Pull requests are welcome. 

You can then run the builder for the reference database
(note: it could take a day to download packages from scratch):
```bash
$ cd measurementDB && ./buildStore.sh
```

CVE reports for Debian are supported by LightVerifier. 
You can make the CVE updater run frequently (e.g. every hour):
```bash
$ cp cve/* /etc/cron.hourly/
```

**Optional**: you can replicate an existing measurementDB database to another
verifier's Redis instance by performing the following instructions.

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

**Important note:** the database can only be set to one distro at a time.
The current default is Debian. To change this to another distro, change the
"DISTRO" variable in **downloadDeb.sh** and rerun the **buildstore.sh** script.

### Installing the remote attestation client

If you haven't already, then enable the TPM in the BIOS of the device
and then take ownership using **tpm_takeownership**.
Then proceed to make the Attestation Identity Key (AIK)
using the following commands from the included tpm-quote-tools package:

```bash
$ tpm_mkuuid aik.uuid
$ tpm_mkaik aik.blob aik.pub
$ tpm_loadkey aik.blob aik.uuid
```

Make sure the verifier database has been deployed (see README in measurementDB
  directory) and then run the "register.sh" script on each machine that
needs to be registered:

```bash
$ ./register.sh <aik.pub> <aik.uuid> <verifier_db_host_ip>
```
This will connect to the verifier database and record the necessary machine
information (DNS hostname, AIK public cert, the corresponding hash,
  and the boot aggregate digest).
**Importantly**, you must register before installing the IMA policy.
Note, that when you run the verify script in the next section, you should use
the hostname rather than the IP address.

Finally, we can set up the required integrity measurement policy.
The policy checks loaded executable files (programs,
shared libraries and executable files).
This should typically be written to ```/etc/ima/ima-policy```,
but it depends on your platform.
The systemd init system should load it automatically if it exists.

```
measure func=BPRM_CHECK
measure func=FILE_MMAP mask=MAY_EXEC
```
This example policy is known as a binary attestation policy, but 
other types of policy are possible to some degree.

## Remote Attestation Scripts

* verify.sh is the requester; its job is to fetch and analyse quotes and
logs to attest that a platform is trustworthy. You can run it with:
```bash
$ ./verify.sh <hostname> <port>
```
If successful, it will generate a file called report.log.

* ra-agent.sh is run on the machine to be monitored; 
it waits for a request from the verifier and sends both the log and TPM quote.
You can run it with:
```bash
$ ./ra-agent.sh <aik.pub> <aik.uuid> <port> 10
```

## How does it work

The aim of the project is to use both binary attestation and CVE databases to
evaluate trust for a given machine.

There are two parties:
* The **verifier** - this machine runs _verify.sh_ and contains the database
* The **attestor** - this machine runs _ra-agent.sh_ and logs activity with IMA

First, the verifier should build the database from the measurementDB.
This will store the SHA-1 hash of every ELF file in the
packages in a Redis database. We are working to add support 
for newer hash algorithms.

Secondly, the machine to verify should have IMA running and launch **ra-agent.sh**. 
This script will then wait for a request from the verifier and a new
instance will be created for each request.

When the machine needs to be verified, the verifier sends a nonce/challenge for freshness.
The sender will then create a quote (with the nonce used to prevent replay
attacks) and sends it along with the IMA log (unencrypted)

The verifier, using the IMA log, will recompute the value of the PCR for each
entry, and will check if the quote contains that same value. Once the right line
 has been reached, the verifier stops and returns that the distant server is the
  right one (verified by the AIK) and that the log provided is
   correct up to that line.

We can then use the database to check if the binaries that run on the machine
are genuine, and we can also check their potential vulnerabilities with the
CVE database.

In the event of the verifier never reaching the line confirming the quote,
the requester would deem the machine as untrustworthy,
and simply stop the process.

