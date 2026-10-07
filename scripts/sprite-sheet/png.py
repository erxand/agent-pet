import zlib, struct
def read(path):
    d=open(path,'rb').read(); assert d[:8]==b'\x89PNG\r\n\x1a\n'
    i=8; idat=b''; 
    while i<len(d):
        n,=struct.unpack('>I',d[i:i+4]); t=d[i+4:i+8]; c=d[i+8:i+8+n]; i+=12+n
        if t==b'IHDR': w,h,bd,ct=struct.unpack('>IIBB',c[:10]); 
        elif t==b'IDAT': idat+=c
        elif t==b'PLTE': plte=c
    assert bd==8, bd
    bpp={6:4,2:3,0:1,4:2,3:1}[ct]; raw=zlib.decompress(idat); stride=w*bpp; rows=[]; prev=bytearray(stride); p=0
    for y in range(h):
        f=raw[p]; line=bytearray(raw[p+1:p+1+stride]); p+=1+stride
        for x in range(stride):
            a=line[x-bpp] if x>=bpp else 0; b=prev[x]; c=prev[x-bpp] if x>=bpp else 0
            if f==1: line[x]=(line[x]+a)&255
            elif f==2: line[x]=(line[x]+b)&255
            elif f==3: line[x]=(line[x]+(a+b)//2)&255
            elif f==4:
                pa=abs(b-c); pb=abs(a-c); pc=abs(a+b-2*c)
                pr=a if pa<=pb and pa<=pc else (b if pb<=pc else c); line[x]=(line[x]+pr)&255
        rows.append(bytes(line)); prev=line
    px=[]
    for r in rows:
        out=[]
        for x in range(w):
            s=r[x*bpp:(x+1)*bpp]
            if ct==6: out.append(tuple(s))
            elif ct==2: out.append(tuple(s)+(255,))
            elif ct==3: k=s[0]; out.append(tuple(plte[k*3:k*3+3])+(255,))
            else: out.append((s[0],)*3+(255,))
        px.append(out)
    return w,h,ct,px
def write(path,w,h,px):
    raw=b''.join(b'\x00'+bytes(v for p in row for v in p) for row in px)
    def ch(t,c): return struct.pack('>I',len(c))+t+c+struct.pack('>I',zlib.crc32(t+c)&0xffffffff)
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'+ch(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+ch(b'IDAT',zlib.compress(raw,9))+ch(b'IEND',b''))
