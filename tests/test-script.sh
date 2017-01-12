#/bin/bash

# Add "localhost" AIK to to the trust store
#redis-cli --raw -n 13 set localhost a7ca3d9fed8e1020770622d8bf2396274c608e78

#redis-cli -h localhost -n 15 RPUSH "a7ca3d9fed8e1020770622d8bf2396274c608e78" "MTAgY2U4YmY0MTFhM2IzNWZjZmI0NTE3MjJmMTQyNzhlZGMzNmQxNDExZiBpbWEtbmcgc2hhMTpiNTI1MGVhNDZmNTFiMDUyMjVkM2FmMmU0MzY3ZTRmMWQwNzdmYzBmIGJvb3RfYWdncmVnYXRlCg=="
#redis-cli -h localhost -n 15 RPUSH "a7ca3d9fed8e1020770622d8bf2396274c608e78" "ADZRVVQyLk499gAAAADCCEAAAAAAAP////8AAwAEAAG+m+JHRZ+NT2PnVhT9Xoy4F2KsSA=="
#redis-cli -h localhost -n 15 RPUSH "a7ca3d9fed8e1020770622d8bf2396274c608e78" "MEQwN0FFNEZDMUVCQzEyMDRCNDg5ODdEQzUzODJFODI1RjZFMUI3Rgo="
#redis-cli -h localhost -n 15 RPUSH "a7ca3d9fed8e1020770622d8bf2396274c608e78" "IIBLAIBAQIBAgIEAAABHASCARwAAAABAAEAAgAAAAwAAAgAAAAAAgAAAAAAAAEAlHgy8TDVt6jn7jIEXT0hLXt3umK/JWD8daCWBUHX26qtv4hQQIHkxJZFGRW7KiA78Sfj+1RcgZP8puIjw+3NWaE0RDUlhMmi0K+HpR2LII3pbLqkmkUB14fOyhMJg/USTLOHbjuaBd7Z+Po9e7WQbCL2fARdKd8jxo9IBOBGFybHNqKYtwE+yyf3hLftMtpD0Qlw6Q2/3OT5huDd7kYgyF/IglL3fG6TTp4locvXlNNbgRorfMZQ504QdY+Ql1uXzWhAwnIx/hE8Gjez8Twqq+xYb2lnHggFr44BLPP4HniKYKuxS2/ZXTNlx2YkSFSk+ONe+3YoB9IZma56Zdf72w=="

echo "Deleting List from the verifier"
redis-cli --raw -n 15 LTRIM "$HASHAIK" '-1' '0'
redis-cli --raw -n 15 DEL "$HASHAIK"

echo "Inserting golden measurements"

redis-cli --raw -n 15 RPUSH "$HASHAIK" "$(cat tests/refLog | base64)"
redis-cli --raw -n 15 RPUSH "$HASHAIK" "$(cat tests/hashPCR | base64)"
redis-cli --raw -n 15 RPUSH "$HASHAIK" "$(cat tests/pcrValue | base64)"
redis-cli --raw -n 15 RPUSH "$HASHAIK" "$(cat tests/pubAIK | base64)"

echo "Done"

# Start the remote attestation agent
./ra-agent.sh tests/pubAIK --testmode 5000 10 &

# Start the verification test
AIKDIR=$PWD/tests ./lqr.sh localhost 5000 --testmode
RESULT=$?

#sleep 2

#AIKDIR=$PWD/tests ./lqr.sh localhost 5000 --testmode
#RESULT2=$?

# End test
exit $RESULT
#exit $(($RESULT + $RESULT2))
