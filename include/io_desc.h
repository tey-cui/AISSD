/*
 * SPDX-License-Identifier: Apache-2.0
 * Clean-room AISSD internal I/O descriptor (not derived from Cosmos+ sources).
 */
#ifndef AISSD_IO_DESC_H
#define AISSD_IO_DESC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opcode for the internal FE → FTL path. */
typedef enum aissd_io_op {
    AISSD_IO_READ = 0,
    AISSD_IO_WRITE = 1,
    AISSD_IO_FLUSH = 2,
    AISSD_IO_DISCARD = 3
} aissd_io_op_t;

/*
 * Traffic classes (Gen-1 QoS / scheduling tags).
 * Aligns with Project design plan TC_* names; values are AISSD-owned.
 */
typedef enum aissd_traffic_class {
    AISSD_TC_LAT_READ = 0, /* KV / vector hot read */
    AISSD_TC_BW_READ = 1,  /* prefetch / sequential read */
    AISSD_TC_BW_WRITE = 2, /* checkpoint / bulk write */
    AISSD_TC_META = 3,     /* FTL metadata / journal */
    AISSD_TC_BG = 4,       /* GC / WL / scrub */
    AISSD_TC_COUNT = 5
} aissd_traffic_class_t;

/* Unified internal command descriptor between host FE and FTL. */
typedef struct aissd_io_desc {
    uint64_t lba;          /* logical block address */
    uint32_t nlb;          /* number of logical blocks (0-based NVMe style + 1) */
    uint32_t nsid;         /* NVMe namespace id */
    uint16_t ruh;          /* FDP Reclaim Unit Handle (0 = unspecified) */
    uint8_t priority;      /* 0 = highest, 255 = lowest */
    uint8_t op;            /* aissd_io_op_t */
    uint8_t traffic_class; /* aissd_traffic_class_t */
    uint8_t flags;         /* reserved / future hints */
    uint64_t host_tag;     /* opaque host / CQ correlation */
    void *buf;             /* host or DMA buffer pointer (sim: user pointer) */
    uint32_t buf_len;      /* bytes available at buf */
} aissd_io_desc_t;

/* Zero-initialize and set required fields for a simple R/W. */
void aissd_io_desc_init(aissd_io_desc_t *d, aissd_io_op_t op, uint64_t lba,
                        uint32_t nlb, uint32_t nsid);

#ifdef __cplusplus
}
#endif

#endif /* AISSD_IO_DESC_H */
