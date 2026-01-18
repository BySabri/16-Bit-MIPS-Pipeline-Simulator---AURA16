// ============================================================
// IF/ID Pipeline Register
// Data transfer from IF stage to ID stage
// ============================================================
module IF_ID_Register (
    input clk,
    input Enable,             // 0 = Stall (freeze), 1 = Normal
    input CLR,                // 1 = Flush (clear) - for Branch/Jump
    
    // --- Inputs (from IF Stage) ---
    input [15:0] PC_Adder_In, // PC + 1 value
    input [15:0] IR_In,       // Instruction
    
    // --- Outputs (to ID Stage) ---
    output reg [15:0] PC_Adder_Out,
    output reg [15:0] IR_Out
);

    // Initial values
    initial begin
        PC_Adder_Out = 16'h0000;
        IR_Out = 16'h0000;  // NOP
    end

    always @(posedge clk) begin
        if (CLR) begin
            // Flush: Insert NOP (clear pipeline when Branch/Jump taken)
            PC_Adder_Out <= 16'h0000;
            IR_Out <= 16'h0000;
        end
        else if (Enable) begin
            // Normal operation: Transfer data
            PC_Adder_Out <= PC_Adder_In;
            IR_Out <= IR_In;
        end
        // If Enable = 0, value is preserved (Stall)
    end

endmodule
