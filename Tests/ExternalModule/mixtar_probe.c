#include <linux/init.h>
#include <linux/module.h>

static int __init mixtar_probe_init(void)
{
    return 0;
}

static void __exit mixtar_probe_exit(void)
{
}

module_init(mixtar_probe_init);
module_exit(mixtar_probe_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Mixtar external module SDK acceptance probe");
