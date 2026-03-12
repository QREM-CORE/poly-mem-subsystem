# QREM Polynomial Memory Subsystem

## Overview

This repository implements the **memory subsystem for the QREM ML-KEM hardware accelerator**.

In ML-KEM, most cryptographic operations operate on **polynomials containing 256 coefficients**. These coefficients must be stored and accessed efficiently by compute blocks such as:

- Number Theoretic Transform (NTT)
- Inverse NTT (INTT)
- Polynomial multiplication
- Sampling
- Pack / Unpack operations
- Keccak / SHAKE seed handling

Because these operations require multiple coefficients at the same time, the memory subsystem is designed using **banked polynomial memory** rather than a single RAM.

The memory architecture provides:

- parallel coefficient access
- scalable polynomial storage
- bank conflict detection
- clean integration interface for compute modules

---

# Memory Architecture

The system contains two types of memory:

1. **Polynomial memory**
2. **Seed memory**

High-level architecture:

         QREM Compute Modules
  (NTT / PolyMul / Sampler / Pack)

                |
                v
        +-------------------+
        | poly_mem_wrapper  |
        |  4-lane interface |
        +---------+---------+
                  |
    +-------------+-------------+
    |             |             |
  Bank0         Bank1         Bank2         Bank3

poly_ram_bank  poly_ram_bank  poly_ram_bank  poly_ram_bank

       Separate memory for randomness

            +---------------+
            |   seed_ram    |
            +---------------+

The **wrapper module** translates logical coefficient indices into physical bank addresses.

---

# Polynomial Memory Organization

Each polynomial contains:

- **N = 256 coefficients**
- **16-bit coefficient width**

Instead of storing all coefficients in one RAM, they are distributed across **four banks**.

This enables **parallel access to four coefficients per cycle**.

---

# Memory Mapping

The mapping rule used in the design is:


bank = coefficient_index % 4
row = coefficient_index / 4


This distributes coefficients across banks.

Example layout:

| Row | Bank0 | Bank1 | Bank2 | Bank3 |
|----|----|----|----|----|
|0|c0|c1|c2|c3|
|1|c4|c5|c6|c7|
|2|c8|c9|c10|c11|
|...|...|...|...|...|
|63|c252|c253|c254|c255|

This allows the system to read:


c0 c1 c2 c3


in **one cycle**, since they reside in different banks.

---

# Multiple Polynomial Storage

The memory can store multiple polynomials.

Each polynomial is selected using **poly_id**.

The final address inside each bank is calculated as:


bank_address = poly_id × (N/4) + row


Example:

| poly_id | rows used |
|---|---|
|0|0–63|
|1|64–127|
|2|128–191|

---

# RTL Modules

## poly_ram_bank.sv

This module implements a **dual-port RAM bank**.

Features:

- parameterized depth and width
- synchronous read
- two independent access ports

Main signals:

Port A

a_we

a_addr

a_wdata

a_rdata


Port B

b_we

b_addr

b_wdata

b_rdata


This allows simultaneous memory accesses.

---

## poly_mem_wrapper_4bank.sv

This is the **main memory interface used by compute blocks**.

Responsibilities:

- translate coefficient index → bank and row
- compute bank address
- route requests to RAM banks
- detect bank conflicts
- support **four parallel access lanes**

### Inputs


clk

rst_n

poly_id_i

v_i

rd_en_i

rd_idx_i[3:0]

wr_en_i[3:0]

wr_idx_i[3:0]

wr_data_i[3:0]


### Outputs


ready_o
rd_data_o[3:0]


### Operation

1. Decode coefficient index
2. Determine target bank
3. Calculate bank address
4. Route request to correct RAM
5. Return read data

---

## poly_mem_subsystem.sv

This module implements a **basic multi-bank memory subsystem**.

Features:

- multiple RAM banks
- simple arbitration
- support for NTT / PolyMul / Pack-Unpack accesses

This module is useful for lower-level integration and testing.

---

## seed_ram.sv

This module stores randomness and seed data.

Used by:

- Keccak
- SHAKE
- Sampler
- Random seed generation

Configuration:

| property | value |
|---|---|
|width|64 bits|
|type|synchronous RAM|

---

# Conflict Detection

Because multiple lanes may access memory simultaneously, conflicts can occur.

Example:

read coefficient 1

read coefficient 5

Both map to:

bank = 1

When this happens the wrapper detects the conflict and outputs:

ready_o = 0

This signals the compute unit to stall or retry.

---

# Memory Timing

The RAM uses **synchronous reads**.

Example:

Cycle N

address applied

Cycle N+1

data returned

Writes occur on the rising clock edge.

---

# Running Simulations

The design is verified using **Icarus Verilog**.

---

## Test polynomial memory wrapper

Compile


rm -rf build && mkdir -p build
iverilog -g2012 -o build/sim_out rtl/poly_ram_bank.sv rtl/poly_mem_wrapper_4bank.sv tb/tb_poly_mem_wrapper_4bank.sv


Run


vvp build/sim_out


Expected output


TB PASS


---

## Test seed RAM

Compile


rm -rf build && mkdir -p build
iverilog -g2012 -o build/seed_sim_out rtl/seed_ram.sv tb/tb_seed_ram.sv


Run


vvp build/seed_sim_out


Expected output


TB PASS


---

# Folder Structure


poly-mem-subsystem/

**rtl/**

- poly_ram_bank.sv
- poly_mem_wrapper_4bank.sv
- poly_mem_subsystem.sv
- seed_ram.sv

**tb/**
- tb_poly_mem_wrapper_4bank.sv
- tb_seed_ram.sv

docs/
memory_map.md
memory_interface.md

build/


---

# Integration with QREM Modules

The memory subsystem supports the following modules:

| Module | Memory usage |
|---|---|
|NTT|read/write polynomial coefficients|
|PolyMul|read operands write results|
|Sampler|write generated coefficients|
|Pack/Unpack|read polynomial values|
|Keccak|uses seed RAM|

---

# Design Goals

The memory architecture was designed to provide:

- parallel coefficient access
- scalable banked storage
- efficient polynomial mapping
- conflict detection for safe access
- integration with ML-KEM hardware pipeline

---

# Summary

The implemented memory subsystem includes:

- four dual-port polynomial RAM banks
- an interleaving memory mapping scheme
- a wrapper module handling bank routing and conflict detection
- a seed RAM for randomness storage
- simulation testbenches verifying correct operation

This memory architecture provides the storage infrastructure required for efficient ML-KEM hardware acceleration.

---

# Author

Memory subsystem implementation for the **QREM ML-KEM Hardware Accelerator Project**

York University  
Computer Engineering
