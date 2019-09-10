#!/usr/bin/python3

import urjtag;

def do_command(urc, op, addr, data):
    urc.set_dr_in(op,1,0)
    urc.set_dr_in(data,65,2)
    urc.set_dr_in(addr,73,66)
#    print("Sending:", urc.get_dr_in_string())
    urc.shift_dr()
    urc.set_dr_in(0x0,73,0)
    for x in range(5):
        urc.shift_dr()
#        print("Received:", urc.get_dr_out_string())
        rsp_code = urc.get_dr_out(1,0)
        if rsp_code == 0:
            return urc.get_dr_out(65,2)
        if rsp_code != 3:
            print("Weird response ! rsp=%x" % rsp_code);
    print("Timeout sending command !")

def do_read(urc, addr):
    return do_command(urc, 1, addr, 0)

def do_write(urc, addr, val):
    do_command(urc, 2, addr, val)

def main():
    # Init jtag
    #urjtag.loglevel( urjtag.URJ_LOG_LEVEL_ALL )

    urc = urjtag.chain()
    urc.cable("DigilentHS1")
    print('Cable frequency:', urc.get_frequency())
    #urc.tap_detect()
    #length = urc.len()
    #for i in range(0,urc.len()):
    #    idcode = urc.partid(0)
    #    print('[%d] 0x%08x' % (i, idcode))
    urc.addpart(6);
    print("Part ID: ", urc.partid(0))
    #urc.part(0)
    #urc.reset();
    urc.add_register("USER2_REG", 74);
    urc.add_instruction("USER2", "000011", "USER2_REG");
    urc.add_register("IDCODE_REG", 32);
    urc.add_instruction("IDCODE", "001001", "IDCODE_REG");
    # Send test command
    urc.set_instruction("IDCODE")
    urc.shift_ir()
    urc.shift_dr()
    print("Got:", hex(urc.get_dr_out()))

    urc.set_instruction("USER2")
    urc.shift_ir()

    print("Reading 0x00: %x" % do_read(urc, 0))
    print("Reading 0xaa: %x" % do_read(urc, 0xaa))
    

if __name__ == "__main__":
    main()
