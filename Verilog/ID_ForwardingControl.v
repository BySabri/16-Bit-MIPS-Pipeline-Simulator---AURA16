// ============================================================
// ID Forwarding Control
// Forwarding decisions for branch comparison
// Forwarding from ID_EX, EX_MEM and WB stages
// ============================================================
module ID_ForwardingControl (
    input [2:0] IF_ID_Rs,         // Rs address in ID
    input [2:0] ID_EX_Rd,         // ID/EX destination register
    input ID_EX_RegWrite,         // Will ID/EX write?
    input [2:0] EX_MEM_Rd,        // EX/MEM destination register
    input EX_MEM_RegWrite,        // Will EX/MEM write?
    input [2:0] WB_Rd,            // WB destination register
    input WB_RegWrite,            // Will WB write?
    input [2:0] IF_ID_Rt,         // Rt address in ID

    output [1:0] MuxA_Slct,       // For RD1: 00=Reg, 01=ALU, 10=EX_MEM, 11=WB
    output [1:0] MuxB_Slct        // For RD2: 00=Reg, 01=ALU, 10=EX_MEM, 11=WB
);

    // =========================================================
    // ID_EX Match (1 cycle ago - ALU result ready)
    // =========================================================
    wire ID_EX_Rs_match = (ID_EX_Rd == IF_ID_Rs) & (ID_EX_Rd != 3'b000) & ID_EX_RegWrite;
    wire ID_EX_Rt_match = (ID_EX_Rd == IF_ID_Rt) & (ID_EX_Rd != 3'b000) & ID_EX_RegWrite;
    
    // =========================================================
    // EX_MEM Match (2 cycles ago - in pipeline register)
    // =========================================================
    wire EX_MEM_Rs_match = (EX_MEM_Rd == IF_ID_Rs) & (EX_MEM_Rd != 3'b000) & EX_MEM_RegWrite & ~ID_EX_Rs_match;
    wire EX_MEM_Rt_match = (EX_MEM_Rd == IF_ID_Rt) & (EX_MEM_Rd != 3'b000) & EX_MEM_RegWrite & ~ID_EX_Rt_match;
    
    // =========================================================
    // WB Match (3 cycles ago - needed for LW)
    // =========================================================
    wire WB_Rs_match = (WB_Rd == IF_ID_Rs) & (WB_Rd != 3'b000) & WB_RegWrite & ~ID_EX_Rs_match & ~EX_MEM_Rs_match;
    wire WB_Rt_match = (WB_Rd == IF_ID_Rt) & (WB_Rd != 3'b000) & WB_RegWrite & ~ID_EX_Rt_match & ~EX_MEM_Rt_match;

    // =========================================================
    // MuxA_Slct (for Rs) - Priority: ID_EX > EX_MEM > WB
    // =========================================================
    assign MuxA_Slct = ID_EX_Rs_match  ? 2'b01 :   // From ALU
                       EX_MEM_Rs_match ? 2'b10 :   // From EX/MEM
                       WB_Rs_match     ? 2'b11 :   // From WB
                                         2'b00;    // Register File

    // =========================================================
    // MuxB_Slct (for Rt) - Priority: ID_EX > EX_MEM > WB
    // =========================================================
    assign MuxB_Slct = ID_EX_Rt_match  ? 2'b01 :   // From ALU
                       EX_MEM_Rt_match ? 2'b10 :   // From EX/MEM
                       WB_Rt_match     ? 2'b11 :   // From WB
                                         2'b00;    // Register File

endmodule
