// Dữ liệu chuẩn hóa từ 29 tài liệu nguồn PDF. Không tự suy diễn thêm sự kiện.
export const course = {
  slug: 'vnr202', code: 'VNR202', title: 'Lịch sử Đảng Cộng sản Việt Nam',
  description: 'Học phần VNR202; tài liệu do người học cung cấp, gồm 29 buổi học.'
};

export const chapters = [
  { key: 'intro', sortOrder: 0, title: 'Nhập môn',
    description: 'Đối tượng, chức năng và phương pháp nghiên cứu Lịch sử Đảng.' },
  { key: 'chapter1', sortOrder: 1, title: 'Chương 1 · Thành lập Đảng và đấu tranh giành chính quyền',
    description: 'Bối cảnh ra đời của Đảng và lãnh đạo phong trào cách mạng đến năm 1945.' },
  { key: 'chapter2', sortOrder: 2, title: 'Chương 2 · Kháng chiến và thống nhất đất nước',
    description: 'Xây dựng, bảo vệ chính quyền; các cuộc kháng chiến giai đoạn 1945–1975.' },
  { key: 'chapter3', sortOrder: 3, title: 'Chương 3 · Xây dựng đất nước và công cuộc Đổi mới',
    description: 'Xây dựng đất nước sau 1975, các kỳ đại hội và quá trình Đổi mới, hội nhập.' }
];

export function buildLessons(documents) {
  return documents.map(d => ({
    id: `lesson-${String(d.sessionNumber).padStart(2, '0')}`,
    chapterKey: d.chapterKey, documentId: d.id,
    sessionNumber: d.sessionNumber, title: d.title,
    summary: `Buổi ${d.sessionNumber}: ${d.title}. Nội dung chi tiết và trích dẫn theo từng trang nằm trong tài liệu PDF đính kèm.`,
    sortOrder: d.sessionNumber
  }));
}

export function buildFlashcards(questions) {
  return questions.map(q => ({
    id: `flash-${q.id}`,
    lessonId: `lesson-${q.sourceDoc.split('-').at(-1)}`,
    questionId: q.id, front: q.prompt,
    back: q.options[q.correct], explanation: q.explanation,
    sourceDocumentId: q.sourceDoc, sourcePage: q.sourcePage
  }));
}

export const achievements = [
  { code: 'first_steps', name: 'Những bước chân đầu tiên', description: 'Hoàn thành chiến dịch đầu tiên.', icon: 'footprints', requiredXp: null },
  { code: 'hundred_xp', name: 'Nhà thám hiểm', description: 'Đạt tối thiểu 100 điểm XP.', icon: 'compass', requiredXp: 100 },
  { code: 'five_hundred_xp', name: 'Nhà sử học trẻ', description: 'Đạt tối thiểu 500 điểm XP.', icon: 'graduation-cap', requiredXp: 500 },
  { code: 'thousand_xp', name: 'Bậc thầy lịch sử', description: 'Đạt tối thiểu 1000 điểm XP.', icon: 'trophy', requiredXp: 1000 }
];
