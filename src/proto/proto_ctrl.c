/*
 * SPDX-License-Identifier: Apache-2.0
 */
#include "proto_ctrl.h"

#include <stdlib.h>
#include <string.h>

typedef struct aissd_sq {
    aissd_io_desc_t *slots[AISSD_PROTO_SQ_DEPTH];
    uint32_t head;
    uint32_t tail;
    uint32_t count;
} aissd_sq_t;

struct aissd_proto_ctrl {
    aissd_ftl_t *ftl;
    aissd_qos_fdp_t *qos;
    uint32_t num_queues;
    aissd_sq_t sq[AISSD_PROTO_MAX_QUEUES];
    uint32_t wrr_cursor;
    uint32_t rr_qid;
    aissd_proto_stats_t stats;
    int saw_lat_read;
};

aissd_proto_ctrl_t *aissd_proto_create(aissd_ftl_t *ftl, aissd_qos_fdp_t *qos,
                                       uint32_t num_queues)
{
    aissd_proto_ctrl_t *c;

    if (!ftl || num_queues == 0 || num_queues > AISSD_PROTO_MAX_QUEUES) {
        return NULL;
    }
    c = calloc(1, sizeof(*c));
    if (!c) {
        return NULL;
    }
    c->ftl = ftl;
    c->qos = qos;
    c->num_queues = num_queues;
    if (qos) {
        aissd_ftl_set_qos(ftl, qos);
    }
    return c;
}

void aissd_proto_destroy(aissd_proto_ctrl_t *c)
{
    free(c);
}

aissd_status_t aissd_proto_enqueue(aissd_proto_ctrl_t *c, uint32_t qid,
                                   aissd_io_desc_t *desc)
{
    aissd_sq_t *q;

    if (!c || !desc || qid >= c->num_queues) {
        return AISSD_ERR_INVAL;
    }
    q = &c->sq[qid];
    if (q->count >= AISSD_PROTO_SQ_DEPTH) {
        c->stats.dropped++;
        return AISSD_ERR_BUSY;
    }
    q->slots[q->tail] = desc;
    q->tail = (q->tail + 1) % AISSD_PROTO_SQ_DEPTH;
    q->count++;
    c->stats.enqueued++;
    return AISSD_OK;
}

static aissd_io_desc_t *sq_pop_head(aissd_sq_t *q)
{
    aissd_io_desc_t *d;

    if (q->count == 0) {
        return NULL;
    }
    d = q->slots[q->head];
    q->slots[q->head] = NULL;
    q->head = (q->head + 1) % AISSD_PROTO_SQ_DEPTH;
    q->count--;
    return d;
}

/* Remove first descriptor matching traffic class (scan from head). */
static aissd_io_desc_t *sq_pop_tc(aissd_sq_t *q, aissd_traffic_class_t tc)
{
    uint32_t i;
    uint32_t idx;
    uint32_t found;
    aissd_io_desc_t *d;
    aissd_io_desc_t *tmp[AISSD_PROTO_SQ_DEPTH];
    uint32_t n = 0;

    if (q->count == 0) {
        return NULL;
    }

    found = UINT32_MAX;
    for (i = 0; i < q->count; i++) {
        idx = (q->head + i) % AISSD_PROTO_SQ_DEPTH;
        if (q->slots[idx] && q->slots[idx]->traffic_class == (uint8_t)tc) {
            found = i;
            break;
        }
    }
    if (found == UINT32_MAX) {
        return NULL;
    }

    /* Rebuild queue skipping the found entry. */
    d = NULL;
    for (i = 0; i < q->count; i++) {
        idx = (q->head + i) % AISSD_PROTO_SQ_DEPTH;
        if (i == found) {
            d = q->slots[idx];
            continue;
        }
        tmp[n++] = q->slots[idx];
    }
    q->head = 0;
    q->tail = 0;
    q->count = 0;
    memset(q->slots, 0, sizeof(q->slots));
    for (i = 0; i < n; i++) {
        q->slots[q->tail] = tmp[i];
        q->tail = (q->tail + 1) % AISSD_PROTO_SQ_DEPTH;
        q->count++;
    }
    return d;
}

uint32_t aissd_proto_drain(aissd_proto_ctrl_t *c, uint32_t max_ops)
{
    uint32_t done = 0;
    uint32_t idle_rounds = 0;
    aissd_io_desc_t *desc;
    aissd_io_desc_t *completed[16];
    uint32_t n;
    aissd_traffic_class_t prefer;
    uint32_t qid;
    uint32_t i;
    uint32_t hq;

    if (!c || max_ops == 0) {
        return 0;
    }

    c->saw_lat_read = 0;

    while (done < max_ops && idle_rounds < c->num_queues * AISSD_TC_COUNT + 2) {
        prefer = AISSD_TC_LAT_READ;
        if (c->qos) {
            prefer = aissd_qos_fdp_wrr_pick(c->qos, &c->wrr_cursor);
        }
        desc = NULL;

        for (i = 0; i < c->num_queues; i++) {
            qid = (c->rr_qid + i) % c->num_queues;
            desc = sq_pop_tc(&c->sq[qid], prefer);
            if (desc) {
                c->rr_qid = (qid + 1) % c->num_queues;
                break;
            }
        }

        if (!desc) {
            for (i = 0; i < c->num_queues; i++) {
                qid = (c->rr_qid + i) % c->num_queues;
                desc = sq_pop_head(&c->sq[qid]);
                if (desc) {
                    c->rr_qid = (qid + 1) % c->num_queues;
                    break;
                }
            }
        }

        if (!desc) {
            idle_rounds++;
            continue;
        }
        idle_rounds = 0;

        if (desc->traffic_class == AISSD_TC_LAT_READ) {
            c->saw_lat_read = 1;
        }

        if (aissd_ftl_submit(c->ftl, desc) != AISSD_OK) {
            c->stats.dropped++;
            continue;
        }
        c->stats.submitted++;
        if (desc->nsid <= AISSD_PROTO_MAX_NS) {
            c->stats.per_ns_ios[desc->nsid]++;
        }
        if (desc->traffic_class < AISSD_TC_COUNT) {
            c->stats.per_tc_ios[desc->traffic_class]++;
        }
        hq = (uint32_t)(desc->host_tag >> 32);
        if (hq < AISSD_PROTO_MAX_QUEUES) {
            c->stats.per_q_ios[hq]++;
        }

        n = aissd_ftl_poll_complete(c->ftl, completed, 16);
        c->stats.completed += n;
        done++;
    }

    if (!c->saw_lat_read) {
        aissd_ftl_gc_resume(c->ftl);
        (void)aissd_ftl_gc_tick(c->ftl);
    } else {
        /* Keep GC suspended while serving latency-sensitive reads. */
        (void)aissd_ftl_gc_tick(c->ftl); /* counts blocked ticks */
    }

    return done;
}

const aissd_proto_stats_t *aissd_proto_stats(const aissd_proto_ctrl_t *c)
{
    return c ? &c->stats : NULL;
}
