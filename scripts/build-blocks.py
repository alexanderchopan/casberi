import json, re, sys
S='/private/tmp/claude-501/-Users-alexanderchopan-Developer-casberi/4babae3a-9902-4901-a40c-411792d45221/scratchpad/'
icons=json.load(open(S+'icons-small.json')); namecls=json.load(open(S+'namecls.json'))
css=open('styles.css').read()
# A brand name can appear in SEVERAL selectors — `.ai-grok { background }` at
# the top and `.sw-tab .t-ico .ai-grok { box-shadow }` further down. Naive
# last-wins clobbered the real tile colour with a box-shadow-only body, so
# keep the FIRST body that actually declares a background.
rules={}
for m in re.finditer(r'\.ai-([a-z0-9-]+)\s*\{([^}]*)\}', css):
    k, body = m.group(1), m.group(2).strip()
    if 'background' not in body:      # decoration-only rule, not the tile colour
        continue
    rules.setdefault(k, body)
rules.setdefault('privacy','background: #232320;')

def clean(b):
    keep=[d.strip() for d in b.split(';') if d.strip() and d.split(':')[0].strip() in ('background','color')]
    return '; '.join(keep)+';'

def glow(body):
    """A representative hex for the aura. Gradients contribute their first
    colour stop; a white tile glows a soft grey so the room doesn't blow out."""
    hexes=re.findall(r'#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b', body or '')
    if not hexes: return '#3b8cf0'
    h=hexes[0]
    if len(h)==3: h=''.join(c*2 for c in h)
    r,g,b=(int(h[i:i+2],16) for i in (0,2,4))
    if r>235 and g>235 and b>235: return '#8e97a8'      # white tiles: no blowout
    if r<26 and g<26 and b<26:    return '#5a6474'      # near-black: give it presence
    return '#'+h

out={}; used={}
for name,uri in icons.items():
    k=namecls[name]
    body=rules.get(k,'')
    out[name]={'u':uri,'c':k,'g':glow(body)}
    if k in rules: used[k]=body

brand="<style>\n"+"\n".join(f".ai-{k}{{{clean(v)}}}" for k,v in sorted(used.items()))+"\n</style>"
t=open(S+'tetris.tpl.html').read()
assert '/*__ICONS__*/' in t and '<!--__BRANDCSS__-->' in t, "template markers missing"
t=t.replace('/*__ICONS__*/',json.dumps(out,separators=(',',':'))).replace('<!--__BRANDCSS__-->',brand)
open('blocks.html','w').write(t)
print("blocks.html", len(t)//1024, "KB | icons", len(out), "| brands", len(used))
print("sample glows:", {n:out[n]['g'] for n in ['Farcaster','Notion','Grok','Snapchat','Spotify','Kraken']})
