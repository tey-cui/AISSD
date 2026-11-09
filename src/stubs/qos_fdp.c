/*
 * SPDX-License-Identifier: Apache-2.0
 */
#include "qos_fdp.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void aissd_qos_fdp_init_defaults(aissd_qos_fdp_t *q)
{
    if (!q) {
        return;
    }
    memset(q, 0, sizeof(*q));
    q->wrr.weight[AISSD_TC_LAT_READ] = 8;
    q->wrr.weight[AISSD_TC_BW_READ] = 4;
    q->wrr.weight[AISSD_TC_BW_WRITE] = 4;
    q->wrr.weight[AISSD_TC_META] = 2;
    q->wrr.weight[AISSD_TC_BG] = 1;
}

int aissd_qos_fdp_apply_line(aissd_qos_fdp_t *q, const char *line)
{
    unsigned tc, weight, ruh, region;
    uint32_t i;

    if (!q || !line) {
        return -1;
    }
    while (*line == ' ' || *line == '\t') {
        line++;
    }
    if (*line == '#' || *line == '\0' || *line == '\n') {
        return 0;
    }

    if (sscanf(line, "wrr %u %u", &tc, &weight) == 2) {
        if (tc >= AISSD_TC_COUNT) {
            return -1;
        }
        q->wrr.weight[tc] = (uint16_t)weight;
        return 0;
    }
    if (sscanf(line, "ruh %u %u", &ruh, &region) == 2) {
        if (region >= AISSD_FDP_MAX_REGIONS) {
            return -1;
        }
        for (i = 0; i < q->ruh_count; i++) {
            if (q->ruh_table[i].ruh == (uint16_t)ruh) {
                q->ruh_table[i].region_id = (uint16_t)region;
                q->ruh_table[i].valid = 1;
                return 0;
            }
        }
        if (q->ruh_count >= AISSD_FDP_MAX_RUH) {
            return -1;
        }
        q->ruh_table[q->ruh_count].ruh = (uint16_t)ruh;
        q->ruh_table[q->ruh_count].region_id = (uint16_t)region;
        q->ruh_table[q->ruh_count].valid = 1;
        q->ruh_count++;
        return 0;
    }
    return -1;
}

uint16_t aissd_qos_fdp_region_for_ruh(const aissd_qos_fdp_t *q, uint16_t ruh)
{
    uint32_t i;

    if (!q || ruh == 0) {
        return 0;
    }
    for (i = 0; i < q->ruh_count; i++) {
        if (q->ruh_table[i].valid && q->ruh_table[i].ruh == ruh) {
            return q->ruh_table[i].region_id;
        }
    }
    return 0;
}

aissd_traffic_class_t aissd_qos_fdp_wrr_pick(aissd_qos_fdp_t *q, uint32_t *cursor)
{
    uint32_t start;
    uint32_t i;
    uint32_t idx;

    if (!q || !cursor) {
        return AISSD_TC_LAT_READ;
    }
    start = *cursor % AISSD_TC_COUNT;
    for (i = 0; i < AISSD_TC_COUNT; i++) {
        idx = (start + i) % AISSD_TC_COUNT;
        if (q->wrr.weight[idx] > 0) {
            *cursor = idx + 1;
            return (aissd_traffic_class_t)idx;
        }
    }
    *cursor = start + 1;
    return AISSD_TC_LAT_READ;
}
