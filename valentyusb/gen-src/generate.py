#!/usr/bin/env python3

# Based on valentyusb/sim/generate_verilog.py , modified
# for Microwatt

# This variable defines all the external programs that this module
# relies on.  lxbuildenv reads this variable in order to ensure
# the build will finish without exiting due to missing third-party
# programs.
LX_DEPENDENCIES = []

# Import lxbuildenv to integrate the deps/ directory
#import lxbuildenv

# Disable pylint's E1101, which breaks completely on migen
#pylint:disable=E1101

import argparse
import os
import yaml

#from migen import *
from migen import Module, Signal, Instance, ClockDomain, If
from migen.genlib.resetsync import AsyncResetSynchronizer
from migen.fhdl.specials import TSTriple
from migen.fhdl.bitcontainer import bits_for
from migen.fhdl.structure import ClockSignal, ResetSignal, Replicate, Cat

# from litex.build.sim.platform import SimPlatform
from litex.build.lattice import LatticePlatform
from litex.build.generic_platform import Pins, IOStandard, Misc, Subsignal
from litex.soc.integration.soc_core import SoCCore
from litex.soc.integration.builder import Builder
from litex.soc.interconnect import wishbone
from litex.soc.interconnect.csr import AutoCSR, CSRStatus, CSRStorage

from valentyusb import usbcore
from valentyusb.usbcore import io as usbio
from valentyusb.usbcore.cpu import dummyusb, cdc_eptri, eptri, epfifo
from valentyusb.usbcore.endpoint import EndpointType

_connectors = []

class _CRG(Module):
    def __init__(self, platform):
        clk = platform.request("clk")
        rst = platform.request("reset")

        clk12 = Signal()

        self.clock_domains.cd_sys = ClockDomain()
        self.clock_domains.cd_usb_12 = ClockDomain()
        self.clock_domains.cd_usb_48 = ClockDomain()
        self.clock_domains.cd_usb_48_to_12 = ClockDomain()

        clk48 = clk.clk48

        self.comb += self.cd_usb_48.clk.eq(clk48)
        self.comb += self.cd_usb_48_to_12.clk.eq(clk48)

        clk12_counter = Signal(2)
        self.sync.usb_48_to_12 += clk12_counter.eq(clk12_counter + 1)

        self.comb += clk12.eq(clk12_counter[1])

        self.comb += self.cd_sys.clk.eq(clk.clksys)
        self.comb += self.cd_usb_12.clk.eq(clk12)

        self.comb += [
            ResetSignal("sys").eq(rst),
            ResetSignal("usb_12").eq(rst),
            ResetSignal("usb_48").eq(rst),
        ]

class BaseSoC(SoCCore):

    def __init__(self, platform, io, sys_freq, output_dir="build", usb_variant='dummy', **kwargs):
        # Disable integrated RAM as we'll add it later
        self.integrated_sram_size = 0

        self.output_dir = output_dir

        platform.add_extension(io)

        self.submodules.crg = _CRG(platform)

        # prior to SocCore.__init__
        self.csr_map = {
            "uart":     0, # microwatt soc will remap addresses to 0
        }

        SoCCore.__init__(self, platform, sys_freq,
            cpu_type=None,
            integrated_rom_size=0x0,
            integrated_sram_size=0x0,
            integrated_main_ram_size=0x0,
            csr_address_width=14, csr_data_width=32,
            with_uart=False, with_timer=False)

        # Add USB pads
        usb_pads = platform.request("usb")
        usb_iobuf = usbio.IoBuf(usb_pads.d_p, usb_pads.d_n, usb_pads.pullup)
        self.comb += usb_pads.tx_en.eq(usb_iobuf.usb_tx_en)
        if usb_variant == 'eptri':
            self.submodules.usb = eptri.TriEndpointInterface(usb_iobuf, debug=True)
        elif usb_variant == 'epfifo':
            self.submodules.usb = epfifo.PerEndpointFifoInterface(usb_iobuf, debug=True)
        elif usb_variant == 'cdc_eptri':
            extra_args = {}
            passthrough = ['product', 'manufacturer']
            for p in passthrough:
                try:
                    extra_args[p] = kwargs[p]
                except KeyError:
                    pass
            self.submodules.uart = cdc_eptri.CDCUsb(usb_iobuf, debug=True, **extra_args)
        elif usb_variant == 'dummy':
            self.submodules.usb = dummyusb.DummyUsb(usb_iobuf, debug=True)
        else:
            raise ValueError('Invalid endpoints value. It is currently \'eptri\' and \'dummy\'')
        try:
            self.add_wb_master(self.usb.debug_bridge.wishbone)
        except AttributeError:
            pass

        if self.uart:
            self.comb += self.platform.request("interrupt").eq(self.uart.ev.irq)

        wb_ctrl = wishbone.Interface()
        self.add_wb_master(wb_ctrl)
        platform.add_extension(wb_ctrl.get_ios("wb_ctrl"))
        self.comb += wb_ctrl.connect_to_pads(self.platform.request("wishbone"), mode="slave")

def add_fsm_state_names():
    """Hack the FSM module to add state names to the output"""
    from migen.fhdl.visit import NodeTransformer
    from migen.genlib.fsm import NextState, NextValue, _target_eq
    from migen.fhdl.bitcontainer import value_bits_sign

    class My_LowerNext(NodeTransformer):
        def __init__(self, next_state_signal, next_state_name_signal, encoding, aliases):
            self.next_state_signal = next_state_signal
            self.next_state_name_signal = next_state_name_signal
            self.encoding = encoding
            self.aliases = aliases
            # (target, next_value_ce, next_value)
            self.registers = []

        def _get_register_control(self, target):
            for x in self.registers:
                if _target_eq(target, x[0]):
                    return x[1], x[2]
            raise KeyError

        def visit_unknown(self, node):
            if isinstance(node, NextState):
                try:
                    actual_state = self.aliases[node.state]
                except KeyError:
                    actual_state = node.state
                return [
                    self.next_state_signal.eq(self.encoding[actual_state]),
                    self.next_state_name_signal.eq(int.from_bytes(actual_state.encode(), byteorder="big"))
                ]
            elif isinstance(node, NextValue):
                try:
                    next_value_ce, next_value = self._get_register_control(node.target)
                except KeyError:
                    related = node.target if isinstance(node.target, Signal) else None
                    next_value = Signal(bits_sign=value_bits_sign(node.target), related=related)
                    next_value_ce = Signal(related=related)
                    self.registers.append((node.target, next_value_ce, next_value))
                return next_value.eq(node.value), next_value_ce.eq(1)
            else:
                return node
    import migen.genlib.fsm as fsm
    def my_lower_controls(self):
        self.state_name = Signal(len(max(self.encoding,key=len))*8, reset=int.from_bytes(self.reset_state.encode(), byteorder="big"))
        self.next_state_name = Signal(len(max(self.encoding,key=len))*8, reset=int.from_bytes(self.reset_state.encode(), byteorder="big"))
        self.comb += self.next_state_name.eq(self.state_name)
        self.sync += self.state_name.eq(self.next_state_name)
        return My_LowerNext(self.next_state, self.next_state_name, self.encoding, self.state_aliases)
    fsm.FSM._lower_controls = my_lower_controls


_io = [
    # Wishbone
    ("wishbone", 0,
        Subsignal("adr",   Pins(30)),
        Subsignal("dat_r", Pins(32)),
        Subsignal("dat_w", Pins(32)),
        Subsignal("sel",   Pins(4)),
        Subsignal("cyc",   Pins(1)),
        Subsignal("stb",   Pins(1)),
        Subsignal("ack",   Pins(1)),
        Subsignal("we",    Pins(1)),
        Subsignal("cti",   Pins(3)),
        Subsignal("bte",   Pins(2)),
        Subsignal("err",   Pins(1))
    ),
    ("usb", 0,
        Subsignal("d_p", Pins(1)),
        Subsignal("d_n", Pins(1)),
        Subsignal("pullup", Pins(1)),
        Subsignal("tx_en", Pins(1)),
    ),
    ("clk", 0,
        Subsignal("clk48", Pins(1)),
        Subsignal("clksys", Pins(1)),
    ),
    ("interrupt", 0, Pins(1)),
    ("reset", 0, Pins(1)),
]

def generate(core_config, output_dir, csr_csv):

    toolchain = core_config["toolchain"]
    if toolchain == "trellis":
        platform = LatticePlatform(core_config["device"], [], toolchain=toolchain)
    else:
        raise ValueError(f"Unknown config toolchain {toolchain}")

    soc = BaseSoC(platform, _io, core_config["sys_freq"],
                            usb_variant=core_config["usb_variant"],
                            cpu_type=None, cpu_variant=None,
                            output_dir=output_dir,
                            product=core_config["product"],
                            manufacturer="Microwatt")
    builder = Builder(soc, output_dir=output_dir,
                           csr_csv=csr_csv,
                           compile_software=False)
    vns = builder.build(run=False, build_name='valentyusb')
    soc.do_exit(vns)

def main():
    parser = argparse.ArgumentParser(description="Build standalone ValentyUSB verilog output")
    # parser.add_argument('variant', metavar='VARIANT',
    #                                choices=['dummy', 'cdc_eptri', 'eptri', 'epfifo'],
    #                                default='dummy',
    #                                help='USB variant. Choices: [%(choices)s] (default: %(default)s)' )
    parser.add_argument('--dir', metavar='DIRECTORY',
                                 default='build',
                                 help='Output directory (default: %(default)s)' )
    parser.add_argument('--csr', metavar='CSR',
                                 default='csr.csv',
                                 help='csr file (default: %(default)s)')
    parser.add_argument('config', type=argparse.FileType('r'),
                                 help='Input platform config file')
    args = parser.parse_args()

    core_config = yaml.load(args.config.read(), Loader=yaml.Loader)
    # XXX matt - not sure if this needed, maybe only for sim target?
    # add_fsm_state_names()
    output_dir = args.dir
    generate(core_config, output_dir, args.csr)

    print(
"""Build complete.  Output files:
    {}/gateware/valentyusb.v               Source Verilog file.
""".format(output_dir))

if __name__ == "__main__":
    main()
