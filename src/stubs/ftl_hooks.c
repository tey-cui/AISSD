/*
 * SPDX-License-Identifier: Apache-2.0
 */
#include "ftl_hooks.h"

#include <stdlib.h>
#include <string.h>

#include "nand_model.h"

#define AISSD_FTL_CQ_DEPTH 64
#define AISSD_FTL_L2P_SLOTS 4096

struct aissd_ftl {
    aissd_nand_model_t *nand;
    int gc_suspended;
    aissd_io_desc_t *cq[AISSD_FTL_CQ_DEPTH];
    uint32_t cq_head;
    uint32_t cq_tail;
    uint32_t cq_count;
    uint64_t l2p[AISSD_FTL_L2P_SLOTS];
    uint8_t l2p_valid[AISSD_FTL_L2P_SLOTS];
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

static aissd_status_t cq_push(aissd_ftl_t *ftl, aissd_io_desc_t *desc)
{
    if (ftl->cq_count >= AISSD_FTL_CQ_DEPTH) {
        return AISSD_ERR_BUSY;
    }
    ftl->cq[ftl->cq_tail] = desc;
    ftl->cq_tail = (ftl->cq_tail + 1) % AISSD_FTL_CQ_DEPTH;
    ftl->cq_count++;
    return AISSD_OK;
}

aissd_status_t aissd_ftl_submit(aissd_ftl_t *ftl, aissd_io_desc_t *desc)
{
    uint64_t pba;
    uint32_t page_size;
    int rc;

    if (!ftl || !desc) {
        return AISSD_ERR_INVAL;
    }
    if (desc->traffic_class == AISSD_TC_LAT_READ) {
        aissd_ftl_gc_suspend_for_lat_read(ftl);
    }

    page_size = aissd_nand_page_size(ftl->nand);
    if (page_size == 0 || !desc->buf || desc->buf_len < page_size) {
        return AISSD_ERR_INVAL;
    }

    pba = aissd_ftl_l2p_lookup(ftl, desc->lba);
    if (pba == UINT64_MAX || pba >= aissd_nand_page_count(ftl->nand)) {
        return AISSD_ERR_INVAL;
    }

    if (desc->op == AISSD_IO_WRITE) {
        rc = aissd_nand_write_page(ftl->nand, pba, desc->buf, page_size);
        if (rc != 0) {
            return AISSD_ERR_IO;
        }
        (void)aissd_ftl_l2p_update(ftl, desc->lba, pba);
    } else if (desc->op == AISSD_IO_READ) {
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
        ftl->gc_suspended = 1;
    }
}
