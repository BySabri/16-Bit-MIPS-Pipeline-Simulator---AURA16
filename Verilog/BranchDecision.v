// ============================================================
// Logical Decision (Branch Decision)
// Generates PCSrc signal for BEQ and BNQ
// ============================================================
// Logic:
//   PCSrc = (Branch AND Zero) OR (BNQ AND NOT Zero)
//
//   Branch=1, Zero=1 → BEQ taken (equal)
//   BNQ=1, Zero=0    → BNQ taken (not equal)
// ============================================================
module BranchDecision (
    input Branch,              // BEQ signal
    input Zero,                // ALU zero flag (1 if A == B)
    input Branch_Not_Equal,    // BNQ signal
    output PCSrc               // Branch taken?
);

    // Gate-level implementation (as shown in diagram):
    //
    //  Branch ──┬──[AND]──┐
    //           │         │
    //  Zero ────┴─────────┼──[OR]── PCSrc
    //           │         │
    //      [NOT]┴──[AND]──┘
    //           │
    //  BNQ ─────┘

    wire beq_taken;    // Branch AND Zero
    wire bnq_taken;    // BNQ AND (NOT Zero)
    wire not_zero;

    assign not_zero = ~Zero;
    
    assign beq_taken = Branch & Zero;       // BEQ: jump if equal
    assign bnq_taken = Branch_Not_Equal & not_zero;      // BNQ: jump if not equal
    
    assign PCSrc = beq_taken | bnq_taken;   // Take branch if either condition is true

endmodule
