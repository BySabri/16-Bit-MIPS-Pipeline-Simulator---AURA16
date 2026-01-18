
from simulator.assembler import assemble
try:
    codes, _, _ = assemble("SW $r1, $r0, 0")
    code = int(codes[0], 16)
    opcode = (code >> 12) & 0xF
    rs = (code >> 9) & 0x7
    rt = (code >> 6) & 0x7
    imm = code & 0x3F
    print(f"Code: {hex(code)}")
    print(f"Opcode: {bin(opcode)} (Expected 0b0010)")
    print(f"Rs: {rs} (Expected 0 - $r0)")
    print(f"Rt: {rt} (Expected 1 - $r1)")
    print(f"Imm: {imm} (Expected 0)")
except Exception as e:
    print(e)
