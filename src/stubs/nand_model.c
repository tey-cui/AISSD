/*
 * SPDX-License-Identifier: Apache-2.0
 */
#include "nand_model.h"

#include <stdlib.h>
#include <string.h>

struct aissd_nand_model {
    uint64_t page_count;
    uint32_t page_size;
    aissd_nand_timing_t timing;
    uint64_t sim_time_us;
    uint8_t *data;  /* page_count * page_size */
    uint8_t *valid; /* 1 = programmed */
    uint8_t *bad;   /* 1 = bad */
    aissd_nand_stats_t stats;
};

static const aissd_nand_timing_t k_default_timing = {
    .read_us = 40,
    .prog_us = 500,
    .erase_us = 3000,
    .read_us_per_kib = 0,
    .write_us_per_kib = 0,
};

static uint32_t xfer_extra_us(uint32_t us_per_kib, size_t len)
{
    if (us_per_kib == 0 || len == 0) {
        return 0;
    }
    return (uint32_t)(((len + 1023u) / 1024u) * (uint64_t)us_per_kib);
}

static void record_latency(aissd_nand_model_t *n, uint32_t lat_us, int is_write)
{
    uint32_t bucket;
    uint32_t width;

    if (is_write) {
        n->stats.write_lat_sum_us += lat_us;
        if (lat_us > n->stats.write_lat_max_us) {
            n->stats.write_lat_max_us = lat_us;
        }
    } else {
        n->stats.read_lat_sum_us += lat_us;
        if (lat_us > n->stats.read_lat_max_us) {
            n->stats.read_lat_max_us = lat_us;
        }
    }

    width = n->stats.lat_hist_bucket_us;
    if (width == 0) {
        width = 50;
        n->stats.lat_hist_bucket_us = width;
    }
    bucket = lat_us / width;
    if (bucket >= AISSD_NAND_LAT_HIST_BUCKETS) {
        bucket = AISSD_NAND_LAT_HIST_BUCKETS - 1;
    }
    n->stats.lat_hist[bucket]++;
}

aissd_nand_model_t *aissd_nand_create(uint64_t page_count, uint32_t page_size,
                                      const aissd_nand_timing_t *timing)
{
    aissd_nand_model_t *n;

    if (page_count == 0 || page_size == 0) {
        return NULL;
    }

    n = calloc(1, sizeof(*n));
    if (!n) {
        return NULL;
    }

    n->page_count = page_count;
    n->page_size = page_size;
    n->timing = timing ? *timing : k_default_timing;
    n->stats.lat_hist_bucket_us = 50;
    n->data = calloc(page_count, page_size);
    n->valid = calloc(page_count, 1);
    n->bad = calloc(page_count, 1);
    if (!n->data || !n->valid || !n->bad) {
        aissd_nand_destroy(n);
        return NULL;
    }
    return n;
}

void aissd_nand_destroy(aissd_nand_model_t *n)
{
    if (!n) {
        return;
    }
    free(n->data);
    free(n->valid);
    free(n->bad);
    free(n);
}

uint32_t aissd_nand_page_size(const aissd_nand_model_t *n)
{
    return n ? n->page_size : 0;
}

uint64_t aissd_nand_page_count(const aissd_nand_model_t *n)
{
    return n ? n->page_count : 0;
}

uint64_t aissd_nand_sim_time_us(const aissd_nand_model_t *n)
{
    return n ? n->sim_time_us : 0;
}

void aissd_nand_set_timing(aissd_nand_model_t *n,
                           const aissd_nand_timing_t *timing)
{
    if (!n || !timing) {
        return;
    }
    n->timing = *timing;
}

const aissd_nand_stats_t *aissd_nand_stats(const aissd_nand_model_t *n)
{
    return n ? &n->stats : NULL;
}

void aissd_nand_stats_reset(aissd_nand_model_t *n)
{
    uint32_t bucket_us;

    if (!n) {
        return;
    }
    bucket_us = n->stats.lat_hist_bucket_us;
    memset(&n->stats, 0, sizeof(n->stats));
    n->stats.lat_hist_bucket_us = bucket_us ? bucket_us : 50;
}

uint32_t aissd_nand_p99_latency_us(const aissd_nand_model_t *n)
{
    uint64_t total = 0;
    uint64_t need;
    uint64_t seen = 0;
    uint32_t i;
    uint32_t width;

    if (!n) {
        return 0;
    }
    for (i = 0; i < AISSD_NAND_LAT_HIST_BUCKETS; i++) {
        total += n->stats.lat_hist[i];
    }
    if (total == 0) {
        return 0;
    }
    need = (total * 99 + 99) / 100; /* ceil(total * 0.99) */
    if (need == 0) {
        need = 1;
    }
    width = n->stats.lat_hist_bucket_us ? n->stats.lat_hist_bucket_us : 50;
    for (i = 0; i < AISSD_NAND_LAT_HIST_BUCKETS; i++) {
        seen += n->stats.lat_hist[i];
        if (seen >= need) {
            return (i + 1) * width;
        }
    }
    return AISSD_NAND_LAT_HIST_BUCKETS * width;
}

int aissd_nand_read_page(aissd_nand_model_t *n, uint64_t pba, void *dst,
                         size_t len)
{
    uint32_t lat;

    if (!n || !dst || pba >= n->page_count || len > n->page_size || n->bad[pba]) {
        return -1;
    }
    lat = n->timing.read_us + xfer_extra_us(n->timing.read_us_per_kib, len);
    n->sim_time_us += lat;
    if (n->valid[pba]) {
        memcpy(dst, n->data + pba * n->page_size, len);
    } else {
        memset(dst, 0, len);
    }
    n->stats.reads++;
    n->stats.bytes_read += len;
    record_latency(n, lat, 0);
    return 0;
}

int aissd_nand_write_page(aissd_nand_model_t *n, uint64_t pba, const void *src,
                          size_t len)
{
    uint32_t lat;

    if (!n || !src || pba >= n->page_count || len > n->page_size || n->bad[pba]) {
        return -1;
    }
    /* In-place rewrite without erase is allowed in this simple model. */
    memcpy(n->data + pba * n->page_size, src, len);
    if (len < n->page_size) {
        memset(n->data + pba * n->page_size + len, 0, n->page_size - len);
    }
    n->valid[pba] = 1;
    lat = n->timing.prog_us + xfer_extra_us(n->timing.write_us_per_kib, len);
    n->sim_time_us += lat;
    n->stats.writes++;
    n->stats.bytes_written += len;
    record_latency(n, lat, 1);
    return 0;
}

int aissd_nand_erase_page(aissd_nand_model_t *n, uint64_t pba)
{
    if (!n || pba >= n->page_count || n->bad[pba]) {
        return -1;
    }
    memset(n->data + pba * n->page_size, 0xFF, n->page_size);
    n->valid[pba] = 0;
    n->sim_time_us += n->timing.erase_us;
    n->stats.erases++;
    return 0;
}

int aissd_nand_mark_bad(aissd_nand_model_t *n, uint64_t pba)
{
    if (!n || pba >= n->page_count) {
        return -1;
    }
    n->bad[pba] = 1;
    return 0;
}

int aissd_nand_is_bad(const aissd_nand_model_t *n, uint64_t pba)
{
    if (!n || pba >= n->page_count) {
        return 1;
    }
    return n->bad[pba] ? 1 : 0;
}
