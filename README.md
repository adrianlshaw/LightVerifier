# LightVerifier

Here is a lightweight IMA agent and verification server that can be used for TPM-based remote attestation.
Most people want to use it for TCG binary attestation, where it logs all the executable programs loaded on the platform.
The more advanced version is the information flow tracking that we've been researching (to reduce the number of
measurements needed to check).

To set things up manually, we require the traditional Netcat package:

```bash
$ apt-get install netcat-traditional tpm-tools libtspi-dev
```
Download the TPM quote tools from the SourceForge website,
build and install them.

Enable the TPM in the BIOS and take ownership using **tpm_takeownership**. Then proceed to make the AIK using the following commands from the tpm-quote-tools package:a

```bash
$ tpm_mkuuid aik.uuid
$ tpm_mkaik aik.blob aik.pub
$ tpm_loadkey aik.blob aik.uuid
```

Make sure the verifier database has been deployed (see DebianMirror project) and then run the "register.sh" script on each machine that needs to be registered:

```bash
$ ./register.sh <aik.pub> <aik.uuid> <verifier_db_host_ip>
```
This will connect to the verifier database and record the necessary machine information (DNS hostname, AIK public cert, the corresponding hash, and the boot aggregate digest).
**Importantly**, you must register before installing the IMA policy.
Note, that when you run the verify script in the next section, you should use
the hostname rather than the IP address.

## Remote Attestation Scripts
* verify.sh is the requester; its job is to fetch and analyse quotes and logs to attest that a platform is trustworthy. You can run it with:
```bash
$ ./verify.sh <hostname> <port>
```
If successful, it will generate a file called report.log.

* lqs.sh is the sender; it waits for a signal to generate a quote and send it.
This runs on the platform to verify. You can run it with:
```bash
$ ./lqs.sh <publicAIKcert> <AIKuuid> <port> 10
```

## How does it work
The aim of the project is to use both binary attestation and CVE databases to
evaluate trust for a given machine.

There are two parties:
* The **verifier** - this machine runs _lqr.sh_ and contains the database
* The **attestor** - this machine runs _lqs.sh_ and logs activity with IMA

First, the verifier should build the database from the Debian mirror (other project). This will store the SHA-1 hash of every ELF file in the packages in a Redis database.

Secondly, the machine to verify should have IMA running (preferably in TCB mode
to ensure the chain of trust isn't broken) and launch lqs.sh. This script will
then wait for a request from the verifier and a new instance will be created for each request.

When the machine needs to be verified, the verifier sends a nonce for freshness. The sender will then create a quote (with the nonce used to prevent replay
attacks) and sends it along with the IMA log (unencrypted)

The verifier, using the IMA log, will recompute the value of the PCR for each entry, and will check if the quote contains that same value. Once the right line has been reached, the verifier stops and returns that the distant server is the right one (verified by the AIK) and that the log provided is correct up to that line.

We can then use the database to check if the binaries that run on the machine
are genuine, and we can also check their potential vulnerabilities with the CVE database.

In the event of the verifier never reaching the line confirming the quote, the requester would deem the machine as untrustworthy, and simply stop the process.

## Binary attestation policy for IMA

The supported policy checks loaded executable files (programs,
shared libraries and executable files).
This should typically be written to ```/etc/ima/ima-policy```,
but it depends on your platform.
The systemd init system should load it automatically if it exists.

```
measure func=BPRM_CHECK
measure func=FILE_MMAP mask=MAY_EXEC
```
## Information flow tracking

Apply the **ima-cont-id-subj.patch** kernel patch to a modern Linux kernel (e.g. 4.x).
Here is the IMA policy for tracking information flows (reads and writes)
as well as regular binaries:

```
dont_measure fsmagic=0x01021994

measure func=BPRM_CHECK
measure func=MMAP_CHECK mask=MAY_EXEC
measure func=FILE_CHECK mask=MAY_READ
measure func=FILE_CHECK mask=MAY_WRITE
```

We used SELinux to gain type enforcement information:
```
$ apt-get build-dep setools
$ apt-get install setools selinux-utils selinux-basics gawk auditd
```
AppArmor may be able to provide similar functionality based on file paths.

You need the SELinux type enforcement policy.
```bash
$ git clone https://github.com/TresysTechnology/refpolicy.git
$ cd refpolicy
$ git submodule init
$ git submodule update
```
Edit **build.conf** making sure that it refers to the **standard** policy
and the particular distro of choice, e.g. **debian**.

If you want to audit absolutely everything (this will degrade performance) then
you can change all rules in .te files to audit allow with a bit of Sed magic:

```bash
$ sed -i -e 's/^\(\|[[:space:]]\)allow[[:space:]]/\1auditallow /g'
```
Be aware that some rules may not accept the change. If errors arise, follow the trail of errors and replace auditallow to allow.

Then proceed with:

```bash
$ make conf
$ make all
$ make load
```
If you get an error during **make load** about lack of file,
then this is normal.
Just copy the file to the right place using:
```bash
$ cp /etc/selinux/refpolicy/contexts/files/file_contexts /etc/selinux/refpolicy/contexts/files/file_contexts.local
```
Proceed with the installation:
```bash
$ make install
```
Change the file at **/etc/selinux/config** and change the following line to:
```
SELINUXTYPE=refpolicy
```
This will make sure that our Tresys **refpolicy** is loaded by default.

Activate file system labeling (extended file attributes). The activate command
will add the right GRUB bootloader parameters. Then you should reboot:
```bash
$ touch /.autorelabel
$ selinux-activate
$ reboot
```

Check for any errors with the **seinfo** tool. You should see something like:

```
root@minined2:~# seinfo

Statistics for policy file: /etc/selinux/refpolicy/policy/policy.29
Policy Version & Type: v.29 (binary, non-mls)

   Classes:            95    Permissions:       254
   Sensitivities:       0    Categories:          0
   Types:            4278    Attributes:        289
   Users:               6    Roles:              14
   Booleans:          235    Cond. Expr.:       266
   Allow:          103705    Neverallow:          0
   Auditallow:         26    Dontaudit:       16895
   Type_trans:       8175    Type_change:        72
   Type_member:        16    Role allow:         29
   Role_trans:        210    Range_trans:         0
   Constraints:       106    Validatetrans:       0
   Initial SIDs:       27    Fs_use:             26
   Genfscon:           89    Portcon:           460
   Netifcon:            0    Nodecon:             0
   Permissives:         0    Polcap:              2

```

And with **sestatus** you should see something like this:

```
root@minined2:~/refpolicy# sestatus
SELinux status:                 enabled
SELinuxfs mount:                /sys/fs/selinux
SELinux root directory:         /etc/selinux
Loaded policy name:             refpolicy
Current mode:                   permissive
Mode from config file:          permissive
Policy MLS status:              disabled
Policy deny_unknown status:     denied
Max kernel policy version:      30
```

## Performance

The basic overhead of performing the protocol is about 2 seconds
(this factors in TPM command overhead) + network transfer time  
The time it takes to perform the verification of an IMA attestation is relative
to the line count of the IMA log.
As an estimate, a few hundred lines takes about a few seconds (in addition to
the the TPM overhead of 2 seconds). Therefore, periodic attestations are
advisable. Time it took to update the CVEs for the Debian reference hashes:
 0m22.154s

Debian (i386, amd64) results in in roughly 1,365,340 measurements, which
occupies around 300MB of RAM in Redis.
Getting the packages, hashing them and inserting them can take several hours.
