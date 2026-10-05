from pathlib import Path
import shutil, tempfile, hashlib, json
own = Path(__file__).resolve().parent
target = Path(r'C:\Users\darli\bootcamp\FREEE\diszkertek-munkalap').resolve()
assert target.name == 'diszkertek-munkalap' and (target / 'AGENTS.md').is_file()
backup = Path(tempfile.mkdtemp(prefix='munkalap-project-tracking-before-'))
changes = []
for name in ['munkalap-data.js', 'index.html', 'service-worker.js']:
    p = target / name
    shutil.copy2(p, backup / name)
    text = p.read_text(encoding='utf-8-sig')
    if name == 'munkalap-data.js':
        needle = '  window.MunkalapDB = {\n'
        assert text.count(needle) == 1
        if 'async projectAccessToken()' not in text:
            text = text.replace(needle, needle + '''    async projectAccessToken() {
      if (previewMode || !client) return null;
      const { data, error } = await client.auth.getSession();
      if (error) return null;
      return data.session?.access_token || null;
    },

''', 1)
    elif name == 'index.html':
        if 'munkalap-project-tracking.css' not in text:
            text = text.replace('</head>', '  <link rel="stylesheet" href="munkalap-project-tracking.css?v=1">\n</head>', 1)
            text = text.replace('</body>', '  <script src="munkalap-project-tracking.js?v=1"></script>\n</body>', 1)
    else:
        if 'munkalap-project-tracking.js' not in text:
            text = text.replace('const ASSETS=[', 'const ASSETS=["./munkalap-project-tracking.js?v=1","./munkalap-project-tracking.css?v=1",', 1)
    p.write_text(text, encoding='utf-8')
    changes.append(name)
for name in ['munkalap-project-tracking.js', 'munkalap-project-tracking.css']:
    assert (own / name).is_file()
    shutil.copy2(own / name, target / name)
    changes.append(name)
print(json.dumps({'changed': changes, 'backup': str(backup), 'app_js_untouched': True}, ensure_ascii=False))
