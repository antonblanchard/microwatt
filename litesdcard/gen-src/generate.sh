#!/bin/bash

# vendor:sysclk
VENDORS="xilinx:100e6 lattice:48e6"

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

for i_clk in $VENDORS
do
    i=$(echo $i_clk | cut -d : -f 1)
    clk=$(echo $i_clk | cut -d : -f 2)
    TARGET_BUILD_PATH=$BUILD_PATH/$i
    TARGET_GEN_PATH=$GEN_PATH/$i
    rm -rf $TARGET_BUILD_PATH
    rm -rf $TARGET_GEN_PATH
    mkdir -p $TARGET_BUILD_PATH
    mkdir -p $TARGET_GEN_PATH

    echo "Generating $i in $TARGET_BUILD_PATH"
    (cd $TARGET_BUILD_PATH && litesdcard_gen --vendor $i --clk-freq $clk)

    cp $TARGET_BUILD_PATH/build/gateware/litesdcard_core.v $TARGET_GEN_PATH/
done
	 
