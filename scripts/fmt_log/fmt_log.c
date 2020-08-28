#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>

typedef unsigned long long u64;

struct log_entry {
	u64	nia_lo: 42;
	u64	nia_hi: 1;
	u64	ic_ra_valid: 1;
	u64	ic_access_ok: 1;
	u64	ic_is_miss: 1;
	u64	ic_is_hit: 1;
	u64	ic_way: 3;
	u64	ic_state: 1;
	u64	ic_part_nia: 4;
	u64	ic_fetch_failed: 1;
	u64	ic_stall_out: 1;
	u64	ic_wb_stall: 1;
	u64	ic_wb_cyc: 1;
	u64	ic_wb_stb: 1;
	u64	ic_wb_adr: 3;
	u64	ic_wb_ack: 1;

	u64	ic_insn: 32;
	u64	ic_valid: 1;
	u64	d1_valid: 1;
	u64	d1_unit: 2;
	u64	d1_part_nia: 4;
	u64	d1_insn_type: 6;
	u64	d2_bypass_a: 1;
	u64	d2_bypass_b: 1;
	u64	d2_bypass_c: 1;
	u64	d2_stall_out: 1;
	u64	d2_stopped_out: 1;
	u64	d2_valid: 1;
	u64	d2_part_nia: 4;
	u64	e1_flush_out: 1;
	u64	e1_stall_out: 1;
	u64	e1_redirect: 1;
	u64	e1_valid: 1;
	u64	e1_write_enable: 1;
	u64	e1_unused: 3;

	u64	e1_irq_state: 1;
	u64	e1_irq: 1;
	u64	e1_exception: 1;
	u64	e1_msr_dr: 1;
	u64	e1_msr_ir: 1;
	u64	e1_msr_pr: 1;
	u64	e1_msr_ee: 1;
	u64	pad1: 5;
	u64	ls_state: 3;
	u64	ls_dw_done: 1;
	u64	ls_min_done: 1;
	u64	ls_do_valid: 1;
	u64	ls_mo_valid: 1;
	u64	ls_lo_valid: 1;
	u64	ls_eo_except: 1;
	u64	ls_stall_out: 1;
	u64	pad2: 1;
	u64	dc_state: 3;
	u64	dc_ra_valid: 1;
	u64	dc_tlb_way: 3;
	u64	dc_stall_out: 1;
	u64	dc_op: 3;
	u64	dc_do_valid: 1;
	u64	dc_do_error: 1;
	u64	dc_wb_cyc: 1;
	u64	dc_wb_stb: 1;
	u64	dc_wb_ack: 1;
	u64	dc_wb_stall: 1;
	u64	dc_wb_adr: 3;
	u64	cr_wr_mask: 8;
	u64	cr_wr_data: 4;
	u64	cr_wr_enable: 1;
	u64	reg_wr_reg: 7;
	u64	reg_wr_enable: 1;

	u64	reg_wr_data;
};

#define FLAG(i, y)	(log.i? y: ' ')
#define FLGA(i, y, z)	(log.i? y: z)
#define PNIA(f)		(full_nia[log.f] & 0xff)

const char *units[4] = { "--", "al", "ls", "fp" };
const char *ops[64] =
{
	"illegal", "nop    ", "add    ", "and    ", "attn   ", "b      ", "bc     ", "bcreg  ",
	"bperm  ", "cmp    ", "cmpb   ", "cmpeqb ", "cmprb  ", "cntz   ", "crop   ", "darn   ",
	"dcbf   ", "dcbst  ", "dcbt   ", "dcbtst ", "dcbz   ", "div    ", "dive   ", "exts   ",
	"extswsl", "fpop   ", "fpopi  ", "icbi   ", "icbt   ", "isel   ", "isync  ", "ld     ",
	"st     ", "fpload ", "fpstore", "mcrxrx ", "mfcr   ", "mfmsr  ", "mfspr  ", "mod    ",
	"mtcrf  ", "mtmsr  ", "mtspr  ", "mull64 ", "mulh64 ", "mulh32 ", "or     ", "popcnt ",
	"prty   ", "rfid   ", "rlc    ", "rlcl   ", "rlcr   ", "sc     ", "setb   ", "shl    ",
	"shr    ", "sync   ", "tlbie  ", "trap   ", "xor    ", "bcd    ", "addg6s ", "ffail  ",
};

const char *spr_names[13] =
{
	"lr ", "ctr", "sr0", "sr1", "hr0", "hr1", "sg0", "sg1",
	"sg2", "sg3", "hg0", "hg1", "xer"
};
			     
int main(int ac, char **av)
{
	struct log_entry log;
	u64 full_nia[16];
	long int lineno = 1;
	FILE *f;
	const char *filename;
	int i;
	long int ncompl = 0;

	if (ac != 1 && ac != 2) {
		fprintf(stderr, "Usage: %s [filename]\n", av[0]);
		exit(1);
	}
	f = stdin;
	if (ac == 2) {
		filename = av[1];
		f = fopen(filename, "rb");
		if (f == NULL) {
			perror(filename);
			exit(1);
		}
	}

	for (i = 0; i < 15; ++i)
		full_nia[i] = i << 2;

	while (fread(&log, sizeof(log), 1, f) == 1) {
		full_nia[log.nia_lo & 0xf] = (log.nia_hi? 0xc000000000000000: 0) |
			(log.nia_lo << 2);
		if (lineno % 20 == 1) {
			printf("        fetch1 NIA      icache                         decode1       decode2   execute1         loadstore  dcache       CR   GSPR\n");
			printf("     ----------------   TAHW S -WB-- pN --insn--    pN un op         pN byp    FR IIE MSR  WC   SD MM CE   SRTO DE -WB-- c ms reg val\n");
			printf("                        LdMy t csnSa IA             IA it            IA abc    le srx EPID em   tw rd mx   tAwp vr csnSa 0 k\n");
		}
		printf("%4ld %c0000%.11llx %c ", lineno,
		       (log.nia_hi? 'c': '0'),
		       (unsigned long long)log.nia_lo << 2,
		       FLAG(ic_stall_out, '|'));
		printf("%c%c%c%d %c %c%c%d%c%c %.2llx ",
		       FLGA(ic_ra_valid, ' ', 'T'),
		       FLGA(ic_access_ok, ' ', 'X'),
		       FLGA(ic_is_hit, 'H', FLGA(ic_is_miss, 'M', ' ')),
		       log.ic_way,
		       FLAG(ic_state, 'W'),
		       FLAG(ic_wb_cyc, 'c'),
		       FLAG(ic_wb_stb, 's'),
		       log.ic_wb_adr,
		       FLAG(ic_wb_stall, 'S'),
		       FLAG(ic_wb_ack, 'a'),
		       PNIA(ic_part_nia));
		if (log.ic_valid)
			printf("%.8x", log.ic_insn);
		else if (log.ic_fetch_failed)
			printf("!!!!!!!!");
		else
			printf("--------");
		printf(" %c%c %.2llx ",
		       FLAG(ic_valid, '>'),
		       FLAG(d2_stall_out, '|'),
		       PNIA(d1_part_nia));
		if (log.d1_valid)
			printf("%s %s",
			       units[log.d1_unit],
			       ops[log.d1_insn_type]);
		else
			printf("-- -------");
		printf(" %c%c ",
		       FLAG(d1_valid, '>'),
		       FLAG(d2_stall_out, '|'));
		printf("%.2llx %c%c%c %c%c ",
		       PNIA(d2_part_nia),
		       FLAG(d2_bypass_a, 'a'),
		       FLAG(d2_bypass_b, 'b'),
		       FLAG(d2_bypass_c, 'c'),
		       FLAG(d2_valid, '>'),
		       FLAG(e1_stall_out, '|'));
		printf("%c%c %c%c%c %c%c%c%c %c%c ",
		       FLAG(e1_flush_out, 'F'),
		       FLAG(e1_redirect, 'R'),
		       FLAG(e1_irq_state, 'w'),
		       FLAG(e1_irq, 'I'),
		       FLAG(e1_exception, 'X'),
		       FLAG(e1_msr_ee, 'E'),
		       FLGA(e1_msr_pr, 'u', 's'),
		       FLAG(e1_msr_ir, 'I'),
		       FLAG(e1_msr_dr, 'D'),
		       FLAG(e1_write_enable, 'W'),
		       FLAG(e1_valid, 'C'));
		printf("%c %d%d %c%c %c%c %c ",
		       FLAG(ls_stall_out, '|'),
		       log.ls_state,
		       log.ls_dw_done,
		       FLAG(ls_mo_valid, 'M'),
		       FLAG(ls_min_done, 'm'),
		       FLAG(ls_lo_valid, 'C'),
		       FLAG(ls_eo_except, 'X'),
		       FLAG(ls_do_valid, '>'));
		printf("%d%c%d%d %c%c %c%c%d%c%c ",
		       log.dc_state,
		       FLAG(dc_ra_valid, 'R'),
		       log.dc_tlb_way,
		       log.dc_op,
		       FLAG(dc_do_valid, 'V'),
		       FLAG(dc_do_error, 'E'),
		       FLAG(dc_wb_cyc, 'c'),
		       FLAG(dc_wb_stb, 's'),
		       log.dc_wb_adr,
		       FLAG(dc_wb_stall, 'S'),
		       FLAG(dc_wb_ack, 'a'));
		if (log.cr_wr_enable)
			printf("%x>%.2x ", log.cr_wr_data, log.cr_wr_mask);
		else
			printf("     ");
		if (log.reg_wr_enable) {
			if (log.reg_wr_reg < 32 || log.reg_wr_reg > 44)
				printf("r%02d", log.reg_wr_reg);
			else
				printf("%s", spr_names[log.reg_wr_reg - 32]);
			printf("=%.16llx", log.reg_wr_data);
		}
		printf("\n");
		++lineno;
		if (log.ls_lo_valid || log.e1_valid)
			++ncompl;
	}
	printf("%ld instructions completed, %.2f CPI\n", ncompl,
	       (double)(lineno - 1) / ncompl);
	exit(0);
}
