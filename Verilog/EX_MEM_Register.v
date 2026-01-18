// ============================================================
// EX/MEM Pipeline Register
// Data and control signal transfer from EX stage to MEM stage
// ============================================================
module EX_MEM_Register (
    input clk,
    input Enable,              // 0 = Stall, 1 = Normal
    input CLR,                 // 1 = Flush
    input [15:0] PC_Adder_In,     // PC + 1 (for JAL)   
    input Reg_Write_In,
    input Mem_Write_In,
    input Mem_Read_In,
    input [1:0] Mem_To_Reg_In,
    input [15:0] ALU_Result_In,   // ALU result
    input [15:0] Read_Data2_In,   // Data to write for SW
    input [2:0] Write_Reg_In,     // Destination register address
    output reg [15:0] PC_Adder_Out,
    output reg Reg_Write_Out,
    output reg Mem_Write_Out,
    output reg Mem_Read_Out,
    output reg [1:0] Mem_To_Reg_Out,
    output reg [15:0] ALU_Result_Out,
    output reg [15:0] Read_Data2_Out,
    output reg [2:0] Write_Reg_Out
);

    // Initial values
    initial begin
        // Control signals
        Reg_Write_Out   = 0;
        Mem_Write_Out   = 0;
        Mem_Read_Out    = 0;
        Mem_To_Reg_Out  = 2'b00;
        
        // Data signals
        PC_Adder_Out    = 16'h0000;
        ALU_Result_Out  = 16'h0000;
        Read_Data2_Out  = 16'h0000;
        Write_Reg_Out   = 3'b000;
    end

    always @(posedge clk) begin
        if (CLR) begin
            // =============================================
            // FLUSH: Reset all signals to zero
            // =============================================
            Reg_Write_Out   <= 0;
            Mem_Write_Out   <= 0;
            Mem_Read_Out    <= 0;
            Mem_To_Reg_Out  <= 2'b00;
            
            PC_Adder_Out    <= 16'h0000;
            ALU_Result_Out  <= 16'h0000;
            Read_Data2_Out  <= 16'h0000;
            Write_Reg_Out   <= 3'b000;
        end
        else if (Enable) begin
            // =============================================
            // NORMAL: Transfer data
            // =============================================
            Reg_Write_Out   <= Reg_Write_In;
            Mem_Write_Out   <= Mem_Write_In;
            Mem_Read_Out    <= Mem_Read_In;
            Mem_To_Reg_Out  <= Mem_To_Reg_In;
            
            PC_Adder_Out    <= PC_Adder_In;
            ALU_Result_Out  <= ALU_Result_In;
            Read_Data2_Out  <= Read_Data2_In;
            Write_Reg_Out   <= Write_Reg_In;
        end
        // If Enable = 0, all values are preserved (Stall)
    end

endmodule
