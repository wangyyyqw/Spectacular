const CHROME_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

function fetchText(url, extraHeaders) {
  if (typeof fetch !== "function") {
    throw new Error("global fetch() is not available in this runtime");
  }

  print("fetchText: " + url);
  const res = fetch(url, {
    headers: {
      "User-Agent": CHROME_USER_AGENT,
      Accept: "*/*",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      ...(extraHeaders || {}),
    },
  });

  print("fetchText: status=" + res.status + " ok=" + res.ok);
  if (!res.ok) {
    throw new Error("HTTP " + res.status + " " + (res.statusText || ""));
  }

  return res.text();
}

function fetchJson(url, extraHeaders) {
  const text = fetchText(url, { Accept: "application/json", ...(extraHeaders || {}) });
  return JSON.parse(text);
}

function extractAuthor(name) {
  let s = String(name || "").trim();
  s = s.replace(/^[\[\(【『（][\u4e00-\u9fa5a-zA-Z]+[\]\)】』）]\s*/u, "");
  s = s.replace(/[()（）][A-Za-z\s.]+[()（）]/g, "");
  s = s.replace(/[•.．]/g, "·");
  s = s.replace(/\s+/g, "");
  const chars = Array.from(s);
  if (chars.length > 3 && s.endsWith("著")) return chars.slice(0, -1).join("");
  return s;
}

function normalizeIntro(input) {
  return String(input || "")
    .replace(/\u3000/g, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/\n+/g, "\n")
    .trim();
}

function formatWan(wordsCount) {
  const n = Number(wordsCount || 0);
  return (n / 10000).toFixed(1) + "万";
}

function search_raw(key) {
  const query = String(key || "").trim();
  if (!query) return { code: 200, data: [], error: null };
  print("qidian search: q=" + query);

  try {
    const url =
      "https://qdcg.qidian.com/api/search/list?key=" +
      encodeURIComponent(query) +
      "&pageIndex=1&pageSize=50&site=1&model=1";

    const json = fetchJson(url, {
      Platform: "10",
      AppId: "50",
      AreaId: "501000",
    });

    const items = (json && json.Data && Array.isArray(json.Data.items) ? json.Data.items : []) || [];
    const data = items.map((b) => {
      const status = Number(b.status || 0) === 0 ? "完结" : "连载";
      return {
        title: String(b.bookName || ""),
        author: extractAuthor(b.authorName || ""),
        alias: "",
        subtitle: "",
        original: "",
        intro: normalizeIntro(b.description || ""),
        cover: "https://bookcover.yuewen.com/qdbimg/349573/" + String(b.bookId || "") + "/600.webp",
        translator: "",
        publisher: "起点中文网",
        publish_date: "",
        price: "",
        isbn: "",
        words: formatWan(b.wordsCount || 0),
        status,
      };
    });

    print("qidian search: books=" + data.length);
    return { code: 200, data, error: null };
  } catch (e) {
    return { code: 500, data: [], error: (e && e.message) || String(e) };
  }
}


function search(key) {
  return JSON.stringify(search_raw(key));
}
