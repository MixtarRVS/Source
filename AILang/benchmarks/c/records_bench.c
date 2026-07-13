#include <stdint.h>
#include <stdio.h>

typedef struct {
    int32_t x;
    int32_t y;
} Point;

uint32_t records_bench(int32_t iterations) {
    Point p = {1, 2};
    const int32_t modulus = 1000000007;
    uint32_t checksum = 0;

    for (int32_t i = 0; i < iterations; i++) {
        p.x = (p.x + p.y) % modulus;
        p.y = (p.y + 2) % modulus;
        checksum += p.x + p.y;
    }

    return checksum;
}

int main(void) {
    int32_t iterations = 4000000;
    uint32_t result = records_bench(iterations);
    printf("%u\n", result);
    return 0;
}
