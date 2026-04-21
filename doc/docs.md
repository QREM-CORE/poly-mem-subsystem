# QREM Polynomial Memory Subsystem - Detailed Notes

## 1. Scope

`poly_mem_subsystem.sv` is the authoritative top-level Memory module for the QREM v0.75 direction.

It owns:

- shared polynomial memory access for PAU, HSU, and Transcoder
- a lightweight address-based seed/protocol store
- wipe and fault/status sideband

This document summarizes the current implemented behavior after the Memory alignment pass.

## 2. External Contracts

### 2.1 Polynomial client contract

Every client keeps the same top-level interface:

- request qualifier: `*_req`
- read request: `*_rd_en`, `*_rd_poly_id`, `*_rd_idx`, `*_rd_lane_valid`
- write request: `*_wr_en`, `*_wr_poly_id`, `*_wr_idx`, `*_wr_data`
- read response: `*_rd_valid`, `*_rd_poly_id_o`, `*_rd_idx_o`, `*_rd_lane_valid_o`, `*_rd_data`
- flow control: `*_stall`

Meaning:

- one request may contain a read side, a write side, or both
- `rd_idx` / `wr_idx` are coefficient indices
- Memory performs bank and row mapping internally

### 2.2 Seed / protocol store contract

Physical Memory-side ports:

- HSU: `hsu_seed_req`, `hsu_seed_we`, `hsu_seed_addr`, `hsu_seed_wdata`, `hsu_seed_ready`, `hsu_seed_rvalid`, `hsu_seed_rdata`
- Transcoder: `tr_seed_req`, `tr_seed_we`, `tr_seed_addr`, `tr_seed_wdata`, `tr_seed_ready`, `tr_seed_rvalid`, `tr_seed_rdata`

Bridge-facing semantic contract above Memory:

- `seed_id`
- `seed_idx`

Address conversion:

`seed_addr = seed_base_addr(seed_id) + seed_idx`

## 3. Internal Scheduling Model

### 3.1 High-level rule

The subsystem now uses a deterministic 2-port scheduler instead of the older split read-plane / write-plane implementation.

Per cycle:

1. Select the highest-priority schedulable request.
2. Select a second request only if it is legal with the first.
3. Preserve combined read+write requests as atomic by assigning both internal ports to one client.

Priority stays:

- `PAU > HSU > Transcoder`

### 3.2 What can overlap

When legal, the implementation can admit:

- two reads
- two writes
- one read and one write

When a client presents read+write together:

- both internal ports belong to that client for the cycle
- lower-priority clients stall

### 3.3 Determinism

Client separation remains intentional:

- Memory does not collapse PAU / HSU / Transcoder semantics into one shared requester
- legality checks are internal implementation detail
- ownership remains explicit and priority-driven

## 4. Wrapper Behavior

`poly_mem_wrapper_4bank.sv` exposes two generic vector ports:

- Port 0 -> physical RAM Port A across all four banks
- Port 1 -> physical RAM Port B across all four banks

Each generic port may carry:

- one 4-lane read vector
- or one 4-lane write vector

The wrapper is responsible for:

- CMI bank mapping
- bank-local row mapping
- same-request lane conflict detection
- cross-port same-address hazard detection
- read metadata alignment and data reordering

## 5. Hazard Rules

### 5.1 Wrapper-level illegal cases

- same-request lane conflict -> fault code `3'b011`
- same-address read/write -> fault code `3'b001`
- same-address write/write -> fault code `3'b010`

### 5.2 Legal overlap examples

- read/read to safe bank/address pairs
- write/write to safe bank/address pairs
- read/write to safe bank/address pairs
- same-bank different-address overlap when the physical port use is well-defined

### 5.3 Top-level scheduling rule

At the top level, unsafe cross-client pairings are filtered before issue:

- the higher-priority admissible request proceeds
- the lower-priority unsafe request stalls

That means the top-level does not intentionally admit ambiguous pairs just to produce a wrapper fault later.

## 6. Timing

Polynomial memory timing:

- accepted read in cycle `n`
- read response in cycle `n+1`
- accepted write commits on the cycle `n` clock edge

Because the wrapper has two generic ports, up to two read responses may be routed back to clients in the same cycle.

Seed/protocol store timing:

- accepted read in cycle `n`
- read response in cycle `n+1`
- write commits on the acceptance edge

## 7. Polynomial Map

Stable numeric layout from `qrem_mem_map_pkg.sv`:

| Region | Base | Count |
|---|---:|---:|
| `A` | 0 | 16 |
| `S` | 16 | 4 |
| `E` | 20 | 4 |
| `T` | 24 | 4 |
| `TEMP` | 28 | 4 |

Helper functions:

- `poly_id_a(row, col)`
- `poly_id_s(j)`
- `poly_id_e(i)`
- `poly_id_t(i)`
- `poly_id_temp(slot)`

Semantic aliases:

- `POLY_ID_S_HAT_*` -> same numeric slots as `POLY_ID_S_*`
- `POLY_ID_E_HAT_*` -> same numeric slots as `POLY_ID_E_*`
- `POLY_ID_T_HAT_*` -> same numeric slots as `POLY_ID_T_*`
- `POLY_ID_A_STREAM_SCRATCH` -> `TEMP_0`

## 8. Seed / Protocol Map

Stable protocol-store bases from `qrem_seed_map_pkg.sv`:

| Object | Base |
|---|---:|
| `d` | 0 |
| `z` | 4 |
| `m` | 8 |
| `rho` | 12 |
| `sigma` | 16 |
| `H(ek)` | 20 |
| `ss` | 24 |
| `tmp` | 28 |

Helper functions:

- `seed_base_addr(seed_id)`
- `seed_word_addr(seed_id, beat)`

The store remains intentionally simple:

- Memory stores words
- the package defines bases
- bridges/controller logic provide semantic meaning

## 9. KeyGen-Oriented Placement Intent

The current map and interfaces support the intended controller flow without overfitting the subsystem to KeyGen only.

Examples:

- HSU writes `s[j]`, PAU later overwrites it in place as `s_hat[j]`
- HSU writes `e[i]`, PAU later overwrites it in place as `e_hat[i]`
- PAU writes final `t_hat[i]` into `t[i]`
- Transcoder reads `t[i]` and protocol-store objects for egress
- `rho`, `sigma`, `H(ek)`, `ss`, and temporary protocol values all fit the same protocol-store model

The A-matrix region stays fully resident-capable, while `POLY_ID_A_STREAM_SCRATCH` gives a clean streamed-scratch option.

## 10. RTL Summary

| File | Role |
|---|---|
| `rtl/poly_mem_subsystem.sv` | Top-level Memory subsystem |
| `rtl/poly_mem_wrapper_4bank.sv` | Two-port bank wrapper |
| `rtl/poly_ram_bank.sv` | Bank RAM primitive |
| `rtl/seed_ram.sv` | Dual-port protocol store RAM |
| `rtl/qrem_mem_map_pkg.sv` | Polynomial map package |
| `rtl/qrem_seed_map_pkg.sv` | Protocol-store map package |
| `rtl/mem_arbiter.sv` | Legacy helper retained in repo |

## 11. Test Coverage

| Testbench | Main checks |
|---|---|
| `tb/poly_mem_wrapper_4bank_tb.sv` | legal dual-read, dual-write, read/write overlap, same-address RW, same-address WW, same-request lane conflicts |
| `tb/poly_mem_tb.sv` | map helper correctness, protocol-store ID+beat mapping, wipe |
| `tb/mem_frontend_top_tb.sv` | dual-read routing, dual-write scheduling, read/write overlap, combined atomicity, KeyGen slot placements, protocol-store concurrency, wipe |

Expected output: `TB PASS`

## 12. Practical Notes

- The shared `make` flow depends on the `build-tools` submodule being initialized.
- The verified local smoke path in this checkout used `iverilog` and `vvp`.
- This pass intentionally does not modify PAU RTL.
- PAU still needs a follow-on update for the richer source/destination contract implied by row-wise MAC-heavy flows.
