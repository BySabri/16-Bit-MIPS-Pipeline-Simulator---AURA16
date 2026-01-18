// ============================================================
// Comparator (Equality Comparator)
// RD1 and RD2 comparison for branch decision
// ============================================================
module Comparator (
    input [15:0] RD1,             // First operand (Rs value)
    input [15:0] RD2,             // Second operand (Rt value)
    output equal                   // 1 if RD1 == RD2
);

    // 16-bit comparison
    assign equal = (RD1 == RD2);

endmodule
