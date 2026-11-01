import xml.etree.ElementTree as ET, math, json, collections
tree=ET.parse('map.osm'); root=tree.getroot()
nodes={}; ntags={}
ways={}; wtags={}; rels=[]
for e in root:
    if e.tag=='node':
        i=int(e.get('id')); nodes[i]=(float(e.get('lat')),float(e.get('lon')))
        t={c.get('k'):c.get('v') for c in e if c.tag=='tag'}
        if t: ntags[i]=t
    elif e.tag=='way':
        i=int(e.get('id')); ways[i]=[int(c.get('ref')) for c in e if c.tag=='nd']
        wtags[i]={c.get('k'):c.get('v') for c in e if c.tag=='tag'}
    elif e.tag=='relation':
        rels.append(({c.get('k'):c.get('v') for c in e if c.tag=='tag'},[(c.get('type'),int(c.get('ref')),c.get('role')) for c in e if c.tag=='member']))
