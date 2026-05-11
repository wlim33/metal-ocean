#pragma once
#include <cstdint>
#include <cstring>

namespace mo {
inline uint64_t fnv1a64(const void* data, size_t n, uint64_t seed = 0xcbf29ce484222325ull) {
    const uint8_t* p = (const uint8_t*)data;
    uint64_t h = seed;
    for (size_t i = 0; i < n; ++i) { h ^= p[i]; h *= 0x100000001b3ull; }
    return h;
}
}
