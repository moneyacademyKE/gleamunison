# ADR-0012: OTP 29 compile file readback pattern

**Status:** Accepted

**Date:** 2026-06-26

## Context

OTP 29 changed the return format of `compile:file/2` with the `return`
option. In OTP 26-28, the function returned either `{ok, ModuleName}` or
`{ok, ModuleName, Binary}`. In OTP 29, it returns `{ok, ModuleName, []}`
where the empty list replaces the binary — the compiled binary is written
to the output directory but not returned in the tuple.

The initial implementation assumed the binary was always returned:
```erlang
case compile:file(TmpFile, [{outdir, TmpDir}, return]) of
    {ok, _Mod, Bin} -> {ok, Bin};
    ...
end
```

This failed on OTP 29 because the `Bin` matched `[]` (an empty list), which
was then passed to `code:load_binary/3` as the BEAM binary argument. The
empty list is not a valid BEAM binary and caused `code:load_binary/3` to
fail with no matching function clause.

## Decision

Detect the OTP 29 format and read the beam file from disk when the binary
is not returned:

```erlang
{ok, _Mod} ->
    % OTP 26-28: no binary, file exists
    read_beam_file(BeamFile);
{ok, _Mod, Bin} when is_binary(Bin), byte_size(Bin) > 0 ->
    % OTP 26-28: binary returned inline
    {ok, Bin};
{ok, _Mod, _Other} ->
    % OTP 29: {ok, Mod, []} — binary on disk
    read_beam_file(BeamFile);
```

The guard `is_binary(Bin), byte_size(Bin) > 0` distinguishes between a
valid BEAM binary (non-empty binary) and the OTP 29 empty list. The file
readback path is shared between the pre-OTP 29 `{ok, Mod}` format and the
OTP 29 `{ok, Mod, []}` format.

## Consequences

**Positive:**
- Compatible with OTP 26 through OTP 29+
- No version detection needed — the guard handles all cases
- The file readback is reliable because `compile:file/2` always writes the
  output beam before returning

**Negative:**
- Slightly slower compilation (extra file read after compile)
- Temp file cleanup must happen AFTER the readback (try/after pattern)
- Race condition if another process deletes the temp directory between
  compile and readback (mitigated by using OS temp directory)

**Alternative considered:** Using `compile:forms/2` instead of
`compile:file/2` to avoid file I/O entirely. Rejected because `compile:forms/2`
requires Erlang abstract format, which means building AST tuples instead of
generating source text. Source generation is simpler and more debuggable.
