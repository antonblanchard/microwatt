library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.decode_types.all;

entity multiply is
    generic (
        PIPELINE_DEPTH : natural := 16
        );
    port (
        clk   : in std_logic;

        m_in  : in Execute1ToMultiplyType;
        m_out : out MultiplyToExecute1Type
        );
end entity multiply;

architecture behaviour of multiply is
    signal m: Execute1ToMultiplyType;

    type multiply_pipeline_stage is record
        valid     : std_ulogic;
        insn_type  : insn_type_t;
        data      : signed(129 downto 0);
        write_reg : std_ulogic_vector(4 downto 0);
        rc        : std_ulogic;
	oe        : std_ulogic;
	is_32bit  : std_ulogic;
	xerc      : xer_common_t;
    end record;
    constant MultiplyPipelineStageInit : multiply_pipeline_stage := (valid => '0',
								     insn_type => OP_ILLEGAL,
								     rc => '0', oe => '0',
								     is_32bit => '0',
								     xerc => xerc_init,
								     data => (others => '0'),
								     others => (others => '0'));

    type multiply_pipeline_type is array(0 to PIPELINE_DEPTH-1) of multiply_pipeline_stage;
    constant MultiplyPipelineInit : multiply_pipeline_type := (others => MultiplyPipelineStageInit);

    type reg_type is record
        multiply_pipeline : multiply_pipeline_type;
    end record;

    signal r, rin : reg_type := (multiply_pipeline => MultiplyPipelineInit);
begin
    multiply_0: process(clk)
    begin
        if rising_edge(clk) then
            m <= m_in;
            r <= rin;
        end if;
    end process;

    multiply_1: process(all)
        variable v : reg_type;
        variable d : std_ulogic_vector(129 downto 0);
        variable d2 : std_ulogic_vector(63 downto 0);
	variable ov : std_ulogic;
    begin
        v := r;

        m_out <= MultiplyToExecute1Init;

        v.multiply_pipeline(0).valid := m.valid;
        v.multiply_pipeline(0).insn_type := m.insn_type;
        v.multiply_pipeline(0).data := signed(m.data1) * signed(m.data2);
        v.multiply_pipeline(0).write_reg := m.write_reg;
        v.multiply_pipeline(0).rc := m.rc;
        v.multiply_pipeline(0).oe := m.oe;
        v.multiply_pipeline(0).is_32bit := m.is_32bit;
        v.multiply_pipeline(0).xerc := m.xerc;

        loop_0: for i in 1 to PIPELINE_DEPTH-1 loop
            v.multiply_pipeline(i) := r.multiply_pipeline(i-1);
        end loop;

        d := std_ulogic_vector(v.multiply_pipeline(PIPELINE_DEPTH-1).data);
	ov := '0';

	-- TODO: Handle overflows
        case_0: case v.multiply_pipeline(PIPELINE_DEPTH-1).insn_type is
            when OP_MUL_L64 =>
                d2 := d(63 downto 0);
		if v.multiply_pipeline(PIPELINE_DEPTH-1).is_32bit = '1' then
		    ov := (or d(63 downto 31)) and not (and d(63 downto 31));
		else
		    ov := (or d(127 downto 63)) and not (and d(127 downto 63));
		end if;
            when OP_MUL_H32 =>
                d2 := d(63 downto 32) & d(63 downto 32);
            when OP_MUL_H64 =>
                d2 := d(127 downto 64);
            when others =>
                --report "Illegal insn type in multiplier";
                d2 := (others => '0');
        end case;

        m_out.write_reg_data <= d2;
        m_out.write_reg_nr <= v.multiply_pipeline(PIPELINE_DEPTH-1).write_reg;
	m_out.xerc <= v.multiply_pipeline(PIPELINE_DEPTH-1).xerc;

	-- Generate OV/OV32/SO when OE=1
        if v.multiply_pipeline(PIPELINE_DEPTH-1).valid = '1' then
            m_out.valid <= '1';
            m_out.rc <= v.multiply_pipeline(PIPELINE_DEPTH-1).rc;
            m_out.write_xerc_enable <= v.multiply_pipeline(PIPELINE_DEPTH-1).oe;

	    -- We must test oe because the RC update code in writeback
	    -- will use the xerc value to set CR0:SO so we must not clobber
	    -- xerc if OE wasn't set.
	    --
	    if v.multiply_pipeline(PIPELINE_DEPTH-1).oe = '1' then
		m_out.xerc.ov <= ov;
		m_out.xerc.ov32 <= ov;
		m_out.xerc.so <= v.multiply_pipeline(PIPELINE_DEPTH-1).xerc.so or ov;
	    end if;
        end if;

        rin <= v;
    end process;
end architecture behaviour;
