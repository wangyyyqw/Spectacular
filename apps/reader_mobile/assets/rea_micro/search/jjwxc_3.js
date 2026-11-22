const CHROME_USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

function shouldRetryNetworkError(e) {
    const msg = (e && e.message) ? String(e.message) : String(e || "");
    return (
        msg.includes("EOFException") ||
        msg.includes("Not enough data available") ||
        msg.includes("java.io.EOFException") ||
        msg.includes("io.ktor") ||
        msg.includes("zipline")
    );
}

function safeStringifyError(e) {
    if (!e) return "";
    if (typeof e === "string") return e;
    if (e && typeof e.message === "string") return e.message;
    try {
        return JSON.stringify(e);
    } catch (_) {
        return String(e);
    }
}

function fetchTextWithEncoding(url, extraHeaders, encoding) {
    if (typeof fetch !== "function") {
        throw new Error("global fetch() is not available in this runtime");
    }

    const maxAttempts = 3;
    let lastError = null;
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
            const res = fetch(url, {
                headers: {
                    "User-Agent": CHROME_USER_AGENT,
                    Accept: "*/*",
                    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                    ...(attempt > 1 ? { Connection: "close" } : {}),
                    ...(extraHeaders || {}),
                },
            });

            if (!res.ok) {
                throw new Error("HTTP " + res.status + " " + (res.statusText || ""));
            }

            const text = res.text();
            if (text && typeof text.then === "function") {
                throw new Error("async fetch() response is not supported in this runtime");
            }
            return text;
        } catch (e) {
            lastError = e;
            if (attempt < maxAttempts && shouldRetryNetworkError(e)) continue;
            throw e;
        }
    }

    throw new Error(safeStringifyError(lastError) || "fetch failed");
}

const _gbkCharToBytes = new Map();

function findGbkBytesForChar(decoder, ch) {
    for (let lead = 0x81; lead <= 0xfe; lead++) {
        for (let trail = 0x40; trail <= 0xfe; trail++) {
            if (trail === 0x7f) continue;
            const decoded = decoder.decode(new Uint8Array([lead, trail]));
            if (decoded === ch) return [lead, trail];
        }
    }
    return null;
}

function gbkPercentEncode(input) {
    if (typeof TextDecoder !== "function") return null;

    let decoder;
    try {
        decoder = new TextDecoder("gbk", { fatal: false });
    } catch (_) {
        return null;
    }

    const bytes = [];
    for (const ch of String(input || "")) {
        const cp = ch.codePointAt(0) || 0;
        if (cp <= 0x7f) {
            bytes.push(cp);
            continue;
        }

        let pair = _gbkCharToBytes.get(ch);
        if (!pair) {
            pair = findGbkBytesForChar(decoder, ch);
            if (!pair) return null;
            _gbkCharToBytes.set(ch, pair);
        }
        bytes.push(pair[0], pair[1]);
    }

    let out = "";
    for (const b of bytes) {
        out += "%" + b.toString(16).toUpperCase().padStart(2, "0");
    }
    return out;
}

function gbkFormEncodeViaJava(input) {
    const s = String(input || "");
    try {
        if (typeof Java !== "undefined" && Java && typeof Java.type === "function") {
            const URLEncoder = Java.type("java.net.URLEncoder");
            const encoded = URLEncoder.encode(s, "GBK");
            if (encoded != null) return String(encoded);
        }
    } catch (_) {}

    try {
        if (typeof Packages !== "undefined" && Packages && Packages.java && Packages.java.net && Packages.java.net.URLEncoder) {
            const encoded = Packages.java.net.URLEncoder.encode(s, "GBK");
            if (encoded != null) return String(encoded);
        }
    } catch (_) {}

    return null;
}

function encodeKwForJjwxc(query) {
    const s = String(query || "");
    let hasNonAscii = false;
    for (const ch of s) {
        if ((ch.codePointAt(0) || 0) > 0x7f) {
            hasNonAscii = true;
            break;
        }
    }
    if (!hasNonAscii) return encodeURIComponent(s);
    try {
        if (typeof gbkEncode === "function") return String(gbkEncode(s));
    } catch (_) {}
    try {
        if (typeof gbkencode === "function") return String(gbkencode(s));
    } catch (_) {}
    return gbkFormEncodeViaJava(s) || gbkPercentEncode(s) || encodeURIComponent(s);
}

function decodeHtmlEntities(input) {
    const s = String(input || "");
    return s
        .replace(/&nbsp;/gi, " ")
        .replace(/&amp;/gi, "&")
        .replace(/&lt;/gi, "<")
        .replace(/&gt;/gi, ">")
        .replace(/&quot;/gi, '"')
        .replace(/&#39;/gi, "'")
        .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n) || 0))
        .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCharCode(parseInt(n, 16) || 0));
}

function stripTags(html) {
    return String(html || "")
        .replace(/<script[\s\S]*?<\/script>/gi, "")
        .replace(/<style[\s\S]*?<\/style>/gi, "")
        .replace(/<\/?[^>]+>/g, "");
}

function htmlToText(html) {
    const withNewlines = String(html || "").replace(/<br\s*\/?>/gi, "\n");
    const text = stripTags(withNewlines);
    return decodeHtmlEntities(text)
        .replace(/\r\n/g, "\n")
        .replace(/\r/g, "\n")
        .replace(/[ \t]+/g, " ")
        .replace(/\n[ \t]+/g, "\n")
        .replace(/\n{3,}/g, "\n\n")
        .trim();
}

function findDivBlockById(html, id) {
    const re = new RegExp('<div\\b[^>]*\\bid=["\\\']' + String(id).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + '["\\\'][^>]*>', "i");
    const m = re.exec(html);
    if (!m) return null;

    const openTagStart = m.index;
    const openTagEnd = html.indexOf(">", openTagStart);
    if (openTagEnd < 0) return null;

    let pos = openTagEnd + 1;
    let depth = 1;
    while (pos < html.length) {
        const nextOpen = html.indexOf("<div", pos);
        const nextClose = html.indexOf("</div", pos);
        if (nextClose < 0) return null;

        if (nextOpen !== -1 && nextOpen < nextClose) {
            depth++;
            pos = nextOpen + 4;
            continue;
        }

        depth--;
        const closeTagEnd = html.indexOf(">", nextClose);
        if (closeTagEnd < 0) return null;
        pos = closeTagEnd + 1;
        if (depth === 0) {
            return { outerHtml: html.slice(openTagStart, pos), innerHtml: html.slice(openTagEnd + 1, nextClose) };
        }
    }
    return null;
}

function extractTopLevelDivBlocks(html) {
    const blocks = [];
    let pos = 0;
    while (pos < html.length) {
        const open = html.indexOf("<div", pos);
        if (open < 0) break;
        const closeAngle = html.indexOf(">", open);
        if (closeAngle < 0) break;

        let scanPos = closeAngle + 1;
        let depth = 1;
        while (scanPos < html.length) {
            const nextOpen = html.indexOf("<div", scanPos);
            const nextClose = html.indexOf("</div", scanPos);
            if (nextClose < 0) break;

            if (nextOpen !== -1 && nextOpen < nextClose) {
                depth++;
                scanPos = nextOpen + 4;
                continue;
            }

            depth--;
            const nextCloseAngle = html.indexOf(">", nextClose);
            if (nextCloseAngle < 0) break;
            scanPos = nextCloseAngle + 1;
            if (depth === 0) {
                blocks.push(html.slice(open, scanPos));
                pos = scanPos;
                break;
            }
        }
        if (depth !== 0) break;
    }
    return blocks;
}

function normalizeJjwxcUrl(url) {
    const u = String(url || "").trim();
    if (!u) return "";
    if (u.startsWith("//")) return "https:" + u;
    if (u.startsWith("http://")) return "https://" + u.slice("http://".length);
    if (u.startsWith("https://")) return u;
    if (u.startsWith("/")) return "https://www.jjwxc.net" + u;
    return "https://www.jjwxc.net/" + u.replace(/^\.\//, "");
}

function parseSearchItem(itemHtml) {
    const titleBlock = /<h3\b[^>]*class=["']title["'][^>]*>([\s\S]*?)<\/h3>/i.exec(itemHtml);
    const titleHtml = titleBlock ? titleBlock[1] : itemHtml;

    const linkMatch = /<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/i.exec(titleHtml);
    const detailUrl = linkMatch ? normalizeJjwxcUrl(decodeHtmlEntities(linkMatch[1])) : "";
    const title = linkMatch ? htmlToText(linkMatch[2]) : "";

    const publishDateMatch = /\((\d{4}-\d{2}-\d{2})\)/.exec(titleHtml);
    const publish_date = publishDateMatch ? publishDateMatch[1] : "";

    const introMatch = /<div\b[^>]*class=["']intro["'][^>]*>([\s\S]*?)<\/div>/i.exec(itemHtml);
    const intro = introMatch ? htmlToText(introMatch[1]) : "";

    const infoMatch = /<div\b[^>]*class=["']info["'][^>]*>([\s\S]*?)<\/div>/i.exec(itemHtml);
    const infoHtml = infoMatch ? infoMatch[1] : "";

    const authorMatch = /作者：[\s\S]*?<a\b[^>]*>([\s\S]*?)<\/a>/i.exec(infoHtml);
    const author = authorMatch ? htmlToText(authorMatch[1]) : "";

    const statusMatch = /进度：\s*<font\b[^>]*>([^<]+)<\/font>/i.exec(infoHtml);
    const status = statusMatch ? htmlToText(statusMatch[1]) : "";

    return { title, author, intro, publish_date, status, detailUrl };
}

function parseJjwxcSearchHtml(html) {
    const block = findDivBlockById(html, "search_result");
    if (block) {
        const items = extractTopLevelDivBlocks(block.innerHtml);
        const parsed = items.map(parseSearchItem).filter((b) => b && b.title);
        if (parsed.length > 0) return parsed;
    }

    const startIdx = String(html || "").search(/id=["']search_result["']/i);
    if (startIdx < 0) return [];
    const footerIdx = String(html || "").search(/id=["']footer["']/i);
    const slice = footerIdx > startIdx ? String(html).slice(startIdx, footerIdx) : String(html).slice(startIdx);

    const results = [];
    const itemRe =
        /<h3\b[^>]*class=["']title["'][^>]*>([\s\S]*?)<\/h3>[\s\S]*?<div\b[^>]*class=["']intro["'][^>]*>([\s\S]*?)<\/div>[\s\S]*?<div\b[^>]*class=["']info["'][^>]*>([\s\S]*?)<\/div>/gi;
    let m;
    while ((m = itemRe.exec(slice))) {
        const itemHtml = "<h3 class=\"title\">" + m[1] + "</h3>" + "<div class=\"intro\">" + m[2] + "</div>" + "<div class=\"info\">" + m[3] + "</div>";
        const parsed = parseSearchItem(itemHtml);
        if (parsed && parsed.title) results.push(parsed);
    }
    return results;
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
        return bt.length - at.length;
    });

    return scored.map((x) => x.book);
}

function extractCoverFromDetailHtml(html) {
    const imgTagMatch = /<img\b[^>]*class=["']noveldefaultimage["'][^>]*>/i.exec(html);
    if (!imgTagMatch) return "";
    const tag = imgTagMatch[0];
    // 晋江的 _src 是加载失败时使用的默认封面，可能排在真实 src 前面。
    const srcMatch = /\ssrc\s*=\s*["']([^"']+)["']/i.exec(tag)
        || /\b_src\s*=\s*["']([^"']+)["']/i.exec(tag);
    if (!srcMatch) return "";
    return normalizeJjwxcUrl(decodeHtmlEntities(srcMatch[1]));
}

function fetchCover(detailUrl) {
    const html = fetchTextWithEncoding(
        detailUrl,
        {
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        Referer: "https://www.jjwxc.net/",
        },
        "gbk"
    );
    return extractCoverFromDetailHtml(html);
}

function search_raw(key) {
    const query = String(key || "").trim();

    if (!query) {
        return { code: 200, data: [], error: null };
    }

    try {
        const encodedKw = encodeKwForJjwxc(query);
        const url = "https://www.jjwxc.net/search.php?kw=" + encodedKw + "&ord=&t=1";

        const html = fetchTextWithEncoding(
            url,
            {
                Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            },
            "gbk"
        );

        const parsed = parseJjwxcSearchHtml(html);
        const filtered = filterByTitleSimilarity(query, parsed);
        const sliced = filtered.slice(0, 5);

        const data = sliced.map((b) => {
            let cover = "";
            if (b.detailUrl) {
                try {
                    cover = fetchCover(b.detailUrl);
                } catch (coverErr) {
                    cover = "";
                }
            }
            return {
                title: String(b.title || ""),
                author: String(b.author || ""),
                alias: "",
                subtitle: "",
                original: "",
                intro: String(b.intro || ""),
                cover,
                translator: "",
                publisher: "晋江文学城",
                publish_date: String(b.publish_date || ""),
                price: "",
                isbn: "",
                words: "",
                status: String(b.status || ""),
            };
        });

        return { code: 200, data, error: null };
    } catch (e) {
        return { code: 500, data: [], error: (e && e.message) || String(e) };
    }
}


function search(key) {
    return JSON.stringify(search_raw(key));
}
