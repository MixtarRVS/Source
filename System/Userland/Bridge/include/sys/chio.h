#ifndef MIXTAR_BRIDGE_SYS_CHIO_H
#define MIXTAR_BRIDGE_SYS_CHIO_H

#include <stdint.h>

#define CHET_MT 0
#define CHET_ST 1
#define CHET_IE 2
#define CHET_DT 3

#define CM_INVERT 0x0001
#define CE_INVERT1 0x0001
#define CE_INVERT2 0x0002
#define CP_INVERT 0x0001

#define CESR_VOLTAGS 0x0001

#define CES_STATUS_FULL 0x0001
#define CES_STATUS_IMPEXP 0x0002
#define CES_STATUS_EXCEPT 0x0004
#define CES_STATUS_ACCESS 0x0008
#define CES_SOURCE_VALID 0x0010
#define CES_SCSIID_VALID 0x0020
#define CES_LUN_VALID 0x0040

#define CESTATUS_BITS "\1FULL\2IMPEXP\3EXCEPT\4ACCESS\5SOURCE\6SCSIID\7LUN"

#define CES_CODE_SET_BINARY 1
#define CES_CODE_SET_ASCII 2
#define CES_CODE_SET_UTF_8 3

#define CSVR_MODE_SET 0x0001
#define CSVR_MODE_REPLACE 0x0002
#define CSVR_MODE_CLEAR 0x0004
#define CSVR_ALTERNATE 0x0008

#define CHIOMOVE 0x6301
#define CHIOEXCHANGE 0x6302
#define CHIOPOSITION 0x6303
#define CHIOGPARAMS 0x6304
#define CHIOGPICKER 0x6305
#define CHIOSPICKER 0x6306
#define CHIOGSTATUS 0x6307
#define CHIOIELEM 0x6308
#define CHIOSETVOLTAG 0x6309

typedef unsigned int ces_status_flags;

struct changer_volume_tag {
	char cv_volid[36];
	uint16_t cv_serial;
};

struct changer_move {
	uint16_t cm_fromtype;
	uint16_t cm_fromunit;
	uint16_t cm_totype;
	uint16_t cm_tounit;
	uint16_t cm_flags;
};

struct changer_exchange {
	uint16_t ce_srctype;
	uint16_t ce_srcunit;
	uint16_t ce_fdsttype;
	uint16_t ce_fdstunit;
	uint16_t ce_sdsttype;
	uint16_t ce_sdstunit;
	uint16_t ce_flags;
};

struct changer_position {
	uint16_t cp_type;
	uint16_t cp_unit;
	uint16_t cp_flags;
};

struct changer_params {
	uint16_t cp_nslots;
	uint16_t cp_ndrives;
	uint16_t cp_npickers;
	uint16_t cp_nportals;
	uint16_t cp_curpicker;
};

struct changer_element_status {
	uint16_t ces_type;
	uint16_t ces_addr;
	uint16_t ces_flags;
	uint16_t ces_sensecode;
	uint16_t ces_sensequal;
	uint16_t ces_source_type;
	uint16_t ces_source_addr;
	uint16_t ces_int_addr;
	uint16_t ces_scsi_id;
	uint16_t ces_scsi_lun;
	uint8_t ces_code_set;
	uint8_t ces_designator_length;
	char ces_designator[64];
	struct changer_volume_tag ces_pvoltag;
	struct changer_volume_tag ces_avoltag;
};

struct changer_element_status_request {
	uint16_t cesr_element_type;
	uint16_t cesr_element_base;
	uint16_t cesr_element_count;
	uint16_t cesr_flags;
	struct changer_element_status *cesr_element_status;
};

struct changer_set_voltag_request {
	uint16_t csvr_type;
	uint16_t csvr_addr;
	uint16_t csvr_flags;
	struct changer_volume_tag csvr_voltag;
};

#endif /* MIXTAR_BRIDGE_SYS_CHIO_H */
