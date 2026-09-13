import socket,subprocess,pathlib,time,sys
root=pathlib.Path(sys.argv[1]);out=pathlib.Path(__file__).parent
for mode in ['frozen','tenfold_duration','tenth_duration']:
 s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
 try:s.bind(('127.0.0.1',17841))
 except OSError:print('SKIPPED existing listener');break
 finally:s.close()
 with (out/('server_'+mode+'.txt')).open('w') as log:
  p=subprocess.Popen([str(root/'flygym-venv/bin/python'),'-u',str(out/'fault_server.py'),str(root),mode],stdout=log,stderr=subprocess.STDOUT)
  try:
   for _ in range(100):
    if 'listening' in (out/('server_'+mode+'.txt')).read_text():break
    if p.poll() is not None:raise RuntimeError('startup failed')
    time.sleep(.1)
   r=subprocess.run([str(root/'ThongpariFlyNeuronSim'),'--labloop'],cwd=root,capture_output=True,text=True,timeout=20)
   (out/('labloop_'+mode+'.txt')).write_text(r.stdout+r.stderr)
   print(mode,'exit',r.returncode,r.stdout,flush=True)
  finally:p.terminate();p.wait(timeout=5)
