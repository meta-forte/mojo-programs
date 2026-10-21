# Mojo on Oracle Linux 9 (WSL2) — installation fixes

Date: 2026-10-21
Environment: Oracle Linux Server 9.8, WSL2 (kernel 6.6.87.2-microsoft-standard-WSL2),
glibc 2.34, Mojo 1.1.0 installed via `pip` into the venv at `~/venv`.

## Symptom

Any invocation of `mojo` failed immediately:

```
/home/manas/venv/bin/mojo: /lib64/libstdc++.so.6: version `GLIBCXX_3.4.30' not found
    (required by /home/manas/venv/bin/mojo)
```

## Root cause

Mojo's prebuilt binaries are compiled against **gcc 12 or newer**, but Oracle Linux 9
(like RHEL 9) ships a **gcc 11** C++ runtime and pins it there for the life of the
release:

```
/lib64/libstdc++.so.6 -> libstdc++.so.6.0.29      # rpm: libstdc++-11.5.0-14.0.1.el9
highest symbol version present: GLIBCXX_3.4.29
```

Checking every ELF binary and shared object shipped in
`~/venv/lib/python3.13/site-packages/modular/` showed the highest C++ symbol version
any of them references is exactly **`GLIBCXX_3.4.30`** (introduced in gcc 12). The
system library stops one version short, so the dynamic loader aborts before `main`.

### Why `dnf install gcc-toolset-15-gcc-c++` does not fix it

This was the first thing tried, and it cannot work. A gcc-toolset is a **build-time**
toolchain only — it deliberately does *not* install a newer shared C++ runtime. All it
provides is a linker script and a static archive:

```
/opt/rh/gcc-toolset-15/root/usr/lib/gcc/x86_64-redhat-linux/15/libstdc++.so   # ASCII linker script, not an ELF
/opt/rh/gcc-toolset-15/root/usr/lib/gcc/x86_64-redhat-linux/15/libstdc++_nonshared.a
```

There is no `libstdc++.so.6.0.3x` anywhere under `/opt/rh`. The toolset links the newer
ABI pieces *statically* into whatever **you** compile with it, which lets Red Hat keep a
single system `libstdc++.so.6` for the whole major release. That does nothing for an
already-compiled third-party binary like `mojo`, which resolves `GLIBCXX_3.4.30` at
runtime against `/lib64/libstdc++.so.6`.

Replacing `/lib64/libstdc++.so.6` itself was rejected as a fix: it is rpm-owned, and
overwriting it puts the system permanently at odds with `dnf`/`rpm`.

## Fix applied

Install a newer `libstdc++` **scoped to the venv** and put it ahead of the system one on
the loader path for Mojo only. Nothing system-wide is modified.

### 1. Source the library

Took the C++ runtime from the conda-forge `libstdcxx` package (gcc 14.4.0). The archive
was extracted by hand with `unzip` + `tar --zstd`; **conda / pixi was not installed**.

```
https://conda.anaconda.org/conda-forge/linux-64/libstdcxx-14.4.0-h934c35e_7.conda
```

Chosen because conda-forge builds against an old sysroot, so the library is forward-safe
on EL9. Verified before installing:

| Check | Result |
| --- | --- |
| Highest `GLIBCXX` provided | `3.4.33` (need `3.4.30`) |
| Highest `GLIBC_*` required by the library | `GLIBC_2.17` |
| System glibc | `2.34` — satisfies it |

### 2. Install into the venv

```
~/venv/lib/gcc-runtime/libstdc++.so.6.0.33
~/venv/lib/gcc-runtime/libstdc++.so.6 -> libstdc++.so.6.0.33
```

### 3. Put it on the loader path on activation

`~/venv/bin/activate` was patched to export `LD_LIBRARY_PATH`, with matching teardown in
its `deactivate()` function so the variable is restored (not leaked) on exit:

```sh
# Newer libstdc++ (GLIBCXX_3.4.30+) required by the Mojo toolchain; EL9 ships 3.4.29.
_OLD_VIRTUAL_LD_LIBRARY_PATH="x${LD_LIBRARY_PATH:-}"
LD_LIBRARY_PATH="$VIRTUAL_ENV/lib/gcc-runtime${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
```

A backup of the original sits at `~/venv/bin/activate.bak.pre-libstdcxx`.

A dedicated `gcc-runtime/` subdirectory is used rather than `~/venv/lib` itself, so only
this one library is exposed to the dynamic loader.

## Verification

In a fresh login shell with `LD_LIBRARY_PATH` unset, after `source ~/venv/bin/activate`:

- `mojo --version` -> `Mojo 1.1.0 (8189361e)`
- `mojo run t.mojo` -> ran correctly (JIT path)
- `mojo build t.mojo -o t_bin && ./t_bin` -> ran correctly (AOT path)
- `mojo run L01.mojo` -> `Hello, World!`
- `deactivate` -> `LD_LIBRARY_PATH` restored to empty

## Notes / gotchas

- **Running `mojo` without activating the venv** bypasses the fix. Either activate first,
  or prefix the call:
  `LD_LIBRARY_PATH=~/venv/lib/gcc-runtime ~/venv/bin/mojo run file.mojo`
- **`gcc-toolset-15-gcc-c++` is not needed for Mojo** and can be removed
  (`sudo dnf remove gcc-toolset-15-gcc-c++`) to reclaim the disk it uses.
- **Mojo 1.1.0 removed `fn`** — top-level functions use `def`. Code written as
  `fn main():` fails with `'fn' has been removed; use 'def' instead`. This is unrelated
  to the library problem but was hit while testing.
- If a future Mojo release requires a symbol above `GLIBCXX_3.4.33`, drop a newer
  `libstdc++.so.6.0.xx` into `~/venv/lib/gcc-runtime/` and repoint the symlink; no other
  change is needed.

## Rollback

```sh
rm -rf ~/venv/lib/gcc-runtime
mv ~/venv/bin/activate.bak.pre-libstdcxx ~/venv/bin/activate
```

---

# Follow-up: VS Code "mojo-lsp failed to start" (same day)

## Symptom

The Mojo extension (`modular-mojotools.vscode-mojo-26.6.1`) repeatedly failed to start the
language server. From
`~/.vscode-server/data/logs/<ts>/exthost1/output_logging_<ts>/2-Mojo Language Server.log`:

```
/home/manas/mojo-programs/.venv/bin/mojo-lsp-server: /lib64/libstdc++.so.6: version `GLIBCXX_3.4.30' not found
[Error] Server process exited with code 1.
[Error] The Mojo Language Client server crashed 5 times in the last 3 minutes. The server will not be restarted.
```

## Root cause

Same missing `GLIBCXX_3.4.30` as above, reached by a different route:

1. The venv fix relied on `LD_LIBRARY_PATH`, which is exported only by
   `~/venv/bin/activate`. VS Code's **extension host never sources `activate`**, so it
   spawns `mojo-lsp-server` with the system loader path and the binary dies instantly.
2. The extension offers no way to inject environment variables — its only relevant
   settings are `mojo.sdk.path`, `mojo.preferWorkspaceEnv`, `mojo.preferPixiEnv`,
   `mojo.lsp.includeDirs`. There is no `mojo.lsp.env`.

The log path `/home/manas/mojo-programs/.venv` is **not** a second install —
`~/mojo-programs/.venv` is a symlink to `~/venv`, which the extension auto-detected via
`Found workspace uv/venv with Mojo SDK at ...`.

An env-var-based fix is therefore structurally inadequate: anything that spawns Mojo
outside an activated shell (VS Code, a GUI launcher, systemd, cron) breaks.

## Fix applied

Every Mojo ELF already ships `$ORIGIN/../lib` as the first entry of its RUNPATH:

```
modular/bin/mojo-lsp-server    RPATH=[$ORIGIN/../lib:...]
modular/lib/libMojoLLDB.so     RPATH=[$ORIGIN:$ORIGIN/../lib:...]
```

`DT_RUNPATH` is searched **before** `ld.so.cache`, so a library dropped into
`modular/lib/` wins over `/lib64` for these binaries only. One relative symlink is
therefore the whole fix — no env var, no `patchelf`, no system change:

```sh
cd ~/venv/lib/python3.13/site-packages/modular/lib
ln -sfn ../../../../gcc-runtime/libstdc++.so.6.0.33 libstdc++.so.6
```

The real file deliberately stays in `~/venv/lib/gcc-runtime/` (not pip-managed, so it
survives a `pip install --upgrade mojo`); only the symlink lives inside the pip-managed
tree.

After that, VS Code needed a **window reload** — the client had hit its "crashed 5 times
... will not be restarted" state and does not retry on its own.

## Verification

With `LD_LIBRARY_PATH` explicitly removed from the environment (`env -u`):

- `.venv/bin/mojo-lsp-server --version` -> `LLVM version 24.0.0git`
- A real LSP `initialize` request over stdio returned a 871-byte result advertising
  `textDocumentSync`, `hoverProvider`, `completionProvider`, `definitionProvider`,
  `codeActionProvider`
- `mojo run L01.mojo` -> `Hello, World!`
- `ldd` on `mojo`, `mojo-lsp-server`, `lld`, `gpu-query`, `llvm-symbolizer`: zero
  unresolved symbols, `libstdc++.so.6` resolving to `modular/bin/../lib/libstdc++.so.6`

The `activate` export from the earlier fix was left in place as harmless redundancy; the
RUNPATH symlink is now the authoritative mechanism.

## LLDB debugger: missing `libbsd` (resolved)

`mojo-lldb`, `lldb-dap`, `lldb-server` and `lldb-argdumper` had one unresolved dependency
unrelated to libstdc++, which would have broken the VS Code **debugger** (not the LSP,
not the compiler):

```
libbsd.so.0 => not found
```

`libbsd` is absent from the base OL9 repos but present in EPEL, already enabled here as
`ol9_developer_EPEL`. Fixed with:

```sh
sudo dnf install -y libbsd      # libbsd-0.12.2-1.el9.x86_64
```

### No `activate` / path changes were needed for this one

Unlike libstdc++, this needed no wiring at all. The distinction is worth remembering:

| | libstdc++ | libbsd |
| --- | --- | --- |
| Problem | rpm-pinned library is **too old** (3.4.29 vs 3.4.30 needed) | library is simply **absent** |
| Can dnf fix it? | No — EL9 pins it for the release | Yes — EPEL has it |
| Where it lands | had to be side-loaded into the venv | `/usr/lib64/libbsd.so.0`, a default loader dir |
| Wiring needed | RUNPATH symlink (see above) | none — `ldconfig -p` already lists it |

Confirmed registered in the loader cache:

```
libbsd.so.0 (libc6,x86-64) => /lib64/libbsd.so.0
```

### Verification

With `LD_LIBRARY_PATH` explicitly stripped (`env -u`):

- `ldd` on `mojo-lldb`, `lldb-dap`, `lldb-server`, `lldb-argdumper`: **0 unresolved**
- `mojo-lldb --version` -> `lldb version 24.0.0git`
- Real debug session on an AOT build (`mojo build -g L01.mojo -o /tmp/l01dbg`), breakpoint
  hit with Mojo-level source resolution:

```
* thread #1, name = 'l01dbg', stop reason = breakpoint 1.1
    frame #0: 0x40121b l01dbg`main at _startup.mojo:41:6
    frame #1: libc.so.6`__libc_start_call_main + 128
(lldb) continue
Hello, World!
Process exited with status = 0
```

### Harmless warning you can ignore

LLDB prints these on every launch:

```
/lib64/libncurses.so.6: no version information available (required by .../liblldb24.0.0git.so)
/lib64/libtinfo.so.6: no version information available
/lib64/libpanel.so.6: no version information available
```

They are warnings, not errors — EL9 builds ncurses without symbol versioning, while the
prebuilt LLDB expects versioned symbols. The symbols resolve fine; `mojo-lldb` exits 0 and
debugging works. Nothing to fix.
