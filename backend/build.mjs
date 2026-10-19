// Bundles admin.html + pages.js + worker.js into dist/worker.mjs (used by Cloudflare deploy and the self-hosted Node server)
import fs from 'node:fs';
const d = new URL('.', import.meta.url).pathname;
fs.mkdirSync(d + 'dist', { recursive: true });
fs.writeFileSync(d + 'dist/worker.mjs', 'const ADMIN_HTML = ' + JSON.stringify(fs.readFileSync(d + 'admin.html', 'utf8')) + ';\n' + fs.readFileSync(d + 'pages.js', 'utf8') + '\n' + fs.readFileSync(d + 'worker.js', 'utf8'));
console.log('built dist/worker.mjs');
