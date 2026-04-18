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

### Stable external polynomial-memory interface

The external client-facing polynomial-memory interface should stay stable even if
the internal wrapper gets smarter later. Each client currently sees:

| Group | Signals | Meaning |
|---|---|---|
| Request qualifier | `*_req` | Client has an active polynomial-memory transaction this cycle |
| Read request | `*_rd_en`, `*_rd_poly_id`, `*_rd_idx`, `*_rd_lane_valid` | Up to 4 coefficient reads from one logical polynomial |
| Write request | `*_wr_en`, `*_wr_poly_id`, `*_wr_idx`, `*_wr_data` | Up to 4 coefficient writes into one logical polynomial |
| Read response | `*_rd_valid`, `*_rd_poly_id_o`, `*_rd_idx_o`, `*_rd_lane_valid_o`, `*_rd_data` | Tagged readback returned to the winning client only |
| Flow control | `*_stall` | Client must hold the current request stable until stall deasserts |

Important clarifications for the team:

- `rd_idx` / `wr_idx` are **4 coefficient indices**, not 4 bank IDs.
- The wrapper maps each coefficient index to a bank and bank-local row.
- A client can request up to 4 coefficients in one cycle, but the request is
  accepted only if the 4 active lanes are conflict-free under the memory bank
  mapping.

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

### Stable external seed / protocol interface

The seed / protocol store should stay simple and bridge-friendly:

| Client | Signals | Meaning |
|---|---|---|
| HSU-side seed port | `hsu_seed_req`, `hsu_seed_we`, `hsu_seed_addr`, `hsu_seed_wdata`, `hsu_seed_ready`, `hsu_seed_rvalid`, `hsu_seed_rdata` | Direct seed/protocol access for HSU-side bridges |
| Transcoder-side seed port | `tr_seed_req`, `tr_seed_we`, `tr_seed_addr`, `tr_seed_wdata`, `tr_seed_ready`, `tr_seed_rvalid`, `tr_seed_rdata` | Direct seed/protocol access for Transcoder-side bridges |

This is intentionally **not** exposed directly to the host boundary. The host
still interacts with the Control / Host Interface, while internal bridges and
the Main Controller decide what gets written to or read from the Seed Store.

### Bridge-facing seed / protocol ID + beat contract

Above Memory, the cleaner contract for HSU-side and Transcoder-side bridge
logic is:

| Signal | Meaning |
|---|---|
| `seed_req` | Bridge has an active seed/protocol access |
| `seed_we` | `1` for write, `0` for read |
| `seed_id` | Semantic object selector such as `SEED_ID_RHO` or `SEED_ID_HEK` |
| `seed_idx` | Beat offset inside the selected object (`0..3` for 256-bit values) |
| `seed_wdata` | 64-bit write data |
| `seed_ready` | Store can accept the request this cycle |
| `seed_rvalid` | Read response valid |
| `seed_rdata` | 64-bit read response data |

Memory itself remains internally address-based. The bridge performs:

`seed_addr = seed_base_addr(seed_id) + seed_idx`

That split keeps the RAM implementation simple while letting other module
designers work with semantic IDs instead of magic addresses.

### Internal control / status expectations

The architecture snapshot does not require Memory to expose itself directly as a
host-visible CSR block. However, the Main Controller should still have a small
internal control / status contract to the memory subsystem.

Already present in RTL:

- `wipe_i`
- `wipe_done_o`

Recommended internal-only additions for the next pass:

- `wipe_busy_o`
- `mem_fault_o`
- `mem_fault_code_o`

These should be internal control/status sideband signals only. They do **not**
need to become host-visible Memory CSRs.

### CMI ownership

`cmi.sv` should live with the PAU, not with Memory.

Reason:

- CMI is part of the PAU timing contract
- it aligns PAU writeback addresses to PAU datapath latency
- Memory should only expose the shared storage fabric and arbitration behavior

The duplicate Memory-owned copy was removed for that reason.

## Hazard matrix

### Current implemented behavior (v0.75 checkpoint)

| Access pair | Status | Notes |
|---|---|---|
| one client read only | Allowed | Normal read-plane use |
| one client write only | Allowed | Normal write-plane use |
| one client read + same client write | Allowed | Combined owner gets both planes |
| PAU read + HSU write | Allowed | One read owner + one write owner |
| PAU read + Transcoder write | Allowed | Same reason |
| HSU read + Transcoder write | Allowed | Same reason |
| two clients both read | Blocked | Only one read plane today |
| two clients both write | Blocked | Only one write plane today |
| same request: two read lanes hit same bank | Blocked | `rd_conflict` |
| same request: two write lanes hit same bank | Blocked | `wr_conflict` |
| same-bank read + write | Allowed | Different physical RAM ports |
| same-address read + write | Forbidden | Raises `mem_fault_code_o = 3'b001` and rejects the cycle |
| same-address write + write | Forbidden | Raises `mem_fault_code_o = 3'b010` and rejects the cycle |

### Memory status / fault sideband

Memory now exposes a small internal-only status interface to the Main
Controller:

| Signal | Meaning |
|---|---|
| `wipe_busy_o` | Wipe FSM is actively zeroizing polynomial and/or seed memory |
| `wipe_done_o` | One-cycle pulse when wipe finishes |
| `mem_fault_o` | One-cycle pulse when an illegal memory hazard is detected |
| `mem_fault_code_o[2:0]` | Encoded reason for the fault pulse |

Recommended/implemented fault code meanings in this pass:

| Code | Meaning |
|---|---|
| `3'b000` | No fault |
| `3'b001` | Illegal same-address read/write |
| `3'b010` | Illegal same-address write/write |
| `3'b011` | Same-request lane conflict / rejected request conflict |

### Proposed future-safe hazard rules

These are the rules to preserve if the internal wrapper is upgraded from
`read plane + write plane` to `2 generic ports` while keeping the external
client interface stable.

| Access pair | Proposed status | Rule |
|---|---|---|
| read + read, different banks | Allowed | Good overlap case |
| read + read, same bank, different addresses | Allowed | One read per physical port |
| read + read, same bank, same address | Allowed | Both return the same stored value |
| read + write, different banks | Allowed | Safe |
| read + write, same bank, different addresses | Allowed | Safe |
| read + write, same bank, same address | Forbidden | Simplest and safest rule |
| write + write, different banks | Allowed | Safe |
| write + write, same bank, different addresses | Allowed | One write per physical port |
| write + write, same bank, same address | Forbidden | Avoid ambiguous winner semantics |

Important note:

- Different `poly_id` values alone do **not** prove two accesses are safe.
- Legality must be decided from bank, bank-local address, operation type, and
  final port assignment.

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
- The external client interfaces are already in a good place; future overlap
  work should prefer changing **internal scheduling**, not growing top-level IO

### Negative / Remaining gaps

- Two different clients still cannot both write polynomial memory in the same
  cycle
- PAU combined requests lock both planes, so HSU/Transcoder must still wait in
  those windows
- Detailed repo docs still trail the RTL in some places
- PAU still needs a cleaner top-level integration contract for the new Memory
  interface, especially around CWM drain/writeback and final result placement
- Memory does not yet expose a small internal fault/status contract back to the
  Main Controller

## Seed / protocol store notes

`H(ek)` is not too large for the current Seed Store plan.

- In ML-KEM, `H(ek)` is a 256-bit hash value.
- The current seed store uses 64-bit words.
- So `H(ek)` naturally occupies 4 words, exactly like `d`, `z`, `m`, `rho`,
  and `sigma`.

That is why the seed map uses **base word addresses**, not single IDs.

Example:

- `SEED_BASE_HEK = 20`
- `H(ek)` occupies words `20, 21, 22, 23`

Using bases rather than single IDs is the better choice because:

- several protocol values are wider than one 64-bit entry
- the Seed Store should remain a simple RAM, not a semantic decoder
- bridges / controller logic can compute `BASE + offset` cleanly

So the right contract is:

- Memory stores raw 64-bit words at addresses
- the map package defines region bases
- bridges / controller use `BASE + word_offset`
- Memory does **not** auto-expand semantic names like "`H(ek)`" into multiple
  accesses by itself

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
