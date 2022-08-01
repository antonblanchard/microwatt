#!/bin/bash

# Runs a test and checks the console output against known good output

if [ $# -ne 1 ]; then
	echo "Usage: run_test_console.sh <test>"
	exit 1
fi

TEST=$1

TMPDIR=$(mktemp -d)

function finish {
	rm -rf "$TMPDIR"
}

trap finish EXIT

MICROWATT_DIR=$PWD

cd $TMPDIR

cp ${MICROWATT_DIR}/tests/${TEST}.bin main_ram.bin

${MICROWATT_DIR}/core_tb > console.out 2> test1.out || true

# check metavalues aren't increasing
COUNT=$(grep -c 'metavalue' console.out)
EXP=$(cat ${MICROWATT_DIR}/tests/${TEST}.metavalue)
if [[ $COUNT -gt $EXP ]] ; then
   echo "$TEST FAIL ******** metavalues increased from $EXP to $COUNT"
   exit 1
fi

grep -v "Failed to bind debug socket" test1.out > test.out

cp ${MICROWATT_DIR}/tests/${TEST}.console_out exp.out

diff -q test.out exp.out && echo "$TEST PASS" && exit 0

echo "$TEST FAIL ******** Console output changed"
exit 1
