#ifndef MIXTAR_BRIDGE_SYS_DISKLABEL_H
#define MIXTAR_BRIDGE_SYS_DISKLABEL_H

#include <stdint.h>
#include <sys/types.h>
#include <sys/uuid.h>

#ifndef __daddr_t_defined
typedef int64_t daddr_t;
#define __daddr_t_defined 1
#endif

#ifndef OPENDEV_PART
#define OPENDEV_PART 0
#endif

#ifndef MAXPARTITIONS
#define MAXPARTITIONS 16
#endif

#ifndef RAW_PART
#define RAW_PART 2
#endif

#ifndef DEV_BSIZE
#define DEV_BSIZE 512
#endif

#ifndef DOSBBSECTOR
#define DOSBBSECTOR 0
#endif

#ifndef DOSPARTOFF
#define DOSPARTOFF 446
#endif

#ifndef NDOSPART
#define NDOSPART 4
#endif

#ifndef DOSACTIVE
#define DOSACTIVE 0x80
#endif

#ifndef DOSMBR_SIGNATURE
#define DOSMBR_SIGNATURE 0xaa55
#endif

#ifndef DOSPTYP_UNUSED
#define DOSPTYP_UNUSED 0x00
#endif

#ifndef DOSPTYP_EXTEND
#define DOSPTYP_EXTEND 0x05
#endif

#ifndef DOSPTYP_EXTENDL
#define DOSPTYP_EXTENDL 0x0f
#endif

#ifndef DOSPTYP_OPENBSD
#define DOSPTYP_OPENBSD 0xa6
#endif

#ifndef DOSPTYP_EFI
#define DOSPTYP_EFI 0xee
#endif

#ifndef DOSPTYP_EFISYS
#define DOSPTYP_EFISYS 0xef
#endif

#ifndef GPTSECTOR
#define GPTSECTOR 1
#endif

#ifndef NGPTPARTITIONS
#define NGPTPARTITIONS 128
#endif

#ifndef GPTPARTNAMESIZE
#define GPTPARTNAMESIZE 36
#endif

#ifndef GPTSIGNATURE
#define GPTSIGNATURE 0x5452415020494645ULL
#endif

#ifndef GPTREVISION
#define GPTREVISION 0x00010000U
#endif

#ifndef GPTMINHDRSIZE
#define GPTMINHDRSIZE 92U
#endif

#ifndef GPTMINPARTSIZE
#define GPTMINPARTSIZE 128U
#endif

#ifndef GPTPARTATTR_REQUIRED
#define GPTPARTATTR_REQUIRED (1ULL << 0)
#endif
#ifndef GPTPARTATTR_IGNORE
#define GPTPARTATTR_IGNORE (1ULL << 1)
#endif
#ifndef GPTPARTATTR_BOOTABLE
#define GPTPARTATTR_BOOTABLE (1ULL << 2)
#endif
#ifndef GPTPARTATTR_MS_READONLY
#define GPTPARTATTR_MS_READONLY (1ULL << 60)
#endif
#ifndef GPTPARTATTR_MS_SHADOW
#define GPTPARTATTR_MS_SHADOW (1ULL << 61)
#endif
#ifndef GPTPARTATTR_MS_HIDDEN
#define GPTPARTATTR_MS_HIDDEN (1ULL << 62)
#endif
#ifndef GPTPARTATTR_MS_NOAUTOMOUNT
#define GPTPARTATTR_MS_NOAUTOMOUNT (1ULL << 63)
#endif

#ifndef GPT_UUID_EFI_SYSTEM
#define GPT_UUID_EFI_SYSTEM { 0x28, 0x73, 0x2a, 0xc1, 0x1f, 0xf8, 0xd2, 0x11, 0xba, 0x4b, 0x00, 0xa0, 0xc9, 0x3e, 0xc9, 0x3b }
#endif

#ifndef GPT_UUID_OPENBSD
#define GPT_UUID_OPENBSD { 0x41, 0x77, 0x24, 0x82, 0x11, 0x86, 0xd1, 0x11, 0x8b, 0xd3, 0x00, 0xa0, 0xc9, 0x85, 0x82, 0xa7 }
#endif

#ifndef htole16
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define htole16(x) __builtin_bswap16((uint16_t)(x))
#define htole32(x) __builtin_bswap32((uint32_t)(x))
#define htole64(x) __builtin_bswap64((uint64_t)(x))
#define letoh16(x) __builtin_bswap16((uint16_t)(x))
#define letoh32(x) __builtin_bswap32((uint32_t)(x))
#define letoh64(x) __builtin_bswap64((uint64_t)(x))
#define htobe16(x) ((uint16_t)(x))
#define htobe32(x) ((uint32_t)(x))
#define htobe64(x) ((uint64_t)(x))
#define betoh16(x) ((uint16_t)(x))
#define betoh32(x) ((uint32_t)(x))
#define betoh64(x) ((uint64_t)(x))
#else
#define htole16(x) ((uint16_t)(x))
#define htole32(x) ((uint32_t)(x))
#define htole64(x) ((uint64_t)(x))
#define letoh16(x) ((uint16_t)(x))
#define letoh32(x) ((uint32_t)(x))
#define letoh64(x) ((uint64_t)(x))
#define htobe16(x) __builtin_bswap16((uint16_t)(x))
#define htobe32(x) __builtin_bswap32((uint32_t)(x))
#define htobe64(x) __builtin_bswap64((uint64_t)(x))
#define betoh16(x) __builtin_bswap16((uint16_t)(x))
#define betoh32(x) __builtin_bswap32((uint32_t)(x))
#define betoh64(x) __builtin_bswap64((uint64_t)(x))
#endif
#endif

#ifndef letoh16
#define letoh16(x) htole16((x))
#endif
#ifndef letoh32
#define letoh32(x) htole32((x))
#endif
#ifndef letoh64
#define letoh64(x) htole64((x))
#endif
#ifndef betoh16
#define betoh16(x) htobe16((x))
#endif
#ifndef betoh32
#define betoh32(x) htobe32((x))
#endif
#ifndef betoh64
#define betoh64(x) htobe64((x))
#endif

struct partition {
	uint64_t p_size;
	uint64_t p_offset;
	uint8_t p_fstype;
	uint8_t p_frag;
	uint16_t p_cpg;
	uint32_t p_fsize;
};

struct disklabel {
	uint32_t d_secsize;
	uint32_t d_nsectors;
	uint32_t d_ntracks;
	uint32_t d_ncylinders;
	uint64_t d_secperunit;
	struct uuid d_uid;
	uint16_t d_npartitions;
	struct partition d_partitions[MAXPARTITIONS];
};

struct dos_partition {
	uint8_t dp_flag;
	uint8_t dp_shd;
	uint8_t dp_ssect;
	uint8_t dp_scyl;
	uint8_t dp_typ;
	uint8_t dp_ehd;
	uint8_t dp_esect;
	uint8_t dp_ecyl;
	uint32_t dp_start;
	uint32_t dp_size;
};

struct dos_mbr {
	uint8_t dmbr_boot[DOSPARTOFF];
	struct dos_partition dmbr_parts[NDOSPART];
	uint16_t dmbr_sign;
};

struct gpt_header {
	uint64_t gh_sig;
	uint32_t gh_rev;
	uint32_t gh_size;
	uint32_t gh_csum;
	uint32_t gh_rsvd;
	uint64_t gh_lba_self;
	uint64_t gh_lba_alt;
	uint64_t gh_lba_start;
	uint64_t gh_lba_end;
	struct uuid gh_guid;
	uint64_t gh_part_lba;
	uint32_t gh_part_num;
	uint32_t gh_part_size;
	uint32_t gh_part_csum;
};

struct gpt_partition {
	struct uuid gp_type;
	struct uuid gp_guid;
	uint64_t gp_lba_start;
	uint64_t gp_lba_end;
	uint64_t gp_attrs;
	uint16_t gp_name[GPTPARTNAMESIZE];
};

static inline uint64_t
mixtar_bridge_dl_blkpersec(const struct disklabel *dl)
{
	if (dl == 0 || dl->d_secsize == 0)
		return 1;
	return ((uint64_t)dl->d_secsize + DEV_BSIZE - 1) / DEV_BSIZE;
}

#ifndef DL_BLKSPERSEC
#define DL_BLKSPERSEC(dl) mixtar_bridge_dl_blkpersec((dl))
#endif
#ifndef DL_BLKTOSEC
#define DL_BLKTOSEC(dl, blk) ((uint64_t)(blk) / DL_BLKSPERSEC((dl)))
#endif
#ifndef DL_SECTOBLK
#define DL_SECTOBLK(dl, sec) ((uint64_t)(sec) * DL_BLKSPERSEC((dl)))
#endif
#ifndef DL_GETDSIZE
#define DL_GETDSIZE(dl) ((uint64_t)((dl)->d_secperunit))
#endif
#ifndef DL_SETDSIZE
#define DL_SETDSIZE(dl, value) ((dl)->d_secperunit = (uint64_t)(value))
#endif

#endif
