// ============================================================
// MEM/WB Pipeline Register
// Data transfer from MEM stage to WB (Write Back) stage
// ============================================================
module MEM_WB_Register (
    input clk,
    input Enable,              // 0 = Stall, 1 = Normal
    
    // =========================================================
    // CONTROL SIGNAL INPUTS (from MEM Stage)
    // =========================================================
    input Reg_Write_In,
    input [1:0] Mem_To_Reg_In,  // 00=ALU, 01=Memory, 10=PC+1 (JAL)
    
    // =========================================================
    // DATA INPUTS (from MEM Stage)
    // =========================================================
    input [15:0] PC_Adder_In,   // PC + 1 (return address for JAL)
    input [15:0] ALU_Result_In, // ALU result (R-type, I-type)
    input [15:0] Read_Data_In,  // Data read from memory (LW)
    input [2:0] Write_Reg_In,   // Destination register address
    
    // =========================================================
    // CONTROL SIGNAL OUTPUTS (to WB Stage)
    // =========================================================
    output reg Reg_Write_Out,
    output reg [1:0] Mem_To_Reg_Out,
    
    // =========================================================
    // DATA OUTPUTS (to WB Stage)
    // =========================================================
    output reg [15:0] PC_Adder_Out,
    output reg [15:0] ALU_Result_Out,
    output reg [15:0] Read_Data_Out,
    output reg [2:0] Write_Reg_Out
);

    // Initial values
    initial begin
        Reg_Write_Out   = 0;
        Mem_To_Reg_Out  = 2'b00;
        
        PC_Adder_Out    = 16'h0000;
        ALU_Result_Out  = 16'h0000;
        Read_Data_Out   = 16'h0000;
        Write_Reg_Out   = 3'b000;
    end

    always @(posedge clk) begin
        if (Enable) begin
            // Transfer data
            Reg_Write_Out   <= Reg_Write_In;
            Mem_To_Reg_Out  <= Mem_To_Reg_In;
            
            PC_Adder_Out    <= PC_Adder_In;
            ALU_Result_Out  <= ALU_Result_In;
            Read_Data_Out   <= Read_Data_In;
            Write_Reg_Out   <= Write_Reg_In;
        end
        // If Enable = 0, all values are preserved (Stall)
    end

endmodule
