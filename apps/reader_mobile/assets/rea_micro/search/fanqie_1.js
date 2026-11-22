// 书籍资料搜索，使用与其他来源一致的同步 fetch 桥接。
// 搜索使用官方移动端接口；网页搜索接口缺少浏览器安全组件时返回空响应。
// 详情读取官方书籍页面内嵌的 JSON 数据，不执行页面脚本。
const CHROME_USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

const MOBILE_USER_AGENT =
  "com.ss.android.article.news/7.0.3 (Linux; U; Android 12; zh_CN; Pixel 6)";

function fetchText(url, mobile) {
  if (typeof fetch !== "function") {
    throw new Error("global fetch() is not available in this runtime");
  }

  const res = fetch(url, {
    headers: {
      "User-Agent": mobile ? MOBILE_USER_AGENT : CHROME_USER_AGENT,
      Accept: mobile ? "application/json" : "text/html",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      Referer: "https://fanqienovel.com/",
    },
  });
  if (!res.ok) throw new Error("HTTP " + res.status + " " + (res.statusText || ""));

  const text = String(res.text() || "").trim();
  if (!text) {
    throw new Error("番茄小说接口返回空响应，请稍后重试");
  }
  return text;
}

function fetchJson(url) {
  const text = fetchText(url, true);
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error("番茄小说搜索接口未返回有效 JSON，可能需要浏览器安全校验");
  }
}

function extractPage(html, bookId) {
  const marker = /window\.__INITIAL_STATE__\s*=\s*/.exec(html);
  if (!marker) throw new Error("番茄小说详情页缺少初始数据");
  const start = marker.index + marker[0].length;
  if (html[start] !== "{") throw new Error("番茄小说详情数据格式异常");
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = start; i < html.length; i++) {
    const c = html[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === "\\") escaped = true;
      else if (c === '"') inString = false;
    } else if (c === '"') inString = true;
    else if (c === "{") depth++;
    else if (c === "}" && --depth === 0) {
      const page = JSON.parse(html.slice(start, i + 1)).page;
      if (!page || String(page.bookId) !== bookId || !page.bookName) {
        throw new Error("番茄小说详情与书籍 ID 不匹配");
      }
      return page;
    }
  }
  throw new Error("番茄小说详情数据不完整");
}

function isTextBook(book) {
  // 官方书籍类型：小说=0、出版=6、短篇=7、故事=8、对话=9、古籍=204。
  // 排除音频、漫画和视频结果。
  if (book.genre == null || book.genre === "") return true;
  return [0, 6, 7, 8, 9, 204].indexOf(Number(book.genre)) !== -1;
}

function normalizeIntro(input) {
  return String(input || "")
    .replace(/\r\n?/g, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p\s*>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/\n+/g, "\n")
    .trim();
}

function formatWan(value) {
  if (value == null || String(value).trim() === "") return "";
  const n = Number(value);
  return isFinite(n) && n >= 0 ? (n / 10000).toFixed(1) + "万" : "";
}

function formatStatus(value) {
  // 官方创作状态：完结=0、连载=1；缺失状态不能视为完结。
  if (value === 0 || value === "0") return "完结";
  if (value === 1 || value === "1") return "连载";
  return "";
}

function search_raw(key) {
  const query = String(key || "").trim();
  if (!query) return { code: 200, data: [], error: null };

  try {
    const encoded = encodeURIComponent(query);
    const json = fetchJson(
      "https://novel.snssdk.com/api/novel/channel/homepage/search/search/v1/" +
        "?device_platform=android&parent_enterfrom=novel_channel_search.tab." +
        "&offset=0&aid=1967&q=" + encoded
    );
    if (!json || (json.code !== 0 && json.code !== "0")) {
      throw new Error("番茄小说搜索失败：" + String(json && (json.message || json.msg) || "接口返回异常"));
    }
    const items = json.data && json.data.ret_data;
    if (!Array.isArray(items)) {
      throw new Error("番茄小说搜索返回结构异常：缺少 ret_data");
    }

    const data = [];
    const seen = {};
    for (let i = 0; i < items.length; i++) {
      const b = items[i];
      if (!b || !(b.title || b.book_name) || !isTextBook(b)) continue;
      const id = String(b.book_id || "");
      if (!/^\d+$/.test(id) || seen[id]) continue;
      seen[id] = true;
      let detail = null;
      try {
        detail = extractPage(fetchText("https://fanqienovel.com/page/" + id, false), id);
      } catch (e) {
        // 个别详情页不可用时保留搜索结果中的书籍资料。
        if (typeof print === "function") print("fanqie detail unavailable: " + id);
      }
      data.push({
        title: normalizeIntro(detail ? detail.bookName : (b.title || b.book_name)),
        author: String(detail && detail.author || b.author || ""),
        alias: "",
        subtitle: "",
        original: "",
        intro: normalizeIntro(detail && detail.abstract || b.abstract || ""),
        cover: String(detail && (detail.thumbUri || detail.thumbUrl) || b.thumb_url || "").replace(/^\/\//, "https://"),
        translator: "",
        publisher: "番茄小说",
        publish_date: "",
        price: "",
        isbn: "",
        words: formatWan(detail && detail.wordNumber != null ? detail.wordNumber : b.word_count),
        status: formatStatus(detail && detail.creationStatus != null ? detail.creationStatus : b.creation_status),
      });
    }

    return { code: 200, data, error: null };
  } catch (e) {
    return { code: 500, data: [], error: (e && e.message) || String(e) };
  }
}

function search(key) {
  return JSON.stringify(search_raw(key));
}
