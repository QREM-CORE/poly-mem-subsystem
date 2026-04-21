# QREM Polynomial Memory Subsystem

## Overview

This repository implements the v0.9 Memory subsystem for the QREM ML-KEM hardware accelerator.

The subsystem owns:

- polynomial memory for PAU, HSU, and Transcoder
- a small dual-port seed/protocol store for HSU and Transcoder sideband protocol objects
- wipe and fault/status sideband logic

The external polynomial-memory client contract remains stable:

- `*_req`
- `*_rd_en`, `*_rd_poly_id`, `*_rd_idx`, `*_rd_lane_valid`
- `*_wr_en`, `*_wr_poly_id`, `*_wr_idx`, `*_wr_data`
- `*_rd_valid`, `*_rd_poly_id_o`, `*_rd_idx_o`, `*_rd_lane_valid_o`, `*_rd_data`
- `*_stall`

PAU also exposes a primary-plus-auxiliary polynomial descriptor so PAU can
own both internal memory ports in one cycle when the requested pair is legal.
This supports PAU-owned read/read, read/write, and write/write phases without
moving PAU-side CMI behavior into Memory.

HSU polynomial traffic remains write-oriented during sampling and matrix-fill.
The only HSU polynomial-read exception is the constrained
`KG_HSU_HASH_EK` path: controller/Gearbox glue asserts
`hsu_hash_ek_read_en`, and Memory permits HSU reads only from `T0..T3`
with no same-request write. The Gearbox/read bridge owns T-slot sequencing,
ByteEncode12 packing, and feeding the HSU hash input. HSU reads protocol
objects through the seed/protocol store.

## Key Features

- 4-bank polynomial memory with memory-side bit-pair-sum bank mapping
- deterministic 2-port internal scheduling
- strict client priority: `PAU > HSU > Transcoder`
- legal `read/read`, `write/write`, and `read/write` overlap when bank/address pairs are safe
- atomic combined read+write requests and PAU primary+auxiliary dual-port phases
- 32 polynomial slots with stable numeric IDs
- dual-port 32 x 64-bit seed/protocol store
- 1-cycle polynomial-read latency
- wipe FSM for both polynomial memory and protocol store

## Architecture

Internally, `poly_mem_subsystem.sv` works like this:

1. Choose the highest-priority schedulable request.
2. Choose a second request only if it is pair-legal with the first.
3. Route the admitted requests into `poly_mem_wrapper_4bank.sv`.
4. Route up to two read responses back to the originating clients one cycle later.
5. Keep PAU primary+auxiliary and combined read+write phases deterministic by assigning both internal ports to one owner when required.

`poly_mem_wrapper_4bank.sv` exposes two symmetric generic vector ports:

- Port 0 binds to physical RAM Port A across all 4 banks
- Port 1 binds to physical RAM Port B across all 4 banks
- either port may be a read vector or a write vector in a cycle

That lets the implementation admit:

- 2 reads in a cycle when legal
- 2 writes in a cycle when legal
- 1 read + 1 write in a cycle when legal

## Polynomial Map

The numeric polynomial slot assignments stay stable:

| Region | poly_id range | Count | Purpose |
|---|---:|---:|---|
| `S` | `0..3` | 4 | `s0..s3`, overwritten in place as `s_hat` |
| `EI` | `4` | 1 | Active row-error scratch, overwritten in place as `e_hat_i` |
| `A` | `5..8` | 4 | Active A row buffer `A0..A3`, may hold `A_hat[i][j]` |
| `T` | `9..12` | 4 | Final `t0..t3`, holding `t_hat_i` |
| `WORK` | `13..31` | 19 | Generic controller-visible work/scratch |

Semantic notes from `qrem_mem_map_pkg.sv`:

- Memory does not take `k` as an input and does not compute placement.
- The controller chooses the active subset for `k=2`, `k=3`, or `k=4`.
- Hats are rewrite semantics only: no separate `*_HAT_*` slot region exists.
- The package intentionally provides straightforward constants only, not runtime map helper functions.

## Seed / Protocol Store

The protocol store remains internally address-based, but bridge-facing logic above Memory should use:

- `seed_id`
- `seed_idx`

`qrem_seed_map_pkg.sv` keeps the stable object bases for:

- `d`
- `z`
- `m`
- `rho`
- `sigma`
- `H(ek)`
- `ss`
- `tmp`

Helper functions:

- `seed_base_addr(seed_id)`
- `seed_word_addr(seed_id, beat)`

The intended contract above Memory is:

`seed_addr = seed_base_addr(seed_id) + seed_idx`

At the Memory boundary, both seed/protocol ports report not-ready during reset
or wipe. Read data is valid-qualified: `*_seed_rvalid` asserts one cycle after
an accepted read, and `*_seed_rdata` is driven to zero whenever `*_seed_rvalid`
is low. The raw RAM primitive does not reset its read-data registers so FPGA
BRAM inference remains clean; storage zeroization is handled by the wipe FSM.

## RTL Modules

| Module | Description |
|---|---|
| `rtl/poly_mem_subsystem.sv` | Top-level subsystem, internal 2-port scheduler, response routing, seed store integration, wipe FSM |
| `rtl/poly_mem_wrapper_4bank.sv` | 4-bank wrapper with two generic vector ports and hazard checking |
| `rtl/poly_ram_bank.sv` | Bank RAM primitive |
| `rtl/seed_ram.sv` | Dual-port protocol store RAM |
| `rtl/qrem_mem_map_pkg.sv` | Stable fixed polynomial slot constants |
| `rtl/qrem_seed_map_pkg.sv` | Stable protocol-store map plus semantic address helpers |

## Hazard Rules

Wrapper-level rules:

- same-request lane conflicts are illegal
- same-address read/write is illegal
- same-address write/write is illegal
- same-bank different-address overlap is legal when each physical port usage is well-defined

Top-level rule:

- illegal cross-client pairings are filtered by the scheduler before issue, so the lower-priority request stalls instead of creating ambiguous memory behavior

## Testing

The repo includes:

- `tb/poly_mem_wrapper_4bank_tb.sv`: legal `RR/WW/RW` issue and wrapper hazard checks
- `tb/poly_mem_tb.sv`: fixed map smoke, protocol-store ID+beat mapping, wipe
- `tb/mem_frontend_top_tb.sv`: PAU-owned dual-port phases, dual-read routing, dual-write, read/write overlap, combined atomicity, constrained HSU hash-ek T-slot reads, KeyGen placements, protocol-store concurrency, wipe

Expected output is `TB PASS`.

The shared `make` flow depends on the `build-tools` submodule being initialized in the local checkout. For direct local smoke checks, the updated benches compile and run with `iverilog` / `vvp`.

## Documentation

- `doc/V075_INTERFACE_REVIEW.md`
- `doc/docs.md`
- `doc/memory_subsystem.tex`
- `doc/memory_connections.tex`

## Follow-On Note

This phase intentionally does not modify PAU RTL or implement the Gearbox
bridge. Memory now makes the intended v0.9 KeyGen placements and constrained
HSU hash-ek T-slot readout expressible and testable. PAU still needs a
follow-on integration update for the richer source/destination contract
implied by MAC-heavy row processing, and controller/Gearbox glue must drive
`hsu_hash_ek_read_en` plus the HSU read sequence during `KG_HSU_HASH_EK`.

PAU-side CMI ownership remains in PAU. Memory only performs the memory-side
bank/row decode needed to access its RAM banks safely.
