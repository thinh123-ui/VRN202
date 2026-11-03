-- Dán vào Neon SQL Editor sau khi import dữ liệu.
SELECT 'courses' AS table_name, COUNT(*) AS records FROM courses
UNION ALL SELECT 'chapters', COUNT(*) FROM chapters
UNION ALL SELECT 'lessons', COUNT(*) FROM lessons
UNION ALL SELECT 'source_documents', COUNT(*) FROM source_documents
UNION ALL SELECT 'source_pages', COUNT(*) FROM source_pages
UNION ALL SELECT 'missions', COUNT(*) FROM missions
UNION ALL SELECT 'questions', COUNT(*) FROM questions
UNION ALL SELECT 'flashcards', COUNT(*) FROM flashcards
UNION ALL SELECT 'timeline_events', COUNT(*) FROM timeline_events
UNION ALL SELECT 'achievements', COUNT(*) FROM achievements
ORDER BY table_name;

-- Kiểm tra bài học chứa bao nhiêu câu hỏi đã tham chiếu nguồn.
SELECT chapter_title, COUNT(*) AS number_of_lessons, SUM(sourced_question_count) AS questions
FROM v_lesson_catalog GROUP BY chapter_title ORDER BY chapter_title;
