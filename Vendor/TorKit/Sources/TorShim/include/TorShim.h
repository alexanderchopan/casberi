#ifndef TORSHIM_H
#define TORSHIM_H

// tor's embedding API, `feature/api/tor_api.h` from tor 0.4.9.14, restated for
// a Clang module (see Package.swift). Unix only: the control socket is an int.

typedef struct tor_main_configuration_t tor_main_configuration_t;
typedef int tor_control_socket_t;

tor_main_configuration_t *tor_main_configuration_new(void);
int tor_main_configuration_set_command_line(tor_main_configuration_t *cfg,
                                            int argc, char *argv[]);
/// An owning controller: already authenticated, and tor exits when it closes.
tor_control_socket_t tor_main_configuration_setup_control_socket(
                                          tor_main_configuration_t *cfg);
void tor_main_configuration_free(tor_main_configuration_t *cfg);
const char *tor_api_get_provider_version(void);
/// Blocks until tor exits. Run it on a thread of its own.
int tor_run_main(const tor_main_configuration_t *);

/// The linked tor's version, e.g. "0.4.9.14" — proves the archive linked.
const char *torshim_version(void);

#endif
