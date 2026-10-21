 You extracted the Mojo learning material into @/mojo-src/ from the source zip file.

  ┌──────────────────────────────────────┬────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
  │                Folder                │  Size  │                                                                                          What it's for                                                                                           │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ docs/manual/                         │ 3.4 MB │ The Mojo Manual, the main tutorial: basics, variables, types, functions, structs, traits, generics, parameters, pointers, errors, Python interop. Start with quickstart.mdx and get-started.mdx. │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ docs/reference/                      │ 2.5 MB │ Language reference: keywords, operators, literals, numeric types, decorators, cheat sheets.                                                                                                      │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ docs/code/                           │ 1.6 MB │ Runnable code samples used in the docs.                                                                                                                                                          │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ docs/tools/                          │ 788 KB │ How to use the mojo command line, testing, debugging, packaging.                                                                                                                                 │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ docs/faq.md, roadmap.mdx, vision.mdx │ small  │ Background on where the language is headed.                                                                                                                                                      │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ stdlib/std/                          │ 4.5 MB │ Standard library source in Mojo, the authoritative answer to "what does this API look like".                                                                                                     │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ stdlib/test/                         │ 3.1 MB │ Stdlib unit tests, a good source of small usage examples for each API.                                                                                                                           │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ examples/                            │ 548 KB │ Small example projects: Game of Life, operators, Python interop, testing, and a few GPU ones.                                                                                                    │
  ├──────────────────────────────────────┼────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
  │ proposals/                           │ 732 KB │ Design documents explaining why features work the way they do.                                                                                                                                   │
  └──────────────────────────────────────┴────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

  Left out of the extraction:
  - the MAX AI framework (max/, about 150 MB uncompressed)
  - the compiler tests and tools (the compiler source itself was added later, see below)
  - the build system (Bazel)
  - the stdlib benchmarks and Unicode data tables

  The release notes are in notes/mojo-release-notes/

  The .md and .mdx files are plain Markdown and read fine in any editor; .mdx just adds a few web components.  check the docs and stdlib source there when you ask about an API.

## Compiler source: mojo-src/compiler/ (15 MB, added 2026-10-21)

Extracted later from the same zip. The C++ files carry Apache 2.0 headers.

| Folder | What it's for |
|---|---|
| compiler/Mojo/docs/compiler/ | Compiler design docs. Start with MojoCompilerWalkthrough.md (pipeline: parser -> lit dialect -> kgen dialect -> elaborator -> pop -> llvm). |
| compiler/Mojo/include/Mojo/ | Headers and MLIR TableGen (.td) definitions: KGENDialect (types like !kgen.simd, !kgen.dtype), POPDialect, LITDialect, HLCFDialect, CODialect, MojoParser, Interpreter. |
| compiler/Mojo/lib/ | C++ implementation: MojoParser, Elaborator, Interpreter, KGENToLLVM, Compiler/ObjectCompiler (LLVM pass pipeline in LLVMPassesPipeline.cpp). |
| compiler/Support/ | Shared support library, e.g. Support/include/Support/ML/DType.h (the 1-byte C++ DType class). |

Not extracted: compiler tests (Mojo/test, 9.4 MB), tools, unittests, and the MAX/AsyncRT parts.

The zip file is now at /home/manas/modular-v26.6.0.zip, retained for the MAX or GPU parts and anything else not extracted.