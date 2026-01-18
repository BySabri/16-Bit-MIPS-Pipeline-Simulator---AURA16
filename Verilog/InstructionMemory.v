module InstructionMemory (
    input [15:0] addr,     // Address from PC (Program Counter)
    output reg [15:0] data // Output Instruction
);

    // 512 rows deep, 16-bit wide memory
    reg [15:0] rom [511:0];
    integer i;

    initial begin
        // 1. First clear all memory (Clean up)

        for (i = 0; i < 512; i = i + 1) begin
            rom[i] = 16'h0000;
        end

        // 2. LOADING CODES FROM REFERENCE
        // According to Logisim diagram order:
        rom[0]  = 16'h3045; // ADDI $r1, $r0, 5 (Presumably)
        rom[1]  = 16'h3085; // ADDI $r2, $r0, 5
        rom[2]  = 16'h6281; // BEQ ...
        rom[3]  = 16'h30c9; 
        rom[4]  = 16'h9004; // JUMP 4
        rom[5]  = 16'ha008; // JAL 8
        rom[6]  = 16'h9006; // JUMP 6
        rom[7]  = 16'h0000; // NOP (Empty)
        rom[8]  = 16'h3243; 
        rom[9]  = 16'h0e05; // JR $r5 (or similar)
        rom[10] = 16'h0000;
        rom[11] = 16'h0000;
        
        // Rest is already set to 0 by loop.
    end

    // 3. Read Logic (Async Read)
    // Data outputs as soon as address changes (no clock wait)
    always @(*) begin
        // Since your PC logic increments by +1, we use address directly.
        // Masking to avoid errors if address exceeds 512:
        data = rom[addr[8:0]]; 
    end

endmodule