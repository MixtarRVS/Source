#ifndef MIXTAR_BRIDGE_ELF_H
#define MIXTAR_BRIDGE_ELF_H

#if defined(__linux__)
#include "/usr/include/elf.h"
#else
#include_next <elf.h>
#endif

#if defined(ELFSIZE) && ELFSIZE == 64
typedef Elf64_Ehdr Elf_Ehdr;
typedef Elf64_Shdr Elf_Shdr;
typedef Elf64_Sym Elf_Sym;
#ifndef ELF_ST_BIND
#define ELF_ST_BIND ELF64_ST_BIND
#endif
#ifndef ELF_ST_TYPE
#define ELF_ST_TYPE ELF64_ST_TYPE
#endif
#elif defined(ELFSIZE) && ELFSIZE == 32
typedef Elf32_Ehdr Elf_Ehdr;
typedef Elf32_Shdr Elf_Shdr;
typedef Elf32_Sym Elf_Sym;
#ifndef ELF_ST_BIND
#define ELF_ST_BIND ELF32_ST_BIND
#endif
#ifndef ELF_ST_TYPE
#define ELF_ST_TYPE ELF32_ST_TYPE
#endif
#endif

#ifndef ELF_TARG_DATA
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define ELF_TARG_DATA ELFDATA2MSB
#else
#define ELF_TARG_DATA ELFDATA2LSB
#endif
#endif

#ifndef ELF_TARG_VER
#define ELF_TARG_VER EV_CURRENT
#endif

#ifndef ELF_TEXT
#define ELF_TEXT ".text"
#endif
#ifndef ELF_RODATA
#define ELF_RODATA ".rodata"
#endif
#ifndef ELF_OPENBSDRANDOMDATA
#define ELF_OPENBSDRANDOMDATA ".openbsd.randomdata"
#endif
#ifndef ELF_DATA
#define ELF_DATA ".data"
#endif
#ifndef ELF_BSS
#define ELF_BSS ".bss"
#endif
#ifndef ELF_GOT
#define ELF_GOT ".got"
#endif
#ifndef ELF_INIT
#define ELF_INIT ".init"
#endif
#ifndef ELF_FINI
#define ELF_FINI ".fini"
#endif
#ifndef ELF_STRTAB
#define ELF_STRTAB ".strtab"
#endif
#ifndef ELF_SYMTAB
#define ELF_SYMTAB ".symtab"
#endif
#ifndef ELF_DYNSTR
#define ELF_DYNSTR ".dynstr"
#endif
#ifndef ELF_DYNSYM
#define ELF_DYNSYM ".dynsym"
#endif

#endif
