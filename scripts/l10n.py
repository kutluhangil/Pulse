# Regenerates PulseUI's Localizable.xcstrings from every L("...") call and the
# Turkish translations in app/Packages/PulseKit/l10n/tr.json.
# Usage: python3 scripts/l10n.py app/Packages/PulseKit/l10n/tr.json
import re, glob, json, sys
import os
src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../app/Packages/PulseKit/Sources/PulseUI")
INT = {"snapshot.runningCount","stopped","container.exitCode","container.restartCount","snapshot.system.securityUpdates",
       "v","code","snapshot.host.threads","t.coresC.count","Int(ms)","u.days","u.hours","u.minutes","s.health.score",
       "Int(prefs.alerts.offlineHold)"}

def find_calls(s):
    out=[]; i=0
    while True:
        i=s.find('L("',i)
        if i<0: break
        if i>0 and (s[i-1].isalnum() or s[i-1]=='_'): i+=1; continue
        j=i+3; depth=0; buf=''
        while True:
            c=s[j]
            if c=='\\' and s[j+1]=='(':
                # interpolation: copy until matching paren
                k=j+2; d=1
                while d:
                    if s[k]=='(': d+=1
                    elif s[k]==')': d-=1
                    k+=1
                buf+=s[j:k]; j=k; continue
            if c=='\\': buf+=s[j:j+2]; j+=2; continue
            if c=='"': break
            buf+=c; j+=1
        out.append(buf); i=j
    return out

def key_of(raw):
    def rep(m):
        expr=m.group(1)
        return "%lld" if expr in INT else "%@"
    # replace \(expr) with balanced parens
    res=''; i=0
    while i<len(raw):
        if raw.startswith('\\(',i):
            k=i+2; d=1
            while d:
                if raw[k]=='(': d+=1
                elif raw[k]==')': d-=1
                k+=1
            expr=raw[i+2:k-1]
            res+= "%lld" if expr in INT else "%@"
            i=k
        else:
            # LocalizationValue escapes literal % as %% in the lookup key.
            res+= "%%" if raw[i]=="%" else raw[i]; i+=1
    return res

keys=[]
for f in sorted(glob.glob(src+"/*.swift")):
    for raw in find_calls(open(f).read()):
        k=key_of(raw)
        if k not in keys: keys.append(k)

TR = json.load(open(sys.argv[1]))
missing=[k for k in keys if k not in TR]
if missing:
    print("MISSING:"); [print(json.dumps(k, ensure_ascii=False)) for k in missing]; sys.exit(1)
extra=[k for k in TR if k not in keys]
if extra: print("unused tr keys:", extra)
cat={"sourceLanguage":"en","version":"1.0","strings":{}}
for k in keys:
    cat["strings"][k]={"localizations":{"tr":{"stringUnit":{"state":"translated","value":TR[k]}}}}
json.dump(cat, open(src+"/Resources/Localizable.xcstrings","w"), ensure_ascii=False, indent=2, sort_keys=True)
print("wrote", len(keys), "keys")
