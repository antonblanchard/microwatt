#!/bin/bash

dirty="0"

usage() {
	echo "$0 <file>"
	echo -e "\tSubstitute @hash@ and @dirty@ in <file> with gathered values."
}

if [ "$1" = "-h" -o "$1" = "--help" ] ;
then
	usage
	exit 1;
fi
if [ -z $1 ] ;
then
	usage
	exit 1;
fi

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
		version=$(git rev-parse --verify --short HEAD 2>/dev/null)
	fi
	if git diff-index --name-only HEAD |grep -qv '.git';
	then
		dirty="1"
	fi
	echo "hash=$version dirty=$dirty"
	sed -e "s/@hash@/$version/" -e "s/@dirty@/$dirty/" ${src}.in > ${src}
fi
