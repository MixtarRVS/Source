#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include <capsicum_helpers.h>
#include <casper/cap_fileargs.h>
#include <casper/cap_net.h>
#include <login_cap.h>
#include <sys/acl.h>
#include <sys/event.h>
#include <sys/mac.h>
#include <vis.h>

int setlogin(const char *name);
int revoke(const char *path);
int issetugid(void);
void logwtmp(const char *line, const char *name, const char *host);
int isduid(const char *value, int flags);
int getrtable(void);
int setpassent(int stayopen);
int setgroupent(int stayopen);
void srandom_deterministic(unsigned int seed);
int chflags(const char *path, unsigned long flags);
int lchflags(const char *path, unsigned long flags);
int fchflags(int fd, unsigned long flags);
int chflagsat(int fd, const char *path, unsigned long flags, int atflags);
long lpathconf(const char *path, int name);
int undelete(const char *path);
void strmode(mode_t mode, char *p);
char *getbsize(int *headerlen, long *blocksize);
void *setmode(const char *mode_text);
mode_t getmode(const void *set, mode_t base);
long long strtonum(const char *nptr, long long minval, long long maxval, const char **errstr);
char *fflagstostr(unsigned long flags);
int strtofflags(char **stringp, unsigned int *setp, unsigned int *clrp);
void *recallocarray(void *ptr, size_t oldnmemb, size_t nmemb, size_t size);
void freezero(void *ptr, size_t size);

int main(void)
{
    char empty[] = "";
    char bad[] = "nodump";
    char *empty_ptr = empty;
    char *bad_ptr = bad;
    unsigned int set = 123;
    unsigned int clr = 456;
    char *flags;
    unsigned char *buf;
    char mode_text[12];
    char vis_buf[32];
    char vis_ch[2];
    char *allocated_vis = NULL;
    int unvis_state = 0;
    cap_channel_t *cap;
    cap_net_limit_t *net_limit;
    fileargs_t *fileargs;
    cap_rights_t rights;
    int trivial = 0;
    mac_t label = NULL;
    char *mac_text = NULL;
    int headerlen = 0;
    long blocksize = 0;
    char *header;
    void *mode_set;
    const char *errstr = (const char *)1;

    if (setlogin("x") != 0)
        return 1;
    if (issetugid() != 0)
        return 2;
    logwtmp("tty", "name", "host");
    if (isduid("x", 0) != 0)
        return 3;
    if (getrtable() != 0)
        return 4;
    if (caph_limit_stdio() != 0 || caph_enter() != 0 ||
        caph_enter_casper() != 0 || caph_rights_limit(0, &rights) != 0)
        return 41;
    caph_cache_catpages();
    cap = cap_init();
    if (cap == NULL || cap_service_open(cap, "system.dns") != cap ||
        cap_close(cap) != 0)
        return 42;
    fileargs = fileargs_cinit(cap, 0, NULL, 0, 0, &rights, FA_OPEN);
    if (fileargs == NULL)
        return 43;
    net_limit = cap_net_limit_init(cap, 0);
    if (net_limit == NULL ||
        cap_net_limit_name2addr_family(net_limit, NULL, 0) != 0 ||
        cap_net_limit(net_limit) != 0)
        return 44;
    if (login_getclass(NULL) != NULL || login_getcapbool(NULL, NULL, 7) != 7 ||
        login_getcapnum(NULL, NULL, 11, 0) != 11 ||
        login_getcapsize(NULL, NULL, 13, 0) != 13 ||
        login_getcaptime(NULL, NULL, 17, 0) != 17 ||
        login_getcapstr(NULL, NULL, empty, NULL) != empty ||
        login_getstyle(NULL, empty, NULL) != empty ||
        setclasscontext(NULL, 0) != 0 ||
        setusercontext(NULL, NULL, 0, 0) != 0)
        return 45;
    login_close(NULL);
    errno = 0;
    if (acl_get_fd_np(0, ACL_TYPE_ACCESS) != NULL || errno == 0)
        return 46;
    if (acl_is_trivial_np(NULL, &trivial) != 0 || trivial != 1 ||
        acl_is_trivial(NULL, &trivial) != 0 || acl_supported("/", ACL_TYPE_ACCESS) != 0 ||
        acl_free(NULL) != 0)
        return 47;
    errno = 0;
    if (acl_set_fd_np(0, NULL, ACL_TYPE_ACCESS) != -1 || errno == 0)
        return 48;
    if (mac_prepare_file_label(&label) != 0 || label == NULL ||
        strcmp(label, "-") != 0 || mac_get_file("/", label) != 0 ||
        mac_get_link("/", label) != 0)
        return 49;
    if (mac_to_text(label, &mac_text) != 0 || mac_text == NULL ||
        strcmp(mac_text, "-") != 0)
        return 50;
    if (mac_free(label) != 0 || mac_free(mac_text) != 0)
        return 51;
    errno = 0;
    if (kqueue() != -1 || errno == 0)
        return 52;
    errno = 0;
    if (kevent(-1, NULL, 0, NULL, 0, NULL) != -1 || errno == 0)
        return 53;
    if (vis(vis_ch, 'x', 0, 0) != vis_ch + 1 || strcmp(vis_ch, "x") != 0)
        return 54;
    if (strvis(vis_buf, "abc", 0) != 3 || strcmp(vis_buf, "abc") != 0)
        return 55;
    if (strnvis(vis_buf, "abcdef", 4, 0) != 6 || strcmp(vis_buf, "abc") != 0)
        return 56;
    if (strvisx(vis_buf, "abcdef", 3, 0) != 3 || strcmp(vis_buf, "abc") != 0)
        return 57;
    if (strnvisx(vis_buf, "abcdef", 6, 4, 0) != 6 || strcmp(vis_buf, "abc") != 0)
        return 58;
    if (stravis(&allocated_vis, "abc", 0) != 3 || allocated_vis == NULL ||
        strcmp(allocated_vis, "abc") != 0)
        return 59;
    free(allocated_vis);
    allocated_vis = NULL;
    if (stravisx(&allocated_vis, "abcdef", 3, 0) != 3 ||
        allocated_vis == NULL || strcmp(allocated_vis, "abc") != 0)
        return 60;
    free(allocated_vis);
    allocated_vis = NULL;
    if (mbsavis(&allocated_vis, "abc", 0) != 3 || allocated_vis == NULL ||
        strcmp(allocated_vis, "abc") != 0)
        return 61;
    free(allocated_vis);
    if (strunvis(vis_buf, "abc") != 3 || strcmp(vis_buf, "abc") != 0)
        return 62;
    if (strnunvis(vis_buf, "abcdef", 4) != 6 || strcmp(vis_buf, "abc") != 0)
        return 63;
    if (unvis(vis_ch, 'q', &unvis_state, 0) != UNVIS_VALID || vis_ch[0] != 'q')
        return 64;
    if (setpassent(0) != 1 || setgroupent(0) != 1)
        return 40;
    srandom_deterministic(1);
    if (chflags("x", 0) != 0 || lchflags("x", 0) != 0 ||
        fchflags(0, 0) != 0 || chflagsat(0, "x", 0, 0) != 0)
        return 5;

    errno = 0;
    if (revoke("x") != -1 || errno == 0)
        return 6;
    errno = 0;
    if (lpathconf("x", 0) != -1 || errno != EINVAL)
        return 7;
    errno = 0;
    if (undelete("x") != -1 || errno == 0)
        return 8;

    strmode(S_IFDIR | 0755, mode_text);
    if (strcmp(mode_text, "drwxr-xr-x ") != 0)
        return 80;
    header = getbsize(&headerlen, &blocksize);
    if (header == NULL || strcmp(header, "512-blocks") != 0 ||
        headerlen != 10 || blocksize != 512)
        return 81;
    mode_set = setmode("0755");
    if (mode_set == NULL || getmode(mode_set, 0) != 0755)
        return 82;
    free(mode_set);
    mode_set = setmode("u+x,g-w");
    if (mode_set == NULL || getmode(mode_set, 0640) != 0740)
        return 83;
    free(mode_set);
    if (strtonum("42", 1, 100, &errstr) != 42 || errstr != NULL)
        return 84;
    if (strtonum("abc", 1, 100, &errstr) != 0 ||
        errstr == NULL || strcmp(errstr, "invalid") != 0)
        return 85;
    if (strtonum("0", 1, 100, &errstr) != 0 ||
        errstr == NULL || strcmp(errstr, "too small") != 0)
        return 86;
    if (strtonum("101", 1, 100, &errstr) != 0 ||
        errstr == NULL || strcmp(errstr, "too large") != 0)
        return 87;

    if (strtofflags(&empty_ptr, &set, &clr) != 0 || set != 0 || clr != 0)
        return 9;
    errno = 0;
    if (strtofflags(&bad_ptr, &set, &clr) != -1 || errno == 0)
        return 10;

    flags = fflagstostr(0);
    if (flags == NULL || strcmp(flags, "") != 0)
        return 11;
    free(flags);
    buf = recallocarray(NULL, 0, 4, 1);
    if (buf == NULL || buf[0] != 0 || buf[3] != 0)
        return 12;
    buf[0] = 0xaa;
    buf = recallocarray(buf, 4, 8, 1);
    if (buf == NULL || buf[0] != 0xaa || buf[4] != 0 || buf[7] != 0)
        return 13;
    freezero(buf, 8);
    return 0;
}
