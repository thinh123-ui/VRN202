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
