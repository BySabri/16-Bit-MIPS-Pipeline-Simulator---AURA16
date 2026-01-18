"""
Django views for MIPS Pipeline Simulator.
Provides API endpoints for assembling, stepping, and resetting the CPU.
"""

import json
from django.shortcuts import render
from django.http import JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from .assembler import assemble, AssemblerError, disassemble
from .cpu import MIPS_CPU


def index(request):
    """Render the main simulator dashboard."""
    return render(request, 'index.html')


@csrf_exempt
@require_http_methods(["POST"])
def assemble_code(request):
    """
    Assemble assembly code to machine code.
    
    Request body: {"code": "ADDI $r1, $r0, 5\\n..."}
    Response: {"success": true, "machine_code": [...], "labels": {...}}
    """
    try:
        data = json.loads(request.body)
        code = data.get('code', '')
        
        if not code.strip():
            return JsonResponse({
                'success': False,
                'error': 'No code provided'
            })
        
        machine_codes, addr_to_source, labels = assemble(code)
        
        # Create a list of instructions with their addresses and disassembly
        instructions = []
        for i, hex_code in enumerate(machine_codes):
            # Convert hex to binary (16 bits)
            binary_code = format(int(hex_code, 16), '016b')
            instructions.append({
                'address': i,
                'hex': hex_code,
                'binary': binary_code,
                'source': addr_to_source.get(i, ''),
                'disasm': disassemble(hex_code)
            })
        
        # Initialize CPU with the program
        cpu = MIPS_CPU()
        cpu.load_program(machine_codes)
        request.session['cpu_state'] = cpu.to_json()
        # Clear state history for new program
        request.session['cpu_state_history'] = []
        
        return JsonResponse({
            'success': True,
            'machine_code': instructions,
            'labels': labels,
            'cpu_state': cpu.get_state()
        })
        
    except AssemblerError as e:
        return JsonResponse({
            'success': False,
            'error': str(e)
        })
    except json.JSONDecodeError:
        return JsonResponse({
            'success': False,
            'error': 'Invalid JSON'
        })
    except Exception as e:
        return JsonResponse({
            'success': False,
            'error': f'Internal error: {str(e)}'
        })


@csrf_exempt
@require_http_methods(["POST"])
def step_cpu(request):
    """
    Execute one clock cycle.
    
    Response: {"success": true, "cpu_state": {...}, "running": true/false}
    """
    try:
        # Get CPU state from session
        cpu_json = request.session.get('cpu_state')
        
        if not cpu_json:
            return JsonResponse({
                'success': False,
                'error': 'No program loaded. Please assemble code first.'
            })
        
        # Save current state to history before stepping
        state_history = request.session.get('cpu_state_history', [])
        state_history.append(cpu_json)
        # Keep max 100 states to prevent memory issues
        if len(state_history) > 100:
            state_history = state_history[-100:]
        request.session['cpu_state_history'] = state_history
        
        cpu = MIPS_CPU.from_json(cpu_json)
        
        # Execute one cycle
        running = cpu.step()
        
        # Save state back to session
        request.session['cpu_state'] = cpu.to_json()
        
        return JsonResponse({
            'success': True,
            'cpu_state': cpu.get_state(),
            'running': running,
            'can_step_back': len(state_history) > 0
        })
        
    except Exception as e:
        return JsonResponse({
            'success': False,
            'error': f'Execution error: {str(e)}'
        })


@csrf_exempt
@require_http_methods(["POST"])
def step_back_cpu(request):
    """
    Step back one clock cycle by restoring from history.
    
    Response: {"success": true, "cpu_state": {...}, "can_step_back": true/false}
    """
    try:
        # Get state history from session
        state_history = request.session.get('cpu_state_history', [])
        
        if not state_history:
            return JsonResponse({
                'success': False,
                'error': 'No previous state to go back to.'
            })
        
        # Pop the last state from history
        previous_state = state_history.pop()
        request.session['cpu_state_history'] = state_history
        
        # Restore CPU to previous state
        request.session['cpu_state'] = previous_state
        cpu = MIPS_CPU.from_json(previous_state)
        
        return JsonResponse({
            'success': True,
            'cpu_state': cpu.get_state(),
            'running': not cpu.halted,
            'can_step_back': len(state_history) > 0
        })
        
    except Exception as e:
        return JsonResponse({
            'success': False,
            'error': f'Step back error: {str(e)}'
        })


@csrf_exempt
@require_http_methods(["POST"])
def reset_cpu(request):
    """
    Reset CPU to initial state (keeps program loaded).
    
    Response: {"success": true, "cpu_state": {...}}
    """
    try:
        cpu_json = request.session.get('cpu_state')
        
        if cpu_json:
            cpu = MIPS_CPU.from_json(cpu_json)
            # Keep instruction memory, reset everything else
            instruction_memory = cpu.instruction_memory.copy()
            cpu.reset()
            cpu.instruction_memory = instruction_memory
            request.session['cpu_state'] = cpu.to_json()
            # Clear state history on reset
            request.session['cpu_state_history'] = []
            
            return JsonResponse({
                'success': True,
                'cpu_state': cpu.get_state()
            })
        else:
            cpu = MIPS_CPU()
            request.session['cpu_state'] = cpu.to_json()
            return JsonResponse({
                'success': True,
                'cpu_state': cpu.get_state()
            })
            
    except Exception as e:
        return JsonResponse({
            'success': False,
            'error': f'Reset error: {str(e)}'
        })


@csrf_exempt
@require_http_methods(["POST"])
def run_all(request):
    """
    Run until halted or max cycles reached.
    
    Response: {"success": true, "cpu_state": {...}, "cycles_executed": int}
    """
    try:
        cpu_json = request.session.get('cpu_state')
        
        if not cpu_json:
            return JsonResponse({
                'success': False,
                'error': 'No program loaded. Please assemble code first.'
            })
        
        cpu = MIPS_CPU.from_json(cpu_json)
        
        max_cycles = 1000  # Safety limit
        cycles_executed = 0
        
        while cpu.step() and cycles_executed < max_cycles:
            cycles_executed += 1
        
        # Save state back to session
        request.session['cpu_state'] = cpu.to_json()
        
        return JsonResponse({
            'success': True,
            'cpu_state': cpu.get_state(),
            'cycles_executed': cycles_executed,
            'halted': cpu.halted
        })
        
    except Exception as e:
        return JsonResponse({
            'success': False,
            'error': f'Execution error: {str(e)}'
        })

