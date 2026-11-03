"""Thêm PDF mới vào kho học liệu hiện tại. Cần: pip install pymupdf.
Ví dụ: python scripts/import-pdf.py "C:\\Downloads\\Buoi30.pdf" --chapter chapter3 --title "Chuyên đề bổ sung"
Sau đó chạy: npm run db:init (có DATABASE_URL).
"""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

try:
    import fitz  # PyMuPDF
except ImportError as exc:
    raise SystemExit('Thiếu thư viện PyMuPDF. Hãy chạy: pip install pymupdf') from exc

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description='Thêm buổi học từ PDF vào data/source-sessions.json và public/sources')
parser.add_argument('pdf', type=Path)
parser.add_argument('--chapter', required=True, choices=['intro','chapter1','chapter2','chapter3'])
parser.add_argument('--title', required=True)
args = parser.parse_args()

source_file = args.pdf.resolve()
if not source_file.is_file() or source_file.suffix.lower() != '.pdf':
    raise SystemExit('Vui lòng chỉ định một file PDF có thật.')
corpus_file = root / 'data' / 'source-sessions.json'
corpus = json.loads(corpus_file.read_text(encoding='utf-8'))
number = max((d['sessionNumber'] for d in corpus), default=0) + 1
if number > 999:
    raise SystemExit('Đã vượt giới hạn 999 buổi học.')
code = f'{number:02d}'
doc_id = f'session-{code}'
if any(x['id'] == doc_id for x in corpus):
    raise SystemExit('Trùng session id, không thể nhập.')

with fitz.open(source_file) as doc:
    if doc.needs_pass:
        raise SystemExit('PDF có mật khẩu, hãy mở khóa trước khi nhập.')
    pages = [{'pageNumber': i+1, 'content': doc[i].get_text('text', sort=True).replace('\x00','')}
             for i in range(doc.page_count)]
if not pages:
    raise SystemExit('File PDF không có trang nào.')
if not any(len(p['content'].strip()) > 50 for p in pages):
    raise SystemExit('PDF có thể là ảnh scan; chưa có nội dung văn bản để nhập. Hãy OCR trước.')

chapter_labels = {'intro':'Nhập môn','chapter1':'Chương 1','chapter2':'Chương 2','chapter3':'Chương 3'}
dest_name = f'Session-{code}.pdf'
destination = root / 'public' / 'sources' / dest_name
if destination.exists():
    raise SystemExit(f'File đích đã tồn tại: {destination}')
new_doc = {
    'id':doc_id, 'sessionNumber':number,'chapterKey':args.chapter,
    'chapterLabel':chapter_labels[args.chapter], 'title':args.title.strip(),
    'fileName':source_file.name, 'filePath':f'/sources/{dest_name}',
    'pageCount':len(pages), 'sha256':hashlib.sha256(source_file.read_bytes()).hexdigest(),
    'pages':pages
}
backup = corpus_file.with_suffix('.json.bak')
shutil.copy2(corpus_file,backup)
shutil.copy2(source_file,destination)
corpus.append(new_doc)
corpus.sort(key=lambda d:d['sessionNumber'])
corpus_file.write_text(json.dumps(corpus,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'✓ Đã thêm {doc_id}: {args.title} ({len(pages)} trang).')
print('✓ Đã giữ bản sao corpus cũ: data/source-sessions.json.bak')
print('Tiếp theo: npm run db:init; npm run db:sql (nếu cần xuất SQL mới).')
