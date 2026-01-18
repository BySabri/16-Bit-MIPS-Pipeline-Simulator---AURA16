// ============================================================
// ID/EX Pipeline Register
// Data and control signal transfer from ID stage to EX stage
// ============================================================
module ID_EX_Register (
    input clk,
    input Enable,              // 0 = Stall, 1 = Normal
    input CLR,                 // 1 = Flush (insert bubble)
    input [15:0] PC_Adder_In,  // PC + 1 (for JAL)
    input Reg_Write_In,
    input [2:0] ALU_Control_In,
    input ALU_Src_In,
    input [1:0] Reg_Dst_In,   // 2-bit: 00=Rt, 01=Rd, 10=$ra (JAL)
    input Mem_Write_In,
    input Mem_Read_In,
    input [1:0] Mem_To_Reg_In, // 2-bit: 00=ALU, 01=Mem, 10=PC+1 (JAL)
    input [15:0] Reg_Data_1_In, // RD1 (Rs value)
    input [15:0] Reg_Data_2_In, // RD2 (Rt value)
    input [2:0] Rs_In,         // Source register 1 address
    input [2:0] Rt_In,         // Source register 2 address
    input [2:0] Rd_In,         // Destination register address
    input [15:0] Immediate_In, // Sign-extended immediate

    output reg [15:0] PC_Adder_Out,
    output reg Reg_Write_Out,
    output reg [2:0] ALU_Control_Out,
    output reg ALU_Src_Out,
    output reg [1:0] Reg_Dst_Out,
    output reg Mem_Write_Out,
    output reg Mem_Read_Out,
    output reg [1:0] Mem_To_Reg_Out,
    output reg [15:0] Reg_Data_1_Out,
    output reg [15:0] Reg_Data_2_Out,
    output reg [2:0] Rs_Out,
    output reg [2:0] Rt_Out,
    output reg [2:0] Rd_Out,
    output reg [15:0] Immediate_Out
);

    // Initial values (Reset/Power-on)
    initial begin
        PC_Adder_Out    = 16'h0000;
        Reg_Write_Out   = 0;
        ALU_Control_Out = 3'b000;
        ALU_Src_Out     = 0;
        Reg_Dst_Out     = 2'b00;
        Mem_Write_Out   = 0;
        Mem_Read_Out    = 0;
        Mem_To_Reg_Out  = 2'b00;
        Reg_Data_1_Out  = 16'h0000;
        Reg_Data_2_Out  = 16'h0000;
        Rs_Out          = 3'b000;
        Rt_Out          = 3'b000;
        Rd_Out          = 3'b000;
        Immediate_Out   = 16'h0000;
    end

    always @(posedge clk) begin
        if (CLR) begin
            // =============================================
            // FLUSH: Reset all signals to zero (NOP/Bubble)
            // =============================================
            PC_Adder_Out    <= 16'h0000; 
            Reg_Write_Out   <= 0;
            ALU_Control_Out <= 3'b000;
            ALU_Src_Out     <= 0;
            Reg_Dst_Out     <= 2'b00;
            Mem_Write_Out   <= 0;
            Mem_Read_Out    <= 0;
            Mem_To_Reg_Out  <= 2'b00;
            Reg_Data_1_Out  <= 16'h0000;
            Reg_Data_2_Out  <= 16'h0000;
            Rs_Out          <= 3'b000;
            Rt_Out          <= 3'b000;
            Rd_Out          <= 3'b000;
            Immediate_Out   <= 16'h0000;
        end
        else if (Enable) begin
            // =============================================
            // NORMAL: Transfer data to next stage
            // =============================================
            PC_Adder_Out    <= PC_Adder_In;
            Reg_Write_Out   <= Reg_Write_In;
            ALU_Control_Out <= ALU_Control_In;
            ALU_Src_Out     <= ALU_Src_In;
            Reg_Dst_Out     <= Reg_Dst_In;
            Mem_Write_Out   <= Mem_Write_In;
            Mem_Read_Out    <= Mem_Read_In;
            Mem_To_Reg_Out  <= Mem_To_Reg_In;
            Reg_Data_1_Out  <= Reg_Data_1_In;
            Reg_Data_2_Out  <= Reg_Data_2_In;
            Rs_Out          <= Rs_In;
            Rt_Out          <= Rt_In;
            Rd_Out          <= Rd_In;
            Immediate_Out   <= Immediate_In;
        end
        // If Enable = 0, all values are preserved (Stall)
    end

endmodule
