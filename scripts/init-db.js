import 'dotenv/config';
import { readFile } from 'node:fs/promises';
import pg from 'pg';
import { missions, sourcedQuestions, events } from './seed-data.js';
import { course, chapters, buildLessons, buildFlashcards, achievements } from './curriculum-data.js';

// Seed tài liệu cục bộ (PDF của bạn đã được trích xuất theo từng trang).
const documents = JSON.parse(await readFile(new URL('../data/source-sessions.json', import.meta.url), 'utf8'));
const connectionString = process.env.DIRECT_URL || process.env.DATABASE_URL;
if (!connectionString) {
  console.error('Thiếu DATABASE_URL. Tạo Neon project, lấy connection string, rồi thêm vào file .env.');
  process.exit(1);
}

const client = new pg.Client({ connectionString, connectionTimeoutMillis: 20000 });
try {
  await client.connect();
  console.log('✓ Đã kết nối PostgreSQL / Neon');
  await client.query(await readFile(new URL('../sql/schema.sql', import.meta.url), 'utf8'));
  console.log('✓ Đã tạo/kiểm tra 19 bảng');
  await client.query('BEGIN');
  for (const d of documents) {
    await client.query(`
      INSERT INTO source_documents
        (id,session_number,chapter_key,chapter_label,title,file_name,file_path,file_sha256,page_count)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
      ON CONFLICT (id) DO UPDATE SET session_number=EXCLUDED.session_number,
        chapter_key=EXCLUDED.chapter_key,chapter_label=EXCLUDED.chapter_label,title=EXCLUDED.title,
        file_name=EXCLUDED.file_name,file_path=EXCLUDED.file_path,
        file_sha256=EXCLUDED.file_sha256,page_count=EXCLUDED.page_count
    `, [d.id,d.sessionNumber,d.chapterKey,d.chapterLabel,d.title,d.fileName,d.filePath,d.sha256,d.pageCount]);
    // Nạp nhiều trang bằng một truy vấn; lặp db:init không tạo bản ghi trùng.
    await client.query(`
      INSERT INTO source_pages(document_id,page_number,content)
      SELECT $1, x.page_number, x.content
      FROM jsonb_to_recordset($2::jsonb) AS x(page_number smallint,content text)
      ON CONFLICT (document_id,page_number) DO UPDATE SET content=EXCLUDED.content
    `, [d.id, JSON.stringify(d.pages.map(p => ({page_number:p.pageNumber,content:p.content})))]);
  }
  for (const m of missions) {
    await client.query(`
      INSERT INTO missions (slug,title,era,description,short_label,sort_order,cover_symbol,color_key)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
      ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title, era=EXCLUDED.era,
      description=EXCLUDED.description, short_label=EXCLUDED.short_label,
      sort_order=EXCLUDED.sort_order, cover_symbol=EXCLUDED.cover_symbol, color_key=EXCLUDED.color_key
    `, [m.slug,m.title,m.era,m.description,m.shortLabel,m.sortOrder,m.symbol,m.color]);
  }
  for (const q of sourcedQuestions) {
    await client.query(`
      INSERT INTO questions (id,mission_slug,position,prompt,options,correct_index,explanation,source_document_id,source_page)
      VALUES ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9)
      ON CONFLICT (id) DO UPDATE SET mission_slug=EXCLUDED.mission_slug, position=EXCLUDED.position,
      prompt=EXCLUDED.prompt, options=EXCLUDED.options, correct_index=EXCLUDED.correct_index,
      explanation=EXCLUDED.explanation,source_document_id=EXCLUDED.source_document_id,
      source_page=EXCLUDED.source_page
    `, [q.id,q.mission,q.position,q.prompt,JSON.stringify(q.options),q.correct,q.explanation,q.sourceDoc,q.sourcePage]);
  }
  for (const e of events) {
    await client.query(`
      INSERT INTO timeline_events (id,event_year,event_date,title,summary,period_key,sort_order,source_document_id,source_page)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
      ON CONFLICT (id) DO UPDATE SET event_year=EXCLUDED.event_year,event_date=EXCLUDED.event_date,
      title=EXCLUDED.title,summary=EXCLUDED.summary,period_key=EXCLUDED.period_key,
      sort_order=EXCLUDED.sort_order,source_document_id=EXCLUDED.source_document_id,source_page=EXCLUDED.source_page
    `, e);
  }
  // Nạp môn học -> chương -> buổi học -> thẻ ghi nhớ (giữ nguyên tiến độ cũ).
  await client.query(`
    INSERT INTO courses (slug,code,title,description) VALUES ($1,$2,$3,$4)
    ON CONFLICT (slug) DO UPDATE SET title=EXCLUDED.title,description=EXCLUDED.description
  `, [course.slug,course.code,course.title,course.description]);
  for (const ch of chapters) {
    await client.query(`
      INSERT INTO chapters (key,course_slug,title,description,sort_order)
      VALUES ($1,$2,$3,$4,$5)
      ON CONFLICT (key) DO UPDATE SET title=EXCLUDED.title,
      description=EXCLUDED.description,sort_order=EXCLUDED.sort_order
    `, [ch.key,course.slug,ch.title,ch.description,ch.sortOrder]);
  }
  const lessons = buildLessons(documents);
  for (const item of lessons) {
    await client.query(`
      INSERT INTO lessons (id,chapter_key,document_id,session_number,title,summary,sort_order)
      VALUES ($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT (id) DO UPDATE SET chapter_key=EXCLUDED.chapter_key,
      document_id=EXCLUDED.document_id,session_number=EXCLUDED.session_number,
      title=EXCLUDED.title,summary=EXCLUDED.summary,sort_order=EXCLUDED.sort_order,
      updated_at=NOW()
    `,[item.id,item.chapterKey,item.documentId,item.sessionNumber,item.title,item.summary,item.sortOrder]);
  }
  const flashcards = buildFlashcards(sourcedQuestions);
  for (const card of flashcards) {
    await client.query(`
      INSERT INTO flashcards (id,lesson_id,question_id,front,back,explanation,source_document_id,source_page)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
      ON CONFLICT (id) DO UPDATE SET lesson_id=EXCLUDED.lesson_id,
      question_id=EXCLUDED.question_id,front=EXCLUDED.front,back=EXCLUDED.back,
      explanation=EXCLUDED.explanation,source_document_id=EXCLUDED.source_document_id,
      source_page=EXCLUDED.source_page
    `,[card.id,card.lessonId,card.questionId,card.front,card.back,card.explanation,card.sourceDocumentId,card.sourcePage]);
  }
  for (const a of achievements) {
    await client.query(`
      INSERT INTO achievements (code,name,description,icon_name,required_xp)
      VALUES ($1,$2,$3,$4,$5)
      ON CONFLICT (code) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,
      icon_name=EXCLUDED.icon_name,required_xp=EXCLUDED.required_xp
    `,[a.code,a.name,a.description,a.icon,a.requiredXp]);
  }
  await client.query('COMMIT');
  console.log(`✓ Đã nạp ${documents.length} tài liệu, ${documents.reduce((a,d)=>a+d.pages.length,0)} trang nội dung.`);
  console.log(`✓ Đã nạp ${chapters.length} chương, ${lessons.length} buổi, ${flashcards.length} flashcards, ${achievements.length} loại huy hiệu.`);
  console.log(`✓ Đã nạp ${missions.length} chiến dịch, ${sourcedQuestions.length} câu hỏi, ${events.length} sự kiện.`);
  console.log('✓ Hoàn tất! Chạy npm run dev.');
} catch (error) {
  try { await client.query('ROLLBACK'); } catch {}
  console.error('Không thể khởi tạo database:', error.message);
  process.exitCode = 1;
} finally {
  await client.end().catch(() => {});
}
