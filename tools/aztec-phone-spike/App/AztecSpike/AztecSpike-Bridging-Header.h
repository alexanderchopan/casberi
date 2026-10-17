// Aztec's native iOS prover (barretenberg, libbb-external.a) exports one C
// entry: msgpack command in, msgpack response out. With no scratch buffer the
// response is always freshly allocated (aligned_alloc), so the caller frees it.
#include <stddef.h>
#include <stdint.h>
void bbapi(const uint8_t *input, size_t input_len, uint8_t **output, size_t *output_len);
