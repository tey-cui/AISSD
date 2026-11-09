/*
 * SPDX-License-Identifier: Apache-2.0
 * Prototype demo: multi-NS / multi-queue AI traffic → FDP → FTL → nand_model.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ftl_hooks.h"
#include "host_traffic.h"
#include "io_desc.h"
#include "nand_model.h"
#include "proto_ctrl.h"
#include "qos_fdp.h"

#define PAGE_SIZE 4096
#define PAGE_COUNT 2048
#define NUM_QUEUES 3
#define MAX_DESCS 512

static int fail(const char *msg)
{
    fprintf(stderr, "proto_demo FAIL: %s\n", msg);
    return 1;
}

static void print_report(aissd_nand_model_t *nand, aissd_ftl_t *ftl,
                         aissd_proto_ctrl_t *ctrl)
{
    const aissd_nand_stats_t *ns = aissd_nand_stats(nand);
    const aissd_ftl_stats_t *fs = aissd_ftl_stats(ftl);
    const aissd_proto_stats_t *ps = aissd_proto_stats(ctrl);
    uint64_t sim_us = aissd_nand_sim_time_us(nand);
    double sim_s = sim_us / 1e6;
    double iops = 0.0;
    uint32_t p99;
    uint64_t ios;

    ios = ns ? (ns->reads + ns->writes) : 0;
    if (sim_s > 0.0) {
        iops = (double)ios / sim_s;
    }
    p99 = aissd_nand_p99_latency_us(nand);

    puts("========== AISSD prototype demo report ==========");
    printf("sim_time_us      : %llu\n", (unsigned long long)sim_us);
    printf("nand reads/writes: %llu / %llu\n",
           (unsigned long long)(ns ? ns->reads : 0),
           (unsigned long long)(ns ? ns->writes : 0));
    printf("bytes R/W        : %llu / %llu\n",
           (unsigned long long)(ns ? ns->bytes_read : 0),
           (unsigned long long)(ns ? ns->bytes_written : 0));
    printf("IOPS (sim)       : %.1f\n", iops);
    printf("p99 latency_us   : %u\n", p99);
    printf("read_max_us      : %u\n", ns ? ns->read_lat_max_us : 0);
    printf("write_max_us     : %u\n", ns ? ns->write_lat_max_us : 0);
    printf("ftl submits      : %llu\n",
           (unsigned long long)(fs ? fs->submits : 0));
    printf("ftl placement    : %llu\n",
           (unsigned long long)(fs ? fs->placement_resolves : 0));
    printf("gc_suspends      : %llu\n",
           (unsigned long long)(fs ? fs->gc_suspends : 0));
    printf("gc_blocked_ticks : %llu\n",
           (unsigned long long)(fs ? fs->gc_blocked_ticks : 0));
    printf("gc_runs          : %llu\n",
           (unsigned long long)(fs ? fs->gc_runs : 0));
    printf("proto enq/sub/cmp: %llu / %llu / %llu\n",
           (unsigned long long)(ps ? ps->enqueued : 0),
           (unsigned long long)(ps ? ps->submitted : 0),
           (unsigned long long)(ps ? ps->completed : 0));
    printf("per-NS ios       : ns1=%llu ns2=%llu\n",
           (unsigned long long)(ps ? ps->per_ns_ios[1] : 0),
           (unsigned long long)(ps ? ps->per_ns_ios[2] : 0));
    printf("per-Q ios        : q0=%llu q1=%llu q2=%llu\n",
           (unsigned long long)(ps ? ps->per_q_ios[0] : 0),
           (unsigned long long)(ps ? ps->per_q_ios[1] : 0),
           (unsigned long long)(ps ? ps->per_q_ios[2] : 0));
    printf("TC LAT_READ/BW_W : %llu / %llu\n",
           (unsigned long long)(ps ? ps->per_tc_ios[AISSD_TC_LAT_READ] : 0),
           (unsigned long long)(ps ? ps->per_tc_ios[AISSD_TC_BW_WRITE] : 0));
    puts("=================================================");
}

int main(void)
{
    aissd_nand_timing_t timing = {
        .read_us = 40,
        .prog_us = 200,
        .erase_us = 1500,
        .read_us_per_kib = 2,
        .write_us_per_kib = 5,
    };
    aissd_nand_model_t *nand = NULL;
    aissd_ftl_t *ftl = NULL;
    aissd_qos_fdp_t qos;
    aissd_proto_ctrl_t *ctrl = NULL;
    aissd_traffic_gen_t *gens[3] = {NULL, NULL, NULL};
    aissd_io_desc_t *descs = NULL;
    uint32_t desc_count = 0;
    aissd_traffic_cfg_t cfgs[3];
    uint32_t i;
    uint32_t drained;
    uint8_t *seed_buf = NULL;
    int rc = 1;

    nand = aissd_nand_create(PAGE_COUNT, PAGE_SIZE, &timing);
    if (!nand) {
        return fail("nand create");
    }
    ftl = aissd_ftl_create(nand);
    if (!ftl) {
        fail("ftl create");
        goto out;
    }

    aissd_qos_fdp_init_defaults(&qos);
    /* RUH 1 → hot KV region 1; RUH 2 → checkpoint region 2. */
    if (aissd_qos_fdp_apply_line(&qos, "ruh 1 1") != 0 ||
        aissd_qos_fdp_apply_line(&qos, "ruh 2 2") != 0 ||
        aissd_qos_fdp_apply_line(&qos, "region 1 64 512") != 0 ||
        aissd_qos_fdp_apply_line(&qos, "region 2 600 800") != 0 ||
        aissd_qos_fdp_apply_line(&qos, "wrr 0 16") != 0) {
        fail("qos config");
        goto out;
    }
    if (aissd_qos_fdp_region_for_ruh(&qos, 1) != 1 ||
        aissd_qos_fdp_region_for_ruh(&qos, 2) != 2) {
        fail("ruh resolve");
        goto out;
    }

    ctrl = aissd_proto_create(ftl, &qos, NUM_QUEUES);
    if (!ctrl) {
        fail("proto create");
        goto out;
    }

    /* Seed pages so KV / embedding reads have data (identity L2P initially). */
    seed_buf = malloc(PAGE_SIZE);
    if (!seed_buf) {
        fail("seed alloc");
        goto out;
    }
    memset(seed_buf, 0x5A, PAGE_SIZE);
    for (i = 0; i < 256; i++) {
        if (aissd_nand_write_page(nand, i, seed_buf, PAGE_SIZE) != 0) {
            fail("seed write");
            goto out;
        }
        if (aissd_ftl_l2p_update(ftl, i, i) != AISSD_OK) {
            fail("seed l2p");
            goto out;
        }
    }
    aissd_nand_stats_reset(nand);

    /* Q0 NS1: KV overflow reads (RUH 1). */
    cfgs[0] = (aissd_traffic_cfg_t){.pattern = AISSD_PAT_KV_OVERFLOW,
                                    .nsid = 1,
                                    .ruh = 1,
                                    .queue_id = 0,
                                    .lba_base = 0,
                                    .count = 48,
                                    .page_size = PAGE_SIZE,
                                    .seed = 1};
    /* Q1 NS1: embedding random reads. */
    cfgs[1] = (aissd_traffic_cfg_t){.pattern = AISSD_PAT_EMBED_RAND,
                                    .nsid = 1,
                                    .ruh = 1,
                                    .queue_id = 1,
                                    .lba_base = 32,
                                    .count = 64,
                                    .page_size = PAGE_SIZE,
                                    .seed = 42};
    /* Q2 NS2: checkpoint sequential writes (RUH 2 → region 2). */
    cfgs[2] = (aissd_traffic_cfg_t){.pattern = AISSD_PAT_CKPT_SEQ,
                                    .nsid = 2,
                                    .ruh = 2,
                                    .queue_id = 2,
                                    .lba_base = 400,
                                    .count = 80,
                                    .page_size = PAGE_SIZE,
                                    .seed = 7};

    descs = calloc(MAX_DESCS, sizeof(*descs));
    if (!descs) {
        fail("desc alloc");
        goto out;
    }

    for (i = 0; i < 3; i++) {
        gens[i] = aissd_traffic_create(&cfgs[i]);
        if (!gens[i]) {
            fail("traffic create");
            goto out;
        }
        while (aissd_traffic_remaining(gens[i]) > 0) {
            if (desc_count >= MAX_DESCS) {
                fail("desc overflow");
                goto out;
            }
            if (!aissd_traffic_next(gens[i], &descs[desc_count])) {
                break;
            }
            if (aissd_proto_enqueue(ctrl, cfgs[i].queue_id, &descs[desc_count]) !=
                AISSD_OK) {
                fail("enqueue");
                goto out;
            }
            desc_count++;
        }
    }

    drained = 0;
    while (drained < desc_count) {
        uint32_t n = aissd_proto_drain(ctrl, 16);
        if (n == 0) {
            break;
        }
        drained += n;
    }

    /* After latency reads drain, allow a few GC ticks. */
    aissd_ftl_gc_resume(ftl);
    for (i = 0; i < 4; i++) {
        (void)aissd_ftl_gc_tick(ftl);
    }

    if (aissd_proto_stats(ctrl)->submitted == 0) {
        fail("no submits");
        goto out;
    }
    if (aissd_ftl_stats(ftl)->placement_resolves == 0) {
        fail("no FDP placement");
        goto out;
    }
    if (aissd_ftl_stats(ftl)->gc_suspends == 0) {
        fail("expected GC suspend on LAT_READ");
        goto out;
    }
    if (aissd_nand_p99_latency_us(nand) == 0) {
        fail("expected p99 samples");
        goto out;
    }

    /* Verify one checkpoint write landed in region 2 PBA range via L2P. */
    {
        uint64_t pba = aissd_ftl_l2p_lookup(ftl, 400);
        if (pba < 600 || pba >= 1400) {
            fail("checkpoint not placed in FDP region 2");
            goto out;
        }
    }

    print_report(nand, ftl, ctrl);
    puts("proto_demo: PASS");
    rc = 0;

out:
    for (i = 0; i < 3; i++) {
        aissd_traffic_destroy(gens[i]);
    }
    free(descs);
    free(seed_buf);
    aissd_proto_destroy(ctrl);
    aissd_ftl_destroy(ftl);
    aissd_nand_destroy(nand);
    return rc;
}
