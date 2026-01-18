// ============================================================
// Write Back MUX
// Selects data to be written to register
// ============================================================
module WB_Mux (
    input [1:0] MemToReg,       // Selection signal
    input [15:0] ALU_Result,    // ALU result
    input [15:0] Read_Data,     // Data read from memory
    input [15:0] PC_Adder,      // PC + 1 (for JAL)
    output reg [15:0] WriteData // Data to be written to register
);

    // MemToReg selection codes:
    // 00 = ALU result (R-type, ADDI, ANDI, SLT etc.)
    // 01 = Data read from memory (LW)
    // 10 = PC + 1 (JAL - return address)

    always @(*) begin
        case (MemToReg)
            2'b00:   WriteData = ALU_Result;
            2'b01:   WriteData = Read_Data;
            2'b10:   WriteData = PC_Adder;
            default: WriteData = ALU_Result;
        endcase
    end

endmodule
