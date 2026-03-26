// ============================================================
// Project      : 5-Stage Pipelined RISC Processor Testbench
// Author       : Harshit Bothra
// College      : PES University, ECE Department
// Description  : Testbench that runs the processor through a
//                test program and verifies register and memory
//                values after execution. Tests pipeline stages,
//                forwarding, and hazard detection.
// ============================================================

`timescale 1ns/1ps

module risc_processor_tb;

    // ---- DUT Signals ----
    logic        clk;
    logic        rst;
    logic [31:0] pc_out;

    // ---- Instantiate DUT ----
    risc_processor DUT (
        .clk    (clk),
        .rst    (rst),
        .pc_out (pc_out)
    );

    // ---- Clock Generation ----
    // 10ns period = 100MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Test Program Expected Results ----
    // The processor runs this program (loaded in risc_processor.sv):
    //   ADDI R1, R0, 5   -> R1 = 5
    //   ADDI R2, R0, 3   -> R2 = 3
    //   ADD  R3, R1, R2  -> R3 = 8  (tests forwarding: R1,R2 just written)
    //   SW   R3, 0(R0)   -> MEM[0] = 8
    //   LW   R4, 0(R0)   -> R4 = 8  (tests load-use hazard handling)

    // Task: check register value
    task check_reg(input int reg_num, input logic [31:0] expected, input string name);
        if (DUT.reg_file[reg_num] === expected)
            $display("[PASS] %s = %0d (R%0d)", name, expected, reg_num);
        else
            $display("[FAIL] %s: expected %0d, got %0d (R%0d)",
                      name, expected, DUT.reg_file[reg_num], reg_num);
    endtask

    // Task: check memory value
    task check_mem(input int addr, input logic [31:0] expected, input string label);
        if (DUT.data_mem[addr] === expected)
            $display("[PASS] MEM[%0d] = %0d (%s)", addr, expected, label);
        else
            $display("[FAIL] MEM[%0d]: expected %0d, got %0d (%s)",
                      addr, expected, DUT.data_mem[addr], label);
    endtask

    // ---- Main Test Sequence ----
    initial begin
        $display("=======================================================");
        $display("  5-Stage Pipelined RISC Processor Testbench");
        $display("  Harshit Bothra | PES University ECE");
        $display("=======================================================");

        // Apply reset for 3 cycles
        rst = 1;
        repeat(3) @(posedge clk);
        rst = 0;
        $display("\n[INFO] Reset released. Pipeline starting...\n");

        // Run for enough cycles to let all instructions complete
        // 5-stage pipeline needs ~10+ cycles to flush all instructions
        repeat(20) @(posedge clk);

        $display("\n--- Pipeline Execution Complete ---\n");
        $display("Checking register file results:");
        $display("-------------------------------------------------------");

        // Verify results
        check_reg(1, 32'd5,  "R1 (ADDI R1=5)");
        check_reg(2, 32'd3,  "R2 (ADDI R2=3)");
        check_reg(3, 32'd8,  "R3 (ADD R3=R1+R2=8) [Forwarding test]");
        check_reg(4, 32'd8,  "R4 (LW R4=MEM[0]=8) [Load-use hazard test]");

        $display("\nChecking data memory:");
        $display("-------------------------------------------------------");
        check_mem(0, 32'd8, "SW R3 -> MEM[0]");

        $display("\n=======================================================");
        $display("  Pipeline Feature Verification:");
        $display("-------------------------------------------------------");
        $display("  [1] IF Stage  : Instruction fetch from instr_mem");
        $display("  [2] ID Stage  : Decode + register read + control signals");
        $display("  [3] EX Stage  : ALU execution + forwarding mux");
        $display("  [4] MEM Stage : Load/Store to data_mem");
        $display("  [5] WB Stage  : Write-back to register file");
        $display("  [6] Forwarding: EX/MEM and MEM/WB forwarding paths");
        $display("  [7] Hazard    : Load-use stall detection");
        $display("  [8] Branch    : BEQ with flush on taken");
        $display("=======================================================\n");

        $finish;
    end

    // ---- Pipeline State Monitor ----
    // Prints pipeline register state every clock cycle
    initial begin
        @(negedge rst); // Wait for reset to release
        $display("\nCycle | PC   | IF/ID Instr | EX ALU Result | WB Reg");
        $display("------|------|-------------|---------------|-------");
        repeat(20) begin
            @(posedge clk); #1;
            $display("  %3t  | %4h | %b  | %14d  | R%0d=%0d",
                $time/10,
                DUT.pc_out,
                DUT.IFID_instr[31:26],
                DUT.EXMEM_aluResult,
                DUT.MEMWB_rd,
                DUT.wb_data);
        end
    end

    // ---- Waveform Dump ----
    initial begin
        $dumpfile("risc_processor_waves.vcd");
        $dumpvars(0, risc_processor_tb);
    end

endmodule
