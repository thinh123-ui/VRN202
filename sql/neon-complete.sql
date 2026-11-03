-- VNR202 QUEST: FULL NEON POSTGRESQL DATABASE
-- 29 PDF / 435 pages / 4 chapters / 29 lessons / 6 missions / 60 questions / 60 flashcards / 13 events
-- SAFE: ON CONFLICT UPSERT; does not delete players or game history
BEGIN;

CREATE TABLE IF NOT EXISTS players (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nickname VARCHAR(32) NOT NULL CHECK (char_length(trim(nickname)) BETWEEN 2 AND 32),
  avatar_key VARCHAR(20) NOT NULL DEFAULT 'astronaut',
  xp INTEGER NOT NULL DEFAULT 0 CHECK (xp >= 0),
  coins INTEGER NOT NULL DEFAULT 0 CHECK (coins >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS missions (
  slug TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  era TEXT NOT NULL,
  description TEXT NOT NULL,
  short_label TEXT NOT NULL,
  sort_order INTEGER NOT NULL UNIQUE,
  cover_symbol TEXT NOT NULL,
  color_key TEXT NOT NULL CHECK (color_key IN ('purple','blue','amber','pink','teal'))
);

CREATE TABLE IF NOT EXISTS questions (
  id TEXT PRIMARY KEY,
  mission_slug TEXT NOT NULL REFERENCES missions(slug) ON DELETE CASCADE,
  position SMALLINT NOT NULL,
  prompt TEXT NOT NULL,
  options JSONB NOT NULL CHECK (jsonb_typeof(options) = 'array' AND jsonb_array_length(options) = 4),
  correct_index SMALLINT NOT NULL CHECK (correct_index BETWEEN 0 AND 3),
  explanation TEXT NOT NULL,
  UNIQUE (mission_slug, position)
);

CREATE TABLE IF NOT EXISTS timeline_events (
  id TEXT PRIMARY KEY,
  event_year TEXT NOT NULL,
  event_date TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  period_key TEXT NOT NULL,
  sort_order INTEGER NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS game_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  mission_slug TEXT NOT NULL REFERENCES missions(slug),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  correct_count SMALLINT,
  xp_earned INTEGER,
  coins_earned INTEGER
);

CREATE TABLE IF NOT EXISTS session_answers (
  session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
  question_id TEXT NOT NULL REFERENCES questions(id),
  choice_index SMALLINT NOT NULL CHECK (choice_index BETWEEN 0 AND 3),
  is_correct BOOLEAN NOT NULL,
  answered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, question_id)
);

CREATE TABLE IF NOT EXISTS mission_progress (
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  mission_slug TEXT NOT NULL REFERENCES missions(slug),
  best_correct SMALLINT NOT NULL DEFAULT 0,
  attempts INTEGER NOT NULL DEFAULT 0,
  first_completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_played_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (player_id, mission_slug)
);

CREATE INDEX IF NOT EXISTS idx_sessions_player_date ON game_sessions(player_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_players_rank ON players(xp DESC, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_questions_mission ON questions(mission_slug, position);

-- Nguồn học liệu: 29 PDF Session, 435 trang. Mỗi câu hỏi có thể dẫn tới trang gốc.
CREATE TABLE IF NOT EXISTS source_documents (
  id TEXT PRIMARY KEY,
  session_number SMALLINT NOT NULL UNIQUE CHECK (session_number BETWEEN 1 AND 999),
  chapter_key TEXT NOT NULL,
  chapter_label TEXT NOT NULL,
  title TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  file_sha256 CHAR(64) NOT NULL,
  page_count SMALLINT NOT NULL CHECK (page_count > 0),
  imported_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS source_pages (
  document_id TEXT NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
  page_number SMALLINT NOT NULL CHECK (page_number > 0),
  content TEXT NOT NULL,
  PRIMARY KEY(document_id, page_number)
);

-- ADD COLUMN IF NOT EXISTS hỗ trợ nâng cấp database phiên bản cũ mà không xóa lịch sử chơi.
ALTER TABLE questions ADD COLUMN IF NOT EXISTS source_document_id TEXT REFERENCES source_documents(id);
ALTER TABLE questions ADD COLUMN IF NOT EXISTS source_page SMALLINT;
ALTER TABLE timeline_events ADD COLUMN IF NOT EXISTS source_document_id TEXT REFERENCES source_documents(id);
ALTER TABLE timeline_events ADD COLUMN IF NOT EXISTS source_page SMALLINT;
CREATE INDEX IF NOT EXISTS idx_source_documents_chapter ON source_documents(chapter_key, session_number);
CREATE INDEX IF NOT EXISTS idx_source_pages_fts ON source_pages USING GIN(to_tsvector('simple', content));
CREATE INDEX IF NOT EXISTS idx_questions_source ON questions(source_document_id, source_page);

-- ===========================================================================
-- VNR202 QUEST v2: cấu trúc học tập mở rộng (tương thích database v1).
-- Các bảng nguồn/quiz cũ được giữ nguyên, không xóa dữ liệu người chơi.
-- ===========================================================================

CREATE TABLE IF NOT EXISTS courses (
  slug TEXT PRIMARY KEY,
  code VARCHAR(20) NOT NULL UNIQUE,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  language_code VARCHAR(10) NOT NULL DEFAULT 'vi',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chapters (
  key TEXT PRIMARY KEY,
  course_slug TEXT NOT NULL REFERENCES courses(slug) ON DELETE RESTRICT,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  sort_order SMALLINT NOT NULL CHECK (sort_order >= 0),
  UNIQUE (course_slug, sort_order)
);

CREATE TABLE IF NOT EXISTS lessons (
  id TEXT PRIMARY KEY,
  chapter_key TEXT NOT NULL REFERENCES chapters(key) ON DELETE RESTRICT,
  document_id TEXT NOT NULL UNIQUE REFERENCES source_documents(id) ON DELETE RESTRICT,
  session_number SMALLINT NOT NULL UNIQUE CHECK (session_number > 0),
  title TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  sort_order SMALLINT NOT NULL UNIQUE CHECK (sort_order > 0),
  is_published BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_lessons_chapter ON lessons(chapter_key, sort_order);

-- Ghi chú biên tập để bổ sung kiến thức mới; trang nguồn là tùy chọn.
CREATE TABLE IF NOT EXISTS lesson_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id TEXT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  sort_order SMALLINT NOT NULL DEFAULT 1 CHECK (sort_order > 0),
  source_document_id TEXT,
  source_page SMALLINT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT lesson_note_source_pair CHECK ((source_document_id IS NULL) = (source_page IS NULL)),
  CONSTRAINT lesson_note_source_page_fk FOREIGN KEY (source_document_id, source_page)
    REFERENCES source_pages(document_id, page_number) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_lesson_notes_order ON lesson_notes(lesson_id,sort_order);

-- Tiến độ đọc của từng người học: không phụ thuộc lịch sử chơi game.
CREATE TABLE IF NOT EXISTS lesson_progress (
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  lesson_id TEXT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  last_page SMALLINT NOT NULL DEFAULT 1 CHECK (last_page > 0),
  completed_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (player_id, lesson_id)
);

-- Thẻ ghi nhớ: 60 thẻ mặc định lấy từ câu hỏi có tham chiếu slide.
CREATE TABLE IF NOT EXISTS flashcards (
  id TEXT PRIMARY KEY,
  lesson_id TEXT NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  question_id TEXT UNIQUE REFERENCES questions(id) ON DELETE SET NULL,
  front TEXT NOT NULL CHECK (length(trim(front)) > 0),
  back TEXT NOT NULL CHECK (length(trim(back)) > 0),
  explanation TEXT NOT NULL DEFAULT '',
  source_document_id TEXT,
  source_page SMALLINT,
  is_published BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT flashcard_source_pair CHECK ((source_document_id IS NULL) = (source_page IS NULL)),
  CONSTRAINT flashcard_source_page_fk FOREIGN KEY (source_document_id, source_page)
    REFERENCES source_pages(document_id, page_number) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_flashcards_lesson ON flashcards(lesson_id,id);

CREATE TABLE IF NOT EXISTS flashcard_reviews (
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  flashcard_id TEXT NOT NULL REFERENCES flashcards(id) ON DELETE CASCADE,
  confidence SMALLINT NOT NULL DEFAULT 0 CHECK (confidence BETWEEN 0 AND 5),
  review_count INTEGER NOT NULL DEFAULT 0 CHECK (review_count >= 0),
  last_reviewed_at TIMESTAMPTZ,
  next_review_at TIMESTAMPTZ,
  PRIMARY KEY (player_id, flashcard_id)
);
CREATE INDEX IF NOT EXISTS idx_flashcard_due ON flashcard_reviews(player_id,next_review_at);

-- Bookmark theo trang PDF, cho phép người học ghi chú cá nhân.
CREATE TABLE IF NOT EXISTS bookmarks (
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  document_id TEXT NOT NULL,
  page_number SMALLINT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (player_id, document_id, page_number),
  CONSTRAINT bookmark_page_fk FOREIGN KEY (document_id, page_number)
    REFERENCES source_pages(document_id, page_number) ON DELETE CASCADE
);

-- Các mốc huy hiệu cho game. Tặng huy hiệu sẽ được triển khai trong API sau.
CREATE TABLE IF NOT EXISTS achievements (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  icon_name TEXT NOT NULL,
  required_xp INTEGER CHECK (required_xp IS NULL OR required_xp >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS player_achievements (
  player_id UUID NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  achievement_code TEXT NOT NULL REFERENCES achievements(code) ON DELETE CASCADE,
  earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (player_id, achievement_code)
);

-- Thông tin duyệt nội dung để dễ dàng thêm/cập nhật câu hỏi về sau.
ALTER TABLE questions ADD COLUMN IF NOT EXISTS difficulty TEXT NOT NULL DEFAULT 'medium';
ALTER TABLE questions ADD COLUMN IF NOT EXISTS review_status TEXT NOT NULL DEFAULT 'review_needed';
ALTER TABLE questions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'questions_difficulty_allowed') THEN
    ALTER TABLE questions ADD CONSTRAINT questions_difficulty_allowed
      CHECK (difficulty IN ('easy','medium','hard'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'questions_review_status_allowed') THEN
    ALTER TABLE questions ADD CONSTRAINT questions_review_status_allowed
      CHECK (review_status IN ('draft','review_needed','approved','archived'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'questions_source_page_fk') THEN
    ALTER TABLE questions ADD CONSTRAINT questions_source_page_fk
      FOREIGN KEY (source_document_id,source_page)
      REFERENCES source_pages(document_id,page_number) ON DELETE RESTRICT;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_questions_review_status ON questions(review_status,difficulty);

-- Tiện ích tra cứu; không chứa dữ liệu thừa, luôn đọc bản mới nhất.
CREATE OR REPLACE VIEW v_lesson_catalog AS
SELECT l.id AS lesson_id, l.session_number, l.title AS lesson_title,
       c.key AS chapter_key,c.title AS chapter_title,
       sd.file_path AS pdf_url,sd.page_count,
       (SELECT COUNT(*) FROM questions q WHERE q.source_document_id=l.document_id) AS sourced_question_count,
       (SELECT COUNT(*) FROM flashcards f WHERE f.lesson_id=l.id) AS flashcard_count
FROM lessons l
JOIN chapters c ON c.key=l.chapter_key
JOIN source_documents sd ON sd.id=l.document_id;

CREATE OR REPLACE VIEW v_question_sources AS
SELECT q.id AS question_id,q.mission_slug,q.position,q.prompt,q.difficulty,q.review_status,
       sd.session_number,sd.title AS source_title,q.source_page,sd.file_path AS pdf_url
FROM questions q
LEFT JOIN source_documents sd ON sd.id=q.source_document_id;


INSERT INTO source_documents (id,session_number,chapter_key,chapter_label,title,file_name,file_path,file_sha256,page_count) VALUES
('session-01',1,'intro','Nhập môn','Đối tượng và chức năng của môn học','Session 1.pdf','/sources/Session-01.pdf','bf1a21e1a1bd06d8b3302b94deaa7cb468b426734f241155e818f8eded8bf588',11),
('session-02',2,'intro','Nhập môn','Phương pháp nghiên cứu và yêu cầu môn học','Session 2.pdf','/sources/Session-02.pdf','81ffb781c1ea72f0a4f850dccf57b675cbea46a64979ce74c04488377d496638',13),
('session-03',3,'chapter1','Chương 1 · 1930–1945','Bối cảnh lịch sử và Nguyễn Ái Quốc','Session 3.pdf','/sources/Session-03.pdf','6b248349a73b3ad117b276f8733423c436bd08665d81189a95f0707d11d80831',20),
('session-04',4,'chapter1','Chương 1 · 1930–1945','Thành lập Đảng và Cương lĩnh đầu tiên','Session 4.pdf','/sources/Session-04.pdf','c6b6bdd4a3544b69c6ca14db5fb865fe74932b4705b687668e7b0e3ef1545024',18),
('session-05',5,'chapter1','Chương 1 · 1930–1945','Phong trào cách mạng 1930–1935','Session 5.pdf','/sources/Session-05.pdf','edd4139bc472804fb4691ef8ad9bd5e3e324cc3ad69c8eb22aba128d45f10478',19),
('session-06',6,'chapter1','Chương 1 · 1930–1945','Phong trào dân chủ 1936–1939','Session 6.pdf','/sources/Session-06.pdf','a4d313a7d739cf10c3698ddad1290e5a48aaee6156c22b26461dd3b1f7dffa0e',12),
('session-07',7,'chapter1','Chương 1 · 1930–1945','Chuyển hướng chỉ đạo chiến lược 1939–1941','Session 7.pdf','/sources/Session-07.pdf','005eca91ceb310b9661be070fbdd7bfa5d3678e9ccbda38eda4a48e149f9f721',17),
('session-08',8,'chapter1','Chương 1 · 1930–1945','Chuẩn bị lực lượng khởi nghĩa 1941–1944','Session 8.pdf','/sources/Session-08.pdf','9ca2df017b21e92b62d5fbcffef00502f9de47d658ca398ed62121af4e0b5242',10),
('session-09',9,'chapter1','Chương 1 · 1930–1945','Cao trào kháng Nhật và Tổng khởi nghĩa 1945','Session 9.pdf','/sources/Session-09.pdf','79da99fa1679f604536cc3d630fc34f55117893d5fe28414265705e45fac4a99',13),
('session-10',10,'chapter1','Chương 1 · 1930–1945','Ý nghĩa và bài học Cách mạng Tháng Tám','Session 10.pdf','/sources/Session-10.pdf','76fad8e390581830505cd162f28a83370b603a7da1aab537b645749fb5fa0f59',10),
('session-11',11,'chapter2','Chương 2 · 1945–1975','Xây dựng chính quyền cách mạng 1945–1946','Session 11.pdf','/sources/Session-11.pdf','871e9121ddf02042480dbe9a194b0d7df0c3faef3608c9e87adfa3ffbc642d64',18),
('session-12',12,'chapter2','Chương 2 · 1945–1975','Toàn quốc kháng chiến và chiến dịch Việt Bắc','Session 12.pdf','/sources/Session-12.pdf','9efd93a858b15a745b3a588f597968c18a2d72f3f0f883a70ce88920264120ff',16),
('session-13',13,'chapter2','Chương 2 · 1945–1975','Đẩy mạnh kháng chiến chống Pháp 1951–1954','Session 13.pdf','/sources/Session-13.pdf','bf486cc4d1f9f33b3c77e30508ec7a0a0d56b5e9648f3c087e29714a6877cab7',18),
('session-14',14,'chapter2','Chương 2 · 1945–1975','Ý nghĩa và kinh nghiệm kháng chiến chống Pháp','Session 14.pdf','/sources/Session-14.pdf','1af36e62b129ea1f0a124243c283c738e01dab177abb795fa85eb4967cb6ca68',10),
('session-15',15,'chapter2','Chương 2 · 1945–1975','Cách mạng hai miền 1954–1960','Session 15.pdf','/sources/Session-15.pdf','c90eb9b61de000cf724fb90b814f72126c4865e5b852ff85879736ec6483a88b',18),
('session-16',16,'chapter2','Chương 2 · 1945–1975','Kháng chiến chống Mỹ giai đoạn 1961–1968','Session 16.pdf','/sources/Session-16.pdf','086ca4014aef06aed68af11209dbed4343c4ca32d08c07dac3d2c803286359b8',13),
('session-17',17,'chapter2','Chương 2 · 1945–1975','Kháng chiến chống Mỹ giai đoạn 1969–1975','Session 17.pdf','/sources/Session-17.pdf','c45260c6d4079f2ca58d84b2928a1ea727b1c4546e21fe9c5307e97ffedd5f00',14),
('session-18',18,'chapter2','Chương 2 · 1945–1975','Ý nghĩa lịch sử thắng lợi năm 1975','Session 18.pdf','/sources/Session-18.pdf','288e9a6e7f2618a3fe2646df0b4cb6d98e7b1cfeaddc81307be29bbf81988b61',10),
('session-19',19,'chapter3','Chương 3 · từ 1975','Thống nhất đất nước về mặt nhà nước','Session 19.pdf','/sources/Session-19.pdf','fa60500060c9d158f68ee14b6f3570eb397d52d90390954eac727492310ae43f',10),
('session-20',20,'chapter3','Chương 3 · từ 1975','Đại hội IV và xây dựng chủ nghĩa xã hội','Session 20.pdf','/sources/Session-20.pdf','e24e928363519852a9dc6efeca1bc0c36c3ddd8661cf5bab622567819dbe87ad',11),
('session-21',21,'chapter3','Chương 3 · từ 1975','Đại hội V và các bước đổi mới kinh tế','Session 21.pdf','/sources/Session-21.pdf','59a18f256e494ba95815189d8258e5f4482ac26a32baf9ec587f27f006dc57d2',10),
('session-22',22,'chapter3','Chương 3 · từ 1975','Đại hội VI và Đổi mới giai đoạn 1986–1996','Session 22.pdf','/sources/Session-22.pdf','f89733ee1fe103b24b5786056e84442898cdbbbd74135522fc76d0b26a156412',26),
('session-23',23,'chapter3','Chương 3 · từ 1975','Đại hội VIII và công nghiệp hóa','Session 23.pdf','/sources/Session-23.pdf','751b2bdaacb1867824eece518477c624e52516276ed3dedf489a7c7bf5727d34',14),
('session-24',24,'chapter3','Chương 3 · từ 1975','Đại hội IX và chiến lược phát triển','Session 24.pdf','/sources/Session-24.pdf','fb6343386ae8b18dd2b5a4f027fe6d47706403a7ed79e26041a84e331caf6f42',11),
('session-25',25,'chapter3','Chương 3 · từ 1975','Đại hội X và quá trình hội nhập','Session 25.pdf','/sources/Session-25.pdf','659cb27bf3e2185bc389f8d7403d4f6872274400540f811cb04c7f8d9d116738',23),
('session-26',26,'chapter3','Chương 3 · từ 1975','Đại hội XI và Cương lĩnh 2011','Session 26.pdf','/sources/Session-26.pdf','8e1aec30052a0eba8b2bf2c9aa647fa96c839e1f18113c5ccf3bea67e71fe5fd',22),
('session-27',27,'chapter3','Chương 3 · từ 1975','Đại hội XII và nhiệm vụ phát triển','Session 27.pdf','/sources/Session-27.pdf','60f55fd145c1107499fca2096804845d5f02124f9a1d95bb0a0d2e6a504099c6',23),
('session-28',28,'chapter3','Chương 3 · từ 1975','Thành tựu công cuộc Đổi mới','Session 28.pdf','/sources/Session-28.pdf','0daba4e8eead3cf5a8a4e12e99c4a8fd20cd5db25b6f9c764bdee267819f753f',13),
('session-29',29,'chapter3','Chương 3 · từ 1975','Nguyên nhân và tác hại của tham nhũng','Session 29.pdf','/sources/Session-29.pdf','ae4ef309ba99145718dddc10e5d013c5df9069af3fed0d7e2f0b91f611e2d8fc',12)
ON CONFLICT (id) DO UPDATE SET session_number=EXCLUDED.session_number,chapter_key=EXCLUDED.chapter_key,chapter_label=EXCLUDED.chapter_label,title=EXCLUDED.title,file_name=EXCLUDED.file_name,file_path=EXCLUDED.file_path,file_sha256=EXCLUDED.file_sha256,page_count=EXCLUDED.page_count;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-01',1,'Chương nhập môn'),
('session-01',2,'13/7/1992
                                                                          Chủ tịch Hội đồng Bộ trưởng
                                                                          ban hành biên soạn giáo trình quốc gia
Bộ môn Lịch sử Đảng Cộng sản Việt Nam            môn Lịch sử Đảng Cộng sản Việt Nam
là một chuyên ngành, là một bộ phận của
                                                                                  1962
          khoa học lịch sử                          Thành lập Ban nghiên cứu
                                                                      Lịch sử Đảng Trung ương
                                                                     (nay là Viện Lịch sử Đảng)

                                                                     Đại hội III (1960)
                                                          Nêu rõ nhiệm vụ tổng kết,
                                                                nghiên cứu lịch sử Đảng

                                                                     1933
                                                      Sơ khảo lịch sử
                                            phong trào cộng sản Đông Dương
                                                          (Hà Huy Tập)'),
('session-01',3,'I. Đối tượng nghiên cứu môn học
      Lịch sử Đảng Cộng sản Việt Nam

      II. Chức năng, nhiệm vụ của môn học
      Lịch sử Đảng Cộng sản Việt Nam                              Chương
                             nhập mônIII. Phương pháp nghiên cứu, học tập môn học
      Lịch sử Đảng Cộng sản Việt Nam

      IV. Mục đích, yêu cầu của môn học
      Lịch sử Đảng Cộng sản Việt Nam'),
('session-01',4,'I. Đối tượng nghiên cứu môn học Lịch sử Đảng Cộng sản Việt Nam

                 Các sự kiện                      Cương lĩnh,
                   lịch sử của Đảng                  đường lối của Đảng

                                            Lịch sử
                                 Đảng Cộng sản
                                              Việt Nam

               Làm rõ thắng lợi, thành tựu,                 Làm rõ hệ thống tổ chức Đảng,
                 kinh nghiệm, bài học cách mạng                      công tác xây dựng Đảng
                      Việt Nam do Đảng lãnh đạo                           qua các thời kỳ'),
('session-01',5,'I. Đối tượng nghiên cứu môn học Lịch sử Đảng Cộng sản Việt Nam

                               Cương lĩnh,
                             đường lối của Đảng
                                   2/1930                                  2011

                                                  10/1930                 1991
                                                         1951'),
('session-01',6,'II. Chức năng, nhiệm vụ của môn học Lịch sử Đảng Cộng sản Việt Nam

                          Chức năng nhận thức

       Chức năng của
          khoa học                           Chức năng giáo dục
         Lịch sử Đảng

                            Chức năng dự báo
                                 và phê phán'),
('session-01',7,'II. Chức năng, nhiệm vụ của môn học Lịch sử Đảng Cộng sản Việt Nam

Hệ thống tri thức về              Nhận thức quy luật                 Nhận thức về vai trò của Đảng
 Đảng cầm quyền,                   ra đời và phát triển                           là tổ chức duy nhất lãnh đạo
                                                                                                  cách mạng Việt Nam  Đảng chính trị                       của Đảng

                   Chức năng nhận thức

                  Nhận thức sự lãnh đạo của Đảng                Nhận thức rõ những vấn đề lớn của
                            là nhân tố hàng đầu quyết định                       đất nước, của dân tộc trong mối
                             cách mạng Việt Nam                         quan hệ với thời đại và thế giới'),
('session-01',8,'II. Chức năng, nhiệm vụ của môn học Lịch sử Đảng Cộng sản Việt Nam

                                      Tinh thần            Ý thức, niềm tự hào, tự tôn, ý chí tự lực,
                                        yêu nước                           tự cường dân tộc

                                   Lý tưởng             Mục tiêu chiến lược là độc lập dân tộc
                                        cách mạng                       và chủ nghĩa xã hội
Chức năng giáo dục
                                    Chủ nghĩa               Tinh thần chiến đấu bất khuất, đức hy sinh,
                                   anh hùng cách mạng             tính tiên phong, gương mẫu của Đảng viên

                                      Truyền thống của              Giáo dục đạo đức cách mạng, nhân cách,
                                 Đảng và dân tộc                                 lối sống cao đẹp'),
('session-01',9,'II. Chức năng, nhiệm vụ của môn học Lịch sử Đảng Cộng sản Việt Nam

                                                                     Tự phê bình và phê bình,Nhận thức quá khứ để hiểu rõ                          Chức năng dự báo                                                                                        kiên quyết phê phán những hiện tại và dự báo tương lai
                              và phê phán                      biểu hiện tiêu cực, suy thoái'),
('session-01',10,'II. Chức năng, nhiệm vụ của môn học Lịch sử Đảng Cộng sản Việt Nam

    Trình bày có hệ thống                                                    Tái hiện tiến trình lịch sử
Cương lĩnh, đường lối của Đảng                                           lãnh đạo, đấu tranh của Đảng

                            Nhiệm vụ của
                               khoa học
                                  Lịch sử Đảng

                                                     Làm rõ vai trò, sức chiến đấu
    Tổng kết lịch sử Đảng                                              của hệ thống tổ chức Đảng từ
                                                                 Trung ương đến địa phương'),
('session-01',11,'XIN CẢM ƠN')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-02',1,'Chương nhập môn'),
('session-02',2,'I. Đối tượng nghiên cứu môn học
      Lịch sử Đảng Cộng sản Việt Nam

      II. Chức năng, nhiệm vụ của môn học
      Lịch sử Đảng Cộng sản Việt Nam                              Chương
                             nhập mônIII. Phương pháp nghiên cứu, học tập môn học
      Lịch sử Đảng Cộng sản Việt Nam

      IV. Mục đích, yêu cầu của môn học
      Lịch sử Đảng Cộng sản Việt Nam'),
('session-02',3,'III. Phương pháp nghiên cứu, học tập môn học Lịch sử Đảng Cộng sản Việt Nam

                                                                       Phương pháp lịch sử
     Phương                                  Quán triệt                                                                        Các phương pháp                                    phương pháp luận                      Phương pháp logic      pháp                                                             cụ thể
                                              sử học    nghiên cứu                                                                        Khác'),
('session-02',4,'III. Phương pháp nghiên cứu, học tập môn học Lịch sử Đảng Cộng sản Việt Nam

                                    Quán triệt
                                       phương pháp luận
                                                 sử học
                                                            Quan điểm khách quan, toàn diện,
                                                                                phát triển và lịch sử cụ thể

     Chủ nghĩa duy vật biện chứng                                                                      Thực tiễn là tiêu chuẩn của chân lý

                                                                            Các mối quan hệ      Chủ nghĩa duy vật lịch sử                                                                                                    Nguyên nhân - Kết quả
                                                                                                   Hình thức - Nội dung
                                                                                                          Hiện tượng - Bản chất
                                                                                                              Cái chung - cái riêng
                                                                                                     Phổ biến - đặc thù'),
('session-02',5,'III. Phương pháp nghiên cứu, học tập môn học Lịch sử Đảng Cộng sản Việt Nam

                                         Các con đường, cách thức tìm hiểu và trình bày quá trình                 Phương pháp lịch sử                                            phát triển với đầy đủ tính cụ thể, sống động, quanh co

                      Các phương pháp
                              cụ thể

                                           Đi sâu tìm hiểu cái bản chất, cái phổ biến, cái lặp lại của sự vật                 Phương pháp logic                                             hiện tượng, phân tích, so sánh, tổng hợp với tư duy khái quát'),
('session-02',6,'III. Phương pháp nghiên cứu, học tập môn học Lịch sử Đảng Cộng sản Việt Nam

 Các phương pháp               Khác      cụ thể'),
('session-02',7,'IV. Mục đích, yêu cầu của môn học Lịch sử Đảng Cộng sản Việt Nam

              Đánh giá, kết hợp dựa trên luận cứ khoa học
                                                                Phản ánh lịch sử
Tính khoa học                                                                     khách quan, trung thực
               Sáng tạo, nghiêm túc và có trách nhiệm

                 Đứng trên lập trường chủ nghĩa Mác - Lênin và tư tưởng Hồ Chí Minh
    Tính
    đảng                   Lợi ích của giai cấp vô sản, nhân dân lao động và của dân tộc'),
('session-02',8,'IV. Mục đích, yêu cầu của môn học Lịch sử Đảng Cộng sản Việt Nam

                              1975 đến nay                 Đảng lãnh đạo cả nước quá độ lên                                                                              chủ nghĩa xã hội, bảo vệ Tổ quốc và
                                                                                       thực hiện công cuộc đổi mới

                                                 Đảng lãnh đạo hai cuộc kháng chiến giành
                                                             độc lập hoàn toàn, thống nhất đất nước và                 1945 - 1975
                                                          xây dựng chủ nghĩa xã hội trên miền Bắc

                        Đảng Cộng sản Việt Nam ra đời và1930 - 1945                             lãnh đạo đấu tranh giải phóng dân tộc'),
('session-02',9,'IV. Mục đích, yêu cầu của môn học Lịch sử Đảng Cộng sản Việt Nam

                                             Đảng Cộng sản Việt Nam ra đời và                  1930 - 1945                                                      lãnh đạo đấu tranh giải phóng dân tộc

Mâu thuẫn chủ yếu của xã hội              Sự thất bại của các phong trào                                                           Đảng Cộng sản Việt Namthuộc địa, phong kiến Việt Nam                 yêu nước và khủng hoảng
                                                                                      ra đờicuối thế kỷ XIX, đầu thế kỷ XX                  đường lối cứu nước'),
('session-02',10,'IV. Mục đích, yêu cầu của môn học Lịch sử Đảng Cộng sản Việt Nam

                                               Đảng Cộng sản Việt Nam ra đời và                     1930 - 1945                                                         lãnh đạo đấu tranh giải phóng dân tộc

    1930 -                     1936 -                     1939 -
     1931                      1939                      1945
 Cao trào            Phong trào           Phong trào
cách mạng             dân chủ                 giải phóng
                                         dân tộc'),
('session-02',11,'IV. Mục đích, yêu cầu của môn học Lịch sử Đảng Cộng sản Việt Nam

                                 Đảng lãnh đạo hai cuộc kháng chiến giành
                                          độc lập hoàn toàn, thống nhất đất nước và    1945 - 1975
                                        xây dựng chủ nghĩa xã hội trên miền Bắc'),
('session-02',12,'IV. Mục đích, yêu cầu của môn học Lịch sử Đảng Cộng sản Việt Nam

                                      Đảng lãnh đạo cả nước quá độ lên
                                            chủ nghĩa xã hội, bảo vệ Tổ quốc và     1975 đến nay
                                                   thực hiện công cuộc đổi mới'),
('session-02',13,'XIN CẢM ƠN')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-03',1,'ĐẢNG CỘNG SẢN VIỆT NAM RA ĐỜI
VÀ LÃNH ĐẠO ĐẤU TRANH GIÀNH CHÍNH QUYỀN
                  (1930 - 1945)

            Chương 1'),
('session-03',2,'Phong trào cách mạng 1930 - 1931 và
          Bối cảnh lịch sử
                                                                   khôi phục phong trào 1932 - 1935
Nguyễn Ái Quốc chuẩn bị các điều kiện
         để thành lập Đảng                                Phong trào dân chủ 1936 - 1939

                                                                           Lãnh đạo quá trình đấu tranh          Đảng Cộng sản Việt Nam ra đời &
            Cương lĩnh chính trị đầu tiên                                                        giành chính quyền                 Chương 1                  của Đảng (2/1930)                                                                  (1930 - 1945)

 Thành lập Đảng Cộng sản Việt Nam và                          Phong trào giải phóng dân tộc
 Cương lĩnh chính trị đầu tiên của Đảng                                  1939 - 1945
   Ý nghĩa lịch sử của việc thành lập                          Tính chất, ý nghĩa và bài học kinh nghiệm
      Đảng Cộng sản Việt Nam                                 của Cách mạng Tháng Tám 1945'),
('session-03',3,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                                 Bối cảnh lịch sử
Tình hình thế giới

                                               Đế      Nửa sau thế kỷ XIX
                                                    quốc
     Tự do          Độc
    cạnh tranh         quyền

      Chủ nghĩa tư bản
                                       Nhân dân lao động       Nhân dân thuộc địa
                                                                               Á, Phi, Mỹ latinh                                                      chính quốc'),
('session-03',4,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                                 Bối cảnh lịch sử
                                              1920
                                    Sơ khảo lần thứ nhất nhữngTình hình thế giới                                    luận cương về vấn đề dân tộc
                                       và vấn đề thuộc địa
                                                                                                         Phong trào
                                                                 Phong trào                                                                                                                                                   giải phóng                                                  Đế                                                                        vô sản                                                                                                           dân tộc
                                                       quốc

 Cách mạng Tháng 10 Nga                                           Nhân dân lao động       Nhân dân thuộc địa           1917                                       3/1919                                                          chính quốc             Á, Phi, Mỹ latinh                           Quốc tế Cộng sản'),
('session-03',5,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                              Bối cảnh lịch sử
Tình hình                Việt Nam nằm ở vị trí địa chính trị quan trọng của Châu Á
Việt Nam

                                    1/9/1858 Pháp nổ súng tấn công Đà Nẵng'),
('session-03',6,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                              Bối cảnh lịch sử
Tình hình
Việt Nam

                              Hiệp ước               Hiệp ước
                              Giáp Tuất               Patenotre                                                                                                         Việt Nam trở thành
                                                                                 “một xứ thuộc địa, dân ta là vong                                                         6/6/1884              1862    1874   1883                                                                                         quốc nô, Tổ quốc ta bị giày xéo
                                                                                              dưới gót sắt của kẻ thù hung ác”                   Hiệp ước               Hiệp ước
              Nhâm Tuất           Harman

   Nhà Nguyễn
   Vua Tự Đức'),
('session-03',7,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                               Bối cảnh lịch sử
 Tình hình
  Việt Nam

Lập chính quyền thuộc địa
                    Chính trị      “Chia để trị”                                        Chính sách                              Chính sách “ngu dân”                                       Văn hóa                                                                                     Lập nhà tù nhiều hơn trường học                                                      cai trị của                                                                                   Rượu cồn & thuốc phiện                                              xã hội                                            thực dân Pháp                                                                                              “Khai hóa văn minh Đại Pháp”
     Lần 1: 1897 - 1914
                    Khai thác    Lần 2: 1919 - 1929
 Bóc lột tài nguyên, lao động
     Thuế khóa nặng nề'),
('session-03',8,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                                  Bối cảnh lịch sử
     Tình hình
     Việt Nam
             Câu kết với Pháp
                                                                    Ra đời muộn hơn công nhânNêu cao tinh thần dân tộc                          Giai cấp địa chủ                                                                     Giai cấp tư sản
Lãnh đạo phong trào nông dân      bị phân hóa                                                                           Tư sản mại bản & tư sản dân tộc
                                          Chính sách      Kinh doanh theo lối tư bản
                                                         cai trị của
                                               thực dân Pháp      Hơn 90% dân số                                                  Nhanh chóng phát triển
  Chịu hai tầng bóc lột                                             Giai cấp công nhân Chủ yếu xuất thân từ nông dân                         Giai cấp nông dân
    Tinh thần cách mạng                                                                       Ra đời trong cuộc khai thác thuộc địa
                                              Tầng lớp tiểu tư sản &
                                                                             sĩ phu phong kiến'),
('session-03',9,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                                   Bối cảnh lịch sử
     Tình hình
      Việt Nam

                      Giai cấp công nhân

                      Giai cấp nông dân
                                                                 Chính sách
                                                                                      cai trị củaNhững mâu thuẫn mới                        Giai cấp tư sản                                                                        thực dân Pháp      xuất hiện

                       Giai cấp địa chủ
                               bị phân hóa     Mâu thuẫn chủ yếu nhất là
                                              giữa toàn thể dân tộc
                       Tầng lớp tiểu tư sản &    Việt Nam với thực dân Pháp
                                        sĩ phu phong kiến
                                         và phản động tay sai'),
('session-03',10,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                              Bối cảnh lịch sử
Tình hình                                          Bác Tôn Đức Thắng
                                                1919 Tham gia bảo vệ nước Nga Xô viết
Việt Nam
                                                                             Các luồng tư tưởng
                                                                                 bên ngoài

                                                                1917   Cách mạng Tháng Mười Nga

                                                                  1911   Cách mạng Tân Hợi Trung Quốc

                                                         1898  Vận động Duy Tân ở Trung Quốc

                                                         1868  Duy Tân Nhật Bản

                                                           1789  Cách mạng Tư sản Pháp

                                                           Phan Văn Trường
                                                     1923 công bố “Tuyên Ngôn của Đảng Cộng sản”'),
('session-03',11,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                                 Bối cảnh lịch sử
Các phong trào yêu nước                      Phong trào Cần Vương
 của nhân dân Việt Nam                                                                                       1885 - 1896
   trước khi có Đảng

                            Hệ tư tưởng
                               phong kiến
           Hoàng Hoa Thám
                                        Vua Hàm Nghi  Tôn Thất Thuyết

                              Phong trào
                               nông dân

        Khởi nghĩa Yên Thế
                   Cuối thế kỷ 19 - Đầu thế kỷ 20'),
('session-03',12,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                                Bối cảnh lịch sửCác phong trào yêu nước
 của nhân dân Việt Nam
   trước khi có Đảng
       Xu hướng cải cách                        Xu hướng bạo động

                              Trào lưu
                            dân chủ
                                  tư sản

         Phan Châu Trinh                             Phan Bội Châu
       “Bất bạo động, bạo động tắc                                Phong trào Đông Du
        tử”    “Khai dân trí, chấn dân khí, hậu dân sinh”                                                                        Việt Nam Quang phục Hội'),
('session-03',13,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                                Bối cảnh lịch sửCác phong trào yêu nước
 của nhân dân Việt Nam
   trước khi có Đảng                                             Tiểu tư sản
                                                             trí thức
           Việt Nam Quốc dân Đảng
         Thành lập tháng 12/1927 tại Bắc Kỳ       “Không thành công thì thành nhân”

             Nguyễn Thái Học                                                     Khởi Nghĩa Yên Bái tháng 2/1930'),
('session-03',14,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
                                  Bối cảnh lịch sử  Các phong trào yêu nước
  của nhân dân Việt Nam
     trước khi có Đảng

                              Trào lưu                                                  Hệ tư tưởng   Nguyên nhân thất bại       dân chủ                                                       phong kiến                Đặt ra yêu cầu                                  tư sản
Thiếu đường lối chính trị đúng đắn                                                      cấp thiết phải có một
                                                                                          tổ chức tiên phong,Chưa giải quyết mâu thuẫn cơ bản
                                                                         đường lối cứu nước
Chưa tập hợp được toàn dân tộc                                                                           đúng đắn                                Tiểu tư sản                  Phong trào
Phương pháp chưa thích hợp                                            trí thức                    nông dân'),
('session-03',15,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
          Nguyễn Ái Quốc chuẩn bị các điều kiện để thành lập Đảng

   5/6/1911
   "Dù màu da có khác nhau, trên đời này chỉ có hai giống người:
            giống người bóc lột và giống người bị bóc lột"'),
('session-03',16,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
               Nguyễn Ái Quốc chuẩn bị các điều kiện để thành lập Đảng

                                                                   Đến Liên Xô, làm việc tại
                                                                         Quốc tế Cộng sản
             Bản yêu sách của nhân dân An Nam                 1920                       1923        1917
               Tham gia Đảng Xã hội Pháp
Cách mạng tháng 10 Nga                         Sơ khảo lần thứ nhất những     Tán thành gia nhập
                                                  luận cương về vấn đề dân tộc      Quốc tế Cộng sản                          1919                                                  và vấn đề thuộc địa                                                                      Sáng lập Đảng Cộng sản Pháp

  “Cách mạng đến nơi”'),
('session-03',17,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
             Nguyễn Ái Quốc chuẩn bị các điều kiện để thành lập Đảng

                                                             Chuẩn bị
                                                                          về tư tưởng
        1921
Hội Liên Hiệp thuộc địa

    Báo Le Paria
  (Người Cùng khổ)

Viết bài báo Nhân đạo,
 Đời sống công nhân, ...

     Trưởng tiểu ban                                                                 “Đảng muốn vững thì phải có chủ nghĩaNghiên cứu về Đông Dương                                                                 làm cốt, trong Đảng ai cũng phải hiểu,
                                                                                            ai cũng phải theo chủ nghĩa ấy”
Lên án chủ nghĩa thực dân, kêu gọi, thức tỉnh
  nhân dân bị áp bức đấu tranh giải phóng'),
('session-03',18,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
             Nguyễn Ái Quốc chuẩn bị các điều kiện để thành lập Đảng

                                                             Chuẩn bị
              Cách mạng vô sản                                                                          về chính trị
                 ở chính quốc
“Trước hết phải có
 đảng cách mệnh

                                                                            Tự do, hạnh phúc cho đồng bào                                                       Giải phóng dân tộc
                                                                                Xây dựng nhà nước mang lại                    Các dân tộc                                                      Giải phóng giai cấpđể trong thì vận động                                                                      quyền và lợi ích cho nhân dân                           bị áp bức
và tổ chức dân chúng,
                    Cách mạng ngoài thì liên lạc với
dân tộc bị áp bức và vô
sản giai cấp mọi nơi...”                Công - nông
           Các giai tầng bị bóc lột khác'),
('session-03',19,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
             Nguyễn Ái Quốc chuẩn bị các điều kiện để thành lập Đảng

                                                       Xuất bản Báo Thanh niên    Chuẩn bị
     về tổ chức

                                                              Hội Việt Nam                    Đến Quảng Châu                                                                                                         Huấn luyện
                                                              Cách mạng                                                                                                                                     cán bộ                              11/1924“đi vào quần chúng, thức tỉnh                                       Thanh niên
                                   2/1925 họ, tổ chức họ, đoàn kết họ,
huấn luyện họ, đưa họ ra đấu                           Cộng sản đoàn                                                          6/1925 tranh giành tự do, độc lập”
                                                                                    Đại học Phương Đông (Liên Xô)
                                                                                  Trường Quân sự Hoàng Phố (Trung Quốc)'),
('session-03',20,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-04',1,'ĐẢNG CỘNG SẢN VIỆT NAM RA ĐỜI
VÀ LÃNH ĐẠO ĐẤU TRANH GIÀNH CHÍNH QUYỀN
                  (1930 - 1945)

            Chương 1'),
('session-04',2,'Phong trào cách mạng 1930 - 1931 và
            Bối cảnh lịch sử                                                                  khôi phục phong trào 1932 - 1935
 Nguyễn Ái Quốc chuẩn bị các điều kiện để
                                                        Phong trào dân chủ 1936 - 1939           thành lập Đảng

                                                                          Lãnh đạo quá trình đấu tranh         Đảng Cộng sản Việt Nam ra đời &
           Cương lĩnh chính trị đầu tiên                                                        giành chính quyền                 Chương 1                của Đảng (2/1930)                                                                  (1930 - 1945)

Thành lập Đảng Cộng sản Việt Nam và                        Phong trào giải phóng dân tộc
Cương lĩnh chính trị đầu tiên của Đảng                               1939 - 1945
  Ý nghĩa lịch sử của việc thành lập                       Tính chất, ý nghĩa và bài học kinh nghiệm
     Đảng Cộng sản Việt Nam                               của Cách mạng Tháng Tám 1945'),
('session-04',3,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
      Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng

 Các tổ chức cộng sản
       ra đời
                                                                                   Kỳ bộ Bắc Kỳ thành lập
                                                                                                                            chi bộ cộng sản đầu tiên      Sự phát triển của phong trào yêu nước theo khuynh hướng vô sản
                                                                                                            3/1929                      Mang tính chính trị sâu sắc Hình thức sơ khai
                           Có sự lãnh đạo  Bỏ trốn tập thể                                                                1928 - 1929 gấp
                            Có sự liên kết   Phá giao kèo,                                                                               2.5 lần 1926 - 1927
                           Có sức lôi cuốnđưa đơn phản kháng
                                                                                                     Hội Việt Nam
                                                                                                    Cách mạng                     Trước 1914     1919-1925     1926-1929
                                                                                              Thanh niên                                                                                  Không còn
                                                                                                             thích hợp và
           Hình thức phát triển                                                                                   đủ sức lãnh đạo
            Phổ biến bãi công
           Quy mô lớn và
                  thời gian dài'),
('session-04',4,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
      Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng

Các tổ chức cộng sản
       ra đời                            Nửa cuối năm 1929

                                                                                         Kêu gọi Quốc tế Cộng sản thừa nhận                                               17/6/1929
                                                                                                                           tổ chức của từng Đảng                               Đông Dương cộng sản Đảng

                                         Phân tử tiên tiến của Tân Việt thành lập
                                       Đông Dương cộng sản liên đoàn (9/1929)

                                                                                                 "Việc thiếu một Đảng cộng sản duy nhất trong lúc phong
                                                  11/1929                                      trào quần chúng công nhân và nông dân ngày càng phát
                              An Nam cộng sản Đảng                                    triển, đã trở thành một điều nguy hiểm vô cùng cho tương
                                                                                                                          lai trước mắt của cuộc cách mạng Đông Dương"'),
('session-04',5,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
    Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng

   Hội nghị thành lập
Đảng Cộng sản Việt Nam

                                 Cửu Long
                                   (Hồng Kông)
                                                              6/1 - 7/2/1930

                                                                                       Trịnh Đình Cửu                                                                                                              Châu Văn Liêm                                                                                        Nguyễn Ái Quốc
                                                                                             Phái viên Quốc tế Cộng sản
                                                                                   Chủ trì

                                        23/12/1929                                                                            Nguyễn Đức Cảnh                            Nguyễn Thiệu
                                                    Đông Dương                 An Nam
                                                      Cộng sản Đảng                 Cộng sản Đảng'),
('session-04',6,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
   Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng

        Hội nghị thành lập                                                                             Bỏ mọi thành kiến
     Đảng Cộng sản Việt Nam                                                                                  xung đột cũ ... thống nhất
                                                                                                     các nhóm cộng sản

                                                                                  Định tên Đảng là
                                                                        Đảng Cộng sản Việt Nam

                       Năm điểm lớn của                  Thảo Chính cương và
                                                                                     Điều lệ sơ lược của Đảng                              Nguyễn Ái Quốc

                                                                               Định kế hoạch việc thực
                                                                                                hiện thống nhất trong nước

  Đại biểu của                   Thảo luận ý kiến                                                                           Cử mộtQuốc tế Cộng sản
                       của đại biểu                                              Ban Trung ương lâm thời  nói lí do của
                  Quốc tế cộng sản   Hội nghị'),
('session-04',7,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
    Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng

         Hội nghị thành lập                                                            Chánh cương vắn tắt,
      Đảng Cộng sản Việt Nam                                       Thông qua các                Sách lược vắn tắt,
                                           văn kiện                                                             Chương trình tóm tắt,
                                                                      Điều lệ vắn tắt

                                                   “Đảng Cộng sản Việt Nam tổ chức ra để lãnh đạo quần
                                      Tôn chỉ mục đích                                                        chúng lao khổ làm giai cấp tranh đấu để tiêu trừ tư bản                                              của Đảng
                                                              đế quốc chủ nghĩa, làm cho thực hiện xã hội cộng sản”

Các thống nhất của Hội nghị                                   “tin theo chủ nghĩa cộng sản, chương trình đảng và                                    Quy định điều kiện                                                   Quốc tế cộng sản, hăng hái tranh đấu và dám hy sinh                                               vào Đảng
                                                            phục tùng mệnh lệnh Đảng và đóng kinh phí ...”'),
('session-04',8,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
    Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng

         Hội nghị thành lập                                              - Khi về nước các đại biểu tổ chức
      Đảng Cộng sản Việt Nam                                   một Trung ương lâm thời để                              - Xây dựng tổ chức công hội,
                                             lãnh đạo cách mạng        Chủ trương     nông hội, cứu tế, tổ chức phản đế
                                                            hành động                                               - Quy định thành lập hệ thống                            - Xuất bản một tạp chí lý luận
                                               tổ chức Đảng từ chi bộ đến                         và ba tờ báo tuyên truyền
                                            Trung ương

                                                                        Đông Dương
                                                                                         cộng sản
                                                                                                                   liên đoàn
Các thống nhất của Hội nghị                                                               24/2/1930
                                     Hoàn thành thống nhất thành một chính đảng duy nhất'),
('session-04',9,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
  Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng
                                                  Nội dung bản
                                          Cương lĩnh chính trị
                                             đầu tiên của Đảng

                         Cương lĩnh chính trị
                              đầu tiên
                                của Đảng

   Chánh cương vắn tắt                                            Sách lược vắn tắt'),
('session-04',10,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
      Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng
                                                         Nội dung bản
                                                Cương lĩnh chính trị
                                                   đầu tiên của Đảng

    Mục tiêu                                                              Phương pháp
    chiến lược                                                                         cách mạng

                             Cương lĩnh chính trị   Nhiệm vụ                                                             Đoàn kết
                                  đầu tiênchủ yếu trước mắt                                                                    quốc tế
                                     của Đảng
   Lực lượng                                                                     Vai trò lãnh đạo
   cách mạng                                                                      của Đảng'),
('session-04',11,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
    Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng

        Nội dung bản
                                                  “chủ trương làm tư sản dân quyền c.m và     Cương lĩnh chính trị
     đầu tiên của Đảng                                                      thổ địa c.m để đi tới xã hội cộng sản”

                       Mục tiêu chiến lược

Cương lĩnh chính trị                           “Đánh đổ đế quốc chủ nghĩa Pháp và bọn phong kiến,
     đầu tiên                                   làm cho nước Nam hoàn toàn độc lập
     của Đảng

                               Đế quốc
                                                            Phong        Nhiệm vụ
                                     chủ nghĩa                                                                         chủ yếu trước mắt                                                                           kiến
                                    Pháp'),
('session-04',12,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
     Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng
      Nội dung bản
   Cương lĩnh chính trị                                            Phương diện kinh tế
   đầu tiên của Đảng                                                                                                  Chính phủ                                                                          Quốc trái
                                                                         Tư bản đế quốc                                                                                                       công nông binh
      Phương diện xã hội                                                 chủ nghĩa Pháp                                                                                                 quản lí

                                                                              Dân cày
                                                             Đế quốcDân chúng được                                                                                                           nghèo, loại
                                                                        chủ nghĩa                                                                                               Toàn bộ ruộng đất  tự do tổ chức                                                                                                   bỏ sưu thuế

                              Nhiệm vụ
                                               Mở mangNam nữ bình quyền                                  chủ yếu
                                                                    công nông nghiệp                                      trước mắt

Phổ thông giáo dục                                                       Thi hành luật
theo công nông hóa                                                 ngày làm tám giờ'),
('session-04',13,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
    Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng
   Nội dung bản
Cương lĩnh chính trị
 đầu tiên của Đảng                Công                  Nông                                                Hai lực lượng cơ bản
                         nhân                    dân
                             Lãnh đạo

                                Tất cả                                                     Yêu nước
                                  lực lượng tiến bộ Lực lượng cách mạng
                     Đảng “phải thu phục cho được đại bộ phận giai cấp mình ... đại bộ phận dân cày,
                                                          ... hết sức liên lạc với tiểu tư sản, trí thức và trung nông ... để kéo họ đi vào phe vô sản
                              giai cấp. Còn đối với bọn phú nông, trung, tiểu địa chủ và tư bản An Nam mà chưa rõ
                          mặt phản c.m thì phải lợi dụng, ít lâu mới làm cho họ đứng trung lập”'),
('session-04',14,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
    Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng
   Nội dung bản
 Cương lĩnh chính trị
 đầu tiên của Đảng                                                         Phương pháp
                                                                   cách mạng          Bạo lực cách mạng của quần chúng,
                                                      không thỏa hiệp trong bất cứ hoàn cảnh nào

                                                     Tinh thần         Cách mạng Việt Nam
                                                 đoàn kếtlà một bộ phận của cách mạng vô sản thế giới                                                      quốc tế

                              Vai trò                  “Đảng là đội tiên phong của vô sản giai cấp phải
                             lãnh đạo                                                          thu phục cho được đại bộ phận giai cấp mình, phải
                             của Đảng                                                    làm cho giai cấp mình lãnh đạo được dân chúng”'),
('session-04',15,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
    Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng
   Nội dung bản
Cương lĩnh chính trị                            Phản ánh súc tích luận điểm
 đầu tiên của Đảng                                  cơ bản của cách mạng Việt Nam

                                                       Thể hiện bản lĩnh chính trị
                                                            độc lập, tự chủ, sáng tạo
                    Cương lĩnh
                        chính trị                                               Đánh giá đúng mâu thuẫn cơ bản
                    đầu tiên của                                                        và chủ yếu của dân tộc Việt Nam
                     Đảng

                                                Đánh giá đúng thái độ
                                                                 các giai tầng trong xã hội

                                           Thỏa mãn nhu cầu phát triển
                                                 của thực tiễn cách mạng'),
('session-04',16,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
    Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng

    Ý nghĩa lịch sử
   của việc thành lập
Đảng Cộng sản Việt Nam
                                       Chấm dứt khủng hoảng
                                                đường lối cứu nước

                    Chủ nghĩa                  Phong trào              Phong trào
                   Mác - Lênin                    công nhân                 yêu nước'),
('session-04',17,'I. Đảng Cộng sản Việt Nam ra đời & Cương lĩnh chính trị đầu tiên của Đảng (2/1930)
   Thành lập Đảng Cộng sản Việt Nam & Cương lĩnh chính trị đầu tiên của Đảng
                                         Ý nghĩa lịch sử
                                                    của việc thành lập
                                        Đảng Cộng sản Việt Nam    Lần đầu tiên cách mạng                                                              Đáp ứng nhu cầu cơ bản và
   Việt Nam có một cương lĩnh                                                                               cấp bách của xã hội Việt Nam  chính trị khách quan, khoa học

                                                                          Là sự vận dụng đúng đắnPhù hợp với tiến trình phát triển
                                                                                  chủ nghĩa Mác - Lênin vào  theo quy luật của cách mạng
                                                                                             điều kiện thực tiễn Việt Nam

     Khẳng định lựa chọn                                                           Trở thành nhân tố hàng đầu
     con đường cách mạng:                                                                quyết định đưa cách mạng
  con đường cách mạng vô sản                                                                  Việt Nam đi tới thắng lợi'),
('session-04',18,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-05',1,'ĐẢNG CỘNG SẢN VIỆT NAM RA ĐỜI
VÀ LÃNH ĐẠO ĐẤU TRANH GIÀNH CHÍNH QUYỀN
                  (1930 - 1945)

            Chương 1'),
('session-05',2,'Phong trào cách mạng 1930 - 1931 và
           Bối cảnh lịch sử                                                      khôi phục phong trào 1932 - 1935
Nguyễn Ái Quốc chuẩn bị các điều kiện để
                                                        Phong trào dân chủ 1936 - 1939          thành lập Đảng

                                                                          Lãnh đạo quá trình đấu tranh         Đảng Cộng sản Việt Nam ra đời &
           Cương lĩnh chính trị đầu tiên                                                        giành chính quyền                 Chương 1                 của Đảng (2/1930)                                                                  (1930 - 1945)

 Thành lập Đảng Cộng sản Việt Nam và                          Phong trào giải phóng dân tộc
 Cương lĩnh chính trị đầu tiên của Đảng                                   1939 - 1945
   Ý nghĩa lịch sử của việc thành lập                           Tính chất, ý nghĩa và bài học kinh nghiệm
      Đảng Cộng sản Việt Nam                                 của Cách mạng Tháng Tám 1945'),
('session-05',3,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                Phong trào cách mạng
                                                                                   1930 - 1931
           1929 - có vốn tích lũy,
       sản xuất được máy móc thiết yếu

          1927 Công nghiệp vượt xa
          mức trước Thế chiến I

        1929 Nông nghiệp khôi phục          Đạt được nhiều thành quả quan trọng
         bằng mức trước Thế chiến I              trong công cuộc xây dựng đất nước'),
('session-05',4,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
        Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                              Phong trào cách mạng
                                                                                                1930 - 1931

                                                               Số nhà
                                                              xây mới
                                                          giảm 80%                                    Công nghiệp                         50 triệu người
                                        giảm 45%                                    thất nghiệp

   Các nước tư bản chủ nghĩa
diễn ra khủng hoảng 1929 - 1933                         5000                                                                                         Sản xuất
                            ngân hàng                                                                                                    đình trệ
                             phá sản'),
('session-05',5,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
        Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                              Phong trào cách mạng
                                                                                                1930 - 1931

                                        Phong trào
                                            cách mạng thế giới
                                           dâng cao

   Các nước tư bản chủ nghĩa                                        Đạt được nhiều thành quả quan trọng
diễn ra khủng hoảng 1929 - 1933                                              trong công cuộc xây dựng đất nước'),
('session-05',6,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
         Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                              Phong trào cách mạng
                                                                                                1930 - 1931

                                                          Tăng cường bóc lột bù đắp
                                                            hậu quả khủng hoảng

   Các nước tư bản chủ nghĩa
diễn ra khủng hoảng 1929 - 1933

                              Pháp bị khủng hoảng
                                                               Chiến dịch khủng bố trắng
                                                                    Đông Dương                                                          đàn áp khởi nghĩa Yên Bái'),
('session-05',7,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
      Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                          Phong trào cách mạng
 Xô Viết Nghệ Tĩnh                                                                          1930 - 1931
                                                Chết 171 người                              9/1930

                                                 Cuộc biểu tình của nông dân                                                                                                 Nhiều cuộc biểu tình lớn của nông dân ở                                                 phủ Hưng Nguyên (Nghệ An)                                                                                                                  hai tỉnh Nghệ An và Hà Tĩnh                                                           12/9/1930

                                        5/1930 phát triển thành cao trào

  Bãi công của công nhân nhà máy                      1/5/1930 kỷ niệm Quốc tế lao động               Nổ ra 121 cuộc đấu tranh trên cả nước.
  ximang Hải Phòng, dầu Nhà Bè,                  Có 16 cuộc bãi công của công nhân,                Nổi bật tổng bãi công KCN Bến Thủy - Vinh
  đồn điền Phú Riềng, Dầu Tiếng,                      34 cuộc biểu tình nông dân,                            "Một thời kỳ mới,
dệt Nam Định, diêm và cưa Bến Thủy                4 cuộc đấu tranh của dân thành thị                         thời kỳ đấu tranh kịch liệt đã đến"

     Tháng 1 - 4/1930                                                                            6 - 8/1930'),
('session-05',8,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935
                                                                                 Phong trào cách mạng
                                                                                    1930 - 1931
                                                Đầu năm 1931
                                             Phong trào
                                                        Hàng ngàn người chiến sĩ                                                    cách mạng
                                                                     cộng sản và yêu nước bị
                                                                                         bắt, giết, tù đày

            Kết hợp bạo lực với chính trị
                                                                   4/1931                                             Xô viết
                                              Nghệ Tĩnh                                                           Toàn bộ BCH TW Đảng bị bắt Cưỡng bức      Tổ chức
                          Nhận thẻ                  không còn một ủy viên nào
 dân cày ra       rước cờ                                                                   "Các tổ chức Đảng và của                             quy thuận
  đầu thú         vàng                                    quần chúng tan rã hầu hết"'),
('session-05',9,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935
                                                                                 Phong trào cách mạng
                                            Khẳng định trong
                                                                                    1930 - 1931                                                     thực tế quyền lãnh
                                                 đạo và năng lực
                                                     của Đảng

                      Phát triển tinh                                        Rèn luyện đội
                     thần yêu nước, mở                                       ngũ cán bộ, đảng
                    đường cho thắng                                                  viên và quần
                                    Xô viết                                    lợi về sau                                             chúng yêu nước
                                     Nghệ Tĩnh

                                    Để lại nhiều
                                                      bài học
                                              kinh nghiệm'),
('session-05',10,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
       Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935
                                                                                      Luận cương chính trị của
                                                                                Đảng Cộng sản Đông Dương,
                                                                                                    10/1930

    14 đến 31/10/1930
                                                     Đảng Cộng sản          Đảng Cộng sản                             Hội nghị
                                                                           Việt Nam             Đông Dương                            Ban
                            Chấp
                              hành
                               Trung
                             ương lần
                                thứ nhất                                       Thông qua Luận cương chính trị                                            Tổng bí thư Trần Phú
                                                                                  của Đảng Cộng sản Đông DươngHương Cảng, Trung Quốc'),
('session-05',11,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
        Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935
                                                                                       Luận cương chính trị của
                                                                                 Đảng Cộng sản Đông Dương,
                                                                                                     10/1930

   Xác định                                                                            Lực lượng và
  mâu thuẫn                                                                           lãnh đạo cách mạng

Phương hướng                                                             Phương pháp
  chiến lược                                                                         cách mạng

  Nhiệm vụ                                                            Quan hệ với
                                                                                   cách mạng thế giới    cốt yếu'),
('session-05',12,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
        Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935
                                                                                       Luận cương chính trị của
                                                                                 Đảng Cộng sản Đông Dương,
                                      “một bên thì thợ             “một bên thì địa chủ,              10/1930
   Xác định                                            thuyền, dân cày và            phong kiến, tư bổn và
  mâu thuẫn                                            các phần tử lao khổ”              đế quốc chủ nghĩa”

                                          “cách mạng tư sản dân quyền”,             “phát triển, bỏ qua thời kỳ tư bổn mà tranhPhương hướng
                                           “có tánh chất thổ địa và phản đế”           đấu thẳng lên con đường xã hội chủ nghĩa”  chiến lược

                                                             “tranh đấu để đánh đổ các di tích phong kiến, đánh đổ các cách bóc lột                                      “Cái cốt”  Thổ địa
                                                                  theo lối tiền tư bổn và để thực hiện thổ địa cách mạng cho triệt để”
  Nhiệm vụ
    cốt yếu
                                                          “đánh đổ đế quốc chủ nghĩa Pháp,
                                        Phản đế                                                     làm cho Đông Dương hoàn toàn độc lập”'),
('session-05',13,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
       Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935
                                                                                      Luận cương chính trị của
                                                                               Đảng Cộng sản Đông Dương,
                                                                                                    10/1930
                                Giai cấp vô sản và nông dân là hai động lực chính,
                               trong đó giai cấp vô sản là động lực chính và mạnh
                                                                                      Lực lượng và
 “cần phải có một Đảng Cộng sản có một đường lối chánh trị đúng đắn, có kỷ luật, tập                                                                                       lãnh đạo cách mạng
trung, mật thiết liên lạc với quần chúng, và từng trải qua tranh đấu mà trưởng thành”

                                                                       Phương pháp                           “võ trang bạo động”, “phải theo khuôn phép nhà binh”
                                                                                   cách mạng

                                                                    Quan hệ với   Là một bộ phận của cách mạng vô sản thế giới, đoàn kết với giai cấp vô sản thế giới,
                                                                                  cách mạng thế giới                    trước hết là vô sản Pháp và phong trào ở thuộc địa, nửa thuộc địa'),
('session-05',14,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
     Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935
                                                                                   Luận cương chính trị của
                                                                            Đảng Cộng sản Đông Dương,
                                                                                                10/1930
                                                                 Khẳng định lại nhiều
                                                                    vấn đề của Cương lĩnh
 Nguyên nhân
                                                                                   Không nêu được mâu thuẫn cơ bản,
                                                                                           nên xác định nhiệm vụ chưa đúng
  Nhận thức chưa
 đầy đủ về thực tiễn                   Ý nghĩa và                                                                     Đánh giá không đúngcách mạng thuộc địa
                                 hạn chế của                      lực lượng cách mạng
                               Luận Cương
  Chịu ảnh hưởng                                                                                 Phủ nhận vai trò của tiểu tư sản,
   tả khuynh của                                                                                                     tư sản dân tộc, địa chủ vừa và nhỏ
 Quốc tế Cộng sản
                                                               Chưa thiết lập được
                                                                      mối liên minh'),
('session-05',15,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
       Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                                     Cuộc đấu tranh khôi phục tổ chức
                                                                                                             và phong trào cách mạng,
                                                                                                       Đại hội Đảng lần thứ I (3/1935)
                                          Thường vụ
                Tổng bí thư              Trung ương phê phán
                 Trần Phú             Xứ ủy Trung Kỳ sai
                          bị bắt               lầm về “thanh Đảng”
                                                                                                “Hãy giữ vững    3/1931     18/4/1931   11/4/1931      5/1931     6/9/1931
                                                                                                                                    chí khí chiến đấu!”
   Hội nghị                Quốc tế Cộng sản              Tổng Bí thư
  Trung Ương                  công nhận Đảng             Trần Phú hy sinh
quyết định nhiều                    là chi bộ độc lập
vấn đề thúc đẩy
   đấu tranh'),
('session-05',16,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
       Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                                       Cuộc đấu tranh khôi phục tổ chức
                                                                                                              và phong trào cách mạng,
                                                                                                         Đại hội Đảng lần thứ I (3/1935)

Nhà tù Hỏa Lò (Hà Nội)
                        Thành lập các Chi bộ nhà tù
                 Đấu tranh chống khủng bố, hà khắc lao tù
                    Huấn luyện, bồi dưỡng đảng viên
                           Biên soạn tài liệu, ra báo bí mật
 Khám Lớn (Sài Gòn)                                                                  Nguyễn Đức Cảnh        Lý Tự Trọng
                                                                                            viết tổng kết công tác    “Con đường của thanh
                                                                  vận động công nhân      niên chỉ có thể là con
                                                                            trong xà lim án chém     đường cách mạng”

   Nhà tù Côn Đảo'),
('session-05',17,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
 Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                          Cuộc đấu tranh khôi phục tổ chức
                                                                                                 và phong trào cách mạng,
                                                                                            Đại hội Đảng lần thứ I (3/1935)
        1932                       Đầu năm 1934
                                                     Thành lập Ban Chỉ huy ở  Chương trình hành động của
                                                               ngoài của Đảng Cộng sản      Công hội, Nông hội,
                                                Đông Dương có chức năng như  Thanh niên Cộng sản đoàn ...
                                                 Ban Chấp hành Trung ương
Chương trình hành động của Đảng
                                Đầu năm 1935 “gây dựng một đoàn thể bí mật,
                                               Hệ thống tổ chức đảng được   có kỷ luật nghiêm ngặt cứng
                                Đồng chí                                                       phục hồi, tiến tới Đại hội lần thứ I   như sắt, vững như đồng...”
                                    Lê Hồng Phong'),
('session-05',18,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
         Phong trào cách mạng 1930 - 1931 và khôi phục phong trào 1932 - 1935

                                                                                                          Cuộc đấu tranh khôi phục tổ chức
                                                                                                                  và phong trào cách mạng,
3/1935 Đại hội đại biểu lần thứ I của Đảng Cộng sản Đông Dương                                           Đại hội Đảng lần thứ I (3/1935)
              họp tại Ma Cao (Trung Quốc)

                                                          Củng cố và phát triển Đảng

                                           Ba
                                                        Đẩy mạnh cuộc vận động                                            nhiệm vụ
                                                                            tập hợp quần chúng                                                      trước
                                           mắt                                                                                 Tuyên truyền chống đế quốc,
                                                                                      chống chiến tranh, ủng hộ Liên Xô, ...
                              Tổng bí thư
                               Lê Hồng Phong
                                                      “Người ta không thể làm cách mạng phản đế, sau đó mới làm cách
                                             mạng điền địa. Cách mạng sẽ chỉ thắng lợi với điều kiện hai cuộc
                                                            cách mạng ấy gắn bó chặt chẽ với nhau và cùng đi với nhau”'),
('session-05',19,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-06',1,'ĐẢNG CỘNG SẢN VIỆT NAM RA ĐỜI
VÀ LÃNH ĐẠO ĐẤU TRANH GIÀNH CHÍNH QUYỀN
                  (1930 - 1945)

            Chương 1'),
('session-06',2,'Phong trào cách mạng 1930 - 1931 và
           Bối cảnh lịch sử                                                                  khôi phục phong trào 1932 - 1935
Nguyễn Ái Quốc chuẩn bị các điều kiện để
                                               Phong trào dân chủ 1936 - 1939          thành lập Đảng

                                                                          Lãnh đạo quá trình đấu tranh         Đảng Cộng sản Việt Nam ra đời &
           Cương lĩnh chính trị đầu tiên                                                        giành chính quyền                 Chương 1                 của Đảng (2/1930)                                                                  (1930 - 1945)

 Thành lập Đảng Cộng sản Việt Nam và                          Phong trào giải phóng dân tộc
 Cương lĩnh chính trị đầu tiên của Đảng                                  1939 - 1945
   Ý nghĩa lịch sử của việc thành lập                           Tính chất, ý nghĩa và bài học kinh nghiệm
      Đảng Cộng sản Việt Nam                                 của Cách mạng Tháng Tám 1945'),
('session-06',3,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                    Phong trào dân chủ 1936 - 1939
    Điều kiện lịch sử
                                Nguy cơ chiến tranh đe dọa và chủ trương của Đảng
                                 nền hòa bình và an ninh quốc tế
Tình hình thế giới

       Khủng hoảng kinh tế                                                              Hình thành phe
     làm mâu thuẫn dâng cao                                                                       Trục phát xít

                                   Giai cấp tư sản một số nơi chủ trương
                                dùng bạo lực chia lại thị trường'),
('session-06',4,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                      Phong trào dân chủ 1936 - 1939
        Điều kiện lịch sử
     và chủ trương của Đảng
                                                                   Chủ trương của
                                                                      Quốc tế Cộng sản   Tình hình thế giới

                                                                             Kẻ thù nguy hiểm trước mắt
                                                                                                                là chủ nghĩa phátxít

                                                                                  Nhiệm vụ trước mắt:
                                                                                       chống phátxít, chống chiến tranh,
                                                                                          bảo vệ dân chủ và hòa bình
    Tổng bí thư
  Lê Hồng Phong                                                                                         Giai cấp công nhân
                                                                                                       phải thống nhất hàng ngũ,được bầu làm Ủy viên                                                                                                            lập mặt trận nhân dân rộng rãi
  Ban Chấp hành
  Quốc tế Cộng sản'),
('session-06',5,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                      Phong trào dân chủ 1936 - 1939
        Điều kiện lịch sử
     và chủ trương của Đảng

   Tình hình thế giới

                                                Ban bố nhiều quyền tự do,                                                                                       Tạo điều kiện
                                                    dân chủ, có những quyền                                                                                              thuận lợi
                                                         được áp dụng ở thuộc địa

 Mặt trận nhân dân Pháp do Đảng Cộng sản Pháp
làm nòng cốt giành thắng lợi trong Tổng tuyển cử 1936
    Ra đời Chính phủ Mặt trận nhân dân Pháp'),
('session-06',6,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                        Phong trào dân chủ 1936 - 1939
                                                    Tổng bí thư            Điều kiện lịch sử                                                                                    Đồng chí            Đồng chí                                                       Lê Hồng Phong
        và chủ trương của Đảng                                                                        Hà Huy Tập         Phùng Chí Kiên                                                          chủ trì
                                                 Nhằm “sửa chữa những
                                                                                   sai lầm” trước đó và
       26/7/1936                                                                    “định lại chính sách mới”
                                                                          theo nghị quyết của                         Hội nghị
                                                           Quốc tế Cộng sản
                         Ban
                         Chấp
                                                Nhiệm vụ trước mắt: chống phátxít, chống chiến tranh đế quốc,                           hành
                                                chống phản động thuộc địa và tay sai, đòi tự do, dân chủ, cơm áo và hòa bình                           Trung
                                                                       “lập Mặt trận nhân dân phản đế rộng rãi ...                           ươngThượng Hải, Trung Quốc                                 để cùng nhau tranh đấu đòi những điều dân chủ đơn sơ”

                                                                                            Công khai, nửa công                                                        Bí mật,                                                                                                                            khai, hợp pháp, nửa hợp
                                              không hợp pháp                        pháp kết hợp bí mật và                                                                              Chuyển hình thức                                                                                                                      bất hợp pháp
                                                                                            hoạt động'),
('session-06',7,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào dân chủ 1936 - 1939
   Điều kiện lịch sử
và chủ trương của Đảng

             Nhận thức mới của Đảng về hai nhiệm vụ phản đế và điền địa

       “Nếu phát triển cuộc tranh đấu chia
       đất mà ngăn trở cuộc đấu tranh phản                                     Cần chọn địch nhân                                                          Chống đế                                                                                                                   chính, nguy hiểm nhất                                                                            Điền địa       đế thì phải lựa chọn vấn đề nào quan                        quốc      mà đánh cho toàn thắng
          trọng hơn mà giải quyết trước”

               "Chung quanh vấn đề chiến sách mới" 10.1936'),
('session-06',8,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào dân chủ 1936 - 1939
Phong trào đấu tranh
  đòi tự do, dân chủ,
  cơm áo, hòa bình
                                                         Đầu năm 1937, tổ chức “đón rước”,
                                                                                “míttinh, biểu tình, đưa đơn dân nguyện”                  Mít tinh, hội họp

                          Ủy ban trù bị
                       Đông Dương đại hội

                                                                        Godart                      Brevie
                                                                   Phái viên Chính phủ Pháp   Toàn quyền Đông Dương
                                                                                       mới sang nhậm chức
                  “Dân nguyện”'),
('session-06',9,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                       Phong trào dân chủ 1936 - 1939
        Phong trào đấu tranh
           đòi tự do, dân chủ,
         cơm áo, hòa bình                                    Lĩnh vực báo chí, tuyên truyền

                                          1938                         1938    Tổng bí thư Hà Huy Tập                                                                  Thành lập Hội truyền bá quốc ngữ
                           Qua Ninh (Trường Chinh) &             Hải Triềuviết "Tờrốtxky và phản cách mạng"
                            Vân Đình (Võ Nguyên Giáp)'),
('session-06',10,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào dân chủ 1936 - 1939
Phong trào đấu tranh
  đòi tự do, dân chủ,
  cơm áo, hòa bình

                            Thành lập       1937 - 1938           Viện Dân biểu Bắc Kỳ, Trung Kỳ
                        Mặt trận dân      Vận động                                                            Hội đồng quản hạt Nam Kỳ
                            chủ Đông Dương       tranh cử                                                        Hội đồng kinh tế lý tài Đông Dương
     Hội nghị
 Trung ương Đảng
  29 - 30/3/1938

                                    Bầu đồng chí Nguyễn Văn Cừ
                                            làm Tổng bí thư'),
('session-06',11,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                    Phong trào dân chủ 1936 - 1939
  Phong trào đấu tranh
    đòi tự do, dân chủ,
    cơm áo, hòa bình

                                                Giải quyết quan                               Xây dựng Mặt
                                              hệ mục tiêu chiến                                     trận thống nhất
                                                   lược và mục tiêu                                 phù hợp, phân
                                                    trước mắt                                         hóa, cô lập kẻ thù

                                                       Phong trào dân chủ
                                                                 1936 - 1939

                                             Kết hợp tổ chức bí                                    Đấu tranh nghị
                                                                                                                                   trường, mặt trận báo                                      mật và công khai
                                                                                                                                                                  chí, đòi các quyền tự           9/1939                                                để tập hợp quần
Thực dân Pháp đàn áp cách mạng                                                                         do dân sinh dân chủ,                                               chúng                                                              bãi công lớn
 Đảng rút vào hoạt động bí mật
 Cuộc vận động dân chủ kết thúc'),
('session-06',12,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-07',1,'ĐẢNG CỘNG SẢN VIỆT NAM RA ĐỜI
VÀ LÃNH ĐẠO ĐẤU TRANH GIÀNH CHÍNH QUYỀN
                  (1930 - 1945)

            Chương 1'),
('session-07',2,'Phong trào cách mạng 1930 - 1931 và
           Bối cảnh lịch sử                                                                  khôi phục phong trào 1932 - 1935
Nguyễn Ái Quốc chuẩn bị các điều kiện để
                                                        Phong trào dân chủ 1936 - 1939          thành lập Đảng

                                                                          Lãnh đạo quá trình đấu tranh         Đảng Cộng sản Việt Nam ra đời &
           Cương lĩnh chính trị đầu tiên                                                        giành chính quyền                 Chương 1                 của Đảng (2/1930)                                                                  (1930 - 1945)

 Thành lập Đảng Cộng sản Việt Nam và                     Phong trào giải phóng dân tộc
 Cương lĩnh chính trị đầu tiên của Đảng                                1939 - 1945
   Ý nghĩa lịch sử của việc thành lập                           Tính chất, ý nghĩa và bài học kinh nghiệm
      Đảng Cộng sản Việt Nam                                 của Cách mạng Tháng Tám 1945'),
('session-07',3,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
               Phong trào giải phóng dân tộc 1939 - 1945
   Bối cảnh lịch sử và
chủ trương chiến lược mới
       của Đảng

         Tháng 9/1939 Thế chiến thứ II bùng nổ

                           Các chính phủ Pháp       Đàn áp dân chủ
            trong nước
                                                                                                                   6/1941
                                                                    6/1940 Pháp
                                                                                             Đức tấn công
                                                                   đầu hàng Đức
                                                                                                                         Liên Xô

        Đàn áp phong                    Chính phủ
           trào thuộc địa
                       Daladier         Chính phủ
                                   của Thủ tướng Pétain'),
('session-07',4,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
               Phong trào giải phóng dân tộc 1939 - 1945
   Bối cảnh lịch sử và
chủ trương chiến lược mới
       của Đảng
                  28/9/1939                                                      Toàn quyền Đông Dương
                                                       Georges Catroux                 Cấm tuyên truyền cộng sản
                   Đặt Đảng Cộng sản Đông Dương                             9/1940
                                                                                  đầu hàng Nhật                           ra ngoài vòng pháp luật
                        Giải tán hội đoàn, cấm tụ tập, ...

                              Phátxít hóa bộ máy
                         Tăng cường vơ vét'),
('session-07',5,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
               Phong trào giải phóng dân tộc 1939 - 1945
   Bối cảnh lịch sử và
chủ trương chiến lược mới
       của Đảng

                                     Hội nghị Ban Chấp hành Trung ương (11/1939)
                                                    tại Bà Điểm (Hóc Môn, Gia Định) - Lần VI

 Chủ trương
                                             Hội nghị Cán bộ Trung ương (11/1940)
  chiến lược                                                         tại Đình Bảng (Từ Sơn, Bắc Ninh) - Lần VII
  của Đảng

                                     Hội nghị Ban Chấp hành Trung ương (5/1941)
                                                         tại Pác Pó (Cao Bằng) - Lần VIII'),
('session-07',6,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                    Phong trào giải phóng dân tộc 1939 - 1945
           Bối cảnh lịch sử và
        chủ trương chiến lược mới
                                                 Hội nghị Ban Chấp hành Trung ương (11/1939)              của Đảng
                                                                         tại Bà Điểm (Hóc Môn, Gia Định)

      Rút vào                                                  Lấy quyền lợi dân tộc làm tối cao,
  hoạt động bí mật                                                           tất cả mọi vấn đề đều hướng vào nó

Chuyển trọng tâm công tác                                                        Giải phóng              Vấn đề điền
  về nông thôn, đồng thời                                                 dân tộc                         địa vẫn chú trọng thành thị

                                                      "Bước đường sinh tồn của các dân tộc Đông Dương không còn con đường
                                                   nào khác hơn là con đường đánh đổ đế quốc Pháp, chống tất cả ách ngoại
                                                     xâm, vô luận da trắng hay da vàng để giành lấy giải phóng độc lập"                             29/9/1939
              "Hoàn cảnh Đông Dương sẽ tiến bước                                                              Chủ trương thành lập
                 đến vấn đề giải phóng dân tộc"                                                   Mặt trận dân tộc thống nhất phản đế Đông Dương'),
('session-07',7,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                 Phong trào giải phóng dân tộc 1939 - 1945
      Bối cảnh lịch sử và
   chủ trương chiến lược mới
          của Đảng                                    Hội nghị Cán bộ Trung ương (11/1940)
                                                               tại Đình Bảng (Từ Sơn, Bắc Ninh) - Lần VII

                                        Cách mạng          Cách mạng                                                                                       "Phải
                                                                              đồng                                         phản đế                thổ địa
                                                                                                        tiến"

17/1/1940 Tổng bí thư
 Nguyễn Văn Cừ và                                         "Mặc dầu lúc này khẩu hiệu cách mạng phản đế -
nhiều đồng chí Ủy viên                                              cách mạng giải phóng dân tộc cao hơn và thiết dụng hơn  Trung ương bị bắt
                                                song nếu không làm được cách mạng thổ địa thì
                                                       cách mạng phản đế khó thành công"'),
('session-07',8,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
       Bối cảnh lịch sử và
    chủ trương chiến lược mới
                                              Hội nghị Ban Chấp hành Trung ương (5/1941)           của Đảng
                                                                     tại Pác Pó (Cao Bằng) - Lần VIII

                                                Bầu đồng chí
                                                     Trường Chinh
                                                 làm Tổng bí thư                                                               Giải phóng              Vấn đề điền
                                                       dân tộc                         địa

                                                                      Tạm gác       28/1/1941
Nguyễn Ái Quốc về nước                                                           "Vấn đề chính là nhận định cuộc cách mạng trước mắt
                                                                của Việt Nam là một cuộc cách mạng giải phóng dân tộc;
                                                           Lập Mặt trận Việt Minh, khẩu hiệu chính là: Đoàn
                                                                            kết toàn dân, chống Nhật, chống Pháp, tranh lại độc lập;
                                                                       hoãn cách mạng ruộng đất"'),
('session-07',9,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
       Bối cảnh lịch sử và
    chủ trương chiến lược mới
                                              Hội nghị Ban Chấp hành Trung ương (5/1941)           của Đảng
                                                                     tại Pác Pó (Cao Bằng) - Lần VIII

                                        Thứ nhất, nhấn mạnh mâu thuẫn chủ yếu, cấp bách

                                   Thứ hai, khẳng định dứt khoát chủ trương phải thay đổi chiến lược

                                    Thứ ba, giải quyết vấn đề dân tộc trong khuôn khổ từng nước Đông Dương
                                          Thứ tư, tập hợp rộng rãi mọi lực lượng dân tộc       28/1/1941
Nguyễn Ái Quốc về nước                                       Thứ năm, chủ trương tổ chức sau cách mạng thành công

                                 Thứ sáu, xác định chuẩn bị khởi nghĩa vũ trang là nhiệm vụ trung tâm'),
('session-07',10,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
        Bối cảnh lịch sử và
     chủ trương chiến lược mới
                                               Hội nghị Ban Chấp hành Trung ương (5/1941)            của Đảng
                                                                      tại Pác Pó (Cao Bằng) - Lần VIII

                                        Thứ nhất, nhấn mạnh mâu thuẫn chủ yếu, cấp bách

                                                                             Phát xít
                                                                          Nhật
                                Dân tộc
                                             Việt Nam
       28/1/1941                                                     Đế quốc
Nguyễn Ái Quốc về nước                                                     Pháp

                                        "Quyền lợi của tất cả các giai cấp bị cướp giật, vận mạng
                                              dân tộc nguy vong không lúc nào bằng"'),
('session-07',11,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
        Bối cảnh lịch sử và
     chủ trương chiến lược mới
                                               Hội nghị Ban Chấp hành Trung ương (5/1941)            của Đảng
                                                                      tại Pác Pó (Cao Bằng) - Lần VIII

                                           Thứ hai, khẳng định dứt khoát chủ trương phải thay đổi chiến lược
                                             Phản đế

                                                                                                               Cách mạng giải
                                                   Cách mạng                                                                                                                                 quyết một vấn đề
                                                               tư sản                                          cần kíp "dân tộc
                                                    dân quyền                                                    giải phóng"
       28/1/1941
Nguyễn Ái Quốc về nước                                                  Điền địa
                                            "Trong lúc này quyền lợi của bộ phận, của giai cấp phải đặt dưới sự sinh tử, tồn vong của quốc
                                                        gia, của dân tộc. Trong lúc này nếu không giải quyết được vấn đề dân tộc giải phóng, không đòi
                                          được độc lập, tự do cho toàn thể dân tộc, thì chẳng những toàn thể quốc gia dân tộc còn chịu mãi
                                                  kiếp ngựa trâu, mà quyền lợi của bộ phận, của giai cấp đến vạn năm cũng không đòi lại được"'),
('session-07',12,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
        Bối cảnh lịch sử và
     chủ trương chiến lược mới                            Hội nghị Ban Chấp hành Trung ương (5/1941)
            của Đảng                                                   tại Pác Pó (Cao Bằng) - Lần VIII

                                           Thứ ba, giải quyết vấn đề dân tộc trong khuôn khổ từng nước Đông Dương
                                                         Tổ chức thành
                                                                                     liên bang                                                                                                                       Ai Lao
                                                              cộng hòa dân chủ                                                                                                          Độc lập
                                                                                                                   đồng minh
                                                                                                           Đông
                                                                                                                                         Việt Nam                                                                                                            Dương
                                                                                                          Độc lập                                                                                                              Độc lập
                                                                                                                   đồng minh                                                                                                                         đồng       28/1/1941
                                                                                                                 minh
Nguyễn Ái Quốc về nước                                                                                                         Cao Miên
                                               Đứng riêng thành                                                                                                          Độc lập
                                                                  lập một quốc gia                                 đồng minh
                                                                                  Thi hành chính sách
                                                                              "dân tộc tự quyết"'),
('session-07',13,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
        Bối cảnh lịch sử và
     chủ trương chiến lược mới                            Hội nghị Ban Chấp hành Trung ương (5/1941)
            của Đảng                                                   tại Pác Pó (Cao Bằng) - Lần VIII

                                          Thứ tư, tập hợp rộng rãi mọi lực lượng dân tộc

                                                   Mặt trận
                                                                        Việt Minh
                                                                                                            Phụ nữ
                                                                      Công nhân                                                           cứu
                                                                              cứu quốc
                                                                                                                                quốc
       28/1/1941                                                                                                                                       Thanh                                                                              Nông nhân                                                                        Phụ lão                                    niên cứu                                                                                         cứu quốcNguyễn Ái Quốc về nước                                                                                        Thiếu niên                                                                                    cứu                                     quốc                                                                                                                       cứu quốc
                                                                                      quốc

                                   "Không phân biệt thợ thuyền, dân cày, phú nông, địa chủ, tư bản bản xứ, ai có lòng yêu nước thương nòi sẽ
                                      cùng nhau thống nhất mặt trận, thu góp toàn lực đem tất cả ra giành quyền độc lập, tự do cho dân tộc"'),
('session-07',14,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
        Bối cảnh lịch sử và
     chủ trương chiến lược mới                            Hội nghị Ban Chấp hành Trung ương (5/1941)
            của Đảng                                                   tại Pác Pó (Cao Bằng) - Lần VIII

                                       Thứ năm, chủ trương tổ chức sau cách mạng thành công

                                                                              "Toàn thể nhân dân liên hợp và
                                                                                           lập chính phủ dân chủ cộng hòa"

       28/1/1941
Nguyễn Ái Quốc về nước
                                                     Thành lập một nhà nước chung của
                                                          toàn thể dân tộc, theo tinh thần tân dân chủ
                                                  Thành lập nước Việt Nam Dân chủ Cộng hòa'),
('session-07',15,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
        Bối cảnh lịch sử và
     chủ trương chiến lược mới                            Hội nghị Ban Chấp hành Trung ương (5/1941)
            của Đảng                                                   tại Pác Pó (Cao Bằng) - Lần VIII

                                        Thứ sáu, xác định chuẩn bị khởi nghĩa vũ trang là nhiệm vụ trung tâm

                                        Khởi nghĩa
                                      từng phần tiến tới
                                   Tổng khởi nghĩa
       28/1/1941
Nguyễn Ái Quốc về nước
                                                  “với lực lượng sẵn có, ta có thể lãnh đạo một cuộc khởi nghĩa
                                           từng phần trong từng địa phương cũng có thể giành sự thắng
                                                                   lợi mở đường cho một cuộc tổng khởi nghĩa to lớn”'),
('session-07',16,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
        Bối cảnh lịch sử và
     chủ trương chiến lược mới                            Hội nghị Ban Chấp hành Trung ương (5/1941)
            của Đảng                                                   tại Pác Pó (Cao Bằng) - Lần VIII

                                Khắc phục triệt để những hạn chế của
                               Luận cương chính trị tháng 10/1930

       28/1/1941
Nguyễn Ái Quốc về nước'),
('session-07',17,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-08',1,'ĐẢNG CỘNG SẢN VIỆT NAM RA ĐỜI
VÀ LÃNH ĐẠO ĐẤU TRANH GIÀNH CHÍNH QUYỀN
                  (1930 - 1945)

            Chương 1'),
('session-08',2,'Phong trào cách mạng 1930 - 1931 và
           Bối cảnh lịch sử                                                                  khôi phục phong trào 1932 - 1935
Nguyễn Ái Quốc chuẩn bị các điều kiện để
                                                        Phong trào dân chủ 1936 - 1939          thành lập Đảng

                                                                          Lãnh đạo quá trình đấu tranh         Đảng Cộng sản Việt Nam ra đời &
           Cương lĩnh chính trị đầu tiên                                                        giành chính quyền                 Chương 1                 của Đảng (2/1930)                                                                  (1930 - 1945)

 Thành lập Đảng Cộng sản Việt Nam và                     Phong trào giải phóng dân tộc
 Cương lĩnh chính trị đầu tiên của Đảng                                1939 - 1945
   Ý nghĩa lịch sử của việc thành lập                           Tính chất, ý nghĩa và bài học kinh nghiệm
      Đảng Cộng sản Việt Nam                                 của Cách mạng Tháng Tám 1945'),
('session-08',3,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
Phong trào chống Pháp - Nhật,
 đẩy mạnh chuẩn bị lực lượng
 cho cuộc khởi nghĩa vũ trang                                    "Những tiếng súng báo hiệu cho cuộc khởi nghĩa toàn quốc,
                                         là bước đầu đấu tranh bằng võ lực của các dân tộc ở một nước Đông Dương"

            Khởi nghĩa Bắc Sơn                  Khởi nghĩa Nam Kỳ                     Binh biến Đô Lương
                9/1940                             11/1940                                   1/1941'),
('session-08',4,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
 Phong trào chống Pháp - Nhật,
  đẩy mạnh chuẩn bị lực lượng
  cho cuộc khởi nghĩa vũ trang

                        Hà Huy Tập    Nguyễn Văn Cừ    Võ Văn Tần                        26/8/1941
               Thực dân Pháp xử bắn
                    tại Hóc Môn - Gia Định

Lê Hồng Phong                                                                             Nguyễn Ái Quốc
                                                                                                    8/1942 - 9/1943 hy sinh trong
nhà tù Côn Đảo
                              Nguyễn Thị Minh Khai   Phan Đăng Lưu'),
('session-08',5,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
Phong trào chống Pháp - Nhật,
 đẩy mạnh chuẩn bị lực lượng
                                                                          25/10/1941 cho cuộc khởi nghĩa vũ trang
                                                                                      Việt Minh công bố Tuyên Ngôn
                                                                                      "Việt Nam Độc lập đồng minh ra đời"
        Việt Nam độc lập đồng minh
 Có bản chương trình đánh Nhật, đánh Tây.    Hội hè, tín ngưỡng, báo chương,
      Quyết làm cho nước non này,        Họp hành, đi lại, có quyền tự do.
   Cờ treo độc lập, nền xây bình quyền.         Nông dân có ruộng, có bò,
     Làm cho con cháu Rồng, Tiên,        Đủ ăn, đủ mặc, khỏi lo cơ hàn.
     Dân ta giữ lấy lợi quyền của ta.         Công nhân làm lụng gian nan,
      Có mười chính sách bày ra,          Tiền lương phải đủ, mỗi ban tám giờ.
     Một là ích nước, hai là lợi dân.           Gặp khi tai nạn bất ngờ,
    Bao nhiêu thuế ruộng, thuế thân,     Thuốc thang Chính phủ bấy giờ giúp cho.
   Đều đem bỏ hết cho dân khỏi phiền.'),
('session-08',6,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
Phong trào chống Pháp - Nhật,
 đẩy mạnh chuẩn bị lực lượng
 cho cuộc khởi nghĩa vũ trang
                         Đẩy mạnh hoạt động báo chí, tuyên truyền'),
('session-08',7,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
Phong trào chống Pháp - Nhật,
 đẩy mạnh chuẩn bị lực lượng
 cho cuộc khởi nghĩa vũ trang                                                 1944                               1943

                                                                  "Hội Văn hóa cứu quốc Việt Nam"
                       "Dân tộc, khoa học, đại chúng"'),
('session-08',8,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
Phong trào chống Pháp - Nhật,
 đẩy mạnh chuẩn bị lực lượng
 cho cuộc khởi nghĩa vũ trang

                                Đội du kích Bắc Sơn
                                    --> Cứu quốc quân

                            Đẩy mạnh công tác
                                         binh vận

                           Mở rộng các đội tự vệ cứu quốc
                                          --> đội du kích --> phát động
                                          tổng khởi nghĩa khi có thời cơ

                                                                                 22/12/1944
                                                                      Việt Nam Tuyên truyền giải phóng quân'),
('session-08',9,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
Phong trào chống Pháp - Nhật,
 đẩy mạnh chuẩn bị lực lượng                        "Phe xâm lược gần đến ngày bị tiêu diệt. Các Đồng minh sắp tranh được
 cho cuộc khởi nghĩa vũ trang                                              sự thắng lợi cuối cùng. Cơ hội cho dân tộc ta giải phóng chỉ ở trong một
                                     năm hoặc năm rưỡi nữa. Thời gian rất gấp. Ta phải làm nhanh!"

                                                                           10/1944
Khu căn cứ địa được thành lập vào cuối năm 1943                         Chủ trương triệu tập
Tổng bộ Việt Minh ra chỉ thị "Sửa soạn khởi nghĩa"                          Đại hội đại biểu quốc dân'),
('session-08',10,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-09',1,'ĐẢNG CỘNG SẢN VIỆT NAM RA ĐỜI
VÀ LÃNH ĐẠO ĐẤU TRANH GIÀNH CHÍNH QUYỀN
                  (1930 - 1945)

            Chương 1'),
('session-09',2,'Phong trào cách mạng 1930 - 1931 và
           Bối cảnh lịch sử                                                                  khôi phục phong trào 1932 - 1935
Nguyễn Ái Quốc chuẩn bị các điều kiện để
                                                        Phong trào dân chủ 1936 - 1939          thành lập Đảng

                                                                          Lãnh đạo quá trình đấu tranh         Đảng Cộng sản Việt Nam ra đời &
           Cương lĩnh chính trị đầu tiên                                                        giành chính quyền                 Chương 1                 của Đảng (2/1930)                                                                  (1930 - 1945)

 Thành lập Đảng Cộng sản Việt Nam và                     Phong trào giải phóng dân tộc
 Cương lĩnh chính trị đầu tiên của Đảng                                1939 - 1945
   Ý nghĩa lịch sử của việc thành lập                           Tính chất, ý nghĩa và bài học kinh nghiệm
      Đảng Cộng sản Việt Nam                                 của Cách mạng Tháng Tám 1945'),
('session-09',3,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
 Cao trào kháng Nhật
      cứu nước               Đầu năm 1945, Thế chiến thứ II bước vào giai đoạn kết thúc
                                                    Liên Xô giải phóng
                                                      các nước châu Âu và                  Thực dân Pháp ở Đông Dương ráo riết chuẩn bị,
                   Chính phủ                    tiến về Đông Đức                  chờ Đồng minh vào đánh Nhật sẽ khôi phục thống trị
                  de Gaulle về Pari

      2/1945
 Mỹ đổ quân lên giải
phóng Pháp và tiến về
     Tây Đức

                                                                              “Cả hai quân thù Nhật - Pháp đều đang sửa soạn
                                                                                                           tiến tới chỗ tao sống mày chết, quyết liệt cùng nhau”'),
('session-09',4,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
 Cao trào kháng Nhật
      cứu nước

                                               9/3/1945
                                     Nhật đảo chính Pháp,
                                         độc chiếm Đông Dương

                                                                       Chính phủ Bảo Đại - Trần Trọng KimHội nghị Ban Thường vụ Trung ương Đảng
     Đình Bảng - Từ Sơn - Bắc Ninh'),
('session-09',5,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
Cao trào kháng Nhật
     cứu nước                                                                  Nhận định
                                                                   Đây là cuộc đảo chính tranh giành lợi ích
                                                                                             của Nhật - Pháp

                                                                                       Xác định kẻ thù
                                                                                   Trước mắt và duy nhất là phát xít Nhật
                                                                 12/3/1945
                                                           Chỉ thị
                                                  "Nhật - Pháp bắn nhau và
                                                                                 Khẩu hiệu                                            hành động của chúng ta"
                                                                               Đổi "Đánh đuổi phát xít Nhật - Pháp"
                                                                                           --> "Đánh đuổi phát xít Nhật"

            Hội nghị Ban Thường vụ Trung ương Đảng                                                                              Chủ trương
                Đình Bảng - Từ Sơn - Bắc Ninh                                                                                Phát động cao trào kháng Nhật cứu nước,
                                                                                sẵn sàng tiến lên Tổng khởi nghĩa khi có thời cơ'),
('session-09',6,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
Cao trào kháng Nhật
      cứu nước
                                                                                              Khu giải phóng được
                                                                                                 4/6/1945                                                                                                                    thành lập
                                                                                                                                       (chiến khu Việt Bắc) Du kích cục bộ và
khởi nghĩa từng phần                                                   Hồ Chí Minh về
   ở Thượng du và                                                                            5/1945                                                           Tân Trào, chuẩn bị
  Trung du Bắc Kỳ                                           Đại hội quốc dân
                                                                                                            Hội sự quân sự
                                                                                                                          cách mạng Bắc Kỳ
                                                                                                     15/5/1945    Khởi nghĩa Ba Tơ                                                                                                (Bắc Giang):
     (Quãng Ngãi)                                                                                           thống nhất các LLVT,
                                                                  Tổng bộ                                                                                                                                    lập 7 chiến khu
                                                                            Việt Minh ra chỉ thị
                                                                                                           16/4/1945                                                                              tổ chức Ủy ban giải
                                                                phóng Việt Nam'),
('session-09',7,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
Cao trào kháng Nhật
     cứu nước

                               Báo chí cách mạng của Đảng và Việt Minh hoạt động công khai

                                        Nhiều lao tù thực dân, chiến sĩ cộng sản vượt ngục

                               Cao trào kháng Nhật thu hút: công nông, tiểu thương, tiểu chủ,
        “Phá kho thóc,                                        học sinh, viên chức, tư sản dân tộc và một số địa chủ nhỏ
         giải quyết nạn đói”'),
('session-09',8,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
 Tổng khởi nghĩa                                                                            8/1945, Thế chiến thứ hai kết thúc
giành chính quyền                                                                    Liên Xô đánh bại đạo quân Quan đông của Nhật
                                       Mỹ ném hai quả bom nguyên tử xuống Hirosima và Nagasaki
                                                                       Nhật đầu hàng

    9/5/1945 Đức đầu hàng
                                 Chính quyền Nhật ở Đông Dương hoang mang, thời cơ cách mạng đã xuất hiện'),
('session-09',9,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                    Phong trào giải phóng dân tộc 1939 - 1945
     Tổng khởi nghĩa
    giành chính quyền    Tình thế khó khăn xuất hiện                                Thời cơ giành chính quyền

HỘI NGHỊ PỐTXĐAM 7/1945                               HỘI NGHỊ IANTA 2/1945
                                                                                    Tồn tại trong
                                                                                        khoảng thời gian
  Quân Trung Hoa Dân quốc                                   Mỹ ủng hộ đề nghị chỉ để            từ khi Nhật đầu
      vào Bắc Việt Nam                                                                các thuộc địa dưới quyền          hàng đồng minh
                                                                             ủy trị của "mẫu quốc"                                                                                              đến trước khi
 Vĩ tuyến 16
                                                                                      quân Đồng minh                                                                     Truman cam kết không
                                                                                can thiệp Pháp khôi phục          vào Đông Dương,
     Quân Liên hiệp Anh                                                                        cai trị Đông Dương            khoảng nửa cuối
      vào Nam Việt Nam                                                 Cho rằng: "hoạt động                                                                                                 tháng 8
                                                                                       phiến loạn do cộng sản
                                                                         cầm đầu"'),
('session-09',10,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                  Phong trào giải phóng dân tộc 1939 - 1945
 Tổng khởi nghĩa
giành chính quyền

            23 giờ 13/8/1945                                       Hội nghị toàn quốc của Đảng
       Quân lệnh số 1 - phát lệnh
                                                  14 - 15/8/1945         Tổng khởi nghĩa cả nước
                                            Tân Trào

                                      Dự đoán                                                        "Phản đối xâm lược!
                                                           tình hình                                                 Hoàn toàn độc lập!                                                                                                                                    Chính quyền nhân dân!"
                13/8/1945
           Thành lập Ủy ban
            khởi nghĩa toàn quốc
                                                         Nguyên tắc chỉ đạo                                         Nội dung                   Chiếm ngay những                                                       Tập trung, thống nhất,                                                                                                                                              nơi chắc thắng                                                                             kịp thời                                                hội nghị

         12/8/1945, Ủy ban lâm thời
                                               Quân sự và                                                                                                                               Thành lập ủy ban nhân       Khu giải phóng hạ lệnh khởi                                                               chính trị                                                        dân ở những nơi giành
             nghĩa trong khu                                      kết hợp                                                                được chính quyền'),
('session-09',11,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
                   Phong trào giải phóng dân tộc 1939 - 1945
  Tổng khởi nghĩa
  giành chính quyền
                       Đại hội Quốc dân
                             16/8/1945
                                                               Thông qua 10 chính sách của Việt Minh                       Tân Trào

                                                             Lập Ủy ban kháng chiến do Hồ Chí Minh làm chủ tịch
 60 đại biểu của các
 đảng phái, đoàn thể
                                                                                    “Việt Nam
cứu quốc, các dân tộc,                                                         Dân chủ Cộng hòa”
tôn giáo và đồng bào
 quốc dân chiến khu'),
('session-09',12,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
         Phong trào giải phóng dân tộc 1939 - 1945
                                                                   Tổng khởi nghĩa
                                                                          giành chính quyền

                        Ngày 2/9/1945, chủ tịch Hồ Chí Minh đọc Tuyên ngôn độc lập
                                                    tại Lễ Độc lập, Ba Đình (Hà Nội)'),
('session-09',13,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-10',1,'ĐẢNG CỘNG SẢN VIỆT NAM RA ĐỜI
VÀ LÃNH ĐẠO ĐẤU TRANH GIÀNH CHÍNH QUYỀN
                  (1930 - 1945)

            Chương 1'),
('session-10',2,'Phong trào cách mạng 1930 - 1931 và
           Bối cảnh lịch sử                                                                  khôi phục phong trào 1932 - 1935
Nguyễn Ái Quốc chuẩn bị các điều kiện để
                                                        Phong trào dân chủ 1936 - 1939          thành lập Đảng

                                                                          Lãnh đạo quá trình đấu tranh         Đảng Cộng sản Việt Nam ra đời &
           Cương lĩnh chính trị đầu tiên                                                        giành chính quyền                 Chương 1                 của Đảng (2/1930)                                                                  (1930 - 1945)

 Thành lập Đảng Cộng sản Việt Nam và                          Phong trào giải phóng dân tộc
 Cương lĩnh chính trị đầu tiên của Đảng                                  1939 - 1945
   Ý nghĩa lịch sử của việc thành lập                   Tính chất, ý nghĩa và bài học kinh nghiệm
      Đảng Cộng sản Việt Nam                         của Cách mạng Tháng Tám 1945'),
('session-10',3,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
    Tính chất, ý nghĩa và bài học kinh nghiệm của Cách mạng Tháng Tám 1945

Tính chất

     Cách mạng Tháng Tám năm 1945
   “là một cuộc cách mạng giải phóng dân tộc
       mang tính chất dân chủ mới.
 Nó là một bộ phận khăng khít của cách mạng
    dân tộc dân chủ nhân dân Việt Nam”'),
('session-10',4,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
    Tính chất, ý nghĩa và bài học kinh nghiệm của Cách mạng Tháng Tám 1945

Tính chất

   “Cách mạng Tháng Tám Việt Nam là một
  cuộc cách mạng giải phóng dân tộc. Mục đích
   của nó là làm cho dân tộc Việt Nam thoát
    khỏi ách đế quốc, làm cho nước Việt Nam
       thành một nước độc lập, tự do”'),
('session-10',5,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
    Tính chất, ý nghĩa và bài học kinh nghiệm của Cách mạng Tháng Tám 1945

Tính chất

     Cách mạng giải phóng
       dân tộc điển hình

        Cách mạng có
      tính chất dân chủ mới'),
('session-10',6,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
     Tính chất, ý nghĩa và bài học kinh nghiệm của Cách mạng Tháng Tám 1945

 Tính chất

Cách mạng giải phóng                                         Tập trung hoàn thành nhiệm vụ hàng đầu
  dân tộc điển hình                                                                   là giải phóng dân tộc

                                         Lực lượng là toàn thể dân tộc, đoàn kết chặt chẽ
                                                       trong Mặt trận Việt Minh

                                            Thành lập chính quyền nhà nước
                                                      “của chung toàn dân tộc”'),
('session-10',7,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
      Tính chất, ý nghĩa và bài học kinh nghiệm của Cách mạng Tháng Tám 1945

 Tính chất                                  Chưa làm cách mạng ruộng đất,
                                           chưa xóa bỏ chế độ phong kiếm chiếm hữu ruộng đất

 “Có tính chất dân chủ,
nhưng tính chất đó chưa
                                                 Các tầng lớp nhân dânđược đầy đủ và sâu sắc”
                                                  được hưởng quyền tự do, dân chủ

   Cách mạng có                      Đã giải quyết một số quyền lợi cho nông dân,
tính chất dân chủ mới                                   lực lượng đông đảo nhất trong dân tộc'),
('session-10',8,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
   Tính chất, ý nghĩa và bài học kinh nghiệm của Cách mạng Tháng Tám 1945

Ý nghĩa

                                                                               Khẳng định sự sáng                         Đưa Việt Nam trở         Đảng trở thành     Đập tan xiềng xích                                                                                                  tạo của cách mạng                               thành một nước có         Đảng cầm quyền,       nô lệ thực dân,                                                                                               thuộc địa, đột phá                                chủ quyền, vươn         mở ra kỷ nguyên      chấm dứt chế độ                                                                                           góp phần tan rã                                       lên cùng thế giới           mới cho dân tộc         phong kiến                                                                                          chủ nghĩa đế quốc'),
('session-10',9,'II. Lãnh đạo quá trình đấu tranh giành chính quyền (1930 - 1945)
     Tính chất, ý nghĩa và bài học kinh nghiệm của Cách mạng Tháng Tám 1945

  Bài học
kinh nghiệm

                                                    Phương pháp                                                                      Xây dựng Đảng     Chỉ đạo chiến lược     Xây dựng lực lượng                                                              cách mạng

     Phải giương cao ngọn cờ giải   Liên minh công - nông - trí    Kết hợp đấu tranh chính trị   Đảng phải tuyệt đối trung thành
                                                                                                                       với lợi ích giai cấp và       phóng dân tộc, giải quyết                                      với quân sự, nắm vững quan                                   phải khơi dậy tinh thần
                                                                                           dân tộc, liên hệ chặt chẽ với                                                            điểm bạo lực của quần chúng,       đúng đắn hai nhiệm vụ       dân tộc trong mọi lực                                                                                         quần chúng và với đội ngũ cán bộ.                                                                             tiến hành chiến tranh du kích          độc lập dân tộc và                                    lượng, đoàn kết rộng rãi                                                                                            Đội ngũ đảng viên được tôi luyện                                                                     cục bộ, từng phần tiến tới         cách mạng ruộng đất                                                                                                          trong đấu tranh cách mạng
                                                             Tổng khởi nghĩa'),
('session-10',10,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-11',1,'ĐẢNG LÃNH ĐẠO HAI CUỘC KHÁNG CHIẾN CHỐNG NGOẠI XÂM,
HOÀN THÀNH GIẢI PHÓNG DÂN TỘC, THỐNG NHẤT ĐẤT NƯỚC
                          (1945 - 1975)

            Chương 2'),
('session-11',2,'Xây dựng và bảo vệ chính quyền cách mạng                         Sự lãnh đạo của Đảng đối với
              1945 - 1946                                                             cách mạng hai miền Nam - Bắc (1954 - 1965)
    Đường lối kháng chiến toàn quốc                            Lãnh đạo cách mạng cả nước
và quá trình tổ chức thực hiện (1946 - 1950)                                  (1965 - 1975)

           Lãnh đạo xây dựng, bảo vệ                                                            Lãnh đạo xây dựng chủ nghĩa xã hội ở
         chính quyền cách mạng, kháng chiến                                                          miền Bắc và kháng chiến chống đế quốc
           chống thực dân Pháp xâm lược                                                Mỹ xâm lược, giải phóng miền Nam,               Chương 2                                                                                                             thống nhất đất nước (1954 - 1975)                     (1945 - 1954)

 Đẩy mạnh cuộc kháng chiến đến thắng lợi                   Ý nghĩa lịch sử và kinh nghiệm lãnh đạo
               (1951 - 1954)                                         của Đảng thời kỳ 1954 - 1975
  Ý nghĩa lịch sử và bài học kinh nghiệm của Đảng trong
lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ'),
('session-11',3,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
Tình hình Việt Nam sau
 Cách mạng Tháng Tám
        1945
   Thuận lợi
                              Indonesia - 17/8/1945                                        Liên Xô trở thành
                                                                             thành trì của
                                                                             chủ nghĩa xã hội

     Lào - 12/10/1945        Philippine - 4/7/1946

 Phong trào giải phóng dân tộc ở các nước thuộc địa dâng cao'),
('session-11',4,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
Tình hình Việt Nam sau
 Cách mạng Tháng Tám                                        Hồ Chí Minh        1945
                                                           trở thành biểu tượng
    Thuận lợi                                                  của nền độc lập, tự do
                        Việt Nam trở thành                                   Đảng Cộng sản
                    quốc gia độc lập, tự do                                                 trở thành đảng
                                                                     cầm quyền

                                                                             Chính quyền
                 Nhân dân từ nô lệ trở                                                                                   cách mạng được hình
                  thành người chủ đất nước                                                                             thành thống nhất từ
                                                                          Trung ương đến cơ sở'),
('session-11',5,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
 Tình hình Việt Nam sau
 Cách mạng Tháng Tám                                                                              Hệ thống chính quyền mới, non
        1945                                                                                                                                       trẻ, thiếu thốn, yếu kém nhiều mặt                                                               20 vạn
                                                                   Trung Hoa dân quốc    Khó khăn                                                                                                                   Kinh tế xơ xác, tiêu điều,                                                                                 Việt Quốc, Việt Cách
                                                                                                                            công nghiệp đình đốn

                                                                                                               Nông nghiệp: 50% ruộng đất bị bỏ hoang

                                                                                                                                   Tài chính kiệt quệ, kho bạc trống rỗng,
                                                          Vĩ tuyến 16                                                                                                                       lạm phát tăng cao

                               Hơn 6 vạn
                                                                     Hủ tục lạc hậu, thói hư tật xấu
                                                                                                    chưa khắc phục
                                                     23/9/1945                                      95% dân số mù chữ,
Các nước đế quốc âm mưu chia                                                                                             2 triệu người chết đói
 lại hệ thống thuộc địa thế giới.
                                 Thực dân Pháp                      2 vạn Tấn công, đàn áp phong trào
                                      2/9/1945                                                “Ngàn cân treo sợi tóc”      cách mạng thế giới                                         Liên quân Anh - Ấn'),
('session-11',6,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946

 Xây dựng chế độ mới &                                   Chính phủ lâm thời họp phiên đầu tiên
 chính quyền cách mạng                                                   3/9/1945

                              Nhiệm vụ lớn trước mắt

                                                                               Diệt giặc                                  Diệt giặc đói    Diệt giặc dốt
                                                                             ngoại xâm'),
('session-11',7,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946

 Xây dựng chế độ mới &                                 25/11/1945 Ban Chấp hành Trung ương Đảng           Xúc tiến bầu cử
 chính quyền cách mạng                                    Chỉ thị "Kháng chiến kiến quốc"                   Quốc hội để lập                                                                                                                   Chính phủ chính
                                                                                                                                                  thức, ban hành
                                                                                                                       Hiến pháp                                                                                                                          Động viên lực   Kẻ thù chính: thực dân Pháp
                                                                                                                                                      lượng toàn dân,
                                                                                                                                                                     kiên trì kháng
                                                                                                                                                                    chiến và chuẩn
                                                                                                                                                                                               bị kháng chiến
      "Dân tộc giải phóng"                                         Biện                            lâu dài
   Khẩu hiệu: "Dân tộc trên hết,                                   pháp        Tổ quốc trên hết"
                                                        cụ thể                   Kiên định     Củng cố chính quyền,
                                                                                                                   nguyên tắc      chống Pháp xâm lược                                                                                                                            độc lập về
        Bài trừ nội phản,                                                                                                                               chính trị
  cải thiện đời sống cho nhân dân                                                                  Ngoại giao
                                                                                          khôn khéo,                                                                            Diệt giặc                                                                                                                                            "Hoa - Việt thân thiện"                               Diệt giặc đói    Diệt giặc dốt                                                                                               "thêm bạn,                                                                          ngoại xâm
                                                                                                             bớt thù"                  "độc lập về chính trị -
                                                                                                                                           nhân nhượng về kinh tế"'),
('session-11',8,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946

             Chống giặc đói, đẩy lùi nạn đói                                    Xây dựng chế độ mới &                                                                                                       chính quyền cách mạng

     Tăng gia sản xuất,
                                                               Lập hũ gạo tiết kiệm      thực hành tiết kiệm
       Chia ruộng đất
                                                                Đầu năm 1946,
                                                                nạn đói cơ bản được đẩy lùi,
                      Bãi bỏ thuế thân,                  Giảm tô
                                                                              đời sống nhân dân được ổn định                        các thứ thuế vô lý                   25%

               "Tuần lễ vàng"                      Quỹ "Đảm phụ quốc phòng"

              Quỹ "Độc lập"                      Quỹ "Nam Bộ kháng chiến"'),
('session-11',9,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946

                                                                                     Xây dựng chế độ mới &                         Chống giặc dốt, xóa nạn mù chữ                                                                                                       chính quyền cách mạng
                                          Cuối 1946
                                    2.5 triệu người biết đọc, viết chữ quốc ngữ
           "Bình dân học vụ"

                                                                                               Lễ khai giảng trường Đại học Quốc gia Việt Nam     "Toàn dân học chữ quốc ngữ"      Thành lập trường Đại học Văn khoa Hà Nội
                                                                                                        ngày 13/11/1945
 "Xây dựng nếp sống mới, đẩy lùi tệ nạn"'),
('session-11',10,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946

                                                                                     Xây dựng chế độ mới &                 Khẩn trương xây dựng, củng cố chính quyền cách mạng                                                                                                       chính quyền cách mạng
 6/1/1946 nhân dân cả nước bầu cử

                                                                        Ban Thường trực Quốc hội
                                                                                      (Nguyễn Văn Tố)

                                                                                  Chính phủ gồm 10 bộ
                                                               Hồ Chí Minh làm chủ tịch

                                            2/3/1946                                                            9/11/1946                    333                                                                                            Kỳ họp thứ 2 Quốc hội khóa I                                   Quốc hội khóa I
                                                                                              Nhà hát lớn - Hà Nội                       đại biểu                               Nhà hát lớn - Hà Nội                                                                                                                    thông qua Hiến Pháp'),
('session-11',11,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
                 Khẩn trương xây dựng, củng cố chính quyền cách mạng                                                                                     Xây dựng chế độ mới &
                                                                                                       chính quyền cách mạng                                                                                                              Cuối 1946      Huỳnh Thúc Kháng         Tôn Đức Thắng
                                                                                        Có 8 vạn quân chính quy,             - Hội trưởng                   - Hội phó
                                                                                                                                lực lượng công an tổ chức
                                                                                                          đến cấp huyện, hàng vạn
                                                                                                      dân quân, tự vệ
                                 Mặt trận
                                            Liên Việt

                                                                    Tích cực mua sắm                     Tích trữ lương thực,
                                                               vũ khí                              thuốc men
   Mặt trận dân tộc thống nhất được mở rộng
       và tăng cường thực lực cách mạng,
         tập trung chống Pháp ở Nam Bộ                     LLVT được củng cố                   Củng cố cơ sở,
                                                              và tổ chức lại                      căn cứ địa cách mạng
                                     Hội đồng
          Vĩnh Thụy                                  Cố vấn
          đứng đầu                                      Chính phủ                         Chuẩn bị
                                                                           kháng chiến lâu dài'),
('session-11',12,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
                                                                                                            Tổ chức kháng chiến chống
                                                                                                                                thực dân Pháp ở Nam Bộ,
                                                                                                                   đấu tranh bảo vệ
                                                                                                                                   chính quyền non trẻ

                                                                          25/10/1945     Hội nghị cán bộ Đảng bộ Nam Bộ
                                                                                                           Thiên Hộ - Cái Bè - Tiền Giang
                                Chợ Bến Thành, 23/9/1945

                                                “Thà chết tự do còn hơn sống nô lệ”

                               Đường phố Sài Gòn thực hiện
Đêm 22 rạng sáng 23/9/1945          “tiêu thổ kháng chiến”
 quân đội Pháp nổ súng đánh                                                                   Sáng 23/9/1945
  chiếm Sài Gòn - Gia Định

                                                                 Hội nghị Liên tịch
                                           Ủy ban nhân dân - Ủy ban kháng chiến - đại diện Việt Minh
                              Nhân dân Nam Bộ kháng chiến'),
('session-11',13,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
                                                                                                            Tổ chức kháng chiến chống
                                                                                                                                thực dân Pháp ở Nam Bộ,
                                                                                                                   đấu tranh bảo vệ
                                                                                                                                   chính quyền non trẻ

                                                                                                                      26/9/1945
                                                                                                            Chi đội Nam tiến đầu tiên

                  "Thành đồng Tổ quốc"'),
('session-11',14,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
                                                                                                            Tổ chức kháng chiến chống
                                                                                                                                thực dân Pháp ở Nam Bộ,
                                                                                                                   đấu tranh bảo vệ
                                                                                                                                   chính quyền non trẻ                                 Nhân nhượng với Tưởng

                                                                                                           28/2/1946
                                                                                                              6/3/1946                                                                                                   Hiệp ước Trùng Khánh
                                                                                                         Hiệp định sơ bộ                                  Đồng ý cung cấp lương thực                       (Hoa - Pháp)
                                           cho 20 vạn quân Tưởng
           11/11/1945
     Tuyên bố Tự giải tán                       Đồng ý lưu hành tiền
                                         quan kim, quốc tệ                                                                                                                   1.Chính phủ Pháp công nhân Việt Nam là một
                                                                                                            quốc gia tự do, có chính phủ, nghị viện, tài chính
                                 Đồng ý mở thêm 70 ghế trong                              và quân đội riêng, nằm trong khối Liên hiệp Pháp
                                  Quốc hội không qua bầu cử cho                                             2. Đồng ý cho Pháp ra Bắc thay thế Tưởng
                                                                                                                                             giải giáp quân Nhật, rút dần trong 5 năm                                                 Việt cách, Việt quốc
                                                                                                                                                          3. Hai bên sẽ tiếp tục đàm phán'),
('session-11',15,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
                                                                                                            Tổ chức kháng chiến chống
                                                                                                                                thực dân Pháp ở Nam Bộ,
                                                                                                                   đấu tranh bảo vệ
                                                                                                                                   chính quyền non trẻ

                                                                       9/3/1946
                                                                Chỉ thị "Hòa để tiến"

                                                                   Đẩy mạnh                           Nêu cao           Không được làm                                                                                công tác xây dựng          Củng cố                                tinh thần cảnh          nhụt tinh thần                                                                            Đảng, đào tạo            phong trào
                                    giác, sẵn sàng           quyết chiến của                                                                               cán bộ chính trị &          quần chúng
                                  chiến đấu              dân tộc                                                                             quân sự'),
('session-11',16,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                  Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
                                                                                                             Tổ chức kháng chiến chống
                                                                                                                                  thực dân Pháp ở Nam Bộ,
                                                                                                                     đấu tranh bảo vệ
  Tạm ước 14/9/1946                                                                                                                                    chính quyền non trẻ
        Marseill
                                                                                                       Quyền chủ tịch nước
                                                                                                 Huỳnh Thúc Kháng

                                                                             Quân Tưởng trì hoãn rút quân
                                                                  6/7 - 10/9/1946
                                                                          Quân Pháp gây hấn, mốc nối Việt Quốc,31/5/1946 - 20/10/1946                                 Phạm Văn Đồng
                                                                                                             Việt Cách âm mưu đảo chínhHồ Chí Minh thăm Pháp                               đàm phán với Pháp ở
                                                                    Fontainebleau                         Rạng sáng 12/7/1946 ta tấn công trụ sở Đại Việt,
                                                                                      Quốc dân Đảng, thu hồ sơ, đưa ra trước Quốc hội
                                 19/4 - 10/5/1946
                               Hội nghị trù bị                                                          Kịp thời kết thúc vụ án
                                                                                              Số 7 Phố Ôn Như Hầu'),
('session-11',17,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                 Xây dựng và bảo vệ chính quyền cách mạng 1945 - 1946
                                                                                                            Tổ chức kháng chiến chống                                          Từng bước                                                                     Tiếp tục giam        Khẩn trương di                                                                                                                                thực dân Pháp ở Nam Bộ,                                            chuyển sang tình                                            Củng cố, xây dựng                                                           chân địch ở Nam         chuyển các cơ                                                                                                                   đấu tranh bảo vệ                                              trạng chiến tranh,                                                   căn cứ địa, chiến
                                                                   Bộ, thành thị         quan lãnh đạo ra                                   chính quyền non trẻ                                           chuẩn bị kháng                                                        khu, an toàn khu
                                                             miền Bắc             khỏi thành thị                                                    chiến lâu dài

                                                       "Công việc
                                                   khẩn cấp bây giờ"

                                                                  20/10/1946
                                                 Bác Hồ và đoàn đàm phán về đến Cảng Hải Phòng'),
('session-11',18,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-12',1,'ĐẢNG LÃNH ĐẠO HAI CUỘC KHÁNG CHIẾN CHỐNG NGOẠI XÂM,
HOÀN THÀNH GIẢI PHÓNG DÂN TỘC, THỐNG NHẤT ĐẤT NƯỚC
                          (1945 - 1975)

            Chương 2'),
('session-12',2,'Xây dựng và bảo vệ chính quyền cách mạng                             Sự lãnh đạo của Đảng đối với
                1945 - 1946                                                                cách mạng hai miền Nam - Bắc (1954 - 1965)
    Đường lối kháng chiến toàn quốc                             Lãnh đạo cách mạng cả nước
 và quá trình tổ chức thực hiện (1946 - 1950)                                                                        (1965 - 1975)

           Lãnh đạo xây dựng, bảo vệ                                                            Lãnh đạo xây dựng chủ nghĩa xã hội ở
         chính quyền cách mạng, kháng chiến                                                          miền Bắc và kháng chiến chống đế quốc
           chống thực dân Pháp xâm lược                                                Mỹ xâm lược, giải phóng miền Nam,               Chương 2                                                                                                             thống nhất đất nước (1954 - 1975)                     (1945 - 1954)

  Đẩy mạnh cuộc kháng chiến đến thắng lợi                    Ý nghĩa lịch sử và kinh nghiệm lãnh đạo
               (1951 - 1954)                                         của Đảng thời kỳ 1954 - 1975
  Ý nghĩa lịch sử và bài học kinh nghiệm của Đảng trong
lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ'),
('session-12',3,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
 Cuộc kháng chiến toàn
quốc bùng nổ và đường lối                      Từ cuối tháng
  kháng chiến của Đảng                                           10/1946

                                                                       Mong muốn
                                                                    đàm phán, hòa bình

                                                Kiên trì thực hiệnPháp đặt lại nền thống trị
                                         chủ trương hòa bình, cứu vãn   ở Lào, Campuchia,
                                                                                    “dùng biện pháp                                        mối quan hệ Việt - Pháp   chia rẽ Đông Dương
                                                                               quân sự để giải quyết
                                    Ngăn chặn một cuộc chiến nổ                                                                             mối quan hệ Việt - Pháp”    Âm mưu
                                             ra quá sớm và không cân sức   chia cắt Việt Nam

                                 Bù nhìn “Chính phủ
                                          cộng hòa Nam Kỳ”'),
('session-12',4,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
 Cuộc kháng chiến toàn
quốc bùng nổ và đường lối
  kháng chiến của Đảng
                              Lạng
                                                                                              18/12/1946
                                Sơn            Cuối tháng                                                                Đơn phương cắt đứt mọi liên hệ                                        Hải
                                       11/1946                         và phá bỏ các Hiệp ước đã kí                                          Phòng,
                                     Hải Dương

                                 Đà
                                     Nẵng

                                                                                  16 và 17/12/1946 tấn công
                                                                                                trụ sở Bộ Tài chính,
                                                                       Bộ Giao thông công chính

                                 Bù nhìn “Chính phủ
                                          cộng hòa Nam Kỳ”'),
('session-12',5,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
                                                                                             Cuộc kháng chiến toàn
                                                                                                     quốc bùng nổ và đường lối
                 12/12/1946                                                                            kháng chiến của Đảng
       Chỉ thị “Toàn dân kháng chiến”
                                                                    20 giờ 19/12/1946
                  18/12/1946                                                                     Lệnh kháng chiến lan tỏa các chiến trường        Hội nghị Thường vụ TW Đảng
               tại Vạn Phúc, Hà Đông
                          “Chúng ta muốn hòa bình, chúng ta phải
                         nhân nhượng. Nhưng chúng ta càng nhân
                            nhượng, thực dân Pháp càng lấn tới, vì
                           chúng quyết tâm cướp nước ta lần nữa!
                          Không! Chúng ta thà hy sinh tất cả, chứ
                            nhất định không chịu mất nước, nhất định
                          không chịu làm nô lệ.
                          Hỡi đồng bào!
           19/12/1946    Chúng ta phải đứng lên!”
 Lời kêu gọi toàn quốc kháng chiến'),
('session-12',6,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
                                                                                             Cuộc kháng chiến toàn
                                                                                                     quốc bùng nổ và đường lối                                             “Dựa trên sức mạnh toàn dân                                                                                                kháng chiến của Đảng
                                          Kháng chiến toàn dân, toàn diện, lâu dài
                                                      và dựa vào sức minh”

                                                 Đường lối
                                                                                             Kháng chiến nhất định                                                     kháng chiến
              Kháng chiến kiến quốc                                                                                                                thắng lợi                                                       chống thực dân                      25/11/1945                                                                                                  (TBT Trường Chinh)
                                                      Pháp                                                                                                                 8/1947

                            Chỉ thị Tình hình và              1945 - 1947                   Lời kêu gọi toàn quốc
                                chủ trương                                                      kháng chiến
                                  3/3/1946                                                            19/12/1946

                                                    Chỉ thị                        Chỉ thị
                                         Hòa để tiến              Toàn dân kháng chiến
                                                    9/3/1946                      12/12/1946'),
('session-12',7,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
                                                                                             Cuộc kháng chiến toàn
                                                                                                     quốc bùng nổ và đường lối
                                                                                                kháng chiến của Đảng

                                                                                        "Mỗi người dân là một chiến sĩ,
                                                                                      mỗi làng xã là một pháo đài,                                                         Kháng chiến
                                                                   toàn dân           mỗi đường phố là một mặt trận"
                                                                                                                 - Quân đội nhân dân làm nòng cốt

                                                                                             Trên mọi lĩnh vực, mọi mặt trận,          Mục tiêu                                                                  Kháng chiến                                 Đường lối                                 Quân sự & vũ trang đóng vai trò  1. Đánh đổ thực dân Pháp xâm lược,                                       toàn diện
                                                                                   mũi nhọn, quyết định      giành nền độc lập, tự do,          kháng chiến
       thống nhất hoàn toàn          chống thực dân
  2. Vì nền tự do dân chủ và góp phần                                     Pháp                                                                             Vừa tiêu hao sinh lực địch
      bảo vệ hòa bình thế giới                                       Kháng chiến                                                                                        vừa phát triển lực lượng ta,                                                                                   lâu dài
                                                                                              từng bước xoay chuyển tương quan lực lượng

                                                                                      Lấy độc lập, tự chủ về đường lối là yếu tố quan trọng
                                                           Dựa vào sức mình                                                                                       hàng đầu, lấy nội lực và phát huy sức mạnh vật chất,                                                                                              là chính                                                                                                          tinh thần của dân tộc làm chỗ dựa chủ yếu'),
('session-12',8,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
    Tổ chức chỉ đạo
                                                                                   Cuối năm 1947    cuộc kháng chiến
     (1947 - 1950)                            Mở rộng
                                              Mặt trận dân tộc
                                                            thống nhất                            Tổng số đảng viên = 70.000 người

                                                                            Củng cố
                                                                                            chính quyền                  Bộ độ chính quy = 12 vạn quân
                                                                            nhân dân ở vùng
Chia cả nước thành các khu,                                                                                                 địch tạm chiếm                                             6/4/1947 sau này là chiến khu quân
                                    Hội nghị cán bộ                                      57 trung đoàn, 20 tiểu đoàn sự, thành lập Ủy ban kháng
                                     Trung ương      chiến hành chính
                                                                                  Phát động
                                                                                            chiến tranh du kích,             Lực lượng dân quân tự vệ = 1 triệu người
                                                                              đẩy mạnh công tác
                                                                                          ngoại giao
                                                                                                        3 vạn khẩu súng, 20 công xưởng sửa chữa,
                                          Mở đợt phát triển                                                                                                                        sản xuất vũ khí thô sơ
                                                            đảng viên mới
                                                               "Lớp tháng Tám"
                                                                                                 Tổ chức Nha Công an rộng khắp, lập nhiều chiến công'),
('session-12',9,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
    Tổ chức chỉ đạo
    cuộc kháng chiến
     (1947 - 1950)
                                               Tiếp tục đẩy mạnh tăng gia sản xuất, tự túc lương thực,
                                      đảm bảo đời sống cho bộ đội và nhân dân

        Kinh tế,
                                        Duy trì bình dân học vụ, dạy và học ở các        văn hóa,
                                                          trường phổ thông các cấp         xã hội

                                          Tranh thủ sự ủng hộ của quốc tế, đặt cơ quan
                                                        đại diện ở Thái Lan, Miến Điện ...'),
('session-12',10,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
    Tổ chức chỉ đạo
    cuộc kháng chiến
     (1947 - 1950)                         Về quân sự

   Loại bỏ hàng ngàn                             Bảo toàn được
    tên địch, phá hủy                                   cơ quan đầu não
    hàng trăm xe cơ
                                và căn cứ địa       giới, bắn chìm
                                kháng chiến     nhiều tàu chiến
                  21/12/1947                                                                                               Thu Đông 1947, 15.000
            Kết thúc 75 ngày đêm                                                                                                    quân Pháp: lục quân, hải
               chiến đấu thắng lợi                                                                                                      quân và không quân
   Đánh bại âm                Trận thực chiến
    mưu đánh                                     trực diện phản                                               15/10/1947    nhanh, thắng                                công đầu tiên của
  nhanh của Pháp                          Chỉ thị mở chiến dịch                           Quân đội ta
                                                Việt Bắc Thu Đông'),
('session-12',11,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
    Tổ chức chỉ đạo
    cuộc kháng chiến
     (1947 - 1950)
                             Lễ phong tướng
                                20/1/1948

       Phong hàm
                                                                             Phong hàm Thiếu tướng        Đại tướng:
                                                                            Nguyễn Sơn, Lê Thiết Hùng,
     Võ Nguyên Giáp                                                                     Chu Văn Tấn, Hoàng Sâm,
                                                                      Hoàng Văn Thái, Lê Hiến Mai,
                                                                   Văn Tiến Dũng, Trần Đại Nghĩa,       Phong hàm
                                                                                    Trần Tử Bình       Trung tướng:
       Nguyễn Bình'),
('session-12',12,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
    Tổ chức chỉ đạo
    cuộc kháng chiến                      Từ đầu năm 1948     (1947 - 1950)
                                    Tình hình có chuyển biến

              Lời kêu gọi thi đua ái quốc 11/6/1948;                                      1/10/1949 Đảng Cộng sản Trung Quốc giành được chính quyền,
Hội nghị Văn hóa toàn quốc tháng 7/1948 ghi nhận nhiều thành tựu                         Nhà nước Cộng hòa nhân dân Trung Hoa ra đời

                                                                         Pháp gặp khó khăn: vùng tự do ngày càng mở rộng, mâu thuẫn ở   11/1949 chủ tịch Hồ Chí Minh ký sắc lệnh về nghĩa vụ quân sự
                                                                                            chính quốc, thế chiến lược ở Đông Dương bị đảo lộn    Phong trào “rèn cán, chỉnh quân” làm phát triển quân đội

            Đẩy mạnh công tác xây dựng Đảng                                  1950 Trung Quốc, Liên Xô, Đông Âu, Triều Tiên đặt quan hệ
          1948 - 1949 kết nạp 50.000 đảng viên mới                                       ngoại giao, ủng hộ kháng chiến của nhân dân Việt Nam

         Nhiều trận thắng điển hình, gắn kết tình quân dân                       Mỹ ngày càng can thiệp sâu vào chiến tranh Việt Nam,
                                                                       âm mưu thay thế Pháp    La Ngà, Nghĩa Lộ (3/1948); Tầm Vu, Đồng Dương (4/1948)'),
('session-12',13,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
    Tổ chức chỉ đạo
    cuộc kháng chiến
     (1947 - 1950)
                                                                                                      9/1/1950, 3000 học sinh sinh
                                                                                                         viên Sài Gòn biểu tình bị Pháp
                                                                                            đàn áp dã man

                                             19/3/1950 hơn 500.000 người
                                         dân Sài Gòn chống Mỹ đưa tàu
                                                      chiến vào cảng Sài Gòn'),
('session-12',14,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
    Tổ chức chỉ đạo
    cuộc kháng chiến
     (1947 - 1950)

     Giữa năm 1949, tướng Revers đề ra
      kế hoạch mở rộng vùng chiếm đóng,
  phong tỏa, khóa chặt biên giới Việt - Trung

                                                                                       6/1950 Ban Thường Vụ Trung ương Đảng
                                                                                                         quyết định mở chiến dịch     13/6/1949 Bảo Đại được Pháp đưa
                                                                                                      Biên giới Thu đông 1950        về Sài Gòn làm quốc trưởng,
      thành lập "Quốc gia Việt Nam"                                                                                Chủ động tấn công địch dọc
                                                                                                        biên giới Việt Trung, Cao Bằng, Lạng sơn'),
('session-12',15,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
        Đường lối kháng chiến toàn quốc và quá trình tổ chức thực hiện (1946 - 1950)
    Tổ chức chỉ đạo
    cuộc kháng chiến
     (1947 - 1950)

    Xoay chuyển tình thế, giành thế
      chủ động trên chiến trường

                                                                                       6/1950 Ban Thường Vụ Trung ương Đảng
                                                                                                         quyết định mở chiến dịch    Chiến dịch quân sự lớn, đầu tiên
                                                                                                      Biên giới Thu đông 1950     mà ta chủ động tiến công

                                                                                Chủ động tấn công địch dọc
                                                                                                        biên giới Việt Trung, Cao Bằng, Lạng sơn'),
('session-12',16,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-13',1,'ĐẢNG LÃNH ĐẠO HAI CUỘC KHÁNG CHIẾN CHỐNG NGOẠI XÂM,
HOÀN THÀNH GIẢI PHÓNG DÂN TỘC, THỐNG NHẤT ĐẤT NƯỚC
                          (1945 - 1975)

            Chương 2'),
('session-13',2,'Xây dựng và bảo vệ chính quyền cách mạng                           Sự lãnh đạo của Đảng đối với
               1945 - 1946                                                             cách mạng hai miền Nam - Bắc (1954 - 1965)
      Đường lối kháng chiến toàn quốc                              Lãnh đạo cách mạng cả nước
  và quá trình tổ chức thực hiện (1946 - 1950)                                                                        (1965 - 1975)

           Lãnh đạo xây dựng, bảo vệ                                                            Lãnh đạo xây dựng chủ nghĩa xã hội ở
         chính quyền cách mạng, kháng chiến                                                          miền Bắc và kháng chiến chống đế quốc
           chống thực dân Pháp xâm lược                                                Mỹ xâm lược, giải phóng miền Nam,               Chương 2                                                                                                             thống nhất đất nước (1954 - 1975)                     (1945 - 1954)

 Đẩy mạnh cuộc kháng chiến đến thắng lợi                   Ý nghĩa lịch sử và kinh nghiệm lãnh đạo
                (1951 - 1954)                                                                 của Đảng thời kỳ 1954 - 1975
  Ý nghĩa lịch sử và bài học kinh nghiệm của Đảng trong
lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ'),
('session-13',3,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
Đại hội đại biểu lần thứ II                                       Bối cảnh lịch sửvà Chính cương của Đảng
         (2/1951)
                                                                                 "Chiến tranh đơn phương"

        1949 Liên Xô chế tạo thành công
             bom nguyên tử                                                         23/12/1950
                                                                          Hiệp định Phòng thủ
         Công nghiệp tăng bình quân                                                   chung
           9.6%/năm, trở thành nước            Cách mạng ba nước Đông Dương
            công nghiệp thứ 2 sau Mỹ              phát triển theo chiều hướng tích cực'),
('session-13',4,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
Đại hội đại biểu lần thứ II
và Chính cương của Đảng
         (2/1951)
                                                                                                                                             22/3/1955
                                                                                                            Đảng Nhân dân Lào

                                                                                                                                                  2/1951
                                                                                                          Đảng Lao động Việt Nam
                                                                                                                                        tuyên bố hoạt động
                                                                                                                                         công khai

                                                       Đảng Cộng sản Đông Dương
               Đại hội II
                                                                                                                                             28/6/1951
   Vinh Quang, Chiêm Hóa, Tuyên Quang                                                                                                             Đảng Nhân dân
                                                                                                                                         cách mạng Campuchia                 11 - 19/2/1951
        158 đại biểu chính thức, 53 dự khuyết
        Đại diện cho hơn 766.000 đảng viên'),
('session-13',5,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
Đại hội đại biểu lần thứ II
và Chính cương của Đảng
         (2/1951)

                                           Chính cương Đảng Lao động Việt Nam

              Tổng kết phong trào cách
           mạng thế giới và Việt Nam,
              dự báo triển vọng tốt đẹp                                                                                     Đường lối cách mạng
                                                                                          dân tộc dân chủ nhân dân
         Mục tiêu trước mắt là tiêu diệt                                                                                                                          tiến lên chủ nghĩa xã hội
             thực dân Pháp, can thiệp Mỹ
               giành độc lập hoàn toàn'),
('session-13',6,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
Đại hội đại biểu lần thứ II
và Chính cương của Đảng                                                                                           Xác định
         (2/1951)                                                                                                               tính chất
                                                                                               xã hội
                                                                                                              Việt Nam
             Hồ Chí Minh
                   bầu làm
                                                                           Điều lệ                           Nhiệm vụ              Chủ tịch Đảng
                                                                Đảng mới                                                                                                                  cách mạng
                                                                                           Chính cương
                                                                                 Đảng Lao động
                                                                                                                Việt Nam

                                       Đại hội II (2/1951)                 Trường Chinh
                   bầu làm                                                                                             Triển vọng            Động lực của
                 Tổng bí thư                                                                                       phát triển                 cách mạng'),
('session-13',7,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
Đại hội đại biểu lần thứ II
và Chính cương của Đảng
                                                               Nhiệm vụ chính         (2/1951)

                                                                            Đánh đuổi đế
            Tính chất của                                                              quốc xâm lược,                          Xóa bỏ di tích
                                                                                                                                phong kiến và          xã hội Việt Nam                                                             giành độc lập và                                                                                                                         nửa phong kiến,                                                                                             thống nhất thật
                                                                                                                           làm cho người                                                                                                sự cho dân tộc                       Một phần                                                                                                                                               cày có ruộng
                              thuộc địa                                                             Nhiệm vụ  Dân chủ
  nhân dân                                                                cách mạng
                         Nửa                                             Chính cương                            Việt Nam                          phong kiến                                    Đảng Lao động Việt Nam
                                                           Gây cơ sở cho                                                                                                                    Phát triển         Đối tượng đấu tranh chính
                                                                        chủ nghĩa     CNĐQ xâm lược Pháp, can thiệp                                                                                              chế độ dân chủ
      Mỹ và phong kiến phản động                                            xã hội                              nhân dân'),
('session-13',8,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
                                                                                             Đại hội đại biểu lần thứ II
                         Lực lượng lãnh đạo                                                              và Chính cương của Đảng
                                    cách mạng                                                                                   (2/1951)

                                                        Nông dân                       Công nhân

                                                                    Động lực của
                                                                                        cách mạng
         Chính cương                                                                                             Việt Nam
    Đảng Lao động Việt Nam
                             Tiểu tư sản và                                                                  Thân sĩ yêu nước
                             tư sản dân tộc                                                                        và tiến bộ

                                                        Công - nông - trí       Nền tảng'),
('session-13',9,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
                                                                      Triển vọng phát triển                             Đại hội đại biểu lần thứ II
                                                                nhất định sẽ tiến lên                               và Chính cương của Đảng
                                                                  chủ nghĩa xã hội                                               (2/1951)
        Chính cương
   Đảng Lao động Việt Nam            Giai đoạn 1                  Giai đoạn 2                    Giai đoạn 3

                                                                     Xóa bỏ tàn tích                 Xây dựng CSVC                         Hoàn thành                                                                          phong kiến, thực                                                                                                      cho CNXH,                                        giải phóng                       hiện triệt để người                                                                                                                       tiến lên thực hiện
                              dân tộc                        cày có ruộng, hoàn                                                                   CNXH                                                                                  chỉnh chế độ DCND

                                                  Mục đích, tôn chỉ của Đảng
                                                                                                           Là Đảng của giai cấp                                                                         "để thực hiện tự do, hạnh phúc
            Điều lệ mới                                     cho giai cấp công nhân, nhân                                        công nhân, nhân dân                      13 chương,
                                                           dân lao động và tất cả các dân                                              lao động và toàn thể             của Đảng                        71 điều                                                                            tộc đa số, thiểu số ở Việt Nam"                                      dân tộc Việt Nam'),
('session-13',10,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
  Đẩy mạnh phát triển
     cuộc kháng chiến                                                                                              Phát triển chiến tranh du        về mọi mặt                                                                                                                kích vùng sau lưng địch
                            Tiêu diệt một bộ phận sinh lực địch
                                    giải phóng một phần Tây Bắc
                         Phá âm mưu "xứ Thái tự trị"                                            Đầu 1951
                                                                    Mở các chiến dịch
                                                                                                                         tiến công quy mô lớn vào
                            Chiến dịch Hòa Bình (12/1951)                                                                                                   trung du và đồng bằng Bắc bộ                          Chiến dịch Tây Bắc Thu đông 1952

                   Chiến dịch Thượng Lào 5/1953
                 Giải phóng đất đai, khu căn cứ của Lào                                                                                         Phá hủy 5 triệu lít xăng,        Phá thế bố trí chiến lược của Pháp ở Bắc Đông Dương
                                                                              1000 quả bom, một đại đội Pháp

                                                                                Đánh khu hậu cần của Pháp ở
                                                                                     Phú Thọ (Sài Gòn) 8/5/1952'),
('session-13',11,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
  Đẩy mạnh phát triển
     cuộc kháng chiến                                                      Hội nghị BCHTW Đảng thứ ba 4/1952        về mọi mặt                      Chính trị                                     Xác định "chỉ Đảng, chỉnh quân"
                                                                      Xây dựng Đảng, xây dựng quân đội

                                                                   Vận động gia tăng sản xuất, thực hành tiết kiệm
                                                                        Tự túc một phần lương thực, thực phẩm
                                              Đảm bảo đạn dược, thuốc men, quân trang, quân dụng cung cấp đủ cho quân đội                       Kinh tế
                                                                          Chấn chỉnh lại chế độ thuế khóa
                        xã hội                                                                        Xây dựng ngành thương nghiệp, ngân hàng
                                                                      Thực hiện từng bước chính sách ruộng đất, nông nghiệp, địa tô

                                                                     Xây dựng nếp sống mới
                   Văn hóa                             Củng cố mặt trận dân tộc thống nhất
                                                                 Đẩy mạnh giáo dục'),
('session-13',12,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
  Đẩy mạnh phát triển                                    Chủ trương thực hiện các
     cuộc kháng chiến                                                            cải cách dân chủ
        về mọi mặt

                                                                Tạm cấp gần 180.000 ha
     Từ đầu                                                                        đất của thực dân,                                            Phát động quần chúng                                                                                                   địa chủ Việt gian,
                                                              triệt để giảm tô, giảm tức                                                                                   ruộng công, hoang hóa,       1953
                                                                                 vắng chủ cho nông dân

                                                                                                                                              Thúc đẩy phát triển
                                            Tiến tới cải cách ruộng đất, thực                                                          nông thôn, đáp ứng
                                                                                                                                              nguyện vọng nông dân,
                                             hiện mục tiêu người cày có ruộng                                                                                                                                                                                      chi viện cho tiền tuyến

         Hội nghị lần thứ 4                       Hội nghị lần thứ 5                      Kỳ họp thứ 3                           Giáo điều chủ nghĩa,
       BCHTW - 1/1953                BCHTW - 11/1953              QH khóa I -4/12/1953                      độc đoán, chuyên quyền,
                                                                                                                                                           định kiến chủ quan,
 Họp kiểm điểm về thực hiện chủ trương            Thông qua Cương lĩnh ruộng đất ...                 Thông qua Luật cải cách ruộng đất                  quan liêu, mệnh lệnh,
                                                                                                                                                     nhất là phương pháp, & quyết định tiến tới cải cách ruộng đất      Chủ trương thực hiện dưới nhiều hình thức: hiến      Hàng ngàn héc ta ruộng, các loại nông cụ, trâu
                                                 ruộng đất, trung mua, tịch thu đem chia cho           bò, TLSX nông nghiệp đã được chia cho dân cày,                    cách làm   một số vùng nông thôn Việt Nam                                            những người không có hoặc thiếu ruộng cày cấy                nhất là bần nông và cố nông'),
('session-13',13,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
                                                                                                            Kết hợp đấu tranh quân sự
                                                                                                       và ngoại giao, kết thúc                                                     Chiếm     Tập                                                                                                          thắng lợi cuộc kháng chiến
                                                                     giữ      trung

                                             Bảo vệ đồng bằng
                                                    Bắc Bộ

                                                                                   Bị kẹt trong
                                                                                    nhiều lựa
                                                                                chọn
                                            Bảo vệ vùng Tây Bắc,
                                                 Thượng Lào                           Ngày càng lệ
                                                                              thuộc vào Mỹ

                                                      Phòng     Tiến
                                                        ngự      công'),
('session-13',14,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
                                                                                                            Kết hợp đấu tranh quân sự
                                                                                                       và ngoại giao, kết thúc
                                                                                                          thắng lợi cuộc kháng chiến                                                    18 tháng
                                                                  Tập trung binh lực,                              "Chuyển bại      5/1953                                                                           "quả đấm thép"                              thành thắng"                                                                               quyết chiến với
                                                                                      Việt Minh

                                         Kế hoạch "Navarre"
                                                      7/1953

     Henri Navarre                         Tổng chỉ huy quân đội
 Tổng tham mưu trưởng                       viễn chinh Pháp ở Đông Dương                    Biến Điện Biên Phủ
      lục quân NATO                                                            thành “pháo đài bất khả xâm phạm”,
                                                                                             “cổ máy nghiền Việt Minh”'),
('session-13',15,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
                                                                                                            Kết hợp đấu tranh quân sự
                                                                                                       và ngoại giao, kết thúc
                                                                                                          thắng lợi cuộc kháng chiến

                                                                                           Tiến công chiến lược
                                                                     Đông Xuân 1953 - 1954      Bộ chỉ huy Chiến dịch Điện Biên Phủ

                                                                                                      1.Tiêu diệt sinh lực địch,
                                              9/1953                                                                                                    bồi dưỡng lực lượng ta
                                                                                                               2. Giữ vững thế chủ động,
                                                                                  buộc địch phải phân tán lực lượng

          Đại tướng Võ Nguyên Giáp
            “Tướng quân tại ngoại”'),
('session-13',16,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
                                                                                                            Kết hợp đấu tranh quân sự
                                                                                                       và ngoại giao, kết thúc
                                                                                                          thắng lợi cuộc kháng chiến

                                       Chiến thắng Điện Biên Phủ
                                                                                              Hiệp định Geneve                                “Lừng lẫy năm châu, chấn động địa cầu”'),
('session-13',17,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
                Đẩy mạnh cuộc kháng chiến đến thắng lợi (1951 - 1954)
                                                                                                            Kết hợp đấu tranh quân sự
                                                                                                       và ngoại giao, kết thúc
        Không ký,                                                                                                          thắng lợi cuộc kháng chiến
      những tuyên bố
          sẽ tôn trọng
         Hiệp định

                                               Tuyên bố chung của
                                               Hội nghị Geneve
                                                          21/7/1954

                       Cam kết tôn trọng  Không can thiệp  Cam kết chấm dứt
                                quyền dân tộc cơ   vào công việc nội    chiến tranh và
                               bản của ba nước    bộ của ba nước     lập lại hòa bình
                             Đông Dương     Đông Dương'),
('session-13',18,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-14',1,'ĐẢNG LÃNH ĐẠO HAI CUỘC KHÁNG CHIẾN CHỐNG NGOẠI XÂM,
HOÀN THÀNH GIẢI PHÓNG DÂN TỘC, THỐNG NHẤT ĐẤT NƯỚC
                          (1945 - 1975)

            Chương 2'),
('session-14',2,'Xây dựng và bảo vệ chính quyền cách mạng                           Sự lãnh đạo của Đảng đối với
               1945 - 1946                                                             cách mạng hai miền Nam - Bắc (1954 - 1965)
      Đường lối kháng chiến toàn quốc                              Lãnh đạo cách mạng cả nước
  và quá trình tổ chức thực hiện (1946 - 1950)                                                                        (1965 - 1975)

           Lãnh đạo xây dựng, bảo vệ                                                            Lãnh đạo xây dựng chủ nghĩa xã hội ở
        chính quyền cách mạng, kháng chiến                                                          miền Bắc và kháng chiến chống đế quốc
          chống thực dân Pháp xâm lược                                                Mỹ xâm lược, giải phóng miền Nam,               Chương 2                                                                                                            thống nhất đất nước (1954 - 1975)                    (1945 - 1954)

  Đẩy mạnh cuộc kháng chiến đến thắng lợi                     Ý nghĩa lịch sử và kinh nghiệm lãnh đạo
                (1951 - 1954)                                                                 của Đảng thời kỳ 1954 - 1975

  Ý nghĩa lịch sử và bài học kinh nghiệm của Đảng trong
lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ'),
('session-14',3,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
   Ý nghĩa lịch sử và kinh nghiệm của Đảng trong lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ

  Ý nghĩa thắng lợi
    của cuộc chiến                                          Có tính lan tỏa trong                               Bảo vệ thành quả của
                                                           khu vực và mang tầm vóc                                Cách mạng tháng Tám
                                                                                  thời đại sâu sắc

                     Củng cố, phát triển                              Chứng tỏ được sức mạnh của
                      chế độ mới trên mọi lĩnh vực                                     tinh thần độc lập dân tộc                Ý nghĩa

                                                                  Cổ vũ phong trào
                Mang đến niềm tin tất thắng                         lịch sử                                                                       đấu tranh vì hòa bình,
                         của kháng chiến
                                                                         dân chủ và tiến bộ

                                                            Đặt nền móng cho                              Miền Bắc tiến lên CNXH,
                                                                 sự tan rã hệ thống thuộc địa                             hậu phương lớn cho tiền tuyến
                                                                                trên thế giới                                      miền Nam'),
('session-14',4,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
   Ý nghĩa lịch sử và kinh nghiệm của Đảng trong lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ

  Ý nghĩa thắng lợi
    của cuộc chiến

                                               Sau nhiều năm ở Việt Bắc,                                                                                                         Bảo vệ thành quả của
                                     Đảng và nhân dân đã tiếp quản Thủ Đô                        Cách mạng tháng Tám

                                                                                             Củng cố, phát triển
                                                                                                                   chế độ mới trên mọi lĩnh vực

                                                                                 Mang đến niềm tin tất thắng
                                                                                                              của kháng chiến

                                                                                                         Miền Bắc tiến lên CNXH,
                                                                                                          hậu phương lớn cho tiền tuyến
                                                                                                                     miền Nam'),
('session-14',5,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
   Ý nghĩa lịch sử và kinh nghiệm của Đảng trong lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ

  Ý nghĩa thắng lợi
    của cuộc chiến

    Có tính lan tỏa trong
   khu vực và mang tầm vóc
         thời đại sâu sắc

           Chứng tỏ được sức mạnh của
                                                                              “Người ta có thể đánh bại một quân đội,                 tinh thần độc lập dân tộc
                                                                            chứ không thể đánh bại được một dân tộc”

               Cổ vũ phong trào                                                             “Hân hạnh được làm kẻ chiến bại của Tướng Giáp”               đấu tranh vì hòa bình,
                dân chủ và tiến bộ

     Đặt nền móng cho                        Tướng De Castries bị bắt
  sự tan rã hệ thống thuộc địa
          trên thế giới'),
('session-14',6,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
   Ý nghĩa lịch sử và kinh nghiệm của Đảng trong lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ

  Ý nghĩa thắng lợi
    của cuộc chiến                                           Điện Biên Phủ trở thành biểu tượng lan tỏa
                                                                       tinh thần đấu tranh giải phóng dân tộc

    Có tính lan tỏa trong
   khu vực và mang tầm vóc
         thời đại sâu sắc

           Chứng tỏ được sức mạnh của
                 tinh thần độc lập dân tộc

               Cổ vũ phong trào
               đấu tranh vì hòa bình,
                dân chủ và tiến bộ

     Đặt nền móng cho
  sự tan rã hệ thống thuộc địa
          trên thế giới                                 Người dân Algeria mừng ngày độc lập
                                                            5/7/1962'),
('session-14',7,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
   Ý nghĩa lịch sử và kinh nghiệm của Đảng trong lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ

  Ý nghĩa thắng lợi
    của cuộc chiến                                           Điện Biên Phủ trở thành biểu tượng lan tỏa
                                                                       tinh thần đấu tranh giải phóng dân tộc

    Có tính lan tỏa trong
   khu vực và mang tầm vóc
         thời đại sâu sắc

           Chứng tỏ được sức mạnh của
                 tinh thần độc lập dân tộc

               Cổ vũ phong trào
               đấu tranh vì hòa bình,
                dân chủ và tiến bộ

     Đặt nền móng cho                              Chủ tịch Cuba Fidel Castro trong buổi diễu
  sự tan rã hệ thống thuộc địa
          trên thế giới                                      hành chiến thắng ở Quảng trường
                                                          thủ đô La Habana năm 1959'),
('session-14',8,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
   Ý nghĩa lịch sử và kinh nghiệm của Đảng trong lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ

Kinh nghiệm của Đảng
về lãnh đạo kháng chiến
                                                                     Đề ra đường lối đúng đắn, sáng tạo,
                                                                         phù hợp với thực tiễn ngay từ những ngày đầu

                                                                         Kết hợp chặt chẽ và giải quyết đúng đắn mối quan hệ
                                                                              giữa hai nhiệm vụ vừa kháng chiến vừa kiến quốc,
                                                                              chống đế quốc và chống phong kiến

                                                                Ngày càng hoàn thiện phương thức lãnh đạo, tổ chức, điều hành
                                                                                 cuộc kháng chiến phù hợp với đặc thù của từng giai đoạn

                                                               Xây dựng và phát triển lực lượng vũ trang ba thứ quân
                                                               một cách thích hợp, kịp thời đáp ứng yêu cầu nhiệm vụ

                                                                                            Coi trọng công tác xây dựng, chỉnh đốn Đảng,
                                                                                     nâng cao vai trò lãnh đạo toàn diện của Đảng'),
('session-14',9,'I. Lãnh đạo xây dựng, bảo vệ chính quyền cách mạng, kháng chiến chống thực dân Pháp xâm lược (1945 - 1954)
   Ý nghĩa lịch sử và kinh nghiệm của Đảng trong lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ

Kinh nghiệm của Đảng
về lãnh đạo kháng chiến

     Đường lối cơ bản là
   “kháng chiến, kiến quốc”

                           Kháng chiến toàn dân,                                                       Kháng chiến toàn diện            Kháng chiến trường kỳ
                                     tự lực cánh sinh'),
('session-14',10,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-15',1,'ĐẢNG LÃNH ĐẠO HAI CUỘC KHÁNG CHIẾN CHỐNG NGOẠI XÂM,
HOÀN THÀNH GIẢI PHÓNG DÂN TỘC, THỐNG NHẤT ĐẤT NƯỚC
                          (1945 - 1975)

            Chương 2'),
('session-15',2,'Xây dựng và bảo vệ chính quyền cách mạng                          Sự lãnh đạo của Đảng đối với
              1945 - 1946                                  cách mạng hai miền Nam - Bắc (1954 - 1965)
     Đường lối kháng chiến toàn quốc                              Lãnh đạo cách mạng cả nước
 và quá trình tổ chức thực hiện (1946 - 1950)                                                                       (1965 - 1975)

         Lãnh đạo xây dựng, bảo vệ                                                            Lãnh đạo xây dựng chủ nghĩa xã hội ở
      chính quyền cách mạng, kháng chiến                                                          miền Bắc và kháng chiến chống đế quốc
        chống thực dân Pháp xâm lược                                                Mỹ xâm lược, giải phóng miền Nam,               Chương 2                                                                                                          thống nhất đất nước (1954 - 1975)                  (1945 - 1954)

 Đẩy mạnh cuộc kháng chiến đến thắng lợi                     Ý nghĩa lịch sử và kinh nghiệm lãnh đạo
               (1951 - 1954)                                                                của Đảng thời kỳ 1954 - 1975

  Ý nghĩa lịch sử và bài học kinh nghiệm của Đảng trong
lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ'),
('session-15',3,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
   Khôi phục kinh tế, cải tạo                                     Hệ thống XHCN,
 XHCN ở miền Bắc, chuyển                                                                      Liên Xô ngày càng lớn mạnh  cách mạng miền Nam sang
  thế tiến công (1954 - 1960)
                                                                                                          Bất đồng nội bộ khối                Mỹ hùng mạnh,
                   âm mưu làm   Bối cảnh lịch sử                                                                          XHCN,
                                                                                    mâu thuẫn Xô Trung                         bá chủ thế giới

                                                           Ba dòng thác
                                                                             cách mạng

                                                                                   Phong trào    Thế giới bước vào chiến tranh lạnh,                                                                                      xã hội chủ nghĩa
           chạy đua vũ trang                    Phong trào
                                                              giải phóng dân tộc
                                                                  Phong trào
                                                                  hòa bình, dân chủ'),
('session-15',4,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
   Khôi phục kinh tế, cải tạo
 XHCN ở miền Bắc, chuyển
  cách mạng miền Nam sang
  thế tiến công (1954 - 1960)
                                                      Miền Bắc đi lên CNXH,
   Bối cảnh lịch sử                                                                        trở thành hậu phương
                                                        Kinh tế nghèo nàn, lạc hậu
                                                                               bị chiến tranh tàn phá

                                             Một Đảng
                                                        hai nhiệm vụ

                                                                                                     Trở thành kẻ thù
                                              Do đế quốc, tay sai                                 trực tiếp của
                                                               kiểm soát,                          nhân dân Việt Nam
        10/10/1954                                        không chịu thực hiện
      Giải phóng Thủ đô                                          Hiệp thương'),
('session-15',5,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                 Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
    Khôi phục kinh tế, cải tạo
  XHCN ở miền Bắc, chuyển                                   Sớm đưa miền Bắc   cách mạng miền Nam sang                                                   trở lại bình thường    thế tiến công (1954 - 1960)
                                          sau 9 năm kháng chiến
Chủ trương với Miền Bắc                                                                              Phải ra sức
                                                                                                 củng cố miền Bắc

                                                            Hội nghị                                                   9/1954
                                                            Trung ương               Mỹ đã dựng nên                                        Bộ Chính trị đề ra    Hàn gắn vết thương                                                                                                         Điều cốt lõi của                                                                                                       chính quyền bù nhìn                                            nhiệm vụ chủ yếu         lần 7 (3/1955) &
         chiến tranh                                                                                                                          cách mạng                                                      trước mắt của                                          chống phá Hiệp định                                                                    lần 8 (8/1955)
                                                miền Bắc                                                              khóa II
       Tăng cường và
      mở rộng quan
                                                                                                          Giữ vững và đẩy mạnh           hệ quốc tế
                                                                                                                            cuộc đấu tranh của
                                                                                                       nhân dân miền Nam
               Trước hết là phục hồi     Phục hồi kinh tế
           nông nghiệp, ổn định xã hội,                                      quốc dân
                  đời sống nhân dân'),
('session-15',6,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                 Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
   Khôi phục kinh tế, cải tạo
  XHCN ở miền Bắc, chuyển                                                           11/1958   cách mạng miền Nam sang
   thế tiến công (1954 - 1960)                    HNTW
Thực hiện chủ trương miền Bắc                                lần thứ 14                                                                       Đã xây mới 7 nhà máy
            Vận động đổi công,
                                                                               Đang xây thêm 11 nhà máy
               giúp nhau sản xuất                  Kế hoạch 3 năm                                                                                   Củng cố 28 xí nghiệp cũ
                                                                                                               1955: 28 tỷ đồng          1957, năng suất và sản lượng
        đạt mức trước chiến tranh (1939),       Khôi phục và         Công nghiệp,                     --> 1957: 232 tỷ đồng
       năm cao nhất thời Pháp thuộc                                   phát triển nông nghiệp    tiểu thủ công nghiệp,
                                                là trọng tâm         giao thông vận tải

              Cải cách ruộng đất                                                                  Khôi phục 657km đường sắt                1957
                                                                                            1624 Km đường bộ       7/1956 Chế độ chiếm hữu ruộng đất
   phong kiến ở miền Bắc đã xóa bỏ hoàn toàn
                                                                     Làm mới 600km trục đường chính      Hơn 9 triệu người trong 2 triệu hộ
        được chia 810.000 ha ruộng đất'),
('session-15',7,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                 Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
   Khôi phục kinh tế, cải tạo
  XHCN ở miền Bắc, chuyển
   cách mạng miền Nam sang
   thế tiến công (1954 - 1960)
Thực hiện chủ trương miền Bắc

                                                                                              Chính trị    Tự nguyện         Cùng có lợi      Quản lý dân chủ
                                                                                  GCTS là một thành viên của
                                                                                         Mặt trận Tổ quốc
                Ba nguyên tắc
                   hợp tác xã                     4/1959
                           HNTW        Cải tạo hòa bình                                                                                              Kinh tế                                                                                           với giai cấp tư sản                   Hình thức &                                                                                                                                                                           1. Không tịch thu mà mua lại,                                               lần thứ 16                       bước đi                                                                                                               công tư hợp doanh TLSX
                                                                                                                                              2. Sắp xếp công việc cho người tư
        Hợp tác hóa                                                                                        sản trong xí nghiệp, dần cải tạo
    (Thủy lợi hóa và tổ chức lại                                                                                      thành người lao động                      Cơ giới hóa
             lao động)'),
('session-15',8,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
   Khôi phục kinh tế, cải tạo
  XHCN ở miền Bắc, chuyển
  cách mạng miền Nam sang
  thế tiến công (1954 - 1960)
Chủ trương với miền Nam

                                          Biến miền Nam thành thuộc
                                                                                     "Biên giới của Mỹ kéo dài đến vĩ tuyến 17"                                              địa kiểu mới, là nơi đối đầu                                                                                                         - Ngô Đình Diệm
                                             chiến lược ở chiến tranh lạnh                                                                        Lập “khu trù mật”, “khu dinh điền”'),
('session-15',9,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
   Khôi phục kinh tế, cải tạo
  XHCN ở miền Bắc, chuyển
  cách mạng miền Nam sang
  thế tiến công (1954 - 1960)
Chủ trương với miền Nam
                                                                  Nhiệm vụ trước mắt                                                                                                                    10/1954
                                                       Đấu tranh đòi thi hành Hiệp định       Xứ ủy Nam Kỳ thành lập
                                                           Chuyển hướng công tác phù hợp tình hình mới
                           Xác định kẻ thù chính                    Tập hợp mọi lực lượng đấu tranh lật đổ
                                            là Mỹ                                                                            chính quyền bù nhìn thân Mỹ

                                                                   22/7/1954                    HN TW lần                                         Nghị quyết
                                                                      Lời kêu gọi
                                   thứ 6                                      Bộ Chính trị    7/1954                                                             đồng bào và
                                  7/1954                                              9/1954                                                                       chiến sĩ cả nước

                                                    "Trung - Nam - Bắc đều là   Chuyển từ đấu tranh
                                                    bờ cõi của ta, nước ta nhất   quân sự sang chính trị                                                                                                                  Bí thư Xứ ủy Nam Kỳ - Lê Duẩn                                                          định thống nhất"
                                                                                     Dự thảo
                                                                                                      "Đề cương đường lối cách mạng
                                                                                                          miền Nam Việt Nam"'),
('session-15',10,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
   Khôi phục kinh tế, cải tạo
  XHCN ở miền Bắc, chuyển
  cách mạng miền Nam sang
  thế tiến công (1954 - 1960)
                                                                Nghị quyết Hội nghị Trung ương 15Chủ trương với miền Nam
                                                               (mở rộng) Tháng 1 / 1959

           3/1959                                                             1. Tinh thần cơ bản là tiếp tục của cách mạng dân tộc dân chủ nhân dân
      "đặt miền Nam trong                                               2. Sử dụng bạo lực cách mạng với hai lực lượng chính trị và vũ trang
     tình trạng chiến tranh"          Luật 10/59                                                                                       3. Kết hợp đấu tranh chính trị với quân sự
                           Lập Toàn án                                                                  4. Khởi nghĩa từng phần tiến tới khởi nghĩa vũ trang giành chính quyền
                          quân sự đặt biệt'),
('session-15',11,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                 Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)
    Khôi phục kinh tế, cải tạo
  XHCN ở miền Bắc, chuyển
   cách mạng miền Nam sang
   thế tiến công (1954 - 1960)
Thực hiện chủ trương miền Nam

       Đường 559
  "Đường mòn Hồ Chí Minh"
       Đường 759
"Đường Hồ Chí Minh trên biển"
                                                                                                     20/12/1960
                                                   Phong trào Đồng khởi 1960 ở             Tân Lập - Tây Ninh
                                                                         Mặt trận Dân tộc Giải phóng miền Nam                                                 Bến Tre và lan ra nhiều tỉnh khác
                                                                                                      Việt Nam do Nguyễn Hữu Thọ làm Chủ tịch'),
('session-15',12,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)

  Xây dựng CNXH ở miền Bắc,
    phát triển thế tiến công của
      cách mạng Việt Nam
          (1961 - 1965)
               5 - 10/9/1960
       Đại hội Đại biểu lần thứ III - Hà Nội
                                                                Đường lối chung của               Về hòa bình,
                                                                                cách mạng Việt Nam              thống nhất Tổ quốc

                                                              Mục tiêu                   Về triển vọng
                                                                                        chiến lược chung                     cách mạng

                                                                              Vị trí, vai trò,                  Về xây dựng
                                                                         nhiệm vụ cụ thể                 chủ nghĩa xã hội
   “Đại hội lần này là Đại hội xây dựng chủ nghĩa xã hội ở miền Bắc
           và đấu tranh hòa bình thống nhất nước nhà”'),
('session-15',13,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)

  Xây dựng CNXH ở miền Bắc,
    phát triển thế tiến công của
      cách mạng Việt Nam
          (1961 - 1965)

  Thực hiện đồng thời hai chiến lược ở hai miền:
                                               Đường lối chung của       Cách mạng XHCN ở miền Bắc &
                                                           cách mạng Việt NamCách mạng dân tộc dân chủ nhân dân ở miền Nam

                                                                                                                          Quyết định toàn bộ                   Giải phóng miền Nam,                                              Mục tiêu                                                                                                                                       cách mạng Việt Nam và
              hòa bình, thống nhất đất nước                                                                 chiến lược chung                                                                                                                                sự nghiệp thống nhất nước nhà

                                                          Vị trí, vai trò,                                        Quyết định trực tiếp đối với sự
                                                      nhiệm vụ cụ thể                                             nghiệp giải phóng miền Nam,
                                                                                                                                  thống nhất nước nhà'),
('session-15',14,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)

    Kiên định giữ vững đường lối hòa bình                                                                      Xây dựng CNXH ở miền Bắc,
                                                  Về hòa bình, Đề cao cảnh giác địch dám đánh ra miền Bắc,                                                                               phát triển thế tiến công của
                                                      thống nhất Tổ quốc                                              cách mạng Việt Nam   cả nước sẵn sàng đứng lên đánh bại chúng                                                                                                                                        (1961 - 1965)

    Gay go, gian khổ, phức tạp và lâu dài
                                                  Về triển vọng     Thắng lợi cuối cùng nhất định về ta,                                                                   CNH XHCN là nhiệm vụ trung tâm                                                              cách mạng   Bắc - Nam nhất định sum họp một nhà                                                                                                                  trong suốt thời kỳ quá độ

                                                                LLSX
                                                                                          Tư tưởng,
                                               QHSX                                                                                            văn hóa, tinh thần

                                         Xã hội tiền tư bản                                                        Chủ nghĩa             Chủ nghĩa
            Về xây dựng                     Kinh tế nông nghiệp
                                                                            tư bản                   xã hội            chủ nghĩa xã hội                               lạc hậu

                                                   Đường lối chung: Đoàn kết toàn dân, phát huy truyền thống yêu nước,
                                                                         lao động cần cù của nhân dân và đoàn kết với các nước XHCN'),
('session-15',15,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)

                                                                                                           Xây dựng CNXH ở miền Bắc,
                                                                                                                             phát triển thế tiến công của
                                                                                                                                      cách mạng Việt Nam
                                                                                                                                        (1961 - 1965)                                                  Căn cứ địa vững chắc
                                                                      với chế độ chính trị ưu
                                                                                      việt, kinh tế và quốc                   Kế hoạch 5 năm
                                                           phòng lớn mạnh                        lần thứ nhất
                      1961 - 1965

                Mục tiêu
             1.Tiếp tục hoàn thiện QHSX XHCN
                                                                                                   1965 tăng gấp 9 lần số  2. Xây dựng một bước cơ sở vật chất - kỹ thuật cho CNXH                                                                                                     quân chi viện                 3. Cải thiện đời sống nhân dân                                                                                                  10 lần vật chất               4. Bảo đảm quốc phòng an ninh                                                                                                                        so với 1961
 5. Làm hậu thuẫn cho cuộc đấu tranh thống nhất nước nhà'),
('session-15',16,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)

                                                                                                           Xây dựng CNXH ở miền Bắc,                                           Kế hoạch Staley-Taylor (1961 - 1963)                                                                                                                             phát triển thế tiến công của
                                                                                                                                      cách mạng Việt Nam                                        Kế hoạch Johnson - Mcnamara (1964 - 1965)
                                                                                                                                        (1961 - 1965)

                             Trực                                                                   Thiết
                            thăng                                                        xa
                           vận                                                       vận

                             10/8/1961                                            Ấp
                  Mỹ rải chất                                                              chiến
                             độc dioxin                                                                 lược   Ở miền Nam
      Từ 1961'),
('session-15',17,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                Sự lãnh đạo của Đảng đối với cách mạng hai miền Nam - Bắc (1954 - 1965)

                                                                                                           Xây dựng CNXH ở miền Bắc,
                                                                                                                             phát triển thế tiến công của
                                                                                                                                      cách mạng Việt Nam
                                                                                                                                        (1961 - 1965)                              Chiến thắng Ấp Bắc (Mỹ Tho) -
                                           2/1/1963          “Một tấc không đi, một ly không rời”

                                        Nhiều chiến công khắp nơi ở miền Nam
   Ở miền Nam           Đến đầu 1965, ba trụ cột của chiến tranh đặc biệt: ngụy quân,
      Từ 1961         ngụy quyền, ấp chiến lược lung lay tận gốc, “Chiến tranh đặc biệt” phá sản!'),
('session-15',18,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-16',1,'ĐẢNG LÃNH ĐẠO HAI CUỘC KHÁNG CHIẾN CHỐNG NGOẠI XÂM,
HOÀN THÀNH GIẢI PHÓNG DÂN TỘC, THỐNG NHẤT ĐẤT NƯỚC
                          (1945 - 1975)

            Chương 2'),
('session-16',2,'Xây dựng và bảo vệ chính quyền cách mạng                               Sự lãnh đạo của Đảng đối với
              1945 - 1946                                          cách mạng hai miền Nam - Bắc (1954 - 1965)
     Đường lối kháng chiến toàn quốc                        Lãnh đạo cách mạng cả nước
 và quá trình tổ chức thực hiện (1946 - 1950)                                                                 (1965 - 1975)

         Lãnh đạo xây dựng, bảo vệ                                                            Lãnh đạo xây dựng chủ nghĩa xã hội ở
      chính quyền cách mạng, kháng chiến                                                          miền Bắc và kháng chiến chống đế quốc
        chống thực dân Pháp xâm lược                                                Mỹ xâm lược, giải phóng miền Nam,               Chương 2                                                                                                          thống nhất đất nước (1954 - 1975)                  (1945 - 1954)

 Đẩy mạnh cuộc kháng chiến đến thắng lợi                     Ý nghĩa lịch sử và kinh nghiệm lãnh đạo
               (1951 - 1954)                                                                của Đảng thời kỳ 1954 - 1975
  Ý nghĩa lịch sử và bài học kinh nghiệm của Đảng trong
lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ'),
('session-16',3,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                      Lãnh đạo cách mạng cả nước (1965 - 1975)
      Đường lối
  kháng chiến chống Mỹ,
   cứu nước của Đảng
                                                            South
  Bối cảnh lịch sử                          Thailand        Korea

                          New
                                 Zealand                                Austraylia

                              Mỹ                         Hình: Tổng thống Mỹ Lyndon B. Johnson
                                                                                     “Chiến tranh cục bộ” - Local War Strategy                                                               8/3/1965
                                                                                            "Chiến lược phản ứng linh hoạt"                                            Quân Mỹ đổ bộ Đà Nẵng
                                           Tham chiến miền Nam,                  Chủ yếu: Quân Mỹ và đồng minh
   “Chiến tranh đặc biệt”                 mở rộng phá hoại miền Bắc             Hỗ trợ và bình định: Quân đội Sài Gòn
có nguy cơ thất bại hoàn toàn'),
('session-16',4,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
       "Quyết tâm đánh thắng                                                                         Đường lối
        giặc Mỹ xâm lược"                                       Đánh lâu dài,                      kháng chiến chống Mỹ,
                                                           dựa vào sức mình là chính                   cứu nước của Đảng
                                                         Càng đánh càng mạnh      Phát động toàn dân             Hội nghị Trung ương                                    Chủ trương                                                             Tập trung mở những          chống Mỹ                   lần thứ 11 (3/1965) và
                                                                         cuộc tiến công lớn                                        lần thứ 12 (12/1965)
          Quyết tâm                                                                    Phương châm
            chiến lược                                                                                       chiến lược                                     Đường lối
                                         kháng chiến
                                                                                               Miền Bắc                                            chống Mỹ         Mục tiêu                                                                  Tư tưởng                                                                                           Chuyển hướng kinh tế
            chiến lược                                                                                               chỉ đạo                                                                                                    Chi viện miền Nam
                                                                                       Chống chiến tranh phá hoại
      Bảo vệ miền Bắc,
      giải phóng miền Nam,
      thống nhất đất nước                                            Miền Nam
                                                                                                        Tiền tuyến           Hậu                                                                           Giữ, phát triển,
                                                                                                             lớn             phương lớn                                                                              kiên trì tiến công,
                                                                                               liên tục'),
('session-16',5,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                           Quá trình
                                                                                                  thực hiện đường lối
      Ở miền Bắc                                                                                                (1965 - 1968)

                                                                                                            5/8/1964 Mỹ dựng lên
                                                                                                                 “sự kiện Vịnh Bắc Bộ”

                                     Dùng không quân, hải quân đánh phá miền Bắc
                                      Ý đồ đưa miền Bắc trở về thời kỳ đồ đá,
                                                 ngăn chặn chi viện miền Nam
                                                                                        Bộ trưởng Quốc phòng Mỹ
                                                                                                              Robert S. McNamara'),
('session-16',6,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                           Quá trình
                                                                                                  thực hiện đường lối
      Ở miền Bắc                                                                                                (1965 - 1968)
                                             Miền
                                                Bắc

                                        Chuyển hướng        Chống chiến tranh            Chi viện
                                                 kinh tế                phá hoại               miền Nam

                                            Từ kinh tế XHCN            Tay cày, tay súng              “Ba sẵn sàng”
                                                  sang kinh tế thời chiến          Tay búa, tay súng               của thanh niên

                                             Tổ chức mô hình HTX       Bắn rơi 3.200 máy bay,         “Thóc không thiếu 1 cân
                                                       trang bị cơ khí nhỏ            140 tàu chiến         Quân không thiếu 1 người”
                                            Nhà máy CN lớn: sơ tán, chia nhỏ   1/11/1968 Mỹ chấm dứt ném           “Xe chưa qua,
                                                         thành CN địa phương        bom không điều kiện                                                                                                   nhà không tiếc”'),
('session-16',7,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                           Quá trình
         Ở miền Bắc                                                                     thực hiện đường lối
                                                                                                (1965 - 1968)
            “Ba đảm đang”
                                                                  Thanh niên vui mừng nhận
                                                                                   giấy trúng tuyển nhập ngũ

                                                                          “Tay cày, tay súng”
Đảm nhiệm sản xuất, công tác, thay thế cho nam giới đi chiến đấu.
Đảm nhiệm gia đình, khuyến khích chồng con yên tâm chiến đấu.
Đảm nhiệm phục vụ chiến đấu và sẵn sàng chiến đấu khi cần thiết.'),
('session-16',8,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                           Quá trình
                                                                                                  thực hiện đường lối
                                        Miền                                        (1965 - 1968)
                                Nam

                        Mùa khô          Mùa khô                                                     1968                              1965 - 1966          1966 - 1967'),
('session-16',9,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                           Quá trình
                                                                                                  thực hiện đường lối
                                        Miền                                        (1965 - 1968)
                                Nam

                        Phản công và
                                    tiến công

                        Mùa khô
                              1965 - 1966

                               700.000 quân
                                (20.000 quân Mỹ)
                                   Tây Nguyên,
                         Đồng bằng khu V, Đông Nam Bộ

                               Tìm diệt, bình định,
                                   giành lại thế chủ động
                               Lập 900 ấp chiến lược'),
('session-16',10,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                           Quá trình
                                                                                                  thực hiện đường lối
                                        Miền                                        (1965 - 1968)
                                Nam

                                  4 bám                     3 mũi giáp công
                             Cấp trên bám cấp dưới               Quân sự
                               Đảng bám dân                     Chính trị
                             Dân bám đất                      Binh vận
                            Bộ đội, du kích bám địch
                                            Mùa khô               80% đất do Mặt trận
                                                      1966 - 1967                                                                                 Giải phóng miền Nam Việt Nam kiểm soát
                                                         390.000 quân Mỹ
                                                          50.000 chư hầu
                                                        540.000 quân VNCH
                                                           4.000 máy bay
                                                                2.500 tăng giáp
                                                      Từ Tây Nguyên đến Sài Gòn
                                               Lấy lại 50% miền Nam'),
('session-16',11,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                           Quá trình
                                                                                                  thực hiện đường lối
                                        Miền                                        (1965 - 1968)
                                Nam

               1968

                                                                             “Chiến tranh cục bộ” phá sản
                                                       Đàm phán Pari
                                                                                       13/5/1968'),
('session-16',12,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                           Quá trình
                                                                                                  thực hiện đường lối
                                                                                                (1965 - 1968)

                     Ông Lê Đức Thọ
   Ông Xuân Thủy                     Ủy viên Bộ Chính trị
 Bộ Trưởng Ngoại giao                                    Bà Nguyễn Thị Bình                “Chiến tranh cục bộ” phá sản                         Cố vấn
     Trưởng đoàn                                        Bộ Trưởng Ngoại giao                                                             Đàm phán Pari
                                                               Trưởng đoàn
                                                                                                13/5/1968'),
('session-16',13,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-17',1,'ĐẢNG LÃNH ĐẠO HAI CUỘC KHÁNG CHIẾN CHỐNG NGOẠI XÂM,
HOÀN THÀNH GIẢI PHÓNG DÂN TỘC, THỐNG NHẤT ĐẤT NƯỚC
                          (1945 - 1975)

            Chương 2'),
('session-17',2,'Xây dựng và bảo vệ chính quyền cách mạng                               Sự lãnh đạo của Đảng đối với
              1945 - 1946                                          cách mạng hai miền Nam - Bắc (1954 - 1965)
     Đường lối kháng chiến toàn quốc                        Lãnh đạo cách mạng cả nước
 và quá trình tổ chức thực hiện (1946 - 1950)                                                                 (1965 - 1975)

         Lãnh đạo xây dựng, bảo vệ                                                            Lãnh đạo xây dựng chủ nghĩa xã hội ở
      chính quyền cách mạng, kháng chiến                                                          miền Bắc và kháng chiến chống đế quốc
        chống thực dân Pháp xâm lược                                                Mỹ xâm lược, giải phóng miền Nam,               Chương 2                                                                                                          thống nhất đất nước (1954 - 1975)                  (1945 - 1954)

 Đẩy mạnh cuộc kháng chiến đến thắng lợi                     Ý nghĩa lịch sử và kinh nghiệm lãnh đạo
               (1951 - 1954)                                                                của Đảng thời kỳ 1954 - 1975

  Ý nghĩa lịch sử và bài học kinh nghiệm của Đảng trong
lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ'),
('session-17',3,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam  Ở miền Bắc                                                                                               (1969 - 1975)

                                                                                                23/9/1969, Quốc hội Khóa III
                                                                            Bầu Chủ tịch nước Tôn Đức Thắng
   Từ tháng 11/1968 khi Mỹ dừng                                         02/09/1969, Chủ tịch Hồ Chí Minh qua đời
  ném bom, miền Bắc đã thực hiện                                          Tổn thất rất lớn cho cách mạng
       các kế hoạch ngắn hạn để
   khắc phục hậu quả chiến tranh'),
('session-17',4,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam  Ở miền Bắc                                                                                               (1969 - 1975)

                                                   Hầu hết xí nghiệp bị địch
                                                           đánh phá được khôi phục,
                                                                        sửa chữa

                                  Nông nghiệp 1969                                Hệ thống giao thông,
                                            diện tích vượt 1968,                                      cầu phà được khôi phục,
   Từ tháng 11/1968 khi Mỹ dừng                                   chăn nuôi phát triển mạnh                                      xây dựng thêm
  ném bom, miền Bắc đã thực hiện
       các kế hoạch ngắn hạn để
   khắc phục hậu quả chiến tranh'),
('session-17',5,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam  Ở miền Bắc                                                                                               (1969 - 1975)

                           Góp phần tạo ra nhiều trận chiến
                               thắng quyết định như ở Quảng Trị,
                               Tây Nguyên, Đông Nam Bộ

                                                                            Giải phóng Thành cổ Quảng Trị    Miền Bắc tăng cường chi viện
                                                                            28/6 - 16/9/1972   sức người, sức của cho tiền tuyến
           miền Nam'),
('session-17',6,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam  Ở miền Bắc                                                                                               (1969 - 1975)

                                                     Mỹ

                                     4/1972
                                                              Linebacker II

          Từ 4/1972
   Mỹ cho máy bay, tàu chiến
          tái phá hoại miền Bắc'),
('session-17',7,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam                     Hà Nội 12 ngày đêm  Ở miền Bắc                                                                                               (1969 - 1975)
                                      cuối 1972

                                                            Mỹ

                           Bắn rơi 84 máy bay, 34 máy bay B.52,                                                                          27/1/1973
                                                                                                                                              Hiệp định Pari                                  5 máy bay F.111A, bắt 43 giặc lái
                                                                                                                                                  ký kết
          Từ 4/1972
   Mỹ cho máy bay, tàu chiến
          tái phá hoại miền Bắc'),
('session-17',8,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
         Từ đầu 1969                                                                                                           chiến đấu giải phóng miền Nam                                                                                                                                (1969 - 1975)
        “Chiến tranh cục bộ”                                                                              Tổng thống Mỹ
              thất bại                                     “Dùng người Việt Nam                        Richard Nixon
                                       đánh người Việt Nam”

                                           Việt Nam
                                      hóa
                                          chiến tranh

                                 Ra sức củng cố ngụy quyền,
                                                                            “Học thuyết Nixon”                                    xây dựng ngụy quân đông, hiện đại
                                                                          Cùng chia sẻ
                                                                                     Sức mạnh của Mỹ
  Ở miền Nam                                                   Sẵn sàng thương lượng'),
('session-17',9,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam
                                                                                                                                (1969 - 1975)
  Việt Nam hóa chiến tranh

                                22/5/1972 Nixon đến Liên Xô
                                            Mâu
                                                           thuẫn

 Ở miền Nam         21/2/1972 Nixon thăm Trung Quốc'),
('session-17',10,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam
                                                                                                                                (1969 - 1975)

                                                                                        Hội nghị Trung ương lần 18 (1/1970)
                                                                                            và Hội nghị Bộ Chính trị (6/1970)

                                                                 Lấy nông thôn làm hướng tiến công chính
                                                              Tập trung ngăn chặn chương trình “bình định”
                                                            Đẩy mạnh tác chiến quân chủ lực
                                                                        Phát triển mạnh mẽ ba thứ quân
                              Thư chúc Tết Kỷ Dậu 1969
                                   của Chủ tịch Hồ Chí Minh
Ở miền Nam'),
('session-17',11,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam
                                                                                                                                (1969 - 1975)

                                                                                                                                                 27/1/1973
                                                                                                                                  Hiệp định Pari
Ở miền Nam                                                                                                         ký kết                                                  Cuộc tiến công chiến lược
                            Chiến dịch phản công           năm 1972
                         Đường 9 - Nam Lào'),
('session-17',12,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam
                                                                                                                                (1969 - 1975)

                            Hội nghị Ban Chấp hành Trung ương         Mỹ - Ngụy ngang ngược
                                          lần thứ 21 khóa III                     phá hoại Hiệp định

                           Con đường bạo lực cách mạng
                                Tích cực phản công, chuẩn bị tiến lên                                                                                                                                                 27/1/1973
                             hoàn toàn giải phóng miền Nam                                                                                                                                  Hiệp định Pari
                                                                                                                                      ký kết
Ở miền Nam'),
('session-17',13,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
                     Lãnh đạo cách mạng cả nước (1965 - 1975)
                                                                                                                          Khôi phục kinh tế, bảo vệ
                                                                                                                     miền Bắc, đẩy mạnh cuộc
                                                                                                                                         chiến đấu giải phóng miền Nam
                                                                                                                                (1969 - 1975)

                            Hội nghị Ban Chấp hành Trung ương
                                          lần thứ 21 khóa III

                           Con đường bạo lực cách mạng
                                Tích cực phản công, chuẩn bị tiến lên
                             hoàn toàn giải phóng miền Nam

                                                           30/4/1975Ở miền Nam                                                Chiến dịch Hồ Chí Minh toàn thắng'),
('session-17',14,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-18',1,'ĐẢNG LÃNH ĐẠO HAI CUỘC KHÁNG CHIẾN CHỐNG NGOẠI XÂM,
HOÀN THÀNH GIẢI PHÓNG DÂN TỘC, THỐNG NHẤT ĐẤT NƯỚC
                          (1945 - 1975)

            Chương 2'),
('session-18',2,'Xây dựng và bảo vệ chính quyền cách mạng                               Sự lãnh đạo của Đảng đối với
              1945 - 1946                                          cách mạng hai miền Nam - Bắc (1954 - 1965)
     Đường lối kháng chiến toàn quốc                              Lãnh đạo cách mạng cả nước
 và quá trình tổ chức thực hiện (1946 - 1950)                                                                       (1965 - 1975)

         Lãnh đạo xây dựng, bảo vệ                                                            Lãnh đạo xây dựng chủ nghĩa xã hội ở
      chính quyền cách mạng, kháng chiến                                                          miền Bắc và kháng chiến chống đế quốc
        chống thực dân Pháp xâm lược                                                Mỹ xâm lược, giải phóng miền Nam,               Chương 2                                                                                                          thống nhất đất nước (1954 - 1975)                  (1945 - 1954)

 Đẩy mạnh cuộc kháng chiến đến thắng lợi                       Ý nghĩa lịch sử và kinh nghiệm lãnh đạo
               (1951 - 1954)                                         của Đảng thời kỳ 1954 - 1975

  Ý nghĩa lịch sử và bài học kinh nghiệm của Đảng trong
lãnh đạo kháng chiến chống thực dân Pháp và can thiệp Mỹ'),
('session-18',3,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
           Ý nghĩa lịch sử và kinh nghiệm lãnh đạo của Đảng thời kỳ 1954 - 1975

                                                            Ý nghĩa

                                                           Kết thúc 21 năm chống Mỹ,
                                              30 năm chiến tranh cách mạng,
                                                                   117 năm chống đế quốc

                                                         Kết thúc cách mạng dân tộc dân
                                                       chủ nhân dân trên cả nước, mở ra         Ý nghĩa
                                                          kỷ nguyên mới cho dân tộc

                                          Làm thất bại âm mưu và thủ đoạn
                                                         của chủ nghĩa đế quốc tiến công
                                                      vào CNXH và cách mạng thế giới'),
('session-18',4,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
           Ý nghĩa lịch sử và kinh nghiệm lãnh đạo của Đảng thời kỳ 1954 - 1975

                                                            Ý nghĩa
                                               Kết thúc 21 năm chống Mỹ,
                                    30 năm chiến tranh cách mạng,
                                                     117 năm chống đế quốc

  1858 Pháp nổ súng tấn công Đà Nẵng     1954 chiến thắng Điện Biên Phủ           1975 Giải phóng miền Nam
      Cai trị, bóc lột gần 100 năm                                               Thống nhất đất nước'),
('session-18',5,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
           Ý nghĩa lịch sử và kinh nghiệm lãnh đạo của Đảng thời kỳ 1954 - 1975

                                                            Ý nghĩa                                                Kết thúc cách mạng dân tộc dân
                                              chủ nhân dân trên cả nước, mở ra
                                                 kỷ nguyên mới cho dân tộc

           1975 Giải phóng miền Nam
             Thống nhất đất nước                     Kỷ nguyên hòa bình, thống nhất, cùng chung
                                                      nhiệm vụ chiến lược, đi lên chủ nghĩa xã hội'),
('session-18',6,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
           Ý nghĩa lịch sử và kinh nghiệm lãnh đạo của Đảng thời kỳ 1954 - 1975

                                      Làm thất bại âm mưu và thủ đoạn                  Ý nghĩa
                                                    của chủ nghĩa đế quốc tiến công
                                                 vào CNXH và cách mạng thế giới

                       Đánh bại cuộc chiến xâm lược quy mô lớn nhất, dài ngày
                             nhất từ sau Thế chiến II, chia rẽ nước Mỹ sâu sắc nhất,
                           làm phá sản tất cả chiến lược mới mà Mỹ thử nghiệm'),
('session-18',7,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
           Ý nghĩa lịch sử và kinh nghiệm lãnh đạo của Đảng thời kỳ 1954 - 1975

                                                            Ý nghĩa

                                             “Năm tháng sẽ trôi qua, nhưng thắng lợi của nhân dân
                                                                    ta trong sự nghiệp kháng chiến chống Mỹ, cứu nước
                                                     mãi mãi được ghi vào lịch sử dân tộc ta như một trong
                                                     những trang chói lọi nhất, một biểu tượng sáng ngời về   Ý nghĩa                                                             sự toàn thắng của chủ nghĩa anh hùng cách mạng và
                                                                                      trí tuệ con người, và đi vào lịch sử thế giới như một
                                                                    chiến công vĩ đại của thế kỷ XX, một sự kiện có tầm
                                                      quan trọng quốc tế to lớn và có tính thời đại sâu sắc”'),
('session-18',8,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
           Ý nghĩa lịch sử và kinh nghiệm lãnh đạo của Đảng thời kỳ 1954 - 1975

                                                                       Kinh nghiệm
                                                        Giương cao ngọn cờ
                                                           độc lập dân tộc và CNXH
                                                          để tập hợp sức mạnh toàn dân

                                                   Tìm ra phương pháp
      Kinh                          đấu tranh đúng đắn, thích hợp

                                                 Công tác tổ chức chiến đấu     nghiệm
                                                                            giỏi ở cấp bộ đảng và
                                                                           chi ủy quân đội

                                                        Hết sức coi trọng
                                                          công tác xây dựng Đảng'),
('session-18',9,'II. Lãnh đạo xây dựng CNXH ở miền Bắc và kháng chiến chống đế quốc Mỹ xâm lược, giải phóng miền Nam, thống nhất đất nước (1954 - 1975)
           Ý nghĩa lịch sử và kinh nghiệm lãnh đạo của Đảng thời kỳ 1954 - 1975

                                                                       Kinh nghiệm

                         Hạn chế
                         Có thời điểm đánh giá so sánh lực lượng giữa      Kinh                                   ta và địch chưa thực sự đầy đủ và còn những
     nghiệm       biểu hiện nóng vội, chủ quan, duy ý chí trong
                                xây dựng chủ nghĩa xã hội ở miền Bắc'),
('session-18',10,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-19',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-19',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                 khủng hoảng kinh tế - xã hội 1986 - 1996
 Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                                                                   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
                 1975 - 1981                                                                                     hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                               Lãnh đạo công cuộc đổi mới,       Lãnh đạo cả nước xây dựng
                                                                                     đẩy mạnh công nghiệp hóa,        chủ nghĩa xã hội và bảo vệ                                                                                             hiện đại hóa và hội nhập quốc tế               Chương 3          Tổ quốc (1975 - 1986)                                                                                                               (từ năm 1986 đến nay)

Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                             Thành tựu, kinh nghiệm của công cuộc đổi mới
  và các bước đột phá tiếp tục đổi mới kinh tế
             1982 - 1986                                                                 Nguyên nhân và tác hại của tham nhũng'),
('session-19',3,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
           Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981

                                    Bối cảnh lịch sử quốc tế
                                                                 Xuất hiện khủng hoảng,
                                                                             bộc lộ khuyết điểm

                                                  Mâu thuẫn Xô - Trung
                                                                 Trung Quốc xa rời khối
                                                   XHCN

                                            Âm mưu bá quyền

                                                                          Phá thế
                                                                                            địa chính trị'),
('session-19',4,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
           Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981

                                   Bối cảnh lịch sử trong nước

                                      Việt Nam
                       Dân chủ Cộng hòa                                                                              Chưa thi hành
                                                                                           đầy đủ

                                                               Hòa bình, nhưng
                                                                         chưa thống nhất về
                                                                   mặt Nhà nước

                                   Chính phủ Lâm thời
                                 Miền Nam Việt Nam'),
('session-19',5,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
           Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                 Hoàn thành
                                                                                                thống nhất đất nước                                                 Đưa cả nước tiến nhanh,                                                                                                         về mặt nhà nước
                                                                          tiến mạnh lên chủ nghĩa xã hội

                    Miền Bắc tiếp tục đẩy mạnh
                      sự nghiệp xây dựng CNXH và
                     hoàn thiện QHSX XHCN
                                                       Hội nghị Trung ương
                                                          24 khóa III
                                                                          (8/1975)

                     Miền Nam phải đồng thời
                              tiến hành cải tạo XHCN
                        và xây dựng CNXH                                               Hoàn thành thống nhất nước nhà,
                                                             chống âm mưu chia rẻ của
                                                                         các thế lực thù địch'),
('session-19',6,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
           Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                 Hoàn thành
                                                                                                thống nhất đất nước                                       Hội nghị Hiệp thương chính trị                                                                                                         về mặt nhà nước
                                          của hai đoàn đại biểu Bắc Nam
                                                   15 đến 21/11/1975

                              Nước Việt Nam, dân tộc Việt Nam là một, ... tổ chức
                                    tổng tuyển cử trên toàn lãnh thổ Việt Nam bầu ra
                             Quốc hội chung theo nguyên tắc dân chủ, phổ thông,
                                           bình đẳng, trực tiếp và bỏ phiếu kín'),
('session-19',7,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
                Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                        Hoàn thành
                                                                        24/6 - 3/7/1976          thống nhất đất nước
                                                                                                                   về mặt nhà nước

25/4/1976

                                                                                 98.77%

                                                                           23 triệu cử tri bầu ra 492 đại biểu
                                                                                      của Quốc hội thống nhất'),
('session-19',8,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
               Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                       Hoàn thành
                                                                                                        thống nhất đất nước
                                                                                                                 về mặt nhà nước                                                                     Đặt tên nước
       24/6 - 3/7/1976                                                               “Cộng hòa xã hội chủ nghĩa Việt Nam”
                                                                    Thủ đô Hà Nội
                                                                  Đổi tên thành phố Sài Gòn thành Thành phố Hồ Chí Minh

       Kỳ họp thứ nhất
Quốc hội nước Việt Nam thống nhất

                                      Chủ tịch nước     Chủ tịch Ủy ban Thường vụ Quốc hội   Thủ tướng Chính Phủ
                                         Tôn Đức Thắng              Trường Chinh            Phạm Văn Đồng'),
('session-19',9,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
           Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                 Hoàn thành
                                                                                                 thống nhất đất nước
                                                                                                          về mặt nhà nước

             Chủ trương thống nhất các tổ chức chính trị - xã hội với tên gọi mới

                                     Đoàn Thanh niên
                                            Lao động
                                   Hồ Chí Minh

               Mặt trận                                 Tổng Công đoàn            Hội Liên hiệp
             Tổ quốc Việt Nam                                        Việt Nam            Phụ nữ Việt Nam'),
('session-19',10,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-20',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-20',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                 khủng hoảng kinh tế - xã hội 1986 - 1996
 Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                                                                   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
                1975 - 1981                                                                                     hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                               Lãnh đạo công cuộc đổi mới,       Lãnh đạo cả nước xây dựng
                                                                                     đẩy mạnh công nghiệp hóa,        chủ nghĩa xã hội và bảo vệ                                                                                             hiện đại hóa và hội nhập quốc tế               Chương 3          Tổ quốc (1975 - 1986)                                                                                                               (từ năm 1986 đến nay)

Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                             Thành tựu, kinh nghiệm của công cuộc đổi mới
  và các bước đột phá tiếp tục đổi mới kinh tế
             1982 - 1986                                                                 Nguyên nhân và tác hại của tham nhũng'),
('session-20',3,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
              Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                             Đại hội lần thứ IV và                            Đại hội đại biểu toàn quốc lần thứ IV của Đảng                                                                                               quá trình xây dựng
                                  họp từ 14 - 20/12/1976 tại Hà Nội                                                                              CNXH, bảo vệ Tổ quốc

                                                                  Sửa đổi Điều lệ Đảng
                                                              Kế hoạch Nhà nước 5 năm
                                                                           (1976 - 1980)

Tổng bí thư
 Lê Duẩn
                      Đảng Lao động                  Đảng Cộng sản
                                  Việt Nam                              Việt Nam'),
('session-20',4,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
              Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                             Đại hội lần thứ IV và
                                                                                              quá trình xây dựng
                                                                             CNXH, bảo vệ Tổ quốc

   Hòa bình nhưng                                                       Cuộc đối đầu                                                                              Đại hội đại biểu toàn quốc lần thứ IV của Đảngcòn hậu quả chiến tranh,                                                        ý thức hệ còn quyết liệt
                                                                                     họp từ 14 - 20/12/1976 tại Hà Nội     tàn dư CNTD                                                                     trên thế giới

                           Đặc điểm của
                            cách mạng Việt Nam
                                    giai đoạn mới

                         Kinh tế nước ta còn phổ biến
  Đặc trưng                           là sản xuất nhỏ tiến thẳng lên CNXH,                                 Việt Nam có đủ điều kiện đi lên và xây dựng
   lớn nhất                    bỏ qua TBCN                                                                        thành công chủ nghĩa xã hội, nhưng đó là sự nghiệp
                                                                               khó khăn, phức tạp và lâu dài'),
('session-20',5,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
              Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                             Đại hội lần thứ IV và
                                              quá trình xây dựng   Tăng cường CCVS,                                     CNXH, bảo vệ Tổ quốc                                   Cách mạng KHKT là then chốtlàm chủ tập thể XHCN
         Tăng cường                                                                                 Đẩy mạnh CNH HĐH
     nhà nước XHCN                                                                                                                            là trung tâm
                             Chính trị                  Kinh tế    3 cuộc cách mạng                                                                                                Phát triển
    - Quan hệ sản xuất                                                                                                    công nghiệp năng hợp lý
   - Khoa học kỹ thuật                                                                                                                         Kết hợp kinh tế trung ương
   - Tư tưởng, văn hóa                                                                                                                  và địa phương
                        ĐƯỜNG LỐI
                         CÁCH MẠNG

                                                                                                               Giữ gìn quan hệ với
                                                                                                                               Liên Xô và các nước XHCN
       Không ngừng
   nâng cao cảnh giác                                                                                        Bảo vệ mối quan hệ
                          Quốc phòng                   Đối ngoại                                                                                                                                      Việt Nam - Lào - Cam
                                                                                                   Góp phần vào phong tràoBảo vệ Tổ quốc XHCN
                                                                               DTDCND trên thế giới'),
('session-20',6,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
                Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                               Đại hội lần thứ IV và
                                                                                                 quá trình xây dựng
                                                                               CNXH, bảo vệ Tổ quốc

                                          Đại hội đại biểu toàn quốc lần thứ IV của Đảng
                                                 họp từ 14 - 20/12/1976 tại Hà Nội

   Chưa tổng kết 21 năm xây dựng CNXH ở                                               Nóng vội khi dự kiến thời gian từ nền sản xuất
  miền Bắc trong điều kiện đặc biệt nên chưa                                                   nhỏ lên sản xuất lớn XHCN trong 20 năm
     áp dụng đầy đủ các quy luật kinh tế

Chưa phát hiện những khuyết tật của mô hình                                              Nóng vội phát triển công nghiệp nặng với
 chủ nghĩa xã hội đã bộc lộ rõ sau chiến tranh                                                     quy mô lớn, vượt quá khả năng thực té

                                     Bộc lộ một số hạn chế'),
('session-20',7,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
              Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                             Đại hội lần thứ IV và
  Hội nghị                                                                                              quá trình xây dựng
Trung ương 6             Bước đột                     Cho sản xuất bung ra,           CNXH, bảo vệ Tổ quốc
  khóa IV               phá                     xóa trạm kiểm soát, tự do trao đổi
   8/1979
              đầu tiên

                        Khai hoang       Tự làm         Miễn          Hưởng toàn bộ
                                                                    SP làm ra                                                               thuế

                                                                              Có thể đem bán
                                         Nhận diện        HTX đảm                                                                Nộp về NN,           trên thị trường                    Khoán SP đến                                                                  tích, tự cấy,        nhận các khâu                                                                    dư được hưởng                   nhóm NLĐ                                          chăm sóc            có máy móc

   Chỉ thị
100/CT-TW              Sản lượng từ 13.4 triệu tấm/năm 1976 - 1980
  13/1/1981                   tăng lên 17 triệu tấn/năm 1981 - 1985'),
('session-20',8,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
           Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                        Đại hội lần thứ IV và
                                                                                         quá trình xây dựng     Quyết định
                                                                         CNXH, bảo vệ Tổ quốc
       25/CP
       01/1981

                                                                            Trả lương khoán theo sản phẩm
                                                               Áp dụng hình thức thưởng

   Tự chủ sản xuất
   Tự chủ tài chính

                                                                                Quyết định
                        Sản xuất công nghiệp đạt kế hoạch                     26/CP
                                                                                           01/1981                   Công nghiệp địa phương vượt kế hoạch 7.5%'),
('session-20',9,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
           Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                        Đại hội lần thứ IV và
                                                                                         quá trình xây dựng
                                                                         CNXH, bảo vệ Tổ quốc

                                                                                             17/2/1979 Trung Quốc huy động
                                                                        60 vạn quân tấn công
                                                                                                        biên giới phía Bắc nước ta

                                                                                  Sau nhiều Pôn Pốt năm gây hấn,
                                                                                             tấn công lãnh thổ Việt Nam
                                                                                       26/12/1978 Quân tình nguyện Việt Nam
                                                                                         phối hợp và giúp đỡ Campuchia tổng tiến công,
                                                                                                          giải phóng Thủ đô Phnom Pênh vào 7/1/1979'),
('session-20',10,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
               Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc 1975 - 1981
                                                                                              Đại hội lần thứ IV và
                                                                                                quá trình xây dựng
                                                                              CNXH, bảo vệ Tổ quốc

          Kết quả                                            Nguyên nhân

   Chiến thắng hai cuộc chiến tranh biên giới                                 Nền kinh tế thấp kém, thiên tai liên tiếp

Phía Nam cơ bản xóa bỏ chiếm hữu ruộng đất của                             Chiến tranh và chính sách cấm vận, bao vây, cô lập
 đế quốc, phía Bắc từng bước tiến lên sản xuất lớn                                       của Mỹ và các thế lực thù địch                                1975 - 1981

  Lưu thông, phân phối rối ren, giá cả tăng vọt,                                 Khuyết điểm, sai lầm của Đảng, Nhà nước về
      nhập khẩu gấp 4 - 5 lần xuất khẩu                                                lãnh đạo và quản lý kinh tế

   Hiện tượng “xé rào”, “khoán chui” ở miền Bắc
Thí điểm hợp tác xã lúng túng, phức tạp ở miền Nam'),
('session-20',11,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-21',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-21',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                 khủng hoảng kinh tế - xã hội 1986 - 1996
 Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                                                                  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
               1975 - 1981                                                    hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                              Lãnh đạo công cuộc đổi mới,      Lãnh đạo cả nước xây dựng
                                                                                    đẩy mạnh công nghiệp hóa,       chủ nghĩa xã hội và bảo vệ                                                                                            hiện đại hóa và hội nhập quốc tế               Chương 3         Tổ quốc (1975 - 1986)                                                                                                              (từ năm 1986 đến nay)

Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                            Thành tựu, kinh nghiệm của công cuộc đổi mới
 và các bước đột phá tiếp tục đổi mới kinh tế
               1982 - 1986
                                                                Nguyên nhân và tác hại của tham nhũng'),
('session-21',3,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
Đại hội đại biểu toàn quốc lần thứ V của Đảng và các bước đột phá tiếp tục đổi mới kinh tế 1982 - 1986
                                                                                            Đại hội lần thứ V và
                                                                                             quá trình thực hiện
                                                                                                Nghị quyết Đại hội
                               Đại hội đại biểu toàn quốc của Đảng
                                  họp từ 27 - 31/3/1982 tại Hà Nội
                                                                                             Bị bao vây, cấm vận

                                                                                 “Kế hoạch hậu chiến của Mỹ”

   Tổng bí thư
    Lê Duẩn                                                                    Khủng hoảng kinh tế, hàng hóa khan hiếm'),
('session-21',4,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
Đại hội đại biểu toàn quốc lần thứ V của Đảng và các bước đột phá tiếp tục đổi mới kinh tế 1982 - 1986
                                                                                            Đại hội lần thứ V và
                                                                                             quá trình thực hiện
                                                                                                Nghị quyết Đại hội
                           Chặng đường đầu tiên   Khó khăn, phức tạp và lâu dài
                                của thời kỳ quá độ                                                           Nhất là 1981 - 1985 kéo dài đến 1990 đặc biệt quan trọng

Đại hội
                          Chặng đường trước mắt   Giữ ổn định, cải thiện đời sống nhân dân
  V

                                    Điều kiện để đảm bảo
                                 xây dựng thành công Tổ quốc  Giữ vững an ninh quốc phòng
                                            Việt Nam XHCN'),
('session-21',5,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
Đại hội đại biểu toàn quốc lần thứ V của Đảng và các bước đột phá tiếp tục đổi mới kinh tế 1982 - 1986

                                              Đại hội lần thứ V và
           Cơ bản giữ nguyên ĐH IV                                                         Quan hệ với Liên Xô là                                               quá trình thực hiện
                                                                                                   hòn đá tảng                                                 Nghị quyết Đại hội
         Thực hiện CCVS, không thừa                                            Đối                                                                                    Quan hệ Việt Nam - Lào -                             Chính trị          nhận KT nhiều thành phần                                               ngoại     Cam có ý nghĩa sống còn

                                                                                            Kêu gọi ASEAN đối thoại            Tăng cường tính giai cấp
                    công nhân
                                        Đường lối
                                               cách mạng

    Mặt trận hàng đầu.                                                                                                 Tiếp tục một số
                             Tập trung phát triển                                                               Phục vụ    Khai thác tiềm năng,                               Kinh tế                                                                               ngành công nghiệp
                                 nông nghiệp                                                                nông nghiệp               lợi thế                                                                                nặng quan trọng

                                              Kết hợp công - nông hợp lý
                                                   Chương trình ba mục tiêu:
                                       hàng lương thực, thực phẩm; hàng tiêu dùng; hàng xuất khẩu'),
('session-21',6,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
   Đại hội đại biểu toàn quốc lần thứ V của Đảng và các bước đột phá tiếp tục đổi mới kinh tế 1982 - 1986

                                                                                               Đại hội lần thứ V và
                                                                                                quá trình thực hiện                                         Hội nghị TW 8 Khóa V
                                                                                                   Nghị quyết Đại hội                                                     6/1985

                                                     (Bước đột phá thứ hai)

                                               Chỉ quy định giá: xăng dầu, xi măng,
                                   Giá                                                                                                                                                      ...
                                             Giá khác bằng hoặc cao hơn chi phí sản xuất, giá thóc làm chuẩn

                                           Bù giá vào lương
                                                                             Hạch toán, kinh doanh                                                              Lương
                                                  Lương đủ sống,                                                                                         xã hội chủ nghĩa
                                                     không ước lệ

                                                14/9/1985 đổi tiềnCơ chế kế hoạch hóa tập trung
                                     Tiền   quan liêu hành chính                                          10 đồng hiện hành đổi 1 đồng mới'),
('session-21',7,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
Đại hội đại biểu toàn quốc lần thứ V của Đảng và các bước đột phá tiếp tục đổi mới kinh tế 1982 - 1986

                                                                                           Đại hội lần thứ V và
                                    Hội nghị Bộ Chính trị                             quá trình thực hiện
                                                                                                Nghị quyết Đại hội                                   Khóa V (8/1986)

                                            Cải tạo xã hội chủ nghĩa

                                                                           Phát triển lực lượng sản xuất     Lộ trình

       Phù hợp từng thời kỳ,
            từng lĩnh vực

                                                                    Cần thiết có kinh tế
                                                                                       nhiều thành phần
                               Công cụ         Lâu dài, dần dần'),
('session-21',8,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
Đại hội đại biểu toàn quốc lần thứ V của Đảng và các bước đột phá tiếp tục đổi mới kinh tế 1982 - 1986

                                                                                           Đại hội lần thứ V và                                  Hội nghị Bộ Chính trị                                                                                             quá trình thực hiện
                                 Khóa V (8/1986)                                    Nghị quyết Đại hội

     Quy luật kinh tế XHCN            Cơ chế quản lý kinh tế
      Quy luật hàng - tiền                                                                            Trao quyền tự chủ sản xuất kinh doanh

                                                                    Phân biệt chức năng quản lý hành chính
                                                                          nhà nước với chức năng kinh tế'),
('session-21',9,'I. Lãnh đạo cả nước xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc (1975 - 1986)
Đại hội đại biểu toàn quốc lần thứ V của Đảng và các bước đột phá tiếp tục đổi mới kinh tế 1982 - 1986

                                                                                           Đại hội lần thứ V và
                                                                                             quá trình thực hiện
                                                                                                Nghị quyết Đại hội

        10/7/1986                          14/7/1986 Ban Chấp hành Trung ương họp bất thường
                                               bầu đồng chí Trường Chinh giữ chức Tổng Bí thưTổng Bí thư Lê Duẩn qua đời'),
('session-21',10,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-22',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-22',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                         khủng hoảng kinh tế - xã hội 1986 - 1996
Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                                                                Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
              1975 - 1981                                                    hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                            Lãnh đạo công cuộc đổi mới,     Lãnh đạo cả nước xây dựng
                                                                                   đẩy mạnh công nghiệp hóa,      chủ nghĩa xã hội và bảo vệ                                                                                          hiện đại hóa và hội nhập quốc tế               Chương 3        Tổ quốc (1975 - 1986)                                                                                                           (từ năm 1986 đến nay)

 Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                           Thành tựu, kinh nghiệm của công cuộc đổi mới
  và các bước đột phá tiếp tục đổi mới kinh tế
              1982 - 1986
                                                               Nguyên nhân và tác hại của tham nhũng'),
('session-22',3,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
           Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                               Đại hội lần thứ VI và
                                                                                                              thực hiện đường lối
                                                                                                                      đổi mới toàn diện

                                         Xu thế đối đầu                                Bối cảnh Đại hội VI
                                                chuyển sang đối thoại

        Cách mạng khoa học kỹ thuật
                                                          Khan hiếm lương thực,
                                                                       thực phẩm & hàng tiêu dùng
                                                    Lạm phát 774% (1986)
                                                                  Vi phạm pháp luật, vượt biên

Liên Xô và các nước xã hội chủ nghĩa tiến hành cải tổ'),
('session-22',4,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
          Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                              Đại hội lần thứ VI và
                                                                                                             thực hiện đường lối
                                                                                                                     đổi mới toàn diện

   Bầu cử         Mục đích
                                                                                  Nguyên nhân của sai lầm
                     Nhìn thẳng vào sự thật,
                     đánh giá đúng sự thật,
                              nói rõ sự thật                                                                        Đều bắt nguồn từ hoạt
                       Chỉ rõ sai lầm, khuyết điểm                                                                                động tư tưởng, tổ chức và
                          của Đảng 1975 - 1986                                                                                     công tác cán bộ của Đảng
Đ/c Nguyễn Văn Linh
                         Đổi mới đưa đất nước    Tổng Bí thư                            thoát khỏi khủng hoảng
                                 Hà Nội
                                            15 - 18/12/1986'),
('session-22',5,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                                                                                           thực hiện đường lối
                                                                                                                   đổi mới toàn diện
                                       Luôn xuất phát từ  Trong toàn bộ hoạt
                                               thực tế, tôn trọng  động, phải quán triệt
                                         quy luật khách quan    "lấy dân làm gốc"

                               Chăm lo xây dựng Đảng
Kết hợp sức mạnh dân tộc                                           Hà Nội                                      ngang tầm với nhiệm vụ
  với sức mạnh thời đại                                                 lãnh đạo                15 - 18/12/1986   trong điều kiện mới'),
('session-22',6,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                                                                                           thực hiện đường lối
                                                                                                                   đổi mới toàn diện

                                                                                 Đối mới kinh tế
                           Thực hiện
    Kinh tế quốc doanh             nhất quán nhiều      Kinh tế tập thể
                        thành phần kinh tế

  Cơ chế tập
  trung, quan
    liêu, hành                                                      Hà Nội chính, bao cấp                                                                            15 - 18/12/1986
                                             Kết hợp kế hoạch với thị trường'),
('session-22',7,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
           Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                               Đại hội lần thứ VI và
                                                                                                             thực hiện đường lối
                                                                                                                      đổi mới toàn diện

                                                                                   Đối mới kinh tế
                 Sản xuất đủ                                               Cải tạo XHCN
                       tiêu dùng và                                             thường xuyên với
                     có tích lũy                                                bước đi thích hợp

  Lương thực -
     thực phẩm
                                                                                        Giải quyết cho                  Bước đầu
                                                                                được rối ren về                         Nhiệm vụ,Hàng tiêu dùng      tạo ra cơ cấu                                       Hà Nội                                                                           phân phối và                       mục tiêu                   kinh tế hợp lý                                                                              15 - 18/12/1986                                                                                        lưu thông                             tổng quát
 Hàng xuất khẩu'),
('session-22',8,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                                                                                           thực hiện đường lối
                                                                                                                   đổi mới toàn diện

                                 Sử dụng                                               Đối mới kinh tế
                               đúng đắn và                                                        Phát huy
          Điều chỉnh cơ               cải tạo các                                                        động lực
            cấu đầu tư            TPKT                                                       khoa học –
            xây dựng                                                          kỹ thuật

                                                    Mở rộng và   Bố trí lại                                                                        nâng cao
    cơ cấu                5 phương                             Hà Nội                                                                                     hiệu quả kinh
                      hướng lớn                                    tế đối ngoại           15 - 18/12/1986   sản xuất
                        phát triển
                          kinh tế'),
('session-22',9,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                                                                                           thực hiện đường lối
                                                                                                                   đổi mới toàn diện

                                                                                Chính sách xã hội      Kế hoạch                                   Công bằng                 Chính sách
    hóa dân số &                                     xã hội, an
        việc làm           xã hội                toàn xã hội

            Giáo dục,                                             Chính sách           văn hóa,                                                 bảo trợ              sức khỏe                                                xã hội                Hà Nội           nhân dân                                                                            15 - 18/12/1986                Vấn đề
                   xã hội'),
('session-22',10,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                                                                                           thực hiện đường lối                Tăng cường tình hữu nghị và                                                                                                                   đổi mới toàn diện               hợp tác toàn diện với Liên Xô và
                         các nước XHCN
                                                                        Đường lối đối ngoại

                 Bình thường hóa quan hệ với
                       Trung Quốc

                 Giữ vững hòa bình ở Đông Dương,
                     tăng cường quan hệ ba nước

                                                                      Đảm bảo lợi ích quốc gia,
                                                                                                 chống bao vây, cấm vận, phá hoại

                                                                                                     Vì hòa bình, độc lập dân tộc,
                                                                                        dân chủ và chủ nghĩa xã hội trên thế giới                  Phấn đầu bảo vệ hòa bình ở
                 Đông Nam Á và trên thế giới'),
('session-22',11,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                                                                                           thực hiện đường lối
                                                                                                                   đổi mới toàn diện

                                                                        Đối mới sự lãnh đạo của Đảng

                                                        Tăng cường sự đoàn kết,              Phải đổi mới tư duy,
                                                               nhất trí trong Đảng             trước hết là tư duy kinh tế

            Đổi mới công tác cán bộ và                      "Dân biết, dân bàn, dân làm,
               phong cách làm việc                                dân kiểm tra"

          Giữ vững nguyên tắc tổ chức &                        Tăng cường hiệu lực quản lý của
                   sinh hoạt Đảng                           Nhà nước để huy động quần chúng'),
('session-22',12,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                    Hội nghị                                          thực hiện đường lối
                                                                                                                   đổi mới toàn diện                                  Trung ương
                                     2 (4/1987)                              Thực hiện đường lối

                                                        Giải quyết rối ren
                                              phân phối, lưu thông

         Mở rộng lưu thông               4 giảm                                                  Quốc doanh         Hạch toán kinh                hàng hóa
                                   Giảm bội chi ngân sách      XHCN             doanh XHCN

                                   Giảm nhịp độ tăng giá

                                      Giảm lạm phát             Thực hiện cơ chế                                                                           14/11/1987
          một giá và thống nhất                                                                Trao quyền tự chủ                                   Giảm khó khăn đời sống             chế độ lương cả nước                                        cho doanh nghiệp'),
('session-22',13,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                                                                                           thực hiện đường lối
                                                                                                                   đổi mới toàn diện

                                                                                Thực hiện đường lối

                                                              Bảo đảm có thu              "Khoán  5/4/1988                       Khoán đến NLĐ                                                            15 năm                                                                 nhập từ 40% sảnBộ Chính trị         10"         Hộ nông dân                                                                        lương khoán trở lên

                 Cơ chế
Công nghiệp       tập trung,
                 bao cấp'),
('session-22',14,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội lần thứ VI và
                                                                                                           thực hiện đường lối
                                                                                                                   đổi mới toàn diện
                                                                        Kết quả
                45 vạn
                  tấn gạo
                                                     1991                        1989Cuối năm 1988
                                                   67.1%
                           Đủ ăn,
                                       có dự trữ và             Lưu thông thuận lợi
                                     xuất khẩu              Bước đầu hình thành cơ
                                                                          chế thị trường dưới sự
                                                              quản lý của Nhà nước'),
('session-22',15,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                          Đại hội VII và Cương lĩnh
                                                                                              xây dựng đất nước trong
                                                                                                                  thời kỳ quá độ lên CNXH
           Nhận định
                                                   Bầu cử   Nền kinh tế bước đầu chuyển biến tích cực
            Hình thành nền
      kinh tế hàng hóa nhiều thành phần

         Biểu quyết thông qua

      Cương lĩnh xây dựng đất nước
                                                              Tổng Bí thư   trong thời kỳ quá độ lên chủ nghĩa xã hội                 Hà Nội
                                                    24 - 27/6/1991                                                    Đỗ Mười Chiến lược ổn định và phát triển kinh tế xã hội
             đến năm 2000'),
('session-22',16,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
            Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                             Đại hội VII và Cương lĩnh
                                           Nắm vững ngọn cờ độc                                                                                                  xây dựng đất nước trong                                       1                                                                      lập dân tộc và CNXH                                                                                                                       thời kỳ quá độ lên CNXH

                                                                    Sự nghiệp cách mạng là                                   2                                                                          của dân, do dân, vì dân
Cương lĩnh xây dựng        5
                                                                       Tăng cường,   đất nước trong                           bài học                                     3                                                                          củng cố 4 đoàn kết TKQĐ lên CNXH                           lớn (Cương lĩnh 1991)

                                                                             Kết hợp sức mạnh dân tộc                                4                                                                                         với sức mạnh thời đại

                                                                    Sự lãnh đạo đúng đắn của                                5    Đảng đảm bảo thắng lợi'),
('session-22',17,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
            Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                             Đại hội VII và Cương lĩnh
                                                                                                  xây dựng đất nước trong                                     Đặc trưng cơ bản của chủ nghĩa xã hội mà
                                                                                                                       thời kỳ quá độ lên CNXH                                                 nước ta xây dựng

                               Chính trị          Do nhân dân lao động làm chủ

                                      Có nền kinh tế phát triển cao dựa trên LLSX hiện
Cương lĩnh xây dựng    Kinh tế                                                         đại và chế độ công hữu về TLSX chủ yếu
   đất nước trong
                                       Có nền văn hóa tiên tiến, đậm đà bản sắc dân tộc                            Văn hóa TKQĐ lên CNXH
 (Cương lĩnh 1991)                    Con người được giải phóng khỏi áp bức, bóc lột, làm theo năng
                             Xã hội                lực, hưởng theo lao động, có cuộc sống ấm no, tự do,
                                                            hạnh phúc, có điều kiện phát triển toàn diện
                            Đoàn kết    Các dân tộc trong nước bình đẳng, đoàn kết và giúp
                               dân tộc                đỡ lần nhau cùng tiến bộ
                           Quan hệ    Có quan hệ hữu nghị và hợp tác với nhân dân tất cả
                                   quốc tế                      các nước trên giới'),
('session-22',18,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                          Đại hội VII và Cương lĩnh
                                       Xây dựng                                       xây dựng đất nước trong
                                                                                                                  thời kỳ quá độ lên CNXH                                     Nhà nước                                                          CNH gắn liền với
                                                                                             phát triển nông                               XHCN
                                                                                                 nghiệp toàn diện
                                                                                                                  là nhiệm vụ
                                                                                                 trung tâm

                                                                                                             Thiết lập                            7 Phương hướng                                                                 QHSX XHCN                 Thực hiện xây                                                                                                     từ thấp đến cao                dựng và bảo vệ             phát triển                                                                                         đa dạng về
                  Tổ quốc                                                                                                 hình thức                         (Cương lĩnh 1991)                                                                                                         sở hữu

                            Thực hiện                                           Phát triển nên
                                                             KTHH nhiều                               chính sách                                                               Tiến hành                 thành phần,
                                  đại đoàn                                          vận động theo                                                              cách mạng                                                                                                     cơ chế TT, có                                   kết dân tộc                 trên lĩnh vực                                                                                              sự QL của NN
                                                               tư tưởng,
                                                      văn hóa'),
('session-22',19,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
           Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                            Đại hội VII và Cương lĩnh
                                                                                                 xây dựng đất nước trong
                                                                                                                     thời kỳ quá độ lên CNXH

                                 2000 thoát khỏi khủng hoảng
                               GDP gấp hai lần 1990

  Chiến lược ổn định và             Mục tiêu và động lực chính
phát triển kinh tế - xã hội               vì con người, do con người, giải phóng sức sản
                                             xuất, khởi dậy mọi tiềm năng của mỗi cá    đến năm 2000
                                             nhân, tập thể và toàn dân tộc

                                   Mọi người được tự do kinh doanh theo
                                      pháp luật, được bảo hộ quyền sở hữu và
                                                  thu nhập hợp pháp'),
('session-22',20,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                          Đại hội VII và Cương lĩnh
                                                                                              xây dựng đất nước trong
                                                                                                                  thời kỳ quá độ lên CNXH
                                                              Thực hiện đường lối
                                                       Ba mục tiêu chủ yếu

                                                                Xây dựng nông thôn mới có kinh tế phát triển, đời
                                                                          sống văn hóa phong phú, lành mạnh, CSVC và xã
                                                                                    hội đáp ứng được nhu cầu cơ bản của nông dân
                            Hội nghị
              Coi nông nghiệp là    Trung ương                                                               Phát huy dân chủ,            mặt trận hàng đầu                                                đảm bảo công bằng xã hội                             5 (6/1993)

                                                                  Tăng cường đoàn kết và ổn định chính
                                                                                                                    trị, giữ vững trật tụ xã hội, củng cố
                                                                            vững chắc ANQP'),
('session-22',21,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
          Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                           Đại hội VII và Cương lĩnh
                                                                                               xây dựng đất nước trong
                                                                                                                    thời kỳ quá độ lên CNXH
                                                              Thực hiện đường lối

                                                   Mục tiêu lâu dài là cải biến nước ta
                                  Phát triển công nghiệp                                                                 thành nước công nghiệp hiện đại ...
  Hội nghị
Trung ương 7
                                                                Tăng năng suất lao động,                                  Phát triển công nghệ  (7/1994)                                                      đảm bảo gắn CNH với HĐH

                                                       Có bản lĩnh chính trị, trình độ học                            Xây dựng giai cấp công nhân
                                                                        vấn, tay nghề cao, tiếp thu và sáng                                                  giai đoạn mới
                                                                               tạo công nghệ mới ...'),
('session-22',22,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                          Đại hội VII và Cương lĩnh
                                                                                              xây dựng đất nước trong
                                                                                                                  thời kỳ quá độ lên CNXH
                              1991 - 1995                         Kết quả

                                                                       1995: 12.7%          8.2%

                                                                          1991: 67.1%
                                       Lạm phát giảm
                                        5.5 - 6.5%'),
('session-22',23,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                          Đại hội VII và Cương lĩnh
                                                                                              xây dựng đất nước trong
                                                                                                                  thời kỳ quá độ lên CNXH
                                                                        Kết quả
                                                                             11/1991 bình thường hóa
                                                                quan hệ với Trung Quốc

                                                                              11/7/1995 bình thường hóa
                                                                    quan hệ với Hoa Kỳ
 Hội nghị Paris về vấn đề Campuchia

                                                                       28/7/1995 gia nhập ASEAN'),
('session-22',24,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                          Đại hội VII và Cương lĩnh
                                                                                              xây dựng đất nước trong
                                                                                                                  thời kỳ quá độ lên CNXH
              Hội nghị đại biểu giữa nhiệm kỳ (1/1994)
                   4 nguy cơ, thách thức

                 Chệch   Tụt hậu                    Tham                                                 "Diễn biến                 hướng  xa hơn về                             nhũng và                                             hòa bình"                  xã hội   kinh tế                              tệ quan liêu                chủ nghĩa'),
('session-22',25,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
         Đổi mới toàn diện, đưa đất nước ra khỏi khủng hoảng kinh tế - xã hội 1986 - 1996
                                                                                          Đại hội VII và Cương lĩnh
                                                                                              xây dựng đất nước trong
                                                                                                                  thời kỳ quá độ lên CNXH             Hội nghị đại biểu giữa nhiệm kỳ (1/1994)

                                                             Do Đảng Cộng sản Việt Nam
                                                                                             lãnh đạo

                                   Lần đầu tiên khẳng    Không                                          định chủ trương
   thừa nhận                        xây dựng Nhà nước
                                     pháp quyền của dân,   Nhà nước                                                    Quyền lực nhà nước là thống nhất,                                        do dân, vì dân  pháp quyền                                                                      có sự phân công, phối hợp'),
('session-22',26,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-23',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-23',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                  khủng hoảng kinh tế - xã hội 1986 - 1996
Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
              1975 - 1981                                                     hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                            Lãnh đạo công cuộc đổi mới,     Lãnh đạo cả nước xây dựng
                                                                                   đẩy mạnh công nghiệp hóa,      chủ nghĩa xã hội và bảo vệ                                                                                          hiện đại hóa và hội nhập quốc tế               Chương 3        Tổ quốc (1975 - 1986)                                                                                                           (từ năm 1986 đến nay)

 Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                           Thành tựu, kinh nghiệm của công cuộc đổi mới
  và các bước đột phá tiếp tục đổi mới kinh tế
              1982 - 1986
                                                               Nguyên nhân và tác hại của tham nhũng'),
('session-23',3,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

              Đại hội VIII                             Đại hội IX                             Đại hội X
             28/6 - 1/7/1996                           19 - 22/4/2001                           18 - 25/4/2006

              Đại hội XI                             Đại hội XII                           Đại hội XIII
               12 - 19/1/2011                       20 - 28/1/2016                              25/1 - 1/2/2021'),
('session-23',4,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                               Đại hội lần thứ VIII
                                                                                                                  và bước đầu thực hiện
                                                                                                                     công nghiệp hóa - hiện đại hóa

                                                                                          Bối cảnh Đại hội VIII

Cách mạng khoa học công nghệ                                                    Những thắng lợi bước đầu sau 10 năm
                                                                                                           đổi mới, phá thế bao vây, cô lậpphát triển với trình độ cao hơn

                                                                            Nước ta vẫn là nước nghèo,  Chủ nghĩa xã hội hiện thực
                                                                     kém phát triển, xã hội còn nhiều     lâm vào thoái trào
                                                                                                       tiêu cực và vấn đề cần giải quyết
                                  Hà Nội
                                          28/6 - 1/7/1996'),
('session-23',5,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                              Đại hội lần thứ VIII
                                                                                                                 và bước đầu thực hiện
                                                                                                                    công nghiệp hóa - hiện đại hóa

                                                                                    Nội dung Đại hội VIII

       1.198 đại biểu

Bổ sung đặc trưng bản chất:
  "Dân giàu, nước mạnh,
xã hội công bằng, văn minh"                                                         Đồng chí Đỗ Mười
                                                                                                 được bầu tiếp tục
                                                                                        làm Tổng Bí thư
                                 Hà Nội
                                         28/6 - 1/7/1996'),
('session-23',6,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                            Đại hội lần thứ VIII
                     Giữ vững                                                                               và bước đầu thực hiện
                                                                                                                 công nghiệp hóa - hiện đại hóa                mục tiêu độc lập
                   dân tộc và chủ                                                                                  Nội dung Đại hội VIII
                      nghĩa xã hội                                          Kết hợp                                                 Đẩy mạnh công nghiệp hóa,  Coi xây dựng
                                         chặt chẽ đổi mới           hiện đại hóa cả nước Đảng là nhiệm
                                        kinh tế và đổi             trong thời kỳ mới  vụ then chốt
                                    mới chính trị

                  Bài học chủ yếu
                                   Tăng trưởng Mở rộng hợp tác               qua 10 năm đổi mới
  quốc tế, kết hợp                         kinh tế gắn liền                                              Những tiền đề chuẩn bị
 sức mạnh dân tộc                           với công bằng                                                        cho công nghiệp hóa    và thời đại                            xã hội                             Hà Nội              Mở rộng và                                                           cơ bản đã hoàn thành                                                                       28/6 - 1/7/1996                    tăng cường khối
                        đại đoàn kết
                       toàn dân'),
('session-23',7,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                            Đại hội lần thứ VIII
                                                                                                               và bước đầu thực hiện
                                                                                                                 công nghiệp hóa - hiện đại hóa

                                                    KHCN là động lực,                             Giữ vững độc lập,                                                                                  Nội dung Đại hội VIII
                                                                                             kết hợp công nghệ                                 tự chủ và mở rộng
                                                                                   truyền thống với hiện                              hợp tác. Dựa vào
                                                                                                   đại, đi nhanh ở những                                  nội lực là chính và
                                                                          khâu quyết định                               tranh thủ ngoại lực
     Là sự nghiệp của                             QUAN ĐIỂM                             Lấy hiệu quả kinh tế -
    toàn dân, mọi thành                           CÔNG NGHIỆP HÓA -                         xã hội làm tiêu chuẩn
    phần kinh tế, kinh tế                                                                                                                cơ bản để xác định                                HIỆN ĐẠI HÓA      nhà nước đóng                                                                                              phương án, đầu tư và
                           TRONG THỜI KỲ MỚI        vai trò chủ đạo                                                                                                           công nghệ
                             Lấy phát huy                              Kết hợp
                          nguồn lực con người                                                                kinh tế với                                    là yếu tố cơ bản cho
                                                             quốc phòng -                             phát triển nhanh và
                                  bền vững                                                         an ninh'),
('session-23',8,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                               Đại hội lần thứ VIII
                                                                                                                  và bước đầu thực hiện
                                                                                                                     công nghiệp hóa - hiện đại hóa

                                                                                     Nội dung Đại hội VIII

   Đảng phải tiếp tục tự đổi mới,                                                     Nâng cao phẩm chất, năng lực cán bộ,
   chỉnh đốn, nâng cao hơn nữa sức                                                           đảng viên; Củng cố tổ chức Đảng,
    chiến đấu và năng lực lãnh đạo                                                                   thực hiện nghiêm tập trung dân chủ

  Cần phải giữ vững và tăng cường                                                                    Tiếp tục đổi mới phương thức lãnh đạo
bản chất giai cấp công nhân của Đảng                                                             của Đảng và đổi mới công tác kiểm
                                                                                                                                tra, kỷ luật của Đảng

                                Xây dựng Đảng ngang tầm đòi hỏi của thời kỳ đẩy mạnh
                               công nghiệp hóa - hiện đại hóa là vấn đề có ý nghĩa quyết định hàng đầu'),
('session-23',9,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                            Đại hội lần thứ VIII
                                                                                                               và bước đầu thực hiện
                                                                                                                 công nghiệp hóa - hiện đại hóa

                                                                                           Thực hiện đường lối Đại hội
                                                                                                               VIII

                                            Thu hút đầu tư, chuyển giao công
                                                              nghệ

 Nguồn lực
                                              Xuất khẩu, hợp tác kinh tế con người'),
('session-23',10,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                            Đại hội lần thứ VIII
                                                                                                               và bước đầu thực hiện
                                                                                                                 công nghiệp hóa - hiện đại hóa

                                                                                           Thực hiện đường lối Đại hội
                                                                                                               VIII
                                               Thực hiện cơ chế Cần kiệm để CNH, khắc                                                                    Tích cực giải quyết việc                                                           thị trường, nhưng có sự
phục xu hướng chạy theo                                                                      làm, xóa đói                                             quản lý và điều tiết    "xã hội tiêu dùng"                                                                                giảm nghèo                                                  định hướng XHCN

                                                                  Thúc đẩy chuyển dịch                       Hướng mạnh về                                                                               cơ cấu kinh tế, công                        xuất khẩu, không coi nhẹ                                                                          nghiệp hóa, hiện đại hóa                                thị trường trong nước                                                                 nông nghiệp, nông thôn'),
('session-23',11,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                            Đại hội lần thứ VIII
                                                                                                               và bước đầu thực hiện
                                                                                                                 công nghiệp hóa - hiện đại hóa

                                                                                           Thực hiện đường lối Đại hội
                                                                                                               VIII

                                  GDP tăng trưởng bình quân 7%/năm

                                              Nông nghiệp phát triển liên tục

                                             Giá trị sản xuất công nghiệp tăng bình quân
                                                          13.5%/năm
                       Việt Nam vượt qua
              khủng hoàng tài chính - tiền tệ
                   Châu Á 1997'),
('session-23',12,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                            Đại hội lần thứ VIII
                                                                                                               và bước đầu thực hiện
                                                                                                                 công nghiệp hóa - hiện đại hóa

                                                                                           Thực hiện đường lối Đại hội
                                                                                                               VIII
                                                                  Ban hành Chỉ thị số 30-CT/TW
                                                     Hội nghị Bộ Chính trị                                                                      ngày 18/2/1998 về xây dựng và thực hiện                                                               2/1998
                                                                 Quy chế dân chủ cơ sở

                                                                Ban hành Nghị quyết số 10-NQ/TW
                                                    Hội nghị Trung ương 6                                                                      ngày 2/2/1999 về một số vấn đề cơ bản và                                                                       (lần 2) 2/1999
                                                                             cấp bách trong công tác xây dựng Đảng

    Hội nghị Trung ương 4 khóa VIII (12/1997)
   Bầu đồng chí Lê Khả Phiêu làm Tổng Bí thư'),
('session-23',13,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                              Đại hội lần thứ VIII
                                                                                                                 và bước đầu thực hiện
                                                                                                                   công nghiệp hóa - hiện đại hóa

                                                                                             Thực hiện đường lối Đại hội
                                       Chiến lược khoa học công                                         VIII
      Chiến lược phát triển
                                              nghệ: kế thừa tinh hoa                                                                                            Hội nghị Trung ương 2      giáo dục đào tạo thời kỳ
                                    nhân loại, nâng cao năng                            khóa VIII (12/1996)
       CNH HĐH
                                                       lực nội sinh
                                                                                Tạo nguồn nhân lực cho
                                                                                     công nghiệp hóa - hiện đại hóa

                               Xây dựng nền văn hóa
Giữ gìn và phát huy              Tiếp thu có                                             tiên tiến, đậm đà bản                                Nghị quyết 03   giá trị bản sắc            chọn lọc tinh hoa                                                              HNTW 16/7/1998                                              sắc dân tộc  văn hóa dân tộc           văn hóa thế giới'),
('session-23',14,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-24',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-24',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                  khủng hoảng kinh tế - xã hội 1986 - 1996
Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
              1975 - 1981                                                     hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                            Lãnh đạo công cuộc đổi mới,     Lãnh đạo cả nước xây dựng
                                                                                   đẩy mạnh công nghiệp hóa,      chủ nghĩa xã hội và bảo vệ                                                                                          hiện đại hóa và hội nhập quốc tế               Chương 3        Tổ quốc (1975 - 1986)                                                                                                           (từ năm 1986 đến nay)

 Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                           Thành tựu, kinh nghiệm của công cuộc đổi mới
   và các bước đột phá tiếp tục đổi mới kinh tế
               1982 - 1986
                                                               Nguyên nhân và tác hại của tham nhũng'),
('session-24',3,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                              Đại hội lần thứ IX (2001)
                                                                                                                                                             tiếp tục thực hiện
                                                                                                                      công nghiệp hóa - hiện đại hóa

                                                                                            Bối cảnh Đại hội IX

 Cách mạng khoa học công nghệ                                                  Khu vực Châu Á - Thái Bình Dương có
                                                                                                 nhiều tiềm năng phát triển những cũng  kinh tế tri thức, toàn cầu hóa
                                                                                                       có những nhân tố gây mất ổn định        diễn ra mạnh mẽ

  Sau sự kiện 11/9/2001 ở Mỹ,                                                        Các chỉ tiêu Đại hội VIII không đạt,
                                                                                                    các nguy cơ Hội nghị giữa nhiệm kỳmột số nước lớn đã lợi dụng chống
                                                                                     1994 vẫn là thách thức lớnkhủng bố để can thiệp nhiều nước
                                  Hà Nội
                                           19 - 22/4/2001'),
('session-24',4,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                             Đại hội lần thứ IX (2001)
                                                                                                                                                           tiếp tục thực hiện
                                                                                                                     công nghiệp hóa - hiện đại hóa

                                                                                      Nội dung Đại hội IX
  Tổng kết thế kỷ XX đối với thế giới
          và Việt Nam

Thông qua nhiều văn kiện quan trọng:
 Chiến lược phát triển kinh tế xã hội
         2001 - 2010
   Xác định rõ nội dung tư tưởng
        Hồ Chí Minh
                                                                              Đồng chí Nông Đức Mạnh
                                                                                             được bầu làm Tổng Bí thư
                                  Hà Nội
                                          19 - 22/4/2001'),
('session-24',5,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                             Đại hội lần thứ IX (2001)
                                                                                                                                                            tiếp tục thực hiện
                                                                                                                     công nghiệp hóa - hiện đại hóa

                                                                                      Nội dung Đại hội IX
                                                           Mục tiêuĐại hội IX thông qua
                                         GDP năm 2010 tăng gấp đôi so với năm 2000Chiến lược phát triển
                                               Đưa nước ta thoát khỏi tình trạng kém phát triểnkinh tế xã hội 10 năm
                                                     Tạo nền tảng đến năm 2020 nước ta cơ bản trở thành   2001 - 2010
                                                               nước công nghiệp theo hướng hiện đại

                          Kết quả
     GDP năm 2000 đã tăng gấp đôi so với năm 1990

                                                                    “Chiến lược ổn định và phát triển kinh tế xã hội đến năm 2000"
                                                                              được thông qua ở Đại hội VII (1991)'),
('session-24',6,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ IX (2001)
                                                                                                                                                       tiếp tục thực hiện
                                                                                                                  công nghiệp hóa - hiện đại hóa
                                                  Nhiều hình thức sở hữu,
                                                     nhiều thành phần kinh tế,                         Nội dung Đại hội IX
                                                     nhiều hình thức phân phối

                                                 Thực hiện nhất quán và lâu dài nền            Xây dựng nền văn hóa Việt NamCon đường phát triển quá độ lên
                                                        kinh tế thị trường định hướng                 làm nền tảng tinh thần của chủ nghĩa xã hội của nước ta là                                         XHCN; coi đây là mô hình kinh tế                                                                                      xã hội, vừa là mục tiêu, động lực bỏ qua chế độ tư bản chủ nghĩa                                                      tổng quát của nước ta trong TKQĐ                                                                                              thúc đẩy phát triển kinh tế - xã hội

                    Quan hệ các giai cấp, các tầng lớp                                                                                    Việt Nam sẵn sàng là bạn,
                      xã hội là quan hệ hợp tác và đấu tranh                                                                                           là đối tác tin cậy của các nước
                          trong nội bộ nhân dân, đoàn kết và
                                                                            trong cộng đồng quốc tế, phấn đấu                         hợp tác lâu dài trong sự nghiệp
                                                                                           vì hòa bình, độc lập và phát triển                           xây dựng và bảo vệ Tổ quốc.'),
('session-24',7,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ IX (2001)
                                                                                                                                                       tiếp tục thực hiện
                                                                                                                 công nghiệp hóa - hiện đại hóa

                                                                                           Thực hiện đường lối Đại hội IX
     Hội nghị                    Nghị quyết                    Sắp xếp, đổi mới, phát triển và
   Trung ương 3                05-NQ/TW                    nâng cao hiệu quả DNNN
                                   24/9/2001     khóa IX

                              Thống nhất                                                            Cần thiết thúc đẩy, đổi mới kinh tế     Hội nghị
                             nhận thức về                                                                                tập thể theo hình thức mới,   Trung ương 5                                    kinh tế                            xác lập môi trường thể chế
     khóa IX                                     tập thể                          và tâm lý xã hội thuận lợi'),
('session-24',8,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ IX (2001)
                                                                                                                                                       tiếp tục thực hiện
                                                                                                                  công nghiệp hóa - hiện đại hóa

                                                                                           Thực hiện đường lối Đại hội IX
                           Thống nhất  Hội nghị
                                                                                                           1. Một bộ phận cấu thành quan trọng của nền kinh tế                         nhận thức vềTrung ương 5                                                                                                        2. Vấn đề chiến lược lâu dài                                kinh tế
  khóa IX                                                                       3. Đổi mới cơ chế, khuyến khích kinh tế tư nhân phát triển                                  tư nhân

  Hội nghị                                                                                                      1. Tài nguyên quý giá, là TLSX đặc biệt                            Thống nhất                                                                                                      2. Quyền sử dụng đất là hàng hóa đặc biệt
Trung ương 7                nhận thức về                               3. Đất đai thuộc sở hữu toàn dân
  khóa IX                        đất đai                      4. Nhà nước giao đất, cho thuê đất lâu dài theo thời hạn                                                                                           5. Không thừa nhận đòi lại đất đã giao cho cá nhân, tổ chức sử dụng'),
('session-24',9,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ IX (2001)
          tiếp tục thực hiện
  công nghiệp hóa - hiện đại hóa
                                                                 Phát huy sức mạnh đại đoàn kết                              Nghị quyết 23-Thực hiện đường lối Đại hội IX                                                                     toàn dân tộc vì mục tiêu chung                          NQ/TW
                                                          "Dân giàu, nước mạnh, công bằng,                                    12/3/2003
                                                                  dân chủ, văn minh"
   Hội nghị
                              Nghị quyết 24- Trung ương 7                                              Công tác dân tộc, khẳng định vai
                          NQ/TW                                                                               trò của các dân tộc, tăng cường    khóa IX                                    12/3/2003                                                               đoàn kết, chống chia rẽ dân tộc    3/2003

                              Nghị quyết 25-                                                          Công tác tôn giáo. Khẳng định tín
                          NQ/TW                                                              ngưỡng là nhu cầu của nhân dân,
                                    12/3/2003                                                                      được Nhà nước tôn trọng'),
('session-24',10,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ IX (2001)
                                                                                                                                                       tiếp tục thực hiện
                                                                                                                 công nghiệp hóa - hiện đại hóa

                                                                                           Thực hiện đường lối Đại hội IX

                               Nghị quyết 36- Bộ Chính trị                                              Công tác đối với người Việt Nam ở
                           NQ/TW                                                                nước ngoài, coi đó là bộ phận không   khóa IX                                   26/3/2004                                                                            thể tách rời của dân tộ Việt Nam

                                 Được Nhà nước bảo hộ, thỏa thuận
                                             để bảo vệ quyền và lợi ích
                                             chính đáng của kiều bào'),
('session-24',11,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-25',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-25',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                  khủng hoảng kinh tế - xã hội 1986 - 1996
Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
              1975 - 1981                                                     hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                            Lãnh đạo công cuộc đổi mới,     Lãnh đạo cả nước xây dựng
                                                                                   đẩy mạnh công nghiệp hóa,      chủ nghĩa xã hội và bảo vệ                                                                                          hiện đại hóa và hội nhập quốc tế               Chương 3        Tổ quốc (1975 - 1986)                                                                                                           (từ năm 1986 đến nay)

 Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                           Thành tựu, kinh nghiệm của công cuộc đổi mới
   và các bước đột phá tiếp tục đổi mới kinh tế
               1982 - 1986
                                                               Nguyên nhân và tác hại của tham nhũng'),
('session-25',3,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                           Đại hội lần thứ X (2006)
                                                                                                               và quá trình thực hiện
                                                                                                                 Nghị quyết Đại hội
                                                                                         Bối cảnh Đại hội X

                                                                                Đất nước trải qua 20 năm đổi mới,
                                                                                                    đạt nhiều thành tựu to lớn
   Tình hình quốc tế diễn biến
nhanh chóng, phức tạp, khó lường
                                                                              Đất nước có sự thay đổi cơ bản,
                                                                                        toàn diện, thế và lực, uy tín quốc tế
                                                                                             tăng lên nhiều so với trước

                                Hà Nội
                                         18 - 25/4/2006'),
('session-25',4,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ X (2006)
                                                                                                               và quá trình thực hiện
                                                                                                                 Nghị quyết Đại hội                                                  Sớm đưa nước ta                                   Phát huy                                                                    ra khỏi tình                                                                                    Nội dung Đại hội X                                       sức mạnh                                                                     trạng kém                                   toàn dân tộc                                                                   phát triển                 Nâng cao                                         Đẩy mạnh                 năng lực lãnh                                                 toàn diện công                 đạo và sức chiến                                                    cuộc đổi mới                 đấu của Đảng

                   Chủ đề Đại hội X

Đồng chí Nông Đức Mạnh
                                                         Hà Nội  được bầu tiếp tục làm
  Tổng Bí thư của Đảng                                                             18 - 25/4/2006'),
('session-25',5,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ X (2006)
                                                                                                               và quá trình thực hiện
                                                                                                                 Nghị quyết Đại hội
                                                                                    Nội dung Đại hội X

             Kế hoạch Bổ sung                         Báo cáo               5 năm  Điều lệ                             chính trị            2006 -  Đảng
              2010

                                                          Hà Nội
                                                                             18 - 25/4/2006'),
('session-25',6,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ X (2006)
                                                                                                               và quá trình thực hiện
                                                                                                                 Nghị quyết Đại hội
                                                                                    Nội dung Đại hội X                                5 bài học lớn
                             của sự nghiệp
                                                                              Phát huy nội lực,                            Đổi mới                                   đổi mới
                                                                                          kết hợp với ngoại                          toàn diện, đồng bộ,
                                                                                                       lực, sức mạnh dân                           có kế thừa, có bước đi,
                                                                                          tộc với sức mạnh                             hình thức và
                                                                                          thời đại trong điều                            cách làm phù hợp
                                                     Đổi mới phải                  kiện mới           Nâng cao năng   Phải kiên định mục
                                                                  vì lợi ích của nhân dân,  tiêu độc lập dân tộc và                                                                                          lực lãnh đạo của
  CNXH trên nền tảng                                dựa vào nhân dân,                                                                                        Đảng, đảm bảo
  CN Mác - Lênin và                                   xuất phát từ thực tiễn,
                                                                                           quyền lực thuộc  tư tưởng Hồ Chí Minh                                                    nhạy bén với
                                                                                                      về nhân dân                                                                         cái mới'),
('session-25',7,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ X (2006)
        Cương lĩnh xây dựng đất nước trong thời kì quá                                                                                                               và quá trình thực hiện                                                                       Đại hội X                độ lên chủ nghĩa xã hội (1991)                                                                       Nghị quyết Đại hội
          Dân giàu, nước mạnh, xã hội công bằng             Dân giàu, nước mạnh, công bằng, dân chủ
                                                                                    Nội dung Đại hội X                   và văn minh (ĐH VIII)                                  và văn minh
                                                 Có Nhà nước pháp quyền XHCN của nhân dân, do
                                                     nhân dân, vì nhân dân dưới sự lãnh đạo của ĐCS

            Do nhân dân lao động làm chủ                     Do nhân dân làm chủ

       Có nền kinh tế phát triển cao dựa trên LLSX hiện          LLSX hiện đại, QHSX phù hợp với trình độ
              đại và chế độ công hữu về TLSX chủ yếu                          phát triển của LLSX
       Có nền văn hóa tiên tiến, đậm đà bản sắc dân tộc

        Con người được giải phóng khỏi áp bức, bóc lột, làm theo năng
                                                     Con người được giải phóng khỏi áp bức, bất công, có                   lực, hưởng theo lao động, có cuộc sống ấm no, tự do,
                hạnh phúc, có điều kiện phát triển toàn diện                 cuộc sống ấm no, tự do, hạnh phúc, phát triển toàn diện
       Các dân tộc trong nước bình đẳng, đoàn kết và giúp
                  đỡ lẫn nhau cùng tiến bộ
      Có quan hệ hữu nghị và hợp tác với nhân dân tất cả
                        các nước trên giới'),
('session-25',8,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ X (2006)
                                                                                                               và quá trình thực hiện
                                                                                                                 Nghị quyết Đại hội
                                                                                    Nội dung Đại hội X

                                                                            Nhiệm vụ then chốt,
                                                                                    thành tố đầu tiên là
                                                                                 xây dựng, chỉnh đốn Đảng
  “Đội tiên phong của giai cấp                         “Đội tiên phong của giai cấp công
                                                         nhân, đồng thời là đội tiên phong của   công nhân, đại biểu trung                                                  nhân dân lao động và của dân tộc Việt
 thành lợi ích của giai cấp công                   Nam, đại biểu trung thành lợi ích của
  nhân, nhân dân lao động và                             giai cấp công nhân, nhân dân lao động
                                                               và của dân tộc”         của dân tộc”'),
('session-25',9,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                              Đại hội lần thứ X (2006)
                                                                                                                  và quá trình thực hiện                                                       Nhiệm vụ then chốt,
                                                                                                                    Nghị quyết Đại hội                                                             thành tố đầu tiên là                Tuân thủ
                                                          xây dựng, chỉnh đốn Đảng               Điều lệ Đảng,                                                               Nội dung Đại hội X
               pháp luật của
              Nhà nước

                                                                    Tăng cường            Gắn kết chặt chẽ           Cho phép Đảng viên                                                                             bên ngoài                    với nhân dân             làm kinh tế, kể cả
             kinh tế tư bản tư nhân

                            Phân phối theo
Đảng viên làm KTTN            lao động, theo                                                  Đấu tranh chống                                                                      Chỉnh đốn    phải trực tiếp             phúc lợi xã hội, ưu                                                                            tiêu cực, tham nhũng,                                                                             bên trong tham gia lao động             tiên cho NLĐ mua                                                                                                         suy thoái
                                  cổ phần, góp vốn'),
('session-25',10,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ X (2006)
                                                                                                               và quá trình thực hiện
                                                 Nhiệm vụ then chốt                                                                                                                 Nghị quyết Đại hội
                                                         thứ hai là phát huy
                                                           sức mạnh toàn dân tộc                                                                                    Nội dung Đại hội X
     Điểm tương đồng                                               Điểm mới
      Độc lập dân tộc và                                                    Xóa bỏ mặc cảm,
        chủ nghĩa xã hội                   Chủ trương            định kiến quá khứ
                      đoàn kết
 Dân giàu, nước mạnh, dân chủ,                           Tôn trọng ý kiến khác nhau                      dân tộc
     công bằng và văn minh                             nhưng không trái với lợi ích chung'),
('session-25',11,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
 Đại hội lần thứ X (2006)
   và quá trình thực hiện
    Nghị quyết Đại hội
 Nội dung Đại hội X ĐẨY MẠNH TOÀN DIỆN                              Tiếp tục hoàn thiện thể chế KTTT
                                                                          định hướng xã hội chủ nghĩa

   Nhiệm vụ then chốt                                              Đẩy mạnh CNH - HĐH gắn với   thứ ba là đẩy mạnh
                                                                           phát triển kinh tế tri thứctoàn diện công cuộc đổi mới

                công cuộc đổi mới
                                                Mở rộng quan hệ đối ngoại,
                                                                                                tích cực, chủ động'),
('session-25',12,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
   Đại hội lần thứ X (2006)
    và quá trình thực hiện                                                       Nhiệm vụ then chốt,
      Nghị quyết Đại hội                                                             thành tố đầu tiên là
                                                          xây dựng, chỉnh đốn ĐảngThực hiện đường lối Đại hội X

     Hội nghị                                             Tăng cường sự lãnh đạo của Đảng đối
                                  Nghị quyết 04-NQ/TW   Trung ương 3                                                           với công tác đấu tranh phòng,                                        21/8/2006
      khóa X                                                                 chống tham nhũng, lãng phí

     Hội nghị
                                  Nghị quyết 14-NQ/TW                  Tăng cường công tác kiểm tra,   Trung ương 5
                                        30/7/2007                           giám sát của Đảng      khóa X'),
('session-25',13,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
   Đại hội lần thứ X (2006)
    và quá trình thực hiện                                                       Nhiệm vụ then chốt,
      Nghị quyết Đại hội                                                             thành tố đầu tiên là
                                                          xây dựng, chỉnh đốn ĐảngThực hiện đường lối Đại hội X

     Hội nghị                                           6 ban tham mưu của Trung ương
                                Sắp xếp bộ máy Nhà nước   Trung ương 4                                                   Chính phủ có 22 bộ và                                   tinh gọn, hiệu lực, hiệu quả hơn
      khóa X                                                                             cơ quan ngang bộ

     Hội nghị                                          Nâng cao năng lực lãnh đạo, sức chiến
                                  Nghị quyết 22-NQ/TW   Trung ương 6                                               đấu của tổ chức cơ sở đảng và                                        2/2/2008
      khóa X                                                                       chất lượng đội ngũ đảng viên'),
('session-25',14,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
   Đại hội lần thứ X (2006)
    và quá trình thực hiện                                                       Nhiệm vụ then chốt,
      Nghị quyết Đại hội                                                             thành tố đầu tiên là
                                                          xây dựng, chỉnh đốn ĐảngThực hiện đường lối Đại hội X

             Hội nghị                                                   Tiếp tục đổi mới phương thức
                                          Nghị quyết 15-NQ/TW          Trung ương 5                                             lãnh đạo của Đảng đối với hoạt                                                30/7/2007
             khóa X                                             động của hệ thống chính trị
                                      Đảng lãnh đạo bằng                                                              Đảng buông lỏng sự                  Đảng bao biện                                            cương lĩnh, đường lối,                                                                                  lãnh đạo                     làm thay                                               chủ trương lớn

                     Thực hiện đúng                                   Đẩy mạnh phân cấp,                                           Thực hành dân chủ
                    nguyên tắc tập trung                                       tăng trách nhiệm cá nhân,                                              rộng rãi trong xã hội
                   dân chủ trong Đảng                                        nhất là người đứng đầu'),
('session-25',15,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
   Đại hội lần thứ X (2006)
    và quá trình thực hiện                                                    Nhiệm vụ then chốt
      Nghị quyết Đại hội                                                             thứ hai là phát huy
                                                               sức mạnh toàn dân tộcThực hiện đường lối Đại hội X

     Hội nghị                                                       Tiếp tục xây dựng giai cấp công nhân
   Trung ương 6              Nghị quyết 20-NQ/TW                 trong thời kỳ đẩy mạnh CNH - HĐH
      khóa X                                                                              đất nước

     Hội nghị                                               Tăng cường sự lãnh đạo của Đảng
                                  Nghị quyết 25-NQ/TW   Trung ương 7                                                        đối với công tác thanh niên thời kỳ                                        25/7/2008
      khóa X                                                                 đẩy mạnh CNH - HĐH'),
('session-25',16,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
   Đại hội lần thứ X (2006)
    và quá trình thực hiện                                                    Nhiệm vụ then chốt
      Nghị quyết Đại hội                                                             thứ hai là phát huy
                                                               sức mạnh toàn dân tộcThực hiện đường lối Đại hội X

                                                                                                                   1. Coi việc trả công đúng cho NLĐ
     Hội nghị                                                                                            là thực hiện đầu tư phát triển                              Cải cách tiền lương, BHXH
   Trung ương 6             và trợ cấp cho người có công                                                                                                      2. Tạo động lực nội sinh
      khóa X                       giai đoạn 2008 - 2012                               3. Góp phần làm trong sạch và
                                                                  nâng cao hiệu quả bộ máy nhà nước

     Hội nghị
                                  Nghị quyết 27-NQ/TW                 Xây dựng đội ngũ tri thức trong   Trung ương 7
                                       6/8/2008                            thời kỳ đẩy mạnh CNH - HĐH      khóa X'),
('session-25',17,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
   Đại hội lần thứ X (2006)
    và quá trình thực hiện                                                           Nhiệm vụ then chốt
      Nghị quyết Đại hội                                                                    thứ ba là đẩy mạnh
                                                                toàn diện công cuộc đổi mớiThực hiện đường lối Đại hội X                                                                Nghị quyết 09 về
                                                                                  Chiến lược biển Việt Nam đến 2020

                                                                 Có vị trí địa chính trị,
        Hội nghị                                                          địa kinh tế cực kỳ quan trọng
      Trung ương 4                                                                     Phấn đấu đến 2020,
                                                                           kinh tế biển đóng góp 53 - 55% GDP,        khóa X
                                                                        55 - 60% kim ngạch xuất khẩu

                                                                    Trở thành quốc gia mạnh về biển, làm giàu và
                                                                             phát huy mọi tiềm năng từ biển'),
('session-25',18,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
   Đại hội lần thứ X (2006)
    và quá trình thực hiện                                                           Nhiệm vụ then chốt
      Nghị quyết Đại hội                                                                    thứ ba là đẩy mạnh
                                                                toàn diện công cuộc đổi mớiThực hiện đường lối Đại hội X

     Hội nghị                                Nghị quyết 21 về                                                          Tôn trọng đầy đủ các quy luật   Trung ương 6              Tiếp tục hoàn thiện thể chế
                                                                                 thị trường và các thông lệ quốc tế      khóa X             KTTT định hướng XHCN

     Hội nghị
                                         Nghị quyết                         Giải quyết đồng bộ, gắn với quá trình   Trung ương 7                Về giải quyết vấn đề nông
                                     nghiệp, nông dân và nông thôn              đẩy mạnh công nghiệp hóa, hiện đại hóa      khóa X'),
('session-25',19,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
   Đại hội lần thứ X (2006)
    và quá trình thực hiện                                                           Nhiệm vụ then chốt
      Nghị quyết Đại hội                                                                    thứ ba là đẩy mạnh
                                                                toàn diện công cuộc đổi mớiThực hiện đường lối Đại hội X

                                     Hội nghị
                                                                  Nghị quyết 08-NQ/TW                                  Trung ương 4
                                                                             5/2/2007
                                    khóa X

                                                     Chủ trương, chính sách lớn để nền
                                                                    kinh tế phát triển nhanh và bền
           11/2006                                        vững khi Việt Nam là thành viên
                                                                           của WTO'),
('session-25',20,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
Đại hội lần thứ X (2006)
 và quá trình thực hiện
   Nghị quyết Đại hội
                                           2010
   Kết quả              Quan hệ giao thương với 230 quốc gia và vùng lãnh thổ

                              Hai đối tác lớn nhất là Hoa Kỳ và Trung Quốc'),
('session-25',21,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
Đại hội lần thứ X (2006)
 và quá trình thực hiện
   Nghị quyết Đại hội
   Kết quả

               Đầu tư trực tiếp nước ngoài
           2005: 6.84 tỷ USD --> 2010: 19.88 tỷ USD'),
('session-25',22,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
Đại hội lần thứ X (2006)                                                       Tốc độ tăng trưởng GDP bình quân = và quá trình thực hiện                                                    7%   Nghị quyết Đại hội
    Kết quả

                                                                                       Đơn vị: nghìn tỷ đồng       GDP bình quân đầu người 2010: 1.168 USD

            Ra khỏi nhóm nước nghèo từ 2008'),
('session-25',23,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-26',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-26',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                  khủng hoảng kinh tế - xã hội 1986 - 1996
Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
              1975 - 1981                                                     hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                            Lãnh đạo công cuộc đổi mới,     Lãnh đạo cả nước xây dựng
                                                                                   đẩy mạnh công nghiệp hóa,      chủ nghĩa xã hội và bảo vệ                                                                                          hiện đại hóa và hội nhập quốc tế               Chương 3        Tổ quốc (1975 - 1986)                                                                                                           (từ năm 1986 đến nay)

Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                           Thành tựu, kinh nghiệm của công cuộc đổi mới
  và các bước đột phá tiếp tục đổi mới kinh tế
              1982 - 1986
                                                               Nguyên nhân và tác hại của tham nhũng'),
('session-26',3,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                           Đại hội lần thứ XI (2011)
                                                                                                                  của Đảng bổ sung, phát triển
                                                                                                        Cương lĩnh 1991
                                                                                         Bối cảnh Đại hội XI Hòa bình, hợp tác và phát triển
       vẫn là xu thế lớn
                                                                           Cả nước vừa kỷ niệm 1000 năm
  Chiến tranh cục bộ, xung đột                                                        Thăng Long với những thành tựu
 vũ trang, khủng bố, tranh chấp                                                      quan trọng nhưng còn nhiều yếu kém
   lãnh thổ diễn biến phức tạp
                                                                                Các thế lực thù địch tiếp tục chống
Thiên tai, dịch bệnh, khủng hoảng,                                                                                               phá, kích động bạo loạn, đẩy mạnh
    suy thoái kinh tế toàn cầu,                                                                                           hoạt động “Diễn biến hòa bình”
   ô nhiễm môi trường, biến đổi
   khí hậu diễn ra nghiêm trọng
                                Hà Nội
                                           12 - 19/1/2011'),
('session-26',4,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                           Đại hội lần thứ XI (2011)
                                                                                                                  của Đảng bổ sung, phát triển
                                                                                                        Cương lĩnh 1991
                                                                                    Nội dung Đại hội XI

          Chiến lược                                                 Đồng chí Nguyễn Phú Trọng
           phát triển                                                            được bầu làm Tổng Bí thư
         kinh tế - xã hội                                     Hà Nội         2011 - 2020                                                  12 - 19/1/2011'),
('session-26',5,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                           Đại hội lần thứ XI (2011)
                                                                                                                  của Đảng bổ sung, phát triển
                                                                                                        Cương lĩnh 1991
                        Quá trình cách mạng Việt Nam và                                                                                    Nội dung Đại hội XI                               những bài học kinh nghiệm

                        Quá độ lên chủ nghĩa xã hội ở Việt Nam
                                 trong bối cảnh mới diễn biến phức tạp

                               Những định hướng lớn về phát triển kinh tế,
                                 văn hóa, xã hội, quốc phòng an ninh, đối ngoại

                                  Xây dựng, chỉnh đốn
   Cương lĩnh 2011 bổ sung,                                     và phát triển Đảng
   phát triển Cương lĩnh 1991'),
('session-26',6,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)                                         Quá trình cách mạng Việt Nam và
của Đảng bổ sung, phát triển                                                 những bài học kinh nghiệm
     Cương lĩnh 1991                                       Không ngừng
Nội dung Đại hội XI                          tăng cường, củng cố
                                           bốn đoàn kết
                     Sự nghiệp                                                                           Kết hợp sức mạnh
                     cách mạng là của                               dân tộc với sức mạnh
                 nhân dân, do nhân                                       thời đại, trong nước
                     dân, vì nhân dân                                            với quốc tế

                      Quá trình cách mạng Việt Nam
                                                                                   Sự lãnh đạo         Nắm vững ngọn cờ                                                                               đúng đắn của đảng là
              độc lập dân tộc và           Hoàn thành cách mạng                                                                              nhân tố hàng đầu
              chủ nghĩa xã hội.            dân tộc dân chủ nhân dân                                                                              quyết định thắng lợi
                               Làm tròn nghĩa vụ quốc tế
                                      Thực hiện đổi mới thắng lợi
                                Những sai lầm, hạn chế và thái độ'),
('session-26',7,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)                                                       Quá độ lên chủ nghĩa xã hội ở Việt Nam
của Đảng bổ sung, phát triển                                                                           trong bối cảnh mới diễn biến phức tạp
     Cương lĩnh 1991
Nội dung Đại hội XI

   Đặc điểm, xu thế chung

                                                      Đấu tranh dân tộc, giai cấp
                                                                Chiến tranh cục bộ, xung đột vũ trang

                                                            Hoạt động can thiệp, khủng bố

                                                               Tranh chấp lãnh thổ biển, đảo      Hòa bình, độc lập dân
          tộc, dân chủ, hợp tác và
                                                         Cạnh tranh quyết liệt về kinh tế        phát triển là xu thế lớn'),
('session-26',8,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)                                                       Quá độ lên chủ nghĩa xã hội ở Việt Nam
của Đảng bổ sung, phát triển                                                                           trong bối cảnh mới diễn biến phức tạp
     Cương lĩnh 1991
Nội dung Đại hội XI
     Đánh giá về chủ nghĩa xã hội

                                         Xuất hiện các trào lưu
                                       chủ nghĩa xã hội hiện thực mới

                                                                       "Theo quy luật tiến hóa
                                                                     của lịch sử, loài người                                       Các nước tư bản chủ nghĩa
          Chủ nghĩa tư bản còn tiềm năng                                             phải điều chỉnh chiến lược                  nhất định sẽ tiến tới              phát triển, nhưng chứa đựng
               nhiều bất ổn, khủng hoảng                                              chủ nghĩa xã hội"
                                       Các quốc gia vừa hợp tác
                                         vừa cạnh tranh gay gắt             Những mối quan tâm lớn
                  liên quan vận mệnh thế giới                vì lợi ích quốc gia, dân tộc'),
('session-26',9,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)                                                     Đẩy mạnh                       Quá độ lên chủ nghĩa xã hội ở Việt Nam
của Đảng bổ sung, phát triển                                            CNH-HĐH                               trong bối cảnh mới diễn biến phức tạp
     Cương lĩnh 1991                                          gắn với PTKT              Phát triển                                    Xây dựng
                                                                                            tri thức, bảo vệ                kinh tế                                   Đảng
                                              TNMT                      thị trườngNội dung Đại hội XI                                           trong sạch,
                                                                                             định hướng                                      vững mạnh
                                                             XHCN

                                                                                                              Xây dựng nền
                      Xây dựng Nhà                                                                         văn hóa tiến tiến                             8 Phương hướng
                           nước pháp                                                               đậm đà bản sắc,                                                                                                                     nâng cao đời                                  phát triển                         quyền của dân,                                                                                sống nhân dân,
                                                                                                                                                                tiến bộ và                         do dân, vì dân                             (Cương lĩnh 2011)                          công bằng

                                    Xây dựng                                    Bảo đảm
                                      dân chủ                                          quốc phòng
                                                              Đối ngoại                               XHCN, tăng                                   an ninh, trật
                                        cường đoàn                 độc lập tự                                                                                                                      tự, an toàn
                                                kết dân tộc                  chủ, tích cực                                                                                        xã hội
                                                                           hội nhập
                                                                    quốc tế'),
('session-26',10,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)                                                                       Quá độ lên chủ nghĩa xã hội ở Việt Nam
của Đảng bổ sung, phát triển                                                                                                 trong bối cảnh mới diễn biến phức tạp
     Cương lĩnh 1991
Nội dung Đại hội XI'),
('session-26',11,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)
                                                                             Những định hướng lớn về phát triển kinh tế,của Đảng bổ sung, phát triển
                                                                                   văn hóa, xã hội, quốc phòng an ninh, đối ngoại     Cương lĩnh 1991
Nội dung Đại hội XI

                                                            Kinh tế Nhà nước      Giữ vai trò chủ đạo

         Phát triển                         Các thành phần               Kinh tế tập thể      Cùng với kinh tế nhà nước tạo
        nền kinh tế                                                                                       nền tảng xã hội chủ nghĩa                         kinh tế bình đẳng trước           thị trường
                                                                          Một trong những         định hướng       pháp luật, là các bộ phận           Kinh tế tư nhân
                                                                                     động lực quan trọng
       xã hội chủ nghĩa      hợp thành nền kinh tế
                                                             Kinh tế có vốn                                                                                  Khuyến khích
                                                          đầu tư nước ngoài          phát triển'),
('session-26',12,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)
                                                                             Những định hướng lớn về phát triển kinh tế,của Đảng bổ sung, phát triển
                                                                                   văn hóa, xã hội, quốc phòng an ninh, đối ngoại     Cương lĩnh 1991
Nội dung Đại hội XI

 Coi trọng phát triển công nghiệp nặng,                                                     Bảo vệ                                                 Công nghiệp                                                                 Kinh tế           chế tạo, có lợi thế                                                                 hóa,                                          tài nguyên,
                                                                                                   tri thức                           Phát triển        hiện đại hóa     Phát triển nông, lâm, ngư có                                                         môi trường
     chất lượng cao, công nghệ cao       kinh tế là
     gắn với công nghiệp chế biến      nhiệm vụ
                            trung tâm           Cơ cấu kinh tế hợp lý,          Gắn kết chặt chẽ     Bảo đảm hài hòa, gắn kết
                                                                  hiện đại, hiệu quả, bền vững         ba khu vực kinh tế            các vùng miền
 Xây dựng nền kinh tế độc lập, tự chủ,
            tích cực hội nhập'),
('session-26',13,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)
                                                                             Những định hướng lớn về phát triển kinh tế,của Đảng bổ sung, phát triển
                                                                                   văn hóa, xã hội, quốc phòng an ninh, đối ngoại     Cương lĩnh 1991
Nội dung Đại hội XI

                                        Coi con người là trung tâm của phát triển
          Xây dựng nền                                       Coi phát triển giáo dục đào tạo là quốc sách
          văn hóa tiên tiến,                             Đầu tư cho giáo dục đào tạo là đầu tư phát triển
         đậm đà bản sắc    Chủ trương: chuẩn hóa, hiện đại hóa và xã hội hóa giáo dục
             dân tộc                    Đẩy lùi tệ nạn xã hội
                                 Cân bằng giới tính và chất lượng dân số'),
('session-26',14,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)
của Đảng bổ sung, phát triển                                           Xây dựng, chỉnh đốn
     Cương lĩnh 1991                                                                 và phát triển Đảng
Nội dung Đại hội XI

                             Đảng lãnh đạo          Thống nhất            Chịu sự giám sát
                                                                                          của nhân dân, hoạt                                bằng cương lĩnh,            lãnh đạo
                                                                                      động trong khuôn
                                     sách lược, chủ          công tác cán bộ                                                                                      khổ Hiến pháp &
                                     trương lớn          và quản lý cán bộ                                                                                         pháp luật'),
('session-26',15,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XI (2011)
của Đảng bổ sung, phát triển
     Cương lĩnh 1991
Nội dung Đại hội XI                        Quan điểm phát triển:
                                  Phát triển nhanh gắn với phát triển bền vững
                                      Ba đột phá chiến lược
                                                1. Hoàn thiện thể chế kinh tế thị trường định hướng XHCN          Chiến lược
           phát triển              2. Phát triển nhanh nguồn nhân lực, nhất là chất lượng cao
         kinh tế - xã hội                                                3. Xây dựng kết cấu hạ tầng đồng bộ, hiện đại
         2011 - 2020
                                            Định hướng
                              Đổi mới mô hình tăng trưởng, cơ cấu lại nền kinh tế
                                 Tăng hiệu lực, hiệu quả quản lý Nhà nước
                              Đấu tranh phòng chống tham nhũng'),
('session-26',16,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

   Đại hội lần thứ XI (2011)
 của Đảng bổ sung, phát triển
      Cương lĩnh 1991
Thực hiện đường lối Đại hội XI

       Hội nghị
                               Chủ trương xây dựng                Đưa nước ta cơ bản     Trung ương 4
                                   hệ thống kết cấu hạ tầng                         trở thành nước       khóa XI
                                       đồng bộ                          công nghiệp theo hướng          (1/2012)
                                                                                        hiện đại vào năm 2020

       Hội nghị
                                                                   Đất được phân bổ hợp lý, sử dụng     Trung ương 5                  Khẳng định vai trò,
                                                                         đúng mục đích, tiết kiệm và       khóa XI                        khái niệm đất đai
                                                                                      có hiệu quả, đảm bảo mục đích          (5/2012)
                                                                                           trước mắt và lâu dài'),
('session-26',17,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

   Đại hội lần thứ XI (2011)
 của Đảng bổ sung, phát triển
      Cương lĩnh 1991
Thực hiện đường lối Đại hội XI

       Hội nghị
                                    Kết luận Đề án tiếp tục              DNNN là công cụ    Trung ương 6
                                   sắp xếp, đổi mới và nâng                 hỗ trợ Nhà nước QLKT       khóa XI
                                     cao hiệu quả DNNN                 Tập trung vào các lĩnh vực        (10/2012)
                                                                                     then chốt, trọng yếu
                                                     Mở rộng quyền tự chủ,
                                                                                       tự chịu trách nhiệm'),
('session-26',18,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

   Đại hội lần thứ XI (2011)
 của Đảng bổ sung, phát triển
      Cương lĩnh 1991
Thực hiện đường lối Đại hội XI

       Hội nghị
     Trung ương 4                  Nghị quyết số 12-NQ/TW                                                              Một số vấn đề cấp bách trong
       khóa XI                                (16/1/2012)                                                                            xây dựng Đảng hiện nay
          (1/2012)

       Hội nghị                                                        Tăng cường sự lãnh đạo của                                   Nghị quyết số 25-NQ/TW
     Trung ương 7                                                 Đảng trong công tác dân vận                                                 (3/6/2013)
       khóa XI                                                                      trong tình hình mới'),
('session-26',19,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

   Đại hội lần thứ XI (2011)
 của Đảng bổ sung, phát triển
      Cương lĩnh 1991
Thực hiện đường lối Đại hội XI

                                                                             Phát triển khoa học &       Hội nghị
                                  Nghị quyết số 20-NQ/TW                                                                              công nghệ phục vụ sự nghiệp     Trung ương 6
                                                   (1/12/2012)                                                  CNH HĐH trong điều kiện       khóa XI
                                                              KTTT định hướng XHCN

       Hội nghị                                                           Đổi mới toàn diện, căn bản                                  Nghị quyết số 29-NQ/TW
     Trung ương 8                                                                   giáo dục và đào tạo đáp ứng                                                  (4/11/2013)
       khóa XI                                             CNH HĐH'),
('session-26',20,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

   Đại hội lần thứ XI (2011)
 của Đảng bổ sung, phát triển
      Cương lĩnh 1991
Thực hiện đường lối Đại hội XI

                                                                   Xây dựng, phát triển văn hóa,       Hội nghị
                                   Nghị quyết số 33-NQ/TW                                                                              con người Việt Nam đáp ứng     Trung ương 9
                                                (9/6/2014)                                                                    nhu cầu phát triển bền vững       khóa XI
                                                                                          đất nước

       Hội nghị                  Chủ trương giải quyết                                                                                                                                                 1. Thực hiện rộng rãi chính sách an sinh xã hội
     Trung ương 5                    một số vấn đề                                                                                                                           2. Khuyến khích mọi thành phần tham gia
       khóa XI                        chính sách xã hội                                                                                                                         3. Tạo điều kiện để người dân tự đảm bảo an sinh'),
('session-26',21,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

   Đại hội lần thứ XI (2011)
 của Đảng bổ sung, phát triển
      Cương lĩnh 1991
Thực hiện đường lối Đại hội XI

       Hội nghị                                                                Chủ động ứng phó biến đổi                                  Nghị quyết số 24-NQ/TW     Trung ương 7                                                                                      khí hậu, tăng cường quản lý                                                 (6/3/2013)       khóa XI                                                                                                  tài nguyên & bảo vệ môi trường

       Hội nghị
                                  Nghị quyết số 28-NQ/TW             Chiến lược bảo vệ Tổ quốc     Trung ương 8
                                                (25/10/2013)                                                                             trong tình hình mới       khóa XI'),
('session-26',22,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-27',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-27',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                  khủng hoảng kinh tế - xã hội 1986 - 1996
Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
              1975 - 1981                                                     hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                            Lãnh đạo công cuộc đổi mới,     Lãnh đạo cả nước xây dựng
                                                                                   đẩy mạnh công nghiệp hóa,      chủ nghĩa xã hội và bảo vệ                                                                                          hiện đại hóa và hội nhập quốc tế               Chương 3        Tổ quốc (1975 - 1986)                                                                                                            (từ năm 1986 đến nay)

Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                           Thành tựu, kinh nghiệm của công cuộc đổi mới
  và các bước đột phá tiếp tục đổi mới kinh tế
              1982 - 1986
                                                               Nguyên nhân và tác hại của tham nhũng'),
('session-27',3,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ XII (2016)
                                                                                                            đẩy mạnh toàn diện, đồng bộ
    Chủ đề Đại hội XII                                                                                     công cuộc đổi mới, tích cực,
                                                                                                                 chủ động hội nhập quốc tế

   Tăng cường xây dựng Đảng                                                                                   Nội dung Đại hội XII
     trong sạch, vững mạnh
 Phát huy sức mạnh toàn dân tộc,
    dân chủ xã hội chủ nghĩa
  Đẩy mạnh toàn diện, đồng bộ
       công cuộc đổi mới
Bảo vệ vững chắc Tổ quốc, giữ vững
   môi trường hòa bình, ổn định                                                                     Đồng chí Nguyễn Phú Trọng
   Phấn đấu sớm đưa nước ta                                                              được tiếp tục
                                Hà Nội    trở thành nước công nghiệp                                                        bầu làm Tổng Bí thư
                                 20 - 28/1/2016       theo hướng hiện đại'),
('session-27',4,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ XII (2016)
                                                                                                            đẩy mạnh toàn diện, đồng bộ
                                                                                                                   công cuộc đổi mới, tích cực,
                                                                                                                 chủ động hội nhập quốc tế
                                     Kinh nghiệm
                                        sau 5 năm                                                                                   Nội dung Đại hội XII
                                           thực hiện
                                          nghị quyết                           Nhìn thẳng vào                                      Kiên trì thực hiện
                                        Đại hội XI            các mục tiêu lâu dài,                             sự thật, đánh giá
                                                                            đồng thời tập trung                         đúng sự thật, nói rõ
                                                                         nguồn lực giải quyết                           sự thật, bám sát thực
                                                                                          các vấn đề cấp bách                                  tiễn của đất nước và                                                                              Chủ động,                                            Gắn kết chặt chẽ,                                                                                              trước mắt   Hết sức chú trọng               thế giới                                                                                                                     tích cực hội nhập                                                    đồng bộ nhiệm vụ
    xây dựng Đảng,                                                      phát triển kinh tế xã hội                             quốc tế trên cơ sở
  phát huy dân chủ và                                                                - xây dựng Đảng - phát                                 giữ vững độc lập,  tăng cường khối đại                                                                   triển văn hóa - quốc                                                                                                    tự chủ, lợi ích quốc   đoàn kết dân tộc                                                     phòng an ninh                                                                                                               gia dân tộc'),
('session-27',5,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
                                                                                                          Đại hội lần thứ XII (2016)
                                                                                                            đẩy mạnh toàn diện, đồng bộ
                                                                                                                   công cuộc đổi mới, tích cực,
                                                                                                                 chủ động hội nhập quốc tế        Tăng cường xây dựng,                      Đẩy mạnh đấu tranh
            chỉnh đốn Đảng                            phòng, chống tham nhũng                                                                                   Nội dung Đại hội XII

                                                6
        Thực hiện nâng cao chất lượng                           Kiên trì bảo vệ Tổ quốc,
             tăng trưởng, NSLĐ                                  giữ môi trường hòa bình,                                                    nhiệm
            và tính cạnh tranh                              ổn định để phát triển
                                                     vụ
                                                           trọng
        Thu hút, phát huy mạnh mẽ                        Phát huy nhân tố con
         nguồn lực và sức sáng tạo                         người trong mọi lĩnh vực                                                 tâm
               của nhân dân                               của đời sống xã hội'),
('session-27',6,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ XII (2016)
    đẩy mạnh toàn diện, đồng bộ
     công cuộc đổi mới, tích cực,
     chủ động hội nhập quốc tế
Thực hiện đường lối Đại hội XII

                                                               Một số chủ trương, chính sách lớn nhằm                 Hội nghị
                                                                                                     tiếp tục đổi mới mô hình tăng trưởng,                                    Nghị quyết số 05-NQ/TW               Trung ương 6                                                     (1/11/2016)                                                                          nâng cao chất lượng tăng trưởng,                 khóa XII
                                                                   NSLĐ, sức cạnh tranh của nền kinh tế

                         Cải thiện môi                                                                                                                          Phát huy tiềm                                                      Gắn với nông                                                Cơ cấu lại nông nghiệp,                          Nâng cao chất     Hoàn thiện thể    trường đầu tư,                                                                                       năng, lợi thế mọi
                                                    đầu tư công, DNNN,    thôn mới, nâng            lượng tăng trưởng,       chế KTTT định      khởi nghiệp,                                                                                      ngành, lĩnh vực,
                                                     Tổ chức tín dụng,      cao hiệu quả            NSLĐ, sức cạnh
      hướng XHCN    trọng dụng nhân                                                                           mọi địa phương và                                             NSNN nợ công                                                                   kinh tế, xã hội            tranh là trọng yếu                                    tài ...                                                                                                    cả nước'),
('session-27',7,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ XII (2016)
    đẩy mạnh toàn diện, đồng bộ
     công cuộc đổi mới, tích cực,
     chủ động hội nhập quốc tế
Thực hiện đường lối Đại hội XII
                                                      "Thực hiện hiệu quả
                                                                tiến trình hội nhập kinh tế                      Kiên định độc lập, tự chủ,
           Hội nghị                            quốc tế, giữ vững ổn định                                                                                                             tích cực chủ động hội nhập
         Trung ương 4                             chính trị xã hội trong                                                                                                kinh tế quốc tế
                                                               bối cảnh tham gia các           khóa XII                                                                                                   "Lợi ích quốc gia - dân tộc
                                                             hiệp định thương mại                                                                                                                    là trên hết"
                                                            tư do thế hệ mới"

                                       Hội nhập các lĩnh               Hội nhập là sự
                                          vực khác phải tạo                nghiệp của toàn
                                              điều kiện cho hội                dân, mọi thành
                                       nhập về kinh tế                phần kinh tế'),
('session-27',8,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ XII (2016)
    đẩy mạnh toàn diện, đồng bộ
     công cuộc đổi mới, tích cực,
     chủ động hội nhập quốc tế
Thực hiện đường lối Đại hội XII

           Hội nghị                                           Nghị quyết số 12-NQ/TW                                                                                             Tiếp tục cơ cấu lại, đổi mới và nâng         Trung ương 5                                                        3/6/2017                                                                                       cao hiệu quả doanh nghiệp nhà nước           khóa XII

        100% vốn điều lệ
                                                                              Cạnh tranh bình         Vốn góp chi phối
                                                                                           đẳng
                                                                         Lấy hiệu quả kinh tế làm tiêu chí chủ yếu, tự chủ,  Cơ cấu lại: tập trung vào các địa bàn
                                                                                                   tự chịu trách nhiệm      trọng yếu, lĩnh vực then chốt'),
('session-27',9,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ XII (2016)
    đẩy mạnh toàn diện, đồng bộ
     công cuộc đổi mới, tích cực,
     chủ động hội nhập quốc tế
Thực hiện đường lối Đại hội XII
                                                                                   Phát triển kinh tế tư nhân           Hội nghị                                          Nghị quyết số 10-NQ/TW                                                                                                   trở thành một động lực quan         Trung ương 5                                                        3/6/2017                                                                                         trọng của nền kinh tế thị trường           khóa XII
                                                                                       định hướng xã hội chủ nghĩa

                Thừa nhận: kinh tế tư nhân là một động lực quan trọng

                                                                     Nòng cốt
        Kinh tế            Kinh tế            Kinh tế                                                                              phát triển kinh tế
      Nhà nước             tập thể              tư nhân                                                                                độc lập, tự chủ'),
('session-27',10,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ XII (2016)
    đẩy mạnh toàn diện, đồng bộ
     công cuộc đổi mới, tích cực,
     chủ động hội nhập quốc tế
Thực hiện đường lối Đại hội XII
                                                                                   Phát triển kinh tế tư nhân           Hội nghị                                          Nghị quyết số 10-NQ/TW                                                                                                   trở thành một động lực quan         Trung ương 5                                                        3/6/2017                                                                                         trọng của nền kinh tế thị trường           khóa XII
                                                                                       định hướng xã hội chủ nghĩa
                               Xóa bỏ mọi định kiến
         Khuyến khích phát triển doanh nghiệp vừa và nhỏ, các tập đoàn tư nhân đa sở hữu

                   Khuyến khích tư nhân góp vốn vào doanh nghiệp nhà nước

                Tăng cường thanh tra, giám sát, đảm bảo làm giàu đúng pháp luật'),
('session-27',11,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ XII (2016)
    đẩy mạnh toàn diện, đồng bộ
     công cuộc đổi mới, tích cực,
     chủ động hội nhập quốc tế
Thực hiện đường lối Đại hội XII

           Hội nghị                                                                            Tăng cường xây dựng, chỉnh                                          Nghị quyết số 04-NQ/TW
         Trung ương 4                                                                             đốn Đảng, ngăn chặn, đẩy lùi                                                    30/10/2016
           khóa XII                                                                                                "tự diễn biến", "tự chuyển hóa"

             Nhìn thẳng vào sự thật, nói lên sự thật và đánh giá đúng sự thật
             Nêu gương người đứng đầu, nhất là Bộ Chính trị, Ban Bí Thư'),
('session-27',12,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ XII (2016)
    đẩy mạnh toàn diện, đồng bộ
     công cuộc đổi mới, tích cực,
     chủ động hội nhập quốc tế
Thực hiện đường lối Đại hội XII

                                                                            Tăng cường công tác bảo vệ,                                          Nghị quyết số 20-NQ/TW
                                                                       chăm sóc và nâng cao sức khỏe                                                       25/10/2017
                                                                           nhân dân trong tình hình mới
           Hội nghị
         Trung ương 6                                                                   Đầu tư cho sức khỏe, dân số
           khóa XII                                                                                                            là đầu tư cho phát triển

                                           Nghị quyết số 21-NQ/TW                                                                              Công tác dân số
                                                       25/10/2017                                                                                             trong tình hình mới'),
('session-27',13,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)
    Đại hội lần thứ XII (2016)
    đẩy mạnh toàn diện, đồng bộ
     công cuộc đổi mới, tích cực,
     chủ động hội nhập quốc tế
Thực hiện đường lối Đại hội XII
                                                                                   Cải cách chính sách tiền lương
                                          Nghị quyết số 27-NQ/TW                                                                                               đối với cán bộ, công chức, viên
                                                         21/5/2018                                                                                                 chức, LLVT, người lao động
                                                                                             trong doanh nghiệp           Hội nghị
         Trung ương 7
           khóa XII

                                          Nghị quyết số 28-NQ/TW                                                                                       Cải cách chính sách
                                                        23/5/2018                                                                                        bảo hiểm xã hội'),
('session-27',14,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
   Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                                                  Đại hội lần thứ XIII (2021)
                                                                                                                                        tiếp tục đẩy mạnh toàn diện,      Chủ đề Đại hội XIII
                                                                                                     đồng bộ công cuộc đổi mới
 Tăng cường xây dựng, chỉnh đốn Đảng,                                                                                     Nội dung Đại hội XIII
hệ thống chính trị trong sạch, vững mạnh
  Khởi dậy khát vọng phát triển đất nước,
   phát huy ý chí, sức mạnh đoàn kết toàn
   dân tộc kết hợp với sức mạnh thời đại
      Tiếp tục đẩy mạnh toàn diện,
      đồng bộ công cuộc đổi mới
   Bảo vệ vững chắc Tổ quốc, giữ vững
                                                                       Đồng chí Nguyễn Phú Trọng     môi trường hòa bình, ổn định
                                                                                           được tiếp tục     Phấn đấu đến giữa thế kỷ XXI,                                    Hà Nội                                                                                   bầu làm Tổng Bí thư    nước ta trở thành nước phát triển,
                                                   25/1 - 1/2/2021    theo định hướng xã hội chủ nghĩa'),
('session-27',15,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                                               Đại hội lần thứ XIII (2021)
                                                                                                                                    tiếp tục đẩy mạnh toàn diện,
                                                                                                  đồng bộ công cuộc đổi mới

                                                                                   Nội dung Đại hội XIII

    Kỷ niệm 50 năm giải phóng miền Nam,          Kỷ niệm 100 năm                  Kỷ niệm 100 năm
             thống nhất đất nước                     thành lập Đảng                      Quốc khánh

            2025                    2030                    2045

        Là nước đang phát triển,                                     Là nước đang phát triển,
         có công nghiệp theo hướng                                            Trở thành nước phát triển,                                               có công nghiệp hiện đại,
         hiện đại, vượt qua mức thu                                                   thu nhập cao                                           thu nhập trung bình cao
         nhập trung bình thấp'),
('session-27',16,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
  Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

 Đại hội lần thứ XIII (2021)                                                                       Kiên định,                                                                                      Chủ nghĩa Mác - Lênin & tư tưởng Hồ Chí Minh tiếp tục đẩy mạnh toàn diện,                                             vận dụng
 đồng bộ công cuộc đổi mới                                                và phát                                                                       Mục tiêu độc lập dân tộc & CNXH                                                                                         triển
Nội dung Đại hội XIII
                                                                           Bảo đảm                                   Đảm bảo ở vị trí tối thượng
                                                                                                                          lợi ích
                                                                                     quốc gia -                                                      Trên cơ sở các nguyên tắc cơ bản của                                                                               dân tộc                                                    Hiến chương LHQ và luật pháp  QUAN                                                       quốc tế, bình đẳng, cùng có lợi
                                                                     Khơi dậy                                                                                               Khát vọng phát triển đất nước phồn vinh, hạnh phúc
                                                        mạnh mẽ
                                                                                tinh thần                                                                                                   Phát huy dân chủ XHCN, sức mạnh                                                                        yêu nước  ĐIỂM                                                                                                                   cả HTCT, con người Việt Nam
                                                                                                                Kết hợp sức                                             Nêu cao ý chí độc lập, tự chủ                                                                                      mạnh dân tộc
                                                                                                                               với sức mạnh   CHỈ                Phát huy tối đa nội lực,                                     thời đại
                                                      tích cực thu hút ngoại lực
                                                                       Tăng cường                                                                                               Nâng cao năng lực lãnh đạo, cầm quyền                                                                            xây dựng,  ĐẠO                                                                                    chỉnh đốn
                                                                             Xây dựng Đảng, Nhà nước tinh gọn, hiệu quả                                                                  Đảng'),
('session-27',17,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

Đại hội lần thứ XIII (2021)
tiếp tục đẩy mạnh toàn diện,
 đồng bộ công cuộc đổi mới

Nội dung Đại hội XIII

    6                                                Đẩy mạnh phòng chống quan liêu,                           Tiếp tục xây dựng,
                                                 tham nhũng, lãng phí, tiêu cực, lợi ích nhóm  nhiệm            chỉnh đốn Đảng,
   vụ              Nhà nước,                   Xây dựng đội ngũ đảng viên đủ phẩm chất,                         hệ thống chính trị
  trọng                                          năng lực, uy tín và ngang tầm nhiệm vụ
  tâm'),
('session-27',18,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

Đại hội lần thứ XIII (2021)
tiếp tục đẩy mạnh toàn diện,
 đồng bộ công cuộc đổi mới
                                                            Tiêm chủng đại trà vắc xinNội dung Đại hội XIII
                                                             Phục hồi kinh tế - xã hội
    6                                               Có chính sách hỗ trợ hiệu quả doanh nghiệp,                    Tập trung kiểm soát
                                                                nhất là trong nông nghiệp                         đại dịch Covid - 19,  nhiệm
                                                     Tăng cường liên kết các vùng, miền, lĩnh vực                        phát triển kinh tế   vụ                        hậu Covid                                              Đẩy mạnh nghiên cứu, chuyển giao công nghệ  trọng
                                                          Thực hiện chuyển đổi số quốc gia,
  tâm                                                             xây dựng kinh tế số, xã hội số'),
('session-27',19,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

Đại hội lần thứ XIII (2021)
tiếp tục đẩy mạnh toàn diện,
 đồng bộ công cuộc đổi mới

Nội dung Đại hội XIII

                                                 Xây dựng quân độ, công an tinh nhuệ, hiện đại    6                      Giữ vững độc lập,
                                                             Kiên quyết, kiên trì đấu tranh bảo vệ chủ                           tự chủ, tiếp tục  nhiệm
                                                                  quyền, thống nhất, toàn vẹn biển đảo                       phát huy đối ngoại,   vụ                           hội nhập quốc tế                   Giữ vững môi trường hòa bình, ổn định để
                                                                      phát triển đất nước  trọng
  tâm'),
('session-27',20,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

Đại hội lần thứ XIII (2021)
tiếp tục đẩy mạnh toàn diện,
 đồng bộ công cuộc đổi mới

Nội dung Đại hội XIII
                                                  Giữ gìn, phát huy giá trị văn hóa,
                                                            sức mạnh con người Việt Nam
    6                      Khơi dậy khát vọng             Có chính sách cụ thể phát triển văn hóa
                       phát triển đất nước                     đồng bào dân tộc thiểu số  nhiệm
                        phồn vinh,                                                Thực hiện tốt chính sách xã hội, bảo đảm   vụ                        hạnh phúc                                                  an sinh xã hội, an ninh con người  trọng                                             Nâng cao chất lượng cuộc sống, chỉ số
  tâm                                                 hạnh phúc của con người Việt Nam'),
('session-27',21,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

Đại hội lần thứ XIII (2021)
tiếp tục đẩy mạnh toàn diện,
 đồng bộ công cuộc đổi mới

Nội dung Đại hội XIII

    6                                        Tăng cường pháp chế, đảm bảo kỷ cương xã hội                     Hoàn thiện đồng bộ
                           hệ thống pháp luật,  nhiệm                                        Thực thi tinh thần "thượng tôn pháp luật"                             cơ chế, chính sách,
                           phát huy dân chủ   vụ                                                 Gương mẫu chấp hành và thực hiện
                          xã hội chủ nghĩa                                                        dân chủ xã hội chủ nghĩa  trọng
  tâm'),
('session-27',22,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
 Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

Đại hội lần thứ XIII (2021)
tiếp tục đẩy mạnh toàn diện,
 đồng bộ công cuộc đổi mới

Nội dung Đại hội XIII

    6                                    Quản lý chặt chẽ, sử dụng hợp lý, hiệu quả
                  Quản lý tài nguyên,  nhiệm                                                     Bảo vệ, cải thiện môi trường
                       bảo vệ môi trường   vụ                                            Chủ động, tích cực triển khai các giải pháp
                                                                       thích ứng biến đổi khí hậu  trọng
  tâm'),
('session-27',23,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-28',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-28',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                  khủng hoảng kinh tế - xã hội 1986 - 1996
Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                                                                    Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
              1975 - 1981                                                        hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                            Lãnh đạo công cuộc đổi mới,     Lãnh đạo cả nước xây dựng
                                                                                   đẩy mạnh công nghiệp hóa,      chủ nghĩa xã hội và bảo vệ                                                                                          hiện đại hóa và hội nhập quốc tế               Chương 3        Tổ quốc (1975 - 1986)                                                                                                           (từ năm 1986 đến nay)

 Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                           Thành tựu, kinh nghiệm của công cuộc đổi mới
  và các bước đột phá tiếp tục đổi mới kinh tế
              1982 - 1986
                                                               Nguyên nhân và tác hại của tham nhũng'),
('session-28',3,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                       Thành tựu, kinh nghiệm của công cuộc đổi mới

                      “Nền kinh tế thị trường định hướng xã hội chủ nghĩa tiếp  Thành tựu
                           tục phát triển; kinh tế vĩ mô ổn định, vững chắc hơn, các
Về phát triển kinh tế     cân đối lớn của nền kinh tế cơ bản được đảm bảo, tốc độ                                        Đại hội XIII
                       tăng trưởng duy trì ở mức khá cao; quy mô và tiềm lực nền
                         kinh tế tăng lên, chất lượng tăng trưởng được cải thiện”

      1986          1996         2008

             Bắt đầu đổi mới                                 Chấm dứt tình trạng          Ra khỏi tình trạng nước nghèo,
       Nhiệm vụ phát triển kinh tế                                      khủng hoảng kinh tế - xã hội             kém phát triển,
                  là trung tâm,                                                                                     có thu nhập trung bình
        xây dựng Đảng là then chốt'),
('session-28',4,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                       Thành tựu, kinh nghiệm của công cuộc đổi mới

  Thành tựu                                                Theo Tổng cục Thống kê

Về phát triển kinh tế                                                                                                    271.2 tỷ USD
                                                                               245.2 tỷ USD        Tốc độ tăng trưởng bình quân đạt 6%/năm
                                                              205.3 tỷ USD    Năm 2020 tăng 2.91% thuộc top cao nhất thế giới

 Thu nhập bình quân đầu người đạt 2.779 USD - Năm 2020

   Năng suất lao động giai đoạn 2016 - 2020 đạt 6%/năm'),
('session-28',5,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                       Thành tựu, kinh nghiệm của công cuộc đổi mới

  Thành tựu

Về phát triển kinh tế

      Chiến lược đề ra từ 1996 là phát triển khoa học, công nghệ , giáo dục và đào tạo
         đáp thúc đẩy mạnh mẽ sự nghiệp công nghiệp hóa, hiện đại hóa đất nước

          Chương trình phổ thông, sách giáo khoa đổi mới căn bản, toàn diện

        Quản lý, quản trị giáo dục đại học có bước đổi mới, chất lượng tăng lên.
                 Giáo dục nghề nghiệp có nhiều chuyển biến tích cực

             Nhân lực chất lượng cao tăng cả về số lượng và chất lượng'),
('session-28',6,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                       Thành tựu, kinh nghiệm của công cuộc đổi mới

 Thành tựu

Về văn hóa, xã hội
                                       Các chính sách xã hội, an sinh, dân tộc, tôn giáo phát triển
                                              Tỷ lệ bao phủ Bảo hiểm y tế trên 90%
    Xã hội                                              Tỷ lệ hộ nghèo đa chiều còn dưới 3%
                                Hoàn thành mục tiêu phát triển Thiên niên kỷ của Liên Hợp Quốc

                                         Nhiều giá trị và di sản văn hóa được bảo tồn, phát huy
                                    Văn hóa trong chính trị và kinh tế bước đầu được      1998                                                               coi trọng, phát huy hiệu quả tích cực
                                       Văn hóa gắn liền với xây dựng con người
Xây dựng nền văn hóa tiên tiến,
   đậm đà bản sắc dân tộc'),
('session-28',7,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                         Thành tựu, kinh nghiệm của công cuộc đổi mới

   Thành tựu
                          Chính trị - xã hội                                  Giữ vững và tăng cường
                                                                                       sự lãnh đạo của ĐảngVề chính trị, quốc phòng          ổn định

                     Kiên quyết bảo vệ                                                   Sự quản lý tập trung,
                   vững chắc Tổ quốc                                                     thống nhất của Nhà nước

                                                                                      Kết hợp quốc phòng với                           Xây dựng QĐND, CAND
                                                                                        kinh tế, văn hóa, xã hội                                   chính quy, tinh nhuệ'),
('session-28',8,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                        Thành tựu, kinh nghiệm của công cuộc đổi mới

  Thành tựu

Về quan hệ đối ngoại

 Tiếp tục được mở rộng, đi vào chiều sâu, tạo khung khổ
      quan hệ ổn định và bền vững với các đối tác

  Chủ động tham gia xây dựng nguyên tắc, chuẩn mực
 quốc tế trong các thể chế đa phương khu vực và toàn cầu

Xử lý đúng đắn, hiệu quả quan hệ với các nước láng giềng,
              các nước lớn, với các đối tác'),
('session-28',9,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                        Thành tựu, kinh nghiệm của công cuộc đổi mới

  Thành tựu

Về quan hệ đối ngoại'),
('session-28',10,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                        Thành tựu, kinh nghiệm của công cuộc đổi mới

   Hạn chế

Hoàn thiện thể chế; đổi mới mô hình tăng trưởng,
                                                                           An ninh quốc phòng, đối ngoại cơ cấu lại nền kinh tế; công nghiệp hóa - hiện đại
                                                                                                           còn nhiều hạn chế   hóa chưa tạo được sự chuyển biến căn bản

Đổi mới giáo dục và đào tạo chưa thực sự là động                                                Xây dựng Nhà nước pháp quyền có mặt
 lực then chốt thúc đẩy phát triển kinh tế xã hội                                                         chưa đáp ứng tốt yêu cầu phát triển

    Quản lý tài nguyên, bảo vệ môi trường                                                         Xây dựng, chỉnh đốn Đảng
              còn nhiều bất cập                                                                              còn một số hạn chế'),
('session-28',11,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                        Thành tựu, kinh nghiệm của công cuộc đổi mới

  Nguyên nhân

           Chủ quan        Nguyên                                                      Khách quan
                  là chủ yếu        nhân
                                                              Đổi mới là một sự nghiệp to lớn,   Công tác nghiên cứu lý luận, tổng kết thực tiễn
                                                                     toàn diện, lâu dài và phức tạp         chưa được quan tâm đúng mức
                                                      Tình hình thế giới - khu vực có tác động không thuận lợi
    Dự báo tình hình chậm, thiếu chính xác
                                                      Sự chống phá quyết liệt của các thế lực thù địch,
Nhận thức, phương pháp và cách chỉ đạo còn hạn chế                                                            phản động và cơ hội chính trị
     Quản lý, giáo dục, rèn luyện đảng viên
             chưa đáp ứng yêu cầu'),
('session-28',12,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                      Thành tựu, kinh nghiệm của công cuộc đổi mới

Kinh nghiệm

                        Thực hiện                          Tập trung ưu
                        nghiêm túc                                  tiên đồng bộ thể
                      quan điểm “lấy                                chế, hài hòa các
                       dân làm gốc”                          mối quan hệ      Công tác xây                                                    Phải có quyết                        Chủ động
      dựng, chỉnh đốn                                           tâm chính trị cao,                                                                                        nghiên cứu,
    Đảng phải quyết                                                 nổ lực lớn,                                                               nắm bắt, dự báo
          liệt, toàn diện,                              hành động                                                                             đúng tình hình      thường xuyên                                     quyết liệt'),
('session-28',13,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO source_pages (document_id,page_number,content) VALUES
('session-29',1,'ĐẢNG LÃNH ĐẠO CẢ NƯỚC QUÁ ĐỘ LÊN CHỦ NGHĨA XÃ HỘI
        VÀ TIẾN HÀNH CÔNG CUỘC ĐỔI MỚI
                  (TỪ 1975 ĐẾN NAY)

            Chương 3'),
('session-29',2,'Đổi mới toàn diện, đưa đất nước ra khỏi
                                                                  khủng hoảng kinh tế - xã hội 1986 - 1996
Xây dựng chủ nghĩa xã hội và bảo vệ Tổ quốc                                                                                    Tiếp tục công cuộc đổi mới, đẩy mạnh công nghiệp hóa,
              1975 - 1981                                                        hiện đại hóa và hội nhập quốc tế (từ 1996 đến nay)

                                                                            Lãnh đạo công cuộc đổi mới,     Lãnh đạo cả nước xây dựng
                                                                                   đẩy mạnh công nghiệp hóa,      chủ nghĩa xã hội và bảo vệ                                                                                          hiện đại hóa và hội nhập quốc tế               Chương 3        Tổ quốc (1975 - 1986)                                                                                                           (từ năm 1986 đến nay)

 Đại hội đại biểu toàn quốc lần thứ V của Đảng                                                             Thành tựu, kinh nghiệm của công cuộc đổi mới
  và các bước đột phá tiếp tục đổi mới kinh tế
              1982 - 1986
                                                    Nguyên nhân và tác hại của tham nhũng'),
('session-29',3,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

                                   Nguyên nhân

                               Những hạn chế                                  Hạn chế trong        Hạn chế trong                                                                       Hạn chế trong                                     trong quản lí, điều  Hạn chế trong                                                                nhận thức bổ                                hành nền kinh tế,             việc phát hiện                                                                                                công tác    chính sách                                    hoạt động của các                                                                          nhiệm, luân                                             và xử lí                                     tuyên truyền,                                      cơ quan Nhà nước,    pháp luật                                                                       chuyển cán bộ                                           tổ chức xã hội          tham nhũng                                 phổ biến'),
('session-29',4,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

 Nguyên nhân

                       Hạn chế trong việc
                                                            Chính sách không được minh bạch, đối tượng                             thực hiện các chính sách                                                               khó tiếp cận chính sách nên cần bôi trơn,...
                            của Đảng và Nhà nước

  Hạn chế trong
    chính sách
    pháp luật                                                 Sự thiếu hoàn thiện của hệ thống pháp luật
                  Hạn chế                                                           Sự chồng chéo, mâu thuẫn trong các quy định của pháp luật
                        về pháp luật
                                                              Sự bất cập, thiếu minh bạch và kém khả thi
                                                                          trong nhiều quy định của pháp luật'),
('session-29',5,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

 Nguyên nhân

         Hạn chế trong việc phân công trách nhiệm,
               quyền hạn giữa các chủ thể quản lí
                                     Hạn chế trong          Hạn chế trong việc công khai, minh bạch hóa
                                          quản lí và điều hành                       các cơ chế quản lí kinh tế
                                                nền kinh tế            Chính sách quản lí, điều hành kinh tế của
                                                                                                              Những hạn chế
             Nhà nước còn chưa thực sự hợp lí                                                                                                                                        trong quản lí, điều
                                                                                                                    hành nền kinh tế,
                                                                                                                                   hoạt động của các
                                                                                                                                            cơ quan Nhà nước,
                                                                                                                                                      tổ chức xã hội
                              Hạn chế trong
                                             cải cách hành chính'),
('session-29',6,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

 Nguyên nhân

        Hạn chế trong việc                                               Hạn chế trong hoạt động
         khuyến khích tố giác                                                            của các cơ quan phát hiện
        hành vi tham nhũng                                                         tham nhũng                                      Hạn chế trong
                                                              việc phát hiện
                                                  và xử lí
                                            tham nhũng
       Hạn chế trong hoạt                            Hạn chế trong hoạt
        động của các cơ quan                                 động của các cơ quan
            tư pháp hình sự                                           truyền thông'),
('session-29',7,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

 Nguyên nhân

                                    Hạn chế trong       Sự xuống cấp về đạo đức,                                      Tư tưởng cục bộ, địa phương,
                                          nhận thức bổ
     phẩm chất của một bộ phận                                                  bè phái trong công tác bổ                                                 nhiệm, luân
      cán bộ, công chức, viên chức                                                                   nhiệm cán bộ vẫn còn tồn tại                                               chuyển cán bộ'),
('session-29',8,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

 Nguyên nhân

                                    Hạn chế trong                                                  Hình thức        Phạm vi                                                  công tác
           thực hiện                         tuyên truyền,               tuyên truyền
                                               phổ biến

        Mới chỉ được thực hiện                                       Hình thức tuyên truyền, phổ biến, giáo
        trong nội bộ các cơ quan, tổ                                             dục phòng, chống tham nhũng
         chức, đơn vị, chưa được tiến                                           còn khá đơn điệu, chủ yếu thực hiện
         hành sâu rộng đến mọi                Nội dung tuyên truyền, phổ biến,       bằng hình thức báo cáo viên phổ biến,
            tầng lớp nhân dân                      giáo dục về phòng, chống tham                giải thích cho người nghe.
                                               nhũng còn chưa được biên soạn
                                                    cho thực sự phù hợp với các nhóm
                                                                đối tượng khác nhau'),
('session-29',9,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

   Tác hại

                                      Tác hại của
                                 tham nhũng

                      Chính                      Xã
                                    trị                                hội
                                     Kinh
                                                     tế'),
('session-29',10,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

   Tác hại                                            Chiến lược quốc gia phòng, chống tham
                                        nhũng đến năm 2020 Ban hành kèm
 Về Chính trị                                  theo Nghị quyết số 21/NQ-CP
                                           ngày 12 tháng 5 năm 2009 của CP

                              “tình hình tham nhũng vẫn diễn biến phức tạp
                trên nhiều lĩnh vực, nhất là trong quản lý, sử dụng đất đai, đầu tư xây dựng,
               cổ phần hóa doanh nghiệp nhà nước, quản lý, sử dụng vốn, tài sản nhà nước,
               gây hậu quả xấu về nhiều mặt, làm giảm sút lòng tin của nhân dân vào sự
                lãnh đạo của Đảng và sự quản lý Nhà nước, tiềm ẩn các xung đột lợi ích,
             phản kháng về xã hội, làm tăng thêm khoảng cách giàu nghèo. Tham nhũng
                  trở thành vật cản lớn cho thành công của công cuộc đổi mới, cho sức chiến
                        đấu của Đảng, đe dọa sự tồn vong của chế độ.”'),
('session-29',11,'II. Lãnh đạo công cuộc đổi mới, đẩy mạnh công nghiệp hóa, hiện đại hóa và hội nhập quốc tế (từ năm 1986 đến nay)
                     Nguyên nhân và tác hại của tham nhũng

   Tác hại

               Về Kinh tế                          Về xã hội
       Làm thất thoát những           Ảnh hưởng đến các giá trị, các
                                           chuẩn mực đạo đức và pháp luật            khoản tiền lớn

       Ảnh hưởng lớn đến môi trường          Làm xáo trộn trật tự xã hội
        kinh doanh, làm chậm tốc độ tăng
             trưởng của nền kinh tế'),
('session-29',12,'XIN CẢM ƠN!!!')
ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content;

INSERT INTO missions (slug,title,era,description,short_label,sort_order,cover_symbol,color_key) VALUES
('nhap-mon-lich-su-dang','Cánh cổng lịch sử','Nhập môn','Khởi động hành trình: đối tượng, chức năng và phương pháp học Lịch sử Đảng.','Nhập môn VNR202',0,'◈','teal'),
('ngon-lua-khoi-dau','Ngọn lửa khởi đầu','1930 – 1945','Từ sự ra đời của Đảng đến thắng lợi của Cách mạng Tháng Tám.','Hành trình khởi nguyên',1,'✦','purple'),
('bao-ve-doc-lap','Bảo vệ nền độc lập','1945 – 1954','Chính quyền non trẻ, kháng chiến chống Pháp và Điện Biên Phủ.','Ý chí kháng chiến',2,'⚡','blue'),
('non-song-lien-mot-dai','Non sông liền một dải','1954 – 1975','Các mốc đấu tranh giải phóng miền Nam, thống nhất đất nước.','Đường tới thống nhất',3,'★','amber'),
('kien-thiet-dat-nuoc','Kiến thiết đất nước','1975 – 1986','Thống nhất về mặt nhà nước và bước ngoặt tư duy đổi mới.','Bước ngoặt lịch sử',4,'◆','pink'),
('khat-vong-vuon-xa','Khát vọng vươn xa','1986 – 2007','Đổi mới, hội nhập khu vực và gia nhập thương mại toàn cầu.','Kỷ nguyên hội nhập',5,'✺','teal')
ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title,era=EXCLUDED.era,description=EXCLUDED.description,short_label=EXCLUDED.short_label,sort_order=EXCLUDED.sort_order,cover_symbol=EXCLUDED.cover_symbol,color_key=EXCLUDED.color_key;

INSERT INTO questions (id,mission_slug,position,prompt,options,correct_index,explanation,source_document_id,source_page) VALUES
('a01','ngon-lua-khoi-dau',1,'Hội nghị thành lập Đảng Cộng sản Việt Nam gắn với tháng, năm nào?','["2/1930","9/1945","7/1954","12/1986"]',0,'Slide Chương 1 giới thiệu Hội nghị thành lập Đảng và Cương lĩnh chính trị đầu tiên vào tháng 2/1930.','session-04',6),
('a02','ngon-lua-khoi-dau',2,'Ai chủ trì Hội nghị hợp nhất các tổ chức cộng sản đầu năm 1930?','["Trần Phú","Nguyễn Ái Quốc","Phan Bội Châu","Võ Nguyên Giáp"]',1,'Nguyễn Ái Quốc chủ trì Hội nghị hợp nhất, đặt nền tảng cho việc thành lập Đảng.','session-04',6),
('a03','ngon-lua-khoi-dau',3,'Phong trào Xô viết Nghệ - Tĩnh diễn ra chủ yếu trong giai đoạn nào?','["1919–1920","1945–1946","1930–1931","1959–1960"]',2,'Xô viết Nghệ - Tĩnh là đỉnh cao của phong trào cách mạng 1930–1931.','session-05',7),
('a04','ngon-lua-khoi-dau',4,'Mặt trận Việt Minh được thành lập vào năm nào?','["1930","1936","1946","1941"]',3,'Mặt trận Việt Nam Độc lập Đồng minh (Việt Minh) được thành lập năm 1941.','session-07',8),
('a05','ngon-lua-khoi-dau',5,'Sự kiện nào đánh dấu sự ra đời của nước Việt Nam Dân chủ Cộng hòa?','["Đại hội Đảng lần II","Tuyên ngôn Độc lập ngày 2/9/1945","Chiến thắng Điện Biên Phủ","Hiệp định Giơ-ne-vơ"]',1,'Ngày 2/9/1945, Chủ tịch Hồ Chí Minh đọc Tuyên ngôn Độc lập tại Quảng trường Ba Đình.','session-09',12),
('b01','bao-ve-doc-lap',1,'Cuộc Tổng tuyển cử đầu tiên bầu Quốc hội nước Việt Nam Dân chủ Cộng hòa diễn ra ngày nào?','["6/1/1946","19/12/1946","7/5/1954","2/7/1976"]',0,'Ngày 6/1/1946, nhân dân cả nước đi bầu Quốc hội khóa I.','session-11',10),
('b02','bao-ve-doc-lap',2,'Hiệp định Sơ bộ ngày 6/3/1946 được ký nhằm mục tiêu chủ yếu nào?','["Từ bỏ nền độc lập","Chấm dứt ngay mọi xung đột","Tranh thủ hòa hoãn để củng cố lực lượng","Gia nhập một liên minh quân sự"]',2,'Chủ trương hòa hoãn nhằm tránh cùng lúc đối phó nhiều lực lượng và tranh thủ thời gian chuẩn bị.','session-11',14),
('b03','bao-ve-doc-lap',3,'Lời kêu gọi Toàn quốc kháng chiến được phát đi vào ngày nào?','["2/9/1945","19/12/1946","3/2/1930","21/7/1954"]',1,'Ngày 19/12/1946 gắn với Lời kêu gọi Toàn quốc kháng chiến của Chủ tịch Hồ Chí Minh.','session-12',5),
('b04','bao-ve-doc-lap',4,'Chiến thắng Việt Bắc Thu – Đông 1947 làm thất bại kế hoạch nào của thực dân Pháp?','["Việt Nam hóa chiến tranh","Chiến tranh đặc biệt","Đánh lâu dài ngay từ đầu","Đánh nhanh, thắng nhanh"]',3,'Thất bại tại Việt Bắc khiến thực dân Pháp không thực hiện được âm mưu đánh nhanh, thắng nhanh.','session-12',10),
('b05','bao-ve-doc-lap',5,'Chiến thắng nào gắn với tiến trình đi tới Hiệp định Genève năm 1954?','["Chiến thắng Điện Biên Phủ","Chiến dịch Hồ Chí Minh","Phong trào Đồng khởi","Cách mạng Tháng Tám"]',0,'Session 13 đặt chiến thắng Điện Biên Phủ và Hiệp định Genève trong phần kết thúc cuộc kháng chiến chống Pháp.','session-13',16),
('c01','non-song-lien-mot-dai',1,'Phong trào Đồng khởi bùng nổ mạnh ở Bến Tre vào năm nào?','["1954","1960","1968","1975"]',1,'Phong trào Đồng khởi ở Bến Tre bùng nổ mạnh vào tháng 1/1960.','session-15',11),
('c02','non-song-lien-mot-dai',2,'Mặt trận Dân tộc Giải phóng miền Nam Việt Nam được thành lập ngày nào?','["3/2/1930","2/9/1945","20/12/1960","30/4/1975"]',2,'Mặt trận Dân tộc Giải phóng miền Nam Việt Nam được thành lập ngày 20/12/1960.','session-15',11),
('c03','non-song-lien-mot-dai',3,'Đàm phán Pari được nêu trong tài liệu bắt đầu vào năm nào?','["1968","1954","1975","1986"]',0,'Session 16, trang 11 ghi đàm phán Pari bắt đầu ngày 13/5/1968.','session-16',11),
('c04','non-song-lien-mot-dai',4,'Hiệp định Paris về chấm dứt chiến tranh, lập lại hòa bình ở Việt Nam được ký ngày nào?','["7/5/1954","19/12/1946","2/7/1976","27/1/1973"]',3,'Hiệp định Paris được ký vào ngày 27/1/1973.','session-17',7),
('c05','non-song-lien-mot-dai',5,'Mốc thời gian gắn với giải phóng Sài Gòn, kết thúc chiến tranh là ngày nào?','["19/8/1945","30/4/1975","2/9/1945","6/1/1946"]',1,'Ngày 30/4/1975 đánh dấu thắng lợi của Chiến dịch Hồ Chí Minh và giải phóng Sài Gòn.','session-17',13),
('d01','kien-thiet-dat-nuoc',1,'Tổng tuyển cử bầu Quốc hội chung của nước Việt Nam thống nhất diễn ra năm nào?','["1954","1973","1976","1986"]',2,'Ngày 25/4/1976, cả nước tiến hành Tổng tuyển cử bầu Quốc hội chung.','session-19',7),
('d02','kien-thiet-dat-nuoc',2,'Tên nước Cộng hòa xã hội chủ nghĩa Việt Nam được Quốc hội quyết định vào năm nào?','["1976","1945","1986","1995"]',0,'Quốc hội khóa VI quyết định tên nước Cộng hòa xã hội chủ nghĩa Việt Nam vào tháng 7/1976.','session-19',8),
('d03','kien-thiet-dat-nuoc',3,'Đại hội đại biểu toàn quốc lần thứ IV của Đảng được tổ chức vào năm nào?','["1960","1976","1982","1986"]',1,'Đại hội IV của Đảng diễn ra vào tháng 12/1976.','session-20',3),
('d04','kien-thiet-dat-nuoc',4,'Đại hội nào được xem là dấu mốc khởi xướng đường lối Đổi mới toàn diện?','["Đại hội III","Đại hội IV","Đại hội V","Đại hội VI"]',3,'Đại hội VI (tháng 12/1986) đề ra đường lối Đổi mới toàn diện đất nước.','session-22',4),
('d05','kien-thiet-dat-nuoc',5,'Một điểm quan trọng của chủ trương Đổi mới 1986 là gì?','["Dừng mọi hoạt động kinh tế đối ngoại","Chỉ tập trung thay đổi về văn hóa","Đổi mới tư duy và cơ chế quản lý kinh tế","Xóa bỏ mọi hình thức sở hữu"]',2,'Đổi mới nhấn mạnh đổi mới tư duy kinh tế, khắc phục cơ chế quản lý tập trung quan liêu bao cấp.','session-22',6),
('e01','khat-vong-vuon-xa',1,'Đại hội VI, dấu mốc mở đầu công cuộc Đổi mới, diễn ra vào năm nào?','["1975","1986","1995","2007"]',1,'Đại hội VI diễn ra tháng 12/1986, mở đầu công cuộc Đổi mới.','session-22',4),
('e02','khat-vong-vuon-xa',2,'Việt Nam chính thức gia nhập ASEAN vào năm nào?','["1995","1986","2000","2007"]',0,'Việt Nam gia nhập ASEAN vào ngày 28/7/1995.','session-22',23),
('e03','khat-vong-vuon-xa',3,'Nghị quyết 08-NQ/TW (5/2/2007) đề cập chính sách phát triển khi Việt Nam gia nhập tổ chức nào?','["ASEAN","UNESCO","WTO","Liên đoàn bóng đá thế giới"]',2,'Session 25, trang 19 nhắc đến Nghị quyết 08-NQ/TW về chủ trương, chính sách khi Việt Nam là thành viên WTO.','session-25',19),
('e04','khat-vong-vuon-xa',4,'Chủ trương kết hợp phát triển đất nước với mở rộng quan hệ quốc tế được gọi là gì?','["Đóng cửa kinh tế","Tách biệt khu vực","Tự cô lập","Hội nhập quốc tế"]',3,'Hội nhập quốc tế là quá trình chủ động tham gia, hợp tác và gắn kết với khu vực, thế giới.','session-23',10),
('e05','khat-vong-vuon-xa',5,'Về kinh tế, Đổi mới ở Việt Nam gắn với sự phát triển mô hình nào?','["Kinh tế tự cấp tự túc duy nhất","Kinh tế thị trường định hướng xã hội chủ nghĩa","Kinh tế không có trao đổi hàng hóa","Chỉ có một loại hình doanh nghiệp"]',1,'Đường lối Đổi mới từng bước hình thành và hoàn thiện mô hình kinh tế thị trường định hướng xã hội chủ nghĩa.','session-22',6),
('i01','nhap-mon-lich-su-dang',1,'Nội dung nào thuộc đối tượng nghiên cứu của môn Lịch sử Đảng Cộng sản Việt Nam?','["Cấu tạo địa chất","Ngữ pháp tiếng Anh","Cương lĩnh và đường lối của Đảng","Các định luật vật lý"]',2,'Đối tượng nghiên cứu bao gồm các sự kiện lịch sử, Cương lĩnh, đường lối, tổ chức và kinh nghiệm lãnh đạo của Đảng.','session-01',4),
('i02','nhap-mon-lich-su-dang',2,'Theo slide, chức năng nào SAU ĐÂY là một chức năng của khoa học Lịch sử Đảng?','["Chức năng dự báo thời tiết","Chức năng kế toán","Chức năng thiết kế kỹ thuật","Chức năng dự báo và phê phán"]',3,'Slide nêu ba nhóm: chức năng nhận thức, giáo dục, dự báo và phê phán.','session-01',6),
('i03','nhap-mon-lich-su-dang',3,'Chức năng nhận thức của môn học giúp người học hiểu điều gì?','["Chỉ cách vẽ bản đồ","Quy luật ra đời và phát triển của Đảng","Cách vận hành máy tính","Quy tắc bóng đá"]',1,'Chức năng nhận thức hướng tới nhận thức quy luật ra đời và phát triển của Đảng cùng vai trò lãnh đạo trong lịch sử.','session-01',7),
('i04','nhap-mon-lich-su-dang',4,'Chức năng giáo dục góp phần bồi dưỡng điều gì?','["Kiến thức thiên văn","Tinh thần yêu nước và ý chí tự cường","Kỹ năng sửa chữa động cơ","Cách phân tích biểu đồ chứng khoán"]',1,'Slide đặt tinh thần yêu nước, lý tưởng cách mạng và đạo đức cách mạng trong nhóm chức năng giáo dục.','session-01',8),
('i05','nhap-mon-lich-su-dang',5,'Chức năng dự báo và phê phán có nội dung nào?','["Chỉ ghi nhớ năm sinh","Không đánh giá sự kiện","Bỏ qua hoàn toàn quá khứ","Nhận thức quá khứ để hiểu hiện tại và dự báo tương lai"]',3,'Slide nhấn mạnh nhận thức quá khứ để hiểu hiện tại, dự báo tương lai và phê phán biểu hiện tiêu cực.','session-01',9),
('i06','nhap-mon-lich-su-dang',6,'Phương pháp lịch sử chú trọng cách tìm hiểu nào?','["Trình bày quá trình phát triển trong tính cụ thể, sinh động","Chỉ sử dụng suy đoán","Chỉ so sánh công thức","Bỏ qua trình tự lịch sử"]',0,'Phương pháp lịch sử trình bày tiến trình phát triển với những điều kiện và diễn biến cụ thể.','session-02',5),
('i07','nhap-mon-lich-su-dang',7,'Phương pháp logic chú trọng thao tác nào?','["Chỉ sắp xếp theo thứ tự ngày","Ghi chép nguyên văn mọi tài liệu","Phân tích, so sánh, tổng hợp để khái quát bản chất","Đo chiều dài di tích"]',2,'Phương pháp logic đi vào bản chất, cái phổ biến và sử dụng tư duy phân tích, so sánh, tổng hợp.','session-02',5),
('i08','nhap-mon-lich-su-dang',8,'Theo phương pháp luận sử học trong slide, tiêu chuẩn của chân lý là gì?','["Số đông mạng xã hội","Sự suy diễn","Thực tiễn","Tin đồn"]',2,'Slide nêu rõ thực tiễn là tiêu chuẩn của chân lý.','session-02',4),
('i09','nhap-mon-lich-su-dang',9,'Tính khoa học trong nghiên cứu lịch sử yêu cầu điều gì?','["Chỉ nêu cảm xúc cá nhân","Không cần kiểm tra dữ kiện","Chỉ dùng một nguồn tin không đối chiếu","Phản ánh khách quan, trung thực và có luận cứ khoa học"]',3,'Tính khoa học đòi hỏi phản ánh lịch sử khách quan, trung thực, dựa trên luận cứ khoa học.','session-02',7),
('i10','nhap-mon-lich-su-dang',10,'Giai đoạn nào gắn với Đảng lãnh đạo đấu tranh giành chính quyền?','["1930–1945","1975–1986","1986–2000","2001–2020"]',0,'Slide phân chia giai đoạn 1930–1945 với sự ra đời của Đảng và đấu tranh giải phóng dân tộc.','session-02',8),
('a06','ngon-lua-khoi-dau',6,'Theo slide, thực dân Pháp nổ súng tấn công Đà Nẵng vào thời điểm nào?','["7/5/1954","1/9/1858","2/9/1945","19/12/1946"]',1,'Ngày 1/9/1858 được ghi trong slide như mốc Pháp nổ súng tấn công Đà Nẵng.','session-03',5),
('a07','ngon-lua-khoi-dau',7,'Báo Thanh niên gắn với quá trình chuẩn bị nào của Nguyễn Ái Quốc?','["Ký Hiệp định Pari","Gia nhập ASEAN","Chuẩn bị về tổ chức và tuyên truyền cách mạng","Thành lập Quốc hội năm 1976"]',2,'Slide nhắc tới xuất bản Báo Thanh niên trong tiến trình chuẩn bị điều kiện thành lập Đảng.','session-03',19),
('a08','ngon-lua-khoi-dau',8,'Hội nghị Trung ương lần thứ nhất tháng 10/1930 thông qua văn kiện nào?','["Cương lĩnh 2011","Luận cương chính trị","Hiến pháp 1946","Hiệp định Genève"]',1,'Slide Session 5, trang 10 ghi hội nghị tháng 10/1930 thông qua Luận cương chính trị.','session-05',10),
('a09','ngon-lua-khoi-dau',9,'Phong trào dân chủ 1936–1939 nhấn mạnh yêu cầu trước mắt nào?','["Thành lập WTO","Thống nhất nhà nước năm 1976","Đổi mới quản lý kinh tế năm 1986","Tự do, dân chủ, cơm áo và hòa bình"]',3,'Chủ trương giai đoạn 1936–1939 nêu các yêu cầu dân sinh, dân chủ, hòa bình.','session-06',6),
('a10','ngon-lua-khoi-dau',10,'Hội nghị Trung ương lần thứ VIII (5/1941) họp tại đâu?','["Đà Nẵng","Pác Bó (Cao Bằng)","Hà Nội","Điện Biên"]',1,'Slide ghi rõ Hội nghị Trung ương lần thứ VIII diễn ra tại Pác Bó, Cao Bằng, tháng 5/1941.','session-07',5)
ON CONFLICT (id) DO UPDATE SET mission_slug=EXCLUDED.mission_slug,position=EXCLUDED.position,prompt=EXCLUDED.prompt,options=EXCLUDED.options,correct_index=EXCLUDED.correct_index,explanation=EXCLUDED.explanation,source_document_id=EXCLUDED.source_document_id,source_page=EXCLUDED.source_page;

INSERT INTO questions (id,mission_slug,position,prompt,options,correct_index,explanation,source_document_id,source_page) VALUES
('b06','bao-ve-doc-lap',6,'Biện pháp nào được vận động để chống nạn đói sau Cách mạng Tháng Tám?','["Chỉ dùng biện pháp quân sự","Tăng gia sản xuất và lập hũ gạo tiết kiệm","Đóng cửa mọi hoạt động sản xuất","Dừng chia sẻ lương thực"]',1,'Slide về xây dựng chính quyền 1945–1946 nêu tăng gia sản xuất, tiết kiệm và lập hũ gạo.','session-11',8),
('b07','bao-ve-doc-lap',7,'Ngày 6/1/1946 nhân dân cả nước tham gia sự kiện nào?','["Giải phóng Sài Gòn","Đại hội VI","Bầu cử Quốc hội","Ký Hiệp định Pari"]',2,'Slide Session 11, trang 10 ghi ngày 6/1/1946 nhân dân cả nước đi bầu cử.','session-11',10),
('b08','bao-ve-doc-lap',8,'Đường lối cơ bản của cuộc kháng chiến chống Pháp được nêu bằng cụm từ nào?','["Không cần hậu phương","Hạn chế sự tham gia của nhân dân","Kháng chiến, kiến quốc","Chỉ đấu tranh ngoại giao"]',2,'Slide về kinh nghiệm kháng chiến nêu đường lối cơ bản là kháng chiến, kiến quốc.','session-14',9),
('b09','bao-ve-doc-lap',9,'Kế hoạch quân sự Navarre được nêu trong slide vào năm nào?','["1975","1986","1953","1930"]',2,'Slide giai đoạn 1951–1954 ghi Kế hoạch Navarre từ tháng 5/1953.','session-13',14),
('b10','bao-ve-doc-lap',10,'Sự kiện nào được đặt cạnh Hiệp định Genève trên slide tổng kết kháng chiến chống Pháp?','["Tổng khởi nghĩa 1945","Đại hội XII","Gia nhập ASEAN","Chiến thắng Điện Biên Phủ"]',3,'Session 13, trang 16 giới thiệu chiến thắng Điện Biên Phủ và Hiệp định Genève.','session-13',16),
('c06','non-song-lien-mot-dai',6,'Tên gọi gắn với Đường 559 trong slide là gì?','["Đại lộ Thăng Long","Đường mòn Hồ Chí Minh","Đường sắt Bắc–Nam","Đường ven biển ASEAN"]',1,'Slide Session 15, trang 11 ghi Đường 559 là Đường mòn Hồ Chí Minh.','session-15',11),
('c07','non-song-lien-mot-dai',7,'Ai được nêu là Chủ tịch Mặt trận Dân tộc Giải phóng miền Nam Việt Nam?','["Đỗ Mười","Lê Duẩn","Nguyễn Hữu Thọ","Hà Huy Tập"]',2,'Slide Session 15, trang 11 ghi Nguyễn Hữu Thọ làm Chủ tịch Mặt trận.','session-15',11),
('c08','non-song-lien-mot-dai',8,'Theo slide, cách mạng miền Bắc giai đoạn này có nhiệm vụ chiến lược nào?','["Chỉ công nghiệp hóa thương mại","Khởi nghĩa năm 1930","Cải tổ Liên Xô","Cách mạng xã hội chủ nghĩa"]',3,'Slide nêu hai chiến lược: cách mạng XHCN ở miền Bắc và cách mạng dân tộc dân chủ nhân dân ở miền Nam.','session-15',13),
('c09','non-song-lien-mot-dai',9,'Theo slide, miền Nam có nhiệm vụ chiến lược nào trong giai đoạn 1954–1975?','["Cách mạng dân tộc dân chủ nhân dân","Chỉ xây dựng các nhà máy","Tham gia ASEAN","Soạn Cương lĩnh 2011"]',0,'Slide Session 15, trang 13 xác định cách mạng dân tộc dân chủ nhân dân ở miền Nam.','session-15',13),
('c10','non-song-lien-mot-dai',10,'Sự kiện ngày 30/4/1975 trên slide được gọi là gì?','["Ký Hiệp định Genève","Hội nghị Trung ương VIII","Đại hội Đảng lần thứ VI","Chiến dịch Hồ Chí Minh toàn thắng"]',3,'Session 17, trang 13 ghi ngày 30/4/1975 gắn với thắng lợi Chiến dịch Hồ Chí Minh.','session-17',13),
('d06','kien-thiet-dat-nuoc',6,'Hội nghị Hiệp thương chính trị hai miền Bắc–Nam diễn ra vào thời điểm nào?','["28/7/1995","15–21/11/1975","3–7/2/1930","12–19/1/2011"]',1,'Session 19, trang 6 nêu Hội nghị Hiệp thương chính trị từ ngày 15 đến 21/11/1975.','session-19',6),
('d07','kien-thiet-dat-nuoc',7,'Tổng tuyển cử ngày 25/4/1976 bầu Quốc hội chung với bao nhiêu đại biểu theo slide?','["158","1.198","492","333"]',2,'Session 19, trang 7 ghi 23 triệu cử tri bầu ra 492 đại biểu.','session-19',7),
('d08','kien-thiet-dat-nuoc',8,'Kỳ họp thứ nhất Quốc hội nước Việt Nam thống nhất quyết định đổi tên Sài Gòn thành gì?','["Thành phố Huế","Thành phố Đà Nẵng","Thành phố Hà Nội","Thành phố Hồ Chí Minh"]',3,'Session 19, trang 8 trình bày quyết định đổi tên Sài Gòn thành Thành phố Hồ Chí Minh.','session-19',8),
('d09','kien-thiet-dat-nuoc',9,'Đại hội đại biểu toàn quốc lần thứ V của Đảng diễn ra năm nào?','["1991","2001","1982","1976"]',2,'Slide Session 21, trang 3 ghi Đại hội V họp từ 27 đến 31/3/1982.','session-21',3),
('d10','kien-thiet-dat-nuoc',10,'Chương trình ba mục tiêu kinh tế nêu trong slide Đại hội V gồm những nhóm hàng nào?','["Chỉ hàng nhập khẩu, vàng và bất động sản","Dầu mỏ, ô tô, máy bay","Chỉ nông nghiệp","Lương thực–thực phẩm, hàng tiêu dùng, hàng xuất khẩu"]',3,'Session 21, trang 5 nêu ba chương trình: lương thực–thực phẩm, hàng tiêu dùng và hàng xuất khẩu.','session-21',5),
('e06','khat-vong-vuon-xa',6,'Đại hội VII thông qua Cương lĩnh xây dựng đất nước trong thời kỳ quá độ lên CNXH vào năm nào?','["1991","1975","1930","2016"]',0,'Session 22, trang 15 ghi Đại hội VII họp tháng 6/1991 và thông qua Cương lĩnh.','session-22',15),
('e07','khat-vong-vuon-xa',7,'Đại hội đại biểu toàn quốc lần thứ VIII diễn ra năm nào?','["2011","1945","1996","1982"]',2,'Session 23, trang 3 ghi Đại hội VIII diễn ra từ 28/6 đến 1/7/1996.','session-23',3),
('e08','khat-vong-vuon-xa',8,'Đại hội XI (2011) bổ sung và phát triển văn kiện nào?','["Luận cương 1930","Hiệp định Genève","Cương lĩnh 1991","Hiệp định Sơ bộ 1946"]',2,'Session 26, trang 5 nêu Cương lĩnh năm 2011 bổ sung, phát triển Cương lĩnh 1991.','session-26',5),
('e09','khat-vong-vuon-xa',9,'Đại hội XII của Đảng diễn ra vào năm nào?','["2016","1986","1996","2001"]',0,'Session 27, trang 3 ghi Đại hội XII diễn ra 20–28/1/2016.','session-27',3),
('e10','khat-vong-vuon-xa',10,'Theo slide về nguyên nhân tham nhũng, hạn chế nào thuộc nhóm pháp luật?','["Thiếu trang thiết bị thiên văn","Khí hậu thay đổi theo mùa","Sự khác biệt múi giờ quốc tế","Sự chồng chéo, mâu thuẫn trong các quy định pháp luật"]',3,'Session 29, trang 4 liệt kê sự chồng chéo, mâu thuẫn và thiếu minh bạch trong pháp luật.','session-29',4)
ON CONFLICT (id) DO UPDATE SET mission_slug=EXCLUDED.mission_slug,position=EXCLUDED.position,prompt=EXCLUDED.prompt,options=EXCLUDED.options,correct_index=EXCLUDED.correct_index,explanation=EXCLUDED.explanation,source_document_id=EXCLUDED.source_document_id,source_page=EXCLUDED.source_page;

INSERT INTO timeline_events (id,event_year,event_date,title,summary,period_key,sort_order,source_document_id,source_page) VALUES
('t01','1930','03.02.1930','Thành lập Đảng Cộng sản Việt Nam','Bước ngoặt lịch sử, thống nhất sự lãnh đạo cách mạng.','1930–1945',1,'session-04',6),
('t02','1931','1930–1931','Xô viết Nghệ – Tĩnh','Đỉnh cao phong trào cách mạng 1930–1931.','1930–1945',2,'session-05',7),
('t03','1941','19.05.1941','Thành lập Mặt trận Việt Minh','Tập hợp lực lượng cho sự nghiệp giải phóng dân tộc.','1930–1945',3,'session-07',8),
('t04','1945','02.09.1945','Tuyên ngôn Độc lập','Nước Việt Nam Dân chủ Cộng hòa ra đời.','1930–1945',4,'session-09',12),
('t05','1946','19.12.1946','Toàn quốc kháng chiến','Mở đầu cuộc kháng chiến toàn quốc chống thực dân Pháp.','1945–1954',5,'session-12',5),
('t06','1954','07.05.1954','Chiến thắng Điện Biên Phủ','Chiến thắng quân sự có ý nghĩa quyết định.','1945–1954',6,'session-13',16),
('t07','1960','20.12.1960','Mặt trận Dân tộc Giải phóng miền Nam','Ra đời trong phong trào đấu tranh ở miền Nam.','1954–1975',7,'session-15',11),
('t08','1973','27.01.1973','Ký Hiệp định Paris','Thỏa thuận về chấm dứt chiến tranh, lập lại hòa bình ở Việt Nam.','1954–1975',8,'session-17',7),
('t09','1975','30.04.1975','Giải phóng Sài Gòn','Kết thúc chiến tranh, mở ra thời kỳ đất nước thống nhất.','1954–1975',9,'session-17',13),
('t10','1976','02.07.1976','Tên nước CHXHCN Việt Nam','Quốc hội khóa VI quyết định tên nước và nhiều vấn đề của quốc gia thống nhất.','1975–1986',10,'session-19',8),
('t11','1986','12.1986','Đại hội VI – Khởi xướng Đổi mới','Đề ra đường lối Đổi mới toàn diện đất nước.','1975–1986',11,'session-22',4),
('t12','1995','28.07.1995','Việt Nam gia nhập ASEAN','Bước tiến quan trọng trong hội nhập khu vực.','1986–2007',12,'session-22',23),
('t13','2007','11.01.2007','Gia nhập WTO','Một dấu mốc trong tiến trình hội nhập kinh tế quốc tế.','1986–2007',13,'session-25',19)
ON CONFLICT (id) DO UPDATE SET event_year=EXCLUDED.event_year,event_date=EXCLUDED.event_date,title=EXCLUDED.title,summary=EXCLUDED.summary,period_key=EXCLUDED.period_key,sort_order=EXCLUDED.sort_order,source_document_id=EXCLUDED.source_document_id,source_page=EXCLUDED.source_page;

INSERT INTO courses (slug,code,title,description) VALUES
('vnr202','VNR202','Lịch sử Đảng Cộng sản Việt Nam','Học phần VNR202; tài liệu do người học cung cấp, gồm 29 buổi học.')
ON CONFLICT (slug) DO UPDATE SET code=EXCLUDED.code,title=EXCLUDED.title,description=EXCLUDED.description;

INSERT INTO chapters (key,course_slug,title,description,sort_order) VALUES
('intro','vnr202','Nhập môn','Đối tượng, chức năng và phương pháp nghiên cứu Lịch sử Đảng.',0),
('chapter1','vnr202','Chương 1 · Thành lập Đảng và đấu tranh giành chính quyền','Bối cảnh ra đời của Đảng và lãnh đạo phong trào cách mạng đến năm 1945.',1),
('chapter2','vnr202','Chương 2 · Kháng chiến và thống nhất đất nước','Xây dựng, bảo vệ chính quyền; các cuộc kháng chiến giai đoạn 1945–1975.',2),
('chapter3','vnr202','Chương 3 · Xây dựng đất nước và công cuộc Đổi mới','Xây dựng đất nước sau 1975, các kỳ đại hội và quá trình Đổi mới, hội nhập.',3)
ON CONFLICT (key) DO UPDATE SET course_slug=EXCLUDED.course_slug,title=EXCLUDED.title,description=EXCLUDED.description,sort_order=EXCLUDED.sort_order;

INSERT INTO lessons (id,chapter_key,document_id,session_number,title,summary,sort_order) VALUES
('lesson-01','intro','session-01',1,'Đối tượng và chức năng của môn học','Buổi 1: Đối tượng và chức năng của môn học. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',1),
('lesson-02','intro','session-02',2,'Phương pháp nghiên cứu và yêu cầu môn học','Buổi 2: Phương pháp nghiên cứu và yêu cầu môn học. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',2),
('lesson-03','chapter1','session-03',3,'Bối cảnh lịch sử và Nguyễn Ái Quốc','Buổi 3: Bối cảnh lịch sử và Nguyễn Ái Quốc. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',3),
('lesson-04','chapter1','session-04',4,'Thành lập Đảng và Cương lĩnh đầu tiên','Buổi 4: Thành lập Đảng và Cương lĩnh đầu tiên. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',4),
('lesson-05','chapter1','session-05',5,'Phong trào cách mạng 1930–1935','Buổi 5: Phong trào cách mạng 1930–1935. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',5),
('lesson-06','chapter1','session-06',6,'Phong trào dân chủ 1936–1939','Buổi 6: Phong trào dân chủ 1936–1939. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',6),
('lesson-07','chapter1','session-07',7,'Chuyển hướng chỉ đạo chiến lược 1939–1941','Buổi 7: Chuyển hướng chỉ đạo chiến lược 1939–1941. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',7),
('lesson-08','chapter1','session-08',8,'Chuẩn bị lực lượng khởi nghĩa 1941–1944','Buổi 8: Chuẩn bị lực lượng khởi nghĩa 1941–1944. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',8),
('lesson-09','chapter1','session-09',9,'Cao trào kháng Nhật và Tổng khởi nghĩa 1945','Buổi 9: Cao trào kháng Nhật và Tổng khởi nghĩa 1945. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',9),
('lesson-10','chapter1','session-10',10,'Ý nghĩa và bài học Cách mạng Tháng Tám','Buổi 10: Ý nghĩa và bài học Cách mạng Tháng Tám. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',10),
('lesson-11','chapter2','session-11',11,'Xây dựng chính quyền cách mạng 1945–1946','Buổi 11: Xây dựng chính quyền cách mạng 1945–1946. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',11),
('lesson-12','chapter2','session-12',12,'Toàn quốc kháng chiến và chiến dịch Việt Bắc','Buổi 12: Toàn quốc kháng chiến và chiến dịch Việt Bắc. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',12),
('lesson-13','chapter2','session-13',13,'Đẩy mạnh kháng chiến chống Pháp 1951–1954','Buổi 13: Đẩy mạnh kháng chiến chống Pháp 1951–1954. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',13),
('lesson-14','chapter2','session-14',14,'Ý nghĩa và kinh nghiệm kháng chiến chống Pháp','Buổi 14: Ý nghĩa và kinh nghiệm kháng chiến chống Pháp. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',14),
('lesson-15','chapter2','session-15',15,'Cách mạng hai miền 1954–1960','Buổi 15: Cách mạng hai miền 1954–1960. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',15),
('lesson-16','chapter2','session-16',16,'Kháng chiến chống Mỹ giai đoạn 1961–1968','Buổi 16: Kháng chiến chống Mỹ giai đoạn 1961–1968. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',16),
('lesson-17','chapter2','session-17',17,'Kháng chiến chống Mỹ giai đoạn 1969–1975','Buổi 17: Kháng chiến chống Mỹ giai đoạn 1969–1975. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',17),
('lesson-18','chapter2','session-18',18,'Ý nghĩa lịch sử thắng lợi năm 1975','Buổi 18: Ý nghĩa lịch sử thắng lợi năm 1975. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',18),
('lesson-19','chapter3','session-19',19,'Thống nhất đất nước về mặt nhà nước','Buổi 19: Thống nhất đất nước về mặt nhà nước. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',19),
('lesson-20','chapter3','session-20',20,'Đại hội IV và xây dựng chủ nghĩa xã hội','Buổi 20: Đại hội IV và xây dựng chủ nghĩa xã hội. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',20),
('lesson-21','chapter3','session-21',21,'Đại hội V và các bước đổi mới kinh tế','Buổi 21: Đại hội V và các bước đổi mới kinh tế. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',21),
('lesson-22','chapter3','session-22',22,'Đại hội VI và Đổi mới giai đoạn 1986–1996','Buổi 22: Đại hội VI và Đổi mới giai đoạn 1986–1996. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',22),
('lesson-23','chapter3','session-23',23,'Đại hội VIII và công nghiệp hóa','Buổi 23: Đại hội VIII và công nghiệp hóa. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',23),
('lesson-24','chapter3','session-24',24,'Đại hội IX và chiến lược phát triển','Buổi 24: Đại hội IX và chiến lược phát triển. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',24),
('lesson-25','chapter3','session-25',25,'Đại hội X và quá trình hội nhập','Buổi 25: Đại hội X và quá trình hội nhập. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',25),
('lesson-26','chapter3','session-26',26,'Đại hội XI và Cương lĩnh 2011','Buổi 26: Đại hội XI và Cương lĩnh 2011. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',26),
('lesson-27','chapter3','session-27',27,'Đại hội XII và nhiệm vụ phát triển','Buổi 27: Đại hội XII và nhiệm vụ phát triển. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',27),
('lesson-28','chapter3','session-28',28,'Thành tựu công cuộc Đổi mới','Buổi 28: Thành tựu công cuộc Đổi mới. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',28),
('lesson-29','chapter3','session-29',29,'Nguyên nhân và tác hại của tham nhũng','Buổi 29: Nguyên nhân và tác hại của tham nhũng. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.',29)
ON CONFLICT (id) DO UPDATE SET chapter_key=EXCLUDED.chapter_key,document_id=EXCLUDED.document_id,session_number=EXCLUDED.session_number,title=EXCLUDED.title,summary=EXCLUDED.summary,sort_order=EXCLUDED.sort_order;

INSERT INTO flashcards (id,lesson_id,question_id,front,back,explanation,source_document_id,source_page) VALUES
('flash-a01','lesson-04','a01','Hội nghị thành lập Đảng Cộng sản Việt Nam gắn với tháng, năm nào?','2/1930','Slide Chương 1 giới thiệu Hội nghị thành lập Đảng và Cương lĩnh chính trị đầu tiên vào tháng 2/1930.','session-04',6),
('flash-a02','lesson-04','a02','Ai chủ trì Hội nghị hợp nhất các tổ chức cộng sản đầu năm 1930?','Nguyễn Ái Quốc','Nguyễn Ái Quốc chủ trì Hội nghị hợp nhất, đặt nền tảng cho việc thành lập Đảng.','session-04',6),
('flash-a03','lesson-05','a03','Phong trào Xô viết Nghệ - Tĩnh diễn ra chủ yếu trong giai đoạn nào?','1930–1931','Xô viết Nghệ - Tĩnh là đỉnh cao của phong trào cách mạng 1930–1931.','session-05',7),
('flash-a04','lesson-07','a04','Mặt trận Việt Minh được thành lập vào năm nào?','1941','Mặt trận Việt Nam Độc lập Đồng minh (Việt Minh) được thành lập năm 1941.','session-07',8),
('flash-a05','lesson-09','a05','Sự kiện nào đánh dấu sự ra đời của nước Việt Nam Dân chủ Cộng hòa?','Tuyên ngôn Độc lập ngày 2/9/1945','Ngày 2/9/1945, Chủ tịch Hồ Chí Minh đọc Tuyên ngôn Độc lập tại Quảng trường Ba Đình.','session-09',12),
('flash-b01','lesson-11','b01','Cuộc Tổng tuyển cử đầu tiên bầu Quốc hội nước Việt Nam Dân chủ Cộng hòa diễn ra ngày nào?','6/1/1946','Ngày 6/1/1946, nhân dân cả nước đi bầu Quốc hội khóa I.','session-11',10),
('flash-b02','lesson-11','b02','Hiệp định Sơ bộ ngày 6/3/1946 được ký nhằm mục tiêu chủ yếu nào?','Tranh thủ hòa hoãn để củng cố lực lượng','Chủ trương hòa hoãn nhằm tránh cùng lúc đối phó nhiều lực lượng và tranh thủ thời gian chuẩn bị.','session-11',14),
('flash-b03','lesson-12','b03','Lời kêu gọi Toàn quốc kháng chiến được phát đi vào ngày nào?','19/12/1946','Ngày 19/12/1946 gắn với Lời kêu gọi Toàn quốc kháng chiến của Chủ tịch Hồ Chí Minh.','session-12',5),
('flash-b04','lesson-12','b04','Chiến thắng Việt Bắc Thu – Đông 1947 làm thất bại kế hoạch nào của thực dân Pháp?','Đánh nhanh, thắng nhanh','Thất bại tại Việt Bắc khiến thực dân Pháp không thực hiện được âm mưu đánh nhanh, thắng nhanh.','session-12',10),
('flash-b05','lesson-13','b05','Chiến thắng nào gắn với tiến trình đi tới Hiệp định Genève năm 1954?','Chiến thắng Điện Biên Phủ','Session 13 đặt chiến thắng Điện Biên Phủ và Hiệp định Genève trong phần kết thúc cuộc kháng chiến chống Pháp.','session-13',16),
('flash-c01','lesson-15','c01','Phong trào Đồng khởi bùng nổ mạnh ở Bến Tre vào năm nào?','1960','Phong trào Đồng khởi ở Bến Tre bùng nổ mạnh vào tháng 1/1960.','session-15',11),
('flash-c02','lesson-15','c02','Mặt trận Dân tộc Giải phóng miền Nam Việt Nam được thành lập ngày nào?','20/12/1960','Mặt trận Dân tộc Giải phóng miền Nam Việt Nam được thành lập ngày 20/12/1960.','session-15',11),
('flash-c03','lesson-16','c03','Đàm phán Pari được nêu trong tài liệu bắt đầu vào năm nào?','1968','Session 16, trang 11 ghi đàm phán Pari bắt đầu ngày 13/5/1968.','session-16',11),
('flash-c04','lesson-17','c04','Hiệp định Paris về chấm dứt chiến tranh, lập lại hòa bình ở Việt Nam được ký ngày nào?','27/1/1973','Hiệp định Paris được ký vào ngày 27/1/1973.','session-17',7),
('flash-c05','lesson-17','c05','Mốc thời gian gắn với giải phóng Sài Gòn, kết thúc chiến tranh là ngày nào?','30/4/1975','Ngày 30/4/1975 đánh dấu thắng lợi của Chiến dịch Hồ Chí Minh và giải phóng Sài Gòn.','session-17',13),
('flash-d01','lesson-19','d01','Tổng tuyển cử bầu Quốc hội chung của nước Việt Nam thống nhất diễn ra năm nào?','1976','Ngày 25/4/1976, cả nước tiến hành Tổng tuyển cử bầu Quốc hội chung.','session-19',7),
('flash-d02','lesson-19','d02','Tên nước Cộng hòa xã hội chủ nghĩa Việt Nam được Quốc hội quyết định vào năm nào?','1976','Quốc hội khóa VI quyết định tên nước Cộng hòa xã hội chủ nghĩa Việt Nam vào tháng 7/1976.','session-19',8),
('flash-d03','lesson-20','d03','Đại hội đại biểu toàn quốc lần thứ IV của Đảng được tổ chức vào năm nào?','1976','Đại hội IV của Đảng diễn ra vào tháng 12/1976.','session-20',3),
('flash-d04','lesson-22','d04','Đại hội nào được xem là dấu mốc khởi xướng đường lối Đổi mới toàn diện?','Đại hội VI','Đại hội VI (tháng 12/1986) đề ra đường lối Đổi mới toàn diện đất nước.','session-22',4),
('flash-d05','lesson-22','d05','Một điểm quan trọng của chủ trương Đổi mới 1986 là gì?','Đổi mới tư duy và cơ chế quản lý kinh tế','Đổi mới nhấn mạnh đổi mới tư duy kinh tế, khắc phục cơ chế quản lý tập trung quan liêu bao cấp.','session-22',6),
('flash-e01','lesson-22','e01','Đại hội VI, dấu mốc mở đầu công cuộc Đổi mới, diễn ra vào năm nào?','1986','Đại hội VI diễn ra tháng 12/1986, mở đầu công cuộc Đổi mới.','session-22',4),
('flash-e02','lesson-22','e02','Việt Nam chính thức gia nhập ASEAN vào năm nào?','1995','Việt Nam gia nhập ASEAN vào ngày 28/7/1995.','session-22',23),
('flash-e03','lesson-25','e03','Nghị quyết 08-NQ/TW (5/2/2007) đề cập chính sách phát triển khi Việt Nam gia nhập tổ chức nào?','WTO','Session 25, trang 19 nhắc đến Nghị quyết 08-NQ/TW về chủ trương, chính sách khi Việt Nam là thành viên WTO.','session-25',19),
('flash-e04','lesson-23','e04','Chủ trương kết hợp phát triển đất nước với mở rộng quan hệ quốc tế được gọi là gì?','Hội nhập quốc tế','Hội nhập quốc tế là quá trình chủ động tham gia, hợp tác và gắn kết với khu vực, thế giới.','session-23',10),
('flash-e05','lesson-22','e05','Về kinh tế, Đổi mới ở Việt Nam gắn với sự phát triển mô hình nào?','Kinh tế thị trường định hướng xã hội chủ nghĩa','Đường lối Đổi mới từng bước hình thành và hoàn thiện mô hình kinh tế thị trường định hướng xã hội chủ nghĩa.','session-22',6),
('flash-i01','lesson-01','i01','Nội dung nào thuộc đối tượng nghiên cứu của môn Lịch sử Đảng Cộng sản Việt Nam?','Cương lĩnh và đường lối của Đảng','Đối tượng nghiên cứu bao gồm các sự kiện lịch sử, Cương lĩnh, đường lối, tổ chức và kinh nghiệm lãnh đạo của Đảng.','session-01',4),
('flash-i02','lesson-01','i02','Theo slide, chức năng nào SAU ĐÂY là một chức năng của khoa học Lịch sử Đảng?','Chức năng dự báo và phê phán','Slide nêu ba nhóm: chức năng nhận thức, giáo dục, dự báo và phê phán.','session-01',6),
('flash-i03','lesson-01','i03','Chức năng nhận thức của môn học giúp người học hiểu điều gì?','Quy luật ra đời và phát triển của Đảng','Chức năng nhận thức hướng tới nhận thức quy luật ra đời và phát triển của Đảng cùng vai trò lãnh đạo trong lịch sử.','session-01',7),
('flash-i04','lesson-01','i04','Chức năng giáo dục góp phần bồi dưỡng điều gì?','Tinh thần yêu nước và ý chí tự cường','Slide đặt tinh thần yêu nước, lý tưởng cách mạng và đạo đức cách mạng trong nhóm chức năng giáo dục.','session-01',8),
('flash-i05','lesson-01','i05','Chức năng dự báo và phê phán có nội dung nào?','Nhận thức quá khứ để hiểu hiện tại và dự báo tương lai','Slide nhấn mạnh nhận thức quá khứ để hiểu hiện tại, dự báo tương lai và phê phán biểu hiện tiêu cực.','session-01',9),
('flash-i06','lesson-02','i06','Phương pháp lịch sử chú trọng cách tìm hiểu nào?','Trình bày quá trình phát triển trong tính cụ thể, sinh động','Phương pháp lịch sử trình bày tiến trình phát triển với những điều kiện và diễn biến cụ thể.','session-02',5),
('flash-i07','lesson-02','i07','Phương pháp logic chú trọng thao tác nào?','Phân tích, so sánh, tổng hợp để khái quát bản chất','Phương pháp logic đi vào bản chất, cái phổ biến và sử dụng tư duy phân tích, so sánh, tổng hợp.','session-02',5),
('flash-i08','lesson-02','i08','Theo phương pháp luận sử học trong slide, tiêu chuẩn của chân lý là gì?','Thực tiễn','Slide nêu rõ thực tiễn là tiêu chuẩn của chân lý.','session-02',4),
('flash-i09','lesson-02','i09','Tính khoa học trong nghiên cứu lịch sử yêu cầu điều gì?','Phản ánh khách quan, trung thực và có luận cứ khoa học','Tính khoa học đòi hỏi phản ánh lịch sử khách quan, trung thực, dựa trên luận cứ khoa học.','session-02',7),
('flash-i10','lesson-02','i10','Giai đoạn nào gắn với Đảng lãnh đạo đấu tranh giành chính quyền?','1930–1945','Slide phân chia giai đoạn 1930–1945 với sự ra đời của Đảng và đấu tranh giải phóng dân tộc.','session-02',8),
('flash-a06','lesson-03','a06','Theo slide, thực dân Pháp nổ súng tấn công Đà Nẵng vào thời điểm nào?','1/9/1858','Ngày 1/9/1858 được ghi trong slide như mốc Pháp nổ súng tấn công Đà Nẵng.','session-03',5),
('flash-a07','lesson-03','a07','Báo Thanh niên gắn với quá trình chuẩn bị nào của Nguyễn Ái Quốc?','Chuẩn bị về tổ chức và tuyên truyền cách mạng','Slide nhắc tới xuất bản Báo Thanh niên trong tiến trình chuẩn bị điều kiện thành lập Đảng.','session-03',19),
('flash-a08','lesson-05','a08','Hội nghị Trung ương lần thứ nhất tháng 10/1930 thông qua văn kiện nào?','Luận cương chính trị','Slide Session 5, trang 10 ghi hội nghị tháng 10/1930 thông qua Luận cương chính trị.','session-05',10),
('flash-a09','lesson-06','a09','Phong trào dân chủ 1936–1939 nhấn mạnh yêu cầu trước mắt nào?','Tự do, dân chủ, cơm áo và hòa bình','Chủ trương giai đoạn 1936–1939 nêu các yêu cầu dân sinh, dân chủ, hòa bình.','session-06',6),
('flash-a10','lesson-07','a10','Hội nghị Trung ương lần thứ VIII (5/1941) họp tại đâu?','Pác Bó (Cao Bằng)','Slide ghi rõ Hội nghị Trung ương lần thứ VIII diễn ra tại Pác Bó, Cao Bằng, tháng 5/1941.','session-07',5)
ON CONFLICT (id) DO UPDATE SET lesson_id=EXCLUDED.lesson_id,question_id=EXCLUDED.question_id,front=EXCLUDED.front,back=EXCLUDED.back,explanation=EXCLUDED.explanation,source_document_id=EXCLUDED.source_document_id,source_page=EXCLUDED.source_page;

INSERT INTO flashcards (id,lesson_id,question_id,front,back,explanation,source_document_id,source_page) VALUES
('flash-b06','lesson-11','b06','Biện pháp nào được vận động để chống nạn đói sau Cách mạng Tháng Tám?','Tăng gia sản xuất và lập hũ gạo tiết kiệm','Slide về xây dựng chính quyền 1945–1946 nêu tăng gia sản xuất, tiết kiệm và lập hũ gạo.','session-11',8),
('flash-b07','lesson-11','b07','Ngày 6/1/1946 nhân dân cả nước tham gia sự kiện nào?','Bầu cử Quốc hội','Slide Session 11, trang 10 ghi ngày 6/1/1946 nhân dân cả nước đi bầu cử.','session-11',10),
('flash-b08','lesson-14','b08','Đường lối cơ bản của cuộc kháng chiến chống Pháp được nêu bằng cụm từ nào?','Kháng chiến, kiến quốc','Slide về kinh nghiệm kháng chiến nêu đường lối cơ bản là kháng chiến, kiến quốc.','session-14',9),
('flash-b09','lesson-13','b09','Kế hoạch quân sự Navarre được nêu trong slide vào năm nào?','1953','Slide giai đoạn 1951–1954 ghi Kế hoạch Navarre từ tháng 5/1953.','session-13',14),
('flash-b10','lesson-13','b10','Sự kiện nào được đặt cạnh Hiệp định Genève trên slide tổng kết kháng chiến chống Pháp?','Chiến thắng Điện Biên Phủ','Session 13, trang 16 giới thiệu chiến thắng Điện Biên Phủ và Hiệp định Genève.','session-13',16),
('flash-c06','lesson-15','c06','Tên gọi gắn với Đường 559 trong slide là gì?','Đường mòn Hồ Chí Minh','Slide Session 15, trang 11 ghi Đường 559 là Đường mòn Hồ Chí Minh.','session-15',11),
('flash-c07','lesson-15','c07','Ai được nêu là Chủ tịch Mặt trận Dân tộc Giải phóng miền Nam Việt Nam?','Nguyễn Hữu Thọ','Slide Session 15, trang 11 ghi Nguyễn Hữu Thọ làm Chủ tịch Mặt trận.','session-15',11),
('flash-c08','lesson-15','c08','Theo slide, cách mạng miền Bắc giai đoạn này có nhiệm vụ chiến lược nào?','Cách mạng xã hội chủ nghĩa','Slide nêu hai chiến lược: cách mạng XHCN ở miền Bắc và cách mạng dân tộc dân chủ nhân dân ở miền Nam.','session-15',13),
('flash-c09','lesson-15','c09','Theo slide, miền Nam có nhiệm vụ chiến lược nào trong giai đoạn 1954–1975?','Cách mạng dân tộc dân chủ nhân dân','Slide Session 15, trang 13 xác định cách mạng dân tộc dân chủ nhân dân ở miền Nam.','session-15',13),
('flash-c10','lesson-17','c10','Sự kiện ngày 30/4/1975 trên slide được gọi là gì?','Chiến dịch Hồ Chí Minh toàn thắng','Session 17, trang 13 ghi ngày 30/4/1975 gắn với thắng lợi Chiến dịch Hồ Chí Minh.','session-17',13),
('flash-d06','lesson-19','d06','Hội nghị Hiệp thương chính trị hai miền Bắc–Nam diễn ra vào thời điểm nào?','15–21/11/1975','Session 19, trang 6 nêu Hội nghị Hiệp thương chính trị từ ngày 15 đến 21/11/1975.','session-19',6),
('flash-d07','lesson-19','d07','Tổng tuyển cử ngày 25/4/1976 bầu Quốc hội chung với bao nhiêu đại biểu theo slide?','492','Session 19, trang 7 ghi 23 triệu cử tri bầu ra 492 đại biểu.','session-19',7),
('flash-d08','lesson-19','d08','Kỳ họp thứ nhất Quốc hội nước Việt Nam thống nhất quyết định đổi tên Sài Gòn thành gì?','Thành phố Hồ Chí Minh','Session 19, trang 8 trình bày quyết định đổi tên Sài Gòn thành Thành phố Hồ Chí Minh.','session-19',8),
('flash-d09','lesson-21','d09','Đại hội đại biểu toàn quốc lần thứ V của Đảng diễn ra năm nào?','1982','Slide Session 21, trang 3 ghi Đại hội V họp từ 27 đến 31/3/1982.','session-21',3),
('flash-d10','lesson-21','d10','Chương trình ba mục tiêu kinh tế nêu trong slide Đại hội V gồm những nhóm hàng nào?','Lương thực–thực phẩm, hàng tiêu dùng, hàng xuất khẩu','Session 21, trang 5 nêu ba chương trình: lương thực–thực phẩm, hàng tiêu dùng và hàng xuất khẩu.','session-21',5),
('flash-e06','lesson-22','e06','Đại hội VII thông qua Cương lĩnh xây dựng đất nước trong thời kỳ quá độ lên CNXH vào năm nào?','1991','Session 22, trang 15 ghi Đại hội VII họp tháng 6/1991 và thông qua Cương lĩnh.','session-22',15),
('flash-e07','lesson-23','e07','Đại hội đại biểu toàn quốc lần thứ VIII diễn ra năm nào?','1996','Session 23, trang 3 ghi Đại hội VIII diễn ra từ 28/6 đến 1/7/1996.','session-23',3),
('flash-e08','lesson-26','e08','Đại hội XI (2011) bổ sung và phát triển văn kiện nào?','Cương lĩnh 1991','Session 26, trang 5 nêu Cương lĩnh năm 2011 bổ sung, phát triển Cương lĩnh 1991.','session-26',5),
('flash-e09','lesson-27','e09','Đại hội XII của Đảng diễn ra vào năm nào?','2016','Session 27, trang 3 ghi Đại hội XII diễn ra 20–28/1/2016.','session-27',3),
('flash-e10','lesson-29','e10','Theo slide về nguyên nhân tham nhũng, hạn chế nào thuộc nhóm pháp luật?','Sự chồng chéo, mâu thuẫn trong các quy định pháp luật','Session 29, trang 4 liệt kê sự chồng chéo, mâu thuẫn và thiếu minh bạch trong pháp luật.','session-29',4)
ON CONFLICT (id) DO UPDATE SET lesson_id=EXCLUDED.lesson_id,question_id=EXCLUDED.question_id,front=EXCLUDED.front,back=EXCLUDED.back,explanation=EXCLUDED.explanation,source_document_id=EXCLUDED.source_document_id,source_page=EXCLUDED.source_page;

INSERT INTO achievements (code,name,description,icon_name,required_xp) VALUES
('first_steps','Những bước chân đầu tiên','Hoàn thành chiến dịch đầu tiên.','footprints',NULL),
('hundred_xp','Nhà thám hiểm','Đạt tối thiểu 100 điểm XP.','compass',100),
('five_hundred_xp','Nhà sử học trẻ','Đạt tối thiểu 500 điểm XP.','graduation-cap',500),
('thousand_xp','Bậc thầy lịch sử','Đạt tối thiểu 1000 điểm XP.','trophy',1000)
ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,icon_name=EXCLUDED.icon_name,required_xp=EXCLUDED.required_xp;

COMMIT;

SELECT 'source_documents' AS dataset,COUNT(*) AS rows FROM source_documents UNION ALL SELECT 'source_pages',COUNT(*) FROM source_pages UNION ALL SELECT 'chapters',COUNT(*) FROM chapters UNION ALL SELECT 'lessons',COUNT(*) FROM lessons UNION ALL SELECT 'missions',COUNT(*) FROM missions UNION ALL SELECT 'questions',COUNT(*) FROM questions UNION ALL SELECT 'flashcards',COUNT(*) FROM flashcards UNION ALL SELECT 'timeline_events',COUNT(*) FROM timeline_events;
