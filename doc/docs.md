# QREM Polynomial Memory Subsystem - Detailed Notes

## 1. Scope

`poly_mem_subsystem.sv` is the authoritative top-level Memory module for the QREM v0.9 direction.

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
- HSU polynomial traffic is write-oriented during sampling/matrix-fill, with
  one constrained read exception: during `KG_HSU_HASH_EK`, controller/Gearbox
  glue may assert `hsu_hash_ek_read_en` and read only `T0..T3` through the HSU
  response channel. Mixed HSU read/write requests and non-T-slot reads still
  stall cleanly.
- PAU has an additional auxiliary descriptor channel. When PAU primary and
  auxiliary descriptors are both valid and pair-legal, PAU owns both internal
  memory ports for that cycle. This is Memory-side scheduling support only;
  PAU-side CMI remains in PAU.

### 2.2 Seed / protocol store contract

Physical Memory-side ports:

- HSU: `hsu_seed_req`, `hsu_seed_we`, `hsu_seed_addr`, `hsu_seed_wdata`, `hsu_seed_ready`, `hsu_seed_rvalid`, `hsu_seed_rdata`
- Transcoder: `tr_seed_req`, `tr_seed_we`, `tr_seed_addr`, `tr_seed_wdata`, `tr_seed_ready`, `tr_seed_rvalid`, `tr_seed_rdata`

Bridge-facing semantic contract above Memory:

- `seed_id`
- `seed_idx`

Address conversion:

`seed_addr = seed_base_addr(seed_id) + seed_idx`

Boundary behavior:

- `*_seed_ready` is low during reset or wipe.
- `*_seed_rvalid` asserts one cycle after an accepted read.
- `*_seed_rdata` is driven to zero whenever `*_seed_rvalid` is low.
- The raw seed RAM does not reset contents or read-data registers; the wipe FSM is the zeroization mechanism.

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

When PAU presents primary and auxiliary descriptors together:

- both internal ports belong to PAU if the pair is legal
- the pair may be read/read, read/write, or write/write
- lower-priority clients stall behind the PAU-owned pair

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

- memory-side bit-pair-sum bank mapping
- bank-local row mapping
- same-request lane conflict detection
- cross-port same-address hazard detection
- read metadata alignment and data reordering

This bank mapping is Memory-side decode only. PAU-side CMI remains owned by PAU.

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
- reset/wipe deasserts `*_seed_ready`; idle read data is zeroed at the subsystem boundary

## 7. Polynomial Map

Stable numeric layout from `qrem_mem_map_pkg.sv`:

| Region | Base | Count |
|---|---:|---:|
| `S0..S3` | 0 | 4 |
| `EI` | 4 | 1 |
| `A0..A3` | 5 | 4 |
| `T0..T3` | 9 | 4 |
| `WORK0..WORK18` | 13 | 19 |

The package intentionally defines only fixed constants. Memory does not take
`k` as an input and does not compute runtime placement. The controller chooses
which subset of `S0..S3`, `A0..A3`, and `T0..T3` is active for `k=2..4`.

Rewrite semantics:

- `s_j` is overwritten in the same `S*` slot as `s_hat_j`
- `e_i` is overwritten in `POLY_ID_EI` as `e_hat_i`
- `A*` row-buffer slots may hold `A_hat[i][j]`
- `T*` slots hold final `t_hat_i`

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

- HSU writes `s_j` into `POLY_ID_S0..POLY_ID_S3`; PAU later overwrites the same slot as `s_hat_j`
- HSU writes the active row error into `POLY_ID_EI`; PAU later overwrites it as `e_hat_i`
- HSU fills the active A row buffer in `POLY_ID_A0..POLY_ID_A3`
- PAU writes final `t_hat_i` into `POLY_ID_T0..POLY_ID_T3`
- During `KG_HSU_HASH_EK`, a Gearbox/read bridge may use the constrained HSU
  T-slot read path to pack `t_hat` coefficients for the HSU hash input
- Transcoder reads `t[i]` and protocol-store objects for egress
- `rho`, `sigma`, `H(ek)`, `ss`, and temporary protocol values all fit the same protocol-store model

## 10. RTL Summary

| File | Role |
|---|---|
| `rtl/poly_mem_subsystem.sv` | Top-level Memory subsystem |
| `rtl/poly_mem_wrapper_4bank.sv` | Two-port bank wrapper |
| `rtl/poly_ram_bank.sv` | Bank RAM primitive |
| `rtl/seed_ram.sv` | Dual-port protocol store RAM |
| `rtl/qrem_mem_map_pkg.sv` | Polynomial map package |
| `rtl/qrem_seed_map_pkg.sv` | Protocol-store map package |

## 11. Test Coverage

| Testbench | Main checks |
|---|---|
| `tb/poly_mem_wrapper_4bank_tb.sv` | legal dual-read, dual-write, read/write overlap, same-address RW, same-address WW, same-request lane conflicts |
| `tb/poly_mem_tb.sv` | fixed map constants, protocol-store ID+beat mapping, wipe |
| `tb/mem_frontend_top_tb.sv` | PAU-owned dual-port phases, dual-read routing, dual-write scheduling, read/write overlap, combined atomicity, constrained HSU hash-ek T-slot reads, KeyGen slot placements, protocol-store concurrency, wipe |

Expected output: `TB PASS`

## 12. Practical Notes

- The shared `make` flow depends on the `build-tools` submodule being initialized.
- The verified local smoke path in this checkout used `iverilog` and `vvp`.
- This pass intentionally does not modify PAU RTL.
- PAU still needs a follow-on update for the richer source/destination contract implied by row-wise MAC-heavy flows.
- Gearbox/controller glue still needs to drive the `KG_HSU_HASH_EK` T-slot
  read sequence, ByteEncode12 packing, and HSU hash input stream outside Memory.
