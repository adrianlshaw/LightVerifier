#!/bin/bash
service redis-server start
pkill ra-agent
pkill lqr.sh
pkill nc.traditional
pkill nc

# Redis DB numbers
REDIS_MEASUREMENTS=10
REDIS_AIK=13
REDIS_AIK_INFO=15

HASHAIK="67b1ef23f175e0d40c18d32c6e64d8a16119407b"

# Since we can't host the entire database in the test environment,
# then let's add two reference measurements to the database
#redis-cli -n $REDIS_MEASUREMENTS set "620bfeeab8eef65f57c3ffd15945ee4363f5e4b9" "/bin/grep"
#redis-cli -n $REDIS_MEASUREMENTS set "3309e0cda7088ec9f2a3a5599e18551b07c1ed47" "/home/labs/LightVerifier/lqr.sh"

# Add "localhost" public AIK to to the trust store
redis-cli --raw -n $REDIS_AIK set "localhost" "$HASHAIK"

# Remove old information from the verifier
redis-cli --raw -n $REDIS_AIK_INFO LTRIM "$HASHAIK" '-1' '0'
redis-cli --raw -n $REDIS_AIK_INFO DEL "$HASHAIK"

echo "Provisioning expected boot aggregate PCR and public AIK"
redis-cli --raw -n $REDIS_AIK_INFO RPUSH "$HASHAIK" "$(cat tests/refLog | base64)"
redis-cli --raw -n $REDIS_AIK_INFO RPUSH "$HASHAIK" "$(cat tests/hashPCR | base64)"
redis-cli --raw -n $REDIS_AIK_INFO RPUSH "$HASHAIK" "$(cat tests/pcrValue | base64)"
redis-cli --raw -n $REDIS_AIK_INFO RPUSH "$HASHAIK" "$(cat tests/pubAIK | base64)"

echo "Starting agent and verification server"

# Start the remote attestation agent
./ra-agent.sh tests/pubAIK --testmode 5000 10 &

# Start the verification test
AIKDIR=$PWD/tests/2.0/ TPM2=1 ./lqr.sh localhost 5000 --testmode
RESULT=$?

# End test
exit $RESULT
