# Deploy VNR202 Quest lên Render bằng Docker

Dự án dùng React/Vite và Node.js/Express. Các tệp `Dockerfile` và `.dockerignore` này phù hợp với cấu trúc hiện tại, trong đó `package.json` nằm ở thư mục gốc.

## Cấu hình Render

1. Commit và push `Dockerfile`, `.dockerignore` và hướng dẫn này lên nhánh `main`.
2. Trong Render, tạo hoặc mở Web Service và đặt:
   - **Language:** Docker
   - **Branch:** `main`
   - **Dockerfile Path:** `./Dockerfile`
   - **Root Directory:** để trống
   - **Docker Command:** để trống
3. Trong phần **Environment**, thêm `DATABASE_URL` với connection string PostgreSQL của Neon. Render tự cung cấp `PORT`; image có giá trị mặc định `10000`.
4. Khởi tạo schema và dữ liệu Neon một lần bằng `npm run db:init` từ môi trường có quyền kết nối database. Dockerfile không chạy lệnh này khi build hoặc khởi động để tránh ghi dữ liệu lại ở mỗi lần deploy.
5. Chọn **Manual Deploy → Deploy latest commit** rồi kiểm tra `/api/health`.

Không commit `.env` hoặc connection string lên GitHub. Nếu cấu trúc repository thay đổi, hãy cập nhật Root Directory và Dockerfile Path tương ứng.
