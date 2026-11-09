/*
 * SPDX-License-Identifier: Apache-2.0
 * QoS / FDP placement stubs (WRR weights + RUH → region table).
 */
#ifndef AISSD_QOS_FDP_H
#define AISSD_QOS_FDP_H

#include <stdint.h>

#include "io_desc.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AISSD_FDP_MAX_RUH 32
#define AISSD_FDP_MAX_REGIONS 8

typedef struct aissd_wrr_cfg {
    uint16_t weight[AISSD_TC_COUNT]; /* relative WRR weights; 0 = parked */
} aissd_wrr_cfg_t;

typedef struct aissd_ruh_map_entry {
    uint16_t ruh;
    uint16_t region_id; /* placement region / RU grouping stub */
    uint8_t valid;
} aissd_ruh_map_entry_t;

/*
 * Region layout: each region owns a contiguous PBA range
 * [pba_base, pba_base + pba_count). Used by FTL placement.
 */
typedef struct aissd_region_layout {
    uint64_t pba_base;
    uint64_t pba_count;
    uint64_t next_free; /* bump allocator within region */
    uint8_t valid;
} aissd_region_layout_t;

typedef struct aissd_qos_fdp {
    aissd_wrr_cfg_t wrr;
    aissd_ruh_map_entry_t ruh_table[AISSD_FDP_MAX_RUH];
    uint32_t ruh_count;
    aissd_region_layout_t regions[AISSD_FDP_MAX_REGIONS];
} aissd_qos_fdp_t;

void aissd_qos_fdp_init_defaults(aissd_qos_fdp_t *q);

/*
 * Parse a tiny config line:
 *   "wrr <tc_index> <weight>"
 *   "ruh <id> <region>"
 *   "region <id> <pba_base> <pba_count>"
 */
int aissd_qos_fdp_apply_line(aissd_qos_fdp_t *q, const char *line);

/* Lookup placement region for RUH; returns 0 if unspecified / missing. */
uint16_t aissd_qos_fdp_region_for_ruh(const aissd_qos_fdp_t *q, uint16_t ruh);

/* Allocate next free PBA in region; returns UINT64_MAX on failure. */
uint64_t aissd_qos_fdp_alloc_pba(aissd_qos_fdp_t *q, uint16_t region_id);

/* Next traffic class under WRR (RR fallback when all weights equal). */
aissd_traffic_class_t aissd_qos_fdp_wrr_pick(aissd_qos_fdp_t *q,
                                             uint32_t *cursor);

#ifdef __cplusplus
}
#endif

#endif /* AISSD_QOS_FDP_H */
