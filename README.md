<p align="center">
<img src="media/microwatt-title.png" alt="Microwatt">
</p>

# Microwatt

A tiny Open POWER ISA softcore written in VHDL 2008. It aims to be simple and easy
to understand.

## Simulation using ghdl
<p align="center">
<img src="http://neuling.org/microwatt-micropython.gif" alt="MicroPython running on Microwatt"/>
</p>

You can try out Microwatt/Micropython without hardware by using the ghdl simulator. If you want to build directly for a hardware target board, see below.

- Build micropython. If you aren't building on a ppc64le box you
  will need a cross compiler. If it isn't available on your distro
  grab the powerpc64le-power8 toolchain from https://toolchains.bootlin.com.
  You may need to set the CROSS_COMPILE environment variable
  to the prefix used for your cross compilers.  The default is
  powerpc64le-linux-gnu-.

```
git clone https://github.com/micropython/micropython.git
cd micropython
cd ports/powerpc
make -j$(nproc)
cd ../../../
```

  A prebuilt micropython image is also available in the micropython/ directory.

- Microwatt uses ghdl for simulation. Either install this from your
  distro or build it. Microwatt requires ghdl to be built with the LLVM
  or gcc backend, which not all distros do (Fedora does, Debian/Ubuntu
  appears not to). ghdl with the LLVM backend is likely easier to build.

  If building ghdl from scratch is too much for you, the microwatt Makefile
  supports using Docker or Podman.

- Next build microwatt:

```
git clone https://github.com/antonblanchard/microwatt
cd microwatt
make
```

   To build using Docker:
```
make DOCKER=1
```

   and to build using Podman:

```
make PODMAN=1
```

- Link in the micropython image:

```
ln -s ../micropython/ports/powerpc/build/firmware.bin main_ram.bin
```

  Or if you were using the pre-built image:

```
ln -s micropython/firmware.bin main_ram.bin
```

- Now run microwatt, sending debug output to /dev/null:

```
./core_tb > /dev/null
```

## Synthesis on Xilinx FPGAs using Vivado

- Install Vivado (I'm using the free 2022.1 webpack edition).

- Setup Vivado paths:

```
source /opt/Xilinx/Vivado/2022.1/settings64.sh
```

- Install FuseSoC:

```
pip3 install --user -U fusesoc
```
Fedora users can get FuseSoC package via
```
sudo dnf copr enable sharkcz/danny
sudo dnf install fusesoc
```

- If this is your first time using fusesoc, initialize fusesoc. 
  This is needed to be able to pull down fussoc library components referenced 
  by microwatt. Run

- If you use artix as a reference, like the uart16550 example below, you need to install the corresponding vivado package.

<p align="center">
<img src="https://github.com/user-attachments/assets/0390507c-cdea-4fce-b2f6-d58830bea176" alt="MicroPython running on Microwatt"/>
</p>

```
fusesoc init
fusesoc library add microwatt /path/to/microwatt
fusesoc fetch uart16550
```

- Build using FuseSoC. For hello world (Replace nexys_video with your FPGA board such as --target=arty_a7-100):
  You may wish to ensure you have [installed Digilent Board files](https://reference.digilentinc.com/vivado/installing-vivado/start#installing_digilent_board_files) 
  or appropriate files for your board first.

```
fusesoc run --target=nexys_video microwatt --memory_size=16384 --ram_init_file=/path/to/microwatt/fpga/hello_world.hex
```
You should then be able to see output via the serial port of the board (/dev/ttyUSB1, 115200 for example assuming standard clock speeds). There is a know bug where initial output may not be sent - try the reset (not programming button) on your board if you don't see anything.

- To build micropython (currently requires 1MB of BRAM eg an Artix-7 A200):

```
fusesoc run --target=nexys_video microwatt
```

## Linux on Microwatt

Mainline Linux supports Microwatt as of v5.14. The Arty A7 is the best tested
platform, but it's also been tested on the OrangeCrab and ButterStick.

<p align="center">
<img src="https://github.com/user-attachments/assets/b26dbdaf-aa93-4ecd-a66d-d3bd29f05146" alt="MicroPython running on Microwatt"/>
</p>

1. Use buildroot to create a userspace

   A small change is required to glibc in order to support the VMX/AltiVec-less
   Microwatt, as float128 support is mandiatory and for this in GCC requires
   VSX/AltiVec. This change is included in Joel's buildroot fork, along with a
   defconfig:
   ```
   git clone -b microwatt-2022.08 https://github.com/shenki/buildroot
   cd buildroot
   make ppc64le_microwatt_defconfig
   make
   ```

   The output is `output/images/rootfs.cpio`.

2. Build the Linux kernel
   ```
   git clone https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
   cd linux
   make ARCH=powerpc microwatt_defconfig
   make ARCH=powerpc CROSS_COMPILE=powerpc64le-linux-gnu- \
     CONFIG_INITRAMFS_SOURCE=path/to/buildroot/output/images/rootfs.cpio -j`nproc`
   ```

   The output is `arch/powerpc/boot/dtbImage.microwatt.elf`.

3. Build gateware using FuseSoC

   First configure FuseSoC as above.
   ```
   fusesoc run --build --target=arty_a7-100 microwatt --no_bram --memory_size=0
   ```

   The output is `build/microwatt_0/arty_a7-100-vivado/microwatt_0.bit`.

4. Program the flash

   This operation will overwrite the contents of your flash.

   For the Arty A7 A100, set `FLASH_ADDRESS` to `0x400000` and pass `-f a100`.

   For the Arty A7 A35, set `FLASH_ADDRESS` to `0x300000` and pass `-f a35`.
   ```
   sudo microwatt/openocd/flash-arty -f a100 build/microwatt_0/arty_a7-100-vivado/microwatt_0.bit
   sudo microwatt/openocd/flash-arty -f a100 dtbImage.microwatt.elf -t bin -a $FLASH_ADDRESS
   ```

5. Connect to the second USB TTY device exposed by the FPGA

   ```
   sudo minicom -D /dev/ttyUSB1
   ```
   If the cable was plugged in, unplug it when you're done and you'll see the serial console on the minicomputer. If you can't see the serial console, see below.
   
   go to Serial Port Setup; last two lines are Hardware and Software Flow control; just set NO both)

   - https://stackoverflow.com/questions/3913246/cannot-send-character-with-minicom
   ```
   sudo minicom -s; 
   ```
   
   The gateware has firmware that will look at `FLASH_ADDRESS` and attempt to
   parse an ELF there, loading it to the address specified in the ELF header
   and jumping to it.

6. SSH login

  Check  your DHCP server

  ```
  $ cat /etc/default/isc-dhcp-server
  # Defaults for isc-dhcp-server (sourced by /etc/init.d/isc-dhcp-server)
  # Path to dhcpd's config file (default: /etc/dhcp/dhcpd.conf).
  #DHCPDv4_CONF=/etc/dhcp/dhcpd.conf
  #DHCPDv6_CONF=/etc/dhcp/dhcpd6.conf
  # Path to dhcpd's PID file (default: /var/run/dhcpd.pid).
  #DHCPDv4_PID=/var/run/dhcpd.pid
  #DHCPDv6_PID=/var/run/dhcpd6.pid
  # Additional options to start dhcpd with.
  #	Don't use options -cf or -pf here; use DHCPD_CONF/ DHCPD_PID instead
  #OPTIONS=""
  # On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
  #	Separate multiple interfaces with spaces, e.g. "eth0 eth1".
  INTERFACESv4="enp6s0"
  INTERFACESv6="enp6s0"
  ```

  ```
  $ sudo ifconfig enp6s0 192.168.0.1
  $  sudo /etc/init.d/isc-dhcp-server restart
  $ dhcp-lease-list
  To get manufacturer names please download http://standards.ieee.org/regauth/oui/oui.txt to /usr/local/etc/oui.txt
  Reading leases from /var/lib/dhcp/dhcpd.leases
  MAC                IP              hostname       valid until         manufacturer        
  ===============================================================================================
  56:1a:c0:3b:c0:f2  192.168.0.6     microwatt      2024-08-17 11:52:24 -NA-  
  ```

  You can access it by first creating a new user named root on the serial port. For example, I created a user named microwatt

  ```
  $ ssh microwatt@192.168.0.6
  microwatt@192.168.0.6's password: 
  
  $ uname -a
  Linux microwatt 6.11.0-rc3-00279-ge5fa841af679 #3 Sat Aug 17 19:45:10 KST 2024 ppc64le GNU/Linux

  $ cat /etc/os-release 
  NAME=Buildroot
  VERSION=2022.08-7-g119e742cb0
  ID=buildroot
  VERSION_ID=2022.08
  PRETTY_NAME="Buildroot 2022.08"

  $ cat /proc/cpuinfo 
  processor	: 0
  cpu		: Microwatt
  clock		: 100.000000MHz
  revision	: 0.0 (pvr 0063 0000)
  
  timebase	: 100000000
  platform	: microwatt
  ```

## Testing

- A simple test suite containing random execution test cases and a couple of
  micropython test cases can be run with:

```
make -j$(nproc) check
```

## Issues

- There are a few instructions still to be implemented:
  - Vector/VMX/VSX
