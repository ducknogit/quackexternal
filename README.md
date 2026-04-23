# Quack External

A Roblox external script executor written in C++. Operates entirely outside the Roblox process — no DLL injection, no driver.

> **Notice:** This source has been permitted for open source release. Please respect the [MIT License](LICENSE) and its terms.
> This is **not** our main/production source. It may contain traces of AI-assisted development. Use it as a reference at your own discretion.

---

## How it works

Quack attaches to a running Roblox process from the outside. It locates the Lua state through the TaskScheduler, elevates thread identity to 8, injects a signed Luau bytecode payload via a hijacked CoreScript slot (CollisionMatchers2D → JestModule), and exposes a standard executor API surface to user scripts.

Communication between the injected Lua payload and the host process goes through a local HTTP bridge (`localhost:6767`) and a WebSocket server (`localhost:8080`).

## Structure

```
Quack/
├── Source/
│   ├── Main.cpp                  # Entry point, process monitor
│   ├── Client/                   # Roblox process attach & Lua state setup
│   ├── Server/                   # HTTP bridge (localhost:6767)
│   ├── Update/                   # Offsets + remote offset refresh
│   ├── Utility/                  # Bytecode compiler, BLAKE3 signer, memory utils
│   └── Resource/
│       └── Init.lua              # Lua payload — executor API (getgenv, loadstring, drawing, etc.)
└── Dependencies/
    ├── Luau/                     # Luau compiler (AST, Compiler, VM)
    ├── mbedtls/                  # TLS for HTTPS requests
    └── ...
```

## Building

Requires Visual Studio 2022 (v143 toolset), Windows SDK, x64.

```
MSBuild Quack.sln /p:Configuration=Release /p:Platform=x64
```

Output: `Quack/build/Quack.exe`

## Compatibility

Currently supports Roblox version `version-2e6461290a3541f5`. Offsets are in `Quack/Source/Update/Offsets.hpp` and can be refreshed remotely via `Offsets::RefreshFromRemote()`.

SUNC (Standard UNC) compatibility is a primary goal of the Lua payload.

## License

MIT — see [LICENSE](LICENSE).
