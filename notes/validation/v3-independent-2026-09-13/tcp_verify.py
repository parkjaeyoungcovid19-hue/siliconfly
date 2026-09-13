import socket,subprocess,pathlib,time,sys
root=pathlib.Path(sys.argv[1]);out=pathlib.Path(__file__).parent
for mode in ['mock','flygym-headless']:
 s=socket.socket()
 try:s.bind(('127.0.0.1',17841))
 except OSError:print('SKIPPED: existing listener; left untouched',flush=True);break
 finally:s.close()
 with (out/('server_'+mode+'.txt')).open('w') as log:
  p=subprocess.Popen([str(root/'flygym-venv/bin/python'),'-u','flygym_bridge/bridge.py','--'+mode],cwd=root,stdout=log,stderr=subprocess.STDOUT)
  try:
   deadline=time.monotonic()+90
   while time.monotonic()<deadline:
    if p.poll() is not None:raise RuntimeError('bridge failed')
    if 'listening' in (out/('server_'+mode+'.txt')).read_text().lower():break
    time.sleep(.3)
   else:raise RuntimeError('startup timeout')
   r=subprocess.run([str(root/'ThongpariFlyNeuronSim'),'--labloop'],cwd=root,capture_output=True,text=True,timeout=30)
   (out/('labloop_'+mode+'.txt')).write_text(r.stdout+r.stderr)
   print(mode,'exit',r.returncode, r.stdout,flush=True)
  finally:
   p.terminate()
   try:p.wait(timeout=8)
   except subprocess.TimeoutExpired:p.kill();p.wait()
