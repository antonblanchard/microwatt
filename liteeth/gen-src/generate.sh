#!/bin/bash

TARGETS=arty

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

for i in $TARGETS
do
    TARGET_BUILD_PATH=$BUILD_PATH/$i
    TARGET_GEN_PATH=$GEN_PATH/$i
    rm -rf $TARGET_BUILD_PATH
    rm -rf $TARGET_GEN_PATH
    mkdir -p $TARGET_BUILD_PATH
    mkdir -p $TARGET_GEN_PATH

    echo "Generating $i in $TARGET_BUILD_PATH"    
    liteeth_gen --output-dir=$TARGET_BUILD_PATH $MY_PATH/$i.yml

    cp $TARGET_BUILD_PATH/gateware/liteeth_core.v $TARGET_GEN_PATH/
done
	 
