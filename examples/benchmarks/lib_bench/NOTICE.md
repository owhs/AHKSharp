# Third-party code in `lib_bench`

The files in this folder are **vendored, unmodified-as-far-as-known copies of community
AutoHotkey libraries** (plus a few binaries and data files). They are used only as the
"AHK side" of `..\ecosystem_benchmark.ahk`. They are **not** covered by the AHK# license.
Each remains the work of its original author(s) and stays under whatever license they
published it with.

Attribution below is taken from the file headers only. Where a header does not state a
license, none is claimed here: check the upstream project before redistributing.

## Files with an attribution / license stated in their header

| File | Author / credit (from header) | License stated in file |
|------|-------------------------------|------------------------|
| `ImagePut.ahk` | Edison Hua (iseahound), https://github.com/iseahound/ImagePut (v1.12) | MIT License |
| `Array.ahk` | Descolada (Array.ahk v0.4.1) | not stated in file |
| `Map.ahk` | Descolada (Map.ahk v0.1) | not stated in file |
| `String.ahk` | Descolada (String.ahk v0.15); credits tidbit ("String Things") and its contributors: AfterLemon, Bon, Lexikos, MasterFocus, Rseding91, Verdlin; further contributors Axlefublr, neogna2 | not stated in file |
| `Misc.ahk` | Descolada (v1.0.1), credit Coco; also credits plankoe, KaFu, and the Java-Access-Bridge-for-AHK project (Elgin1) for embedded parts | not stated in file |
| `Acc2.ahk` | Sean, jethrow, Sancarn (v1 code), Descolada; thanks to Lexikos | not stated in file |
| `JXON.ahk` | "originally posted by user coco" (https://github.com/cocobelgica/AutoHotkey-JSON) | not stated in file |
| `JSON_thqby.ahk` | thqby, modified from HotKeyIt/Yaml (v1.0.8) | not stated in file |
| `Archive.ahk` | thqby (v1.0.0); wraps libarchive (https://github.com/libarchive/libarchive) | not stated in file |
| `CGdip.ahk` | thqby (v1.0.8) | not stated in file |
| `ctypes.ahk` | thqby (v1.0.5) | not stated in file |
| `Base64_jNizM.ahk` | jNizM | not stated in file |
| `CreateGUID_jNizM.ahk` | jNizM | not stated in file |
| `CreateGradient_jNizM.ahk` | jNizM, just me, SKAN | not stated in file |
| `DNSQuery_jNizM.ahk` | jNizM, just me | not stated in file |
| `FileCountLines_jNizM.ahk` | jNizM | not stated in file |
| `FileFindString_jNizM.ahk` | jNizM | not stated in file |
| `WinClip.ahk` | Deo (header links to the original WinClip page, http://www.autohotkey.net/~Deo/index.html); AHK v2 version | not stated in file |

## Files with no author / license header

Provenance is not recorded in the files themselves. Do not assume a license; identify the
upstream source before redistributing.

| File | Notes |
|------|-------|
| `Base64_thqby.ahk` | `Base64` class (crypt32 wrapper); file name indicates thqby, no header |
| `ComVar.ahk` | `ComVar` VARIANT wrapper, no header |
| `DeepClone.ahk` | `deepclone()` helper, no header |
| `Heap.ahk` | `findHeap()` helper, no header |
| `LoadScript.ahk` | `LoadScript` class, no header |
| `Crypt.ahk` | `MD5`, `Crypt_Hash`, `Crypt_AES` (advapi32/ntdll DllCall wrappers), no header |
| `Socket.ahk` | AHK v1-syntax `Socket` class, no header |
| `WinClipAPI.ahk` | `WinClip_base` support class for `WinClip.ahk`, no header |

## Binaries and data

| File | Notes |
|------|-------|
| `sqlite3.dll`, `sqlite3.def` | SQLite (https://sqlite.org). The SQLite source code is in the public domain per the SQLite project; this binary's exact build/provenance is not recorded here. |
| `tree_data.txt` | UI Automation tree dump used as test data for `TreeNavigator`. It is captured from a third-party application UI; its origin is not recorded. |

## Project-authored files

| File | Notes |
|------|-------|
| `TreeNavigator.ahk` | Appears to be project-authored (the benchmark code calls it the project's own library); no header, so please confirm. |
| `EcoBench.cs`, `EcoBench.dll` | The C# side of the benchmark. `EcoBench.dll` is the precompiled build of `EcoBench.cs`; rebuild it if you edit the source. |

If you are an author of any file above and the attribution is wrong or missing, please
open an issue so it can be corrected.
