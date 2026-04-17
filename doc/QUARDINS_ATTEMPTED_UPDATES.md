# Quardin's Attempted Updates

## Why this branch exists

This branch realigns the memory repo with the `v0.7` QREM architecture and the
row-wise KeyGen / scratch-accumulator PAU flow discussed during design review.

The old frontend had three big problems:

1. It modeled PAU, HSU, and Transcoder as **scalar** clients, even though the
   real architecture is built around **4-lane polynomial access**.
2. It split ownership rules across multiple places:
   - `mem_arbiter` only arbitrated PAU vs HSU cleanly
   - Transcoder bypassed that path through a separate PU route
   - `poly_mem_subsystem` had its own partial priority policy
3. It broadcast returned NTT-side data to more than one client with no clear
   response ownership.

That combination did not match the row-wise KeyGen FSM, the PAU scratch-backed
MAC update, or the strict `PAU > HSU > Transcoder` priority called out in the
system architecture snapshot.

## What changed

### 1. `mem_arbiter.sv`

Rewritten as a **centralized owner arbiter**.

New behavior:

- strict one-slot arbitration
- strict priority:
  - PAU
  - HSU / poly-memory writer
  - Transcoder
- selected client sees downstream stall if the memory core is not ready
- lower-priority active clients stall immediately

Important design choice:

This arbiter no longer tries to partially understand bank routing. It only
chooses the owner of the shared vector request slot for the current cycle.

### 2. `mem_frontend_top.sv`

Rewritten around a **shared 4-lane polynomial request plane**.

New client contract for PAU / HSU / Transcoder:

- `req`
- `poly_id`
- `rd_en`
- `rd_idx[4]`
- `rd_lane_valid[4]`
- `wr_en[4]`
- `wr_idx[4]`
- `wr_data[4]`
- routed response:
  - `rd_valid`
  - `rd_poly_id`
  - `rd_idx_o`
  - `rd_lane_valid_o`
  - `rd_data[4]`

Key fixes:

- PAU is now treated as a true vector client.
- HSU is treated as a vector write/read client suitable for a poly-memory
  writer bridge.
- Transcoder no longer bypasses arbitration.
- Read responses are explicitly tagged by owner and routed only to the client
  that issued the accepted read.

This is the biggest architectural fix in the branch.

### 3. `poly_mem_subsystem.sv`

Rewritten so the subsystem matches the architecture more directly.

New role:

- owns the banked polynomial memory through `poly_mem_wrapper_4bank`
- owns the lightweight seed/protocol store through `seed_ram`
- supports a security wipe for both polynomial and seed memory

Important change:

The old subsystem exposed separate legacy scalar concepts like:

- NTT path
- PolyMul path
- Pack/Unpack path

Those were replaced by:

- one shared vector polynomial-memory port
- one independent seed-store port

This matches the current architecture much better:

- PAU uses the vector polynomial interface through CMI
- HSU reaches polynomial memory through a writer bridge
- Transcoder is another shared vector client
- seed handling stays independent of the poly-bank datapath

### 4. `poly_mem_wrapper_4bank.sv`

Fixed the reset polarity bug in the read-response bookkeeping block.

Before:

- `rst_n` name suggested active-low
- implementation used active-high sensitivity/behavior

Now:

- the bookkeeping logic is actually active-low, matching the signal name and
  the rest of the repo.

### 5. `cmi.sv`

Small compileability fix:

- replaced the head-of-pipeline `always_comb` assignments that Icarus did not
  like for unresolved array words with explicit continuous assigns

This was not a functional architecture change, but it was necessary to get the
repo back into a testable state.

## How this matches the KeyGen FSM

The intended row-wise KeyGen memory behavior is now much easier to model:

1. PAU keeps `s_hat` resident in polynomial memory.
2. HSU / poly-memory writer writes `e_i` and staged `A_i0..A_i(k-1)` rows.
3. PAU uses the vector memory plane to read the needed operands.
4. The PAU scratch accumulator traps the row sum locally.
5. During drain, PAU reads `e_hat` and writes final `t_hat`.

The important memory win is:

- during row accumulation, shared polynomial memory does **not** need to
  repeatedly read and rewrite `t_acc`

That leaves the shared memory system in a much healthier place than the old
memory-backed partial-sum loop.

## Pain points that were identified

### Old pain point 1: scalar frontend vs vector architecture

This was the biggest mismatch.

The old `mem_frontend_top` only accepted one coefficient index per client per
cycle. That does not match:

- PAU NTT / ADDSUB behavior
- PAU CWM drain path
- HSU 4-coefficient sampling output
- Transcoder block-wise coefficient movement

### Old pain point 2: split arbitration

The old system had:

- `mem_arbiter` partially deciding priority
- `poly_mem_subsystem` making more decisions later
- Transcoder bypassing parts of that logic

That made it hard to reason about true ownership and backpressure.

### Old pain point 3: response ownership

The old top-level broadcast NTT-side read data to more than one client.

That is unsafe once different clients can be stalled or retried. The new
frontend stores the accepted read owner and routes the read response only to
that owner.

### Old pain point 4: memory model drift

The repo contained both:

- a newer 4-lane wrapper/CMI memory story
- an older scalar NTT / PM / PU story

This branch chooses one clear direction: the shared 4-lane wrapper path.

## What still needs follow-up

### 1. HSU bridge logic

This repo now exposes a proper memory-side vector contract for HSU, but it
still does **not** contain the actual AXI-stream-to-poly-writer bridge module.

That bridge still belongs at the system integration layer or as a future memory
repo addition.

### 2. Seed bridge arbitration

The seed store is now cleanly exposed as a direct port from the subsystem, but
this branch does **not** yet add a multi-client seed bridge.

That means:

- the system still needs a small seed-reader / seed-writer bridge above this
  memory layer for HSU / Transcoder / controller coordination

### 3. Encaps / Decaps scheduling

This branch makes KeyGen much more credible, but Encaps and Decaps still need
careful schedule work.

Main remaining risks:

- Encaps:
  - deciding how much overlap to allow between HSU writes and PAU row work
  - coordinating `u` row generation vs `v` inner product flow
- Decaps:
  - similar vector accumulation pressure for the `s_hat * u_hat` style work
  - seed/protocol-store coordination for `H(ek)`, `z`, and related protocol
    fields

The good news is that the same shared-memory contract now supports those flows
better because the PAU side is no longer pretending to be scalar.

### 4. Optional future optimization

This branch keeps the strict `PAU > HSU > Transcoder` arbitration and one
accepted vector transaction per cycle.

That is the safest interpretation of `v0.7`.

If later profiling shows we need more overlap, a future branch could explore:

- bank-aware multi-client issue when requests are provably disjoint
- ping-pong PAU row scratchpads
- dedicated HSU staging buffers

But those are optimizations, not correctness prerequisites.

## Validation done on this branch

Passing testbenches:

- `tb/mem_arbiter_tb.sv`
- `tb/poly_mem_tb.sv`
- `tb/mem_frontend_top_tb.sv`

Additional note:

Icarus still prints a handful of "constant selects in always_*" warnings on
existing code patterns, but the updated benches pass.
