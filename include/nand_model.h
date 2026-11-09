/*
 * SPDX-License-Identifier: Apache-2.0
 * Fixed-latency NAND simulation model (no FPGA / no Cosmos+ NFC).
 */
#ifndef AISSD_NAND_MODEL_H
#define AISSD_NAND_MODEL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct aissd_nand_timing {
    uint32_t read_us;
    uint32_t prog_us;
    uint32_t erase_us;
} aissd_nand_timing_t;

typedef struct aissd_nand_model aissd_nand_model_t;

aissd_nand_model_t *aissd_nand_create(uint64_t page_count, uint32_t page_size,
                                      const aissd_nand_timing_t *timing);
void aissd_nand_destroy(aissd_nand_model_t *n);

uint32_t aissd_nand_page_size(const aissd_nand_model_t *n);
uint64_t aissd_nand_page_count(const aissd_nand_model_t *n);
uint64_t aissd_nand_sim_time_us(const aissd_nand_model_t *n);

/* Page R/W; erase marks page erased (subsequent read returns zeros). */
int aissd_nand_read_page(aissd_nand_model_t *n, uint64_t pba, void *dst,
                         size_t len);
int aissd_nand_write_page(aissd_nand_model_t *n, uint64_t pba, const void *src,
                          size_t len);
int aissd_nand_erase_page(aissd_nand_model_t *n, uint64_t pba);

/* Simple bad-block bitmap (set / test). */
int aissd_nand_mark_bad(aissd_nand_model_t *n, uint64_t pba);
int aissd_nand_is_bad(const aissd_nand_model_t *n, uint64_t pba);

#ifdef __cplusplus
}
#endif

#endif /* AISSD_NAND_MODEL_H */
