import 'dotenv/config';
import pg from 'pg';
const uri=process.env.DIRECT_URL||process.env.DATABASE_URL;
if(!uri){ console.error('Thiếu DATABASE_URL trong .env');process.exit(1); }
const client=new pg.Client({connectionString:uri,connectionTimeoutMillis:20000});
const names=['courses','chapters','lessons','source_documents','source_pages','missions','questions','flashcards','timeline_events','achievements','players','game_sessions','session_answers','mission_progress'];
try{
  await client.connect();
  console.log('KẾT QUẢ DATABASE NEON');
  for(const name of names){
    const result=await client.query(`SELECT COUNT(*)::integer AS total FROM ${name}`);
    console.log(`${name.padEnd(22)} ${result.rows[0].total}`);
  }
  const {rows:[r]}=await client.query(`
    SELECT (SELECT COUNT(*) FROM questions q
            LEFT JOIN source_pages p ON p.document_id=q.source_document_id AND p.page_number=q.source_page
            WHERE q.source_document_id IS NOT NULL AND p.document_id IS NULL)::integer AS bad_question_sources,
           (SELECT COUNT(*) FROM lessons l LEFT JOIN source_documents d ON d.id=l.document_id WHERE d.id IS NULL)::integer AS bad_lessons,
           (SELECT COUNT(*) FROM flashcards f LEFT JOIN lessons l ON l.id=f.lesson_id WHERE l.id IS NULL)::integer AS bad_flashcards
  `);
  if(r.bad_question_sources||r.bad_lessons||r.bad_flashcards) throw new Error('Có tham chiếu nguồn/buổi học không hợp lệ: '+JSON.stringify(r));
  console.log('✓ Kiểm tra khóa ngoại nguồn: hợp lệ.');
} catch(e) { console.error('✗ '+e.message); process.exitCode=1; }
finally{await client.end().catch(()=>{});}
