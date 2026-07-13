#ifndef MIXTAR_BRIDGE_NLIST_H
#define MIXTAR_BRIDGE_NLIST_H

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

#endif
