/*
 * SPDX-License-Identifier: Apache-2.0
 */
#include "io_desc.h"

#include <string.h>

void aissd_io_desc_init(aissd_io_desc_t *d, aissd_io_op_t op, uint64_t lba,
                        uint32_t nlb, uint32_t nsid)
{
    if (!d) {
        return;
    }
    memset(d, 0, sizeof(*d));
    d->op = (uint8_t)op;
    d->lba = lba;
    d->nlb = nlb;
    d->nsid = nsid;
    d->traffic_class =
        (op == AISSD_IO_READ) ? (uint8_t)AISSD_TC_LAT_READ : (uint8_t)AISSD_TC_BW_WRITE;
}
