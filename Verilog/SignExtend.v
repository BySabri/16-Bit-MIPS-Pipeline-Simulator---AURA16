module SignExtend (
    input [5:0] immediate,      // 6-bit immediate (Instruction[5:0])
    output [15:0] extended      // 16-bit sign extended
);

    // Copy sign bit (bit 5) to all upper bits
    assign extended = {{10{immediate[5]}}, immediate};

endmodule
