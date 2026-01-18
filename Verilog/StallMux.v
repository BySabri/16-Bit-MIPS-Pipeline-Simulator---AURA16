module StallMux (
    input stall,                // Stall signal (1 = insert NOP)
    
    // Signals from Control Unit
    input reg_write_in,
    input [2:0] alu_control_in,
    input ALUSrc_in,
    input [1:0] RegDst_in,
    input MemWrite_in,
    input MemRead_in,
    input [1:0] MemToReg_in,
    input branch_in,
    input jump_in,
    
    // Output signals after stall
    output reg_write_out,
    output [2:0] alu_control_out,
    output ALUSrc_out,
    output [1:0] RegDst_out,
    output MemWrite_out,
    output MemRead_out,
    output [1:0] MemToReg_out,
    output branch_out,
    output jump_out
);

    // If stall, reset all signals to zero (insert NOP/Bubble)
    assign reg_write_out   = stall ? 1'b0 : reg_write_in;
    assign alu_control_out = stall ? 3'b0 : alu_control_in;
    assign ALUSrc_out      = stall ? 1'b0 : ALUSrc_in;
    assign RegDst_out      = stall ? 2'b0 : RegDst_in;
    assign MemWrite_out    = stall ? 1'b0 : MemWrite_in;
    assign MemRead_out     = stall ? 1'b0 : MemRead_in;
    assign MemToReg_out    = stall ? 2'b0 : MemToReg_in;
    assign branch_out      = stall ? 1'b0 : branch_in;
    assign jump_out        = stall ? 1'b0 : jump_in;

endmodule
