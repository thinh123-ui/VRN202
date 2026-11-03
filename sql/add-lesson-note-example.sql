-- MẪU THÊM GHI CHÚ BÀI HỌC MỚI (chạy sau khi đã nhập database).
-- Chỉnh title/body/lesson_id và source_page theo dữ liệu của bạn.
-- Câu lệnh này chỉ là ví dụ, KHÔNG được chạy tự động khi khởi tạo.
INSERT INTO lesson_notes(lesson_id,title,body,sort_order,source_document_id,source_page)
VALUES (
  'lesson-01',
  'Ghi chú bổ sung: chức năng nhận thức',
  'Nội dung bạn tự biên soạn để ôn tập, kiểm tra lại với slide trước khi công bố.',
  1,
  'session-01',
  7
);
