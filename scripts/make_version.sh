#!/bin/bash
#
# This script builds a git.vhdl which contains info on the SHA1 and
# dirty status of your git tree.  It always builds but only replaces
# the file if it's changed. This way we can use Makefile $(shell ..)
# to build it which happens before make does it's dependancy checks.
#

dirty="0"
version="00000000000000"

usage() {
	echo "$0 <file>"
	echo -e "\tSubstitute @hash@ and @dirty@ in <file> with gathered values."
}

src=$1

if test -e .git || git rev-parse --is-inside-work-tree > /dev/null 2>&1;
then
	version=$(git describe --exact-match 2>/dev/null)
	if [ -z "$version" ];
	then
		version=$(git describe 2>/dev/null)
	fi
	if [ -z "$version" ];
	then
		version=$(git rev-parse --verify --short=14 HEAD 2>/dev/null)
	fi
	if git diff-index --name-only HEAD |grep -qv '.git';
	then
		dirty="1"
	fi
#	echo "hash=$version dirty=$dirty"
fi

# Put it in a temp file and only update if it's change. This helps Make
sed -e "s/@hash@/$version/" -e "s/@dirty@/$dirty/" ${src}.in > ${src}.tmp
if diff -q ${src}.tmp ${src} >/dev/null 2>&1; then
    rm ${src}.tmp
else
    mv ${src}.tmp ${src}
fi
