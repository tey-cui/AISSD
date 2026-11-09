/*
 * SPDX-License-Identifier: Apache-2.0
 */
#include "ftl_hooks.h"

#include <stdlib.h>
#include <string.h>

#include "nand_model.h"

#define AISSD_FTL_CQ_DEPTH 256
#define AISSD_FTL_L2P_SLOTS 8192

struct aissd_ftl {
    aissd_nand_model_t *nand;
    aissd_qos_fdp_t *qos;
    int gc_suspended;
    uint64_t gc_victim;
    aissd_io_desc_t *cq[AISSD_FTL_CQ_DEPTH];
    uint32_t cq_head;
    uint32_t cq_tail;
    uint32_t cq_count;
    uint64_t l2p[AISSD_FTL_L2P_SLOTS];
    uint8_t l2p_valid[AISSD_FTL_L2P_SLOTS];
    aissd_ftl_stats_t stats;
};

aissd_ftl_t *aissd_ftl_create(void *nand)
{
    aissd_ftl_t *ftl;
    uint32_t i;

    if (!nand) {
        return NULL;
    }
    ftl = calloc(1, sizeof(*ftl));
    if (!ftl) {
        return NULL;
    }
    ftl->nand = (aissd_nand_model_t *)nand;
    for (i = 0; i < AISSD_FTL_L2P_SLOTS; i++) {
        ftl->l2p[i] = i; /* identity map default */
        ftl->l2p_valid[i] = 1;
    }
    return ftl;
}

void aissd_ftl_destroy(aissd_ftl_t *ftl)
{
    free(ftl);
}

void aissd_ftl_set_qos(aissd_ftl_t *ftl, aissd_qos_fdp_t *qos)
{
    if (ftl) {
        ftl->qos = qos;
    }
}

uint64_t aissd_ftl_l2p_lookup(aissd_ftl_t *ftl, uint64_t lba)
{
    if (!ftl || lba >= AISSD_FTL_L2P_SLOTS || !ftl->l2p_valid[lba]) {
        return UINT64_MAX;
    }
    return ftl->l2p[lba];
}

aissd_status_t aissd_ftl_l2p_update(aissd_ftl_t *ftl, uint64_t lba, uint64_t pba)
{
    if (!ftl || lba >= AISSD_FTL_L2P_SLOTS) {
        return AISSD_ERR_INVAL;
    }
    ftl->l2p[lba] = pba;
    ftl->l2p_valid[lba] = 1;
    return AISSD_OK;
}

uint16_t aissd_ftl_resolve_region(aissd_ftl_t *ftl, const aissd_io_desc_t *desc)
{
    uint16_t region = 0;

    if (!ftl || !desc) {
        return 0;
    }
    if (ftl->qos && desc->ruh != 0) {
        region = aissd_qos_fdp_region_for_ruh(ftl->qos, desc->ruh);
        ftl->stats.placement_resolves++;
    }
    return region;
}

static aissd_status_t cq_push(aissd_ftl_t *ftl, aissd_io_desc_t *desc)
{
    if (ftl->cq_count >= AISSD_FTL_CQ_DEPTH) {
        return AISSD_ERR_BUSY;
    }
    ftl->cq[ftl->cq_tail] = desc;
    ftl->cq_tail = (ftl->cq_tail + 1) % AISSD_FTL_CQ_DEPTH;
    ftl->cq_count++;
    ftl->stats.completes++;
    return AISSD_OK;
}

static uint64_t place_write_pba(aissd_ftl_t *ftl, aissd_io_desc_t *desc)
{
    uint16_t region;
    uint64_t pba;

    region = aissd_ftl_resolve_region(ftl, desc);
    if (ftl->qos && ftl->qos->regions[region].valid) {
        pba = aissd_qos_fdp_alloc_pba(ftl->qos, region);
        if (pba != UINT64_MAX) {
            return pba;
        }
    }
    /* Fallback: identity / existing L2P slot. */
    pba = aissd_ftl_l2p_lookup(ftl, desc->lba);
    if (pba == UINT64_MAX) {
        pba = desc->lba;
    }
    return pba;
}

aissd_status_t aissd_ftl_submit(aissd_ftl_t *ftl, aissd_io_desc_t *desc)
{
    uint64_t pba;
    uint32_t page_size;
    int rc;

    if (!ftl || !desc) {
        return AISSD_ERR_INVAL;
    }
    ftl->stats.submits++;

    if (desc->traffic_class == AISSD_TC_LAT_READ) {
        aissd_ftl_gc_suspend_for_lat_read(ftl);
    }

    page_size = aissd_nand_page_size(ftl->nand);
    if (page_size == 0 || !desc->buf || desc->buf_len < page_size) {
        return AISSD_ERR_INVAL;
    }

    if (desc->op == AISSD_IO_WRITE) {
        pba = place_write_pba(ftl, desc);
        if (pba >= aissd_nand_page_count(ftl->nand)) {
            return AISSD_ERR_NOSPC;
        }
        rc = aissd_nand_write_page(ftl->nand, pba, desc->buf, page_size);
        if (rc != 0) {
            return AISSD_ERR_IO;
        }
        if (aissd_ftl_l2p_update(ftl, desc->lba, pba) != AISSD_OK) {
            return AISSD_ERR_INVAL;
        }
    } else if (desc->op == AISSD_IO_READ) {
        pba = aissd_ftl_l2p_lookup(ftl, desc->lba);
        if (pba == UINT64_MAX || pba >= aissd_nand_page_count(ftl->nand)) {
            return AISSD_ERR_INVAL;
        }
        /* Still resolve RUH for telemetry even on reads. */
        (void)aissd_ftl_resolve_region(ftl, desc);
        rc = aissd_nand_read_page(ftl->nand, pba, desc->buf, page_size);
        if (rc != 0) {
            return AISSD_ERR_IO;
        }
    } else {
        /* FLUSH / DISCARD: no-op success in stub. */
    }

    return cq_push(ftl, desc);
}

uint32_t aissd_ftl_poll_complete(aissd_ftl_t *ftl, aissd_io_desc_t **out,
                                 uint32_t n)
{
    uint32_t done = 0;

    if (!ftl || !out || n == 0) {
        return 0;
    }
    while (done < n && ftl->cq_count > 0) {
        out[done++] = ftl->cq[ftl->cq_head];
        ftl->cq[ftl->cq_head] = NULL;
        ftl->cq_head = (ftl->cq_head + 1) % AISSD_FTL_CQ_DEPTH;
        ftl->cq_count--;
    }
    return done;
}

int aissd_ftl_gc_may_run(aissd_ftl_t *ftl)
{
    if (!ftl || ftl->gc_suspended) {
        return 0;
    }
    return 1;
}

void aissd_ftl_gc_suspend_for_lat_read(aissd_ftl_t *ftl)
{
    if (ftl) {
        if (!ftl->gc_suspended) {
            ftl->stats.gc_suspends++;
        }
        ftl->gc_suspended = 1;
    }
}

void aissd_ftl_gc_resume(aissd_ftl_t *ftl)
{
    if (ftl) {
        ftl->gc_suspended = 0;
    }
}

int aissd_ftl_gc_tick(aissd_ftl_t *ftl)
{
    uint64_t pages;
    uint64_t victim;

    if (!ftl) {
        return -1;
    }
    if (!aissd_ftl_gc_may_run(ftl)) {
        ftl->stats.gc_blocked_ticks++;
        return 0;
    }
    pages = aissd_nand_page_count(ftl->nand);
    if (pages == 0) {
        return 0;
    }
    victim = ftl->gc_victim % pages;
    ftl->gc_victim = victim + 1;
    /* Skip user-mapped low pages; GC victims start in upper half. */
    if (victim < pages / 2) {
        victim = pages / 2 + (victim % (pages - pages / 2));
    }
    if (aissd_nand_is_bad(ftl->nand, victim)) {
        return 0;
    }
    if (aissd_nand_erase_page(ftl->nand, victim) != 0) {
        return -1;
    }
    ftl->stats.gc_runs++;
    return 1;
}

const aissd_ftl_stats_t *aissd_ftl_stats(const aissd_ftl_t *ftl)
{
    return ftl ? &ftl->stats : NULL;
}
