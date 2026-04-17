# QREM Polynomial Memory Subsystem — Detailed Documentation

Authors: Mavra Muzmmal, Quardin Lyttle, Salwan Aldhahab, Jessica Buentipo, Mai Komar, Kiet Le  
Project: QREM ML-KEM Hardware Accelerator  
Component: Polynomial Memory Subsystem  

Reference:  
"Highly-Efficient Hardware Architecture for ML-KEM PQC Standard"  
H. Jung, Q. D. Truong, H. Lee — IEEE OJCAS 2025

---

# 1. Introduction

ML-KEM (Module-Lattice Key Encapsulation Mechanism, FIPS 203) is a post-quantum cryptographic standard whose core operations act on **polynomials of 256 coefficients** over **Z_q** with **q = 3329**.

Hardware acceleration of ML-KEM requires issuing multiple coefficient reads and writes per cycle for operations such as:

- **NTT / INTT** (butterfly reads/writes of coefficient pairs)
- **Coefficient-Wise Multiply-and-Accumulate (CWM)**
- **ADD drain** (writing accumulated results back)
- **Sampling** (CBD and NTT rejection sampling via Keccak / SHAKE)
- **ByteEncode / ByteDecode / Compress / Decompress** (Transcoder)

A single-port RAM would force every operation to serialize, creating an unacceptable throughput bottleneck. This subsystem solves the problem with a **4-bank dual-port polynomial memory** combined with **conflict-free memory interface (CMI) bank mapping** derived from the NTT butterfly addressing pattern.

---

# 2. Design Goals

- **4-coefficient parallel access** in a single cycle for NTT butterfly patterns
- **Conflict-free bank mapping** using the CMI bit-pair-sum scheme
- **Multi-client arbitration** — PAU (highest), HSU (mid), Transcoder (lowest)
- **32-polynomial capacity** with configurable depth
- **Dedicated seed / protocol store** independent of polynomial arbitration
- **Security wipe** that zeroes all polynomial and seed memory before key material is released
- **Deterministic 1-cycle read latency** for pipelined compute stages
- **Clean system integration** via per-client request/response interfaces with stall-based flow control

---

# 3. High-Level Architecture

The Memory Subsystem matches the reference architecture from the IEEE OJCAS 2025 paper:

```
            PAU          HSU         Transcoder
             │            │              │
             ▼            ▼              ▼
    ┌──────────────────────────────────────────────┐
    │            poly_mem_subsystem                │
    │                                              │
    │  ┌────────────┐                              │
    │  │ Arbitrator │  PAU > HSU > Transcoder      │
    │  │mem_arbiter │  (strict priority)           │
    │  └─────┬──────┘                              │
    │        │                                     │
    │  ┌─────▼───────────────────────────┐         │
    │  │ poly_mem_wrapper_4bank          │         │
    │  │  Poly Port A (read) ──┐         │         │
    │  │  Poly Port B (write)──┤── 4 ×   │         │
    │  │  CMI bank mapping     │  poly_   │         │
    │  │  Conflict detection   │  ram_    │         │
    │  └───────────────────────┘  bank    │         │
    │                                     │         │
    │  ┌─────────────────────────────┐    │         │
    │  │ Seed & Protocol Store       │    │         │
    │  │ seed_ram                    │    │         │
    │  └─────────────────────────────┘    │         │
    │                                     │         │
    │  ┌─────────────────────────────┐    │         │
    │  │ Security Wipe FSM           │    │         │
    │  │ IDLE→WIPE_POLY→WIPE_SEED   │    │         │
    │  │      →DONE→IDLE            │    │         │
    │  └─────────────────────────────┘    │         │
    └──────────────────────────────────────────────┘
```

### Clients

| Client | Priority | Usage |
|---|---|---|
| **PAU** (Polynomial Arithmetic Unit) | Highest | NTT butterfly, CWM, ADD drain — drives requests through the external CMI adapter |
| **HSU** (Hash Sampling Unit) | Mid | Writes sampled coefficients via Poly Stream Writer |
| **Transcoder** | Lowest | ByteEncode/Decode, Compress/Decompress — sequential polynomial read/write |

All three clients share the same 4-lane vector interface. The arbiter grants exactly one client per cycle; the others are stalled.

---

# 4. Conflict-Free Memory Interface (CMI) Bank Mapping

### Why not simple modulo?

A naïve `bank = index % 4` mapping creates conflicts for NTT butterfly access patterns. For example, indices 0 and 4 both land in bank 0 under modulo-4, yet the first butterfly stage needs to read them in the same cycle.

### CMI bit-pair-sum scheme

The design uses a **bit-pair-sum** mapping:

```
bank = (idx[1:0] + idx[3:2] + idx[5:4] + idx[7:6]) mod 4
```

This guarantees that every butterfly pair at every NTT stage maps to **distinct banks**, enabling conflict-free parallel reads.

### Row address

Regardless of bank mapping, the row within a bank is:

```
row = idx >> 2    (i.e., idx / 4)
```

The final bank address is:

```
bank_addr = poly_id × (N/4) + row
```

### Example: first 12 coefficients under CMI mapping

| idx | idx[1:0] | idx[3:2] | idx[5:4] | idx[7:6] | sum mod 4 (bank) | row |
|-----|----------|----------|----------|----------|-------------------|-----|
| 0   | 0        | 0        | 0        | 0        | 0                 | 0   |
| 1   | 1        | 0        | 0        | 0        | 1                 | 0   |
| 2   | 2        | 0        | 0        | 0        | 2                 | 0   |
| 3   | 3        | 0        | 0        | 0        | 3                 | 0   |
| 4   | 0        | 1        | 0        | 0        | 1                 | 1   |
| 5   | 1        | 1        | 0        | 0        | 2                 | 1   |
| 6   | 2        | 1        | 0        | 0        | 3                 | 1   |
| 7   | 3        | 1        | 0        | 0        | 0                 | 1   |
| 8   | 0        | 2        | 0        | 0        | 2                 | 2   |
| 9   | 1        | 2        | 0        | 0        | 3                 | 2   |
| 10  | 2        | 2        | 0        | 0        | 0                 | 2   |
| 11  | 3        | 2        | 0        | 0        | 1                 | 2   |

Note how consecutive groups of 4 always land in distinct banks — this is critical for the wipe FSM, which writes 4 zeroes per cycle.

---

# 5. Polynomial Memory Organization

- **N = 256** coefficients per polynomial
- **W = 16** bits per coefficient
- **4 banks**, each storing **64 rows** per polynomial
- **32 polynomial slots** (configurable via `NUM_POLYS`)
- Bank depth = `NUM_POLYS × 64 = 2048` entries per bank

### Polynomial slot allocation (`qrem_mem_map_pkg`)

| Region | poly_id range | Count | Purpose |
|--------|---------------|-------|---------|
| A matrix | 0–15 | 16 | ML-KEM-1024 worst case (4×4) |
| Secret **s** | 16–19 | 4 | Secret vector |
| Error **e** | 20–23 | 4 | Error vector |
| Output **t** | 24–27 | 4 | Public key / result |
| Temp/scratch | 28–31 | 4 | Intermediate storage |

---

# 6. RTL Module Descriptions

## 6.1 `poly_mem_subsystem.sv` — Top-Level Memory Subsystem

**Authors:** Mavra Muzmmal, Quardin Lyttle, Salwan Aldhahab

This is the top-level module. It integrates:

1. **Arbitrator** (`mem_arbiter`) — strict priority PAU > HSU > Transcoder
2. **Request mux** — routes the winning client's 4-lane vector request to the memory wrapper
3. **Poly Port A/B** (`poly_mem_wrapper_4bank`) — 4-bank polynomial memory with CMI mapping
4. **Seed & Protocol Store** (`seed_ram`) — independent from polynomial arbitration
5. **Security wipe FSM** — zeroes all memory before releasing key material
6. **Response router** — tags read responses with owner ID and delivers data exclusively to the originating client

### Interface

Each client (PAU, HSU, Transcoder) has an identical set of signals:

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `*_req` | in | 1 | Request valid |
| `*_poly_id` | in | 5 | Polynomial slot selector |
| `*_rd_en` | in | 1 | Read enable |
| `*_rd_idx` | in | 4×8 | Read coefficient indices (4 lanes) |
| `*_rd_lane_valid` | in | 4 | Per-lane read valid |
| `*_wr_en` | in | 4 | Per-lane write enable |
| `*_wr_idx` | in | 4×8 | Write coefficient indices |
| `*_wr_data` | in | 4×16 | Write data |
| `*_rd_valid` | out | 1 | Read response valid |
| `*_rd_poly_id` | out | 5 | Read response polynomial ID |
| `*_rd_idx_o` | out | 4×8 | Read response indices |
| `*_rd_lane_valid_o` | out | 4 | Read response lane valids |
| `*_rd_data` | out | 4×16 | Read data |
| `*_stall` | out | 1 | Client must hold request |

### Security Wipe FSM

| State | Action |
|-------|--------|
| `WIPE_IDLE` | Normal operation; transition on `wipe_i` pulse |
| `WIPE_POLY` | Write zero to all 32 polynomials × 64 rows. 4 coefficients per cycle (conflict-free under CMI). All clients stalled. |
| `WIPE_SEED` | Write zero to all 16 seed locations |
| `WIPE_DONE` | Assert `wipe_done_o` for one cycle, return to `WIPE_IDLE` |

Total wipe latency: `32 × 64 + 16 + 1 = 2065 cycles`.

---

## 6.2 `mem_arbiter.sv` — Priority Arbitrator

**Authors:** Mavra Muzmmal, Quardin Lyttle

Purely combinational module implementing strict priority:

1. If `pau_req_i` → grant PAU, stall HSU and Transcoder
2. Else if `hsu_req_i` → grant HSU, stall Transcoder
3. Else if `tr_req_i` → grant Transcoder

The winning client's stall output reflects backpressure from the memory wrapper (`mem_ready_i`). Losing clients always see `stall = 1`.

---

## 6.3 `poly_mem_wrapper_4bank.sv` — 4-Bank Polynomial Memory

**Authors:** Mavra Muzmmal, Jessica Buentipo

This module implements Poly Port A (read path) and Poly Port B (write path) to the four banked Poly RAMs.

### Responsibilities

- Map coefficient indices → `{bank, local_addr}` using the CMI bit-pair-sum function
- Detect read-read and write-write bank conflicts (6 pairwise comparisons each)
- Route reads to Port A and writes to Port B of each `poly_ram_bank`
- Pipeline read metadata for 1-cycle response alignment
- Reorder read data from bank-indexed outputs back to lane order

### Conflict Detection

Read-vs-write to the same bank is **not** a conflict because reads use Port A and writes use Port B of the dual-port RAM. Only read-read or write-write same-bank collisions cause `ready_o = 0`.

### Timing

- **Request accepted** when `v_i && ready_o`
- **Read data available** 1 cycle after acceptance
- **Writes** take effect on the same clock edge they are accepted

---

## 6.4 `poly_ram_bank.sv` — Dual-Port RAM Primitive

**Author:** Mavra Muzmmal

Single dual-port RAM block. Each bank instance stores `NUM_POLYS × 64` entries of `W`-bit data.

- **Port A:** used for reads (address presented, data returned next cycle)
- **Port B:** used for writes (write-enable + address + data applied on clock edge)
- Both ports can operate independently in the same cycle

---

## 6.5 `seed_ram.sv` — Seed and Protocol Store

**Author:** Mavra Muzmmal

Simple synchronous RAM for storing seed values, hash state, and protocol metadata.

- **Depth:** 16 entries (configurable)
- **Width:** 64 bits
- **Read latency:** 1 cycle
- Independent from polynomial memory arbitration (own request port on `poly_mem_subsystem`)

---

## 6.6 `delay_n.sv` — Generic Delay Line

**Author:** Kiet Le

Parameterized shift register used inside the CMI module to align writeback indices with AU result data. Instantiated with depths of 2, 4, 5, and 9 cycles for the different operation latencies (NTT butterfly, CWM, ADD drain).

---

## 6.7 `cmi.sv` — Conflict-Free Memory Interface (PAU Component)

**Author:** Mai Komar

**Note:** This module belongs to the PAU, not the Memory Subsystem. It is included in this repository to define the interface contract between the PAU and `poly_mem_wrapper_4bank`.

### Responsibilities

- Forward 4-lane read requests (coefficient indices + valid flags) to the memory wrapper
- Consume the wrapper's 1-cycle read response and present aligned data to the Arithmetic Unit
- Align writeback indices via configurable delay pipelines so write addresses arrive at the wrapper at the same time as AU result data
- Allow write-only cycles for drain/final writeback phases

---

## 6.8 `qrem_mem_map_pkg.sv` — Polynomial Slot Map Package

Defines the 32-polynomial address map as SystemVerilog `localparam` constants. Used by the controller to address specific polynomial slots (A matrix, s vector, e vector, t vector, scratch).

---

# 7. Read/Write Timing

```
Cycle 0:  Client asserts req, poly_id, rd_en, rd_idx, rd_lane_valid
          Arbiter grants client; wrapper accepts (ready_o = 1)
          Bank Port A address is applied

Cycle 1:  Bank RAM outputs data on a_rdata
          Wrapper presents rd_valid_o = 1, rd_data_o = reordered bank data
          poly_mem_subsystem routes response to originating client
```

Writes are applied combinationally to Port B on the acceptance cycle (cycle 0). Write data is visible to reads starting from cycle 1.

---

# 8. Simulation and Verification

### Build system

The project uses a shared Makefile that supports both ModelSim/Questa (`vsim`) and Verilator.

```bash
# Run all testbenches
make run_all SIM=verilator

# Run a single testbench
make run_poly_mem_tb SIM=verilator
make run_mem_frontend_top_tb SIM=verilator
```

### Testbenches

| Testbench | What it verifies |
|-----------|-----------------|
| `poly_mem_tb` | PAU-only smoke test: vector write/read, seed store, security wipe |
| `mem_frontend_top_tb` | Full integration: PAU vector write/read, HSU→Transcoder cross-client, arbitration + isolation, seed store, security wipe |
| `poly_mem_wrapper_4bank_tb` | Wrapper-level: CMI bank mapping, conflict detection, read response reorder |
| `cmi_tb` | CMI adapter: read forwarding, writeback delay alignment |
| `mem_arbiter_tb` | Arbiter-level: priority ordering, stall propagation |
| `seed_ram_tb` | Seed RAM: write/read, address sweep |

Expected output for all: `TB PASS`

---

# 9. Directory Structure

```
poly-mem-subsystem/
├── rtl/
│   ├── qrem_mem_map_pkg.sv        # Polynomial slot address map
│   ├── delay_n.sv                 # Generic shift register
│   ├── cmi.sv                     # PAU conflict-free memory interface
│   ├── mem_arbiter.sv             # Priority arbiter
│   ├── poly_ram_bank.sv           # Dual-port RAM primitive
│   ├── seed_ram.sv                # Seed / protocol store
│   ├── poly_mem_wrapper_4bank.sv  # 4-bank memory with CMI mapping
│   └── poly_mem_subsystem.sv      # Top-level memory subsystem
├── tb/
│   ├── poly_mem_tb.sv
│   ├── mem_frontend_top_tb.sv
│   ├── poly_mem_wrapper_4bank_tb.sv
│   ├── cmi_tb.sv
│   ├── mem_arbiter_tb.sv
│   └── seed_ram_tb.sv
├── doc/
│   └── docs.md                    # This document
├── build-tools/                   # Shared build system
├── rtl.f                          # Filelist for compilation
├── Makefile
└── README.md
```

---

# 10. Summary

The QREM polynomial memory subsystem provides:

- **4-bank dual-port polynomial memory** with CMI conflict-free bank mapping
- **Priority arbitration** (PAU > HSU > Transcoder) granting one client per cycle
- **1-cycle read latency** with tagged response routing to the correct client
- **Dedicated seed / protocol store** on an independent port
- **Security wipe FSM** clearing all polynomial and seed memory in ~2065 cycles
- **32-polynomial capacity** organized via `qrem_mem_map_pkg`

The architecture follows the Memory Subsystem design described in *"Highly-Efficient Hardware Architecture for ML-KEM PQC Standard"* (IEEE OJCAS 2025).

---

York University — Computer Engineering  
QREM ML-KEM Hardware Accelerator Project

This architecture enables efficient hardware execution of ML-KEM cryptographic operations.
