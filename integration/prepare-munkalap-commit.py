from pathlib import Path
import subprocess, re
root=Path(r'C:\Users\darli\bootcamp\FREEE\diszkertek-munkalap').resolve()
assert root.name=='diszkertek-munkalap' and (root/'AGENTS.md').is_file()
command=['git','-c','safe.directory='+root.as_posix(),'-C',str(root)]
def git(*args, data=None):
    return subprocess.run(command+list(args),input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True).stdout
assert not git('diff','--cached','--name-only').strip(), 'Meglévő staged munka: külön egyeztetés szükséges.'
own=Path(__file__).resolve().parent
for name in ['app.js','index.html','munkalap-data.js','service-worker.js']:
    base=git('show','HEAD:'+name).decode('utf-8-sig')
    current=(root/name).read_text(encoding='utf-8-sig')
    if name=='app.js':
        pattern=r'const APP_VERSION = "\d+";'
        base=re.sub(pattern,'const APP_VERSION = "65";',base,count=1)
        current=re.sub(pattern,'const APP_VERSION = "65";',current,count=1)
    elif name=='index.html':
        for old in ['v=61','v=63','v=64']:
            base=base.replace(old,'v=65');current=current.replace(old,'v=65')
        base=base.replace('</head>','  <link rel="stylesheet" href="munkalap-project-tracking.css?v=1">\n</head>',1)
        base=base.replace('</body>','  <script src="munkalap-project-tracking.js?v=1"></script>\n</body>',1)
    elif name=='munkalap-data.js':
        needle='  window.MunkalapDB = {\n'
        helper='''    async projectAccessToken() {
      if (previewMode || !client) return null;
      const { data, error } = await client.auth.getSession();
      if (error) return null;
      return data.session?.access_token || null;
    },

'''
        base=base.replace(needle,needle+helper,1)
    else:
        base=base.replace('munkalap-v63','munkalap-v65').replace('v=63','v=65')
        current=current.replace('munkalap-v64','munkalap-v65').replace('v=64','v=65')
        base=base.replace('const ASSETS=[','const ASSETS=["./munkalap-project-tracking.js?v=1","./munkalap-project-tracking.css?v=1",',1)
    (root/name).write_text(current,encoding='utf-8')
    blob=git('hash-object','-w','--stdin',data=base.encode('utf-8')).decode().strip()
    git('update-index','--add','--cacheinfo','100644,'+blob+','+name)
for name in ['munkalap-project-tracking.js','munkalap-project-tracking.css']:
    assert (root/name).read_bytes()==(own/name).read_bytes()
    git('add','--',name)
print(git('diff','--cached','--stat').decode('utf-8'))
print('A más feladatból származó app.js és email-fallback teszt módosítások staged nélkül megmaradtak.')
