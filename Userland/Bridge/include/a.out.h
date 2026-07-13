#ifndef MIXTAR_BRIDGE_A_OUT_H
#define MIXTAR_BRIDGE_A_OUT_H

struct exec {
	unsigned long a_midmag;
	unsigned long a_text;
	unsigned long a_data;
	unsigned long a_bss;
	unsigned long a_syms;
	unsigned long a_entry;
	unsigned long a_trsize;
	unsigned long a_drsize;
};

#ifndef MIXTAR_BRIDGE_STRUCT_NLIST
#define MIXTAR_BRIDGE_STRUCT_NLIST
struct nlist {
    char *n_name;
    union {
        char *n_name;
        long n_strx;
    } n_un;
    unsigned char n_type;
	char n_other;
	short n_desc;
	unsigned long n_value;
};
#endif

#define OMAGIC 0407
#define NMAGIC 0410
#define ZMAGIC 0413
#define QMAGIC 0314

#define N_UNDF 0x00
#define N_ABS 0x02
#define N_TEXT 0x04
#define N_DATA 0x06
#define N_BSS 0x08
#define N_EXT 0x01
#define N_TYPE 0x1e
#define N_STAB 0xe0
#define N_FN 0x1f

#define N_BADMAG(x) (0)
#define N_TXTOFF(x) 0
#define N_SYMOFF(x) 0
#define N_STROFF(x) 0

#endif
