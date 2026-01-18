module RegisterFile (
    input clk,                    // Clock signal
    input reg_write,              // Write enable (1 = write)
    input [2:0] read_reg1,        // 1st read address (3-bit = 8 registers)
    input [2:0] read_reg2,        // 2nd read address
    input [2:0] write_reg,        // Write register address
    input [15:0] write_data,      // Data to write (16-bit)
    output [15:0] ReadData1,      // 1st read output
    output [15:0] ReadData2       // 2nd read output
);

    // --- 8 x 16-bit Registers ---
    // $r0 always returns 0 (MIPS convention)
    reg [15:0] registers [0:7];
    
    integer i;

    // --- Initial Values ---
    initial begin
        for (i = 0; i < 8; i = i + 1) begin
            registers[i] = 16'h0000;
        end
    end

    // --- Write Operation (Synchronous - on rising edge of clock) ---
    always @(posedge clk) begin
        // Writing to $r0 is prohibited (in MIPS $zero is always 0)
        if (reg_write && write_reg != 3'b000) begin
            registers[write_reg] <= write_data;
        end
    end

    // --- Read Operation (Asynchronous - Combinational) ---
    // Decoder + MUX logic: Select correct register based on address
    assign ReadData1 = (read_reg1 == 3'b000) ? 16'h0000 : registers[read_reg1];
    assign ReadData2 = (read_reg2 == 3'b000) ? 16'h0000 : registers[read_reg2];

endmodule
