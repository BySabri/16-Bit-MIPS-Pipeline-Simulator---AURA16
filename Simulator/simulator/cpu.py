"""
MIPS 16-bit Pipeline CPU Simulator
5-stage pipeline: IF, ID, EX, MEM, WB
Includes forwarding unit and hazard detection.
"""

import json
from typing import Dict, List, Optional, Any
from .assembler import disassemble


class MIPS_CPU:
    """
    16-bit MIPS Pipeline CPU with 5 stages.
    
    Pipeline Stages:
        IF  - Instruction Fetch
        ID  - Instruction Decode
        EX  - Execute
        MEM - Memory Access
        WB  - Write Back
    """
    
    def __init__(self):
        self.reset()
    
    def reset(self):
        """Reset CPU to initial state."""
        # Program Counter
        self.pc = 0
        
        # 8 Registers ($r0 always 0)
        self.registers = [0] * 8
        
        # Memory
        self.instruction_memory: List[str] = []  # List of hex codes
        self.data_memory: Dict[int, int] = {}  # Address -> Value
        
        # Cycle counter
        self.cycle = 0
        
        # Pipeline registers - each is a dict representing the latch
        self.IF_ID = self._empty_if_id()
        self.ID_EX = self._empty_id_ex()
        self.EX_MEM = self._empty_ex_mem()
        self.MEM_WB = self._empty_mem_wb()
        
        # Stall/Flush flags
        self.stall = False
        self.flush_if = False
        self.flush_id = False
        
        # Execution finished flag
        self.halted = False
        
        # Forwarding info for visualization
        self.forward_a = None  # 'EX_MEM' or 'MEM_WB' or None
        self.forward_b = None
        
        # Hazard/Stall info for visualization
        self.stall_info = None  # Detailed stall information
        self.memory_warning = None  # Uninitialized memory access warning
        self.control_hazard = None  # Control hazard (branch/jump) information
        self.flush_occurred = False  # Flag to indicate flush happened this cycle
        self.if_id_was_held = False  # Flag to track if IF_ID contains held instruction from stall
        
        # Pipeline history for visualization
        self.pipeline_history = []  # List of cycle snapshots
        self.stall_history = []     # Cycles where stall occurred
        self.forward_history = []   # Cycles with forwarding info
        self.flush_count = 0        # Count of branch/jump flushes
        self._seen_in_if = set()    # Track instructions already shown in IF
        self._seen_in_wb = set()    # Track instructions already shown in WB
    
    def _empty_if_id(self) -> Dict:
        return {
            'instruction': None,  # Hex code
            'pc': 0,
            'valid': False,
        }
    
    def _empty_id_ex(self) -> Dict:
        return {
            'instruction': None,
            'pc': 0,
            'opcode': 0,
            'rs': 0,
            'rt': 0,
            'rd': 0,
            'funct': 0,
            'imm': 0,
            'address': 0,
            'rs_val': 0,
            'rt_val': 0,
            'reg_write': False,
            'mem_read': False,
            'mem_write': False,
            'mem_to_reg': False,
            'branch': False,
            'jump': False,
            'alu_op': 'NOP',
            'valid': False,
        }
    
    def _empty_ex_mem(self) -> Dict:
        return {
            'instruction': None,
            'pc': 0,
            'alu_result': 0,
            'rt_val': 0,
            'rd': 0,
            'reg_write': False,
            'mem_read': False,
            'mem_write': False,
            'mem_to_reg': False,
            'valid': False,
        }
    
    def _empty_mem_wb(self) -> Dict:
        return {
            'instruction': None,
            'pc': 0,
            'alu_result': 0,
            'mem_data': 0,
            'rd': 0,
            'reg_write': False,
            'mem_to_reg': False,
            'valid': False,
        }
    
    def load_program(self, machine_codes: List[str]):
        """Load machine code into instruction memory."""
        self.instruction_memory = machine_codes.copy()
        self.reset()
        self.instruction_memory = machine_codes.copy()
    
    def step(self) -> bool:
        """
        Execute one clock cycle.
        Process stages in reverse order (WB -> IF) to simulate latching.
        Returns True if program is still running, False if halted.
        """
        if self.halted:
            return False
        
        # Reset forwarding and stall info
        self.forward_a = None
        self.forward_b = None
        self.stall_info = None
        self.memory_warning = None
        self.control_hazard = None
        self.flush_occurred = False
        
        # Save current pipeline state before updating
        old_IF_ID = self.IF_ID.copy()
        old_ID_EX = self.ID_EX.copy()
        old_EX_MEM = self.EX_MEM.copy()
        old_MEM_WB = self.MEM_WB.copy()
        
        # Process stages in reverse order
        self._stage_wb(old_MEM_WB)
        new_MEM_WB = self._stage_mem(old_EX_MEM)
        new_EX_MEM = self._stage_ex(old_ID_EX, old_EX_MEM, old_MEM_WB)
        # Pass new_EX_MEM to ID stage for branch forwarding (same-cycle result)
        new_ID_EX, branch_taken, jump_target = self._stage_id(old_IF_ID, new_EX_MEM)
        new_IF_ID = self._stage_if()
        
        # Handle control hazards (branch/jump)
        # Save instruction that completed ID stage for timeline (before flush)
        id_stage_instr_for_timeline = new_ID_EX.get('instruction') if new_ID_EX.get('valid') else None
        
        if branch_taken or jump_target is not None:
            # When branch is taken in ID stage:
            # - old_IF_ID contained the branch instruction  
            # - new_IF_ID contains instruction fetched THIS cycle (wrong path, flush)
            # - new_ID_EX contains decoded branch itself (doesn't need to continue)
            # - new_EX_MEM contains old_ID_EX which was fetched BEFORE branch (wrong path!)
            # We need to flush: new_IF_ID (instruction fetched while branch was decoding)
            # AND new_ID_EX (the branch instruction itself that just finished decoding)
            # Do NOT flush new_EX_MEM (instruction before branch)
            # EXCEPTION: JAL needs to continue through pipeline to write $r7!
            
            # Record control hazard info for visualization
            flushed_instr = new_IF_ID.get('instruction')
            hazard_type = 'Branch' if branch_taken else 'Jump'
            self.control_hazard = {
                'type': f'Control Hazard ({hazard_type})',
                'hazard_type': 'Control',
                'flushed_instruction': disassemble(flushed_instr) if flushed_instr else 'NOP',
                'target_address': jump_target,
                'reason': f'{hazard_type} taken → Flushing pipeline'
            }
            self.flush_occurred = True
            self.flush_count += 1
            
            new_IF_ID = self._empty_if_id()
            
            # Branch/Jump instruction should continue through pipeline (EX, MEM, WB)
            # Only flush ID_EX for JAL exception case is wrong - we should KEEP the branch
            # The branch doesn't do anything in EX/MEM/WB but it should still flow through
            # Actually, for branches (BEQ/BNQ), they don't write to register, so they can
            # continue through as NOPs. But we want timeline to show them progressing.
            # KEEP new_ID_EX for branch - it will continue through pipeline
            # Only if the branch instruction itself has no side effects after ID
            # (no reg_write, no mem_write), it's effectively a NOP in later stages
            # but we still want it in the pipeline for accurate visualization
            
            if jump_target is not None:
                self.pc = jump_target
        
        # Handle stall (load-use hazard)
        stall_occurred = self.stall  # Save before reset
        # Save the held flag from previous cycle (set during previous stall)
        if_id_held_from_previous_stall = self.if_id_was_held
        

        
        if self.stall:
            # Keep IF_ID, insert bubble in ID_EX, don't advance PC
            new_ID_EX = self._empty_id_ex()
            new_IF_ID = old_IF_ID
            # Set PC to fetch NEXT instruction (after the held one), not the same one again
            self.pc = old_IF_ID.get('pc', self.pc - 1) + 1
            self.stall = False
            self.if_id_was_held = True  # Mark that NEXT cycle's IF_ID is held
        else:
            self.if_id_was_held = False  # Reset flag for next cycle
        
        # Update pipeline registers
        self.IF_ID = new_IF_ID
        self.ID_EX = new_ID_EX
        self.EX_MEM = new_EX_MEM
        self.MEM_WB = new_MEM_WB
        
        # Increment cycle
        self.cycle += 1
        
        # Record pipeline history for visualization
        # Track what was in each stage - use PC+instruction to uniquely identify each instruction instance
        
        if not hasattr(self, '_seen_in_if'):
            self._seen_in_if = set()  # Now stores (pc, instruction) tuples
        if not hasattr(self, '_seen_in_wb'):
            self._seen_in_wb = set()  # Now stores (pc, instruction) tuples
        
        # IF stage - only show if instruction at this PC hasn't been seen in IF before
        if_instr = None
        if_pc = None
        current_if_pc = self.IF_ID.get('pc')
        current_if_instr = self.IF_ID.get('instruction')
        if current_if_instr and current_if_pc is not None:
            key = (current_if_pc, current_if_instr)
            if key not in self._seen_in_if:
                if_instr = current_if_instr
                if_pc = current_if_pc
                self._seen_in_if.add(key)
        
        # ID stage - what was decoded this cycle
        id_instr = None
        id_pc = None
        if stall_occurred:
            id_instr = old_IF_ID.get('instruction')
            id_pc = old_IF_ID.get('pc')
        elif id_stage_instr_for_timeline:
            id_instr = id_stage_instr_for_timeline
            id_pc = old_IF_ID.get('pc')  # The branch/jump that just decoded
        else:
            id_instr = self.ID_EX.get('instruction')
            id_pc = self.ID_EX.get('pc')
        
        # EX stage
        ex_instr = self.EX_MEM.get('instruction')
        ex_pc = self.EX_MEM.get('pc')
        
        # MEM stage
        mem_instr = self.MEM_WB.get('instruction')
        mem_pc = self.MEM_WB.get('pc')
        
        # WB stage - only show if instruction at this PC hasn't been seen in WB before
        wb_instr = None
        wb_pc = None
        current_wb_pc = old_MEM_WB.get('pc')
        current_wb_instr = old_MEM_WB.get('instruction') if old_MEM_WB.get('valid') else None
        if current_wb_instr and current_wb_pc is not None:
            key = (current_wb_pc, current_wb_instr)
            if key not in self._seen_in_wb:
                wb_instr = current_wb_instr
                wb_pc = current_wb_pc
                self._seen_in_wb.add(key)
        
        cycle_snapshot = {
            'cycle': self.cycle,
            'IF': if_instr, 'IF_PC': if_pc,
            'ID': id_instr, 'ID_PC': id_pc,
            'EX': ex_instr, 'EX_PC': ex_pc,
            'MEM': mem_instr, 'MEM_PC': mem_pc,
            'WB': wb_instr, 'WB_PC': wb_pc,
        }
        self.pipeline_history.append(cycle_snapshot)
        
        # Record stall if occurred
        if stall_occurred or (not new_ID_EX['valid'] and old_IF_ID['valid']):
            self.stall_history.append(self.cycle)
        
        # Record forwarding if occurred
        if self.forward_a or self.forward_b:
            self.forward_history.append({
                'cycle': self.cycle,
                'forward_a': self.forward_a,
                'forward_b': self.forward_b,
            })
        
        # Check if pipeline is empty
        if (not self.IF_ID['valid'] and 
            not self.ID_EX['valid'] and 
            not self.EX_MEM['valid'] and 
            not self.MEM_WB['valid'] and
            self.pc >= len(self.instruction_memory)):
            self.halted = True
        
        return not self.halted
    
    def _stage_if(self) -> Dict:
        """Instruction Fetch stage."""
        result = self._empty_if_id()
        
        if self.pc < len(self.instruction_memory):
            result['instruction'] = self.instruction_memory[self.pc]
            result['pc'] = self.pc
            result['valid'] = True
            self.pc += 1
        
        return result
    
    def _stage_id(self, if_id: Dict, new_ex_mem: Dict = None) -> tuple:
        """
        Instruction Decode stage.
        new_ex_mem: The result being computed in EX stage this same cycle (for branch forwarding)
        Returns: (id_ex register, branch_taken flag, jump_target or None)
        """
        result = self._empty_id_ex()
        branch_taken = False
        jump_target = None
        
        if not if_id['valid']:
            return result, branch_taken, jump_target
        
        instruction = if_id['instruction']
        if instruction is None:
            return result, branch_taken, jump_target
        
        try:
            code = int(instruction, 16)
        except:
            return result, branch_taken, jump_target
        
        result['instruction'] = instruction
        result['pc'] = if_id['pc']
        result['valid'] = True
        
        # Decode instruction
        opcode = (code >> 12) & 0xF
        result['opcode'] = opcode
        
        if opcode == 0b0000:
            # R-Type
            rs = (code >> 9) & 0x7
            rt = (code >> 6) & 0x7
            rd = (code >> 3) & 0x7
            funct = code & 0x7
            
            result['rs'] = rs
            result['rt'] = rt
            result['rd'] = rd
            result['funct'] = funct
            result['rs_val'] = self.registers[rs]
            result['rt_val'] = self.registers[rt]
            
            if funct == 0b101:  # JR
                result['jump'] = True
                result['alu_op'] = 'JR'
                
                # Get forwarded value for JR (similar to branch forwarding)
                rs_val_jr = self.registers[rs]
                
                # Check for load-use hazard with JR (must stall if LW is writing to rs)
                if self.ID_EX.get('valid') and self.ID_EX.get('mem_read'):
                    if self.ID_EX.get('rd') == rs and rs != 0:
                        # LW is in EX stage, we need to stall
                        self.stall = True
                        self.stall_info = {
                            'type': 'Load-Use Hazard (JR)',
                            'hazard_type': 'RAW',
                            'waiting_reg': f'$r{rs}',
                            'waiting_for': self.ID_EX.get('disasm', 'LW'),
                            'blocked_instr': 'JR',
                            'reason': f'JR needs $r{rs} from memory'
                        }
                        # Return without setting jump_target (will be recalculated after stall)
                        return result, False, None
                
                # Forward from MEM_WB (Lowest Priority)
                if self.MEM_WB.get('valid') and self.MEM_WB.get('reg_write') and self.MEM_WB.get('rd', 0) != 0:
                    if rs == self.MEM_WB['rd']:
                        rs_val_jr = self.MEM_WB.get('mem_data', 0) if self.MEM_WB.get('mem_to_reg') else self.MEM_WB.get('alu_result', 0)
                
                # Forward from EX_MEM (Medium Priority)
                if self.EX_MEM.get('valid') and self.EX_MEM.get('reg_write') and self.EX_MEM.get('rd', 0) != 0:
                    if rs == self.EX_MEM['rd']:
                        rs_val_jr = self.EX_MEM.get('alu_result', 0)
                
                # Forward from new_ex_mem (same-cycle EX result - HIGHEST PRIORITY)
                if new_ex_mem and new_ex_mem.get('valid') and new_ex_mem.get('reg_write') and new_ex_mem.get('rd', 0) != 0:
                    if rs == new_ex_mem['rd']:
                        rs_val_jr = new_ex_mem.get('alu_result', 0)
                
                # Check if ID_EX has the value we need (previous instruction writing to rs)
                # This is a RAW hazard - we need to stall because the value is not ready yet
                if self.ID_EX.get('valid') and self.ID_EX.get('reg_write') and self.ID_EX.get('rd') == rs and rs != 0:
                    # Previous instruction is in EX stage, result will be ready next cycle
                    # We need to stall to wait for forwarding
                    self.stall = True
                    self.stall_info = {
                        'type': 'Data Hazard (JR)',
                        'hazard_type': 'RAW',
                        'waiting_reg': f'$r{rs}',
                        'waiting_for': self.ID_EX.get('disasm', 'instruction'),
                        'blocked_instr': 'JR',
                        'reason': f'JR needs $r{rs} from previous instruction'
                    }
                    return result, False, None
                
                jump_target = rs_val_jr
            elif funct < 5:
                result['reg_write'] = True
                result['alu_op'] = ['ADD', 'SUB', 'AND', 'OR', 'SLT'][funct]
            else:
                # Invalid R-Type funct (6 or 7) -> Treat as NOP
                pass
        
        elif opcode in (0b1001, 0b1010):
            # J-Type
            address = code & 0xFFF
            result['address'] = address
            result['jump'] = True
            
            if opcode == 0b1001:  # JUMP
                result['alu_op'] = 'JUMP'
                jump_target = address
            else:  # JAL
                result['alu_op'] = 'JAL'
                result['reg_write'] = True
                result['rd'] = 7  # $r7
                result['rs_val'] = if_id['pc'] + 1  # Return address
                jump_target = address
        
        else:
            # I-Type
            rs = (code >> 9) & 0x7
            rt = (code >> 6) & 0x7
            imm = code & 0x3F
            
            # Sign extend immediate
            if imm & 0x20:
                imm = imm - 64
            
            result['rs'] = rs
            result['rt'] = rt
            result['rd'] = rt  # For I-type, destination is rt
            result['imm'] = imm
            result['rs_val'] = self.registers[rs]
            result['rt_val'] = self.registers[rt]
            
            # Get forwarded values for branch comparison
            rs_val_fwd = self.registers[rs]
            rt_val_fwd = self.registers[rt]
            
            # Forward from MEM_WB (Lowest Priority)
            if self.MEM_WB.get('valid') and self.MEM_WB.get('reg_write') and self.MEM_WB.get('rd', 0) != 0:
                mem_rd = self.MEM_WB['rd']
                wb_data = self.MEM_WB.get('mem_data', 0) if self.MEM_WB.get('mem_to_reg') else self.MEM_WB.get('alu_result', 0)
                if rs == mem_rd:
                    rs_val_fwd = wb_data
                if rt == mem_rd:
                    rt_val_fwd = wb_data

            # Forward from EX_MEM (Medium Priority)
            if self.EX_MEM.get('valid') and self.EX_MEM.get('reg_write') and self.EX_MEM.get('rd', 0) != 0:
                ex_rd = self.EX_MEM['rd']
                if rs == ex_rd:
                    rs_val_fwd = self.EX_MEM.get('alu_result', 0)
                if rt == ex_rd:
                    rt_val_fwd = self.EX_MEM.get('alu_result', 0)

            # Forward from new_ex_mem (same-cycle EX result - HIGHEST PRIORITY)
            if new_ex_mem and new_ex_mem.get('valid') and new_ex_mem.get('reg_write') and new_ex_mem.get('rd', 0) != 0:
                new_rd = new_ex_mem['rd']
                if rs == new_rd:
                    rs_val_fwd = new_ex_mem.get('alu_result', 0)
                if rt == new_rd:
                    rt_val_fwd = new_ex_mem.get('alu_result', 0)
            
            if opcode == 0b0001:  # LW
                result['mem_read'] = True
                result['mem_to_reg'] = True
                result['reg_write'] = True
                result['alu_op'] = 'ADDI'
            elif opcode == 0b0010:  # SW
                result['mem_write'] = True
                result['alu_op'] = 'ADDI'
            elif opcode == 0b0011:  # ADDI
                result['reg_write'] = True
                result['alu_op'] = 'ADDI'
            elif opcode == 0b0100:  # SUBI
                result['reg_write'] = True
                result['alu_op'] = 'SUBI'
            elif opcode == 0b0101:  # SLTI
                result['reg_write'] = True
                result['alu_op'] = 'SLTI'
            elif opcode == 0b0110:  # BEQ
                result['branch'] = True
                result['alu_op'] = 'BEQ'
                
                if rs_val_fwd == rt_val_fwd:
                    branch_taken = True
                    jump_target = if_id['pc'] + 1 + imm
            elif opcode == 0b0111:  # BNQ
                result['branch'] = True
                result['alu_op'] = 'BNQ'
                if rs_val_fwd != rt_val_fwd:
                    branch_taken = True
                    jump_target = if_id['pc'] + 1 + imm
            elif opcode == 0b1000:  # ANDI
                result['reg_write'] = True
                result['alu_op'] = 'ANDI'
        
        # Check for load-use hazard
        # Branch/Jump resolve in ID stage but LW data is available after MEM stage
        # So branch/jump needs 2 stalls after LW, normal instructions need 1 stall
        
        # Stall case 1: LW in EX stage (ID_EX) - applies to ALL instructions
        if self.ID_EX['valid'] and self.ID_EX['mem_read']:
            ld_rd = self.ID_EX['rd']
            hazard_reg = None
            if result['rs'] == ld_rd and ld_rd != 0:
                hazard_reg = 'rs'
            elif result['rt'] == ld_rd and ld_rd != 0 and not result['mem_write']:
                hazard_reg = 'rt'
            
            if hazard_reg:
                self.stall = True
                self.stall_info = {
                    'type': 'Load-Use Hazard',
                    'hazard_type': 'RAW',
                    'waiting_reg': f'$r{ld_rd}',
                    'waiting_for': self.ID_EX.get('disasm', 'LW'),
                    'blocked_instr': result.get('disasm', 'instruction'),
                    'reason': f'${hazard_reg} needs $r{ld_rd} from memory'
                }
        
        # Stall case 2: LW in MEM stage (EX_MEM) - ONLY for branch/jump
        # Normal ALU instructions can get data via MEM_WB forwarding, but
        # branch/jump decide in ID stage before MEM_WB forwarding is available
        if self.EX_MEM.get('valid') and self.EX_MEM.get('mem_to_reg'):
            ld_rd = self.EX_MEM.get('rd', 0)
            is_branch_or_jump = result.get('branch') or result.get('jump')
            
            if is_branch_or_jump and ld_rd != 0:
                needs_rs = result['rs'] == ld_rd
                needs_rt = result['rt'] == ld_rd
                
                if needs_rs or needs_rt:
                    self.stall = True
                    self.stall_info = {
                        'type': 'Load-Use Hazard (Branch)',
                        'hazard_type': 'RAW',
                        'waiting_reg': f'$r{ld_rd}',
                        'waiting_for': 'LW in MEM stage',
                        'blocked_instr': result.get('disasm', 'Branch/Jump'),
                        'reason': f'Branch needs $r{ld_rd} from LW still in MEM stage'
                    }
        
        return result, branch_taken, jump_target
    
    def _stage_ex(self, id_ex: Dict, ex_mem: Dict, mem_wb: Dict) -> Dict:
        """Execute stage with forwarding."""
        result = self._empty_ex_mem()
        
        if not id_ex['valid']:
            return result
        
        result['instruction'] = id_ex['instruction']
        result['pc'] = id_ex['pc']
        result['valid'] = True
        result['rd'] = id_ex['rd']
        result['reg_write'] = id_ex['reg_write']
        result['mem_read'] = id_ex['mem_read']
        result['mem_write'] = id_ex['mem_write']
        result['mem_to_reg'] = id_ex['mem_to_reg']
        
        # Get operand values with forwarding
        rs_val = id_ex['rs_val']
        rt_val = id_ex['rt_val']
        
        # Forwarding from EX/MEM
        if ex_mem['valid'] and ex_mem['reg_write'] and ex_mem['rd'] != 0:
            if id_ex['rs'] == ex_mem['rd']:
                rs_val = ex_mem['alu_result']
                self.forward_a = {
                    'source': 'EX_MEM',
                    'reg': f'$r{ex_mem["rd"]}',
                    'value': ex_mem['alu_result']
                }
            if id_ex['rt'] == ex_mem['rd']:
                rt_val = ex_mem['alu_result']
                self.forward_b = {
                    'source': 'EX_MEM',
                    'reg': f'$r{ex_mem["rd"]}',
                    'value': ex_mem['alu_result']
                }
        
        # Forwarding from MEM/WB
        if mem_wb['valid'] and mem_wb['reg_write'] and mem_wb['rd'] != 0:
            write_data = mem_wb['mem_data'] if mem_wb['mem_to_reg'] else mem_wb['alu_result']
            if id_ex['rs'] == mem_wb['rd'] and not isinstance(self.forward_a, dict):
                rs_val = write_data
                self.forward_a = {
                    'source': 'MEM_WB',
                    'reg': f'$r{mem_wb["rd"]}',
                    'value': write_data
                }
            if id_ex['rt'] == mem_wb['rd'] and not isinstance(self.forward_b, dict):
                rt_val = write_data
                self.forward_b = {
                    'source': 'MEM_WB',
                    'reg': f'$r{mem_wb["rd"]}',
                    'value': write_data
                }
        
        result['rt_val'] = rt_val
        
        # ALU operation
        alu_op = id_ex['alu_op']
        imm = id_ex['imm']
        
        if alu_op == 'ADD':
            result['alu_result'] = self._alu_add(rs_val, rt_val)
        elif alu_op == 'SUB':
            result['alu_result'] = self._alu_sub(rs_val, rt_val)
        elif alu_op == 'AND':
            result['alu_result'] = rs_val & rt_val
        elif alu_op == 'OR':
            result['alu_result'] = rs_val | rt_val
        elif alu_op == 'SLT':
            result['alu_result'] = 1 if self._signed(rs_val) < self._signed(rt_val) else 0
        elif alu_op == 'ADDI':
            result['alu_result'] = self._alu_add(rs_val, imm)
        elif alu_op == 'SUBI':
            result['alu_result'] = self._alu_sub(rs_val, imm)
        elif alu_op == 'SLTI':
            result['alu_result'] = 1 if self._signed(rs_val) < imm else 0
        elif alu_op == 'ANDI':
            # Zero-extend immediate for ANDI
            result['alu_result'] = rs_val & (imm & 0x3F)
        elif alu_op == 'JAL':
            result['alu_result'] = id_ex['rs_val']  # Return address
        elif alu_op in ('LW', 'SW', 'ADD'):
            # Memory address calculation
            result['alu_result'] = self._alu_add(rs_val, imm)
        else:
            result['alu_result'] = 0
        
        return result
    
    def _stage_mem(self, ex_mem: Dict) -> Dict:
        """Memory stage."""
        result = self._empty_mem_wb()
        
        if not ex_mem['valid']:
            return result
        
        result['instruction'] = ex_mem['instruction']
        result['pc'] = ex_mem['pc']
        result['valid'] = True
        result['alu_result'] = ex_mem['alu_result']
        result['rd'] = ex_mem['rd']
        result['reg_write'] = ex_mem['reg_write']
        result['mem_to_reg'] = ex_mem['mem_to_reg']
        
        addr = ex_mem['alu_result'] & 0xFFFF
        
        if ex_mem['mem_read']:
            # Load from memory - check for uninitialized access
            if addr not in self.data_memory:
                self.memory_warning = {
                    'type': 'Uninitialized Memory',
                    'address': addr,
                    'instruction': ex_mem.get('instruction', ''),
                    'message': f'Reading from uninitialized address {addr} (returns 0)'
                }
            result['mem_data'] = self.data_memory.get(addr, 0)
        elif ex_mem['mem_write']:
            # Store to memory
            self.data_memory[addr] = ex_mem['rt_val'] & 0xFFFF
        
        return result
    
    def _stage_wb(self, mem_wb: Dict):
        """Write Back stage."""
        if not mem_wb['valid']:
            return
        
        if mem_wb['reg_write'] and mem_wb['rd'] != 0:
            if mem_wb['mem_to_reg']:
                self.registers[mem_wb['rd']] = mem_wb['mem_data'] & 0xFFFF
            else:
                self.registers[mem_wb['rd']] = mem_wb['alu_result'] & 0xFFFF
    
    def _alu_add(self, a: int, b: int) -> int:
        """16-bit addition with overflow handling."""
        result = (a + b) & 0xFFFF
        return result
    
    def _alu_sub(self, a: int, b: int) -> int:
        """16-bit subtraction."""
        result = (a - b) & 0xFFFF
        return result
    
    def _signed(self, val: int) -> int:
        """Convert 16-bit unsigned to signed."""
        if val & 0x8000:
            return val - 0x10000
        return val
    
    def get_state(self) -> Dict[str, Any]:
        """Get current CPU state as a dictionary for JSON serialization."""
        # Calculate performance metrics
        instructions_completed = len(self._seen_in_wb)  # Unique instructions that completed WB
        total_cycles = self.cycle
        stall_cycles = len(self.stall_history)
        forward_cycles = len(self.forward_history)
        
        # CPI = Cycles / Instructions (ideal is 1.0 for pure pipeline)
        cpi = total_cycles / instructions_completed if instructions_completed > 0 else 0
        stall_rate = (stall_cycles / total_cycles * 100) if total_cycles > 0 else 0
        forward_rate = (forward_cycles / total_cycles * 100) if total_cycles > 0 else 0
        
        return {
            'pc': self.pc,
            'cycle': self.cycle,
            'registers': self.registers.copy(),
            'data_memory': {str(k): v for k, v in self.data_memory.items()},
            'instruction_memory': self.instruction_memory.copy(),
            'IF_ID': self._pipeline_stage_display(self.IF_ID),
            'ID_EX': self._pipeline_stage_display(self.ID_EX),
            'EX_MEM': self._pipeline_stage_display(self.EX_MEM),
            'MEM_WB': self._pipeline_stage_display(self.MEM_WB),
            'halted': self.halted,
            'forward_a': self.forward_a,
            'forward_b': self.forward_b,
            'stall_info': self.stall_info,
            'memory_warning': self.memory_warning,
            'control_hazard': self.control_hazard,
            'flush_occurred': self.flush_occurred,
            'pipeline_history': self.pipeline_history,
            'stall_history': self.stall_history,
            'forward_history': self.forward_history,
            'is_stalling': self.stall,
            # Performance metrics
            'performance': {
                'cycles': total_cycles,
                'instructions': instructions_completed,
                'cpi': round(cpi, 2),
                'stall_cycles': stall_cycles,
                'stall_rate': round(stall_rate, 1),
                'forward_cycles': forward_cycles,
                'forward_rate': round(forward_rate, 1),
                'flush_count': self.flush_count,
            }
        }
    
    def _pipeline_stage_display(self, stage: Dict) -> Dict:
        """Format pipeline stage for display."""
        result = stage.copy()
        if stage.get('instruction'):
            result['disasm'] = disassemble(stage['instruction'])
        else:
            result['disasm'] = 'NOP'
        return result
    
    def to_json(self) -> str:
        """Serialize CPU state to JSON."""
        state = {
            'pc': self.pc,
            'cycle': self.cycle,
            'registers': self.registers,
            'data_memory': {str(k): v for k, v in self.data_memory.items()},
            'instruction_memory': self.instruction_memory,
            'IF_ID': self.IF_ID,
            'ID_EX': self.ID_EX,
            'EX_MEM': self.EX_MEM,
            'MEM_WB': self.MEM_WB,
            'halted': self.halted,
            'stall': self.stall,
            'pipeline_history': self.pipeline_history,
            'stall_history': self.stall_history,
            'forward_history': self.forward_history,
            'flush_count': self.flush_count,
            # Convert tuple sets to lists of lists for JSON
            '_seen_in_if': [list(t) for t in self._seen_in_if],
            '_seen_in_wb': [list(t) for t in self._seen_in_wb],
        }
        return json.dumps(state)
    
    @classmethod
    def from_json(cls, json_str: str) -> 'MIPS_CPU':
        """Deserialize CPU state from JSON."""
        state = json.loads(json_str)
        cpu = cls()
        cpu.pc = state['pc']
        cpu.cycle = state['cycle']
        cpu.registers = state['registers']
        cpu.data_memory = {int(k): v for k, v in state['data_memory'].items()}
        cpu.instruction_memory = state['instruction_memory']
        cpu.IF_ID = state['IF_ID']
        cpu.ID_EX = state['ID_EX']
        cpu.EX_MEM = state['EX_MEM']
        cpu.MEM_WB = state['MEM_WB']
        cpu.halted = state['halted']
        cpu.stall = state.get('stall', False)
        cpu.pipeline_history = state.get('pipeline_history', [])
        cpu.stall_history = state.get('stall_history', [])
        cpu.forward_history = state.get('forward_history', [])
        # Convert lists back to tuple sets
        cpu._seen_in_if = {tuple(t) for t in state.get('_seen_in_if', [])}
        cpu._seen_in_wb = {tuple(t) for t in state.get('_seen_in_wb', [])}
        cpu.flush_count = state.get('flush_count', 0)
        return cpu


if __name__ == '__main__':
    # Test the CPU
    from .assembler import assemble
    
    test_code = """
    ADDI $r1, $r0, 5
    ADDI $r2, $r0, 3
    ADD $r3, $r1, $r2
    """
    
    codes, sources, labels = assemble(test_code)
    cpu = MIPS_CPU()
    cpu.load_program(codes)
    
    print("Initial state:")
    print(f"  Registers: {cpu.registers}")
    
    for i in range(10):
        if not cpu.step():
            print(f"Halted after {cpu.cycle} cycles")
            break
        print(f"\nCycle {cpu.cycle}:")
        print(f"  PC: {cpu.pc}")
        print(f"  Registers: {cpu.registers}")
        state = cpu.get_state()
        print(f"  IF: {state['IF_ID']['disasm']}")
        print(f"  ID: {state['ID_EX']['disasm']}")
        print(f"  EX: {state['EX_MEM']['disasm']}")
        print(f"  MEM: {state['MEM_WB']['disasm']}")
