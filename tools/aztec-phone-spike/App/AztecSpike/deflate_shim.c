// The prover library is linked against libdeflate's gzip calls, which iOS does
// not ship. These seven are the calls it makes, done with the system zlib.
#include <stdlib.h>
#include <zlib.h>

struct libdeflate_compressor { int level; };
struct libdeflate_decompressor { int unused; };

enum { LD_SUCCESS = 0, LD_BAD_DATA = 1, LD_SHORT_OUTPUT = 2, LD_INSUFFICIENT_SPACE = 3 };

struct libdeflate_compressor *libdeflate_alloc_compressor(int level) {
    struct libdeflate_compressor *c = malloc(sizeof *c);
    if (c) c->level = level < 0 ? Z_DEFAULT_COMPRESSION : (level > 9 ? 9 : level);
    return c;
}
void libdeflate_free_compressor(struct libdeflate_compressor *c) { free(c); }

size_t libdeflate_gzip_compress_bound(struct libdeflate_compressor *c, size_t n) {
    (void)c;
    return compressBound((uLong)n) + 32; // + the gzip header and trailer
}

size_t libdeflate_gzip_compress(struct libdeflate_compressor *c, const void *in, size_t n, void *out, size_t avail) {
    z_stream s = {0};
    if (deflateInit2(&s, c ? c->level : Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) return 0;
    s.next_in = (Bytef *)in; s.avail_in = (uInt)n;
    s.next_out = (Bytef *)out; s.avail_out = (uInt)avail;
    int r = deflate(&s, Z_FINISH);
    size_t written = s.total_out;
    deflateEnd(&s);
    return r == Z_STREAM_END ? written : 0; // 0: did not fit, as libdeflate reports it
}

struct libdeflate_decompressor *libdeflate_alloc_decompressor(void) { return calloc(1, sizeof(struct libdeflate_decompressor)); }
void libdeflate_free_decompressor(struct libdeflate_decompressor *d) { free(d); }

int libdeflate_gzip_decompress(struct libdeflate_decompressor *d, const void *in, size_t n, void *out, size_t avail, size_t *actual) {
    (void)d;
    z_stream s = {0};
    if (inflateInit2(&s, 15 + 16) != Z_OK) return LD_BAD_DATA;
    s.next_in = (Bytef *)in; s.avail_in = (uInt)n;
    s.next_out = (Bytef *)out; s.avail_out = (uInt)avail;
    int r = inflate(&s, Z_FINISH);
    size_t produced = s.total_out;
    inflateEnd(&s);
    if (r == Z_STREAM_END) {
        if (actual) { *actual = produced; return LD_SUCCESS; }
        return produced == avail ? LD_SUCCESS : LD_SHORT_OUTPUT;
    }
    if ((r == Z_BUF_ERROR || r == Z_OK) && produced == avail) return LD_INSUFFICIENT_SPACE;
    return LD_BAD_DATA;
}
