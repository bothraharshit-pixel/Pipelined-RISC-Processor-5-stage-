// ============================================================
// Project      : 5-Stage Pipelined RISC Processor
// Author       : Harshit Bothra
// College      : PES University, ECE Department
// Tool         : ModelSim / Xilinx Vivado
// Description  : A simplified 5-stage pipelined RISC processor
//                implementing the classic IF, ID, EX, MEM, WB
//                pipeline stages with hazard detection and
//                forwarding unit for data hazards.
// ============================================================

module risc_processor (
    input  logic        clk,        // Clock signal
    input  logic        rst,        // Active-high synchronous reset
    output logic [31:0] pc_out      // Current program counter (for debug)
);

    // ============================================================
    // INSTRUCTION SET (6-bit opcode)
    // ADD  = 6'b000000  : R[rd] = R[rs] + R[rt]
    // SUB  = 6'b000001  : R[rd] = R[rs] - R[rt]
    // AND  = 6'b000010  : R[rd] = R[rs] & R[rt]
    // OR   = 6'b000011  : R[rd] = R[rs] | R[rt]
    // LW   = 6'b000100  : R[rt] = MEM[R[rs] + imm]
    // SW   = 6'b000101  : MEM[R[rs] + imm] = R[rt]
    // BEQ  = 6'b000110  : if(R[rs]==R[rt]) PC = PC+4+imm<<2
    // ADDI = 6'b000111  : R[rt] = R[rs] + imm
    // ============================================================

    // ---- Parameter Definitions ----
    parameter ADDR_WIDTH = 8;   // 256 instruction memory locations
    parameter DATA_WIDTH = 32;  // 32-bit data
    parameter REG_COUNT  = 16;  // 16 general-purpose registers

    // ============================================================
    // MEMORIES
    // ============================================================

    // Instruction Memory (ROM - read only during execution)
    logic [31:0] instr_mem [0:255];

    // Data Memory (RAM - read/write)
    logic [31:0] data_mem  [0:255];

    // Register File (16 x 32-bit registers)
    // R0 is hardwired to 0 (RISC convention)
    logic [31:0] reg_file  [0:15];

    // ============================================================
    // PIPELINE REGISTERS
    // Each stage has input/output registers to hold intermediate values
    // ============================================================

    // --- IF/ID Pipeline Register ---
    logic [31:0] IFID_instr;    // Fetched instruction
    logic [31:0] IFID_pc;       // PC + 4 (next PC)

    // --- ID/EX Pipeline Register ---
    logic [31:0] IDEX_pc;
    logic [31:0] IDEX_regA;     // Read data from RS register
    logic [31:0] IDEX_regB;     // Read data from RT register
    logic [31:0] IDEX_imm;      // Sign-extended immediate
    logic [3:0]  IDEX_rs;       // Source register index
    logic [3:0]  IDEX_rt;       // Target register index
    logic [3:0]  IDEX_rd;       // Destination register index
    logic [5:0]  IDEX_opcode;   // Operation code
    // Control signals
    logic        IDEX_regWrite;
    logic        IDEX_memRead;
    logic        IDEX_memWrite;
    logic        IDEX_memToReg;
    logic        IDEX_aluSrc;
    logic        IDEX_branch;

    // --- EX/MEM Pipeline Register ---
    logic [31:0] EXMEM_aluResult;
    logic [31:0] EXMEM_regB;
    logic [3:0]  EXMEM_rd;
    logic        EXMEM_regWrite;
    logic        EXMEM_memRead;
    logic        EXMEM_memWrite;
    logic        EXMEM_memToReg;
    logic        EXMEM_zero;     // Zero flag from ALU
    logic        EXMEM_branch;
    logic [31:0] EXMEM_branchTarget;

    // --- MEM/WB Pipeline Register ---
    logic [31:0] MEMWB_readData;  // Data read from memory
    logic [31:0] MEMWB_aluResult;
    logic [3:0]  MEMWB_rd;
    logic        MEMWB_regWrite;
    logic        MEMWB_memToReg;

    // ============================================================
    // PROGRAM COUNTER
    // ============================================================
    logic [31:0] pc;
    logic [31:0] pc_next;
    logic        pc_stall;       // Stall signal from hazard unit
    logic        branch_taken;

    assign pc_out    = pc;
    assign branch_taken = EXMEM_branch & EXMEM_zero;

    always_ff @(posedge clk) begin
        if (rst)
            pc <= 32'h0;
        else if (!pc_stall)
            pc <= branch_taken ? EXMEM_branchTarget : pc + 4;
    end

    // ============================================================
    // STAGE 1: IF — Instruction Fetch
    // Fetches instruction from instruction memory at current PC
    // ============================================================
    logic [31:0] fetched_instr;
    assign fetched_instr = instr_mem[pc[9:2]]; // Word-aligned fetch

    always_ff @(posedge clk) begin
        if (rst || branch_taken) begin
            IFID_instr <= 32'b0; // Flush on branch
            IFID_pc    <= 32'b0;
        end else if (!pc_stall) begin
            IFID_instr <= fetched_instr;
            IFID_pc    <= pc + 4;
        end
    end

    // ============================================================
    // STAGE 2: ID — Instruction Decode + Register Read
    // Decodes opcode and reads from register file
    // ============================================================
    logic [5:0]  id_opcode;
    logic [3:0]  id_rs, id_rt, id_rd;
    logic [15:0] id_imm_raw;
    logic [31:0] id_imm_ext;  // Sign extended immediate
    logic [31:0] id_regA, id_regB;
    logic        id_regWrite, id_memRead, id_memWrite;
    logic        id_memToReg, id_aluSrc, id_branch;

    // Decode instruction fields
    assign id_opcode  = IFID_instr[31:26];
    assign id_rs      = IFID_instr[25:22];
    assign id_rt      = IFID_instr[21:18];
    assign id_rd      = IFID_instr[17:14];
    assign id_imm_raw = IFID_instr[15:0];
    assign id_imm_ext = {{16{id_imm_raw[15]}}, id_imm_raw}; // Sign extend

    // Register file read (R0 always 0)
    assign id_regA = (id_rs == 4'b0) ? 32'b0 : reg_file[id_rs];
    assign id_regB = (id_rt == 4'b0) ? 32'b0 : reg_file[id_rt];

    // ---- Control Unit ----
    // Generates control signals based on opcode
    always_comb begin
        id_regWrite = 0; id_memRead  = 0; id_memWrite = 0;
        id_memToReg = 0; id_aluSrc   = 0; id_branch   = 0;
        case (id_opcode)
            6'b000000: begin id_regWrite=1; end                         // ADD
            6'b000001: begin id_regWrite=1; end                         // SUB
            6'b000010: begin id_regWrite=1; end                         // AND
            6'b000011: begin id_regWrite=1; end                         // OR
            6'b000100: begin id_regWrite=1; id_memRead=1;               // LW
                             id_memToReg=1; id_aluSrc=1; end
            6'b000101: begin id_memWrite=1; id_aluSrc=1; end            // SW
            6'b000110: begin id_branch=1; end                           // BEQ
            6'b000111: begin id_regWrite=1; id_aluSrc=1; end            // ADDI
        endcase
    end

    // ID/EX Pipeline Register Update
    always_ff @(posedge clk) begin
        if (rst || pc_stall) begin
            IDEX_regWrite <= 0; IDEX_memRead  <= 0;
            IDEX_memWrite <= 0; IDEX_memToReg <= 0;
            IDEX_aluSrc   <= 0; IDEX_branch   <= 0;
            IDEX_regA <= 0; IDEX_regB <= 0; IDEX_imm <= 0;
            IDEX_rs <= 0; IDEX_rt <= 0; IDEX_rd <= 0;
            IDEX_opcode <= 0; IDEX_pc <= 0;
        end else begin
            IDEX_regWrite <= id_regWrite; IDEX_memRead  <= id_memRead;
            IDEX_memWrite <= id_memWrite; IDEX_memToReg <= id_memToReg;
            IDEX_aluSrc   <= id_aluSrc;  IDEX_branch   <= id_branch;
            IDEX_regA  <= id_regA; IDEX_regB  <= id_regB;
            IDEX_imm   <= id_imm_ext;
            IDEX_rs    <= id_rs;   IDEX_rt    <= id_rt;   IDEX_rd <= id_rd;
            IDEX_opcode <= id_opcode; IDEX_pc <= IFID_pc;
        end
    end

    // ============================================================
    // STAGE 3: EX — Execute (ALU Operations)
    // Performs arithmetic/logic operations
    // ============================================================
    logic [31:0] ex_aluA, ex_aluB, ex_aluResult;
    logic        ex_zero;
    logic [1:0]  forwardA, forwardB; // Forwarding control signals

    // ---- Forwarding MUXes ----
    // Resolve data hazards by forwarding results from later stages
    always_comb begin
        case (forwardA)
            2'b00: ex_aluA = IDEX_regA;          // No forwarding
            2'b01: ex_aluA = MEMWB_aluResult;    // Forward from WB
            2'b10: ex_aluA = EXMEM_aluResult;    // Forward from MEM
            default: ex_aluA = IDEX_regA;
        endcase
        case (forwardB)
            2'b00: ex_aluB = IDEX_aluSrc ? IDEX_imm : IDEX_regB;
            2'b01: ex_aluB = MEMWB_aluResult;
            2'b10: ex_aluB = EXMEM_aluResult;
            default: ex_aluB = IDEX_regB;
        endcase
    end

    // ---- ALU ----
    always_comb begin
        ex_aluResult = 32'b0;
        case (IDEX_opcode)
            6'b000000: ex_aluResult = ex_aluA + ex_aluB;  // ADD
            6'b000001: ex_aluResult = ex_aluA - ex_aluB;  // SUB
            6'b000010: ex_aluResult = ex_aluA & ex_aluB;  // AND
            6'b000011: ex_aluResult = ex_aluA | ex_aluB;  // OR
            6'b000100: ex_aluResult = ex_aluA + ex_aluB;  // LW  (addr calc)
            6'b000101: ex_aluResult = ex_aluA + ex_aluB;  // SW  (addr calc)
            6'b000110: ex_aluResult = ex_aluA - ex_aluB;  // BEQ (compare)
            6'b000111: ex_aluResult = ex_aluA + ex_aluB;  // ADDI
            default:   ex_aluResult = 32'b0;
        endcase
        ex_zero = (ex_aluResult == 32'b0);
    end

    // EX/MEM Pipeline Register Update
    always_ff @(posedge clk) begin
        if (rst) begin
            EXMEM_aluResult <= 0; EXMEM_regB <= 0; EXMEM_rd <= 0;
            EXMEM_regWrite  <= 0; EXMEM_memRead <= 0;
            EXMEM_memWrite  <= 0; EXMEM_memToReg <= 0;
            EXMEM_zero <= 0; EXMEM_branch <= 0; EXMEM_branchTarget <= 0;
        end else begin
            EXMEM_aluResult    <= ex_aluResult;
            EXMEM_regB         <= IDEX_regB;
            EXMEM_rd           <= IDEX_opcode[5:2]==4'b0001 ? IDEX_rt : IDEX_rd; // LW writes to RT
            EXMEM_regWrite     <= IDEX_regWrite;
            EXMEM_memRead      <= IDEX_memRead;
            EXMEM_memWrite     <= IDEX_memWrite;
            EXMEM_memToReg     <= IDEX_memToReg;
            EXMEM_zero         <= ex_zero;
            EXMEM_branch       <= IDEX_branch;
            EXMEM_branchTarget <= IDEX_pc + (IDEX_imm << 2);
        end
    end

    // ============================================================
    // STAGE 4: MEM — Memory Access
    // Reads from or writes to data memory
    // ============================================================
    logic [31:0] mem_readData;
    assign mem_readData = EXMEM_memRead ? data_mem[EXMEM_aluResult[9:2]] : 32'b0;

    always_ff @(posedge clk) begin
        if (EXMEM_memWrite)
            data_mem[EXMEM_aluResult[9:2]] <= EXMEM_regB;
    end

    // MEM/WB Pipeline Register Update
    always_ff @(posedge clk) begin
        if (rst) begin
            MEMWB_readData <= 0; MEMWB_aluResult <= 0;
            MEMWB_rd <= 0; MEMWB_regWrite <= 0; MEMWB_memToReg <= 0;
        end else begin
            MEMWB_readData  <= mem_readData;
            MEMWB_aluResult <= EXMEM_aluResult;
            MEMWB_rd        <= EXMEM_rd;
            MEMWB_regWrite  <= EXMEM_regWrite;
            MEMWB_memToReg  <= EXMEM_memToReg;
        end
    end

    // ============================================================
    // STAGE 5: WB — Write Back
    // Writes result back to register file
    // ============================================================
    logic [31:0] wb_data;
    assign wb_data = MEMWB_memToReg ? MEMWB_readData : MEMWB_aluResult;

    always_ff @(posedge clk) begin
        if (MEMWB_regWrite && MEMWB_rd != 4'b0)
            reg_file[MEMWB_rd] <= wb_data;
    end

    // ============================================================
    // HAZARD DETECTION UNIT
    // Detects load-use hazards and inserts stall (bubble)
    // A stall is needed when: EX stage has LW and destination
    // matches source of the next instruction
    // ============================================================
    always_comb begin
        pc_stall = 1'b0;
        if (IDEX_memRead &&
           ((IDEX_rt == id_rs) || (IDEX_rt == id_rt)))
            pc_stall = 1'b1; // Insert one bubble
    end

    // ============================================================
    // FORWARDING UNIT
    // Detects data hazards and sets forwarding mux selects
    // EX hazard : forward from EX/MEM
    // MEM hazard: forward from MEM/WB
    // ============================================================
    always_comb begin
        // Forward A (for RS)
        if (EXMEM_regWrite && EXMEM_rd != 0 && EXMEM_rd == IDEX_rs)
            forwardA = 2'b10; // Forward from EX/MEM
        else if (MEMWB_regWrite && MEMWB_rd != 0 && MEMWB_rd == IDEX_rs)
            forwardA = 2'b01; // Forward from MEM/WB
        else
            forwardA = 2'b00; // No forwarding

        // Forward B (for RT)
        if (EXMEM_regWrite && EXMEM_rd != 0 && EXMEM_rd == IDEX_rt)
            forwardB = 2'b10;
        else if (MEMWB_regWrite && MEMWB_rd != 0 && MEMWB_rd == IDEX_rt)
            forwardB = 2'b01;
        else
            forwardB = 2'b00;
    end

    // ============================================================
    // INITIALIZE INSTRUCTION MEMORY (simple test program)
    // ADD R1, R0, R0  -> R1 = 0
    // ADDI R1, R1, 5  -> R1 = 5
    // ADDI R2, R0, 3  -> R2 = 3
    // ADD R3, R1, R2  -> R3 = 8
    // SW R3, 0(R0)    -> MEM[0] = 8
    // LW R4, 0(R0)    -> R4 = MEM[0] = 8
    // ============================================================
    initial begin
        // Format: [opcode(6)][rs(4)][rt(4)][rd(4)][imm(14) or unused]
        instr_mem[0] = 32'b000000_0000_0001_0001_00000000000000; // ADD R1,R0,R0
        instr_mem[1] = 32'b000111_0001_0001_0000_000000000000101; // ADDI R1,R1,5
        instr_mem[2] = 32'b000111_0000_0010_0000_000000000000011; // ADDI R2,R0,3
        instr_mem[3] = 32'b000000_0001_0010_0011_00000000000000; // ADD R3,R1,R2
        instr_mem[4] = 32'b000101_0000_0011_0000_000000000000000; // SW R3,0(R0)
        instr_mem[5] = 32'b000100_0000_0100_0000_000000000000000; // LW R4,0(R0)
        // Fill remaining with NOP
        for (int i = 6; i < 256; i++) instr_mem[i] = 32'b0;
        // Initialize data memory and registers to 0
        for (int i = 0; i < 256; i++) data_mem[i] = 32'b0;
        for (int i = 0; i < 16;  i++) reg_file[i] = 32'b0;
    end

endmodule
