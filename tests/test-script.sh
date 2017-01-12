#/bin/bash

# Add "localhost" AIK to to the trust store
redis-cli --raw -n 13 set localhost a7ca3d9fed8e1020770622d8bf2396274c608e78

# Start the remote attestation agent
../ra-agent.sh aik.pub --testmode 5000 10 &

# Start the verification test
AIKDIR=$PWD ../lqr.sh localhost 5000 --testmode

exit 0
