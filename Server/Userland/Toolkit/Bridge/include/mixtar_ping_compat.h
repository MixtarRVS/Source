#ifndef MIXTAR_BRIDGE_PING_COMPAT_H
#define MIXTAR_BRIDGE_PING_COMPAT_H

#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>

#ifndef IPV6_MAXPACKET
#define IPV6_MAXPACKET 65535
#endif

#ifndef IPV6_MAXHLIM
#define IPV6_MAXHLIM 255
#endif

#ifndef IPV6_DEFHLIM
#define IPV6_DEFHLIM 64
#endif

#ifndef IPV6_MMTU
#define IPV6_MMTU 1280
#endif

#ifndef IPV6_USE_MIN_MTU
#define IPV6_USE_MIN_MTU 63
#endif

#ifndef SO_RTABLE
#define SO_RTABLE 0x1021
#endif

#ifndef INFTIM
#define INFTIM -1
#endif

#ifndef IPTOS_DSCP_CS0
#define IPTOS_DSCP_CS0 0x00
#endif
#ifndef IPTOS_DSCP_CS1
#define IPTOS_DSCP_CS1 0x20
#endif
#ifndef IPTOS_DSCP_CS2
#define IPTOS_DSCP_CS2 0x40
#endif
#ifndef IPTOS_DSCP_CS3
#define IPTOS_DSCP_CS3 0x60
#endif
#ifndef IPTOS_DSCP_CS4
#define IPTOS_DSCP_CS4 0x80
#endif
#ifndef IPTOS_DSCP_CS5
#define IPTOS_DSCP_CS5 0xa0
#endif
#ifndef IPTOS_DSCP_CS6
#define IPTOS_DSCP_CS6 0xc0
#endif
#ifndef IPTOS_DSCP_CS7
#define IPTOS_DSCP_CS7 0xe0
#endif
#ifndef IPTOS_DSCP_VA
#define IPTOS_DSCP_VA 0xb0
#endif

#ifndef ICMP6_MEMBERSHIP_QUERY
#define ICMP6_MEMBERSHIP_QUERY 130
#endif
#ifndef ICMP6_MEMBERSHIP_REPORT
#define ICMP6_MEMBERSHIP_REPORT 131
#endif
#ifndef ICMP6_MEMBERSHIP_REDUCTION
#define ICMP6_MEMBERSHIP_REDUCTION 132
#endif

#ifndef IPV6_FLOWLABEL_MASK
#define IPV6_FLOWLABEL_MASK 0x000fffff
#endif

#ifndef IPV6_VERSION_MASK
#define IPV6_VERSION_MASK 0xf0
#endif

#define sa_len sa_family
#define sin_len sin_family

static inline int
mixtar_ping_timingsafe_memcmp(const void *a, const void *b, size_t len)
{
	return memcmp(a, b, len);
}

#define timingsafe_memcmp(a, b, len) mixtar_ping_timingsafe_memcmp((a), (b), (len))

static inline uint64_t
mixtar_ping_betoh64(uint64_t value)
{
	return ((value & 0x00000000000000ffULL) << 56) |
	    ((value & 0x000000000000ff00ULL) << 40) |
	    ((value & 0x0000000000ff0000ULL) << 24) |
	    ((value & 0x00000000ff000000ULL) << 8) |
	    ((value & 0x000000ff00000000ULL) >> 8) |
	    ((value & 0x0000ff0000000000ULL) >> 24) |
	    ((value & 0x00ff000000000000ULL) >> 40) |
	    ((value & 0xff00000000000000ULL) >> 56);
}

#define betoh64(value) mixtar_ping_betoh64((uint64_t)(value))

struct ah {
	uint8_t ah_nh;
	uint8_t ah_hl;
};

static inline int
mixtar_ping_inet6_opt_next(void *extbuf, socklen_t extlen, int offset,
    uint8_t *typep, socklen_t *lenp, void **databufp)
{
	(void)extbuf;
	(void)extlen;
	(void)offset;
	(void)typep;
	(void)lenp;
	(void)databufp;
	return -1;
}

static inline int
mixtar_ping_inet6_opt_get_val(void *databuf, int offset, void *val,
    socklen_t vallen)
{
	(void)databuf;
	(void)offset;
	(void)val;
	(void)vallen;
	return -1;
}

static inline int
mixtar_ping_inet6_rth_segments(const void *bp)
{
	(void)bp;
	return -1;
}

static inline struct in6_addr *
mixtar_ping_inet6_rth_getaddr(const void *bp, int idx)
{
	(void)bp;
	(void)idx;
	return (struct in6_addr *)0;
}

#define inet6_opt_next mixtar_ping_inet6_opt_next
#define inet6_opt_get_val mixtar_ping_inet6_opt_get_val
#define inet6_rth_segments mixtar_ping_inet6_rth_segments
#define inet6_rth_getaddr mixtar_ping_inet6_rth_getaddr

#endif /* MIXTAR_BRIDGE_PING_COMPAT_H */
