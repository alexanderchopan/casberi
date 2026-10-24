#include "TorShim.h"

// tor's own version string, from the linked archive (`lib/version/git_revision`'s
// `get_version()`, the string `tor --version` prints).
const char *get_version(void);

const char *torshim_version(void) {
    return get_version();
}
