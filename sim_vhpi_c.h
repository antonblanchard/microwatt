#include <stdint.h>

#define vhpi0	2	/* forcing 0 */
#define vhpi1	3	/* forcing 1 */

char *from_string(void *__p);

uint64_t from_std_logic_vector(unsigned char *p, unsigned long len);

void to_std_logic_vector(unsigned long val, unsigned char *p,
			 unsigned long len);
