const CHROME_USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

function fetchText(url, extraHeaders) {
    if (typeof fetch !== "function") {
        throw new Error("global fetch() is not available in this runtime");
    }

    // 添加更多的请求头，模拟真实浏览器
    const headers = {
        "User-Agent": CHROME_USER_AGENT,
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        "Accept-Encoding": "gzip, deflate",
        "Connection": "keep-alive",
        "Upgrade-Insecure-Requests": "1",
        "Cache-Control": "max-age=0",
        ...(extraHeaders || {}),
    };

    const res = fetch(url, {
        method: "GET",
        headers: headers,
        credentials: "include", // 包含cookie
    });

    // 打印响应头
    const responseHeaders = {};
    for (const [key, value] of Object.entries(res.headers)) {
        responseHeaders[key] = value;
    }

    if (!res.ok) {
        throw new Error("HTTP " + res.status + " " + (res.statusText || ""));
    }

    try {
        return res.text();
    } catch (e) {
        try {
            const buffer = res.arrayBuffer();
            const decoder = new TextDecoder('utf-8', { fatal: false });
            return decoder.decode(buffer);
        } catch (e2) {
            return "";
        }
    }
}

if (typeof globalThis.gbkEncode !== 'function') {
    globalThis.gbkEncode = function (str) {
        return encodeURIComponent(str);
    };
}
if (typeof globalThis.gbkencode !== 'function') {
    globalThis.gbkencode = globalThis.gbkEncode;
}

// 更精确的链接提取函数
function extractLinks(html) {
    const links = [];
    // 尝试多种方式提取链接
    const patterns = [
        // 匹配ul.novelList下的a标签
        /<ul[^>]*class=["'][^"']*novelList[^"']*["'][^>]*>([\s\S]*?)<\/ul>/i,
        // 匹配所有包含book的a标签
        /<a[^>]+href=["']([^"']*book[^"']*)["']/gi,
        // 匹配所有.html链接
        /<a[^>]+href=["']([^"']*\.html)["']/gi
    ];

    for (const pattern of patterns) {
        if (pattern.global) {
            let match;
            while ((match = pattern.exec(html))) {
                const href = match[1];
                if (href) {
                    const absoluteUrl = toAbsoluteUrl(href);
                    if (absoluteUrl && !links.includes(absoluteUrl)) {
                        links.push(absoluteUrl);
                    }
                }
            }
        } else {
            const match = html.match(pattern);
            if (match) {
                const content = match[1];
                const linkRe = /<a[^>]+href=["']([^"']+)["']/gi;
                let linkMatch;
                while ((linkMatch = linkRe.exec(content))) {
                    const href = linkMatch[1];
                    if (href) {
                        const absoluteUrl = toAbsoluteUrl(href);
                        if (absoluteUrl && !links.includes(absoluteUrl)) {
                            links.push(absoluteUrl);
                        }
                    }
                }
            }
        }
    }
    return links;
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

function toAbsoluteUrl(url) {
    const s = String(url || "").trim();
    if (!s) return "";
    if (s.startsWith("http://") || s.startsWith("https://")) return s;
    if (s.startsWith("//")) return "https:" + s;
    if (s.startsWith("/")) return "https:" + s;
    return "https://" + s;
}

function parseDetail(html) {
    // 提取标题
    let title = "";
    const titleMatches = [
        /<h1[^>]*class=["'][^"']*name[^"']*["'][^>]*>([\s\S]*?)<\/h1>/i,
        /<h1[^>]*>([\s\S]*?)<\/h1>/i,
        /<title[^>]*>([\s\S]*?)<\/title>/i
    ];
    for (const pattern of titleMatches) {
        const match = String(html || "").match(pattern);
        if (match) {
            title = stripTags(match[1]);
            if (title) break;
        }
    }
    if (!title) return null;

    // 提取作者
    let author = "";
    const authorBlockMatch = String(html || "").match(/<div[^>]*class=["'][^"']*nl_r1_author[^"']*["'][^>]*>([\s\S]*?)<\/div>/i);
    if (authorBlockMatch) {
        const block = authorBlockMatch[1] || "";
        const authorLinkMatch = String(block).match(/<a[^>]+href=["'][^"']*search_0_1\.html[^"']*t=2[^"']*["'][^>]*>([\s\S]*?)<\/a>/i);
        if (authorLinkMatch) {
            author = stripTags(authorLinkMatch[1]);
        }
    }
    if (!author) {
        const authorMatches = [
            /作者[：:][\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i,
            /作者[：:][\s\S]*?([^<]+)/i
        ];
        for (const pattern of authorMatches) {
            const match = String(html || "").match(pattern);
            if (match) {
                author = stripTags(match[1]);
                if (author) break;
            }
        }
    }

    // 提取封面
    let cover = "";
    const coverMatches = [
        /<img[^>]*class=["'][^"']*cover[^"']*["'][^>]*src=["']([^"']+)["']/i,
        /<img[^>]*src=["']([^"']*cover[^"']*)["']/i,
        /<img[^>]*src=["']([^"']+)["'][^>]*class=["'][^"']*cover[^"']*["']/i
    ];
    for (const pattern of coverMatches) {
        const match = String(html || "").match(pattern);
        if (match) {
            cover = String(match[1] || "").trim();
            if (cover) break;
        }
    }

    // 提取简介
    let intro = "";
    const introMatches = [
        /<div[^>]*id=["']novel_intro["'][^>]*>([\s\S]*?)<\/div>/i,
        /<div[^>]*class=["'][^"']*intro[^"']*["'][^>]*>([\s\S]*?)<\/div>/i,
        /简介[：:][\s\S]*?<div[^>]*>([\s\S]*?)<\/div>/i
    ];
    for (const pattern of introMatches) {
        const match = String(html || "").match(pattern);
        if (match) {
            intro = stripTags(match[1]);
            if (intro) break;
        }
    }

    // 提取状态
    let status = "";
    const statusMatches = [
        /<li[^>]*class=["'][^"']*color999[^"']*["'][^>]*>[\s\S]*?<i[^>]*class=["'][^"']*tag[^"']*["'][^>]*>([\s\S]*?)<\/i>/i,
        /<i[^>]*class=["'][^"']*tag[^"']*["'][^>]*>([\s\S]*?)<\/i>/i,
        /状态[：:][\s\S]*?([^<]+)/i
    ];
    for (const pattern of statusMatches) {
        const match = String(html || "").match(pattern);
        if (match) {
            status = stripTags(match[1]);
            if (status) break;
        }
    }

    // 提取字数
    let words = "";
    const wordsMatches = [
        /<li[^>]*class=["'][^"']*textHide[^"']*["'][^>]*>([\s\S]*?)<\/li>/i,
        /字数[：:][\s\S]*?([^<]+)/i,
        /([0-9]+)字/i
    ];
    for (const pattern of wordsMatches) {
        const match = String(html || "").match(pattern);
        if (match) {
            let txt = stripTags(match[1]);
            if (txt.includes("|")) {
                txt = txt.split("|")[0] || "";
            }
            words = String(txt).replace("字", "").trim();
            if (words) break;
        }
    }

    return {
        title,
        author,
        alias: "",
        subtitle: "",
        original: "",
        intro,
        cover,
        translator: "",
        publisher: "飞卢小说网",
        publish_date: "",
        price: "",
        isbn: "",
        words,
        status,
    };
}

function parseSearchList(html) {
    const src = String(html || "");
    const ulMatch = src.match(/<ul[^>]*class=["'][^"']*novelList[^"']*["'][^>]*>([\s\S]*?)<\/ul>/i);
    if (!ulMatch) return [];
    const ulBody = ulMatch[1] || "";
    const items = [];
    const liRe = /<li\b[^>]*>[\s\S]*?<\/li>/gi;
    let liMatch;
    while ((liMatch = liRe.exec(ulBody)) && items.length < 10) {
        const li = liMatch[0] || "";

        let detail = "";
        const detailRe = /<a[^>]+href=["']([^"']+\/\d+\.html)["'][^>]*>/i;
        const dm = li.match(detailRe);
        if (dm) detail = toAbsoluteUrl(dm[1]);

        let title = "";
        const titleM = li.match(/<div[^>]*class=["'][^"']*bl_r1_tit[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i);
        if (titleM) title = stripTags(titleM[1]);

        let cover = "";
        const coverM = li.match(/<img[^>]*class=["'][^"']*cover[^"']*["'][^>]*src=["']([^"']+)["']/i)
            || li.match(/<img[^>]*class=["'][^"']*bg_cover[^"']*["'][^>]*src=["']([^"']+)["']/i);
        if (coverM) cover = String(coverM[1] || "").trim();
        if (cover.startsWith("http://")) cover = "https://" + cover.slice("http://".length);
        if (cover.startsWith("//")) cover = "https:" + cover;

        let author = "";
        const authorM = li.match(/<div[^>]*class=["'][^"']*nl_r1_author[^"']*["'][^>]*>[\s\S]*?<a[^>]+href=["'][^"']*search_0_1\.html[^"']*t=2[^"']*["'][^>]*>([\s\S]*?)<\/a>/i);
        if (authorM) author = stripTags(authorM[1]);

        let words = "";
        const wordsM = li.match(/<div[^>]*class=["'][^"']*nl_r2[^"']*["'][^>]*>[\s\S]*?<i[^>]*>([\s\S]*?)<\/i>/i);
        if (wordsM) words = stripTags(wordsM[1]);

        let intro = "";
        const introM = li.match(/<div[^>]*class=["'][^"']*bl_r1_into[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i);
        if (introM) intro = stripTags(introM[1]);

        const status = li.includes("<em>完</em>") ? "完结" : "连载";

        if (!title || !detail) continue;

        items.push({
            title,
            author,
            alias: "",
            subtitle: "",
            original: "",
            intro,
            cover,
            translator: "",
            publisher: "飞卢小说网",
            publish_date: "",
            price: "",
            isbn: "",
            words,
            status,
        });
    }
    return items;
}

function search_raw(key) {
    const query = String(key || "").trim();
    if (!query) return { code: 200, data: [], error: null };
    try {
        // 使用gbkEncode函数编码，与Rust版本保持一致
        const encoded_query = gbkEncode(query);
        // 添加t=1参数，与浏览器请求保持一致
        const url = "https://wap.faloo.com/search_1_1.html?t=1&k=" + encoded_query;
        // 获取搜索结果页面
        const html = fetchText(url);
        const data = parseSearchList(html);
        return { code: 200, data: data, error: null };
    } catch (e) {
        return { code: 500, data: [], error: (e && e.message) || String(e) };
    }
}

function search(key) {
    return JSON.stringify(search_raw(key));
}