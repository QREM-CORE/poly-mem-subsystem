# QREM Memory v0.75 Interface Review

Author: Quardin Lyttle

## Purpose

This note captures the current Memory-repo contract after the v0.75 alignment pass. It focuses on what is stable, what changed internally, and how the current subsystem maps to the intended KeyGen / Encaps / Decaps direction.

## What Stays Stable

### Polynomial client interface

Each polynomial-memory client still uses:

- `*_req`
- `*_rd_en`, `*_rd_poly_id`, `*_rd_idx`, `*_rd_lane_valid`
- `*_wr_en`, `*_wr_poly_id`, `*_wr_idx`, `*_wr_data`
- `*_rd_valid`, `*_rd_poly_id_o`, `*_rd_idx_o`, `*_rd_lane_valid_o`, `*_rd_data`
- `*_stall`

Clarifications:

- `rd_idx` / `wr_idx` are coefficient indices, not bank IDs
- bank mapping and row mapping stay inside Memory
- the client sees one stable external contract even though the internals now schedule two generic ports

### Seed / protocol store interface

The physical Memory-side seed/protocol ports remain:

- HSU side:
  - `hsu_seed_req`, `hsu_seed_we`, `hsu_seed_addr`, `hsu_seed_wdata`
  - `hsu_seed_ready`, `hsu_seed_rvalid`, `hsu_seed_rdata`
- Transcoder side:
  - `tr_seed_req`, `tr_seed_we`, `tr_seed_addr`, `tr_seed_wdata`
  - `tr_seed_ready`, `tr_seed_rvalid`, `tr_seed_rdata`

Above Memory, bridges should use semantic:

- `seed_id`
- `seed_idx`

with:

`seed_addr = seed_base_addr(seed_id) + seed_idx`

## What Changed Internally

### Scheduler

The old split read-plane / write-plane model is gone internally.

The subsystem now uses a deterministic 2-port scheduler:

1. Admit the highest-priority schedulable request.
2. Admit a second request only if it is legal with the first after bank/address analysis.
3. Keep client ownership explicit and deterministic.

Priority remains:

- `PAU > HSU > Transcoder`

### Combined requests

If a client presents read and write together in one cycle:

- that request is atomic
- both internal ports belong to that client for the cycle
- lower-priority clients stall

This preserves the PAU-friendly atomic phase behavior needed by current control flow.

### Wrapper model

`poly_mem_wrapper_4bank.sv` now presents:

- generic Port 0 bound to physical RAM Port A
- generic Port 1 bound to physical RAM Port B

Either generic port may be:

- one 4-lane read vector
- one 4-lane write vector

That means the wrapper can legally support:

- 2 reads in a cycle
- 2 writes in a cycle
- 1 read + 1 write in a cycle

when the actual bank/address usage is safe.

## Hazard Rules

### Wrapper-level hazards

These are explicit faults if admitted to the wrapper:

- same-address read/write: `3'b001`
- same-address write/write: `3'b010`
- same-request lane conflict: `3'b011`

Important point:

- legality is decided from final bank/address usage, not just from `poly_id`

### Top-level scheduling behavior

At the top level, illegal cross-client pairings are filtered before issue:

- the higher-priority admissible request may proceed
- the lower-priority unsafe request stalls
- the scheduler does not deliberately issue an unsafe pair just to fault it later

That keeps ownership deterministic and avoids undefined same-cycle outcomes.

## Map Semantics

### Polynomial map

Numeric slot assignments remain stable:

- `A`: `0..15`
- `S`: `16..19`
- `E`: `20..23`
- `T`: `24..27`
- `TEMP`: `28..31`

New helpers/aliases formalize controller intent:

- `poly_id_a(row,col)`
- `poly_id_s(j)`
- `poly_id_e(i)`
- `poly_id_t(i)`
- `poly_id_temp(slot)`

KeyGen-oriented semantic aliases:

- `s[j]` is also `s_hat[j]` after PAU overwrite
- `e[i]` is also `e_hat[i]` after PAU overwrite
- `t[i]` is the final `t_hat[i]`
- `TEMP_0` is the streamed `A_hat` scratch alias

### Seed / protocol map

The store is intentionally broader than "seed RAM". It covers protocol objects used across KeyGen, Encaps, and Decaps:

- `d`
- `z`
- `m`
- `rho`
- `sigma`
- `H(ek)`
- `ss`
- `tmp`

The package keeps stable base addresses and adds:

- `seed_base_addr(seed_id)`
- `seed_word_addr(seed_id, beat)`

## KeyGen Fit

The current map and interfaces cleanly support the intended controller flow:

- HSU writes `s[j]`, PAU later overwrites the same slot with `s_hat[j]`
- HSU writes `e[i]`, PAU later overwrites the same slot with `e_hat[i]`
- PAU commits final `t_hat[i]` into `t[i]`
- Transcoder reads `t[i]` and protocol-store objects such as `rho`
- HSU can store `H(ek)` in the protocol store without disturbing polynomial traffic

The map also stays general enough for later Encaps / Decaps use because it does not collapse the A-matrix region into a KeyGen-only scratch scheme.

## Still Outside Memory Scope

This pass intentionally does not edit PAU RTL.

Practical implication:

- Memory now supports the intended placements and legal overlap behavior
- PAU still needs a follow-on integration update for the richer source/destination contract implied by MAC accumulation and row-final commit behavior

## Summary

The v0.75 Memory contract is now:

- stable externally
- smarter internally
- explicit about semantic placement
- still deterministic about ownership
- conservative about ambiguous hazards

That is the right balance for current KeyGen work while keeping the subsystem usable for future Encaps / Decaps flows.
