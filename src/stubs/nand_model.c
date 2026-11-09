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
    uint8_t *data;     /* page_count * page_size */
    uint8_t *valid;    /* 1 = programmed */
    uint8_t *bad;      /* 1 = bad */
};

static const aissd_nand_timing_t k_default_timing = {
    .read_us = 40,
    .prog_us = 500,
    .erase_us = 3000,
};

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

int aissd_nand_read_page(aissd_nand_model_t *n, uint64_t pba, void *dst,
                         size_t len)
{
    if (!n || !dst || pba >= n->page_count || len > n->page_size || n->bad[pba]) {
        return -1;
    }
    n->sim_time_us += n->timing.read_us;
    if (n->valid[pba]) {
        memcpy(dst, n->data + pba * n->page_size, len);
    } else {
        memset(dst, 0, len);
    }
    return 0;
}

int aissd_nand_write_page(aissd_nand_model_t *n, uint64_t pba, const void *src,
                          size_t len)
{
    if (!n || !src || pba >= n->page_count || len > n->page_size || n->bad[pba]) {
        return -1;
    }
    /* In-place rewrite without erase is allowed in this simple model. */
    memcpy(n->data + pba * n->page_size, src, len);
    if (len < n->page_size) {
        memset(n->data + pba * n->page_size + len, 0, n->page_size - len);
    }
    n->valid[pba] = 1;
    n->sim_time_us += n->timing.prog_us;
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
