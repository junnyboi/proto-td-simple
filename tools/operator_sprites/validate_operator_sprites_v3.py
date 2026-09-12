#!/usr/bin/env python3
"""Validate final V3 sprite geometry and exact preservation of excluded recruits."""
from pathlib import Path
import argparse, hashlib, json
import numpy as np
from PIL import Image
IDS=('gunner_female','gunner_male','mage_apprentice_female','mage_apprentice_male','swordmaster_female','swordmaster_male')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--processed',type=Path,required=True);p.add_argument('--repository',type=Path,required=True);p.add_argument('--recruit-ledger',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
 recruit=json.loads(a.recruit_ledger.read_text())
 for path,digest in recruit.items():assert sha(a.repository/path)==digest,f'Recruit changed: {path}'
 total=0;entries=[]
 for identity in IDS:
  folder=a.processed/identity;m=json.loads((folder/'manifest.json').read_text())
  assert m['identity']==identity and m['anchor_policy']=='neutral-ground-per-direction'
  assert len(m['sequences'])==8
  assert sha(Path(m['carrier']))==m['carrier_sha256']
  anchors={};errors=[];heights=[];bytes_total=0
  for seq in m['sequences']:
   assert seq['cell']==[256,256] and seq['source_kind']=='generated' and not seq['mirrored_from']
   direction,action=seq['direction'],seq['action'];count=24 if action=='idle' else 13
   assert seq['frame_count']==count and len(seq['frames'])==count
   path=folder/seq['atlas'];assert sha(path)==seq['atlas_sha256']
   atlas=Image.open(path).convert('RGBA');arr=np.array(atlas)
   assert atlas.size==(2048,768 if action=='idle' else 512)
   bytes_total+=path.stat().st_size
   for frame in seq['frames']:
    index=frame['index'];x=(index%8)*256;y=(index//8)*256
    cell=arr[y:y+256,x:x+256]
    assert not cell[:8,:,3].any() and not cell[-8:,:,3].any() and not cell[:,:8,3].any() and not cell[:,-8:,3].any(),f'{identity} {action} {direction} {index} clipped'
    mask=cell[:,:,3]>32;yy,xx=np.nonzero(mask);assert xx.size>300
    assert len(np.unique(cell[:,:,3]))>2,'Missing soft alpha coverage'
    bbox=[int(xx.min()),int(yy.min()),int(xx.max()+1),int(yy.max()+1)]
    assert bbox==frame['alpha_bbox'],f'{identity} metadata bbox mismatch'
    assert abs(frame['scale']-m['common_scale'])<1e-9
    previous=anchors.setdefault(direction,frame['offset'])
    assert previous==frame['offset'],'Per-frame recentering is not admitted'
    errors.append(bbox[3]-1-196)
    if action=='idle':heights.append(bbox[3]-bbox[1])
    rgb=cell[:,:,:3].astype(int)
    magenta=(np.minimum(rgb[:,:,0],rgb[:,:,2])-rgb[:,:,1]>65)&(cell[:,:,3]>128)
    assert magenta.sum()<8,f'{identity}/{action}/{direction}: magenta contamination'
    total+=1
   if count==13:assert not arr[256:,5*256:,3].any(),'Padded cells are not transparent'
  assert max(abs(v) for v in errors)<=4,f'{identity} unstable ground contact {min(errors),max(errors)}'
  assert 102<=np.median(heights)<=110,f'{identity} recruit scale mismatch'
  entries.append({'identity':identity,'sequences':8,'frames':148,'body_height_median_px':float(np.median(heights)),'ground_pixel_error':[min(errors),max(errors)],'atlas_bytes':bytes_total,'source_ground_anchors':m['source_ground_anchors']})
 assert total==888
 report={'status':'passed','identities':6,'sequences':48,'frames':total,'recruit_files_unchanged':len(recruit),'cell':[256,256],'foot_boundary':[128,196],'display_height':58,'identities_detail':entries}
 a.report.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps(report,indent=2))
if __name__=='__main__':main()
