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

# Note litesdcard/gen.py doesn't parse a YAML file, instead it takes
# a --vendor=xxx parameter, where xxx = xilinx or lattice.  If we
# want to generate litesdcard for ecp5 we'll have to invent a way to
# map arty to xilinx and ecp5 to lattice

for i in $TARGETS
do
    TARGET_BUILD_PATH=$BUILD_PATH/$i
    TARGET_GEN_PATH=$GEN_PATH/$i
    rm -rf $TARGET_BUILD_PATH
    rm -rf $TARGET_GEN_PATH
    mkdir -p $TARGET_BUILD_PATH
    mkdir -p $TARGET_GEN_PATH

    echo "Generating $i in $TARGET_BUILD_PATH"    
    (cd $TARGET_BUILD_PATH && litesdcard_gen)

    cp $TARGET_BUILD_PATH/build/gateware/litesdcard_core.v $TARGET_GEN_PATH/
done
	 
