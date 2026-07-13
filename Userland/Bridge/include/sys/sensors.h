#ifndef MIXTAR_BRIDGE_SYS_SENSORS_H
#define MIXTAR_BRIDGE_SYS_SENSORS_H

#include <stdint.h>
#include <sys/time.h>

enum sensor_type {
	SENSOR_TEMP = 0,
	SENSOR_FANRPM,
	SENSOR_VOLTS_DC,
	SENSOR_VOLTS_AC,
	SENSOR_OHMS,
	SENSOR_WATTS,
	SENSOR_AMPS,
	SENSOR_WATTHOUR,
	SENSOR_AMPHOUR,
	SENSOR_INDICATOR,
	SENSOR_INTEGER,
	SENSOR_PERCENT,
	SENSOR_LUX,
	SENSOR_DRIVE,
	SENSOR_TIMEDELTA,
	SENSOR_HUMIDITY,
	SENSOR_FREQ,
	SENSOR_ANGLE,
	SENSOR_DISTANCE,
	SENSOR_PRESSURE,
	SENSOR_ACCEL,
	SENSOR_VELOCITY,
	SENSOR_ENERGY,
	SENSOR_MAX_TYPES
};

enum sensor_status {
	SENSOR_S_UNSPEC = 0,
	SENSOR_S_OK,
	SENSOR_S_WARN,
	SENSOR_S_CRIT,
	SENSOR_S_UNKNOWN
};

#define SENSOR_FINVALID 0x0001
#define SENSOR_FUNKNOWN 0x0002

#define SENSOR_DRIVE_EMPTY 0
#define SENSOR_DRIVE_READY 1
#define SENSOR_DRIVE_POWERUP 2
#define SENSOR_DRIVE_ONLINE 3
#define SENSOR_DRIVE_IDLE 4
#define SENSOR_DRIVE_ACTIVE 5
#define SENSOR_DRIVE_REBUILD 6
#define SENSOR_DRIVE_POWERDOWN 7
#define SENSOR_DRIVE_FAIL 8
#define SENSOR_DRIVE_PFAIL 9

struct sensordev {
	int num;
	char xname[32];
	int maxnumt[SENSOR_MAX_TYPES];
};

struct sensor {
	enum sensor_type type;
	int64_t value;
	int status;
	int flags;
	char desc[32];
	struct timeval tv;
};

static const char *sensor_type_s[SENSOR_MAX_TYPES] = {
	"temp",
	"fanrpm",
	"volt0",
	"volt1",
	"ohms",
	"watts",
	"amps",
	"watthour",
	"amphour",
	"indicator",
	"integer",
	"percent",
	"lux",
	"drive",
	"timedelta",
	"humidity",
	"freq",
	"angle",
	"distance",
	"pressure",
	"accel",
	"velocity",
	"energy"
};

#endif /* MIXTAR_BRIDGE_SYS_SENSORS_H */
