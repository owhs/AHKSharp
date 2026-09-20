;; AHK# HTTP/JSON Extension — Built-in HTTP client and JSON parser
;; Ships with AHK# — no external dependencies needed.
;;
;; Uses System.Net.WebClient (HTTP) and System.Web.Script.Serialization (JSON)
;; Both are available in .NET Framework 4.0+ natively.
;;
;; Usage:
;;   #Include <ahk#>
;;   #Include ..\ext\ahk#.http.ahk
;;
;;   response := Http.Get("https://api.github.com/users/octocat")
;;   name := Json.Query(response, "name")

#Requires AutoHotkey v2.0

;; ── Http — Fluent HTTP Client ────────────────────────────────────────────────

class Http extends _CSModule {
    static CSharp := '
    (
        using System;
        using System.Net;
        using System.Text;
        using System.IO;

        static bool _init = Init();
        static bool Init() {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
            return true;
        }

        public static string Get(string url, string headers = "") {
            using (var client = CreateClient(headers)) {
                return client.DownloadString(url);
            }
        }

        public static string Post(string url, string body, string headers = "") {
            using (var client = CreateClient(headers)) {
                client.Headers.Add("Content-Type", "application/json");
                return client.UploadString(url, "POST", body);
            }
        }

        public static string Put(string url, string body, string headers = "") {
            using (var client = CreateClient(headers)) {
                client.Headers.Add("Content-Type", "application/json");
                return client.UploadString(url, "PUT", body);
            }
        }

        public static string Delete(string url, string headers = "") {
            using (var client = CreateClient(headers)) {
                return client.UploadString(url, "DELETE", "");
            }
        }

        public static string Head(string url) {
            var req = WebRequest.Create(url);
            req.Method = "HEAD";
            using (var resp = (HttpWebResponse)req.GetResponse()) {
                return (int)resp.StatusCode + "|" + resp.ContentType + "|" + resp.Server;
            }
        }

        public static void Download(string url, string outputPath) {
            using (var client = CreateClient("")) {
                client.DownloadFile(url, outputPath);
            }
        }

        public static string Upload(string url, string filePath) {
            using (var client = CreateClient("")) {
                byte[] response = client.UploadFile(url, filePath);
                return Encoding.UTF8.GetString(response);
            }
        }

        private static WebClient CreateClient(string customHeaders) {
            var client = new WebClient();
            client.Encoding = Encoding.UTF8;
            client.Headers.Add("User-Agent", "AHK-Sharp/1.0");
            if (!string.IsNullOrEmpty(customHeaders)) {
                string[] headerLines = customHeaders.Split(new string[] {"\n"}, StringSplitOptions.RemoveEmptyEntries);
                foreach (var line in headerLines) {
                    int colonIdx = line.IndexOf(":");
                    if (colonIdx > 0) {
                        client.Headers.Add(line.Substring(0, colonIdx).Trim(), line.Substring(colonIdx + 1).Trim());
                    }
                }
            }
            return client;
        }
    )'
}

;; ── Json — JSON Parser/Serializer ────────────────────────────────────────────

class Json extends _CSModule {
    static References := "System.Web.Extensions.dll"
    static CSharp := '
    (
        using System;
        using System.Collections.Generic;
        using System.Web.Script.Serialization;

        private static readonly JavaScriptSerializer _js = new JavaScriptSerializer() {
            MaxJsonLength = int.MaxValue
        };

        public static string Query(string json, string path) {
            var obj = _js.Deserialize<Dictionary<string, object>>(json);
            string[] segments = path.Split(new char[] { (char)46 });
            object current = obj;

            foreach (string seg in segments) {
                if (current is Dictionary<string, object>) {
                    var dict = (Dictionary<string, object>)current;
                    if (!dict.TryGetValue(seg, out current))
                        return "";
                } else if (current is System.Collections.IList) {
                    var arr = (System.Collections.IList)current;
                    int idx;
                    if (int.TryParse(seg, out idx) && idx >= 0 && idx < arr.Count)
                        current = arr[idx];
                    else
                        return "";
                } else {
                    return "";
                }
            }

            return current != null ? current.ToString() : "";
        }

        public static string Stringify(object obj) {
            return _js.Serialize(obj);
        }

        public static string Flatten(string json) {
            var obj = _js.Deserialize<Dictionary<string, object>>(json);
            var lines = new List<string>();
            FlattenHelper(obj, "", lines);
            return string.Join("\n", lines);
        }

        public static string Build(object pairs) {
            var dict = new Dictionary<string, object>();
            if (pairs is object[]) {
                var arr = (object[])pairs;
                for (int i = 0; i < arr.Length - 1; i += 2) {
                    dict[arr[i].ToString()] = arr[i + 1];
                }
            }
            return _js.Serialize(dict);
        }

        public static bool IsValid(string json) {
            try {
                _js.Deserialize<object>(json);
                return true;
            } catch {
                return false;
            }
        }

        private static void FlattenHelper(object obj, string prefix, List<string> lines) {
            if (obj is Dictionary<string, object>) {
                var dict = (Dictionary<string, object>)obj;
                foreach (var kv in dict) {
                    string key = string.IsNullOrEmpty(prefix) ? kv.Key : prefix + "." + kv.Key;
                    FlattenHelper(kv.Value, key, lines);
                }
            } else if (obj is object[]) {
                var arr = (object[])obj;
                for (int i = 0; i < arr.Length; i++) {
                    FlattenHelper(arr[i], prefix + "[" + i + "]", lines);
                }
            } else {
                lines.Add(prefix + "=" + (obj != null ? obj.ToString() : "null"));
            }
        }
    )'
}
