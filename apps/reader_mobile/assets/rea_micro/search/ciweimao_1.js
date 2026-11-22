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

function matchMeta(html, property) {
  const re = new RegExp(
    '<meta[^>]+property=["\\\']' +
      property.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") +
      '["\\\'][^>]+content=["\\\']([^"\\\']*)["\\\']',
    "i"
  );
  const m = String(html || "").match(re);
  return m ? stripTags(m[1]) : "";
}

function findAll(re, input) {
  const out = [];
  const s = String(input || "");
  let m;
  while ((m = re.exec(s))) out.push(m);
  return out;
}

function parseDetail(html) {
  const title = matchMeta(html, "og:novel:book_name");
  if (!title) return null;
  const author = matchMeta(html, "og:novel:author");
  const intro = matchMeta(html, "og:description");
  const cover = matchMeta(html, "og:image");

  let words = "";
  const gradeMatch = String(html || "").match(/<p[^>]*class=["'][^"']*\bbook-grade\b[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
  if (gradeMatch) {
    const bs = findAll(/<b[^>]*>([\s\S]*?)<\/b>/gi, gradeMatch[1]);
    if (bs[2]) {
      const raw = stripTags(bs[2][1]);
      const n = Number(raw);
      words = isFinite(n) && n > 0 ? (n / 10000).toFixed(1) + "万" : raw;
    }
  }

  let status = "";
  const statusMatch = String(html || "").match(/<p[^>]*class=["'][^"']*\bupdate-state\b[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
  if (statusMatch) status = stripTags(statusMatch[1]).split("·")[0].trim();

  let publish_date = "";
  const timeMatch = String(html || "").match(/<h3[^>]*class=["'][^"']*\btit\b[^"']*["'][^>]*>[\s\S]*?<span[^>]*>([\s\S]*?)<\/span>/i);
  if (timeMatch) publish_date = stripTags(timeMatch[1]).replace("更新时间：", "").trim();

  return {
    title,
    author,
    alias: "",
    subtitle: "",
    original: "",
    intro,
    cover,
    translator: "",
    publisher: "刺猬猫阅读",
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
    const url =
      "https://www.ciweimao.com/get-search-book-list/0-0-0-0-0-0/%E5%85%A8%E9%83%A8/" +
      encodeURIComponent(query) +
      "/1";
    const html = fetchText(url);

    const ids = [];
    const re = /data-book-id=["'](\d+)["']/g;
    let m;
    while ((m = re.exec(html))) ids.push(m[1]);

    const uniqueIds = Array.from(new Set(ids));
    const data = [];
    for (let i = 0; i < uniqueIds.length; i++) {
      const bookUrl = "https://www.ciweimao.com/book/" + uniqueIds[i];
      try {
        const detailHtml = fetchText(bookUrl);
        const book = parseDetail(detailHtml);
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
