// Extend the original code-authored paper artwork without changing the approved first letter.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../assets/entity/letter');
const messages = [
  ['YOU COUNTED', 'THE TICKETS.', 'I COUNTED', 'THE FACES.'],
  ['THAT WAS', 'YOUR VOICE.', 'YOU WERE', 'NOT THERE.'],
  ['SOMEONE', 'TOOK MY SEAT.', 'THEY STILL', 'LOOK LIKE ME.'],
  ['I KNOW', 'YOUR SHIFT.', 'I CAN', 'WAIT.'],
  ['THE TRAIN', 'WAS EMPTY.', 'WHO WAVED', 'GOODBYE?'],
  ['YOU LET', 'ME THROUGH.', 'THANK YOU.'],
  ['I HEARD', 'MY NAME.', 'NOBODY', 'WAS HERE.'],
  ['ONE MORE', 'TICKET.', 'ONE LESS', 'PERSON.'],
  ['I SAVED', 'YOUR SEAT.', 'THIS TIME,', 'STAY.'],
];
(async () => {
  const source = fs.readFileSync(path.join(root, 'entity-letter.html'), 'utf8');
  const browser = await chromium.launch({headless:true, executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  const page = await browser.newPage({viewport:{width:900,height:1200},deviceScaleFactor:1});
  for (let i=0;i<messages.length;i++) {
    const lines = messages[i];
    const start = lines.length===3 ? 395 : 340;
    const writing = '<g fill="#571b14" font-family="EntityHand" text-anchor="middle">' + lines.map((s,j)=>`<text x="${440+(j%2)*8}" y="${start+j*160}" font-size="${Math.min(112, Math.floor(1000/s.length))}" transform="rotate(${j%2?2:-3} 440 ${start+j*160})">${s}</text>`).join('')+'</g>';
    // Pulp fibers, mottled grain and paired light/dark fold ridges remain beneath the lettering.
    let fibers='';
    for(let k=0;k<1900;k++) {
      const x=100+(k*137.31%680), y=45+(k*73.77%1085);
      fibers+=`<path d="M${x} ${y} l${2+k%5} ${k%3-1}" stroke="${k%2?'#f5dfb4':'#422e1e'}" stroke-opacity=".16" stroke-width=".65"/>`;
    }
    let html=source.replace(/<g fill="#571b14" font-family="EntityHand" text-anchor="middle">[\s\S]*?<\/g>/, fibers+writing);
    html=html.replace('baseFrequency=".37"','baseFrequency=".11"').replace('opacity=".21" filter="url(#grain)"','opacity=".45" filter="url(#grain)"');
    await page.setContent(html);
    await page.evaluate(()=>document.fonts.ready);
    await page.screenshot({path:path.join(root,`note-${i+1}.png`),omitBackground:true});
  }
  await browser.close();
})();
