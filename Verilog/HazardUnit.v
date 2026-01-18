// ============================================================
// Hazard Unit
// Load-Use Hazard and Branch Hazard detection
// Forwarding decisions for ID Stage
// ============================================================
module HazardUnit (
    input ID_EX_MemRead,          // Is there a LW in EX?
    input [2:0] ID_EX_Rt,         // Rt in EX (LW destination)
    input [2:0] IF_ID_Rs,         // Rs address in ID
    input [2:0] IF_ID_Rt,         // Rt address in ID
    input [3:0] Opcode_In,        // Opcode in ID (for branch detection)
    input [2:0] ID_EX_WriteReg,   // Destination register in EX
    input ID_EX_RegWrite,         // Will EX write?
    input [2:0] EX_MEM_WriteReg,  // Destination register in MEM
    input EX_MEM_RegWrite,        // Will MEM write?
    input EX_MEM_MemRead,         // Is there a LW in MEM?
    input [2:0] WB_WriteReg,      // Destination register in WB
    input WB_RegWrite,            // Will WB write?
    output Stall,                 // Pipeline stall signal
    output Mux_Stall,             // Reset control signals
    output FW_A_ID,               // Forwarding for Rs in ID Stage
    output FW_B_ID                // Forwarding for Rt in ID Stage
);

    // =========================================================
    // OpCode Definitions (for Branch/Jump detection)
    // =========================================================
    localparam OP_BEQ = 4'b0110;
    localparam OP_BNQ = 4'b0111;
    
    wire is_branch = (Opcode_In == OP_BEQ) || (Opcode_In == OP_BNQ);

    // =========================================================
    // 1. LOAD-USE HAZARD DETECTION (for ALU instructions)
    // =========================================================
    wire load_use_rs = (ID_EX_Rt == IF_ID_Rs) && (ID_EX_Rt != 3'b000);
    wire load_use_rt = (ID_EX_Rt == IF_ID_Rt) && (ID_EX_Rt != 3'b000);
    wire load_use_hazard = ID_EX_MemRead && (load_use_rs || load_use_rt);
    
    // =========================================================
    // 2. BRANCH + LOAD HAZARD (for Branch instructions)
    // =========================================================
    // Branch in ID and LW hasn't produced data yet, stall
    // LW in EX: load_use_hazard already catches this
    // LW in MEM: additional stall needed (for WB forwarding)
    
    wire branch_lw_mem_rs = is_branch && EX_MEM_MemRead && 
                            (EX_MEM_WriteReg == IF_ID_Rs) && 
                            (EX_MEM_WriteReg != 3'b000);
                            
    wire branch_lw_mem_rt = is_branch && EX_MEM_MemRead && 
                            (EX_MEM_WriteReg == IF_ID_Rt) && 
                            (EX_MEM_WriteReg != 3'b000);
    
    wire branch_lw_hazard = branch_lw_mem_rs || branch_lw_mem_rt;
    
    // =========================================================
    // 3. STALL OUTPUT
    // =========================================================
    assign Stall = load_use_hazard || branch_lw_hazard;
    assign Mux_Stall = Stall;

    // =========================================================
    // 4. ID STAGE FORWARDING (for Branch comparison)
    // =========================================================
    // Forwarding from EX/MEM or WB to ID stage
    // Early forwarding needed since branch decisions are made in ID
    
    // --- FW_A_ID: Forwarding for Rs ---
    // Forward from EX_MEM to Rs
    wire fwd_a_from_ex_mem = EX_MEM_RegWrite && 
                              (EX_MEM_WriteReg == IF_ID_Rs) && 
                              (EX_MEM_WriteReg != 3'b000);
    
    // Forward from WB to Rs (if not from EX_MEM)
    wire fwd_a_from_wb = WB_RegWrite && 
                         (WB_WriteReg == IF_ID_Rs) && 
                         (WB_WriteReg != 3'b000) &&
                         !fwd_a_from_ex_mem;
    
    assign FW_A_ID = fwd_a_from_ex_mem || fwd_a_from_wb;
    
    // --- FW_B_ID: Forwarding for Rt ---
    // Forward from EX_MEM to Rt
    wire fwd_b_from_ex_mem = EX_MEM_RegWrite && 
                              (EX_MEM_WriteReg == IF_ID_Rt) && 
                              (EX_MEM_WriteReg != 3'b000);
    
    // Forward from WB to Rt (if not from EX_MEM)
    wire fwd_b_from_wb = WB_RegWrite && 
                         (WB_WriteReg == IF_ID_Rt) && 
                         (WB_WriteReg != 3'b000) &&
                         !fwd_b_from_ex_mem;
    
    assign FW_B_ID = fwd_b_from_ex_mem || fwd_b_from_wb;

endmodule
