# HTTP/JSON Built-in Module

An HTTP client (`Http`) and a small JSON helper (`Json`), both written as `_CSModule`s on top of `System.Net.WebClient` and `System.Web.Script.Serialization`. Both ship in `ext\ahk#.http.ahk`.

## Setup

```autohotkey
#Requires AutoHotkey v2.0
#Include lib\ahk#.ahk
#Include ext\ahk#.http.ahk      ; after the library; adjust both paths for your script's folder
```

## HTTP

```autohotkey
response := Http.Get("https://api.github.com/users/octocat")
Http.Post("https://httpbin.org/post", '{"key": "value"}')
Http.Download("https://example.com/file.zip", "C:\Downloads\file.zip")
```

| Method | Returns | Notes |
|--------|---------|-------|
| `Http.Get(url, headers := "")` | string | |
| `Http.Post(url, body, headers := "")` | string | Sends `Content-Type: application/json` |
| `Http.Put(url, body, headers := "")` | string | Sends `Content-Type: application/json` |
| `Http.Delete(url, headers := "")` | string | |
| `Http.Head(url)` | string | `"status|contentType|server"` |
| `Http.Download(url, outputPath)` | (none) | Saves to a file |
| `Http.Upload(url, filePath)` | string | Multipart file upload; returns the response body |

`headers` is a string of `Name: value` lines separated by newlines (`` `n ``):

```autohotkey
body := Http.Get("https://httpbin.org/headers", "Accept: application/json`nX-Demo: 1")
```

TLS 1.2 is enabled (the bridge switches the whole process to TLS 1.2, and 1.3 where the framework knows it, because the AHK host has no `app.config` and .NET would otherwise fall back to SSL3/TLS 1.0). Network and HTTP errors (`WebException`) reach you as normal AHK errors with the .NET message; wrap calls in `try`. When the error came from a .NET exception it also carries `e.NetType` and works with `CS.ErrorIs(e, "WebException")` ([Error handling](15_api_reference.md#error-handling)). Requests are synchronous; for a non-blocking call use `Http.Async.Get(url).Then(...)` ([Async/Await](04_async.md)), or `System.Net.Http.HttpClient` with an awaitable Task: `CS.System.Net.Http.HttpClient().GetStringAsync(url).Await(15000)`.

## JSON

```autohotkey
name := Json.Query(response, "login")           ; dotted path; numeric segments index arrays
first := Json.Query(response, "items.0.name")
text := Json.Stringify(Map("name", "Alice", "age", 30))   ; Map → JSON object
built := Json.Build("name", "Alice", "age", 30)           ; alternating keys and values, as separate arguments
built := Json.Build(["name", "Alice", "age", "30"])       ; or as ONE Array
valid := Json.IsValid('{"ok": true}')                     ; → 1 / 0
flat := Json.Flatten(response)                            ; "key=value" lines, one per leaf
```

| Method | Returns | Notes |
|--------|---------|-------|
| `Json.Query(json, path)` | string | `""` when the path does not exist. The top-level value must be a JSON object; numeric segments step into arrays (`items.0.name`, `a.b.2.c`) |
| `Json.Stringify(obj)` | string | Serializes a Map (as an object), Array or scalar |
| `Json.Build(key1, value1, key2, value2, ...)` | string | Alternating keys and values. The extra arguments pack into the method's single `object` parameter; passing one Array `[key1, value1, ...]` also works |
| `Json.IsValid(json)` | bool (1/0) | |
| `Json.Flatten(json)` | string | Lines like `user.name=Alice` and `items[0]=x` |

All values come back as strings (`Json.Query` calls `ToString()` on numbers and booleans). Do not name a variable `json` or `http`: AHK is case-insensitive, so it clashes with the `Json` / `Http` classes (`doc := Json.Query(...)`, `body := Http.Get(...)`).

For anything richer, use `Newtonsoft.Json` through [NuGet](05_nuget.md).
