/* tests/userland/zlib.c: zlib from the sysroot: compress and uncompress a buffer.
 * Prints "<arch> zlib ok". GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team. */
#include <stdio.h>
#include <string.h>
#include <zlib.h>

int main(void)
{
    static const char text[] = "GFOpenAmigaGCC zlib zlib zlib zlib zlib zlib";
    unsigned char packed[128], back[128];
    uLongf n = sizeof packed, m = sizeof back;
    if (compress(packed, &n, (const Bytef *)text, sizeof text) != Z_OK)
        return 2;
    if (uncompress(back, &m, packed, n) != Z_OK || m != sizeof text || memcmp(back, text, m))
        return 3;
    printf("%s zlib ok\n", ARCH);
    return 0;
}
