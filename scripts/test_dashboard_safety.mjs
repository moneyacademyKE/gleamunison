import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const hostile = '<img src=x onerror=alert(1)>';
class Element {
  children = [];
  style = {};
  classList = { add() {}, remove() {} };
  appendChild(child) { this.children.push(child); }
  append(...children) { this.children.push(...children); }
  prepend(child) { this.children.unshift(child); }
  replaceChildren(...children) { this.children = children; }
  set textContent(value) { this.text = String(value); }
  get textContent() { return (this.text || '') + this.children.map(c => c.textContent || '').join(''); }
  set innerHTML(value) {
    assert.equal(String(value).includes(hostile), false, 'untrusted value became markup');
    this.children = [];
  }
  addEventListener() {}
}
const nodes = new Map();
const document = {
  getElementById(id) { if (!nodes.has(id)) nodes.set(id, new Element()); return nodes.get(id); },
  createElement() { return new Element(); },
  querySelectorAll() { return []; },
  querySelector() { return null; },
};
const data = {
  '/browse': { defs: [{ name: hostile, expr: hostile }] },
  '/api/processes': { total_count: 1, total_memory_kb: 1, processes: [{pid: hostile, name: hostile, memory_kb: 1}] },
};
function settled(value) {
  return { then(fn) { return settled(fn(value)); }, catch() { return this; } };
}
const context = {
  document, console, Date,
  EventSource: class { close() {} addEventListener() {} },
  fetch(path) { return settled({ json() { return data[path] || {}; } }); },
  setTimeout() {}, setInterval() {}, encodeURIComponent,
};
vm.runInNewContext(readFileSync('priv/static/js/dashboard.js', 'utf8'), context);
vm.runInNewContext('updateDefinitions();', context);
context.updateModuleList([{name: hostile, hash: hostile, diagnostics: hostile}]);
assert.ok(document.getElementById('definitions-list').textContent.includes(hostile));
assert.ok(document.getElementById('module-list').textContent.includes(hostile));
assert.ok(document.getElementById('process-list').textContent.includes(hostile));
console.log('dashboard hostile names/expressions/module/process values stay text: PASS');
