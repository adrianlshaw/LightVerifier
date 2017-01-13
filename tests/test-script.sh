#/bin/bash
pkill ra-agent
pkill lqr.sh
pkill nc.traditional
pkill nc

HASHAIK="a7ca3d9fed8e1020770622d8bf2396274c608e78"

# Add "localhost" public AIK to to the trust store
redis-cli --raw -n 13 set "localhost" "$HASHAIK"

# Remove old information from the verifier 
redis-cli --raw -n 15 LTRIM "$HASHAIK" '-1' '0'
redis-cli --raw -n 15 DEL "$HASHAIK"

echo "Provisioning expected boot aggregate PCR and public AIK"
redis-cli --raw -n 15 RPUSH "$HASHAIK" "$(cat tests/refLog | base64)"
redis-cli --raw -n 15 RPUSH "$HASHAIK" "$(cat tests/hashPCR | base64)"
redis-cli --raw -n 15 RPUSH "$HASHAIK" "$(cat tests/pcrValue | base64)"
redis-cli --raw -n 15 RPUSH "$HASHAIK" "$(cat tests/pubAIK | base64)"

echo "Starting agent and verification server"

# Start the remote attestation agent
./ra-agent.sh tests/pubAIK --testmode 5000 10 &

# Start the verification test
AIKDIR=$PWD/tests ./lqr.sh localhost 5000 --testmode
RESULT=$?

# End test
exit $RESULT
