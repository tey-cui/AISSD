/*
 * SPDX-License-Identifier: Apache-2.0
 * Sim-first smoke: io_desc → FTL stub → NAND model write/readback.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ftl_hooks.h"
#include "io_desc.h"
#include "nand_model.h"
#include "qos_fdp.h"

#define PAGE_SIZE 4096
#define PAGE_COUNT 64

static int fail(const char *msg)
{
    fprintf(stderr, "FAIL: %s\n", msg);
    return 1;
}

int main(void)
{
    aissd_nand_timing_t timing = {.read_us = 10, .prog_us = 20, .erase_us = 30};
    aissd_nand_model_t *nand;
    aissd_ftl_t *ftl;
    aissd_qos_fdp_t qos;
    aissd_io_desc_t wr, rd;
    aissd_io_desc_t *done[2];
    uint8_t *wbuf;
    uint8_t *rbuf;
    uint32_t n;
    uint32_t cursor = 0;
    aissd_traffic_class_t tc;

    nand = aissd_nand_create(PAGE_COUNT, PAGE_SIZE, &timing);
    if (!nand) {
        return fail("nand create");
    }
    ftl = aissd_ftl_create(nand);
    if (!ftl) {
        aissd_nand_destroy(nand);
        return fail("ftl create");
    }

    aissd_qos_fdp_init_defaults(&qos);
    if (aissd_qos_fdp_apply_line(&qos, "wrr 0 16") != 0) {
        return fail("qos wrr");
    }
    if (aissd_qos_fdp_apply_line(&qos, "ruh 1 3") != 0) {
        return fail("qos ruh");
    }
    if (aissd_qos_fdp_region_for_ruh(&qos, 1) != 3) {
        return fail("ruh map");
    }
    tc = aissd_qos_fdp_wrr_pick(&qos, &cursor);
    if (tc != AISSD_TC_LAT_READ) {
        return fail("wrr pick");
    }

    wbuf = malloc(PAGE_SIZE);
    rbuf = malloc(PAGE_SIZE);
    if (!wbuf || !rbuf) {
        return fail("alloc");
    }
    memset(wbuf, 0xA5, PAGE_SIZE);
    memset(rbuf, 0, PAGE_SIZE);

    aissd_io_desc_init(&wr, AISSD_IO_WRITE, 7, 0, 1);
    wr.ruh = 1;
    wr.buf = wbuf;
    wr.buf_len = PAGE_SIZE;
    wr.host_tag = 0x1111;

    if (aissd_ftl_submit(ftl, &wr) != AISSD_OK) {
        return fail("write submit");
    }
    if (aissd_ftl_gc_may_run(ftl) != 1) {
        return fail("gc should still be allowed after BW_WRITE");
    }

    aissd_io_desc_init(&rd, AISSD_IO_READ, 7, 0, 1);
    rd.buf = rbuf;
    rd.buf_len = PAGE_SIZE;
    rd.host_tag = 0x2222;
    /* io_desc_init already sets LAT_READ for reads; suspend GC on submit. */

    if (aissd_ftl_submit(ftl, &rd) != AISSD_OK) {
        return fail("read submit");
    }
    if (aissd_ftl_gc_may_run(ftl) != 0) {
        return fail("gc should be suspended after LAT_READ");
    }

    n = aissd_ftl_poll_complete(ftl, done, 2);
    if (n != 2) {
        return fail("expected 2 completions");
    }
    if (memcmp(wbuf, rbuf, PAGE_SIZE) != 0) {
        return fail("readback mismatch");
    }
    if (aissd_nand_sim_time_us(nand) == 0) {
        return fail("sim time not advanced");
    }

    free(wbuf);
    free(rbuf);
    aissd_ftl_destroy(ftl);
    aissd_nand_destroy(nand);

    puts("smoke_io_desc: PASS");
    return 0;
}
