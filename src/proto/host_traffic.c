/*
 * SPDX-License-Identifier: Apache-2.0
 * Synthetic AI I/O shapes — not derived from LMCache/SGLang source.
 */
#include "host_traffic.h"

#include <stdlib.h>
#include <string.h>

struct aissd_traffic_gen {
    aissd_traffic_cfg_t cfg;
    uint32_t produced;
    uint32_t rng;
    uint8_t *arena; /* count * page_size */
};

static uint32_t xorshift32(uint32_t *state)
{
    uint32_t x = *state;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x ? x : 0xA5A5A5A5u;
    return *state;
}

const char *aissd_traffic_pattern_name(aissd_traffic_pattern_t p)
{
    switch (p) {
    case AISSD_PAT_KV_OVERFLOW:
        return "kv_overflow";
    case AISSD_PAT_EMBED_RAND:
        return "embed_rand";
    case AISSD_PAT_CKPT_SEQ:
        return "ckpt_seq";
    default:
        return "unknown";
    }
}

aissd_traffic_gen_t *aissd_traffic_create(const aissd_traffic_cfg_t *cfg)
{
    aissd_traffic_gen_t *g;

    if (!cfg || cfg->count == 0 || cfg->page_size == 0) {
        return NULL;
    }
    g = calloc(1, sizeof(*g));
    if (!g) {
        return NULL;
    }
    g->cfg = *cfg;
    g->rng = cfg->seed ? cfg->seed : 0xC0FFEEu;
    g->arena = calloc(cfg->count, cfg->page_size);
    if (!g->arena) {
        free(g);
        return NULL;
    }
    /* Pre-fill with pattern-specific marker bytes. */
    memset(g->arena, (int)(0x40 + (cfg->pattern & 0x3f)),
           (size_t)cfg->count * cfg->page_size);
    return g;
}

void aissd_traffic_destroy(aissd_traffic_gen_t *g)
{
    if (!g) {
        return;
    }
    free(g->arena);
    free(g);
}

uint32_t aissd_traffic_remaining(const aissd_traffic_gen_t *g)
{
    if (!g || g->produced >= g->cfg.count) {
        return 0;
    }
    return g->cfg.count - g->produced;
}

int aissd_traffic_next(aissd_traffic_gen_t *g, aissd_io_desc_t *out)
{
    uint32_t idx;
    uint64_t lba;
    aissd_io_op_t op;
    aissd_traffic_class_t tc;

    if (!g || !out || g->produced >= g->cfg.count) {
        return 0;
    }

    idx = g->produced++;
    switch (g->cfg.pattern) {
    case AISSD_PAT_KV_OVERFLOW:
        /* Sequential large-page reads — KV spill / restore shape. */
        op = AISSD_IO_READ;
        tc = AISSD_TC_LAT_READ;
        lba = g->cfg.lba_base + idx;
        break;
    case AISSD_PAT_EMBED_RAND: {
        uint32_t span = g->cfg.count * 4;
        if (span < 16) {
            span = 16;
        }
        op = AISSD_IO_READ;
        tc = AISSD_TC_LAT_READ;
        lba = g->cfg.lba_base + (xorshift32(&g->rng) % span);
        break;
    }
    case AISSD_PAT_CKPT_SEQ:
    default:
        op = AISSD_IO_WRITE;
        tc = AISSD_TC_BW_WRITE;
        lba = g->cfg.lba_base + idx;
        break;
    }

    aissd_io_desc_init(out, op, lba, 0, g->cfg.nsid);
    out->ruh = g->cfg.ruh;
    out->traffic_class = (uint8_t)tc;
    out->priority = (tc == AISSD_TC_LAT_READ) ? 0 : 8;
    out->host_tag = ((uint64_t)g->cfg.queue_id << 32) | idx;
    out->buf = g->arena + (size_t)idx * g->cfg.page_size;
    out->buf_len = g->cfg.page_size;
    /* Unique payload for write integrity. */
    if (op == AISSD_IO_WRITE) {
        memset(out->buf, (int)(0x80 | (idx & 0x7f)), g->cfg.page_size);
    }
    return 1;
}
