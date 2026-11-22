const CHROME_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

function normalizeHeaders(extraHeaders) {
  const headers = extraHeaders || {};
  return {
    "User-Agent": CHROME_USER_AGENT,
    Accept: "*/*",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    ...(headers || {}),
  };
}

function fetchText(url, extraHeaders) {
  const headers = normalizeHeaders(extraHeaders);

  if (typeof fetch !== "function") {
    throw new Error("global fetch() is not available in this runtime");
  }

  print("fetchText: " + url);
  const res = fetch(url, { headers });
  print("fetchText: status=" + res.status + " ok=" + res.ok);
  if (!res.ok) throw new Error("HTTP " + res.status + " " + (res.statusText || ""));
  return res.text();
}

function fetchJson(url, extraHeaders) {
  const text = fetchText(url, { Accept: "application/json", ...(extraHeaders || {}) });
  return JSON.parse(text);
}

function fetchWithHeaders(url, extraHeaders) {
  const headers = normalizeHeaders(extraHeaders);
  if (typeof fetch !== "function") {
    throw new Error("global fetch() is not available in this runtime");
  }
  const res = fetch(url, { headers });
  if (!res || typeof res !== "object") throw new Error("fetch() returned invalid response");
  const status = Number(res.status || 0);
  const ok = !!res.ok;
  if (!ok) throw new Error("HTTP " + status + " " + (res.statusText || ""));
  const body = typeof res.text === "function" ? res.text() : "";
  return { status, body: String(body || ""), headers: res.headers || {} };
}

function postText(url, body, extraHeaders) {
  const headers = normalizeHeaders(extraHeaders);

  if (typeof fetch !== "function") {
    throw new Error("global fetch() is not available in this runtime");
  }
  print("fetchText: " + url);
  const res = fetch(url, { method: "POST", headers, body: String(body || "") });
  print("fetchText: status=" + res.status + " ok=" + res.ok);
  if (!res.ok) throw new Error("HTTP " + res.status + " " + (res.statusText || ""));
  return res.text();
}

function postJson(url, jsonBody, extraHeaders) {
  const headers = extraHeaders || {};
  headers["Content-Type"] = headers["Content-Type"] || "application/json;charset=UTF-8";
  headers.Accept = headers.Accept || "application/json";
  const text = postText(url, JSON.stringify(jsonBody || {}), headers);
  return JSON.parse(text);
}

function stripTags(input) {
  return String(input || "").replace(/<[^>]*>/g, "");
}

function urlDecode(input) {
  try {
    return decodeURIComponent(String(input || ""));
  } catch {
    return String(input || "");
  }
}

function extractCookiesAndToken(headers) {
  const setCookie = [];

  if (headers) {
    // 处理Headers对象
    if (typeof headers.entries === "function") {
      for (const [name, value] of headers.entries()) {
        if (name.toLowerCase() === "set-cookie") {
          setCookie.push(value);
        }
      }
    }
    // 处理普通对象
    else {
      const h = headers || {};
      const cookieHeader = h["set-cookie"] || h["Set-Cookie"] || h["SET-COOKIE"];
      if (cookieHeader) {
        if (Array.isArray(cookieHeader)) {
          setCookie.push(...cookieHeader);
        } else {
          // 处理逗号分隔的cookie字符串
          const cookieStr = String(cookieHeader);
          // 分割cookie，注意要处理cookie值中可能包含的逗号
          const cookies = cookieStr.split(/,(?=[^;]+=)/);
          cookies.forEach(cookie => {
            const trimmedCookie = cookie.trim();
            if (trimmedCookie) {
              setCookie.push(trimmedCookie);
            }
          });
        }
      }
    }
  }

  if (setCookie.length === 0) return { cookies: "", token: "" };

  let cookies = "";
  let token = "";
  for (let i = 0; i < setCookie.length; i++) {
    const v = String(setCookie[i] || "");
    const semi = v.indexOf(";");
    const params = semi >= 0 ? v.slice(0, semi) : v;
    if (params) cookies += params + "; ";
    if (params.indexOf("__cs__=") !== -1) {
      const eq = params.indexOf("=");
      if (eq >= 0) token = params.slice(eq + 1);
    }
  }

  return { cookies, token };
}

function search_raw(key) {
  const query = String(key || "").trim();
  if (!query) return { code: 200, data: [], error: null };
  print("zongheng search: q=" + query);

  try {
    const encodedQuery = encodeURIComponent(query);
    const preUrl = "https://m.zongheng.com/search?keywords=" + encodedQuery;
    const pre = fetchWithHeaders(preUrl);
    const { cookies, token } = extractCookiesAndToken(pre.headers);
    if (!cookies || !token) throw new Error("missing cookies/token");

    const json = postJson(
      "https://m.zongheng.com/api/search",
      { keywords: query, pageNum: 1 },
      { Cookie: cookies, "X-Csrf-Token": token, "Referer": preUrl, "Origin": "https://m.zongheng.com" }
    );

    const items = json && json.data && Array.isArray(json.data.searchBooks) ? json.data.searchBooks : [];
    const data = items.map((b) => ({
      title: stripTags(urlDecode(b.bookName || "")),
      author: stripTags(String(b.authorName || "")),
      alias: "",
      subtitle: "",
      original: "",
      intro: String(b.description || ""),
      cover: "https://static.zongheng.com/upload/" + String(b.coverUrl || ""),
      translator: "",
      publisher: "纵横中文网",
      publish_date: "",
      price: "",
      isbn: "",
      words: String(b.totalWord || ""),
      status: Number(b.serialStatus || 0) === 1 ? "完结" : "连载",
    }));


    print("zongheng search: books=" + data.length);
    return { code: 200, data, error: null };
  } catch (e) {
    return { code: 500, data: [], error: (e && e.message) || String(e) };
  }
}

function search(key) {
  return JSON.stringify(search_raw(key));
}
