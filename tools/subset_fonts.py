# 从 Noto Serif SC 可变字体切出 GB2312 全字符 + ASCII 的 Regular/Bold 两档。
# 用法: python tools/subset_fonts.py
# 源字体下载(gh-proxy 镜像, 直连 GitHub 不通):
#   curl -o tools/fontsrc/NotoSerifSC-var.ttf \
#     "https://gh-proxy.com/https://raw.githubusercontent.com/google/fonts/main/ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf"
import io
import os

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.join(os.path.dirname(__file__), '..')
SRC = os.path.join(ROOT, 'tools', 'fontsrc', 'NotoSerifSC-var.ttf')

# 字符集: ASCII + GB2312 全部(含一级/二级汉字与符号)
chars = set(chr(c) for c in range(0x20, 0x7F))
for hi in range(0xA1, 0xFF):
    for lo in range(0xA1, 0xFF):
        try:
            chars.add(bytes([hi, lo]).decode('gb2312'))
        except UnicodeDecodeError:
            pass
text = ''.join(sorted(chars))
print(f'目标字符数: {len(chars)}')

for wght, out in [
    (400, os.path.join(ROOT, 'assets', 'fonts', 'NotoSerifSC-Regular.otf')),
    (700, os.path.join(ROOT, 'assets', 'fonts', 'NotoSerifSC-Bold.otf')),
]:
    vf = TTFont(SRC)
    fixed = instancer.instantiateVariableFont(
        vf,
        {'wght': wght},
        updateFontNames=True,
    )
    buf = io.BytesIO()
    fixed.save(buf)
    buf.seek(0)

    opts = subset.Options()
    opts.hinting = False
    opts.desubroutinize = True
    opts.layout_features = ['kern']
    ss = subset.Subsetter(options=opts)
    ss.populate(text=text)
    font = TTFont(buf)
    ss.subset(font)
    font.flavor = None
    font.save(out)
    print(f'{out} -> {os.path.getsize(out) / 1024 / 1024:.2f} MB')
