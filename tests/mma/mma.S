        .section ".text","ax"

.global main
main:
        /*
         * MMA accumulator starts at 0 after reset.
         *
         * Test 1:
         *   2 * 3 = 6
         */
        li      %r4, 2
        li      %r5, 3
        .long   0x7C642802      /* mma r3,r4,r5 */

        /*
         * Test 2:
         *   6 + (4 * 5) = 26
         */
        li      %r4, 4
        li      %r5, 5
        .long   0x7C642802      /* mma r3,r4,r5 */

        /*
         * Test 3:
         *   26 + (-2 * 3) = 20
         */
        li      %r4, -2
        li      %r5, 3
        .long   0x7C642802      /* mma r3,r4,r5 */

        /*
         * Return final accumulator value in r3.
         * Expected: 20
         */
        blr
