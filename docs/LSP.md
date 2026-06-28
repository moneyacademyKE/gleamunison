# Gleamunison LSP Server

## Architecture

The Gleamunison Language Server Protocol backend provides IDE integration
for autocomplete, go-to-definition, hover-type, and inline diagnostics.

### Protocol

The LSP server communicates over stdio using JSON-RPC 2.0. It implements
the following capabilities:

| Capability | Status | Description |
|---|---|---|
| `textDocument/completion` | Planned | Context-aware identifier completion |
| `textDocument/hover` | Planned | Type-on-hover information |
| `textDocument/definition` | Planned | Go-to-definition navigation |
| `textDocument/diagnostics` | Planned | Inline type errors and warnings |

### Implementation Strategy

1. **Parse current buffer** — Tokenize + parse the S-expression content
2. **Elaborate in background** — Run elaborator to produce typed AST
3. **Cache results** — Store type information per-file in ETS
4. **Respond to requests** — Look up cached information for the position

### Sever Integration

```sh
# VS Code
code --install-extension gleamunison-lsp

# Helix
[language-server.gleamunison]
command = "gleamunison"
args = ["lsp"]

# Vim/Neovim
let g:lsp_settings = {
  \ 'gleamunison': {'cmd': ['gleamunison', 'lsp']},
  \ }
```

### API Endpoints (partial, planned for v1.1)

```json
// Completion request
{"jsonrpc":"2.0","method":"textDocument/completion","params":{"textDocument":{"uri":"file:///test.gleam"},"position":{"line":10,"character":5}}}

// Completion response
{"jsonrpc":"2.0","result":[{"label":"add","detail":"Int -> Int -> Int","kind":3}]}
```
