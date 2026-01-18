module ProgramCounter (
    input clk,
    input reset,             // To reset the system
    input stall,             // STOP command from Hazard Unit (1 = PC unchanged)
    input [15:0] next_pc,    // Next Address from MUXes
    output reg [15:0] pc_out // Current address (goes to Instruction Memory)
);

    // Initialize to 0
    initial pc_out = 16'h0000;

    // Asynchronous Reset, Synchronous Write
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            pc_out <= 16'h0000; // If reset pressed, go back to start
        end 
        else if (stall == 0) begin
            // IF NO STALL (engine running), update
            pc_out <= next_pc; 
        end
        // If stall == 1, do nothing (keep old value/freeze)
    end

endmodule