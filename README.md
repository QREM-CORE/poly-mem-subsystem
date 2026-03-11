## Memory Modules

This repository currently contains the following memory-related RTL:

- `poly_ram_bank.sv`  
  Parameterized true dual-port RAM bank used as the base storage primitive.

- `poly_mem_wrapper_4bank.sv`  
  Main QREM-facing polynomial memory wrapper. Implements 4-bank interleaved mapping and supports 4-lane accesses.

- `poly_mem_subsystem.sv`  
  Simpler banked subsystem with explicit bank selection and basic arbitration.

- `seed_ram.sv`  
  64-bit RAM for seeds and byte-oriented values.

## Polynomial Memory Mapping

The 4-bank wrapper stores one polynomial in interleaved form:

- `bank = idx % 4`
- `row = idx / 4`

Example:

| Row | Bank 0 | Bank 1 | Bank 2 | Bank 3 |
|-----|--------|--------|--------|--------|
| 0   | c0     | c1     | c2     | c3     |
| 1   | c4     | c5     | c6     | c7     |
| ... | ...    | ...    | ...    | ...    |

This supports 4 coefficient accesses per cycle and matches the banked memory idea used in ML-KEM hardware literature. 

## Running Tests

### 4-bank wrapper test
```bash
rm -rf build && mkdir -p build
iverilog -g2012 -o build/sim_out rtl/poly_ram_bank.sv rtl/poly_mem_wrapper_4bank.sv tb/tb_poly_mem_wrapper_4bank.sv
vvp build/sim_out
