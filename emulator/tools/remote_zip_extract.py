#!/usr/bin/env python3
# Minimal HTTP-range-backed file-like object so zipfile can selectively
# extract members from a remote IPSW without downloading the whole thing.
import sys
import zipfile
import requests

class RangeFile:
    def __init__(self, url):
        self.url = url
        self.pos = 0
        r = requests.head(url, allow_redirects=True, timeout=30)
        self.length = int(r.headers["Content-Length"])

    def seek(self, offset, whence=0):
        if whence == 0:
            self.pos = offset
        elif whence == 1:
            self.pos += offset
        elif whence == 2:
            self.pos = self.length + offset
        return self.pos

    def tell(self):
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            end = self.length - 1
        else:
            end = min(self.pos + n, self.length) - 1
        if end < self.pos:
            return b""
        r = requests.get(self.url, headers={"Range": f"bytes={self.pos}-{end}"}, timeout=60)
        data = r.content
        self.pos += len(data)
        return data

    def seekable(self):
        return True


def main():
    url = sys.argv[1]
    members = sys.argv[2:]
    f = RangeFile(url)
    with zipfile.ZipFile(f) as zf:
        if not members:
            for n in zf.namelist():
                print(n)
            return
        for m in members:
            out = m.split("/")[-1]
            print(f"extracting {m} -> {out}", file=sys.stderr)
            with zf.open(m) as src, open(out, "wb") as dst:
                dst.write(src.read())

if __name__ == "__main__":
    main()
