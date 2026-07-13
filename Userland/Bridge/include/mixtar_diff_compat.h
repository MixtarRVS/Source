/* Mixtar Bridge compatibility for OpenBSD diff.
 *
 * OpenBSD diff has an internal helper named splice(3), while Linux exposes
 * splice(2) from <fcntl.h>. Include the Linux header first, then rename only
 * the OpenBSD helper at preprocessor level.
 */
#ifndef MIXTAR_DIFF_COMPAT_H
#define MIXTAR_DIFF_COMPAT_H

#include <fcntl.h>

#define splice mixtar_diff_splice

#endif
