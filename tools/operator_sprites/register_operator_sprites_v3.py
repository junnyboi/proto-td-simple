#!/usr/bin/env python3
"""Register validated compact operator atlases without modifying recruit assets."""
from pathlib import Path
import argparse, hashlib, json, shutil
IDS=('gunner_female','gunner_male','mage_apprentice_female','mage_apprentice_male','swordmaster_female','swordmaster_male')
DIRECTIONS=('ne','se','sw','nw')
BEGIN='; BEGIN GENERATED ADVANCED OPERATOR ANIMATIONS'
END='; END GENERATED ADVANCED OPERATOR ANIMATIONS'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--repository',type=Path,required=True);p.add_argument('--processed',type=Path,required=True);args=p.parse_args();root=args.repository.resolve()
 rows=[];records=[]
 for identity in IDS:
  source=args.processed/identity
  report=json.loads((source/'manifest.json').read_text())
  assert len(report['sequences'])==8 and report['identity']==identity
  target=root/'assets/operators/v3'/identity;target.mkdir(parents=True,exist_ok=True)
  class_id,gender=identity.rsplit('_',1)
  for direction in DIRECTIONS:
   for action,count in [('idle',24),('attack',13)]:
    asset=source/f'{action}_{direction}.webp'
    record=json.loads((source/f'{action}_{direction}.json').read_text())
    assert record['frame_count']==count and record['cell']==[256,256] and record['source_kind']=='generated'
    assert sha(asset)==record['atlas_sha256']
    output=target/asset.name;shutil.copy2(asset,output)
    relative=output.relative_to(root).as_posix()
    logical=f'op_anim_{identity}_{action}_{direction}'
    rows.append(f'''&"{logical}": {{
"animations": {{&"{action}": {{&"fps": 12.0, &"length": {count}, &"loop": {'true' if action=='idle' else 'false'}, &"start": 0}}}},
"columns": 8,
"frames": {count},
"pattern": "res://{relative}",
"pivot": Vector2(0.5, 0.765625),
"placeholder": false,
"provenance": {{
&"action": "{action}", &"atlas_sha256": "{record['atlas_sha256']}",
&"class_id": "{class_id}", &"direction": "{direction}", &"gender": "{gender}",
&"mirrored_from": "", &"source_kind": "generated", &"source_manifest_id": "operator_sprites_v3"
}},
"size": Vector2i(256, 256)
}}''')
    records.append({'id':logical,'path':relative,'sha256':record['atlas_sha256'],'frame_count':count,'direction':direction,'action':action,'carrier_sha256':record['carrier_sha256'],'source_window':report['windows'][direction][action]})
  maps={action:',\n'.join(f'&"{d}": &"op_anim_{identity}_{action}_{d}"' for d in DIRECTIONS) for action in ('idle','attack')}
  resource=f'''[gd_resource type="Resource" script_class="OperatorAnimationDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/presentation/operator_animation_def.gd" id="1_def"]

[resource]
script = ExtResource("1_def")
schema_version = 3
visual_id = &"operator_{identity}"
idle_by_direction = {{
{maps['idle']}
}}
attack_by_direction = {{
{maps['attack']}
}}
idle_frame_count = 24
attack_frame_count = 13
fps = 12.0
pivot = Vector2(0.5, 0.765625)
source_cell_px = 256
display_height_px = 58
normalized_subject_height_px = 106
placeholder = false
'''
  (root/'data/presentation/operator_visuals'/f'{identity}.tres').write_text(resource)
 manifest=root/'assets/template/manifest.tres';text=manifest.read_text()
 start=text.index(BEGIN);end=text.index(END,start)+len(END)
 manifest.write_text(text[:start]+BEGIN+'\n'+',\n'.join(rows)+'\n'+END+text[end:])
 calibration={'schema_version':1,'target_runtime_body_height_px':58,'measurement':'Shared 106px neutral head-to-ground body calibration, authored foot (128,196); weapons excluded from per-frame rescaling.','identities':{identity:{'normalized_body_height_px':106,'disposition':'regenerated_v3'} for identity in IDS}}
 (root/'data/presentation/advanced_operator_proportions.json').write_text(json.dumps(calibration,indent=2)+'\n')
 provenance={'schema_version':3,'source_manifest_id':'operator_sprites_v3','identity_count':6,'directions':list(DIRECTIONS),'sequence_count':48,'frame_count':888,'cell':[256,256],'contact':[128,196],'display_body_height':58,'source_kind':'generated','mirrored_directions':[],'sequences':records}
 (root/'data/presentation/operator_sprites_v3.json').write_text(json.dumps(provenance,indent=2)+'\n')
 print('REGISTERED_OPERATOR_V3_OK 6 identities,48 sequences,888 frames; recruit resources not modified')
if __name__=='__main__':main()
