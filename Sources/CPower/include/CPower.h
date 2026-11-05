#ifndef CPOWER_H
#define CPOWER_H

#include <stdint.h>

// Power readings for Apple Silicon.
//  - IOReport "Energy Model": per-component energy counters (CPU, GPU, ANE, DRAM).
//    Private Apple API with no public header. Works without root. May change between macOS versions.
//  - SMC: single sensor values such as total system power. Also works without root.

typedef struct {
    char name[64];
    double watts;
} lanes_power_channel;

// Returns 1 on success. Safe to call more than once.
int lanes_power_init(void);

// Fills `out` with the average watts of each Energy Model channel since the previous call
// (the first call after init measures since init). Returns the number of channels, or -1 if
// IOReport is unavailable.
int lanes_power_read(lanes_power_channel *out, int max);

// Returns 1 if the SMC connection opened.
int lanes_smc_open(void);

// Reads a 4-character SMC key that holds a float (for example "PSTR"). Returns 1 and sets
// *value on success, 0 if the key is missing or not a float.
int lanes_smc_read_float(const char *key, double *value);

#endif
