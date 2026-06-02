# HTTP/JSON Built-in Module

Zero-dependency HTTP client and JSON parser.

## Setup

```Autohotkey
#Include <ahk#>
#Include ..\ext\ahk#.http.ahk
```

## HTTP

```Autohotkey
response := Http.Get('https://api.github.com/users/octocat')
Http.Post('https://httpbin.org/post', '{key: value}')
Http.Download('https://example.com/file.zip', 'C:\Downloads\file.zip')
```

## JSON

```Autohotkey
name := Json.Query(response, 'login')
json := Json.Build('name', 'Alice', 'age', '30')
valid := Json.IsValid('{ok: true}')
flat := Json.Flatten(response)
```
