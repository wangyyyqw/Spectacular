const CHROME_USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

const DOUBAN_API_KEY = "0ac44ae016490db2204ce0a042db2916";

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
    try {
        return JSON.parse(text);
    } catch (e) {
        throw new Error("Invalid JSON: " + (e?.message || String(e)));
    }
}

function extractTitle(input) {
    const s = (input ?? "").trim();
    const m = s.match(/^(.*?)(?:[\(（].*)?$/);
    return (m?.[1] ?? s).trim();
}

function extractAuthor(name) {
    let s = (name ?? "").trim();
    s = s.replace(/^[\[\(【『（][\u4e00-\u9fa5a-zA-Z]+[\]\)】』）]\s*/g, "");
    s = s.replace(/[()（）][A-Za-z\s.]+[()（）]/g, "");
    s = s.replace(/[•.．]/g, "·");
    s = s.replace(/\s+/g, "");
    const chars = Array.from(s);
    if (chars.length > 3 && s.endsWith("著")) return chars.slice(0, -1).join("");
    return s;
}

function normalizeDoubanApiBook(book) {
    const alias = String(book.title || "").replace(/\(/g, "（").replace(/\)/g, "）");
    return {
        title: extractTitle(book.title || ""),
        author: Array.isArray(book.author)
            ? book.author.map((a) => extractAuthor(a)).filter(Boolean).join(",")
            : extractAuthor(book.author || ""),
        alias,
        subtitle: book.subtitle || "",
        original: book.origin_title || "",
        intro: book.summary || "",
        cover: book.images?.large || book.images?.medium || book.image || "",
        translator: Array.isArray(book.translator) ? book.translator.filter(Boolean).join(",") : "",
        publisher: book.publisher || "",
        publish_date: book.pubdate || "",
        price: book.price || "",
        isbn: book.isbn13 || book.isbn10 || "",
        words: book.pages ? String(book.pages) + "页" : "",
        detail: book.alt || (book.id ? ("https://book.douban.com/subject/" + book.id + "/") : ""),
        rating: (book && book.rating && typeof book.rating.average !== "undefined")
            ? Number(book.rating.average) || 0
            : 0,
        status: "出版",
    };
}

function filterByTitleSimilarity(query, books) {
    const keywordChars = new Set();
    for (const ch of String(query || "")) {
        if (/[\p{L}\p{N}]/u.test(ch)) keywordChars.add(ch);
    }

    if (keywordChars.size === 0) {
        return books.slice();
    }

    const requiredRatio = 0.3;
    const requiredMatches = Math.ceil(keywordChars.size * requiredRatio);

    const scored = [];
    for (const b of books) {
        const title = String(b && b.title ? b.title : "");
        let matched = 0;
        for (const ch of keywordChars) {
            if (title.includes(ch)) {
                matched++;
            }
        }
        const score = keywordChars.size === 0 ? 0 : matched / keywordChars.size;

        if (score >= requiredRatio) {
            scored.push({ book: b, score });
        }
    }

    scored.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        const at = String(a.book && a.book.title ? a.book.title : "");
        const bt = String(b.book && b.book.title ? b.book.title : "");
        return at.length - bt.length;
    });

    return scored.map((x) => x.book);
}

function search(key) {
    const query = String(key || "").trim();
    if (!query) return JSON.stringify({ code: 200, data: [], error: null });

    try {
        const url =
            "https://api.douban.com/v2/book/search?apikey=" +
            DOUBAN_API_KEY +
            "&q=" +
            encodeURIComponent(query);
        const response = fetchJson(url);
        const books = Array.isArray(response?.books) ? response.books : [];
        const normalized = books.map((b) => normalizeDoubanApiBook(b));
        const withPublisher = normalized.filter((b) => b && b.publisher);
        const data = filterByTitleSimilarity(query, withPublisher);

        return JSON.stringify({ code: 200, data, error: null });
    } catch (e) {
        return JSON.stringify({ code: 500, data: [], error: e?.message || String(e) });
    }
}
