/*
 * SPDX-License-Identifier: Apache-2.0
 * Simulation prototype controller: multi-queue / multi-NS submission path.
 */
#ifndef AISSD_PROTO_CTRL_H
#define AISSD_PROTO_CTRL_H

#include <stdint.h>

#include "ftl_hooks.h"
#include "io_desc.h"
#include "qos_fdp.h"

#ifdef __cplusplus
extern "C" {
#endif

#define AISSD_PROTO_MAX_QUEUES 8
#define AISSD_PROTO_MAX_NS 4
#define AISSD_PROTO_SQ_DEPTH 128

typedef struct aissd_proto_stats {
    uint64_t enqueued;
    uint64_t submitted;
    uint64_t completed;
    uint64_t dropped;
    uint64_t per_ns_ios[AISSD_PROTO_MAX_NS + 1];
    uint64_t per_q_ios[AISSD_PROTO_MAX_QUEUES];
    uint64_t per_tc_ios[AISSD_TC_COUNT];
} aissd_proto_stats_t;

typedef struct aissd_proto_ctrl aissd_proto_ctrl_t;

aissd_proto_ctrl_t *aissd_proto_create(aissd_ftl_t *ftl, aissd_qos_fdp_t *qos,
                                       uint32_t num_queues);
void aissd_proto_destroy(aissd_proto_ctrl_t *c);

/* Enqueue descriptor onto host SQ (copies pointer; caller owns desc lifetime). */
aissd_status_t aissd_proto_enqueue(aissd_proto_ctrl_t *c, uint32_t qid,
                                   aissd_io_desc_t *desc);

/*
 * Drain up to max_ops using WRR traffic-class preference across queues.
 * Also runs a GC tick when no LAT_READ was seen in this drain.
 */
uint32_t aissd_proto_drain(aissd_proto_ctrl_t *c, uint32_t max_ops);

const aissd_proto_stats_t *aissd_proto_stats(const aissd_proto_ctrl_t *c);

#ifdef __cplusplus
}
#endif

#endif /* AISSD_PROTO_CTRL_H */
