library ieee;
use ieee.std_logic_1164.all;

package params is
    type CACHE_PARAMS_T is record
        LINE_SIZE           : natural;
        ICACHE_NUM_LINES    : natural;
        ICACHE_NUM_WAYS     : natural;
        ICACHE_TLB_SIZE     : natural;
        DCACHE_NUM_LINES    : natural;
        DCACHE_NUM_WAYS     : natural;
        DCACHE_TLB_SET_SIZE : natural;
        DCACHE_TLB_NUM_WAYS : natural;
    end record;

    constant CACHE_PARAMS_DEFAULT : CACHE_PARAMS_T := (
        LINE_SIZE           => 64,
        ICACHE_NUM_LINES    => 64,
        ICACHE_NUM_WAYS     => 2,
        ICACHE_TLB_SIZE     => 64,
        DCACHE_NUM_LINES    => 64,
        DCACHE_NUM_WAYS     => 2,
        DCACHE_TLB_SET_SIZE => 64,
        DCACHE_TLB_NUM_WAYS => 2
    );

end package;
