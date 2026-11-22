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

function normalizeWords(input) {
  let s = stripTags(input).replace(/\s+/g, "");
  if (!s) return "";
  s = s.replace(/w/gi, "万");
  s = s.replace(/字+$/g, "");
  if (/^\d+(\.\d+)?万$/.test(s)) return s;
  if (/^\d+$/.test(s)) return s;
  return s.replace(/字+$/g, "");
}

function toAbsoluteUrl(url) {
  const s = String(url || "").trim();
  if (!s) return "";
  if (s.startsWith("http://") || s.startsWith("https://")) return s;
  if (s.startsWith("//")) return "https:" + s;
  if (s.startsWith("/")) return "https://www.ciyuanji.com" + s;
  return "https://www.ciyuanji.com/" + s;
}

function parseSearchList(html) {
  const src = String(html || "");
  const items = [];

  const sectionRe = /<section\b[^>]*class=["'][^"']*\bBookCard__book_card__[^"']*["'][^>]*>[\s\S]*?<\/section>/gi;
  let sectionMatch;
  while ((sectionMatch = sectionRe.exec(src)) && items.length < 10) {
    const section = sectionMatch[0] || "";

    let title = "";
    const titleM = section.match(/<p[^>]*class=["'][^"']*\bBookCard_title__[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
    if (titleM) title = stripTags(titleM[1]);
    if (!title) continue;

    let cover = "";
    const coverM =
      section.match(/<img[^>]*\bdata-src=["']\s*([^"']+?)\s*["'][^>]*>/i) ||
      section.match(/<img[^>]*\bsrc=["']\s*([^"']+?)\s*["'][^>]*>/i);
    if (coverM) {
      cover = String(coverM[1] || "").replace(/`/g, "").trim();
      cover = toAbsoluteUrl(cover);
    }

    let author = "";
    let status = "";
    const authorBlockM = section.match(/<p[^>]*class=["'][^"']*\bBookCard_author__[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
    if (authorBlockM) {
      const block = authorBlockM[1] || "";
      const authorM =
        block.match(/<span[^>]*class=["'][^"']*\bBookCard_name1__[^"']*["'][^>]*>([\s\S]*?)<\/span>/i) ||
        block.match(/<span[^>]*class=["'][^"']*\bBookCard_name__[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
      if (authorM) author = stripTags(authorM[1]);

      const parts = [];
      const spanRe = /<span\b[^>]*class=["'][^"']*\bBookCard_name__[^"']*["'][^>]*>([\s\S]*?)<\/span>/gi;
      let spanMatch;
      while ((spanMatch = spanRe.exec(block))) {
        const t = stripTags(spanMatch[1]);
        if (t && t !== "|") parts.push(t);
      }
      if (parts.length > 0) status = parts[parts.length - 1];
    }

    let words = "";
    const chapterM = section.match(/<p[^>]*class=["'][^"']*\bBookCard_chapter__[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
    if (chapterM) {
      const wordsM = String(chapterM[1] || "").match(/<span[^>]*class=["'][^"']*\bBookCard_name__[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
      if (wordsM) words = normalizeWords(wordsM[1]);
    }

    let intro = "";
    const introM = section.match(/<p[^>]*class=["'][^"']*\bBookCard_desc__[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
    if (introM) intro = stripTags(introM[1]);

    items.push({
      title,
      author,
      alias: "",
      subtitle: "",
      original: "",
      intro,
      cover,
      translator: "",
      publisher: "次元姬",
      publish_date: "",
      price: "",
      isbn: "",
      words,
      status,
    });
  }

  return items;
}

function parseDetail(html) {
  const titleMatch = String(html || "").match(/<div[^>]*class=["'][^"']*\bbook_detail_content__SQOg8\b[^"']*["'][^>]*>[\s\S]*?<h1[^>]*>[\s\S]*?<span[^>]*>([\s\S]*?)<\/span>/i);
  const title = titleMatch ? stripTags(titleMatch[1]) : "";
  if (!title) return null;

  const authorMatch = String(html || "").match(/<div[^>]*class=["'][^"']*\bbook_detail_content__SQOg8\b[^"']*["'][^>]*>[\s\S]*?<p[^>]*>[\s\S]*?<span[^>]*class=["'][^"']*\bbook_detail_text__HlCNP\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
  const author = authorMatch ? stripTags(authorMatch[1]) : "";

  const introMatch = String(html || "").match(/<article[^>]*class=["'][^"']*\bbook_detail_article__tNriO\b[^"']*["'][^>]*title=["']([^"']*)["']/i);
  const intro = introMatch ? decodeHtmlEntities(introMatch[1]).trim() : "";

  const coverMatch = String(html || "").match(/<img[^>]*class=["'][^"']*\blazyautosizes\b[^"']*["'][^>]*data-src=["']([^"']+)["']/i);
  const cover = coverMatch ? String(coverMatch[1] || "").trim() : "";

  const wordsMatch = String(html || "").match(/<p[^>]*class=["'][^"']*\bbook_detail_statistical__8_BoB\b[^"']*["'][^>]*>[\s\S]*?<span[^>]*class=["'][^"']*\bbook_detail_num__6z_p_\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
  const words = wordsMatch ? stripTags(wordsMatch[1]) : "";

  const statusMatch = String(html || "").match(/<span[^>]*class=["'][^"']*\bbook_detail_text__HlCNP\b[^"']*["'][^>]*>[\s\S]*?<\/span>[\s\S]*?<span[^>]*class=["'][^"']*\bbook_detail_text__HlCNP\b[^"']*["'][^>]*>[\s\S]*?<\/span>[\s\S]*?<span[^>]*class=["'][^"']*\bbook_detail_text__HlCNP\b[^"']*["'][^>]*>[\s\S]*?<\/span>[\s\S]*?<span[^>]*class=["'][^"']*\bbook_detail_text__HlCNP\b[^"']*["'][^>]*>[\s\S]*?<\/span>[\s\S]*?<span[^>]*class=["'][^"']*\bbook_detail_text__HlCNP\b[^"']*["'][^>]*>[\s\S]*?<\/span>[\s\S]*?<span[^>]*class=["'][^"']*\bbook_detail_text__HlCNP\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
  const status = statusMatch ? stripTags(statusMatch[1]) : "";

  const timeMatch = String(html || "").match(/<span[^>]*class=["'][^"']*\bbook_detail_time__E3K_Y\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/i);
  const publish_date = timeMatch ? stripTags(timeMatch[1]) : "";

  return {
    title,
    author,
    alias: "",
    subtitle: "",
    original: "",
    intro,
    cover,
    translator: "",
    publisher: "次元姬",
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
    const url = "https://www.ciyuanji.com/search/" + encodeURIComponent(query) + "_0_0_0_0_0_1.html";
    const html = fetchText(url);
    const data = parseSearchList(html);

    return { code: 200, data, error: null };
  } catch (e) {
    return { code: 500, data: [], error: (e && e.message) || String(e) };
  }
}


function search(key) {
  return JSON.stringify(search_raw(key));
}