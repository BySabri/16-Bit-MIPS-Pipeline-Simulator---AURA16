// ============================================================
// ID Stage Forwarding MUX
// Forwarding for branch comparison
// Forward support from ALU_Result, EX_MEM_Result and WB_Data
// ============================================================
module ID_ForwardingMux (
    input [15:0] ReadData1,       // Rs value (from Register File)
    input [15:0] ReadData2,       // Rt value (from Register File)
    input [15:0] ALU_Result,      // EX stage ALU result
    input [15:0] EX_MEM_Result,   // ALU result from EX/MEM
    input [15:0] WB_Data,         // Data from MEM/WB (for LW)
    input [1:0] MuxA_Slct,        // For RD1: 00=Reg, 01=ALU, 10=EX_MEM, 11=WB
    input [1:0] MuxB_Slct,        // For RD2: 00=Reg, 01=ALU, 10=EX_MEM, 11=WB
    output reg [15:0] RD1_out,    // Forwarded RD1
    output reg [15:0] RD2_out     // Forwarded RD2
);

    // MUXA: For RD1
    always @(*) begin
        case (MuxA_Slct)
            2'b01:   RD1_out = ALU_Result;     // Forward from EX stage
            2'b10:   RD1_out = EX_MEM_Result;  // Forward from EX/MEM
            2'b11:   RD1_out = WB_Data;        // Forward from WB (for LW)
            default: RD1_out = ReadData1;      // Normal read
        endcase
    end
    
    // MUXB: For RD2
    always @(*) begin
        case (MuxB_Slct)
            2'b01:   RD2_out = ALU_Result;     // Forward from EX stage
            2'b10:   RD2_out = EX_MEM_Result;  // Forward from EX/MEM
            2'b11:   RD2_out = WB_Data;        // Forward from WB (for LW)
            default: RD2_out = ReadData2;      // Normal read
        endcase
    end

endmodule
