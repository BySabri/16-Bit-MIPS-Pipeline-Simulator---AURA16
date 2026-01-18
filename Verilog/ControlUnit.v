module ControlUnit (
    input [3:0] OpCode,       // Instruction[15:12] - 4-bit opcode
    input [2:0] funct,        // Instruction[2:0] - R-type function code
    
    // --- Output Signals ---
    output reg_write,         // Register write enable
    output [2:0] alu_control, // ALU operation select
    output ALUSrc,            // ALU 2nd input: 0=RD2, 1=Immediate
    output [1:0] RegDst,      // Destination register: 00=Rt, 01=Rd, 10=$r7(JAL)
    output MemWrite,          // Memory write
    output MemRead,           // Memory read
    output [1:0] MemToReg,    // Write to register: 00=ALU, 01=Memory, 10=PC+1
    output branch,            // BEQ branch
    output jump,              // Jump instruction
    output Branch_Not_Equal,  // BNQ branch (branch not equal)
    output JR                 // Jump Register
);

    // --- OpCode Definitions ---
    localparam OP_RTYPE = 4'b0000;  // R-type instructions
    localparam OP_LW    = 4'b0001;  // Load Word
    localparam OP_SW    = 4'b0010;  // Store Word
    localparam OP_ADDI  = 4'b0011;  // ADDI
    localparam OP_SUBI  = 4'b0100;  // SUBI
    localparam OP_SLTI  = 4'b0101;  // Set Less Than Immediate
    localparam OP_BEQ   = 4'b0110;  // Branch if Equal
    localparam OP_BNQ   = 4'b0111;  // Branch if Not Equal
    localparam OP_ANDI  = 4'b1000;  // ANDI
    localparam OP_J     = 4'b1001;  // Jump
    localparam OP_JAL   = 4'b1010;  // Jump and Link

    // --- Funct Definition (for JR) ---
    localparam FUNC_JR = 3'b101;

    // =========================================================
    // DECODER LOGIC - OpCode Decode
    // =========================================================
    wire R_type = (OpCode == OP_RTYPE);
    wire LW     = (OpCode == OP_LW);
    wire SW     = (OpCode == OP_SW);
    wire ADDI   = (OpCode == OP_ADDI);
    wire SUBI   = (OpCode == OP_SUBI);
    wire SLTI   = (OpCode == OP_SLTI);
    wire BEQ    = (OpCode == OP_BEQ);
    wire BNQ    = (OpCode == OP_BNQ);
    wire ANDI   = (OpCode == OP_ANDI);
    wire J      = (OpCode == OP_J);
    wire JAL    = (OpCode == OP_JAL);

    // =========================================================
    // CONTROL SIGNALS - Assign with MUX
    // =========================================================
    
    // reg_write: R-type, ADDI, SUBI, ANDI, SLTI, LW, JAL
    assign reg_write = R_type | LW | ADDI | SUBI | SLTI | ANDI | JAL;

    // ALUSrc: 1 for I-type instructions (ADDI, SUBI, ANDI, SLTI, LW, SW)
    assign ALUSrc = LW | SW | ADDI | SUBI | SLTI | ANDI;

    // RegDst: With splitter
    // RegDst[0] = OR gate, RegDst[1] = JAL
    wire RegDst_OR = LW | ADDI | SUBI | SLTI | ANDI;
    assign RegDst = {JAL, RegDst_OR};

    // MemWrite: Only SW
    assign MemWrite = SW;

    // MemRead: Only LW
    assign MemRead = LW;

    // MemToReg: With splitter
    // MemToReg[0] = LW, MemToReg[1] = JAL
    assign MemToReg = {JAL, LW};

    // branch: BEQ
    assign branch = BEQ;

    // jump: J or JAL
    assign jump = J | JAL;

    // Branch_Not_Equal: BNQ decoder output
    assign Branch_Not_Equal = BNQ;
    
    // --- Funct Decode (for R-type) ---
    wire funct_JR = R_type & (funct == FUNC_JR);
    // JR: Jump Register
    assign JR = funct_JR;

    // =========================================================
    // ALU CONTROL - MUX (Logisim schematic)
    // =========================================================
    // I-type encoding: {SLTI, ANDI, SUBI|BEQ|BNQ}
    wire alu_or = SUBI | BEQ | BNQ;  // OR gate
    wire [2:0] itype_alu = {SLTI, ANDI, alu_or};
    
    // MUX: R_type=1 → funct, R_type=0 → itype_alu
    assign alu_control = R_type ? funct : itype_alu;

endmodule
