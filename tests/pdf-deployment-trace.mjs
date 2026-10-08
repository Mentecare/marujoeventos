// Run after next build: the deployed route must carry its standard fonts and
// native image decoder instead of resolving a bundled absolute scratch path.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const route=path.resolve('.next/server/app/api/quotes/[id]/pdf/route.js');
assert.doesNotMatch(fs.readFileSync(route,'utf8'), /file:\/\/\/workspace\/[^"]+\/node_modules\/pdfkit\//, 'PDFKit cannot resolve an absolute build workspace path in deployed code');
const files=JSON.parse(fs.readFileSync(route+'.nft.json','utf8')).files;
const resolved=files.map(file=>path.resolve(path.dirname(route),file));
for(const font of ['DejaVuSans.ttf','DejaVuSans-Bold.ttf','LICENSE-DejaVu.txt'])assert.ok(resolved.some(file=>file.endsWith('/lib/fonts/'+font)),'licensed Unicode font missing: '+font);
assert.ok(resolved.some(file=>file.endsWith('/pdfkit/package.json')),'PDFKit package missing from deployment trace');
for(const font of ['Helvetica','HelveticaBold'])assert.ok(resolved.some(file=>file.endsWith('/pdfkit/js/standard-fonts/'+font+'.cjs')),'compiled standard font '+font+' missing from deployment trace');
for(const font of ['Helvetica','Helvetica-Bold'])assert.ok(resolved.some(file=>file.includes('/pdfkit/')&&file.endsWith('/'+font+'.afm')),'standard font '+font+' missing from deployment trace');
assert.ok(resolved.some(file=>file.includes('sharp-linux-x64')&&file.endsWith('.node')),'native Sharp missing from deployment trace');
assert.ok(resolved.some(file=>file.includes('libvips-cpp')),'libvips missing from deployment trace');
for(const file of resolved)assert.ok(fs.existsSync(file),'traced file missing: '+file);
console.log('PASS: optimized Next PDF deployment trace includes PDFKit package, licensed DejaVu regular/bold, Helvetica/Helvetica-Bold AFMs, native Sharp and libvips; every traced file exists');
