// Gleamunison Console Dashboard

// Tab switching
function switchTab(tabName) {
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
  const btn = document.querySelector(`.tab-btn[data-tab="${tabName}"]`);
  if (btn) btn.classList.add('active');
  const content = document.getElementById(`tab-${tabName}`);
  if (content) content.classList.add('active');
}

document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => switchTab(btn.dataset.tab));
});

// SSE connection
let eventSource = null;
function connectSSE() {
  if (eventSource) eventSource.close();
  eventSource = new EventSource('/api/events');
  eventSource.addEventListener('module_loaded', e => {
    const d = JSON.parse(e.data);
    addTimelineEntry(`Module loaded: ${d.name} (${d.hash})`, 'info');
    updateStats();
  });
  eventSource.addEventListener('eval_completed', e => {
    const d = JSON.parse(e.data);
    addTimelineEntry(`Eval: ${d.expr} => ${d.result}`, 'info');
  });
  eventSource.addEventListener('definition_added', e => {
    const d = JSON.parse(e.data);
    addTimelineEntry(`Defined: ${d.name}`, 'info');
    updateDefinitions();
  });
  eventSource.addEventListener('redefinition', e => {
    const d = JSON.parse(e.data);
    addTimelineEntry(`Redefined: ${d.name} (${d.old_hash} -> ${d.new_hash})`, 'warn');
    updateRedefinitions();
  });
  eventSource.onerror = () => {
    addTimelineEntry('SSE connection lost, reconnecting...', 'error');
    setTimeout(connectSSE, 3000);
  };
}

// Timeline for sync/log tabs
function addTimelineEntry(msg, level) {
  const tl = document.getElementById('timeline');
  if (!tl) return;
  const entry = document.createElement('div');
  entry.className = `timeline-entry ${level}`;
  entry.textContent = new Date().toISOString().split('T')[1].slice(0,8) + ' ' + msg;
  tl.prepend(entry);
  if (tl.children.length > 100) tl.removeChild(tl.lastChild);
}

// Expression eval
function evalExpr() {
  const expr = document.getElementById('expr').value;
  if (!expr) return;
  const result = document.getElementById('result');
  result.className = 'repl-result';
  result.textContent = 'Evaluating...';
  fetch('/eval?expr=' + encodeURIComponent(expr))
    .then(r => r.json())
    .then(d => {
      if (d.result) {
        result.className = 'repl-result success';
        result.textContent = d.result;
      } else if (d.error) {
        result.className = 'repl-result error';
        result.textContent = d.error;
      }
    })
    .catch(err => {
      result.className = 'repl-result error';
      result.textContent = 'Network error: ' + err;
    });
}

// Define in notebook
function defineExpr() {
  const name = document.getElementById('def-name').value.trim();
  const expr = document.getElementById('def-expr').value.trim();
  if (!name || !expr) return;
  fetch('/define?name=' + encodeURIComponent(name) + '&expr=' + encodeURIComponent(expr))
    .then(r => r.json())
    .then(d => {
      if (d.status === 'defined') {
        const feedback = document.getElementById('def-feedback');
        feedback.textContent = `Defined: ${d.name}`;
        feedback.style.color = '#4ade80';
        updateDefinitions();
      } else if (d.error) {
        const feedback = document.getElementById('def-feedback');
        feedback.textContent = 'Error: ' + d.error;
        feedback.style.color = '#f87171';
      }
    });
}

// Status updates
function updateStats() {
  fetch('/api/status')
    .then(r => r.json())
    .then(d => {
      document.getElementById('stat-node').textContent = d.node;
      document.getElementById('stat-mem').textContent = d.memory_mb + ' MB';
      document.getElementById('stat-uptime').textContent = d.uptime_sec + 's';
      document.getElementById('stat-os').textContent = d.os;
      updateModuleList(d.loaded_modules || []);
    })
    .catch(e => console.error('Status fetch failed', e));
}

function updateModuleList(modules) {
  const listDiv = document.getElementById('module-list');
  if (!listDiv) return;
  listDiv.innerHTML = '';
  if (modules.length === 0) {
    listDiv.innerHTML = '<div style="color:var(--text-muted);font-size:0.85rem;">No compiled modules loaded</div>';
  } else {
    modules.forEach(m => {
      const item = document.createElement('div');
      item.className = 'module-item';
      const name = typeof m === 'string' ? m : (m.name || m);
      const hash = typeof m === 'object' ? m.hash : '';
      const beamTag = typeof m === 'object' && m.diagnostics ? m.diagnostics : 'BEAM';
      item.innerHTML = '<span>' + name + (hash ? ' <span class="module-hash">' + hash + '</span>' : '') + '</span><span class="module-tag">' + beamTag + '</span>';
      listDiv.appendChild(item);
    });
  }
}

// Processes
function updateProcesses() {
  fetch('/api/processes')
    .then(r => r.json())
    .then(d => {
      const el = document.getElementById('process-list');
      if (!el) return;
      el.innerHTML = '<div style="color:var(--text-muted);font-size:0.75rem;margin-bottom:8px;">' + d.total_count + ' processes, ' + d.total_memory_kb + ' KB</div>';
      (d.processes || []).forEach(p => {
        const item = document.createElement('div');
        item.className = 'process-item';
        item.innerHTML = '<span class="process-pid">' + p.pid + '</span><span class="process-name">' + (p.name || '-') + '</span><span class="process-mem">' + p.memory_kb + ' KB</span>';
        el.appendChild(item);
      });
    });
}

// Definitions browser
function updateDefinitions() {
  fetch('/browse')
    .then(r => r.json())
    .then(d => {
      const el = document.getElementById('definitions-list');
      if (!el) return;
      el.innerHTML = '';
      (d.defs || []).forEach(def => {
        const item = document.createElement('div');
        item.className = 'def-item';
        item.innerHTML = '<span class="def-name">' + def.name + '</span><div class="def-expr">' + (def.expr || '') + '</div>';
        item.onclick = () => {
          document.getElementById('def-name').value = def.name;
          document.getElementById('def-expr').value = def.expr || '';
          switchTab('definitions');
        };
        el.appendChild(item);
      });
    });
}

// Sync status
function updateSyncStatus() {
  fetch('/api/sync-status')
    .then(r => r.json())
    .then(d => {
      document.getElementById('sync-genesis').textContent = d.genesis_count;
      document.getElementById('sync-notebook').textContent = d.notebook_defs;
      document.getElementById('sync-loaded').textContent = d.loaded_modules;
      document.getElementById('sync-beams').textContent = d.beams_loaded;
    });
}

// Redefinitions
function updateRedefinitions() {
  fetch('/api/redefinitions?limit=20')
    .then(r => r.json())
    .then(d => {
      const el = document.getElementById('redef-list');
      if (!el) return;
      el.innerHTML = '';
      (d.events || []).forEach(e => {
        const item = document.createElement('div');
        item.className = 'timeline-entry warn';
        item.textContent = e.timestamp + ' ' + e.name + ' (elapsed: ' + e.elapsed_ms + 'ms)';
        el.appendChild(item);
      });
    });
}

// Logs
function updateLogs() {
  fetch('/api/logs?limit=50')
    .then(r => r.json())
    .then(d => {
      const el = document.getElementById('log-viewer');
      if (!el) return;
      el.innerHTML = '';
      (d.entries || []).forEach(e => {
        const entry = document.createElement('div');
        entry.className = 'timeline-entry ' + (e.level || 'info');
        entry.textContent = e.timestamp + ' [' + (e.level || 'info') + '] ' + (e.message || '');
        el.appendChild(entry);
      });
    });
}

// Periodic refresh
function refreshAll() {
  updateStats();
  updateProcesses();
  updateSyncStatus();
  updateRedefinitions();
  updateLogs();
}

// Init
connectSSE();
refreshAll();
setInterval(refreshAll, 5000);
