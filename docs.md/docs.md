# QREM Polynomial Memory Subsystem – Detailed Documentation

Author: Mavra Muzmmal  
Project: QREM ML-KEM Hardware Accelerator  
Component: Polynomial Memory Subsystem  

---

# 1. Introduction

The ML-KEM (Module-Lattice Key Encapsulation Mechanism) cryptographic algorithm operates on **polynomials containing 256 coefficients**.

Hardware acceleration of ML-KEM requires **efficient memory access** because modules such as:

• NTT (Number Theoretic Transform)  
• Polynomial Multiplication  
• Sampling  
• Packing / Unpacking  
• Keccak / SHAKE  

must frequently read and write polynomial coefficients.

A naïve memory design using a **single RAM** would create severe bottlenecks.

To solve this problem, this project implements a **banked polynomial memory subsystem** capable of parallel coefficient access.

---

# 2. Design Goals

The memory subsystem was designed with the following goals:

• Allow parallel coefficient access  
• Support multiple polynomials  
• Prevent memory conflicts  
• Provide scalable architecture  
• Integrate easily with compute modules  
• Maintain deterministic timing for hardware pipelines

---

# 3. High Level Architecture

The QREM memory subsystem consists of two main components:

1. Polynomial Memory
2. Seed Memory
            +----------------------+
            |   QREM Controller    |
            +----------+-----------+
                       |
                       v
              +------------------+
              |  Compute Units   |
              | NTT / PolyMul    |
              | Pack / Unpack    |
              +--------+---------+
                       |
                       v
           +--------------------------+
           | poly_mem_wrapper_4bank   |
           |                          |
           |  address mapping         |
           |  bank selection          |
           |  conflict detection      |
           +-----------+--------------+
                       |
    +------------------+-----------------------------------+
    |                  |                  |                |
  Bank0              Bank1              Bank2            Bank3
  poly_ram_bank  poly_ram_bank   poly_ram_bank   poly_ram_bank

Separate randomness memory:
Keccak / SHAKE
|
v
seed_ram


---

# 4. Polynomial Memory Organization

Each polynomial contains:

N = 256 coefficients

Each coefficient is:

16 bits wide

To enable parallel access, the polynomial is divided across **four memory banks**.

Each bank stores **every fourth coefficient**.

---

# 5. Memory Mapping

The coefficient index determines the bank and row using:
- bank = coefficient_index % 4
- row = coefficient_index / 4


Example distribution:

|Row|Bank0|Bank1|Bank2|Bank3|
|---|---|---|---|---|
|0|c0|c1|c2|c3|
|1|c4|c5|c6|c7|
|2|c8|c9|c10|c11|
|...|...|...|...|...|
|63|c252|c253|c254|c255|

This layout enables **4-coefficient parallel access**.

---

# 6. Multiple Polynomial Storage

The design supports storing multiple polynomials.

The polynomial identifier is:

Example distribution:

|Row|Bank0|Bank1|Bank2|Bank3|
|---|---|---|---|---|
|0|c0|c1|c2|c3|
|1|c4|c5|c6|c7|
|2|c8|c9|c10|c11|
|...|...|...|...|...|
|63|c252|c253|c254|c255|

This layout enables **4-coefficient parallel access**.

---

# 6. Multiple Polynomial Storage

The design supports storing multiple polynomials.

The polynomial identifier is:
poly_id

The final bank address is computed as:
bank_address = poly_id × (N/4) + row


Example:

|poly_id|row range|
|---|---|
|0|0-63|
|1|64-127|
|2|128-191|
|3|192-255|

---

# 7. RTL Module Descriptions

## 7.1 poly_ram_bank.sv

This module implements the **basic dual-port RAM block** used by each bank.

### Features

• dual-port memory  
• synchronous read  
• parameterizable depth  
• parameterizable width

### Port A
- a_we
- a_addr
- a_wdata
- a_rdata

### Port B
- b_we
- b_addr
- b_wdata
- b_rdata

This enables simultaneous memory operations.

---

## 7.2 poly_mem_wrapper_4bank.sv

This is the **main memory interface module**.

Responsibilities:

• translate coefficient index to bank number  
• compute row address  
• calculate final bank address  
• route accesses to RAM banks  
• detect bank conflicts  
• return read data

---

### Inputs

This enables simultaneous memory operations.

---

## 7.2 poly_mem_wrapper_4bank.sv

This is the **main memory interface module**.

Responsibilities:

• translate coefficient index to bank number  
• compute row address  
• calculate final bank address  
• route accesses to RAM banks  
• detect bank conflicts  
• return read data

---

### Inputs
- clk
- rst_n
- poly_id_i
- v_i
- rd_en_i
- rd_idx_i[3:0]
- wr_en_i[3:0]
- wr_idx_i[3:0]
- wr_data_i[3:0]


Explanation:

**clk**  
System clock

**rst_n**  
Active-low reset

**poly_id_i**  
Selects which polynomial is being accessed

**v_i**  
Request valid signal

**rd_en_i**  
Indicates a read request

**rd_idx_i** 
Coefficient indices for four lanes

**wr_en_i** 
Write enable signals for four lanes

**wr_idx_i**  
Coefficient indices for writes

**wr_data_i** 
Data values to write

---

### Outputs
- ready_o
- rd_data_o[3:0]

**ready_o**  
Indicates whether memory access is safe (no conflicts)

**rd_data_o** 
Data returned from memory banks

---

# 8. Conflict Detection

When two accesses target the same bank in the same cycle, a conflict occurs.

Example:
read coefficient 1
read coefficient 5

Both map to:

bank = 1

The wrapper detects this conflict and outputs:

ready_o = 0

The compute module must retry or stall.

---

# 9. Memory Timing

The memory uses **synchronous read behavior**.

Timing example:

**Cycle N** 
Address applied

**Cycle N+1**  
Data returned

Writes occur on the rising clock edge.

---

# 10. Seed Memory

Random seeds used by the cryptographic system are stored in **seed_ram**.

Used by:

• Keccak  
• SHAKE  
• sampling modules  

Configuration:

|property|value|
|---|---|
|width|64 bits|
|type|synchronous RAM|

---

# 11. Simulation and Verification

The memory system was tested using **Icarus Verilog**.

**Compile simulation:**

rm -rf build

mkdir build

iverilog -g2012

-o build/sim_out

rtl/poly_ram_bank.sv

rtl/poly_mem_wrapper_4bank.sv

tb/tb_poly_mem_wrapper_4bank.sv


**Run simulation:**

vvp build/sim_out

**Expected output:**


TB PASS


---

# 12. Project Directory Structure


poly-mem-subsystem

rtl
poly_ram_bank.sv
poly_mem_wrapper_4bank.sv
poly_mem_subsystem.sv
seed_ram.sv

tb
tb_poly_mem_wrapper_4bank.sv
tb_seed_ram.sv

README.md
docs.md
build


---

# 13. Summary

The implemented memory subsystem provides:

• four dual-port RAM banks  
• efficient polynomial storage  
• parallel coefficient access  
• conflict detection logic  
• seed memory for randomness  

This architecture enables efficient hardware execution of ML-KEM cryptographic operations.
