`timescale 1ns / 1ps

module tb_MIPS_Pipeline;

    reg clk;
    reg reset;

    MIPS_Pipeline uut (
        .clk(clk),
        .reset(reset)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║        16-bit MIPS Pipeline Processor - Complete Test            ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║ Instruction Memory:                                              ║");
        $display("║   [0] 3045 - ADDI $r1, $r0, 5                                    ║");
        $display("║   [1] 3085 - ADDI $r2, $r0, 5                                    ║");
        $display("║   [2] 6282 - BEQ  $r1, $r2, 2                                    ║");
        $display("║   [3] 30C9 - ADDI $r3, $r0, 9                                    ║");
        $display("║   [4] 9004 - JUMP 4                                              ║");
        $display("║   [5] A008 - JAL  8                                              ║");
        $display("║   [6] 9006 - JUMP 6                                              ║");
        $display("║   [7] 3243 - ADDI $r4, $r1, 3                                    ║");
        $display("║   [8] 2044 - SW   $r1, 4($r0)                                    ║");
        $display("║   [9] 0E05 - JR/R-type                                           ║");
        $display("╚══════════════════════════════════════════════════════════════════╝");
        $display("");
        
        #20 reset = 0;
        
        $display("┌──────┬─────┬──────────┬──────────┬───────┬───────┬──────┬──────┐");
        $display("│ Time │ PC  │ IF_Instr │ ID_Instr │ Stall │ PCSrc │ Jump │  JR  │");
        $display("├──────┼─────┼──────────┼──────────┼───────┼───────┼──────┼──────┤");
        
        repeat (30) begin
            #10;
            $display("│ %4t │ %3d │   %h   │   %h   │   %b   │   %b   │  %b   │  %b   │ RD1=%h RD2=%h Branch=%b Equal=%b", 
                     $time, 
                     uut.PC_out,
                     uut.Instruction_IF,
                     uut.IF_ID_Instruction,
                     uut.Stall,
                     uut.PCSrc,
                     uut.Jump,
                     uut.JR,
                     uut.ID_RD1_fwd,
                     uut.ID_RD2_fwd,
                     uut.ID_branch_CU,
                     uut.ID_equal);
        end
        $display("└──────┴─────┴──────────┴──────────┴───────┴───────┴──────┴──────┘");
        
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║                      REGISTER FILE CONTENTS                      ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  $r0 = %h (always 0)                                             ║", uut.reg_file.registers[0]);
        $display("║  $r1 = %h                                                        ║", uut.reg_file.registers[1]);
        $display("║  $r2 = %h                                                        ║", uut.reg_file.registers[2]);
        $display("║  $r3 = %h                                                        ║", uut.reg_file.registers[3]);
        $display("║  $r4 = %h                                                        ║", uut.reg_file.registers[4]);
        $display("║  $r5 = %h                                                        ║", uut.reg_file.registers[5]);
        $display("║  $r6 = %h                                                        ║", uut.reg_file.registers[6]);
        $display("║  $r7 = %h                                                        ║", uut.reg_file.registers[7]);
        $display("╚══════════════════════════════════════════════════════════════════╝");
        
        $display("");
        $display("╔══════════════════════════════════════════════════════════════════╗");
        $display("║                      DATA MEMORY (RAM) CONTENTS                  ║");
        $display("╠══════════════════════════════════════════════════════════════════╣");
        $display("║  RAM[0]  = %h                                                    ║", uut.data_mem.RAM[0]);
        $display("║  RAM[1]  = %h                                                    ║", uut.data_mem.RAM[1]);
        $display("║  RAM[2]  = %h                                                    ║", uut.data_mem.RAM[2]);
        $display("║  RAM[3]  = %h                                                    ║", uut.data_mem.RAM[3]);
        $display("║  RAM[4]  = %h  <-- SW target                                     ║", uut.data_mem.RAM[4]);
        $display("║  RAM[5]  = %h                                                    ║", uut.data_mem.RAM[5]);
        $display("║  RAM[6]  = %h                                                    ║", uut.data_mem.RAM[6]);
        $display("║  RAM[7]  = %h                                                    ║", uut.data_mem.RAM[7]);
        $display("║  RAM[8]  = %h                                                    ║", uut.data_mem.RAM[8]);
        $display("║  RAM[9]  = %h                                                    ║", uut.data_mem.RAM[9]);
        $display("╚══════════════════════════════════════════════════════════════════╝");
        
        $display("");
        $display("════════════════════ TEST COMPLETED! ═══════════════════════════");
        $display("");
        
        $finish;
    end

endmodule
