#include "df_raw_stubs.h"

int main(void) {
    if (e2fs_df(-1, (void *)0, (void *)0) != -1) {
        return 1;
    }
    if (ffs_df(-1, (void *)0, (void *)0) != -1) {
        return 2;
    }
    return 0;
}
