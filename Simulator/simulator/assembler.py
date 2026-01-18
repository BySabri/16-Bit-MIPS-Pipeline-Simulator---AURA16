"""
MIPS 16-bit Assembler
Converts assembly code to 16-bit machine code based on custom ISA.
"""

import re
from typing import List, Dict, Tuple, Optional


# Register mapping
REGISTERS = {
    '$r0': 0, '$r1': 1, '$r2': 2, '$r3': 3,
    '$r4': 4, '$r5': 5, '$r6': 6, '$r7': 7,
    # Also support without $ prefix
    'r0': 0, 'r1': 1, 'r2': 2, 'r3': 3,
    'r4': 4, 'r5': 5, 'r6': 6, 'r7': 7,
}

# R-Type instructions (Opcode: 0000)
R_TYPE_FUNCT = {
    'ADD': 0b000,
    'SUB': 0b001,
    'AND': 0b010,
    'OR':  0b011,
    'SLT': 0b100,
    'JR':  0b101,
}

# I-Type instructions with their opcodes
I_TYPE_OPCODES = {
    'LW':   0b0001,
    'SW':   0b0010,
    'ADDI': 0b0011,
    'SUBI': 0b0100,
    'SLTI': 0b0101,
    'BEQ':  0b0110,
    'BNQ':  0b0111,
    'ANDI': 0b1000,
}

# J-Type instructions with their opcodes
J_TYPE_OPCODES = {
    'JUMP': 0b1001,
    'JAL':  0b1010,
}


class AssemblerError(Exception):
    """Custom exception for assembler errors."""
    def __init__(self, message: str, line_num: int = None):
        self.line_num = line_num
        if line_num is not None:
            super().__init__(f"Line {line_num}: {message}")
        else:
            super().__init__(message)


def parse_register(reg_str: str, line_num: int) -> int:
    """Parse a register string and return its number (0-7)."""
    reg_str = reg_str.strip().lower()
    if reg_str in REGISTERS:
        return REGISTERS[reg_str]
    raise AssemblerError(f"Invalid register: {reg_str}", line_num)


def parse_immediate(imm_str: str, line_num: int, bits: int = 6) -> int:
    """Parse an immediate value (supports decimal and hex)."""
    imm_str = imm_str.strip()
    try:
        if imm_str.startswith('0x') or imm_str.startswith('0X'):
            value = int(imm_str, 16)
        elif imm_str.startswith('-'):
            value = int(imm_str)
        else:
            value = int(imm_str)
        
        # Check range for signed immediate
        max_val = (1 << (bits - 1)) - 1
        min_val = -(1 << (bits - 1))
        if value < min_val or value > max_val:
            raise AssemblerError(f"Immediate value {value} out of range [{min_val}, {max_val}]", line_num)
        
        # Convert to unsigned representation for encoding
        if value < 0:
            value = (1 << bits) + value
        
        return value & ((1 << bits) - 1)
    except ValueError:
        raise AssemblerError(f"Invalid immediate value: {imm_str}", line_num)


def encode_r_type(rs: int, rt: int, rd: int, funct: int) -> int:
    """Encode R-Type instruction: 0000 | Rs(3) | Rt(3) | Rd(3) | Funct(3)"""
    opcode = 0b0000
    return (opcode << 12) | (rs << 9) | (rt << 6) | (rd << 3) | funct


def encode_i_type(opcode: int, rs: int, rt: int, imm: int) -> int:
    """Encode I-Type instruction: Opcode(4) | Rs(3) | Rt(3) | Imm(6)"""
    return (opcode << 12) | (rs << 9) | (rt << 6) | (imm & 0x3F)


def encode_j_type(opcode: int, address: int) -> int:
    """Encode J-Type instruction: Opcode(4) | Address(12)"""
    return (opcode << 12) | (address & 0xFFF)


def tokenize_line(line: str) -> Tuple[Optional[str], Optional[str], List[str]]:
    """
    Tokenize a line of assembly code.
    Returns: (label, instruction, operands)
    """
    # Remove comments
    if '#' in line:
        line = line[:line.index('#')]
    if '//' in line:
        line = line[:line.index('//')]
    
    line = line.strip()
    if not line:
        return None, None, []
    
    label = None
    
    # Check for label
    if ':' in line:
        parts = line.split(':', 1)
        label = parts[0].strip()
        line = parts[1].strip()
    
    if not line:
        return label, None, []
    
    # Split instruction and operands
    parts = line.split(None, 1)
    instruction = parts[0].upper()
    
    operands = []
    if len(parts) > 1:
        # Split operands by comma, handling spaces
        operands = [op.strip() for op in parts[1].split(',')]
    
    return label, instruction, operands


def assemble(code: str) -> Tuple[List[str], Dict[int, str], Dict[str, int]]:
    """
    Assemble MIPS assembly code to machine code.
    
    Args:
        code: Multi-line string of assembly code
        
    Returns:
        Tuple of:
        - List of 16-bit hex machine codes
        - Dict mapping memory address to source line
        - Dict mapping labels to addresses
    """
    lines = code.strip().split('\n')
    
    # First pass: collect labels and determine addresses
    labels: Dict[str, int] = {}
    instructions: List[Tuple[int, int, str, List[str]]] = []  # (addr, line_num, instr, operands)
    
    current_addr = 0
    for line_num, line in enumerate(lines, 1):
        label, instruction, operands = tokenize_line(line)
        
        if label:
            if label in labels:
                raise AssemblerError(f"Duplicate label: {label}", line_num)
            labels[label] = current_addr
        
        if instruction:
            instructions.append((current_addr, line_num, instruction, operands))
            current_addr += 1
    
    # Second pass: encode instructions
    machine_codes: List[str] = []
    addr_to_source: Dict[int, str] = {}
    
    for addr, line_num, instruction, operands in instructions:
        try:
            machine_code = encode_instruction(instruction, operands, labels, addr, line_num)
            hex_code = format(machine_code, '04X')
            machine_codes.append(hex_code)
            addr_to_source[addr] = lines[line_num - 1].strip()
        except AssemblerError:
            raise
        except Exception as e:
            raise AssemblerError(str(e), line_num)
    
    return machine_codes, addr_to_source, labels


def encode_instruction(instruction: str, operands: List[str], labels: Dict[str, int], 
                       current_addr: int, line_num: int) -> int:
    """Encode a single instruction to machine code."""
    
    # R-Type instructions
    if instruction in R_TYPE_FUNCT:
        funct = R_TYPE_FUNCT[instruction]
        
        if instruction == 'JR':
            # JR $rs -> only uses rs
            if len(operands) != 1:
                raise AssemblerError(f"JR requires 1 operand, got {len(operands)}", line_num)
            rs = parse_register(operands[0], line_num)
            return encode_r_type(rs, 0, 0, funct)
        else:
            # ADD, SUB, AND, OR, SLT -> $rd, $rs, $rt
            if len(operands) != 3:
                raise AssemblerError(f"{instruction} requires 3 operands, got {len(operands)}", line_num)
            rd = parse_register(operands[0], line_num)
            rs = parse_register(operands[1], line_num)
            rt = parse_register(operands[2], line_num)
            return encode_r_type(rs, rt, rd, funct)
    
    # I-Type instructions
    elif instruction in I_TYPE_OPCODES:
        opcode = I_TYPE_OPCODES[instruction]
        
        if instruction in ('LW', 'SW'):
            # LW/SW $rt, offset($rs) OR LW/SW $rt, $rs, offset
            if len(operands) == 2:
                # Format: LW $rt, offset($rs)
                rt = parse_register(operands[0], line_num)
                match = re.match(r'(-?\d+)\s*\(\s*(\$?r\d)\s*\)', operands[1], re.IGNORECASE)
                if match:
                    imm = parse_immediate(match.group(1), line_num)
                    rs = parse_register(match.group(2), line_num)
                else:
                    raise AssemblerError(f"Invalid memory operand format: {operands[1]}", line_num)
            elif len(operands) == 3:
                # Format: LW $rt, $rs, offset
                rt = parse_register(operands[0], line_num)
                rs = parse_register(operands[1], line_num)
                imm = parse_immediate(operands[2], line_num)
            else:
                raise AssemblerError(f"{instruction} requires 2-3 operands", line_num)
            return encode_i_type(opcode, rs, rt, imm)
        
        elif instruction in ('BEQ', 'BNQ'):
            # BEQ/BNQ $rs, $rt, label/offset
            if len(operands) != 3:
                raise AssemblerError(f"{instruction} requires 3 operands", line_num)
            rs = parse_register(operands[0], line_num)
            rt = parse_register(operands[1], line_num)
            
            # Check if operand is a label or immediate
            target = operands[2].strip()
            if target in labels:
                # Calculate relative offset: target - (PC + 1)
                offset = labels[target] - (current_addr + 1)
            else:
                offset = int(target) if target.lstrip('-').isdigit() else int(target, 16) if target.startswith('0x') else 0
            
            imm = parse_immediate(str(offset), line_num)
            return encode_i_type(opcode, rs, rt, imm)
        
        else:
            # ADDI, SUBI, SLTI, ANDI -> $rt, $rs, imm
            if len(operands) != 3:
                raise AssemblerError(f"{instruction} requires 3 operands", line_num)
            rt = parse_register(operands[0], line_num)
            rs = parse_register(operands[1], line_num)
            imm = parse_immediate(operands[2], line_num)
            return encode_i_type(opcode, rs, rt, imm)
    
    # J-Type instructions
    elif instruction in J_TYPE_OPCODES:
        opcode = J_TYPE_OPCODES[instruction]
        
        if len(operands) != 1:
            raise AssemblerError(f"{instruction} requires 1 operand", line_num)
        
        target = operands[0].strip()
        if target in labels:
            address = labels[target]
        else:
            try:
                if target.startswith('0x') or target.startswith('0X'):
                    address = int(target, 16)
                else:
                    address = int(target)
            except ValueError:
                raise AssemblerError(f"Undefined label or invalid address: {target}", line_num)
        
        if address < 0 or address > 0xFFF:
            raise AssemblerError(f"Jump address {address} out of range [0, 4095]", line_num)
        
        return encode_j_type(opcode, address)
    
    else:
        raise AssemblerError(f"Unknown instruction: {instruction}", line_num)


def disassemble(hex_code: str) -> str:
    """Convert a 16-bit hex machine code back to assembly (for display)."""
    try:
        code = int(hex_code, 16)
    except ValueError:
        return "???"
    
    opcode = (code >> 12) & 0xF
    
    if opcode == 0b0000:
        # R-Type
        rs = (code >> 9) & 0x7
        rt = (code >> 6) & 0x7
        rd = (code >> 3) & 0x7
        funct = code & 0x7
        
        funct_to_instr = {v: k for k, v in R_TYPE_FUNCT.items()}
        instr = funct_to_instr.get(funct, '???')
        
        if instr == 'JR':
            return f"JR $r{rs}"
        else:
            return f"{instr} $r{rd}, $r{rs}, $r{rt}"
    
    elif opcode in (0b1001, 0b1010):
        # J-Type
        address = code & 0xFFF
        instr = 'JUMP' if opcode == 0b1001 else 'JAL'
        return f"{instr} {address}"
    
    else:
        # I-Type
        rs = (code >> 9) & 0x7
        rt = (code >> 6) & 0x7
        imm = code & 0x3F
        
        # Sign extend immediate for display
        if imm & 0x20:  # If sign bit is set
            imm = imm - 64
        
        opcode_to_instr = {v: k for k, v in I_TYPE_OPCODES.items()}
        instr = opcode_to_instr.get(opcode, '???')
        
        if instr in ('LW', 'SW'):
            return f"{instr} $r{rt}, {imm}($r{rs})"
        elif instr in ('BEQ', 'BNQ'):
            return f"{instr} $r{rs}, $r{rt}, {imm}"
        else:
            return f"{instr} $r{rt}, $r{rs}, {imm}"


if __name__ == '__main__':
    # Test the assembler
    test_code = """
    ADDI $r1, $r0, 5
    ADDI $r2, $r0, 3
    ADD $r3, $r1, $r2
    SW $r3, $r0, 0
    LW $r4, $r0, 0
    BEQ $r3, $r4, END
    ADDI $r5, $r0, 99
    END: ADDI $r6, $r0, 1
    """
    
    try:
        codes, sources, labels = assemble(test_code)
        print("Machine Code:")
        for i, code in enumerate(codes):
            print(f"  {i:03d}: {code} -> {disassemble(code)}")
        print(f"\nLabels: {labels}")
    except AssemblerError as e:
        print(f"Error: {e}")
