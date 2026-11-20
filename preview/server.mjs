// Tiny static server for the Noellyne Bet design preview.
// Run: node preview/server.mjs  →  open the printed URL.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = fileURLToPath(new URL('.', import.meta.url));
const port = process.env.PORT || 3000;

const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png' };

createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const file = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    const body = await readFile(join(dir, file));
    res.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream' });
    res.end(body);
  } catch {
    res.writeHead(404); res.end('Not found');
  }
}).listen(port, '0.0.0.0', () => console.log(`Noellyne Bet preview → http://localhost:${port}`));
