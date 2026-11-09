/*
 * SPDX-License-Identifier: Apache-2.0
 * Fixed-latency NAND simulation model (no FPGA / no Cosmos+ NFC).
 */
#ifndef AISSD_NAND_MODEL_H
#define AISSD_NAND_MODEL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define AISSD_NAND_LAT_HIST_BUCKETS 64

typedef struct aissd_nand_timing {
    uint32_t read_us;
    uint32_t prog_us;
    uint32_t erase_us;
    /* Optional bandwidth throttle: extra us per KiB transferred (0 = off). */
    uint32_t read_us_per_kib;
    uint32_t write_us_per_kib;
} aissd_nand_timing_t;

typedef struct aissd_nand_stats {
    uint64_t reads;
    uint64_t writes;
    uint64_t erases;
    uint64_t bytes_read;
    uint64_t bytes_written;
    uint64_t read_lat_sum_us;
    uint64_t write_lat_sum_us;
    uint32_t read_lat_max_us;
    uint32_t write_lat_max_us;
    /* Coarse latency histogram (us), shared for read+write samples. */
    uint64_t lat_hist[AISSD_NAND_LAT_HIST_BUCKETS];
    uint32_t lat_hist_bucket_us; /* width of each bucket */
} aissd_nand_stats_t;

typedef struct aissd_nand_model aissd_nand_model_t;

aissd_nand_model_t *aissd_nand_create(uint64_t page_count, uint32_t page_size,
                                      const aissd_nand_timing_t *timing);
void aissd_nand_destroy(aissd_nand_model_t *n);

uint32_t aissd_nand_page_size(const aissd_nand_model_t *n);
uint64_t aissd_nand_page_count(const aissd_nand_model_t *n);
uint64_t aissd_nand_sim_time_us(const aissd_nand_model_t *n);

/* Replace timing knobs after create (NULL keeps previous). */
void aissd_nand_set_timing(aissd_nand_model_t *n,
                           const aissd_nand_timing_t *timing);

const aissd_nand_stats_t *aissd_nand_stats(const aissd_nand_model_t *n);
void aissd_nand_stats_reset(aissd_nand_model_t *n);

/*
 * Approximate p99 latency from the histogram (us).
 * Returns 0 if no samples. op: 0=all, 1=read-biased hist (same hist in Gen-1).
 */
uint32_t aissd_nand_p99_latency_us(const aissd_nand_model_t *n);

/* Page R/W; erase marks page erased (subsequent read returns zeros). */
int aissd_nand_read_page(aissd_nand_model_t *n, uint64_t pba, void *dst,
                         size_t len);
int aissd_nand_write_page(aissd_nand_model_t *n, uint64_t pba, const void *src,
                          size_t len);
int aissd_nand_erase_page(aissd_nand_model_t *n, uint64_t pba);

/* Simple bad-block bitmap (set / test). */
int aissd_nand_mark_bad(aissd_nand_model_t *n, uint64_t pba);
int aissd_nand_is_bad(const aissd_nand_model_t *n, uint64_t pba);

#ifdef __cplusplus
}
#endif

#endif /* AISSD_NAND_MODEL_H */
