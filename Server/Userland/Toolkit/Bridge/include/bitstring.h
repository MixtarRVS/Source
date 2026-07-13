/* Mixtar Bridge bitstring compatibility shim.
 *
 * This is intentionally C-standard friendly; the OpenBSD header uses
 * statement-expression macros that are valid for its native build but trip
 * Linux `-pedantic -Werror` probes.
 */
#ifndef MIXTAR_BRIDGE_BITSTRING_H
#define MIXTAR_BRIDGE_BITSTRING_H

#include <stdlib.h>

typedef unsigned char bitstr_t;

#define _bit_byte(bit) ((bit) >> 3)
#define _bit_mask(bit) (1u << ((bit) & 0x7))
#define bitstr_size(nbits) (((nbits) + 7) >> 3)
#define bit_alloc(nbits) \
	((bitstr_t *)calloc((size_t)bitstr_size(nbits), sizeof(bitstr_t)))
#define bit_decl(name, nbits) ((name)[bitstr_size(nbits)])
#define bit_test(name, bit) \
	(((name)[_bit_byte((bit))] & _bit_mask((bit))) != 0)
#define bit_set(name, bit) do { \
	(name)[_bit_byte((bit))] |= (bitstr_t)_bit_mask((bit)); \
} while (0)
#define bit_clear(name, bit) do { \
	(name)[_bit_byte((bit))] &= (bitstr_t)~_bit_mask((bit)); \
} while (0)
#define bit_nclear(name, start, stop) do { \
	int _mx_bit; \
	for (_mx_bit = (start); _mx_bit <= (stop); _mx_bit++) \
		bit_clear((name), _mx_bit); \
} while (0)
#define bit_nset(name, start, stop) do { \
	int _mx_bit; \
	for (_mx_bit = (start); _mx_bit <= (stop); _mx_bit++) \
		bit_set((name), _mx_bit); \
} while (0)
#define bit_ffc(name, nbits, value) do { \
	int _mx_bit; \
	*(value) = -1; \
	for (_mx_bit = 0; _mx_bit < (nbits); _mx_bit++) { \
		if (!bit_test((name), _mx_bit)) { \
			*(value) = _mx_bit; \
			break; \
		} \
	} \
} while (0)
#define bit_ffs(name, nbits, value) do { \
	int _mx_bit; \
	*(value) = -1; \
	for (_mx_bit = 0; _mx_bit < (nbits); _mx_bit++) { \
		if (bit_test((name), _mx_bit)) { \
			*(value) = _mx_bit; \
			break; \
		} \
	} \
} while (0)

#endif
