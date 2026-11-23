#!/usr/bin/env node
// 上传 APK 到 Streamshare，并删除上一次上传；上传记录保存在 APK 同一目录的
// .streamshare-latest.json（dist/ 已被忽略）。
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { basename, dirname, join } from 'node:path';

const baseUrl = 'https://streamshare.wireway.ch';
const chunkSize = 4096 * 1024;

const apkPath = process.argv[2];
if (!apkPath) {
  console.error('用法：node tool/share_apk.mjs <apk 路径>');
  process.exit(2);
}

const data = await readFile(apkPath);
const name = basename(apkPath);
const sha256 = createHash('sha256').update(data).digest('hex');
const statePath = join(dirname(apkPath), '.streamshare-latest.json');

const previous = await readFile(statePath, 'utf8')
  .then((raw) => JSON.parse(raw))
  .catch(() => null);

console.log(`文件：${name}（${(data.length / 1024 / 1024).toFixed(1)} MB）`);

const createResponse = await fetch(`${baseUrl}/api/create`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ name }),
});
if (!createResponse.ok) {
  throw new Error(
    `创建上传失败：${createResponse.status} ${await createResponse.text()}`,
  );
}
const { fileIdentifier, deletionToken } = await createResponse.json();
console.log(`标识：${fileIdentifier}`);

const ws = new WebSocket(`${baseUrl.replace('https', 'wss')}/api/upload/${fileIdentifier}`);
ws.binaryType = 'arraybuffer';
const socketError = new Promise((_, reject) => {
  ws.addEventListener('error', () => reject(new Error('WebSocket 连接失败')), {
    once: true,
  });
});

await Promise.race([
  socketError,
  new Promise((resolve) => ws.addEventListener('open', resolve, { once: true })),
]);

let offset = 0;
while (offset < data.length) {
  const end = Math.min(offset + chunkSize, data.length);
  await Promise.race([
    socketError,
    new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('等待 ACK 超时')), 120000);
      const onMessage = (event) => {
        if (event.data === 'ACK') {
          clearTimeout(timer);
          ws.removeEventListener('message', onMessage);
          resolve();
        }
      };
      ws.addEventListener('message', onMessage);
      ws.send(data.subarray(offset, end));
    }),
  ]);
  offset = end;
  console.log(
    `已发送 ${(offset / 1024 / 1024).toFixed(1)} / ${(data.length / 1024 / 1024).toFixed(1)} MB`,
  );
}
ws.close(1000, 'FILE_UPLOAD_DONE');

if (previous?.identifier && previous?.deletionToken) {
  const deleted = await fetch(
    `${baseUrl}/api/delete/${previous.identifier}/${previous.deletionToken}`,
    { method: 'DELETE' },
  ).catch(() => null);
  console.log(
    `删除旧上传 ${previous.identifier}：${deleted ? deleted.status : '请求失败'}`,
  );
}

await writeFile(
  statePath,
  `${JSON.stringify(
    {
      identifier: fileIdentifier,
      deletionToken,
      sha256,
      size: data.length,
      uploadedAt: new Date().toISOString(),
    },
    null,
    2,
  )}\n`,
);

console.log(`下载：${baseUrl}/download/${fileIdentifier}`);
console.log(`SHA-256：${sha256}`);
