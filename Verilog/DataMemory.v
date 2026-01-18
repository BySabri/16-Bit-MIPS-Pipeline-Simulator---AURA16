// ============================================================
// Data Memory (RAM 512 x 16)
// Data memory for Load/Store instructions
// ============================================================
module DataMemory (
    input clk,
    input [15:0] address,      // Address from ALU Result
    input [15:0] write_data,   // Data to write (for SW)
    input MemWrite,            // Write enable (SW)
    input MemRead,             // Read enable (LW)
    output [15:0] read_data    // Data read (for LW)
);

    // --- 512 x 16-bit RAM ---
    reg [15:0] RAM [0:511];
    
    integer i;

    // --- Initialization: Clear all memory ---
    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            RAM[i] = 16'h0000;
        end
        // RAM starts completely empty
    end

    // --- Write Operation (Synchronous - on rising edge of clock) ---
    always @(posedge clk) begin
        if (MemWrite) begin
            RAM[address[8:0]] <= write_data;  // 9-bit address (512 rows)
        end
    end

    // --- Read Operation (Asynchronous - Combinational) ---
    // Output data if MemRead is active, else 0
    assign read_data = MemRead ? RAM[address[8:0]] : 16'h0000;

endmodule
