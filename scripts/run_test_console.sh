#!/bin/bash

# Runs a test and checks the console output against known good output

if [ $# -ne 1 ]; then
	echo "Usage: run_test.sh <test>"
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

${MICROWATT_DIR}/core_tb > /dev/null 2> test1.out || true

grep -v "Failed to bind debug socket" test1.out > test.out

cp ${MICROWATT_DIR}/tests/${TEST}.console_out exp.out

cp test.out /tmp
cp exp.out /tmp

diff -q test.out exp.out && echo "$TEST PASS" && exit 0

echo "$TEST FAIL ********"
exit 1
