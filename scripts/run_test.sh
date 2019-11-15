#!/bin/bash

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

Y=$(${MICROWATT_DIR}/scripts/hash.py tests/${TEST}.out)

cd $TMPDIR

cp ${MICROWATT_DIR}/tests/${TEST}.bin main_ram.bin

X=$( ${MICROWATT_DIR}/core_tb | ${MICROWATT_DIR}/scripts/hash.py )

if [ $X == $Y ]; then
	echo "$TEST PASS"
else
	echo "$TEST FAIL ********"
	exit 1
fi
