const CHROME_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

function fetchText(url, extraHeaders) {
  if (typeof fetch !== "function") {
    throw new Error("global fetch() is not available in this runtime");
  }

  const res = fetch(url, {
    headers: {
      "User-Agent": CHROME_USER_AGENT,
      Accept: "*/*",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      ...(extraHeaders || {}),
    },
  });

  if (!res.ok) {
    throw new Error("HTTP " + res.status + " " + (res.statusText || ""));
  }

  return res.text();
}

function fetchJson(url, extraHeaders) {
  const text = fetchText(url, { Accept: "application/json", ...(extraHeaders || {}) });
  return JSON.parse(text);
}

function stripTagsKeepBreaks(html) {
  return String(html || "")
    .replace(/\r/g, "")
    .replace(/<\/p>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/\n+/g, "\n")
    .trim();
}

function formatWan(n) {
  const num = Number(n || 0);
  if (!isFinite(num) || num <= 0) return "";
  return (num / 10000).toFixed(1) + "万";
}

function search_raw(key) {
  const query = String(key || "").trim();
  if (!query) return { code: 200, data: [], error: null };

  try {
    const url = "https://m.gongzicp.com/webapi/search/novels?k=" + encodeURIComponent(query);
    const json = fetchJson(url);
    const list =
      json && json.data && Array.isArray(json.data.list) ? json.data.list : [];

    const data = [];
    for (let i = 0; i < list.length; i++) {
      const item = list[i];
      const id = item && item.novel_id;
      if (!id) continue;

      try {
        const detailJsonText = fetchText(
          "https://m.gongzicp.com/webapi/novel/novelInfo?id=" + String(id),
          { Accept: "application/json" }
        );
        if (detailJsonText.indexOf('"code":4204') !== -1) continue;
        const detail = JSON.parse(detailJsonText);
        const b = detail && detail.data ? detail.data : null;
        if (!b) continue;

        const intro = stripTagsKeepBreaks(String(b.novel_info || ""));
        data.push({
          title: String(b.novel_name || ""),
          author: String(b.author_nickname || ""),
          alias: "",
          subtitle: String(b.novel_desc || ""),
          original: "",
          intro,
          cover: String(b.novel_cover || ""),
          translator: "",
          publisher: "长佩文学",
          publish_date: String(b.create_time || ""),
          price: "",
          isbn: "",
          words: formatWan(b.novel_wordnumber || 0),
          status: String(b.novel_process || ""),
        });
      } catch (e) {
        continue;
      }
    }

    return { code: 200, data, error: null };
  } catch (e) {
    return { code: 500, data: [], error: (e && e.message) || String(e) };
  }
}


function search(key) {
  return JSON.stringify(search_raw(key));
}
