# VNR202 Quest 2.0 — Database Neon PostgreSQL từ bộ tài liệu học

Mã nguồn website dạng game + **database khởi tạo từ số 0**. Nội dung học liệu được lấy từ **29 file PDF Session 1–29 do người dùng cung cấp**; mỗi trang văn bản trích xuất đều được lưu trong database và liên kết với bản PDF gốc.

> **Lưu ý:** Bộ source code và SQL là một database **sẵn sàng nạp lên Neon**, không phải một database Neon đang chạy. Chỉ bạn mới có quyền tạo project Neon trong tài khoản của mình hoặc cấp kết nối được ủy quyền. Không gửi chuỗi `DATABASE_URL` chứa mật khẩu cho bất kỳ ai.

## 1. Dữ liệu đã chuẩn bị

| Loại nội dung | Số lượng |
|---|---:|
| Môn học | 1: VNR202 |
| Chương/phần kiến thức | 4 (nhập môn + 3 chương) |
| Buổi học | 29 |
| PDF gốc | 29 |
| Trang nội dung PDF | 435 |
| Chiến dịch game | 6 |
| Câu hỏi trắc nghiệm kèm đáp án/giải thích/nguồn | 60 |
| Thẻ ghi nhớ (flashcard) có liên kết bài học | 60 |
| Mốc lịch sử | 13 |
| Loại huy hiệu định nghĩa sẵn | 4 |
| Bảng PostgreSQL | 19 |

Toàn bộ 435 trang là **văn bản trích xuất từ PDF** và có thể tìm kiếm; không phải 435 bài tóm tắt được biên soạn thủ công. Các sơ đồ, hình ảnh, bảng biểu hãy xem trong file PDF gốc. Ngân hàng 60 câu hỏi do trợ lý biên soạn từ tài liệu, hiện đánh dấu `review_needed` để giảng viên/người học rà soát trước khi coi là đề thi chính thức. Không tuyên bố đây là toàn bộ đề cương hoặc đề thi chính thức.

## 2. Tạo Neon PostgreSQL mới (chỉ cần làm một lần)

1. Truy cập https://console.neon.tech, đăng nhập hoặc tạo tài khoản.
2. Chọn **Create Project** và đặt tên **vnr202-quest**. Neon sẽ tạo database PostgreSQL mặc định, thường tên `neondb`.
3. Chọn **Connect**, sao chép PostgreSQL connection string (dạng `postgresql://...`). Có thể sử dụng **pooled URL** cho ứng dụng, và **direct URL** riêng cho lệnh nhập dữ liệu.
4. **KHÔNG chia sẻ password/URL thật**, không commit file `.env` lên GitHub.

### Cách A — Nạp tự động, khuyến nghị

Cài **Node.js 20.19+ hoặc Node.js 22.12+**. Giải nén gói ZIP, mở thư mục `vnr202-quest` bằng VS Code, và chạy trong terminal **PowerShell**:

```powershell
Copy-Item .env.example .env
notepad .env
```

Điền `DATABASE_URL` từ Neon. Có thể điền thêm `DIRECT_URL` nếu bạn có chuỗi direct, còn không thì chỉ cần `DATABASE_URL`.

```powershell
npm install
npm run db:init
npm run db:verify
npm run dev
```

- Website: **http://localhost:5173**
- API: **http://localhost:4000/api/health**
- Database đã được tạo và nạp tự động: **19 bảng**.

**Lưu ý:** `db:init` an toàn khi chạy lại đối với dữ liệu mẫu (`ON CONFLICT`): không tự xóa người chơi, điểm và lịch sử đã có. Các câu hỏi bạn tự thêm có ID khác được giữ lại.

### Cách B — Nạp thẳng trong Neon SQL Editor

- Tạo Neon project như trên.
- Mở **SQL Editor** rồi mở file `sql/neon-complete.sql`, dán toàn bộ nội dung và chạy.
- File này gồm DDL và dữ liệu, tự tạo bảng trước khi nhập dữ liệu.
- Vì file dài (khoảng 630 KB), nếu Neon SQL Editor giới hạn kích thước truy vấn, dùng **Cách A**.
- Sau khi nhập, chạy `sql/verify-counts.sql` trong Neon SQL Editor để kiểm tra.

> Dùng PostgreSQL 16/17 hoặc phiên bản Neon mặc định hiện có; schema không yêu cầu extension thương mại. Cần quyền tạo bảng và chạy `gen_random_uuid()`.

## 3. Cấu trúc database

Danh sách **19 bảng**:

**Dữ liệu học tập (7):** `courses`, `chapters`, `lessons`, `lesson_notes`, `source_documents`, `source_pages`, `timeline_events`.

**Câu hỏi và game (4):** `missions`, `questions`, `game_sessions`, `session_answers`.

**Người học & tiến độ (3):** `players`, `mission_progress`, `lesson_progress`.

**Ghi nhớ & cá nhân hóa (5):** `flashcards`, `flashcard_reviews`, `bookmarks`, `achievements`, `player_achievements`.

Kèm 2 view phục vụ tra cứu: `v_lesson_catalog` và `v_question_sources`.

Khóa ngoại quan trọng:

- `courses` → `chapters` → `lessons` → `source_documents` → `source_pages` (nội dung từng trang PDF).
- `questions` → `missions` và `source_pages` (nơi kiểm tra căn cứ câu trả lời).
- `flashcards` → `lessons`, `questions`, `source_pages`.
- `players` → `game_sessions` → `session_answers` và bảng `mission_progress`.
- `players` → `lesson_progress`, `flashcard_reviews`, `bookmarks`, `player_achievements`.

Các bảng phục vụ tiến độ và huy hiệu có thể trống khi mới cài vì chưa có người chơi. 4 loại huy hiệu đã có sẵn nhưng **API trao huy hiệu tự động chưa triển khai**.

Xem thêm sơ đồ ở `DATABASE.md`.

## 4. Thêm CÂU HỎI mới mà không cần viết SQL

1. Mở `data/questions-import-template.json`.
2. Copy mẫu để tạo câu mới, đổi `id` không trùng (ví dụ `custom-cau-001`) và đặt `position` chưa bị chiếm trong cùng `missionSlug` (bộ mặc định có vị trí 1–10 cho mỗi chiến dịch, dùng 11 trở lên).
3. Nhập đúng **4 lựa chọn** và `correctIndex` bắt đầu từ **0** (`0=A`, `1=B`, `2=C`, `3=D`).
4. Điền `sourceDocumentId` (ví dụ `session-11`) và `sourcePage` (số trang PDF đếm từ 1). Dữ liệu nguồn phải tồn tại.
5. Lưu file rồi chạy:

```powershell
npm run db:import:questions -- data/questions-import-template.json
npm run db:verify
```

Script kiểm tra dữ liệu, nhập câu hỏi và **tạo luôn flashcard tương ứng** trong một transaction. Nếu ID bị trùng hoặc trang nguồn không tồn tại thì rollback, không nạp nửa chừng. Câu mới có trạng thái `review_needed` cho đến khi được duyệt bằng SQL.

Để lấy danh sách chiến dịch và trang tài liệu có trong database:

```sql
SELECT slug, title FROM missions ORDER BY sort_order;
SELECT session_number,title,page_count FROM source_documents ORDER BY session_number;
```

Nếu muốn thêm ghi chú lý thuyết vào buổi học bằng SQL, xem `sql/add-lesson-note-example.sql`.

## 5. Thêm FILE PDF / BUỔI HỌC mới

Cài Python 3.10+ và PyMuPDF (`pip install pymupdf`), sau đó:

```powershell
python scripts/import-pdf.py "C:\Users\ADMIN\Downloads\Buoi30.pdf" --chapter chapter3 --title "Chuyên đề bổ sung"
npm run db:init
npm run db:sql
```

Script sẽ tự:

- Tìm số buổi tiếp theo (30, 31...), tạo ID `session-30`.
- Sao chép PDF vào `public/sources`, lấy SHA-256, trích văn bản theo từng trang, cập nhật `data/source-sessions.json`.
- Tạo bản sao `data/source-sessions.json.bak` để hoàn tác nếu cần.
- Khi chạy `npm run db:init`, các bảng nguồn và bản ghi buổi học mới được cập nhật lên Neon.
- Lệnh `npm run db:sql` xuất lại bộ SQL đầy đủ (nếu cần nhập vào database khác).

Không tự tạo câu hỏi từ PDF mới: bạn bổ sung các câu đã đối chiếu nguồn theo hướng dẫn mục 4. PDF ảnh scan cần OCR trước khi nhập.

## 6. Kiểm tra dữ liệu sau khi nạp

Chạy:

```powershell
npm run db:verify
npm run check
npm test
```

Hoặc trong Neon SQL Editor:

```sql
SELECT 'chapters' AS bang, count(*) FROM chapters
UNION ALL SELECT 'lessons',count(*) FROM lessons
UNION ALL SELECT 'source_pages',count(*) FROM source_pages
UNION ALL SELECT 'questions',count(*) FROM questions
UNION ALL SELECT 'flashcards',count(*) FROM flashcards;
```

Kết quả database **mới chưa thêm gì**: `chapters=4`, `lessons=29`, `source_pages=435`, `questions=60`, `flashcards=60`.

## 7. API hiện có

- `GET /api/health`: kiểm tra kết nối Neon.
- `GET /api/curriculum`: danh sách chương và buổi học.
- `GET /api/curriculum/lesson-01`: bài học, nội dung từng trang, ghi chú.
- `GET /api/flashcards?lessonId=lesson-01`: flashcard cho buổi học.
- `GET /api/library` và `GET /api/library/session-01`: thư viện PDF theo phiên bản đầu.
- `GET /api/timeline`: sự kiện lịch sử có dẫn nguồn.
- `GET /api/overview`: dashboard, tiến độ, bảng xếp hạng.
- `POST /api/players`, `POST /api/sessions`, `POST /api/sessions/:id/answer`, `POST /api/sessions/:id/finish`: game.

Giao diện web hiện có dashboard, 6 chiến dịch, thư viện PDF, timeline và leaderboard. **API/cấu trúc flashcard đã có, nhưng chưa có màn Flashcard riêng trên frontend**.

## 8. Triển khai lên Render

Repository đã có `Dockerfile` và `.dockerignore` để triển khai bằng Docker. Trong Render, chọn **Language: Docker**, **Branch: main**, **Dockerfile Path: `./Dockerfile`**, để trống **Root Directory** và **Docker Command**. Thêm `DATABASE_URL` trong phần Environment; không commit `.env` hoặc connection string lên GitHub.

Khởi tạo Neon một lần bằng `npm run db:init` từ môi trường có quyền kết nối database. Docker deploy không tự chạy lệnh này. Xem [RENDER-DEPLOY.md](./RENDER-DEPLOY.md) để biết các bước chi tiết.

## 9. Danh sách file trọng tâm

```text
vnr202-quest/
├─ Dockerfile                  # build Vite và chạy Express trên Render
├─ .dockerignore
├─ sql/
│  ├─ schema.sql               # 19 bảng + 2 view (chạy được nhiều lần)
│  ├─ neon-complete.sql        # 19 bảng + toàn bộ dữ liệu nguồn
│  ├─ verify-counts.sql        # SQL kiểm tra số lượng
│  └─ add-lesson-note-example.sql
├─ data/
│  ├─ source-sessions.json     # 29 buổi, văn bản của 435 trang PDF
│  └─ questions-import-template.json
├─ public/sources/            # 29 PDF gốc
├─ scripts/
│  ├─ init-db.js              # nhập tự động lên Neon
│  ├─ export-neon-sql.js      # tạo sql/neon-complete.sql
│  ├─ curriculum-data.js      # 4 chương, 29 lesson, 60 flashcard
│  ├─ import-questions.js     # thêm câu hỏi vào Neon
│  ├─ import-pdf.py           # thêm PDF mới vào project
│  └─ verify-db.js            # thống kê + kiểm tra nguồn
├─ server/                    # Express API
├─ src/                       # React dashboard
├─ DATABASE.md                # sơ đồ dữ liệu
├─ RENDER-DEPLOY.md           # hướng dẫn deploy Render bằng Docker
├─ .env.example
└─ package.json
```

## 10. Điều đã/ chưa được kiểm thử

- ✅ Kiểm tra cú pháp JavaScript phía server, script nhập và xuất SQL.
- ✅ 10 bài kiểm thử dữ liệu và logic, bao gồm checksum SHA-256 của 29 PDF nguồn.
- ✅ SQL đã được xuất nhất quán từ cùng dataset nguồn.
- ⚠️ **Chưa thể chạy SQL trên database Neon thật**, vì chưa có Neon project/connection string của người dùng. Không thể khẳng định DB đã được tạo trực tuyến.
- ⚠️ Môi trường biên soạn không tải được dependency frontend từ npm registry, nên chưa xác nhận thành công `npm run build`/chạy React end-to-end.
- ⚠️ Hệ thống dùng hồ sơ khách UUID, chưa có đăng nhập và phân quyền admin. **Không đưa tài khoản này lên production công khai** khi chưa bổ sung Auth và giới hạn truy cập; các endpoint game chưa chống gian lận mức giải đấu.
- ⚠️ Giữ quyền chia sẻ tài liệu gốc và không công khai bộ slide nếu bạn chưa có quyền phát hành.
"# VRN202" 
