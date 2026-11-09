/*
 * SPDX-License-Identifier: Apache-2.0
 * Clean-room FTL hooks for Gen-1 sim path (identity L2P + GC suspend points).
 */
#ifndef AISSD_FTL_HOOKS_H
#define AISSD_FTL_HOOKS_H

#include <stdint.h>

#include "io_desc.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum aissd_status {
    AISSD_OK = 0,
    AISSD_ERR_INVAL = 1,
    AISSD_ERR_NOSPC = 2,
    AISSD_ERR_IO = 3,
    AISSD_ERR_BUSY = 4
} aissd_status_t;

typedef struct aissd_ftl aissd_ftl_t;

/* Create / destroy a host-side FTL stub bound to a NAND model handle. */
aissd_ftl_t *aissd_ftl_create(void *nand);
void aissd_ftl_destroy(aissd_ftl_t *ftl);

/* Submit one io_desc; may complete synchronously in the sim stub. */
aissd_status_t aissd_ftl_submit(aissd_ftl_t *ftl, aissd_io_desc_t *desc);

/* Poll / drain completions; returns number completed into out[] (max n). */
uint32_t aissd_ftl_poll_complete(aissd_ftl_t *ftl, aissd_io_desc_t **out,
                                 uint32_t n);

/* GC policy hooks — stubs for WP-2. */
int aissd_ftl_gc_may_run(aissd_ftl_t *ftl);
void aissd_ftl_gc_suspend_for_lat_read(aissd_ftl_t *ftl);

/* Simple identity L2P helpers (page-granularity). */
uint64_t aissd_ftl_l2p_lookup(aissd_ftl_t *ftl, uint64_t lba);
aissd_status_t aissd_ftl_l2p_update(aissd_ftl_t *ftl, uint64_t lba,
                                    uint64_t pba);

#ifdef __cplusplus
}
#endif

#endif /* AISSD_FTL_HOOKS_H */
