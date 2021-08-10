#!/bin/bash

VENDORS="xilinx"

ME=$(realpath $0)
echo ME=$ME
MY_PATH=$(dirname $ME)
echo MYPATH=$MY_PATH
PARENT_PATH=$(realpath $MY_PATH/..)
echo PARENT=$PARENT_PATH
BUILD_PATH=$PARENT_PATH/build
mkdir -p $BUILD_PATH
GEN_PATH=$PARENT_PATH/generated
mkdir -p $GEN_PATH

for i in $VENDORS
do
    TARGET_BUILD_PATH=$BUILD_PATH/$i
    TARGET_GEN_PATH=$GEN_PATH/$i
    rm -rf $TARGET_BUILD_PATH
    rm -rf $TARGET_GEN_PATH
    mkdir -p $TARGET_BUILD_PATH
    mkdir -p $TARGET_GEN_PATH

    echo "Generating $i in $TARGET_BUILD_PATH"    
    (cd $TARGET_BUILD_PATH && litesdcard_gen --vendor $i)

    cp $TARGET_BUILD_PATH/build/gateware/litesdcard_core.v $TARGET_GEN_PATH/
done
	 
