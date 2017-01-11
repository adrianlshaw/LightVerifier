# LightVerifier

A lightweight IMA agent and verification server that can be used for
TPM-based remote attestation (as well as other roots of trust).
Most people want to use it for TCG binary attestation, where the TPM logs
all the executable programs loaded on the platform, which can be remotely
verified against a set of reference measurements.
The more advanced version is the information flow tracking that we've been
researching (to reduce the number of
measurements needed to check).

To set things up manually, we require the traditional Netcat package:

```bash
$ apt-get install netcat-traditional tpm-tools libtspi-dev
```
Fetch the TPM quote tools from the SourceForge website,
build and install them:

```bash
$ git submodule init
$ git submodule update
$ cd tpm-quote-tools
$ autoreconf -i
$ ./configure
$ make
$ make install
$ cd ..
```
Enable the TPM in the BIOS and then take ownership using **tpm_takeownership**.
Then proceed to make the AIK using the following commands from the
tpm-quote-tools package:

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
$ ./ra-agent.sh <publicAIKcert> <AIKuuid> <port> 10
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

