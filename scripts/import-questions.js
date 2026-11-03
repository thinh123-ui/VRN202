// Dùng: npm run db:import:questions -- data/questions-import-template.json
// Import tất cả câu hỏi mới bằng transaction; mã SQL dùng tham số để tránh SQL injection.
import 'dotenv/config';
import pg from 'pg';
import { readFile } from 'node:fs/promises';

const file = process.argv[2];
if (!file) { console.error('Cần đường dẫn file JSON, ví dụ: data/questions-import-template.json'); process.exit(1); }
const uri = process.env.DIRECT_URL || process.env.DATABASE_URL;
if (!uri) { console.error('Thiếu DATABASE_URL trong .env.'); process.exit(1); }
const questions = JSON.parse(await readFile(file,'utf8'));
if (!Array.isArray(questions) || !questions.length) throw new Error('File cần chứa một mảng câu hỏi không rỗng.');
function assertQuestion(q, i) {
  const err = m => { throw new Error(`Câu hỏi #${i+1}: ${m}`); };
  if (!q || typeof q !== 'object') err('Định dạng không hợp lệ.');
  for(const f of ['id','missionSlug','prompt','explanation','sourceDocumentId']) {
    if (typeof q[f]!=='string' || !q[f].trim()) err(`Thiếu ${f}.`);
  }
  if (!/^[a-zA-Z0-9_-]{3,80}$/.test(q.id)) err('id chỉ dùng chữ, số, gạch dưới hoặc gạch ngang.');
  if (!Array.isArray(q.options) || q.options.length!==4 || q.options.some(v=>typeof v!=='string'||v.trim().length<2) || new Set(q.options).size!==4) err('options cần 4 đáp án khác nhau.');
  if (!Number.isInteger(q.correctIndex) || q.correctIndex<0 || q.correctIndex>3) err('correctIndex phải từ 0 đến 3.');
  if (!Number.isInteger(q.position) || q.position<1 || q.position>32767) err('position phải là số nguyên dương.');
  if (!Number.isInteger(q.sourcePage) || q.sourcePage<1) err('sourcePage phải là số trang PDF gốc.');
  if (!['easy','medium','hard'].includes(q.difficulty||'medium')) err('difficulty phải là easy/medium/hard.');
  if(q.prompt.trim().length<10 || q.explanation.trim().length<10) err('Câu hỏi hoặc giải thích quá ngắn.');
}
questions.forEach(assertQuestion);
if(new Set(questions.map(q=>q.id)).size!==questions.length) throw new Error('ID câu hỏi bị trùng trong file JSON.');
const client = new pg.Client({connectionString:uri,connectionTimeoutMillis:20000});
try {
  await client.connect();
  await client.query('BEGIN');
  let inserted=0;
  for(const q of questions) {
    const source=(await client.query('SELECT 1 FROM source_pages WHERE document_id=$1 AND page_number=$2',[q.sourceDocumentId,q.sourcePage])).rowCount;
    if(!source) throw new Error(`${q.id}: không có trang ${q.sourcePage} của ${q.sourceDocumentId}.`);
    const result=await client.query(`
      INSERT INTO questions (id,mission_slug,position,prompt,options,correct_index,explanation,
        source_document_id,source_page,difficulty,review_status)
      VALUES ($1,$2,$3,$4,$5::jsonb,$6,$7,$8,$9,$10,'review_needed')
      ON CONFLICT (id) DO NOTHING
      RETURNING id
    `,[q.id,q.missionSlug,q.position,q.prompt,JSON.stringify(q.options),q.correctIndex,q.explanation,
       q.sourceDocumentId,q.sourcePage,q.difficulty||'medium']);
    if(!result.rowCount) throw new Error(`${q.id}: đã tồn tại. Hãy chọn id mới; script không ghi đè câu cũ.`);
    inserted++;
    const lessonId='lesson-'+q.sourceDocumentId.slice(-2);
    await client.query(`
      INSERT INTO flashcards (id,lesson_id,question_id,front,back,explanation,source_document_id,source_page)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
    `,[`flash-${q.id}`,lessonId,q.id,q.prompt,q.options[q.correctIndex],q.explanation,q.sourceDocumentId,q.sourcePage]);
  }
  await client.query('COMMIT');
  console.log(`✓ Đã nhập ${inserted} câu hỏi và ${inserted} flashcard. Trạng thái: review_needed.`);
} catch (e) {
  await client.query('ROLLBACK').catch(()=>{});
  console.error('✗ Không nhập được câu hỏi:',e.message);
  process.exitCode=1;
} finally { await client.end().catch(()=>{}); }
