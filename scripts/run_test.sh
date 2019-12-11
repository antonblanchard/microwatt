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

cd $TMPDIR

cp ${MICROWATT_DIR}/tests/${TEST}.bin main_ram.bin

${MICROWATT_DIR}/core_tb | sed 's/.*: //' | egrep '^(GPR[0-9]|LR |CTR |XER |CR [0-9])' | sort | grep -v GPR31 | grep -v XER > test.out || true

grep -v "^$" ${MICROWATT_DIR}/tests/${TEST}.out | sort | grep -v GPR31 | grep -v XER > exp.out

cp test.out /tmp
cp exp.out /tmp

diff -q test.out exp.out && echo "$TEST PASS" && exit 0

echo "$TEST FAIL ********"
exit 1
