# QREM Memory v0.75 Interface Review

Author: Quardin Lyttle

## Why this note exists

This repo has been moving from an older "single shared frontend" view of
memory toward the v0.75 architecture:

- true-dual-port polynomial banks
- split read/write memory-plane ownership
- dedicated HSU and Transcoder seed/protocol access
- PAU-owned CMI instead of a duplicate copy in Memory

This file captures the current interface status, what changed, and what still
needs follow-up.

## What is now true

### Polynomial memory

`poly_mem_subsystem.sv` now exposes a client contract with:

- one request qualifier: `*_req`
- read side:
  - `*_rd_en`
  - `*_rd_poly_id`
  - `*_rd_idx`
  - `*_rd_lane_valid`
- write side:
  - `*_wr_en`
  - `*_wr_poly_id`
  - `*_wr_idx`
  - `*_wr_data`
- read response:
  - `*_rd_valid`
  - `*_rd_poly_id_o`
  - `*_rd_idx_o`
  - `*_rd_lane_valid_o`
  - `*_rd_data`
- flow control:
  - `*_stall`

The subsystem arbitrates one **read owner** and one **write owner** per cycle.

Important rule:

- if a client presents a combined read+write request, it owns both planes for
  that cycle

That is the conservative behavior needed for PAU-style atomic memory phases.

### Seed / protocol store

The seed store is now independent from polynomial arbitration and has:

- one HSU-side port
- one Transcoder-side port

Signals:

- HSU:
  - `hsu_seed_req`, `hsu_seed_we`, `hsu_seed_addr`, `hsu_seed_wdata`
  - `hsu_seed_ready`, `hsu_seed_rvalid`, `hsu_seed_rdata`
- Transcoder:
  - `tr_seed_req`, `tr_seed_we`, `tr_seed_addr`, `tr_seed_wdata`
  - `tr_seed_ready`, `tr_seed_rvalid`, `tr_seed_rdata`

This matches the v0.75 direction much better than a single shared seed port.

### CMI ownership

`cmi.sv` should live with the PAU, not with Memory.

Reason:

- CMI is part of the PAU timing contract
- it aligns PAU writeback addresses to PAU datapath latency
- Memory should only expose the shared storage fabric and arbitration behavior

The duplicate Memory-owned copy was removed for that reason.

## Positive / Neutral / Negative

### Positive

- Memory now actively exploits dual-porting for **read+write overlap**
- HSU sampling writes can overlap with PAU read-heavy windows when the PAU is
  not presenting a combined request
- Seed/protocol access no longer needs to fight polynomial arbitration
- The interface is much closer to the v0.75 architecture snapshot

### Neutral

- The system is still conservative: only one owner per plane per cycle
- This is good enough for KeyGen bring-up and safer than over-aggressive
  overlap
- It is not yet the most throughput-optimized possible design

### Negative / Remaining gaps

- Two different clients still cannot both write polynomial memory in the same
  cycle
- PAU combined requests lock both planes, so HSU/Transcoder must still wait in
  those windows
- Detailed repo docs still trail the RTL in some places
- PAU still needs a cleaner top-level integration contract for the new Memory
  interface, especially around CWM drain/writeback and final result placement

## Redundant / Obsolete / Missing

### Redundant / obsolete

- Memory-owned `cmi.sv`
- Memory-side `tb/cmi_tb.sv`
- older descriptions that talk about a single shared seed port
- older descriptions that say the whole memory subsystem only accepts one
  client total per cycle

### Missing / follow-up

- A PAU integration update that fully uses separate read/write polynomial IDs
- A clearer PAU controller contract for:
  - source polynomial ID(s)
  - destination polynomial ID
  - drain/writeback target
- Top-level bridge modules for:
  - HSU poly stream writer
  - HSU seed reader
  - Transcoder seed reader/writer
- More Encaps / Decaps focused scheduling tests once those flows are wired

## Practical KeyGen impact

This memory design is a good fit for the conservative row-wise KeyGen FSM:

- PAU can read `s_hat` / `A_row_i`
- HSU can write the next row in cycles where PAU is read-only
- Seed values can be fetched/written without disturbing polynomial traffic

But:

- if PAU owns both planes for a combined request, HSU/Transcoder will still
  stall
- so the scheduler should still treat PAU-heavy windows as privileged

That is acceptable for a first correct v0.75 implementation.
