"""Render agent-pet sprite packs. Layout matches docs/sprite-sheet.png in
erxand/agent-pet: scale 4, 4px margin, 4px between frames, 16px between
animations, animations idle walk wave sit emerge dive jump fall, one pack per row.

Run from anywhere: python3 scripts/sprite-sheet/sheet.py [OUT.png [PACK_DIR ...]]
With no arguments it writes docs/sprite-sheet.png from every pack in sprites/."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__)); import png
ANIMS = [('idle',2),('walk',4),('wave',3),('sit',2),('emerge',3),('dive',3),('jump',2),('fall',2)]
def hexrgb(h):
    h=h.lstrip('#'); return tuple(int(h[i:i+2],16) for i in (0,2,4))+(255 if len(h)<8 else int(h[6:8],16),)
def load(d):
    meta=json.load(open(os.path.join(d,'pack.json'))); n=meta['frameSize']
    pal={k:hexrgb(v) for k,v in meta['palette'].items()}
    anims={}
    for a,_ in ANIMS:
        f=os.path.join(d,a+'.txt')
        if not os.path.exists(f): anims[a]=None; continue
        lines=[l.rstrip('\n') for l in open(f)]
        frames=[];cur=[]
        for l in lines:
            if l.strip()=='' :
                if cur: frames.append(cur); cur=[]
            else: cur.append(l)
        if cur: frames.append(cur)
        anims[a]=frames
    # missing emerge/dive: agent-pet holds idle frame 0; missing jump plays walk, missing fall plays idle
    stand_in={'jump':'walk','fall':'idle'}
    for a,c in ANIMS:
        if anims[a] is None: anims[a]=anims[stand_in[a]] if a in stand_in else [anims['idle'][0]]*c
    return meta,n,pal,anims
def frame_px(frame,n,pal):
    T=(0,0,0,0)
    return [[pal.get(frame[y][x],T) if y<len(frame) and x<len(frame[y]) and frame[y][x]!='.' else T for x in range(n)] for y in range(n)]
def blit(canvas,fp,ox,oy,s):
    for y,row in enumerate(fp):
        for x,c in enumerate(row):
            if c[3]==0: continue
            for dy in range(s):
                r=canvas[oy+y*s+dy]
                for dx in range(s): r[ox+x*s+dx]=c
def sheet(dirs,out,s=4,m=4,g=4,G=16):
    packs=[load(d) for d in dirs]; n=packs[0][1]; fs=n*s
    nfr=sum(c for _,c in ANIMS)
    W=2*m+nfr*fs+(nfr-len(ANIMS))*g+(len(ANIMS)-1)*G; H=2*m+len(packs)*fs+(len(packs)-1)*g
    cv=[[(0,0,0,0)]*W for _ in range(H)]
    for i,(meta,n,pal,anims) in enumerate(packs):
        x=m; y=m+i*(fs+g)
        for ai,(a,c) in enumerate(ANIMS):
            for fi,fr in enumerate(anims[a][:c]):
                blit(cv,frame_px(fr,n,pal),x,y,s); x+=fs+(g if fi<c-1 else 0)
            x+=G
    png.write(out,W,H,cv); return W,H
FIRST = ['claude','golem','hatchling','mossling','nimbus','seon','tinowl','walle']
def default_dirs(root):
    sprites=os.path.join(root,'sprites')
    names=[n for n in os.listdir(sprites) if os.path.exists(os.path.join(sprites,n,'pack.json'))]
    ordered=[n for n in FIRST if n in names]+sorted(n for n in names if n not in FIRST)
    return [os.path.join(sprites,n) for n in ordered]
if __name__=='__main__':
    root=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    out=sys.argv[1] if len(sys.argv)>1 else os.path.join(root,'docs','sprite-sheet.png')
    dirs=sys.argv[2:] or default_dirs(root)
    print(sheet(dirs,out))
