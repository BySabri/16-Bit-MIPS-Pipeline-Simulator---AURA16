// ============================================================
// 16-bit MIPS 5-Stage Pipeline Processor
// Top-Level Module
// ============================================================
// Stages: IF → ID → EX → MEM → WB
// Hazards: Resolved with Forwarding + Stalling
// ============================================================
module MIPS_Pipeline (
    input clk,
    input reset
);

    // =========================================================
    // GLOBAL CONTROL SIGNALS
    // =========================================================
    wire Stall;                    // Pipeline stall
    wire Mux_Stall;                // Control MUX stall
    wire PCSrc;                    // Branch taken
    wire Jump;                     // Jump instruction
    wire JR;                       // Jump Register
    wire Flush;                    // Pipeline flush (branch/jump)

    // Flush signal: Clear IF/ID when Branch or Jump is taken
    // JAL should NOT flush ID/EX (must save return address)
    assign Flush = PCSrc | Jump | JR;  // For IF/ID
    // JAL detection: RegDst == 2'b10 means JAL instruction
    wire is_JAL = (ID_RegDst_CU == 2'b10);
    wire ID_EX_Flush = PCSrc | (Jump & ~is_JAL) | JR;  // For ID/EX (except JAL)

    // =========================================================
    //                    IF STAGE
    // =========================================================
    wire [15:0] PC_out;            // Current PC
    wire [15:0] PC_plus1;          // PC + 1
    wire [15:0] Instruction_IF;    // Fetched instruction
    wire [15:0] Branch_Target;     // Branch target address
    wire [15:0] RD1_for_JR;        // Register value for JR

    // Calculate PC + 1
    assign PC_plus1 = PC_out + 16'd1;

    // Branch target: PC+1 + sign_extended_offset
    assign Branch_Target = IF_ID_PC_Adder + ID_Extended_IR;

    // Program Counter
    // JUMP target should be taken from instruction in ID (IF_ID_Instruction)
    wire [15:0] Jump_Target = {IF_ID_PC_Adder[15:12], IF_ID_Instruction[11:0]};
    
    ProgramCounter PC_unit (
        .clk(clk),
        .reset(reset),
        .stall(Stall),
        .next_pc(
            JR ? RD1_for_JR :
            Jump ? Jump_Target :
            PCSrc ? Branch_Target :
            PC_plus1
        ),
        .pc_out(PC_out)
    );

    // Instruction Memory
    reg [15:0] InstrMem [0:511];
    assign Instruction_IF = InstrMem[PC_out[8:0]];

    // Load test program
    integer i;
    initial begin
        // First clear all memory
        for (i = 0; i < 512; i = i + 1) begin
            InstrMem[i] = 16'h0000;
        end
        
        // =====================================================
        // COMPREHENSIVE TEST PROGRAM
        // All instructions and hazard scenarios
        // =====================================================
        
        // --- SECTION 1: Basic I-type and SW/LW ---
        InstrMem[0]  = 16'h3045;  // ADDI $r1, $r0, 5    → $r1 = 5
        InstrMem[1]  = 16'h3089;  // ADDI $r2, $r0, 9    → $r2 = 9
        InstrMem[2]  = 16'h2044;  // SW   $r1, 4($r0)    → RAM[4] = 5
        InstrMem[3]  = 16'h20C5;  // SW   $r2, 5($r1)    → RAM[5+5=10] = WRONG! RAM[5] = 9 (should be rs=$r0, actually 5+5=10)
        
        // --- SECTION 2: R-type instructions (forwarding test) ---
        // Format: OpCode(4) Rs(3) Rt(3) Rd(3) Funct(3)
        // ADD: funct=000, SUB: funct=001, AND: funct=010, OR: funct=011
        InstrMem[4]  = 16'h0298;  // ADD  $r3, $r1, $r2  → Rs=001 Rt=010 Rd=011 Func=000 → $r3 = 5+9 = 14
        InstrMem[5]  = 16'h0461;  // SUB  $r4, $r2, $r1  → Rs=010 Rt=001 Rd=100 Func=001 → $r4 = 9-5 = 4
        InstrMem[6]  = 16'h02AA;  // AND  $r5, $r1, $r2  → Rs=001 Rt=010 Rd=101 Func=010 → $r5 = 5&9 = 1
        InstrMem[7]  = 16'h02B3;  // OR   $r6, $r1, $r2  → Rs=001 Rt=010 Rd=110 Func=011 → $r6 = 5|9 = 13
        
        // --- SECTION 3: LW followed by use (stall test) ---
        InstrMem[8]  = 16'h1084;  // LW   $r2, 4($r0)    → $r2 = RAM[4] = 5
        InstrMem[9]  = 16'h0298;  // ADD  $r3, $r1, $r2  → $r3 = 5+5 = 10 (stall needed!)
        
        // --- SECTION 4: BEQ test (forwarding + branch) ---
        InstrMem[10] = 16'h6282;  // BEQ  $r1, $r2, 2    → If equal, PC+1+2 = 13
        InstrMem[11] = 16'h30C9;  // ADDI $r3, $r0, 9    → will be skipped
        InstrMem[12] = 16'h30C9;  // ADDI $r3, $r0, 9    → will be skipped
        
        // --- SECTION 5: BNQ test ---
        InstrMem[13] = 16'h70C2;  // BNQ  $r3, $r0, 2    → If not equal, PC+1+2 = 16 ($r3=10, $r0=0, not equal!)
        InstrMem[14] = 16'h30C1;  // ADDI $r3, $r0, 1    → will be skipped
        InstrMem[15] = 16'h30C1;  // ADDI $r3, $r0, 1    → will be skipped
        
        // --- SECTION 6: JUMP test ---
        InstrMem[16] = 16'h9012;  // JUMP 18
        InstrMem[17] = 16'h30C1;  // ADDI $r3, $r0, 1    → will be skipped
        
        // --- SECTION 7: JAL test ---
        InstrMem[18] = 16'hA01A;  // JAL  26             → $r7 = 19 (return addr)
        InstrMem[19] = 16'h30C1;  // ADDI $r3, $r0, 1    → will be skipped
        
        // --- SECTION 8: JR test (JAL target) ---
        // JAL @ 18 → target 26, $r7 = 19
        // JR $r7 = will return to 19
        InstrMem[26] = 16'h0000;  // NOP - let $r7 be written
        InstrMem[27] = 16'h0000;  // NOP - let $r7 reach WB
        InstrMem[28] = 16'h0E05;  // JR   $r7           → PC = $r7 = 19
        InstrMem[29] = 16'h0000;  // NOP
        
        // JR return target (PC=19):
        InstrMem[19] = 16'h3141;  // ADDI $r5, $r0, 1    → $r5 = 1 (overwrite)
        InstrMem[20] = 16'h0000;  // NOP - end of program
    end

    // =========================================================
    //                 IF/ID PIPELINE REGISTER
    // =========================================================
    wire [15:0] IF_ID_PC_Adder;
    wire [15:0] IF_ID_Instruction;

    IF_ID_Register IF_ID_reg (
        .clk(clk),
        .Enable(~Stall),           // Freeze if stall
        .CLR(Flush | reset),       // Clear if Branch/Jump
        .PC_Adder_In(PC_plus1),
        .IR_In(Instruction_IF),
        .PC_Adder_Out(IF_ID_PC_Adder),
        .IR_Out(IF_ID_Instruction)
    );

    // =========================================================
    //                    ID STAGE
    // =========================================================
    // Instruction Decode
    wire [3:0] ID_OpCode   = IF_ID_Instruction[15:12];
    wire [2:0] ID_Rs       = IF_ID_Instruction[11:9];
    wire [2:0] ID_Rt       = IF_ID_Instruction[8:6];
    wire [2:0] ID_Rd       = IF_ID_Instruction[5:3];
    wire [2:0] ID_Funct    = IF_ID_Instruction[2:0];
    wire [5:0] ID_Imm      = IF_ID_Instruction[5:0];

    // Control Unit Outputs
    wire ID_reg_write_CU, ID_ALUSrc_CU;
    wire [1:0] ID_RegDst_CU, ID_MemToReg_CU;
    wire ID_MemWrite_CU, ID_MemRead_CU;
    wire ID_branch_CU, ID_BNQ_CU, ID_jump_CU, ID_JR_CU;
    wire [2:0] ID_alu_control_CU;

    ControlUnit ctrl_unit (
        .OpCode(ID_OpCode),
        .funct(ID_Funct),
        .reg_write(ID_reg_write_CU),
        .alu_control(ID_alu_control_CU),
        .ALUSrc(ID_ALUSrc_CU),
        .RegDst(ID_RegDst_CU),
        .MemWrite(ID_MemWrite_CU),
        .MemRead(ID_MemRead_CU),
        .MemToReg(ID_MemToReg_CU),
        .branch(ID_branch_CU),
        .Branch_Not_Equal(ID_BNQ_CU),
        .jump(ID_jump_CU),
        .JR(ID_JR_CU)
    );

    assign Jump = ID_jump_CU;
    assign JR = ID_JR_CU;

    // Stall MUX - Reset control signals if stall
    wire ID_reg_write, ID_ALUSrc;
    wire [1:0] ID_RegDst, ID_MemToReg;
    wire ID_MemWrite, ID_MemRead;
    wire ID_branch, ID_jump_out;
    wire [2:0] ID_alu_control;

    StallMux stall_mux (
        .stall(Mux_Stall),
        .reg_write_in(ID_reg_write_CU),
        .alu_control_in(ID_alu_control_CU),
        .ALUSrc_in(ID_ALUSrc_CU),
        .RegDst_in(ID_RegDst_CU),
        .MemWrite_in(ID_MemWrite_CU),
        .MemRead_in(ID_MemRead_CU),
        .MemToReg_in(ID_MemToReg_CU),
        .branch_in(ID_branch_CU),
        .jump_in(ID_jump_CU),
        .reg_write_out(ID_reg_write),
        .alu_control_out(ID_alu_control),
        .ALUSrc_out(ID_ALUSrc),
        .RegDst_out(ID_RegDst),
        .MemWrite_out(ID_MemWrite),
        .MemRead_out(ID_MemRead),
        .MemToReg_out(ID_MemToReg),
        .branch_out(ID_branch),
        .jump_out(ID_jump_out)
    );

    // Register File
    wire [15:0] ID_ReadData1, ID_ReadData2;
    wire [15:0] WB_WriteData;
    wire [2:0] WB_WriteReg;
    wire WB_RegWrite;

    RegisterFile reg_file (
        .clk(clk),
        .reg_write(WB_RegWrite),
        .read_reg1(ID_Rs),
        .read_reg2(ID_Rt),
        .write_reg(WB_WriteReg),
        .write_data(WB_WriteData),
        .ReadData1(ID_ReadData1),
        .ReadData2(ID_ReadData2)
    );

    // Sign Extend
    wire [15:0] ID_Extended_IR;
    SignExtend sign_ext (
        .immediate(ID_Imm),
        .extended(ID_Extended_IR)
    );

    // ID Stage Forwarding Control
    wire [1:0] MuxA_Slct, MuxB_Slct;
    ID_ForwardingControl id_fwd_ctrl (
        .IF_ID_Rs(ID_Rs),
        .ID_EX_Rd(ID_EX_WriteReg),
        .ID_EX_RegWrite(ID_EX_RegWrite),
        .EX_MEM_Rd(EX_MEM_WriteReg),
        .EX_MEM_RegWrite(EX_MEM_RegWrite),
        .WB_Rd(WB_WriteReg),
        .WB_RegWrite(WB_RegWrite),
        .IF_ID_Rt(ID_Rt),
        .MuxA_Slct(MuxA_Slct),
        .MuxB_Slct(MuxB_Slct)
    );

    // ID Stage Forwarding MUX
    wire [15:0] ID_RD1_fwd, ID_RD2_fwd;
    ID_ForwardingMux id_fwd_mux (
        .ReadData1(ID_ReadData1),
        .ReadData2(ID_ReadData2),
        .ALU_Result(ALU_Result),
        .EX_MEM_Result(EX_MEM_ALUResult),
        .WB_Data(WB_WriteData),
        .MuxA_Slct(MuxA_Slct),
        .MuxB_Slct(MuxB_Slct),
        .RD1_out(ID_RD1_fwd),
        .RD2_out(ID_RD2_fwd)
    );

    assign RD1_for_JR = ID_RD1_fwd;

    // Branch Comparator
    wire ID_equal;
    Comparator branch_cmp (
        .RD1(ID_RD1_fwd),
        .RD2(ID_RD2_fwd),
        .equal(ID_equal)
    );

    // Branch Decision
    BranchDecision branch_dec (
        .Branch(ID_branch_CU),
        .Zero(ID_equal),
        .Branch_Not_Equal(ID_BNQ_CU),
        .PCSrc(PCSrc)
    );

    // Hazard Unit
    wire FW_A_ID, FW_B_ID;
    HazardUnit hazard_unit (
        .IF_ID_Rs(ID_Rs),
        .IF_ID_Rt(ID_Rt),
        .Opcode_In(ID_OpCode),
        .ID_EX_Rt(ID_EX_Rt),
        .ID_EX_WriteReg(ID_EX_WriteReg),
        .ID_EX_MemRead(ID_EX_MemRead),
        .ID_EX_RegWrite(ID_EX_RegWrite),
        .EX_MEM_WriteReg(EX_MEM_WriteReg),
        .EX_MEM_RegWrite(EX_MEM_RegWrite),
        .EX_MEM_MemRead(EX_MEM_MemRead),
        .WB_WriteReg(WB_WriteReg),
        .WB_RegWrite(WB_RegWrite),
        .Stall(Stall),
        .Mux_Stall(Mux_Stall),
        .FW_A_ID(FW_A_ID),
        .FW_B_ID(FW_B_ID)
    );

    // =========================================================
    //                 ID/EX PIPELINE REGISTER
    // =========================================================
    wire ID_EX_RegWrite, ID_EX_ALUSrc, ID_EX_MemWrite, ID_EX_MemRead;
    wire [1:0] ID_EX_RegDst, ID_EX_MemToReg;
    wire [2:0] ID_EX_ALUControl;
    wire [15:0] ID_EX_PC_Adder, ID_EX_RD1, ID_EX_RD2;
    wire [2:0] ID_EX_Rs, ID_EX_Rt, ID_EX_Rd;
    wire [2:0] ID_EX_WriteReg;
    wire [15:0] ID_EX_Immediate;

    ID_EX_Register ID_EX_reg (
        .clk(clk),
        .Enable(1'b1),
        .CLR(ID_EX_Flush | reset),
        // Control inputs - now direct 2-bit signals
        .Reg_Write_In(ID_reg_write),
        .ALU_Control_In(ID_alu_control),
        .ALU_Src_In(ID_ALUSrc),
        .Reg_Dst_In(ID_RegDst),
        .Mem_Write_In(ID_MemWrite),
        .Mem_Read_In(ID_MemRead),
        .Mem_To_Reg_In(ID_MemToReg),
        // Data inputs
        .PC_Adder_In(IF_ID_PC_Adder),
        .Reg_Data_1_In(ID_RD1_fwd),
        .Reg_Data_2_In(ID_RD2_fwd),
        .Rs_In(ID_Rs),
        .Rt_In(ID_Rt),
        .Rd_In(ID_Rd),
        .Immediate_In(ID_Extended_IR),
        // Control outputs
        .Reg_Write_Out(ID_EX_RegWrite),
        .ALU_Control_Out(ID_EX_ALUControl),
        .ALU_Src_Out(ID_EX_ALUSrc),
        .Reg_Dst_Out(ID_EX_RegDst),
        .Mem_Write_Out(ID_EX_MemWrite),
        .Mem_Read_Out(ID_EX_MemRead),
        .Mem_To_Reg_Out(ID_EX_MemToReg),
        // Data outputs
        .PC_Adder_Out(ID_EX_PC_Adder),
        .Reg_Data_1_Out(ID_EX_RD1),
        .Reg_Data_2_Out(ID_EX_RD2),
        .Rs_Out(ID_EX_Rs),
        .Rt_Out(ID_EX_Rt),
        .Rd_Out(ID_EX_Rd),
        .Immediate_Out(ID_EX_Immediate)
    );

    // Write Register selection (RegDst MUX)
    // For JAL write to $r7, for R-type use Rd, for I-type use Rt
    // Write Register MUX - RegDst encoding:
    // 00 = Rd (R-type), 01 = Rt (I-type), 10 = $r7 (JAL)
    assign ID_EX_WriteReg = ID_EX_RegDst[1] ? 3'b111 :     // JAL -> $r7
                            ID_EX_RegDst[0] ? ID_EX_Rt :   // I-type -> Rt
                            ID_EX_Rd;                       // R-type -> Rd

    // =========================================================
    //                    EX STAGE
    // =========================================================
    // EX Stage Forwarding
    wire [1:0] ForwardA, ForwardB;
    ForwardingUnit fwd_unit (
        .ID_EX_Rs(ID_EX_Rs),
        .ID_EX_Rt(ID_EX_Rt),
        .EX_MEM_write_reg(EX_MEM_WriteReg),
        .EX_MEM_reg_write(EX_MEM_RegWrite),
        .MEM_WB_write_reg(WB_WriteReg),
        .MEM_WB_reg_write(WB_RegWrite),
        .ForwardA(ForwardA),
        .ForwardB(ForwardB)
    );

    // ALU Input A MUX (Forwarding)
    // ForwardA = {EX_Match, MEM_Match} → 10=EX/MEM, 01=WB
    reg [15:0] ALU_InputA;
    always @(*) begin
        case (ForwardA)
            2'b00: ALU_InputA = ID_EX_RD1;
            2'b10: ALU_InputA = EX_MEM_ALUResult;  // EX match
            2'b01: ALU_InputA = WB_WriteData;      // MEM match
            default: ALU_InputA = ID_EX_RD1;
        endcase
    end

    // ALU Input B MUX (Forwarding + ALUSrc)
    // ForwardB = {EX_Match, MEM_Match} → 10=EX/MEM, 01=WB
    reg [15:0] ALU_InputB_fwd;
    always @(*) begin
        case (ForwardB)
            2'b00: ALU_InputB_fwd = ID_EX_RD2;
            2'b10: ALU_InputB_fwd = EX_MEM_ALUResult;  // EX match
            2'b01: ALU_InputB_fwd = WB_WriteData;      // MEM match
            default: ALU_InputB_fwd = ID_EX_RD2;
        endcase
    end
    wire [15:0] ALU_InputB = ID_EX_ALUSrc ? ID_EX_Immediate : ALU_InputB_fwd;

    // ALU
    wire [15:0] ALU_Result;
    ALU alu_unit (
        .inputA(ALU_InputA),
        .inputB(ALU_InputB),
        .alu_control(ID_EX_ALUControl),
        .Result(ALU_Result)
    );

    // =========================================================
    //                 EX/MEM PIPELINE REGISTER
    // =========================================================
    wire EX_MEM_RegWrite, EX_MEM_MemWrite, EX_MEM_MemRead;
    wire [1:0] EX_MEM_MemToReg;
    wire [15:0] EX_MEM_PC_Adder, EX_MEM_ALUResult, EX_MEM_RD2;
    wire [2:0] EX_MEM_WriteReg;

    EX_MEM_Register EX_MEM_reg (
        .clk(clk),
        .Enable(1'b1),
        .CLR(reset),
        // Control inputs
        .Reg_Write_In(ID_EX_RegWrite),
        .Mem_Write_In(ID_EX_MemWrite),
        .Mem_Read_In(ID_EX_MemRead),
        .Mem_To_Reg_In(ID_EX_MemToReg),
        // Data inputs
        .PC_Adder_In(ID_EX_PC_Adder),
        .ALU_Result_In(ALU_Result),
        .Read_Data2_In(ALU_InputB_fwd),  // Data for SW
        .Write_Reg_In(ID_EX_WriteReg),
        // Control outputs
        .Reg_Write_Out(EX_MEM_RegWrite),
        .Mem_Write_Out(EX_MEM_MemWrite),
        .Mem_Read_Out(EX_MEM_MemRead),
        .Mem_To_Reg_Out(EX_MEM_MemToReg),
        // Data outputs
        .PC_Adder_Out(EX_MEM_PC_Adder),
        .ALU_Result_Out(EX_MEM_ALUResult),
        .Read_Data2_Out(EX_MEM_RD2),
        .Write_Reg_Out(EX_MEM_WriteReg)
    );

    // =========================================================
    //                    MEM STAGE
    // =========================================================
    wire [15:0] MEM_ReadData;

    DataMemory data_mem (
        .clk(clk),
        .address(EX_MEM_ALUResult),
        .write_data(EX_MEM_RD2),
        .MemWrite(EX_MEM_MemWrite),
        .MemRead(EX_MEM_MemRead),
        .read_data(MEM_ReadData)
    );

    // =========================================================
    //                 MEM/WB PIPELINE REGISTER
    // =========================================================
    wire MEM_WB_RegWrite;
    wire [1:0] MEM_WB_MemToReg;
    wire [15:0] MEM_WB_PC_Adder, MEM_WB_ALUResult, MEM_WB_ReadData;
    wire [2:0] MEM_WB_WriteReg;

    MEM_WB_Register MEM_WB_reg (
        .clk(clk),
        .Enable(1'b1),
        // Control inputs
        .Reg_Write_In(EX_MEM_RegWrite),
        .Mem_To_Reg_In(EX_MEM_MemToReg),
        // Data inputs
        .PC_Adder_In(EX_MEM_PC_Adder),
        .ALU_Result_In(EX_MEM_ALUResult),
        .Read_Data_In(MEM_ReadData),
        .Write_Reg_In(EX_MEM_WriteReg),
        // Control outputs
        .Reg_Write_Out(MEM_WB_RegWrite),
        .Mem_To_Reg_Out(MEM_WB_MemToReg),
        // Data outputs
        .PC_Adder_Out(MEM_WB_PC_Adder),
        .ALU_Result_Out(MEM_WB_ALUResult),
        .Read_Data_Out(MEM_WB_ReadData),
        .Write_Reg_Out(MEM_WB_WriteReg)
    );

    // =========================================================
    //                    WB STAGE
    // =========================================================
    assign WB_RegWrite = MEM_WB_RegWrite;
    assign WB_WriteReg = MEM_WB_WriteReg;

    // Write Back MUX
    WB_Mux wb_mux (
        .MemToReg(MEM_WB_MemToReg),
        .ALU_Result(MEM_WB_ALUResult),
        .Read_Data(MEM_WB_ReadData),
        .PC_Adder(MEM_WB_PC_Adder),
        .WriteData(WB_WriteData)
    );

endmodule
