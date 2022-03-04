# 3D Maze Game

Based on: <https://github.com/programmerjake/rv32/tree/v0.1.0.1-alpha/software>

# Run without FPGA/hardware-simulation

Resize your terminal to be at least 100x76.

Building:
```bash
cd usb_3d_game
make usb_3d_game_emu
```

Running:
```bash
./usb_3d_game_emu
```

# Run on OrangeCrab v0.2.1

Set the OrangeCrab into firmware upload mode by plugging it in to USB while the button is pressed, then run the following commands:

Building/Flashing:
```bash
(cd usb_3d_game; make)
sudo make FPGA_TARGET=ORANGE-CRAB-0.21 dfuprog DOCKER=1 LITEDRAM_GHDL_ARG=-gUSE_LITEDRAM=false RAM_INIT_FILE=usb_3d_game/usb_3d_game.hex MEMORY_SIZE=$((1<<18))
```

Then, in a separate terminal that you've resized to be at least 100x76, run (replacing ttyACM0 with whatever serial device the OrangeCrab is):
```bash
sudo tio /dev/ttyACM0
```

# Controls

Use WASD or the Arrow keys to move around. Press Ctrl+C to quit or restart.

The goal is a set of flashing blocks, nothing special yet happens when you reach them though.