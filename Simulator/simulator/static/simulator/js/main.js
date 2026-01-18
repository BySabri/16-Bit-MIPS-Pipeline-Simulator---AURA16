let machineCode = [];
let previousRegisters = [0, 0, 0, 0, 0, 0, 0, 0];
let currentPC = 0;
let sourceLines = [];
let pipelineHistory = [];    // Timeline data
let instructionMap = {};     // Maps hex code to disassembly
let isRunning = false;       // Animation running state
let runIntervalId = null;    // Interval ID for run animation
let lastMemWb = null;        // Track previous MEM_WB for WB stage display

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initRegisters();
    updateLineNumbers();
    setStatus('ready', 'Ready');

    // Update line numbers on input
    document.getElementById('codeEditor').addEventListener('input', updateLineNumbers);
    document.getElementById('codeEditor').addEventListener('scroll', syncScroll);

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        // ESC - Stop execution or close modals
        if (e.key === 'Escape') {
            if (isRunning) {
                stopRun();
                return;
            }
            document.getElementById('timelineModal').classList.remove('show');
            document.getElementById('referenceModal').classList.remove('show');
            return;
        }

        // Don't trigger shortcuts when typing in editor
        const activeEl = document.activeElement;
        const isTyping = activeEl.tagName === 'TEXTAREA' || activeEl.tagName === 'INPUT';

        // Ctrl+E - Assemble
        if (e.ctrlKey && e.key === 'e') {
            e.preventDefault();
            assembleCode();
            return;
        }

        // Space - Step (only if not typing)
        if (e.code === 'Space' && !isTyping) {
            e.preventDefault();
            const btn = document.getElementById('btnStep');
            if (!btn.disabled) stepCPU();
            return;
        }

        // Backspace - Step Back (only if not typing)
        if (e.code === 'Backspace' && !isTyping) {
            e.preventDefault();
            const btn = document.getElementById('btnStepBack');
            if (!btn.disabled) stepBackCPU();
            return;
        }

        // Ctrl+A - Run/Stop Toggle
        if (e.ctrlKey && e.key === 'a' && !isTyping) {
            e.preventDefault();
            const btn = document.getElementById('btnRunStop');
            if (!btn.disabled || isRunning) toggleRunStop();
            return;
        }

        // Ctrl+R - Reset
        if (e.ctrlKey && e.key === 'r') {
            e.preventDefault();
            resetCPU();
            return;
        }
    });
});

// ============== MODAL FUNCTIONS ==============
function toggleTimelineModal() {
    const modal = document.getElementById('timelineModal');
    modal.classList.toggle('show');
}

function closeTimelineModal(event) {
    if (event.target.id === 'timelineModal') {
        document.getElementById('timelineModal').classList.remove('show');
    }
}

function toggleReferenceModal() {
    const modal = document.getElementById('referenceModal');
    modal.classList.toggle('show');
}

function closeReferenceModal(event) {
    if (event.target.id === 'referenceModal') {
        document.getElementById('referenceModal').classList.remove('show');
    }
}

// ============== HEX EXPORT MODAL ==============
function toggleHexExportModal() {
    const modal = document.getElementById('hexExportModal');
    modal.classList.toggle('show');
    if (modal.classList.contains('show')) {
        updateHexExportContent();
    }
}

function closeHexExportModal(event) {
    if (event.target.id === 'hexExportModal') {
        document.getElementById('hexExportModal').classList.remove('show');
    }
}

function updateHexExportContent() {
    const textarea = document.getElementById('hexExportText');
    if (!machineCode.length) {
        textarea.value = '// No instructions assembled yet';
        return;
    }
    const hexLines = machineCode.map(instr => instr.hex).join('\n');
    textarea.value = hexLines;
}

function copyHexToClipboard() {
    const textarea = document.getElementById('hexExportText');
    textarea.select();
    document.execCommand('copy');

    // Show feedback
    const btn = document.getElementById('copyHexBtn');
    const originalText = btn.textContent;
    btn.textContent = '✓ Copied!';
    btn.style.background = 'rgba(95, 61, 114, 0.3)';
    setTimeout(() => {
        btn.textContent = originalText;
        btn.style.background = '';
    }, 1500);
}

// ============== EXPORT/IMPORT CODE ==============
function exportCode() {
    const code = document.getElementById('codeEditor').value;
    if (!code.trim()) {
        showToast('No code to export');
        return;
    }
    toggleExportModal();
}

function toggleExportModal() {
    const modal = document.getElementById('exportModal');
    modal.classList.toggle('active');
    if (modal.classList.contains('active')) {
        document.getElementById('exportFilename').focus();
        document.getElementById('exportFilename').select();
    }
}

function closeExportModal(event) {
    if (event.target.id === 'exportModal') {
        toggleExportModal();
    }
}

function saveExportFile() {
    const code = document.getElementById('codeEditor').value;
    let filename = document.getElementById('exportFilename').value.trim() || 'program';

    if (!filename.endsWith('.asm')) {
        filename += '.asm';
    }

    const blob = new Blob([code], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);

    toggleExportModal();
    showToast(`Exported as ${filename}`);
}

function importCode() {
    document.getElementById('fileInput').click();
}

function handleFileImport(event) {
    const file = event.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = function (e) {
        document.getElementById('codeEditor').value = e.target.result;
        updateLineNumbers();
        showToast('Code imported!');
    };
    reader.readAsText(file);
    event.target.value = ''; // Reset for re-import
}

// ============== STALL/FORWARD INDICATORS ==============
function updateHazardIndicators(state) {
    const stallInd = document.getElementById('stallIndicator');
    const fwdInd = document.getElementById('forwardIndicator');

    // Stall indicator
    if (state.is_stalling || state.stall_info) {
        stallInd.style.display = 'inline-block';
        if (state.stall_info) {
            stallInd.title = `${state.stall_info.type}: ${state.stall_info.reason || ''}`;
        }
    } else {
        stallInd.style.display = 'none';
    }

    // Forward indicator
    if (state.forward_a || state.forward_b) {
        fwdInd.style.display = 'inline-block';
        let fwdInfo = [];
        if (state.forward_a) fwdInfo.push(`A: ${state.forward_a.source} → ${state.forward_a.reg}`);
        if (state.forward_b) fwdInfo.push(`B: ${state.forward_b.source} → ${state.forward_b.reg}`);
        fwdInd.title = fwdInfo.join(', ');
    } else {
        fwdInd.style.display = 'none';
    }
}

function updateLineNumbers() {
    const editor = document.getElementById('codeEditor');
    const lineNums = document.getElementById('lineNumbers');
    const lines = editor.value.split('\n');
    sourceLines = lines;

    lineNums.innerHTML = lines.map((_, i) => {
        const isCurrent = i === currentPC && machineCode.length > 0;
        return `<div class="line-num ${isCurrent ? 'current' : ''}">
                    ${isCurrent ? '<span class="arrow">▶</span>' : ''}
                    ${i}
                </div>`;
    }).join('');
}

function syncScroll() {
    const editor = document.getElementById('codeEditor');
    const lineNums = document.getElementById('lineNumbers');
    lineNums.scrollTop = editor.scrollTop;
}


// ============== TIMELINE FUNCTIONS ==============
function updateTimeline(history, stallHistory = [], forwardHistory = []) {
    const container = document.getElementById('timelineContainer');

    if (!history || history.length === 0) {
        container.innerHTML = '<div class="mc-empty">Assemble ve Step yaparak timeline\'ı görün</div>';
        return;
    }

    // Build instruction list from history (order of first appearance)
    const instrList = [];
    const instrSet = new Set();
    history.forEach(snap => {
        ['IF', 'ID', 'EX', 'MEM', 'WB'].forEach(stage => {
            if (snap[stage] && !instrSet.has(snap[stage])) {
                instrSet.add(snap[stage]);
                instrList.push({
                    hex: snap[stage],
                    disasm: instructionMap[snap[stage]] || snap[stage]
                });
            }
        });
    });

    // For each instruction, find the FIRST cycle it appears in each stage
    // This ensures IF appears only once per instruction
    const instrTimeline = new Map();
    instrList.forEach(instr => {
        instrTimeline.set(instr.hex, {
            disasm: instr.disasm,
            stages: {} // cycle -> stage mapping
        });
    });

    // Track first IF and WB occurrence for each instruction
    const firstIFCycle = new Map();
    const firstWBCycle = new Map();

    history.forEach(snap => {
        const cycle = snap.cycle;

        // Process each stage
        ['IF', 'ID', 'EX', 'MEM', 'WB'].forEach(stage => {
            const hexCode = snap[stage];
            if (!hexCode) return;

            const timeline = instrTimeline.get(hexCode);
            if (!timeline) return;

            if (stage === 'IF') {
                // Only record IF for first occurrence
                if (!firstIFCycle.has(hexCode)) {
                    firstIFCycle.set(hexCode, cycle);
                    timeline.stages[cycle] = stage;
                }
            } else if (stage === 'WB') {
                // Only record WB for first occurrence
                if (!firstWBCycle.has(hexCode)) {
                    firstWBCycle.set(hexCode, cycle);
                    timeline.stages[cycle] = stage;
                }
            } else {
                // For ID/EX/MEM, always record
                timeline.stages[cycle] = stage;
            }
        });
    });

    const maxCycle = Math.max(...history.map(h => h.cycle));
    const stallSet = new Set(stallHistory);

    // Header row with cycle numbers
    let html = `<div class="timeline-header">
                <div class="timeline-label">Instruction</div>
                <div class="timeline-cycles">
                    ${Array.from({ length: maxCycle }, (_, i) =>
        `<div class="timeline-cycle-num">${i + 1}</div>`
    ).join('')}
                </div>
            </div>`;

    // Row for each instruction
    instrList.forEach(instr => {
        const timeline = instrTimeline.get(instr.hex);
        html += `<div class="timeline-row">
                    <div class="timeline-instr" title="${instr.disasm}">${instr.disasm}</div>
                    <div class="timeline-stages">`;

        for (let c = 1; c <= maxCycle; c++) {
            const stage = timeline.stages[c] || '';
            let stageClass = stage ? stage.toLowerCase() : 'empty';

            // Check for stall at this cycle
            if (stallSet.has(c) && stage === 'ID') {
                stageClass += ' stall';
            }

            html += `<div class="timeline-cell ${stageClass}">${stage}</div>`;
        }

        html += `</div></div>`;
    });

    container.innerHTML = html;
}

// ============== FORWARDING VISUALIZATION ==============
function updateForwardingDisplay(forwardA, forwardB, isStalling) {
    const exStage = document.getElementById('stage-ex');
    const idStage = document.getElementById('stage-id');

    // Reset classes
    exStage.classList.remove('forwarding', 'stalled');
    idStage.classList.remove('stalled');

    // Remove old stall badge
    const oldStallBadge = document.querySelector('.stall-badge');
    if (oldStallBadge) oldStallBadge.remove();

    // Show forwarding
    if (forwardA || forwardB) {
        exStage.classList.add('forwarding');
    }

    // Show stall
    if (isStalling) {
        idStage.classList.add('stalled');
        const badge = document.createElement('div');
        badge.className = 'stall-badge';
        badge.textContent = 'STALL';
        idStage.style.position = 'relative';
        idStage.appendChild(badge);
    }
}


function initRegisters() {
    const grid = document.getElementById('registersGrid');
    grid.innerHTML = '';
    for (let i = 0; i < 8; i++) {
        const item = document.createElement('div');
        item.className = 'register-item' + (i === 0 ? ' zero' : '');
        item.id = `reg-${i}`;
        item.innerHTML = `
                    <span class="reg-name">$r${i}</span>
                    <div class="reg-values">
                        <div class="reg-dec">0</div>
                        <div class="reg-hex">0x0000</div>
                    </div>
                `;
        grid.appendChild(item);
    }
}

function updateRegisters(registers) {
    for (let i = 0; i < 8; i++) {
        const item = document.getElementById(`reg-${i}`);
        const val = registers[i];
        const hex = val.toString(16).toUpperCase().padStart(4, '0');

        // Convert to signed 16-bit value for display
        const signedVal = val > 32767 ? val - 65536 : val;

        if (registers[i] !== previousRegisters[i] && i !== 0) {
            item.classList.add('updated');
            setTimeout(() => item.classList.remove('updated'), 600);
        }

        item.querySelector('.reg-dec').textContent = signedVal;
        item.querySelector('.reg-hex').textContent = `0x${hex}`;
    }
    previousRegisters = [...registers];
}

function updatePipeline(state) {
    // First 4 stages from current pipeline registers
    const stages = [
        { id: 'if', data: state.IF_ID },
        { id: 'id', data: state.ID_EX },
        { id: 'ex', data: state.EX_MEM },
        { id: 'mem', data: state.MEM_WB }
    ];

    stages.forEach(({ id, data }) => {
        const stage = document.getElementById(`stage-${id}`);
        const instr = document.getElementById(`${id}-instr`);
        if (data?.valid) {
            instr.textContent = data.disasm || '—';
            instr.classList.remove('nop');
            stage.classList.add('active');
        } else {
            instr.textContent = '—';
            instr.classList.add('nop');
            stage.classList.remove('active');
        }
    });

    // WB stage shows what was in MEM_WB last cycle (it just completed WB)
    const wbStage = document.getElementById('stage-wb');
    const wbInstr = document.getElementById('wb-instr');
    if (lastMemWb?.valid) {
        wbInstr.textContent = lastMemWb.disasm || '—';
        wbInstr.classList.remove('nop');
        wbStage.classList.add('active');
    } else {
        wbInstr.textContent = '—';
        wbInstr.classList.add('nop');
        wbStage.classList.remove('active');
    }
    // Save current MEM_WB for next cycle's WB display
    lastMemWb = state.MEM_WB ? { ...state.MEM_WB } : null;

    // Forwarding elements
    const fwdExmem = document.getElementById('fwd-exmem');
    const fwdMemwb = document.getElementById('fwd-memwb');
    const exStage = document.getElementById('stage-ex');
    const memStage = document.getElementById('stage-mem');
    const arrowExMem = document.getElementById('arrow-ex-mem');
    const arrowMemWb = document.getElementById('arrow-mem-wb');

    // Reset all forwarding visuals
    fwdExmem.classList.remove('active');
    fwdMemwb.classList.remove('active');
    exStage.classList.remove('forwarding', 'fwd-dest');
    memStage.classList.remove('fwd-source');
    wbStage.classList.remove('fwd-source');
    arrowExMem.classList.remove('fwd-active');
    arrowMemWb.classList.remove('fwd-active');

    // Helper to check forwarding source
    const getFwdSource = (fwd) => fwd?.source || fwd;
    const fwdASource = getFwdSource(state.forward_a);
    const fwdBSource = getFwdSource(state.forward_b);

    // Show forwarding if active
    if (state.forward_a || state.forward_b) {
        exStage.classList.add('forwarding', 'fwd-dest');

        // EX_MEM forwarding (MEM -> EX)
        if (fwdASource === 'EX_MEM' || fwdBSource === 'EX_MEM') {
            fwdExmem.classList.add('active');
            memStage.classList.add('fwd-source');
            arrowExMem.classList.add('fwd-active');
            arrowExMem.textContent = '←';

            // Show detailed info
            const fwd = fwdASource === 'EX_MEM' ? state.forward_a : state.forward_b;
            if (fwd?.reg) {
                fwdExmem.textContent = `MEM → EX: ${fwd.reg} = ${fwd.value}`;
            }
        } else {
            arrowExMem.textContent = '→';
            fwdExmem.textContent = 'MEM → EX Forwarding';
        }

        // MEM_WB forwarding (WB -> EX)
        if (fwdASource === 'MEM_WB' || fwdBSource === 'MEM_WB') {
            fwdMemwb.classList.add('active');
            wbStage.classList.add('fwd-source');
            arrowMemWb.classList.add('fwd-active');
            arrowMemWb.textContent = '←';

            // Show detailed info
            const fwd = fwdASource === 'MEM_WB' ? state.forward_a : state.forward_b;
            if (fwd?.reg) {
                fwdMemwb.textContent = `WB → EX: ${fwd.reg} = ${fwd.value}`;
            }
        } else {
            arrowMemWb.textContent = '→';
            fwdMemwb.textContent = 'WB → EX Forwarding';
        }

    } else {
        // Reset arrows to normal
        arrowExMem.textContent = '→';
        arrowMemWb.textContent = '→';
    }

    // Hazard indicator (Load-Use / RAW)
    const hazardIndicator = document.getElementById('hazard-indicator');
    if (state.stall_info) {
        hazardIndicator.classList.add('active');
        const info = state.stall_info;
        hazardIndicator.innerHTML = `<strong>Data Hazard (RAW)</strong> — Stalling, waiting for ${info.waiting_reg} from memory`;
    } else {
        hazardIndicator.classList.remove('active');
    }

    // Control Hazard indicator (Branch/Jump)
    const controlHazardIndicator = document.getElementById('control-hazard-indicator');
    const ifStage = document.getElementById('stage-if');
    const idStage = document.getElementById('stage-id');

    if (state.control_hazard) {
        controlHazardIndicator.classList.add('active');
        const info = state.control_hazard;
        controlHazardIndicator.innerHTML = `${info.type} — Pipeline flushed, jumping to address ${info.target_address}`;

        // Flush animation on IF and ID stages
        if (state.flush_occurred) {
            ifStage.classList.add('flushed');
            idStage.classList.add('flushed');
            setTimeout(() => {
                ifStage.classList.remove('flushed');
                idStage.classList.remove('flushed');
            }, 500);
        }
    } else {

        controlHazardIndicator.classList.remove('active');
    }

    // Memory warning indicator
    const memWarning = document.getElementById('memory-warning');
    if (state.memory_warning) {
        memWarning.classList.add('active');
        const warn = state.memory_warning;
        memWarning.innerHTML = `<strong>${warn.type}</strong>: Address ${warn.address} (returns 0)`;
    } else {
        memWarning.classList.remove('active');
    }
}

function formatBinary(binary) {
    const op = binary.slice(0, 4);
    if (op === '0000') {
        return `<span class="op">${op}</span><span class="sep"> </span>` +
            `<span class="rs">${binary.slice(4, 7)}</span><span class="sep"> </span>` +
            `<span class="rt">${binary.slice(7, 10)}</span><span class="sep"> </span>` +
            `<span class="rd">${binary.slice(10, 13)}</span><span class="sep"> </span>` +
            `<span class="imm">${binary.slice(13, 16)}</span>`;
    } else if (op === '1001' || op === '1010') {
        return `<span class="op">${op}</span><span class="sep"> </span>` +
            `<span class="imm">${binary.slice(4, 16)}</span>`;
    } else {
        return `<span class="op">${op}</span><span class="sep"> </span>` +
            `<span class="rs">${binary.slice(4, 7)}</span><span class="sep"> </span>` +
            `<span class="rt">${binary.slice(7, 10)}</span><span class="sep"> </span>` +
            `<span class="imm">${binary.slice(10, 16)}</span>`;
    }
}

// Get instruction type from binary opcode
function getInstrType(binary) {
    const op = binary.slice(0, 4);
    if (op === '0000') return { type: 'R-Type', class: 'r-type' };
    if (op === '1001' || op === '1010') return { type: 'J-Type', class: 'j-type' };
    return { type: 'I-Type', class: 'i-type' };
}

function updateInstrMemory(instructions, pc) {
    const list = document.getElementById('instrMemList');
    if (!instructions?.length) {
        list.innerHTML = '<div class="mc-empty">Click "Assemble" to load</div>';
        return;
    }

    list.innerHTML = instructions.map((instr, i) => {
        const instrType = getInstrType(instr.binary);
        return `
                <div class="mc-item ${i === pc ? 'current ' + instrType.class : ''}">
                    <div class="mc-header">
                        <span class="mc-addr">
                            ${i === pc ? '<span class="arrow">▶</span>' : ''}
                            ${String(instr.address).padStart(2, '0')}
                        </span>
                        <span class="instr-type ${instrType.class}">${instrType.type}</span>
                        <span class="mc-asm">${instr.disasm || instr.source}</span>
                    </div>
                    <div class="mc-binary"><span class="mc-bin-part">${formatBinary(instr.binary)}</span><span class="mc-hex-code">0x${instr.hex}</span></div>
                </div>
            `}).join('');
}

function updateDataMemory(memory) {
    const list = document.getElementById('dataMemList');
    const entries = Object.entries(memory);

    if (!entries.length) {
        list.innerHTML = '<div class="mem-empty">No data stored</div>';
        return;
    }

    list.innerHTML = entries
        .sort((a, b) => parseInt(a[0]) - parseInt(b[0]))
        .map(([addr, val]) => `
                    <div class="mem-item">
                        <span class="mem-addr">[${parseInt(addr).toString().padStart(3, '0')}]</span>
                        <span class="mem-hex">0x${val.toString(16).toUpperCase().padStart(4, '0')}</span>
                        <span class="mem-dec">${val}</span>
                    </div>
                `).join('');
}

function setStatus(status, text, isHalted = false) {
    const badge = document.getElementById('statusBadge');
    badge.className = 'status-badge' + (isHalted ? ' halted' : '');
    document.getElementById('statusText').textContent = text;
}

function showToast(msg) {
    const toast = document.getElementById('toast');
    toast.textContent = msg;
    toast.classList.add('show');
    setTimeout(() => toast.classList.remove('show'), 4000);
}

function updateCPUState(state) {
    currentPC = state.pc;
    document.getElementById('cycleCount').textContent = state.cycle;
    document.getElementById('pcValue').textContent = state.pc;
    updateRegisters(state.registers);
    updatePipeline(state);
    updateDataMemory(state.data_memory);
    updateLineNumbers();
    if (machineCode.length) updateInstrMemory(machineCode, state.pc);

    // Update timeline with pipeline history
    if (state.pipeline_history) {
        updateTimeline(state.pipeline_history, state.stall_history || [], state.forward_history || []);
    }

    // Update forwarding and stall display
    updateForwardingDisplay(state.forward_a, state.forward_b, state.is_stalling);

    // Update hazard indicators
    updateHazardIndicators(state);

    // Update performance metrics
    if (state.performance) {
        const perf = state.performance;
        document.getElementById('perfCPI').textContent = perf.instructions > 0 ? perf.cpi.toFixed(2) : '-';
        document.getElementById('perfStallRate').textContent = perf.stall_rate.toFixed(1) + '%';
        document.getElementById('perfForwardRate').textContent = perf.forward_rate.toFixed(1) + '%';
        document.getElementById('perfFlushCount').textContent = perf.flush_count || 0;
    }
}

// API Functions
async function assembleCode() {
    const code = document.getElementById('codeEditor').value;
    setStatus('running', 'Assembling...');

    try {
        const res = await fetch('/assemble', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ code })
        });
        const data = await res.json();

        if (data.success) {
            machineCode = data.machine_code;
            currentPC = 0;
            pipelineHistory = []; // Reset timeline
            lastMemWb = null;     // Reset WB stage tracking

            // Build instruction map for timeline display
            instructionMap = {};
            machineCode.forEach(instr => {
                instructionMap[instr.hex] = instr.disasm;
            });

            updateInstrMemory(machineCode, 0);
            updateCPUState(data.cpu_state);
            document.getElementById('btnStep').disabled = false;
            document.getElementById('btnRunStop').disabled = false;
            setStatus('ready', `${machineCode.length} Instructions`);
        } else {
            showToast(data.error);
            setStatus('error', 'Error');
        }
    } catch (e) {
        showToast('Network error');
    }
}

async function stepCPU() {
    try {
        const res = await fetch('/step', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });
        const data = await res.json();

        if (data.success) {
            updateCPUState(data.cpu_state);
            // Enable step back button if we have history
            document.getElementById('btnStepBack').disabled = !data.can_step_back;
            if (!data.running) {
                setStatus('halted', 'Halted', true);
                document.getElementById('btnStep').disabled = true;
                document.getElementById('btnRunStop').disabled = true;
            } else {
                setStatus('ready', `Cycle ${data.cpu_state.cycle}`);
            }
        } else {
            showToast(data.error);
        }
    } catch (e) {
        showToast('Network error');
    }
}

async function stepBackCPU() {
    try {
        const res = await fetch('/step_back', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });
        const data = await res.json();

        if (data.success) {
            // Reset lastMemWb when stepping back to fix pipeline visualization
            lastMemWb = null;
            updateCPUState(data.cpu_state);
            // Update button states
            document.getElementById('btnStepBack').disabled = !data.can_step_back;
            document.getElementById('btnStep').disabled = false;
            document.getElementById('btnRunStop').disabled = false;
            setStatus('ready', `Cycle ${data.cpu_state.cycle}`);
        } else {
            showToast(data.error);
        }
    } catch (e) {
        showToast('Network error');
    }
}

function toggleRunStop() {
    if (isRunning) {
        stopRun();
    } else {
        runAll();
    }
}

async function runAll() {
    if (isRunning) return;

    isRunning = true;
    const btn = document.getElementById('btnRunStop');
    const btnStep = document.getElementById('btnStep');

    // Switch to Stop mode
    btn.classList.remove('btn-warning');
    btn.classList.add('btn-stop', 'running');
    document.getElementById('iconRun').style.display = 'none';
    document.getElementById('iconStop').style.display = 'block';
    document.getElementById('btnRunStopText').textContent = 'Stop';
    btnStep.disabled = true;
    setStatus('running', 'Running...');

    const runStep = async () => {
        if (!isRunning) return;

        try {
            const res = await fetch('/step', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' }
            });
            const data = await res.json();

            if (data.success) {
                updateCPUState(data.cpu_state);

                if (!data.running) {
                    stopRun();
                    setStatus('halted', 'Halted', true);
                    btnStep.disabled = true;
                    btn.disabled = true;
                } else {
                    setStatus('running', `Cycle ${data.cpu_state.cycle}`);
                    // Schedule next step
                    const delay = parseInt(document.getElementById('speedSlider').value);
                    runIntervalId = setTimeout(runStep, delay);
                }
            } else {
                stopRun();
                showToast(data.error);
            }
        } catch (e) {
            stopRun();
            showToast('Network error');
        }
    };

    // Start first step immediately
    runStep();
}

function stopRun() {
    isRunning = false;
    if (runIntervalId) {
        clearTimeout(runIntervalId);
        runIntervalId = null;
    }

    const btn = document.getElementById('btnRunStop');
    const btnStep = document.getElementById('btnStep');

    // Switch back to Run mode
    btn.classList.remove('btn-stop', 'running');
    btn.classList.add('btn-warning');
    document.getElementById('iconRun').style.display = 'block';
    document.getElementById('iconStop').style.display = 'none';
    document.getElementById('btnRunStopText').textContent = 'Run';

    // Re-enable buttons if not halted
    const statusText = document.getElementById('statusText').textContent;
    if (statusText !== 'Halted') {
        btnStep.disabled = false;
        setStatus('ready', 'Stopped');
    }
}

function updateSpeedDisplay() {
    const slider = document.getElementById('speedSlider');
    const display = document.getElementById('speedValue');
    display.textContent = slider.value + 'ms';
}

async function resetCPU() {
    try {
        const res = await fetch('/reset', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        });
        const data = await res.json();

        if (data.success) {
            currentPC = 0;
            lastMemWb = null; // Reset WB stage tracking
            updateCPUState(data.cpu_state);
            previousRegisters = [0, 0, 0, 0, 0, 0, 0, 0];
            // Disable step back since history is cleared on reset
            document.getElementById('btnStepBack').disabled = true;
            if (machineCode.length) {
                document.getElementById('btnStep').disabled = false;
                document.getElementById('btnRunStop').disabled = false;
                updateInstrMemory(machineCode, 0);
            }
            setStatus('ready', 'Reset');
        }
    } catch (e) {
        showToast('Network error');
    }
}
