# Microwatt eSim Integration

## Overview

This directory contains initial integration support for running the OpenPOWER Microwatt core inside the eSim/NGHDL co-simulation environment.

The integration flow enables Microwatt to be compiled with GHDL and wrapped for NGHDL/XSPICE-based simulation inside eSim.

## Files

### `microwatt_cosim.vhdl`

NGHDL-compatible wrapper for Microwatt.

Exposed ports:

* `clk` : Clock input
* `rst` : Reset input
* `uart_tx` : UART transmit output

### `compile_for_nghdl.sh`

Build script used to:

* Compile Microwatt using GHDL
* Build required helper objects
* Elaborate the wrapper for NGHDL/XSPICE integration

## Build Flow

Run:

```bash
bash esim/compile_for_nghdl.sh
```

Successful compilation generates the NGHDL-compatible elaborated design.

## eSim Workflow

1. Compile Microwatt using the provided script
2. Generate the NGHDL/XSPICE codemodel
3. Import the generated block into eSim
4. Create a schematic using:

   * clock pulse
   * reset pulse
   * UART probe
5. Run transient simulation

## Current Status

* Wrapper compilation successful
* NGHDL integration validated
* Basic schematic-level simulation setup completed

## Future Work

* Add memory and peripheral models
* Expand validation workflows
* Add example system-level designs
