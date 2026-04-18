# QREM Polynomial Memory Subsystem

> Reference: *"Highly-Efficient Hardware Architecture for ML-KEM PQC Standard"*
> — H. Jung, Q. D. Truong, H. Lee (IEEE OJCAS 2025)

## Overview

This repository implements the **Memory Subsystem** for the QREM ML-KEM (FIPS 203) hardware accelerator.

ML-KEM operates on polynomials of **256 coefficients** (16-bit, over Z_q with q = 3329). The memory subsystem provides **4-coefficient parallel access per cycle** using a **4-bank dual-port RAM architecture** with **CMI bank mapping** that guarantees no bank collisions for NTT butterfly patterns.

### Key Features

- **CMI bit-pair-sum bank mapping** — `bank = (idx[1:0] + idx[3:2] + idx[5:4] + idx[7:6]) mod 4`
- **Split read/write arbitration planes** — one read owner and one write owner may overlap in the same cycle
- **Strict priority within each plane** — PAU > HSU > Transcoder
- **32-polynomial capacity** (configurable) with 1-cycle read latency
- **Dedicated dual-port seed/protocol store** (32 × 64-bit, HSU port + Transcoder port)
- **Security wipe FSM** — zeroes all polynomial + seed memory (~2081 cycles with the 32×64 seed store)
- **Tagged response routing** — read data delivered exclusively to the originating client

---

## Architecture

```
            PAU          HSU         Transcoder
             │            │              │
             ▼            ▼              ▼
    ┌──────────────────────────────────────────────┐
    │            poly_mem_subsystem                │
    │                                              │
    │  ┌────────────┐                              │
    │  │ Read Arbiter│  PAU > HSU > Transcoder     │
    │  │ Write Arb.  │  PAU > HSU > Transcoder     │
    │  └─────┬───────┴───────────────┬─────────────┘
    │        │                       │
    │  ┌─────▼───────────────────────▼──────┐       │
    │  │ poly_mem_wrapper_4bank             │       │
    │  │  Port A = one 4-lane READ plane    │       │
    │  │  Port B = one 4-lane WRITE plane   │       │
    │  │  CMI bank mapping + conflict check │       │
    │  └────────────────────────────────────┘       │
    │                                │             │
    │  ┌───────────────────────────┐ │             │
    │  │ seed_ram (dual-port 32×64)│ │             │
    │  └──────────────────┘          │             │
    │                                │             │
    │  ┌──────────────────┐          │             │
    │  │ Wipe FSM         │          │             │
    │  └──────────────────┘          │             │
    └──────────────────────────────────────────────┘
```

### Clients

| Client | Priority | Usage |
|--------|----------|-------|
| **PAU** (Polynomial Arithmetic Unit) | Highest | NTT butterfly, CWM, ADD drain — via external CMI adapter |
| **HSU** (Hash Sampling Unit) | Mid | Writes sampled coefficients via Poly Stream Writer |
| **Transcoder** | Lowest | ByteEncode/Decode, Compress/Decompress |

---

## RTL Modules

| Module | Description |
|--------|-------------|
| `poly_mem_subsystem.sv` | **Top-level.** Split read/write arbitration, response routing, dual-port seed store, wipe FSM |
| `mem_arbiter.sv` | Combinational strict-priority arbiter used independently for read and write planes |
| `poly_mem_wrapper_4bank.sv` | 4-bank memory core with distinct read plane and write plane |
| `poly_ram_bank.sv` | Dual-port RAM primitive (Port A = read plane, Port B = write plane) |
| `seed_ram.sv` | Dual-port seed/protocol store (32 × 64-bit) |
| `delay_n.sv` | Legacy generic delay line (kept for shared utility use) |
| `qrem_mem_map_pkg.sv` | 32-polynomial slot address map constants |
| `qrem_seed_map_pkg.sv` | Seed/protocol-store slot map constants |

---

## Memory Mapping (CMI)

The conflict-free bank mapping uses a bit-pair-sum scheme:

```
bank = (idx[1:0] + idx[3:2] + idx[5:4] + idx[7:6]) mod 4
row  = idx / 4
bank_addr = poly_id × 64 + row
```

This guarantees every NTT butterfly pair maps to **distinct banks** at every stage.

---

## Polynomial Slot Map

| Region | poly_id | Count | Purpose |
|--------|---------|-------|---------|
| A matrix | 0–15 | 16 | Public matrix (up to 4×4 for ML-KEM-1024) |
| Secret **s** | 16–19 | 4 | Secret vector |
| Error **e** | 20–23 | 4 | Error vector |
| Output **t** | 24–27 | 4 | Public key / result |
| Temp | 28–31 | 4 | Scratch storage |

---

## Running Simulations

The project uses a shared Makefile supporting **ModelSim/Questa** and **Verilator**.

```bash
# Run all testbenches
make run_all SIM=verilator

# Run a specific testbench
make run_poly_mem_tb SIM=verilator
make run_mem_frontend_top_tb SIM=verilator
```

### Testbenches

| Testbench | Coverage |
|-----------|----------|
| `poly_mem_tb` | Smoke test: vector write/read, dual-port seed store, security wipe |
| `mem_frontend_top_tb` | Integration: PAU/HSU/Transcoder overlap, combined-owner lockout, seed concurrency, wipe |
| `poly_mem_wrapper_4bank_tb` | Split-plane overlap, conflict detection, read response reorder |
| `mem_arbiter_tb` | Priority ordering, stall propagation |
| `seed_ram_tb` | Dual-port seed/protocol read/write behavior |

Expected output: **`TB PASS`**

---

## Directory Structure

```
poly-mem-subsystem/
├── rtl/
│   ├── qrem_mem_map_pkg.sv
│   ├── delay_n.sv
│   ├── mem_arbiter.sv
│   ├── poly_ram_bank.sv
│   ├── seed_ram.sv
│   ├── poly_mem_wrapper_4bank.sv
│   └── poly_mem_subsystem.sv       ← top-level
├── tb/
│   ├── poly_mem_tb.sv
│   ├── mem_frontend_top_tb.sv
│   ├── poly_mem_wrapper_4bank_tb.sv
│   ├── mem_arbiter_tb.sv
│   └── seed_ram_tb.sv
├── doc/
│   ├── docs.md                     ← detailed markdown docs
│   └── memory_subsystem.tex        ← comprehensive LaTeX document
├── build-tools/
├── rtl.f
├── Makefile
└── README.md
```

---

## Documentation

- **[doc/docs.md](doc/docs.md)** — Detailed markdown documentation covering architecture, CMI mapping, all modules, timing, and verification
- **[doc/memory_subsystem.tex](doc/memory_subsystem.tex)** — Comprehensive LaTeX document with figures, equations, and tables

---

## Authors

York University — Computer Engineering  
QREM ML-KEM Hardware Accelerator Project

- Mavra Muzmmal
- Quardin Lyttle
- Salwan Aldhahab
- Jessica Buentipo
- Mai Komar
- Kiet Le
