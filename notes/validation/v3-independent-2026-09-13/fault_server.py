import sys
sys.path.insert(0,sys.argv[1]+'/flygym_bridge')
from bridge import Bridge
b=Bridge(mode='mock');world=b.body.lab_world
mode=sys.argv[2]
if mode=='frozen':
 original=world.pre_step
 world.pre_step=lambda dt:original(0)
else:
 factor=10 if mode=='tenfold_duration' else 0.1
 for name in ['set_wind','apply_touch']:
  original=getattr(world,name)
  def wrap(_original=original,**kw):
   if kw.get('duration_ms') is not None:kw['duration_ms']*=factor
   return _original(**kw)
  setattr(world,name,wrap)
b.serve()
