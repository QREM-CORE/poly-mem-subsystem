# QREM Polynomial Memory Subsystem

## Overview

This repository implements the v0.75 Memory subsystem for the QREM ML-KEM hardware accelerator.

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

## Key Features

- 4-bank polynomial memory with CMI bit-pair-sum bank mapping
- deterministic 2-port internal scheduling
- strict client priority: `PAU > HSU > Transcoder`
- legal `read/read`, `write/write`, and `read/write` overlap when bank/address pairs are safe
- atomic combined read+write requests for PAU-style phases
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
5. Keep combined read+write requests atomic by assigning both internal ports to one client.

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
| `A` | `0..15` | 16 | Full A-matrix residency for up to `k=4` |
| `S` | `16..19` | 4 | Secret vector |
| `E` | `20..23` | 4 | Error vector / row-error scratch |
| `T` | `24..27` | 4 | Final `t_hat` outputs |
| `TEMP` | `28..31` | 4 | Scratch / working storage |

Semantic notes from `qrem_mem_map_pkg.sv`:

- `s[j]` and `e[i]` are intentionally in-place overwrite slots for `s_hat[j]` and `e_hat[i]`
- `t[i]` is the final placement for `t_hat[i]`
- `TEMP_0` is aliased as `POLY_ID_A_STREAM_SCRATCH` for streamed `A_hat` placement
- helper functions `poly_id_a(row,col)`, `poly_id_s(j)`, `poly_id_e(i)`, `poly_id_t(i)`, and `poly_id_temp(slot)` formalize controller-visible placement

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

## RTL Modules

| Module | Description |
|---|---|
| `rtl/poly_mem_subsystem.sv` | Top-level subsystem, internal 2-port scheduler, response routing, seed store integration, wipe FSM |
| `rtl/poly_mem_wrapper_4bank.sv` | 4-bank wrapper with two generic vector ports and hazard checking |
| `rtl/poly_ram_bank.sv` | Bank RAM primitive |
| `rtl/seed_ram.sv` | Dual-port protocol store RAM |
| `rtl/qrem_mem_map_pkg.sv` | Stable polynomial slot map plus semantic helpers/aliases |
| `rtl/qrem_seed_map_pkg.sv` | Stable protocol-store map plus semantic address helpers |
| `rtl/mem_arbiter.sv` | Legacy strict-priority helper retained in the repo; current top-level scheduling is in `poly_mem_subsystem.sv` |

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
- `tb/poly_mem_tb.sv`: package/helper smoke, protocol-store ID+beat mapping, wipe
- `tb/mem_frontend_top_tb.sv`: dual-read routing, dual-write, read/write overlap, combined atomicity, KeyGen placements, protocol-store concurrency, wipe

Expected output is `TB PASS`.

The shared `make` flow depends on the `build-tools` submodule being initialized in the local checkout. For direct local smoke checks, the updated benches compile and run with `iverilog` / `vvp`.

## Documentation

- `doc/V075_INTERFACE_REVIEW.md`
- `doc/docs.md`
- `doc/memory_subsystem.tex`
- `doc/memory_connections.tex`

## Follow-On Note

This phase intentionally does not modify PAU RTL. Memory now makes the intended v0.75 KeyGen placements expressible and testable, but PAU still needs a follow-on integration update for the richer source/destination contract implied by MAC-heavy row processing.
