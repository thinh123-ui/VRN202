// Xuất một file SQL độc lập để dán vào Neon SQL Editor hoặc chạy bằng psql.
// Dữ liệu SQL được biên dịch từ cùng nguồn với npm run db:init để tránh lệch phiên bản.
import { readFile, writeFile } from 'node:fs/promises';
import { missions, sourcedQuestions, events } from './seed-data.js';
import { course, chapters, buildLessons, buildFlashcards, achievements } from './curriculum-data.js';
const documents=JSON.parse(await readFile(new URL('../data/source-sessions.json',import.meta.url),'utf8'));
const schema=await readFile(new URL('../sql/schema.sql',import.meta.url),'utf8');
const literal = (x) => x===null||x===undefined ? 'NULL' : typeof x==='number' ? String(x) : `'${String(x).replace(/'/g,"''")}'`;
const values = (v) => '('+v.map(literal).join(',')+')';
const sql=[];
sql.push('-- VNR202 QUEST: FULL NEON POSTGRESQL DATABASE\n-- 29 PDF / 435 pages / 4 chapters / 29 lessons / 6 missions / 60 questions / 60 flashcards / 13 events\n-- SAFE: ON CONFLICT UPSERT; does not delete players or game history\nBEGIN;');
sql.push(schema);
function insert(table, cols, data, pk, update){
 const names=cols.join(',');
 const updates=(update||cols.filter(c=>c!==pk)).map(c=>`${c}=EXCLUDED.${c}`).join(',');
 for(let i=0;i<data.length;i+=40){
  const piece=data.slice(i,i+40);
  sql.push(`INSERT INTO ${table} (${names}) VALUES\n${piece.map(values).join(',\n')}\nON CONFLICT (${pk}) DO UPDATE SET ${updates};`);
 }
}
insert('source_documents', ['id','session_number','chapter_key','chapter_label','title','file_name','file_path','file_sha256','page_count'],
  documents.map(d=>[d.id,d.sessionNumber,d.chapterKey,d.chapterLabel,d.title,d.fileName,d.filePath,d.sha256,d.pageCount]),'id');
// ON CONFLICT composite key: separate statement per doc for clarity and easier reruns.
for(const d of documents){
 const rows=d.pages.map(p=>[d.id,p.pageNumber,p.content]);
 insert('source_pages',['document_id','page_number','content'],rows,'document_id,page_number',['content']);
}
insert('missions',['slug','title','era','description','short_label','sort_order','cover_symbol','color_key'],
 missions.map(m=>[m.slug,m.title,m.era,m.description,m.shortLabel,m.sortOrder,m.symbol,m.color]),'slug');
insert('questions',['id','mission_slug','position','prompt','options','correct_index','explanation','source_document_id','source_page'],
 sourcedQuestions.map(q=>[q.id,q.mission,q.position,q.prompt,JSON.stringify(q.options),q.correct,q.explanation,q.sourceDoc,q.sourcePage]),'id');
insert('timeline_events',['id','event_year','event_date','title','summary','period_key','sort_order','source_document_id','source_page'],events,'id');

insert('courses',['slug','code','title','description'],
 [[course.slug,course.code,course.title,course.description]],'slug');
insert('chapters',['key','course_slug','title','description','sort_order'],
 chapters.map(c=>[c.key,course.slug,c.title,c.description,c.sortOrder]),'key');
insert('lessons',['id','chapter_key','document_id','session_number','title','summary','sort_order'],
 buildLessons(documents).map(l=>[l.id,l.chapterKey,l.documentId,l.sessionNumber,l.title,l.summary,l.sortOrder]),'id');
insert('flashcards',['id','lesson_id','question_id','front','back','explanation','source_document_id','source_page'],
 buildFlashcards(sourcedQuestions).map(f=>[f.id,f.lessonId,f.questionId,f.front,f.back,f.explanation,f.sourceDocumentId,f.sourcePage]),'id');
insert('achievements',['code','name','description','icon_name','required_xp'],
 achievements.map(a=>[a.code,a.name,a.description,a.icon,a.requiredXp]),'code');

sql.push('COMMIT;');
sql.push("SELECT 'source_documents' AS dataset,COUNT(*) AS rows FROM source_documents UNION ALL SELECT 'source_pages',COUNT(*) FROM source_pages UNION ALL SELECT 'chapters',COUNT(*) FROM chapters UNION ALL SELECT 'lessons',COUNT(*) FROM lessons UNION ALL SELECT 'missions',COUNT(*) FROM missions UNION ALL SELECT 'questions',COUNT(*) FROM questions UNION ALL SELECT 'flashcards',COUNT(*) FROM flashcards UNION ALL SELECT 'timeline_events',COUNT(*) FROM timeline_events;");
const out=new URL('../sql/neon-complete.sql',import.meta.url);
await writeFile(out,sql.join('\n\n')+'\n','utf8');
console.log('Generated sql/neon-complete.sql');
