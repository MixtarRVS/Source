/*
 * mixtar_auth_pam.c - PAM backend for the AILang mixtar-auth helper.
 *
 * The AILang program owns request validation, stdin-only secret intake,
 * identity normalization, and local secret scrubbing.  This file is only the
 * PAM conversation boundary, kept small because PAM is a C callback ABI.
 *
 * Build-time PAM headers are intentionally not required.  The helper loads the
 * system PAM runtime dynamically so a Mixtar build can stage only runtime PAM.
 */

#define _GNU_SOURCE

#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define MIXTAR_AUTH_OK 0
#define MIXTAR_AUTH_DENIED 1
#define MIXTAR_AUTH_MALFORMED 2
#define MIXTAR_AUTH_BACKEND_UNAVAILABLE 3
#define MIXTAR_AUTH_MAX_PAM_MESSAGES 16
#define MIXTAR_AUTH_DEFAULT_SERVICE "mixtar-login"

#define PAM_SUCCESS 0
#define PAM_BUF_ERR 5
#define PAM_PERM_DENIED 6
#define PAM_AUTH_ERR 7
#define PAM_USER_UNKNOWN 10
#define PAM_MAXTRIES 11
#define PAM_ACCT_EXPIRED 13
#define PAM_CRED_ERR 17
#define PAM_CONV_ERR 19

#define PAM_PROMPT_ECHO_OFF 1
#define PAM_PROMPT_ECHO_ON 2

typedef struct pam_handle pam_handle_t;

struct pam_message {
    int msg_style;
    const char *msg;
};

struct pam_response {
    char *resp;
    int resp_retcode;
};

struct pam_conv {
    int (*conv)(int, const struct pam_message **,
                struct pam_response **, void *);
    void *appdata_ptr;
};

typedef int (*mixtar_pam_start_fn)(const char *, const char *,
                                   const struct pam_conv *, pam_handle_t **);
typedef int (*mixtar_pam_authenticate_fn)(pam_handle_t *, int);
typedef int (*mixtar_pam_acct_mgmt_fn)(pam_handle_t *, int);
typedef int (*mixtar_pam_end_fn)(pam_handle_t *, int);

typedef struct MixtarPamApi {
    void *lib;
    mixtar_pam_start_fn pam_start;
    mixtar_pam_authenticate_fn pam_authenticate;
    mixtar_pam_acct_mgmt_fn pam_acct_mgmt;
    mixtar_pam_end_fn pam_end;
} MixtarPamApi;

typedef struct MixtarPamSecret {
    const char *bytes;
    size_t len;
} MixtarPamSecret;

static void
mixtar_secure_zero(void *ptr, size_t len)
{
    volatile unsigned char *p = (volatile unsigned char *)ptr;
    while (len > 0U) {
        *p++ = 0U;
        len--;
    }
}

static char *
mixtar_secret_copy(const MixtarPamSecret *secret)
{
    char *copy;

    if (secret == NULL || secret->bytes == NULL) {
        return NULL;
    }

    copy = (char *)calloc(secret->len + 1U, 1U);
    if (copy == NULL) {
        return NULL;
    }
    if (secret->len > 0U) {
        memcpy(copy, secret->bytes, secret->len);
    }
    copy[secret->len] = '\0';
    return copy;
}

static void
mixtar_free_replies(struct pam_response *replies, int count)
{
    if (replies == NULL) {
        return;
    }
    for (int i = 0; i < count; i++) {
        if (replies[i].resp != NULL) {
            mixtar_secure_zero(replies[i].resp, strlen(replies[i].resp));
            free(replies[i].resp);
        }
    }
    free(replies);
}

static int
mixtar_pam_converse(int num_msg, const struct pam_message **msg,
                    struct pam_response **resp, void *appdata_ptr)
{
    const MixtarPamSecret *secret = (const MixtarPamSecret *)appdata_ptr;
    struct pam_response *replies;

    if (num_msg <= 0 || num_msg > MIXTAR_AUTH_MAX_PAM_MESSAGES ||
        msg == NULL || resp == NULL || secret == NULL) {
        return PAM_CONV_ERR;
    }

    replies = (struct pam_response *)calloc((size_t)num_msg,
                                            sizeof(struct pam_response));
    if (replies == NULL) {
        return PAM_BUF_ERR;
    }

    for (int i = 0; i < num_msg; i++) {
        if (msg[i] == NULL) {
            mixtar_free_replies(replies, i);
            return PAM_CONV_ERR;
        }
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF ||
            msg[i]->msg_style == PAM_PROMPT_ECHO_ON) {
            replies[i].resp = mixtar_secret_copy(secret);
            if (replies[i].resp == NULL) {
                mixtar_free_replies(replies, i);
                return PAM_BUF_ERR;
            }
            replies[i].resp_retcode = 0;
        }
    }

    *resp = replies;
    return PAM_SUCCESS;
}

static size_t
mixtar_effective_secret_len(const char *secret, int64_t secret_len)
{
    size_t len;

    if (secret == NULL || secret_len <= 0) {
        return 0U;
    }
    len = (size_t)secret_len;
    while (len > 0U && (secret[len - 1U] == '\n' || secret[len - 1U] == '\r')) {
        len--;
    }
    return len;
}

static const char *
mixtar_pam_service_name(void)
{
    const char *override = getenv("MIXTAR_AUTH_PAM_SERVICE");
    if (override != NULL && override[0] != '\0') {
        return override;
    }
    return MIXTAR_AUTH_DEFAULT_SERVICE;
}

static int
mixtar_load_pam(MixtarPamApi *api)
{
    if (api == NULL) {
        return 0;
    }
    memset(api, 0, sizeof(*api));

    api->lib = dlopen("libpam.so.0", RTLD_NOW | RTLD_LOCAL);
    if (api->lib == NULL) {
        api->lib = dlopen("libpam.so", RTLD_NOW | RTLD_LOCAL);
    }
    if (api->lib == NULL) {
        return 0;
    }

    api->pam_start = (mixtar_pam_start_fn)dlsym(api->lib, "pam_start");
    api->pam_authenticate = (mixtar_pam_authenticate_fn)dlsym(
        api->lib, "pam_authenticate");
    api->pam_acct_mgmt = (mixtar_pam_acct_mgmt_fn)dlsym(
        api->lib, "pam_acct_mgmt");
    api->pam_end = (mixtar_pam_end_fn)dlsym(api->lib, "pam_end");

    if (api->pam_start == NULL || api->pam_authenticate == NULL ||
        api->pam_acct_mgmt == NULL || api->pam_end == NULL) {
        dlclose(api->lib);
        memset(api, 0, sizeof(*api));
        return 0;
    }
    return 1;
}

static int64_t
mixtar_auth_result_from_pam(int ret)
{
    if (ret == PAM_SUCCESS) {
        return MIXTAR_AUTH_OK;
    }
    if (ret == PAM_AUTH_ERR || ret == PAM_USER_UNKNOWN ||
        ret == PAM_MAXTRIES || ret == PAM_ACCT_EXPIRED ||
        ret == PAM_PERM_DENIED || ret == PAM_CRED_ERR) {
        return MIXTAR_AUTH_DENIED;
    }
    return MIXTAR_AUTH_BACKEND_UNAVAILABLE;
}

int64_t
mixtar_auth_backend_verify(const char *user, int64_t secret_ptr,
                           int64_t secret_len)
{
    const char *secret_bytes = (const char *)(uintptr_t)secret_ptr;
    MixtarPamSecret secret;
    MixtarPamApi api;
    struct pam_conv conv;
    pam_handle_t *pamh = NULL;
    int ret;

    if (user == NULL || user[0] == '\0' || secret_ptr == 0 || secret_len <= 0) {
        return MIXTAR_AUTH_MALFORMED;
    }

    secret.bytes = secret_bytes;
    secret.len = mixtar_effective_secret_len(secret_bytes, secret_len);
    if (secret.len == 0U) {
        return MIXTAR_AUTH_DENIED;
    }

    if (!mixtar_load_pam(&api)) {
        return MIXTAR_AUTH_BACKEND_UNAVAILABLE;
    }

    conv.conv = mixtar_pam_converse;
    conv.appdata_ptr = &secret;

    ret = api.pam_start(mixtar_pam_service_name(), user, &conv, &pamh);
    if (ret != PAM_SUCCESS || pamh == NULL) {
        dlclose(api.lib);
        return MIXTAR_AUTH_BACKEND_UNAVAILABLE;
    }

    ret = api.pam_authenticate(pamh, 0);
    if (ret == PAM_SUCCESS) {
        ret = api.pam_acct_mgmt(pamh, 0);
    }

    (void)api.pam_end(pamh, ret);
    dlclose(api.lib);
    return mixtar_auth_result_from_pam(ret);
}
