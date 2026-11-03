import express from 'express';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { db, requireDb } from './db.js';
import { calculateReward } from './scoring.js';

const app = express();
const PORT = Number(process.env.PORT || 4000);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
app.disable('x-powered-by');
app.use(express.json({ limit: '12kb' }));
app.use('/api', requireDb);

const docIdPattern = /^session-\d{2,3}$/;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const validUuid = (value) => typeof value === 'string' && uuidPattern.test(value);
const fail = (message, status = 400) => { const err = new Error(message); err.status = status; throw err; };
const asyncRoute = (fn) => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);

async function missionAccess(client, playerId, missionSlug) {
  const { rows: missions } = await client.query('SELECT slug, sort_order FROM missions ORDER BY sort_order');
  const index = missions.findIndex((item) => item.slug === missionSlug);
  if (index < 0) fail('Không tìm thấy chiến dịch.', 404);
  if (index === 0) return true;
  const { rowCount } = await client.query(
    'SELECT 1 FROM mission_progress WHERE player_id = $1 AND mission_slug = $2',
    [playerId, missions[index - 1].slug]
  );
  return rowCount > 0;
}

app.get('/api/health', asyncRoute(async (_req, res) => {
  const { rows } = await db.query('SELECT now() AS server_time');
  res.json({ ok: true, serverTime: rows[0].server_time });
}));

app.post('/api/players', asyncRoute(async (req, res) => {
  const nickname = typeof req.body?.nickname === 'string' ? req.body.nickname.trim().replace(/\s+/g, ' ') : '';
  if (nickname.length < 2 || nickname.length > 32) fail('Tên người chơi phải có từ 2 đến 32 ký tự.');
  const avatar = ['astronaut', 'bolt', 'crown', 'star'].includes(req.body?.avatar) ? req.body.avatar : 'astronaut';
  const { rows } = await db.query(
    'INSERT INTO players (nickname, avatar_key) VALUES ($1, $2) RETURNING id, nickname, avatar_key, xp, coins',
    [nickname, avatar]
  );
  res.status(201).json({ player: rows[0] });
}));

app.get('/api/overview', asyncRoute(async (req, res) => {
  const playerId = req.query.playerId;
  if (playerId && !validUuid(playerId)) fail('Mã người chơi không hợp lệ.');
  let player = null;
  let progress = [];
  if (playerId) {
    const playerResult = await db.query('SELECT id, nickname, avatar_key, xp, coins, created_at FROM players WHERE id = $1', [playerId]);
    player = playerResult.rows[0] ?? null;
    if (player) {
      progress = (await db.query('SELECT mission_slug, best_correct, attempts FROM mission_progress WHERE player_id = $1', [playerId])).rows;
    }
  }
  const missionRows = (await db.query(`
    SELECT m.slug, m.title, m.era, m.description, m.short_label, m.sort_order, m.cover_symbol, m.color_key,
           COUNT(q.id)::integer AS question_count
    FROM missions m LEFT JOIN questions q ON q.mission_slug = m.slug
    GROUP BY m.slug ORDER BY m.sort_order
  `)).rows;
  const progressMap = new Map(progress.map((p) => [p.mission_slug, p]));
  const missions = missionRows.map((m, i) => ({
    ...m,
    unlocked: i === 0 || progressMap.has(missionRows[i - 1].slug),
    completed: progressMap.has(m.slug),
    bestCorrect: progressMap.get(m.slug)?.best_correct ?? 0,
    attempts: progressMap.get(m.slug)?.attempts ?? 0
  }));
  const leaderboard = (await db.query(`
    SELECT id, nickname, avatar_key, xp, coins,
           (SELECT COUNT(*)::integer FROM mission_progress WHERE player_id = players.id) AS missions_done
    FROM players ORDER BY xp DESC, created_at ASC, id ASC LIMIT 12
  `)).rows;
  let stats = { completed: 0, totalCorrect: 0, totalAnswers: 0, accuracy: 0, rank: null };
  if (player) {
    const s = (await db.query(`
      SELECT COUNT(DISTINCT gs.mission_slug) FILTER (WHERE gs.completed_at IS NOT NULL)::integer AS completed,
             COUNT(sa.question_id)::integer AS total_answers,
             COUNT(sa.question_id) FILTER (WHERE sa.is_correct)::integer AS total_correct
      FROM game_sessions gs LEFT JOIN session_answers sa ON sa.session_id = gs.id
      WHERE gs.player_id = $1 AND gs.completed_at IS NOT NULL
    `, [player.id])).rows[0];
    const r = (await db.query('SELECT (COUNT(*) + 1)::integer AS rank FROM players WHERE xp > $1 OR (xp = $1 AND (created_at < $2 OR (created_at = $2 AND id < $3)))', [player.xp, player.created_at, player.id])).rows[0];
    stats = {
      completed: Number(s.completed || 0), totalCorrect: Number(s.total_correct || 0),
      totalAnswers: Number(s.total_answers || 0),
      accuracy: Number(s.total_answers) ? Math.round(Number(s.total_correct) / Number(s.total_answers) * 100) : 0,
      rank: r.rank
    };
  }
  res.json({ player, missions, leaderboard, stats });
}));

app.get('/api/timeline', asyncRoute(async (_req, res) => {
  const { rows } = await db.query(`
    SELECT e.id,e.event_year,e.event_date,e.title,e.summary,e.period_key,
           e.source_document_id,e.source_page,d.file_path AS source_file_path
    FROM timeline_events e LEFT JOIN source_documents d ON d.id=e.source_document_id
    ORDER BY e.sort_order`);
  res.json({ events: rows });
}));

// API học tập chuẩn hóa: chương -> buổi học -> nội dung PDF.
app.get('/api/curriculum', asyncRoute(async (_req, res) => {
  const chapters=(await db.query(`
    SELECT c.key,c.title,c.description,c.sort_order,co.code AS course_code,
           (SELECT COUNT(*)::integer FROM lessons l WHERE l.chapter_key=c.key) AS lesson_count
    FROM chapters c JOIN courses co ON co.slug=c.course_slug ORDER BY c.sort_order
  `)).rows;
  const lessons=(await db.query(`
    SELECT lesson_id,session_number,lesson_title,chapter_key,chapter_title,
           pdf_url,page_count,sourced_question_count,flashcard_count
    FROM v_lesson_catalog ORDER BY session_number
  `)).rows;
  res.json({ chapters, lessons });
}));

app.get('/api/curriculum/:lessonId', asyncRoute(async (req, res) => {
  const id=req.params.lessonId;
  if(!/^lesson-\d{2,3}$/.test(id)) fail('Mã buổi học không hợp lệ.');
  const { rows } = await db.query(`
    SELECT l.id,l.title,l.summary,l.session_number,l.chapter_key,d.file_path,d.page_count,
           d.id AS document_id
    FROM lessons l JOIN source_documents d ON d.id=l.document_id WHERE l.id=$1
  `,[id]);
  if(!rows.length) fail('Không tìm thấy buổi học.',404);
  const pages=(await db.query(`SELECT page_number,content FROM source_pages WHERE document_id=$1 ORDER BY page_number`,[rows[0].document_id])).rows;
  const notes=(await db.query(`SELECT id,title,body,sort_order,source_page FROM lesson_notes WHERE lesson_id=$1 ORDER BY sort_order`,[id])).rows;
  res.json({ lesson:rows[0], pages, notes });
}));

app.get('/api/flashcards', asyncRoute(async (req,res) => {
  const lessonId=typeof req.query.lessonId==='string'?req.query.lessonId:'';
  if(lessonId && !/^lesson-\d{2,3}$/.test(lessonId)) fail('Mã buổi học không hợp lệ.');
  const { rows } = await db.query(`
    SELECT f.id,f.lesson_id,f.front,f.back,f.explanation,f.source_page,
           sd.file_path AS source_file_path
    FROM flashcards f LEFT JOIN source_documents sd ON sd.id=f.source_document_id
    WHERE f.is_published AND ($1='' OR f.lesson_id=$1)
    ORDER BY f.lesson_id,f.id LIMIT 300
  `,[lessonId]);
  res.json({ flashcards:rows,total:rows.length });
}));

// Thư viện kiến thức: metadata không trả 435 trang nội dung cùng một lúc.
app.get('/api/library', asyncRoute(async (req, res) => {
  const search = typeof req.query.search === 'string' ? req.query.search.trim().slice(0, 80) : '';
  const chapter = typeof req.query.chapter === 'string' ? req.query.chapter : '';
  const { rows } = await db.query(`
    SELECT d.id,d.session_number,d.title,d.chapter_key,d.chapter_label,d.page_count,d.file_path,
           COUNT(p.page_number) FILTER (WHERE $1 <> '' AND p.content ILIKE '%' || $1 || '%')::integer AS match_count
    FROM source_documents d LEFT JOIN source_pages p ON p.document_id=d.id
    WHERE ($2 = '' OR d.chapter_key=$2)
    GROUP BY d.id
    HAVING $1 = '' OR d.title ILIKE '%' || $1 || '%' OR COUNT(p.page_number) FILTER (WHERE p.content ILIKE '%' || $1 || '%') > 0
    ORDER BY d.session_number
  `,[search,chapter]);
  res.json({ documents:rows, total:rows.length });
}));

app.get('/api/library/:documentId', asyncRoute(async (req, res) => {
  const id=req.params.documentId;
  if (!docIdPattern.test(id)) fail('Mã tài liệu không hợp lệ.');
  const { rows } = await db.query(`
    SELECT id,session_number,title,chapter_key,chapter_label,page_count,file_path
    FROM source_documents WHERE id=$1`,[id]);
  if (!rows.length) fail('Không tìm thấy tài liệu.',404);
  const pages=(await db.query('SELECT page_number,content FROM source_pages WHERE document_id=$1 ORDER BY page_number',[id])).rows;
  res.json({ document: rows[0], pages });
}));

app.post('/api/sessions', asyncRoute(async (req, res) => {
  const { playerId, missionSlug } = req.body ?? {};
  if (!validUuid(playerId) || typeof missionSlug !== 'string') fail('Thiếu mã người chơi hoặc chiến dịch.');
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const { rowCount } = await client.query('SELECT 1 FROM players WHERE id = $1', [playerId]);
    if (!rowCount) fail('Người chơi không tồn tại.', 404);
    if (!(await missionAccess(client, playerId, missionSlug))) fail('Bạn cần hoàn thành chiến dịch trước để mở khóa.', 403);
    const questions = (await client.query(
      `SELECT q.id,q.position,q.prompt,q.options,q.source_document_id,q.source_page,
              d.file_path AS source_file_path,d.title AS source_title
       FROM questions q LEFT JOIN source_documents d ON d.id=q.source_document_id
       WHERE q.mission_slug = $1 ORDER BY q.position`,
      [missionSlug]
    )).rows;
    if (questions.length === 0) fail('Chiến dịch chưa có câu hỏi.', 409);
    const { rows } = await client.query('INSERT INTO game_sessions (player_id, mission_slug) VALUES ($1, $2) RETURNING id', [playerId, missionSlug]);
    await client.query('COMMIT');
    res.status(201).json({ sessionId: rows[0].id, questions });
  } catch (e) { await client.query('ROLLBACK'); throw e; }
  finally { client.release(); }
}));

app.post('/api/sessions/:sessionId/answer', asyncRoute(async (req, res) => {
  const { sessionId } = req.params;
  const { playerId, questionId, choiceIndex } = req.body ?? {};
  if (!validUuid(sessionId) || !validUuid(playerId) || typeof questionId !== 'string' || !Number.isInteger(choiceIndex) || choiceIndex < 0 || choiceIndex > 3) {
    fail('Dữ liệu câu trả lời không hợp lệ.');
  }
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query('SELECT * FROM game_sessions WHERE id = $1 FOR UPDATE', [sessionId]);
    const session = rows[0];
    if (!session || session.player_id !== playerId) fail('Lượt chơi không tồn tại.', 404);
    if (session.completed_at) fail('Lượt chơi này đã hoàn thành.', 409);
    if (Date.now() - new Date(session.started_at).getTime() > 90 * 60_000) fail('Lượt chơi đã hết hạn, hãy thử lại.', 410);
    const questionList = (await client.query('SELECT id, correct_index, explanation, position FROM questions WHERE mission_slug = $1 ORDER BY position', [session.mission_slug])).rows;
    const answered = (await client.query('SELECT question_id FROM session_answers WHERE session_id = $1', [sessionId])).rows;
    const nextQuestion = questionList[answered.length];
    if (!nextQuestion || nextQuestion.id !== questionId) fail('Hãy trả lời câu hỏi theo đúng thứ tự.', 409);
    const correct = choiceIndex === nextQuestion.correct_index;
    await client.query('INSERT INTO session_answers (session_id, question_id, choice_index, is_correct) VALUES ($1,$2,$3,$4)',
      [sessionId, questionId, choiceIndex, correct]);
    await client.query('COMMIT');
    res.json({ correct, correctIndex: nextQuestion.correct_index, explanation: nextQuestion.explanation, answered: answered.length + 1, total: questionList.length });
  } catch (e) { await client.query('ROLLBACK'); throw e; }
  finally { client.release(); }
}));

app.post('/api/sessions/:sessionId/finish', asyncRoute(async (req, res) => {
  const { sessionId } = req.params;
  const { playerId } = req.body ?? {};
  if (!validUuid(sessionId) || !validUuid(playerId)) fail('Dữ liệu không hợp lệ.');
  const client = await db.connect();
  try {
    await client.query('BEGIN');
    const { rows } = await client.query('SELECT * FROM game_sessions WHERE id = $1 FOR UPDATE', [sessionId]);
    const session = rows[0];
    if (!session || session.player_id !== playerId) fail('Lượt chơi không tồn tại.', 404);
    if (session.completed_at) fail('Lượt chơi này đã được tính điểm.', 409);
    if (Date.now() - new Date(session.started_at).getTime() > 90 * 60_000) fail('Lượt chơi đã hết hạn, hãy thử lại.', 410);
    const { rows: counts } = await client.query(`
      SELECT (SELECT COUNT(*)::integer FROM questions WHERE mission_slug = $2) AS total,
             COUNT(*)::integer AS answered,
             COUNT(*) FILTER (WHERE is_correct)::integer AS correct
      FROM session_answers WHERE session_id = $1
    `, [sessionId, session.mission_slug]);
    const { total, answered, correct } = counts[0];
    if (!total || answered !== total) fail('Bạn chưa hoàn thành tất cả câu hỏi.', 409);
    const { rows: playerRows } = await client.query('SELECT * FROM players WHERE id = $1 FOR UPDATE', [playerId]);
    if (!playerRows.length) fail('Không tìm thấy người chơi.', 404);
    const { rows: existing } = await client.query('SELECT best_correct FROM mission_progress WHERE player_id = $1 AND mission_slug = $2', [playerId, session.mission_slug]);
    const firstCompletion = existing.length === 0;
    const oldBest = firstCompletion ? 0 : existing[0].best_correct;
    const { xpEarned, coinsEarned } = calculateReward(correct, oldBest, firstCompletion);
    await client.query('UPDATE players SET xp = xp + $2, coins = coins + $3 WHERE id = $1', [playerId, xpEarned, coinsEarned]);
    await client.query(`
      INSERT INTO mission_progress (player_id, mission_slug, best_correct, attempts)
      VALUES ($1, $2, $3, 1)
      ON CONFLICT (player_id, mission_slug)
      DO UPDATE SET best_correct = GREATEST(mission_progress.best_correct, EXCLUDED.best_correct),
                    attempts = mission_progress.attempts + 1, last_played_at = now()
    `, [playerId, session.mission_slug, correct]);
    await client.query(`
      UPDATE game_sessions SET completed_at = now(), correct_count = $2, xp_earned = $3, coins_earned = $4 WHERE id = $1
    `, [sessionId, correct, xpEarned, coinsEarned]);
    await client.query('COMMIT');
    res.json({ correct, total, xpEarned, coinsEarned, firstCompletion,
      xp: playerRows[0].xp + xpEarned, coins: playerRows[0].coins + coinsEarned });
  } catch (e) { await client.query('ROLLBACK'); throw e; }
  finally { client.release(); }
}));

app.use('/api', (req, res) => res.status(404).json({ error: 'API không tồn tại.' }));
app.use(express.static(path.join(ROOT, 'dist')));
app.get('*', (_req, res) => res.sendFile(path.join(ROOT, 'dist', 'index.html'), (err) => {
  if (err && !res.headersSent) res.status(404).send('Chạy npm run dev để phát triển giao diện, hoặc npm run build trước khi chạy npm start.');
}));
app.use((err, _req, res, _next) => {
  if (err.status && err.status < 500) return res.status(err.status).json({ error: err.message });
  console.error('[API]', err);
  res.status(500).json({ error: 'Lỗi máy chủ. Kiểm tra kết nối Neon và database đã khởi tạo.' });
});

app.listen(PORT, () => {
  console.log(`VNR202 API: http://localhost:${PORT}`);
  if (!db) console.warn('Chưa có DATABASE_URL. Sao chép .env.example thành .env và kết nối Neon.');
});
