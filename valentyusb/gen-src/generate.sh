#!/bin/sh

# This requires https://github.com/litex-hub/valentyusb  branch hw_cdc_eptri
# Tested with
# commit 912d8e6dc72d45e092e608ffcaabfeaaa6d4580f
# Date:   Wed Jan 6 09:42:42 2021 +0100

set -e

GENSRCDIR=$(dirname $0)
cd $GENSRCDIR

for b in orangecrab-85-0.2; do
    ./generate.py --dir ../generated/$b $b.yml
done
