"""Read only the limited Lua data syntax WoW uses for saved variables; never execute Lua."""
import re
MAX_SIZE = 2_000_000
TOKEN = re.compile(r'\s+|--[^\r\n]*|(?:[A-Za-z_][A-Za-z_0-9]*)|(?:-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)|(?:"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')|[{}\[\]=,;]', re.S)
class SavedDataError(ValueError): pass
class Parser:
    def __init__(self, source):
        if len(source.encode('utf-8')) > MAX_SIZE: raise SavedDataError('File too large')
        self.tokens=[]; pos=0
        while pos < len(source):
            m=TOKEN.match(source,pos)
            if not m: raise SavedDataError('Unsupported syntax')
            t=m.group(); pos=m.end()
            if not t.isspace() and not t.startswith('--'): self.tokens.append(t)
            if len(self.tokens)>100000: raise SavedDataError('Too many tokens')
        self.i=0
    def peek(self): return self.tokens[self.i] if self.i<len(self.tokens) else None
    def pop(self, expected=None):
        t=self.peek()
        if t is None or expected is not None and t != expected: raise SavedDataError('Unexpected token')
        self.i+=1; return t
    def string(self,t):
        value=bytearray(); s=t[1:-1]; i=0
        escapes={'a':7,'b':8,'f':12,'n':10,'r':13,'t':9,'v':11,'\\':92,'"':34,"'":39}
        while i<len(s):
            c=s[i]; i+=1
            if c!='\\': value.extend(c.encode('utf-8')); continue
            if i>=len(s): raise SavedDataError('Bad string escape')
            c=s[i]; i+=1
            if c in escapes: value.append(escapes[c])
            elif c.isdigit():
                digits=c
                while i<len(s) and len(digits)<3 and s[i].isdigit(): digits+=s[i]; i+=1
                n=int(digits)
                if n>255: raise SavedDataError('Bad byte escape')
                value.append(n)
            elif c=='\n': value.append(10)
            else: raise SavedDataError('Unsupported string escape')
        return value.decode('utf-8')
    def value(self, depth=0):
        if depth>20: raise SavedDataError('Nested too deeply')
        t=self.peek()
        if t=='{':
            self.pop('{'); result={}; index=1
            while self.peek()!='}':
                if self.peek() is None: raise SavedDataError('Incomplete table')
                if self.peek()=='[':
                    self.pop('['); key=self.value(depth+1); self.pop(']'); self.pop('=')
                    if not isinstance(key,(str,int)) or isinstance(key,bool): raise SavedDataError('Invalid key')
                    val=self.value(depth+1)
                elif re.fullmatch(r'[A-Za-z_]\w*',self.peek() or '') and self.i+1<len(self.tokens) and self.tokens[self.i+1]=='=':
                    key=self.pop(); self.pop('='); val=self.value(depth+1)
                else:
                    key=index; index+=1; val=self.value(depth+1)
                if key in result: raise SavedDataError('Duplicate key')
                result[key]=val
                if self.peek() in (',',';'): self.pop()
                elif self.peek()!='}': raise SavedDataError('Missing separator')
            self.pop('}'); return result
        t=self.pop()
        if t[:1] in ('"',"'"): return self.string(t)
        if t in ('true','false','nil'): return {'true':True,'false':False,'nil':None}[t]
        if re.fullmatch(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?',t): return float(t) if any(x in t for x in '.eE') else int(t)
        raise SavedDataError('Unsupported value')
    def parse(self):
        self.pop('AzerothWeatherDB'); self.pop('='); result=self.value()
        if self.peek() is not None or not isinstance(result,dict): raise SavedDataError('Unexpected trailing data')
        return result

def parse_saved(source): return Parser(source.lstrip('\ufeff')).parse()
