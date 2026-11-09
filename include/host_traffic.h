/*
 * SPDX-License-Identifier: Apache-2.0
 * Host-side AI I/O pattern generator (inspired by LMCache/SGLang shapes, not a port).
 */
#ifndef AISSD_HOST_TRAFFIC_H
#define AISSD_HOST_TRAFFIC_H

#include <stdint.h>

#include "io_desc.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum aissd_traffic_pattern {
    AISSD_PAT_KV_OVERFLOW = 0, /* large LAT_READ burst (KV spill) */
    AISSD_PAT_EMBED_RAND = 1,  /* random small reads (embedding/ANN) */
    AISSD_PAT_CKPT_SEQ = 2     /* sequential BW_WRITE (checkpoint) */
} aissd_traffic_pattern_t;

typedef struct aissd_traffic_cfg {
    aissd_traffic_pattern_t pattern;
    uint32_t nsid;
    uint16_t ruh;
    uint32_t queue_id;   /* logical host SQ id */
    uint64_t lba_base;
    uint32_t count;      /* number of I/Os to generate */
    uint32_t page_size;  /* bytes per descriptor buffer */
    uint32_t seed;       /* RNG seed for random patterns */
} aissd_traffic_cfg_t;

typedef struct aissd_traffic_gen aissd_traffic_gen_t;

aissd_traffic_gen_t *aissd_traffic_create(const aissd_traffic_cfg_t *cfg);
void aissd_traffic_destroy(aissd_traffic_gen_t *g);

/* Fill next descriptor + own buffer; returns 0 when exhausted, 1 on success. */
int aissd_traffic_next(aissd_traffic_gen_t *g, aissd_io_desc_t *out);

uint32_t aissd_traffic_remaining(const aissd_traffic_gen_t *g);
const char *aissd_traffic_pattern_name(aissd_traffic_pattern_t p);

#ifdef __cplusplus
}
#endif

#endif /* AISSD_HOST_TRAFFIC_H */
