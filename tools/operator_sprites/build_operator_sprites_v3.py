#!/usr/bin/env python3
"""Build compact four-direction operator atlases from one continuous carrier.

The source video and references remain external; final media uses a common scale
and authored foot (128,196), not a weapon-inclusive per-frame size correction.
"""
from __future__ import annotations
import argparse, hashlib, json, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image
from build_advanced_operator_sprites import remove_chroma, subject_bbox, retain_primary_subject

DIRECTIONS=('ne','se','sw','nw')
COUNTS={'idle':24,'attack':13}
CELL=256
FOOT=np.array([128.0,196.0])

def sha(path):
 return hashlib.sha256(path.read_bytes()).hexdigest()

def frame_at(video,seconds):
 command=['ffmpeg','-v','error','-nostdin','-ss',str(seconds),'-i',str(video),'-frames:v','1','-vf','scale=854:480','-f','image2pipe','-vcodec','png','-']
 import io
 return Image.open(io.BytesIO(subprocess.check_output(command))).convert('RGB')

def foot_point(image):
 alpha=np.array(image.getchannel('A'))
 mask=alpha>48
 ys,xs=np.nonzero(mask)
 if not xs.size: raise ValueError('Empty keyed character')
 bottom=int(ys.max())
 # Lower-body contact measurement excludes most weapons and outstretched arms.
 low=mask & (np.arange(mask.shape[0])[:,None]>=bottom-5)
 ly,lx=np.nonzero(low)
 return np.array([(int(lx.min())+int(lx.max()))/2,float(bottom)])

def clean_body(image,identity):
 if not identity.startswith('gunner'):
  return image
 arr=np.array(image)
 rgb=arr[:,:,:3].astype(float)
 # Both accepted Gunner carriers keep the body at the fixed canvas center.
 # A low muzzleflash must never become the provisional foot/body anchor.
 outside=np.abs(np.arange(image.width)[None,:]-image.width/2)>85
 bright=(rgb.max(axis=2)>=185)&((rgb.max(axis=2)-rgb.min(axis=2)>65)|(rgb.sum(axis=2)>600))
 # The authoring brief excludes effects. Preserve the dark rifle/body and
 # remove bright distal shot debris; engine-owned muzzle effects remain intact.
 arr[outside&bright]=0
 if identity=='gunner_male':
  dark=(arr[:,:,3]>180)&(arr[:,:,:3].max(axis=2)<100)
  _,xs=np.nonzero(dark)
  if xs.size:
   # Measured dark-metal/body bounds plus eight source pixels retain the full
   # rifle and clothing, while rejecting the independently generated plume.
   arr[:,:max(0,int(xs.min())-8)]=0
   arr[:,min(image.width,int(xs.max())+9):]=0
 return retain_primary_subject(Image.fromarray(arr),threshold=180 if identity=='gunner_male' else 24)

def process(args):
 video=args.video.resolve();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(video)]))
 if any(s['codec_type']=='audio' for s in probe['streams']): raise ValueError('Carrier must be silent')
 duration=float(probe['format']['duration'])
 if not 29.5<=duration<=30.5: raise ValueError(f'Unexpected carrier duration {duration}')
 times=[start+t for start in (0,7.5,15,22.5) for t in (1,3.6,5.5)]
 montage=Image.new('RGB',(4*427,3*240))
 for index,t in enumerate(times):
  frame=frame_at(video,t)
  montage.paste(frame.resize((427,240)),((index//3)*427,(index%3)*240))
 montage.save(out/'carrier-review.png')
 if args.inspect_only:
  print(json.dumps({'review':str(out/'carrier-review.png'),'times_by_column':times,'video':str(video),'duration':duration}));return
 windows=json.loads(args.windows.read_text()) if args.windows else {d:{'idle':[s+0.4,s+2.4],'attack':[s+3,s+5.7]} for d,s in zip(DIRECTIONS,(0,7.5,15,22.5))}
 sequences={};neutral=[]
 for direction in DIRECTIONS:
  for action,count in COUNTS.items():
   start,end=windows[direction][action]
   sample=np.linspace(start,end,count,endpoint=(action=='attack'))
   frames=[]
   for t in sample:
    rgb=np.array(frame_at(video,float(t))).astype(float)
    border=np.concatenate([rgb[:4].reshape(-1,3),rgb[-4:].reshape(-1,3),rgb[:,:4].reshape(-1,3),rgb[:,-4:].reshape(-1,3)])
    key=np.median(border,axis=0)
    if key[2] < 150:
     # Key only the measured coral hue; distance-only decontamination alters
     # skin and leather. Non-key interior pixels retain their source RGB.
     distance=np.linalg.norm(rgb-key,axis=2)
     coral=(rgb[:,:,0]-rgb[:,:,1]>80)&(rgb[:,:,0]-rgb[:,:,2]>65)&(rgb[:,:,0]>110)
     a=np.ones(distance.shape)
     a[coral]=np.clip((distance[coral]-30)/140,0,1)
     a[distance<38]=0
     fg=(rgb-(1-a[:,:,None])*key)/np.maximum(a[:,:,None],0.1)
     arr=np.dstack([np.clip(fg,0,255),a*255]).astype('uint8')
     arr[arr[:,:,3]<48]=0
     keyed=clean_body(Image.fromarray(arr),args.identity)
     bbox=subject_bbox(keyed,threshold=48)
     frames.append((keyed,float(t),bbox))
     continue
    # Magenta excess estimates the actual matte mixture; distance-only keys
    # incorrectly retain purple outlines around these dark pixel-art subjects.
    excess=np.maximum(0,np.minimum(rgb[:,:,0],rgb[:,:,2])-rgb[:,:,1])
    a=np.clip(1-excess/255,0,1)
    a[excess>=230]=0
    a[excess<=20]=1
    fg=(rgb-(1-a[:,:,None])*np.array([255,0,255]))/np.maximum(a[:,:,None],0.04)
    # Residual keyed hue is never an identity colour in these approved designs.
    edge=(excess>20)
    cap=np.minimum(fg[:,:,0],fg[:,:,2])-fg[:,:,1]
    spill=np.maximum(0,cap)*edge
    fg[:,:,0]-=spill;fg[:,:,2]-=spill
    arr=np.dstack([np.clip(fg,0,255),a*255]).astype('uint8')
    arr[arr[:,:,3]<48]=0
    keyed=clean_body(Image.fromarray(arr),args.identity)
    bbox=subject_bbox(keyed,threshold=32)
    frames.append((keyed,float(t),bbox))
   sequences[(direction,action)]=frames
   neutral.extend(frames[:3] if action=='idle' else [])
 heights=[f[2][3]-f[2][1] for f in neutral]
 source_height=float(np.median(heights))
 scale=106/source_height
 anchors={direction:np.median([foot_point(frame[0]) for frame in sequences[(direction,'idle')]],axis=0) for direction in DIRECTIONS}
 records=[]
 for (direction,action),frames in sequences.items():
  rows=3 if action=='idle' else 2
  atlas=Image.new('RGBA',(8*CELL,rows*CELL))
  directory=out/f'{action}_{direction}';directory.mkdir(exist_ok=True)
  frame_records=[]
  for index,(image,time,bbox) in enumerate(frames):
   anchor=anchors[direction]
   # One neutral ground anchor per direction is shared by every idle/attack
   # pose. Keep genuine pose motion instead of recentering changing silhouettes.
   size=(round(image.width*scale),round(image.height*scale))
   transformed=image.resize(size,Image.Resampling.LANCZOS)
   offset=np.rint(FOOT-anchor*scale).astype(int)
   cell=Image.new('RGBA',(CELL,CELL))
   cell.alpha_composite(transformed,(int(offset[0]),int(offset[1])))
   actual=subject_bbox(cell,threshold=32)
   # Reject genuinely clipped bounds rather than shrinking a strike to fit.
   source_extent=np.array([bbox[0],bbox[1],bbox[2],bbox[3]])*scale+np.tile(offset,2)
   if min(source_extent[:2]) < 1 or max(source_extent[2:]) > CELL-1:
    image.save(out/f'failure-{action}-{direction}-{index}-keyed.png')
    frame_at(video,time).save(out/f'failure-{action}-{direction}-{index}-source.png')
    raise ValueError(f'{direction}/{action}/{index}: body/weapon clips common cell: {source_extent}')
   cell.save(directory/f'{index:03}.webp',lossless=True,method=6,exact=True)
   atlas.alpha_composite(cell,((index%8)*CELL,(index//8)*CELL))
   frame_records.append({'index':index,'source_seconds':time,'source_bbox':bbox,'source_foot':foot_point(image).tolist(),'source_anchor':anchor.tolist(),'scale':scale,'offset':offset.tolist(),'alpha_bbox':actual,'ground_error_px':actual[3]-1-196})
  target=out/f'{action}_{direction}.webp';atlas.save(target,lossless=True,method=6,exact=True)
  record={'identity':args.identity,'direction':direction,'action':action,'frame_count':len(frames),'fps':12,'columns':8,'cell':[CELL,CELL],'pivot':[0.5,196/256],'body_height_px':106,'display_height_px':58,'encoding':'lossless-webp-alpha','atlas':target.name,'atlas_sha256':sha(target),'carrier_sha256':sha(video),'source_kind':'generated','mirrored_from':'','frames':frame_records}
  (out/f'{action}_{direction}.json').write_text(json.dumps(record,indent=2)+'\n')
  records.append(record)
 manifest={'schema_version':3,'identity':args.identity,'carrier':str(video),'carrier_sha256':sha(video),'source_body_height':source_height,'common_scale':scale,'windows':windows,'sequences':records,'anchor_policy':'neutral-ground-per-direction','source_ground_anchors':{k:v.tolist() for k,v in anchors.items()}}
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 print(f'BUILT {args.identity}: 8 atlases,148 frames,shared scale={scale:.5f}',flush=True)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--video',type=Path,required=True);p.add_argument('--identity',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--windows',type=Path);p.add_argument('--inspect-only',action='store_true');process(p.parse_args())
if __name__=='__main__':main()
