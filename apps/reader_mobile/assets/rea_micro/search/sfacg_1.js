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

function decodeHtmlEntities(input) {
  return String(input || "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, code) => String.fromCodePoint(parseInt(code, 16)));
}

function stripTags(input) {
  return decodeHtmlEntities(String(input || "").replace(/<[^>]*>/g, "")).trim();
}

function formatWanFromText(textWithZi) {
  const match = String(textWithZi || "").match(/([\d,]+(?:\.\d+)?)\s*(万)?字/);
  if (!match) return "";
  if (match[2]) return match[1].replace(/,/g, "") + "万";
  const n = Number(match[1].replace(/,/g, ""));
  if (!isFinite(n) || n <= 0) return "";
  return (n / 10000).toFixed(1) + "万";
}

function parseDetail(html) {
  const titleMatch = String(html || "").match(/<span[^>]*class=["'][^"']*\bbook_newtitle\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
  const title = titleMatch ? stripTags(titleMatch[1]) : "";
  if (!title) return null;

  const statusMatch = String(html || "").match(/<div[^>]*class=["'][^"']*\bbook_info2\b[^"']*["'][^>]*>[\s\S]*?<span[^>]*>[\s\S]*?<\/span>\s*<span[^>]*>([\s\S]*?)<\/span>/i);
  const status = statusMatch ? stripTags(statusMatch[1]) : "";

  const info3Matches = [];
  const reInfo3 = /<span[^>]*class=["'][^"']*\bbook_info3\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/gi;
  let m;
  while ((m = reInfo3.exec(String(html || "")))) {
    info3Matches.push(stripTags(m[1].replace(/<br\s*\/?>/gi, "\n")));
  }

  const firstInfo3 = info3Matches[0] || "";
  const parts = firstInfo3.split("/").map((s) => String(s || "").trim()).filter(Boolean);
  const author = parts[0] || "未知";
  const words = formatWanFromText(firstInfo3);

  let publish_date = "";
  const lastInfo3 = info3Matches.length > 0 ? info3Matches[info3Matches.length - 1] : "";
  if (lastInfo3) {
    const time = lastInfo3.match(/\d{2,4}-\d{2}-\d{2}\s+\d{2}:\d{2}/);
    publish_date = time ? time[0] : "";
  }

  const introMatch = String(html || "").match(/<li[^>]*class=["'][^"']*\bbook_bk_qs1\b[^"']*["'][^>]*>([\s\S]*?)<\/li>/i);
  let intro = introMatch ? stripTags(introMatch[1]) : "";
  intro = intro.replace(/\u3000/g, "\n");

  const coverMatch = String(html || "").match(
    /<ul[^>]*>[\s\S]*?<li[^>]*>[\s\S]*?<\/li>[\s\S]*?<li[^>]*>[\s\S]*?<img[^>]+src=["']([^"']+)["']/i
  );
  let cover = coverMatch ? String(coverMatch[1] || "").trim() : "";
  if (cover && cover.startsWith("//")) cover = "https:" + cover;
  if (cover && cover.startsWith("/")) cover = "https://m.sfacg.com" + cover;
  if (cover && cover.indexOf("http") !== 0) cover = "https:" + cover;

  return {
    title,
    author,
    alias: "",
    subtitle: "",
    original: "",
    intro,
    cover,
    translator: "",
    publisher: "菠萝包轻小说",
    publish_date,
    price: "",
    isbn: "",
    words,
    status,
  };
}

function search_raw(key) {
  const query = String(key || "").trim();
  if (!query) return { code: 200, data: [], error: null };

  try {
    const url = "https://m.sfacg.com/API/HTML5.ashx?op=search&keyword=" + encodeURIComponent(query);
    const json = fetchJson(url);
    const novels = json && Array.isArray(json.Novels) ? json.Novels : [];

    const hrefs = [];
    for (let i = 0; i < novels.length; i++) {
      const id = novels[i] && novels[i].NovelID;
      if (!id) continue;
      hrefs.push("https://m.sfacg.com/b/" + String(id) + "/");
    }

    const data = [];
    for (let i = 0; i < hrefs.length; i++) {
      try {
        const html = fetchText(hrefs[i]);
        const book = parseDetail(html);
        if (book) data.push(book);
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
