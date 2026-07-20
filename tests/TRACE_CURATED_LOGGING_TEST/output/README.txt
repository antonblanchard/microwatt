MMU Trace-Array test logs
=========================

This folder holds the captured console output of the MMU trace tests.

Regenerate everything yourself:

    cd ..                       # tests/TRACE_CURATED_LOGGING_TEST
    ./run_and_log.sh            # builds core_tb + firmware, runs both, writes *.log here
    # or, if the simulator is already built:
    ./run_and_log.sh --no-build

Files:

    TRACE_CURATED_LOGGING_TEST.log
        The new curated-logging + one-shot stop-on-full test (8 sub-tests).
        Expected last line:
            SUMMARY : 8 PASS / 0 FAIL   ->  ALL TESTS PASSED

    BIT63_LOGGING_ENABLE_TEST.log
        Regression for the SPR-704 bit-63 enable gate (5 sub-tests).
        Expected last line:
            SUMMARY : 5 PASS / 0 FAIL   ->  ALL TESTS PASSED

Notes / gotchas:
  * The Microwatt sim prints its UART console on STDERR (see sim_console_c.c);
    GHDL's own report chatter goes to STDOUT and is discarded by the runner.
  * The stop-on-full sub-test (Test 08) fills all 2048 trace records, i.e. it
    runs several hundred radix-tree walks, so that test alone takes a few
    minutes of wall-clock simulation time.  This is expected.
