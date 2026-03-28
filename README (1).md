# 5-Stage Pipelined RISC Processor

**Author:** Harshit Bothra
**Institution:** PES University, ECE Department
**Year:** 2nd Year
**Tools:** SystemVerilog, ModelSim / Xilinx Vivado

---

## Project Overview

A fully functional **5-stage pipelined RISC processor** implemented in SystemVerilog, modeled after the classic MIPS pipeline architecture used in modern CPUs and GPUs. The processor implements all five classic pipeline stages with a **forwarding unit** to resolve data hazards and a **hazard detection unit** to handle load-use stalls.

This architecture directly mirrors the execution pipelines inside Nvidia's GPU streaming multiprocessors (SMs), making it a highly relevant project for GPU architecture and hardware verification roles.

---

## Pipeline Stages

| Stage | Name | Description |
|-------|------|-------------|
| IF | Instruction Fetch | Fetches instruction from instruction memory at PC |
| ID | Instruction Decode | Decodes opcode, reads registers, generates control signals |
| EX | Execute | ALU performs arithmetic/logic, branch target computed |
| MEM | Memory Access | Reads from or writes to data memory |
| WB | Write Back | Writes result back to register file |

---

## Supported Instructions

| Opcode | Instruction | Operation |
|--------|-------------|-----------|
| 000000 | ADD | R[rd] = R[rs] + R[rt] |
| 000001 | SUB | R[rd] = R[rs] - R[rt] |
| 000010 | AND | R[rd] = R[rs] & R[rt] |
| 000011 | OR  | R[rd] = R[rs] \| R[rt] |
| 000100 | LW  | R[rt] = MEM[R[rs] + imm] |
| 000101 | SW  | MEM[R[rs] + imm] = R[rt] |
| 000110 | BEQ | if R[rs]==R[rt]: PC = PC+4+imm<<2 |
| 000111 | ADDI | R[rt] = R[rs] + imm |

---

## Key Features

- **Forwarding Unit** — resolves EX and MEM data hazards without stalls by forwarding ALU results directly to the next instruction
- **Hazard Detection Unit** — detects load-use hazards and inserts a pipeline bubble (stall) for one cycle
- **Branch Handling** — BEQ supported with pipeline flush on taken branch
- **Pipeline Registers** — IF/ID, ID/EX, EX/MEM, MEM/WB registers properly separate all stages
- **16 General-Purpose Registers** — R0 hardwired to zero (RISC convention)

---

## File Structure

```
risc_processor/
├── risc_processor.sv      # Full 5-stage pipeline implementation
├── risc_processor_tb.sv   # Testbench with pipeline monitor
└── README.md              # Project documentation
```

---

## How to Run

### Using ModelSim
```bash
vlog risc_processor.sv risc_processor_tb.sv
vsim risc_processor_tb
run -all
```

### Using Vivado
1. New Project → Add `risc_processor.sv` as design source
2. Add `risc_processor_tb.sv` as simulation source
3. Run Behavioral Simulation

---

## Test Program Output

The processor runs this built-in test program:
```
ADDI R1, R0, 5    → R1 = 5
ADDI R2, R0, 3    → R2 = 3
ADD  R3, R1, R2   → R3 = 8  (forwarding test)
SW   R3, 0(R0)    → MEM[0] = 8
LW   R4, 0(R0)    → R4 = 8  (load-use hazard test)
```

Expected output:
```
[PASS] R1 (ADDI R1=5) = 5
[PASS] R2 (ADDI R2=3) = 3
[PASS] R3 (ADD R3=R1+R2=8) [Forwarding test] = 8
[PASS] R4 (LW R4=MEM[0]=8) [Load-use hazard test] = 8
[PASS] MEM[0] = 8 (SW R3 -> MEM[0])
```
