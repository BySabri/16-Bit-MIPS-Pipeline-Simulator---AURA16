// ============================================================
// Forwarding Unit (Data Hazard Resolution)
// Makes forwarding decisions from EX and MEM stages
// ============================================================
module ForwardingUnit (
    // --- Register Addresses from ID/EX ---
    input [2:0] ID_EX_Rs,          // Rs in EX stage
    input [2:0] ID_EX_Rt,          // Rt in EX stage
    
    // --- From EX/MEM (Previous instruction) ---
    input [2:0] EX_MEM_write_reg,  // EX/MEM destination register
    input EX_MEM_reg_write,        // EX/MEM write enable
    
    // --- From MEM/WB (Two instructions ago) ---
    input [2:0] MEM_WB_write_reg,  // MEM/WB destination register
    input MEM_WB_reg_write,        // MEM/WB write enable
    
    // --- Forwarding Decisions ---
    output [1:0] ForwardA,         // For inputA: 00=Normal, 01=EX/MEM, 10=MEM/WB
    output [1:0] ForwardB          // For inputB: 00=Normal, 01=EX/MEM, 10=MEM/WB
);

    // --- Match Signals ---
    // EX Hazard: Is previous instruction writing to this register?
    wire EX_Match_A = (EX_MEM_reg_write) && 
                      (EX_MEM_write_reg != 3'b000) && 
                      (EX_MEM_write_reg == ID_EX_Rs);
                      
    wire EX_Match_B = (EX_MEM_reg_write) && 
                      (EX_MEM_write_reg != 3'b000) && 
                      (EX_MEM_write_reg == ID_EX_Rt);

    // MEM Hazard: Is instruction from two cycles ago writing to this register?
    // (And no EX Hazard - EX has priority)
    wire MEM_Match_A = (MEM_WB_reg_write) && 
                       (MEM_WB_write_reg != 3'b000) && 
                       (MEM_WB_write_reg == ID_EX_Rs) &&
                       ~EX_Match_A;  // No EX hazard
                       
    wire MEM_Match_B = (MEM_WB_reg_write) && 
                       (MEM_WB_write_reg != 3'b000) && 
                       (MEM_WB_write_reg == ID_EX_Rt) &&
                       ~EX_Match_B;  // No EX hazard

    // --- ForwardA/B: With splitter ---
    // [1] = EX_Match (10), [0] = MEM_Match (01)
    assign ForwardA = {EX_Match_A, MEM_Match_A};
    assign ForwardB = {EX_Match_B, MEM_Match_B};

endmodule
