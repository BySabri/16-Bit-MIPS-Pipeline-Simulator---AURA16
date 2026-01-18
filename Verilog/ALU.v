// ============================================================
// 16-bit ALU (Arithmetic Logic Unit)
// Supported operations: ADD, SUB, AND, OR, SLT
// ============================================================
module ALU (
    input [15:0] inputA,       // First operand
    input [15:0] inputB,       // Second operand
    input [2:0] alu_control,   // Operation select
    output [15:0] Result       // Result
);

    // --- ALU Operation Codes ---
    localparam ALU_ADD = 3'b000;  // Addition
    localparam ALU_SUB = 3'b001;  // Subtraction
    localparam ALU_AND = 3'b010;  // AND
    localparam ALU_OR  = 3'b011;  // OR
    localparam ALU_SLT = 3'b100;  // Set Less Than

    // --- Intermediate Signals ---
    wire [15:0] add_result;
    wire [15:0] sub_result;
    wire [15:0] and_result;
    wire [15:0] or_result;
    wire [15:0] slt_result;


    // --- Basic Operations ---
    // Addition (with carry)
    assign add_result = inputA + inputB;
    
    // Subtraction (with borrow)
    assign sub_result = inputA - inputB;
    
    // AND operation
    assign and_result = inputA & inputB;
    
    // OR operation
    assign or_result = inputA | inputB;
    
    // SLT: If A < B then 1, else 0
    // Signed comparison using MSBs
    wire signed [15:0] signed_A = inputA;
    wire signed [15:0] signed_B = inputB;
    assign slt_result = (signed_A < signed_B) ? 16'h0001 : 16'h0000;

    // --- MUX: Operation Selection (using assign) ---
    assign Result = (alu_control == ALU_ADD) ? add_result :
                    (alu_control == ALU_SUB) ? sub_result :
                    (alu_control == ALU_AND) ? and_result :
                    (alu_control == ALU_OR)  ? or_result  :
                    (alu_control == ALU_SLT) ? slt_result :
                    16'h0000;  // default

endmodule
