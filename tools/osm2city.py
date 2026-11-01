exec(open('osmload.py').read())
import math,json,re,random
random.seed(11)
# origin = Kaaba centre
kw=ways[103914569]; kl=[nodes[n] for n in kw]
lat0=sum(a for a,b in kl)/len(kl); lon0=sum(b for a,b in kl)/len(kl)
KX=111320*math.cos(math.radians(lat0)); KZ=110574
def P(n):
    la,lo=nodes[n]; return (round((lo-lon0)*KX,1), round(-(la-lat0)*KZ,1))
b=root.find('bounds'); 
bx=sorted([(float(b.get('minlon'))-lon0)*KX,(float(b.get('maxlon'))-lon0)*KX]); bz=sorted([-(float(b.get('maxlat'))-lat0)*KZ,-(float(b.get('minlat'))-lat0)*KZ])
BOUNDS=[round(bx[0]),round(bz[0]),round(bx[1]),round(bz[1])]
def inb(x,z,m=0): return BOUNDS[0]-m<=x<=BOUNDS[2]+m and BOUNDS[1]-m<=z<=BOUNDS[3]+m
def num(s):
    if s is None: return None
    m=re.match(r'\s*(\d+(?:[.,]\d+)?)',s); return float(m.group(1).replace(',','.')) if m else None
def sarea(p): return sum(p[i][0]*p[(i+1)%len(p)][1]-p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p)))/2
def pip(pt,poly):
    x,z=pt; c=False; n=len(poly)
    for i in range(n):
        x1,z1=poly[i]; x2,z2=poly[(i+1)%n]
        if (z1>z)!=(z2>z) and x < (x2-x1)*(z-z1)/(z2-z1+1e-12)+x1: c=not c
    return c
def clean(ring):
    if len(ring)>1 and ring[0]==ring[-1]: ring=ring[:-1]
    out=[]
    for p in ring:
        if not out or p!=out[-1]: out.append(p)
    return out
# ---- ear clipping with hole bridging
def seg_inter(a,b,c,d):
    def o(p,q,r): return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
    return o(a,b,c)*o(a,b,d)<0 and o(c,d,a)*o(c,d,b)<0
def triangulate(outer,holes):
    ring=list(outer)
    if sarea(ring)<0: ring.reverse()
    hs=[]
    for h in holes:
        h=list(h)
        if sarea(h)>0: h.reverse()
        hs.append(h)
    hs.sort(key=lambda h:-max(p[0] for p in h))
    for h in hs:
        hi=max(range(len(h)),key=lambda i:h[i][0]); hp=h[hi]
        cand=sorted(range(len(ring)),key=lambda i:(ring[i][0]-hp[0])**2+(ring[i][1]-hp[1])**2)
        oi=cand[0]
        for c in cand:
            ok=True
            for i in range(len(ring)):
                if seg_inter(hp,ring[c],ring[i],ring[(i+1)%len(ring)]): ok=False;break
            if ok: oi=c;break
        ring=ring[:oi+1]+h[hi:]+h[:hi+1]+ring[oi:]
    pts=ring; idx=list(range(len(pts))); tris=[]
    def inside(p,a,b,c):
        d1=(p[0]-b[0])*(a[1]-b[1])-(a[0]-b[0])*(p[1]-b[1]); d2=(p[0]-c[0])*(b[1]-c[1])-(b[0]-c[0])*(p[1]-c[1]); d3=(p[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(p[1]-a[1])
        return not((d1<0 or d2<0 or d3<0) and (d1>0 or d2>0 or d3>0))
    guard=0
    while len(idx)>3 and guard<20000:
        guard+=1; found=False
        for k in range(len(idx)):
            i0,i1,i2=idx[k-1],idx[k],idx[(k+1)%len(idx)]
            a,bb,c=pts[i0],pts[i1],pts[i2]
            if (bb[0]-a[0])*(c[1]-a[1])-(bb[1]-a[1])*(c[0]-a[0])<=1e-9: continue
            if any(inside(pts[j],a,bb,c) for j in idx if j not in(i0,i1,i2) and pts[j] not in (a,bb,c)): continue
            tris+= [i0,i1,i2]; idx.pop(k); found=True; break
        if not found: break
    if len(idx)==3: tris+=idx
    return pts,tris
def join_rings(wlist):
    segs=[list(w) for w in wlist if len(w)>1]; rings=[]
    while segs:
        cur=segs.pop(0)
        while cur[0]!=cur[-1]:
            for i,s in enumerate(segs):
                if s[0]==cur[-1]: cur+=s[1:]; segs.pop(i); break
                if s[-1]==cur[-1]: cur+=s[::-1][1:]; segs.pop(i); break
                if s[-1]==cur[0]: cur=s[:-1]+cur; segs.pop(i); break
                if s[0]==cur[0]: cur=s[::-1][:-1]+cur; segs.pop(i); break
            else: break
        if cur[0]==cur[-1] and len(cur)>3: rings.append(cur)
    return rings
# ---- gather polygon sources
polys=[]   # dict(tags, outer(list pts), holes)
inrel=set()
for t,m in rels:
    if t.get('type')!='multipolygon': continue
    outs=[ways[r] for ty,r,role in m if ty=='way' and r in ways and role in('outer','') and all(n in nodes for n in ways[r])]
    ins=[ways[r] for ty,r,role in m if ty=='way' and r in ways and role=='inner' and all(n in nodes for n in ways[r])]
    for ty,r,role in m:
        if ty=='way': inrel.add(r)
    o=join_rings(outs); i=join_rings(ins)
    if not o: continue
    for oring in o:
        op=clean([P(n) for n in oring])
        hl=[clean([P(n) for n in r]) for r in i if pip(P(r[0]),op)]
        polys.append({'t':t,'o':op,'h':hl,'rel':True})
for wid,w in ways.items():
    if len(w)>3 and w[0]==w[-1] and all(n in nodes for n in w) and (wid not in inrel or wtags[wid].get('building') or wtags[wid].get('building:part')):
        polys.append({'t':wtags[wid],'o':clean([P(n) for n in w]),'h':[],'rel':False,'id':wid})
parts=[p for p in polys if 'building:part' in p['t'] and len(p['o'])>=3]
blds=[p for p in polys if p['t'].get('building') and 'building:part' not in p['t'] and len(p['o'])>=3 and p['t'].get('building') not in('bridge',)]
def cen(p): return (sum(a for a,b in p['o'])/len(p['o']),sum(b for a,b in p['o'])/len(p['o']))
for p in parts: p['c']=cen(p)
def has_part(b):
    xs=[a for a,_ in b['o']];zs=[c for _,c in b['o']];x0,x1,z0,z1=min(xs),max(xs),min(zs),max(zs)
    return any(x0<=p['c'][0]<=x1 and z0<=p['c'][1]<=z1 and pip(p['c'],b['o']) for p in parts)
WALL=['d9c7a3','c9b48a','e6d8bb','d3c1ae','c58f6b','e2b9a0']
HOTEL=['e8e1d2','dcd6c8','cfd8dc']
def nm(t):
    en=t.get('name:en') or (t.get('name') if t.get('name') and t.get('name').isascii() else None)
    ar=t.get('name:ar') or (t.get('name') if t.get('name') and not t.get('name').isascii() else None)
    return en or '',ar or ''
def feat(p,kind,default_h=None):
    t=p['t']; o=clean(p['o']); 
    if sarea(o)<0: o.reverse()
    hs=[]
    for h in p['h']:
        h=clean(h)
        if len(h)>=3:
            if sarea(h)>0: h.reverse()
            hs.append(h)
    pts,tris=triangulate(o,hs)
    if not tris: return None
    h=num(t.get('height')); lv=num(t.get('building:levels')) or num(t.get('building:part:levels'))
    if h is None:
        h=lv*3.2 if lv else (default_h if default_h else random.choice([9,12,12,15,18,21]))
    mh=num(t.get('min_height')) or 0
    if t.get('building')=='roof' or t.get('building:part')=='roof': mh=max(mh,max(h-0.8,4)); 
    c=random.choice(WALL); e,a=nm(t)
    if kind=='hotel' or t.get('tourism')=='hotel': c=random.choice(HOTEL)
    if t.get('building')=='religious' and e=='Kaaba': c='0c0c0c'; kind='kaaba'
    ring_sizes=[len(o)]+[len(h) for h in hs]
    allp=o+[q for h in hs for q in h]
    f={'v':[[x,z] for x,z in allp],'r':ring_sizes,'t':tris,'h':round(h,1),'m':round(mh,1),'c':c,'n':e,'a':a,'k':kind}
    if hs: f['p']=[[x,z] for x,z in pts]
    return f
B=[]
for p in parts:
    if not inb(*p['c'],20): continue
    f=feat(p,'part',12); 
    if f: B.append(f)
# parts of Great Mosque etc: keep colour white-ish
for p in blds:
    c=cen(p)
    if not inb(*c,20): continue
    if has_part(p): continue
    f=feat(p,'hotel' if p['t'].get('tourism')=='hotel' else 'bld',None)
    if f: B.append(f)
# special colours: white for mosque / haram
for f in B:
    pass
# ---- areas (marble, parks, parking)
AREAS=[]
for p in polys:
    t=p['t']; kind=None
    nmn=(t.get('name:en') or t.get('name') or '')
    if t.get('building') or t.get('building:part'): continue
    if t.get('highway')=='pedestrian' or 'Square' in nmn or 'Tawaf' in nmn or t.get('place')=='square': kind='marble'
    elif t.get('leisure') in('park','garden') or t.get('landuse') in('grass','recreation_ground'): kind='park'
    elif t.get('amenity') in('parking','bus_station'): kind='parking'
    if not kind or len(p['o'])<3: continue
    c=cen(p)
    if not inb(*c,50): continue
    o=clean(p['o']);hs=[clean(h) for h in p['h'] if len(h)>=3]
    if sarea(o)<0: o.reverse()
    pts,tris=triangulate(o,hs)
    if tris: AREAS.append({'k':kind,'v':[[x,z] for x,z in pts],'t':tris})
# ---- roads
WID={'motorway':11,'trunk':11,'primary':11,'secondary':10,'tertiary':9,'unclassified':7.5,'residential':7.5,'living_street':6,'service':5,'motorway_link':7,'trunk_link':7,'primary_link':7,'secondary_link':7,'tertiary_link':7}
CLS={'motorway':0,'trunk':0,'motorway_link':0,'trunk_link':0,'primary':1,'primary_link':1,'secondary':2,'secondary_link':2,'tertiary':3,'tertiary_link':3,'residential':4,'unclassified':4,'living_street':4,'service':5}
def dp(pts,eps):
    if len(pts)<3: return pts
    a,b=pts[0],pts[-1]; dx,dz=b[0]-a[0],b[1]-a[1]; L=math.hypot(dx,dz)+1e-9
    dm,im=0,0
    for i in range(1,len(pts)-1):
        d=abs(dz*(pts[i][0]-a[0])-dx*(pts[i][1]-a[1]))/L
        if d>dm: dm,im=d,i
    if dm>eps: return dp(pts[:im+1],eps)[:-1]+dp(pts[im:],eps)
    return [a,b]
R=[]
for wid,w in ways.items():
    t=wtags[wid]; hw=t.get('highway')
    if hw not in WID or t.get('tunnel') in('yes','building_passage') or t.get('area')=='yes': continue
    if hw=='service' and t.get('service') in('driveway','parking_aisle'): continue
    if not all(n in nodes for n in w): continue
    pts=dp([P(n) for n in w],1.2)
    pts=[p for p in pts if inb(*p,30)]
    if len(pts)<2: continue
    R.append([WID[hw],CLS[hw],[list(p) for p in pts]])
# ---- POIs, trees, etc
KIND={'restaurant':'food','fast_food':'food','cafe':'food','pharmacy':'pharm','bank':'bank','supermarket':'shop','convenience':'shop','mall':'shop','perfumery':'shop','jewelry':'shop','clothes':'shop','hotel':'hotel','museum':'info'}
POI=[];BUS=[];SIG=[];MOSQ=[];TREES=[];DIST=[]
for nid,t in ntags.items():
    if nid not in nodes: continue
    x,z=P(nid)
    if not inb(x,z): continue
    e,a=nm(t)
    k=t.get('amenity') or t.get('shop') or t.get('tourism')
    if t.get('highway')=='bus_stop': BUS.append([x,z,e or a])
    elif t.get('highway')=='traffic_signals': SIG.append([x,z])
    elif t.get('natural')=='tree': TREES.append([x,z])
    elif t.get('place') in('neighbourhood','city','suburb'): DIST.append([e or a, a, x, z])
    elif t.get('amenity')=='place_of_worship' and t.get('religion','muslim')=='muslim': MOSQ.append([x,z,e,a])
    elif k in KIND and (e or a): POI.append([x,z,e,a,KIND[k]])
for wid,w in ways.items():
    if wtags[wid].get('natural')=='tree_row' and all(n in nodes for n in w):
        pts=[P(n) for n in w]
        for i in range(len(pts)-1):
            a,b2=pts[i],pts[i+1];L=math.hypot(b2[0]-a[0],b2[1]-a[1]); k=max(1,int(L/8))
            for j in range(k):
                q=(a[0]+(b2[0]-a[0])*j/k,a[1]+(b2[1]-a[1])*j/k)
                if inb(*q): TREES.append([round(q[0],1),round(q[1],1)])
TREES=TREES[:2200]
# start: road point nearest to (0,300), class>=primary/secondary/tertiary
best=None
for w,c,pts in R:
    if c>3 or w<9: continue
    for i,(x,z) in enumerate(pts):
        d=math.hypot(x-(-40),z-300)
        if best is None or d<best[0]:
            j=i+1 if i+1<len(pts) else i-1
            dx,dz=pts[j][0]-x,pts[j][1]-z
            if j<i: dx,dz=-dx,-dz
            L=math.hypot(dx,dz) or 1
            best=(d,x,z,dx/L,dz/L)
START=[best[1],best[2]]; SDIR=[round(best[3],3),round(best[4],3)]
# clock tower: parts with h>=400
tall=[p for p in parts if (num(p['t'].get('height')) or 0)>=300]
xs=[a for p in tall for a,b in p['o']];zs=[b for p in tall for a,b in p['o']]
CLOCK=[round((min(xs)+max(xs))/2,1),round((min(zs)+max(zs))/2,1),round((max(xs)-min(xs))/2,1),round((max(zs)-min(zs))/2,1)] if tall else None
out={'bounds':BOUNDS,'start':START,'sdir':SDIR,'kaaba':[0,0],'clock':CLOCK,'roads':R,'bld':B,'areas':AREAS,'poi':POI,'bus':BUS,'sig':SIG,'mosq':MOSQ,'trees':TREES,'dist':DIST}
import os; os.makedirs('data',exist_ok=True)
s=json.dumps(out,separators=(',',':'),ensure_ascii=False)
open('data/city.json','w',encoding='utf8').write(s)
print('bytes',len(s),'bounds',BOUNDS,'start',START,'clock',CLOCK)
print('roads',len(R),sum(len(r[2]) for r in R),'bld',len(B),'areas',len(AREAS),'poi',len(POI),'bus',len(BUS),'sig',len(SIG),'mosq',len(MOSQ),'trees',len(TREES),'dist',len(DIST))
print(DIST[:15])
