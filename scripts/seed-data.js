// Ngân hàng câu hỏi khởi đầu được biên soạn riêng cho bản demo VNR202.
// Hãy rà soát với giáo trình/đề cương của lớp trước khi dùng để chấm điểm chính thức.
import { introMission, pdfQuestions, existingQuestionSources, eventSources } from './pdf-questions.js';

export const missions = [
  introMission,
  {
    slug: 'ngon-lua-khoi-dau', title: 'Ngọn lửa khởi đầu', era: '1930 – 1945',
    description: 'Từ sự ra đời của Đảng đến thắng lợi của Cách mạng Tháng Tám.',
    shortLabel: 'Hành trình khởi nguyên', sortOrder: 1, symbol: '✦', color: 'purple'
  },
  {
    slug: 'bao-ve-doc-lap', title: 'Bảo vệ nền độc lập', era: '1945 – 1954',
    description: 'Chính quyền non trẻ, kháng chiến chống Pháp và Điện Biên Phủ.',
    shortLabel: 'Ý chí kháng chiến', sortOrder: 2, symbol: '⚡', color: 'blue'
  },
  {
    slug: 'non-song-lien-mot-dai', title: 'Non sông liền một dải', era: '1954 – 1975',
    description: 'Các mốc đấu tranh giải phóng miền Nam, thống nhất đất nước.',
    shortLabel: 'Đường tới thống nhất', sortOrder: 3, symbol: '★', color: 'amber'
  },
  {
    slug: 'kien-thiet-dat-nuoc', title: 'Kiến thiết đất nước', era: '1975 – 1986',
    description: 'Thống nhất về mặt nhà nước và bước ngoặt tư duy đổi mới.',
    shortLabel: 'Bước ngoặt lịch sử', sortOrder: 4, symbol: '◆', color: 'pink'
  },
  {
    slug: 'khat-vong-vuon-xa', title: 'Khát vọng vươn xa', era: '1986 – 2007',
    description: 'Đổi mới, hội nhập khu vực và gia nhập thương mại toàn cầu.',
    shortLabel: 'Kỷ nguyên hội nhập', sortOrder: 5, symbol: '✺', color: 'teal'
  }
];

const q = (id, mission, position, prompt, options, correct, explanation) =>
  ({ id, mission, position, prompt, options, correct, explanation });

export const questions = [
  q('a01','ngon-lua-khoi-dau',1,'Hội nghị thành lập Đảng Cộng sản Việt Nam gắn với tháng, năm nào?',
    ['2/1930','9/1945','7/1954','12/1986'],0,
    'Slide Chương 1 giới thiệu Hội nghị thành lập Đảng và Cương lĩnh chính trị đầu tiên vào tháng 2/1930.'),
  q('a02','ngon-lua-khoi-dau',2,'Ai chủ trì Hội nghị hợp nhất các tổ chức cộng sản đầu năm 1930?',
    ['Trần Phú','Nguyễn Ái Quốc','Phan Bội Châu','Võ Nguyên Giáp'],1,
    'Nguyễn Ái Quốc chủ trì Hội nghị hợp nhất, đặt nền tảng cho việc thành lập Đảng.'),
  q('a03','ngon-lua-khoi-dau',3,'Phong trào Xô viết Nghệ - Tĩnh diễn ra chủ yếu trong giai đoạn nào?',
    ['1919–1920','1945–1946','1930–1931','1959–1960'],2,
    'Xô viết Nghệ - Tĩnh là đỉnh cao của phong trào cách mạng 1930–1931.'),
  q('a04','ngon-lua-khoi-dau',4,'Mặt trận Việt Minh được thành lập vào năm nào?',
    ['1930','1936','1946','1941'],3,
    'Mặt trận Việt Nam Độc lập Đồng minh (Việt Minh) được thành lập năm 1941.'),
  q('a05','ngon-lua-khoi-dau',5,'Sự kiện nào đánh dấu sự ra đời của nước Việt Nam Dân chủ Cộng hòa?',
    ['Đại hội Đảng lần II','Tuyên ngôn Độc lập ngày 2/9/1945','Chiến thắng Điện Biên Phủ','Hiệp định Giơ-ne-vơ'],1,
    'Ngày 2/9/1945, Chủ tịch Hồ Chí Minh đọc Tuyên ngôn Độc lập tại Quảng trường Ba Đình.'),

  q('b01','bao-ve-doc-lap',1,'Cuộc Tổng tuyển cử đầu tiên bầu Quốc hội nước Việt Nam Dân chủ Cộng hòa diễn ra ngày nào?',
    ['6/1/1946','19/12/1946','7/5/1954','2/7/1976'],0,
    'Ngày 6/1/1946, nhân dân cả nước đi bầu Quốc hội khóa I.'),
  q('b02','bao-ve-doc-lap',2,'Hiệp định Sơ bộ ngày 6/3/1946 được ký nhằm mục tiêu chủ yếu nào?',
    ['Từ bỏ nền độc lập','Chấm dứt ngay mọi xung đột','Tranh thủ hòa hoãn để củng cố lực lượng','Gia nhập một liên minh quân sự'],2,
    'Chủ trương hòa hoãn nhằm tránh cùng lúc đối phó nhiều lực lượng và tranh thủ thời gian chuẩn bị.'),
  q('b03','bao-ve-doc-lap',3,'Lời kêu gọi Toàn quốc kháng chiến được phát đi vào ngày nào?',
    ['2/9/1945','19/12/1946','3/2/1930','21/7/1954'],1,
    'Ngày 19/12/1946 gắn với Lời kêu gọi Toàn quốc kháng chiến của Chủ tịch Hồ Chí Minh.'),
  q('b04','bao-ve-doc-lap',4,'Chiến thắng Việt Bắc Thu – Đông 1947 làm thất bại kế hoạch nào của thực dân Pháp?',
    ['Việt Nam hóa chiến tranh','Chiến tranh đặc biệt','Đánh lâu dài ngay từ đầu','Đánh nhanh, thắng nhanh'],3,
    'Thất bại tại Việt Bắc khiến thực dân Pháp không thực hiện được âm mưu đánh nhanh, thắng nhanh.'),
  q('b05','bao-ve-doc-lap',5,'Chiến thắng nào gắn với tiến trình đi tới Hiệp định Genève năm 1954?',
    ['Chiến thắng Điện Biên Phủ','Chiến dịch Hồ Chí Minh','Phong trào Đồng khởi','Cách mạng Tháng Tám'],0,
    'Session 13 đặt chiến thắng Điện Biên Phủ và Hiệp định Genève trong phần kết thúc cuộc kháng chiến chống Pháp.'),

  q('c01','non-song-lien-mot-dai',1,'Phong trào Đồng khởi bùng nổ mạnh ở Bến Tre vào năm nào?',
    ['1954','1960','1968','1975'],1,
    'Phong trào Đồng khởi ở Bến Tre bùng nổ mạnh vào tháng 1/1960.'),
  q('c02','non-song-lien-mot-dai',2,'Mặt trận Dân tộc Giải phóng miền Nam Việt Nam được thành lập ngày nào?',
    ['3/2/1930','2/9/1945','20/12/1960','30/4/1975'],2,
    'Mặt trận Dân tộc Giải phóng miền Nam Việt Nam được thành lập ngày 20/12/1960.'),
  q('c03','non-song-lien-mot-dai',3,'Đàm phán Pari được nêu trong tài liệu bắt đầu vào năm nào?',
    ['1968','1954','1975','1986'],0,
    'Session 16, trang 11 ghi đàm phán Pari bắt đầu ngày 13/5/1968.'),
  q('c04','non-song-lien-mot-dai',4,'Hiệp định Paris về chấm dứt chiến tranh, lập lại hòa bình ở Việt Nam được ký ngày nào?',
    ['7/5/1954','19/12/1946','2/7/1976','27/1/1973'],3,
    'Hiệp định Paris được ký vào ngày 27/1/1973.'),
  q('c05','non-song-lien-mot-dai',5,'Mốc thời gian gắn với giải phóng Sài Gòn, kết thúc chiến tranh là ngày nào?',
    ['19/8/1945','30/4/1975','2/9/1945','6/1/1946'],1,
    'Ngày 30/4/1975 đánh dấu thắng lợi của Chiến dịch Hồ Chí Minh và giải phóng Sài Gòn.'),

  q('d01','kien-thiet-dat-nuoc',1,'Tổng tuyển cử bầu Quốc hội chung của nước Việt Nam thống nhất diễn ra năm nào?',
    ['1954','1973','1976','1986'],2,
    'Ngày 25/4/1976, cả nước tiến hành Tổng tuyển cử bầu Quốc hội chung.'),
  q('d02','kien-thiet-dat-nuoc',2,'Tên nước Cộng hòa xã hội chủ nghĩa Việt Nam được Quốc hội quyết định vào năm nào?',
    ['1976','1945','1986','1995'],0,
    'Quốc hội khóa VI quyết định tên nước Cộng hòa xã hội chủ nghĩa Việt Nam vào tháng 7/1976.'),
  q('d03','kien-thiet-dat-nuoc',3,'Đại hội đại biểu toàn quốc lần thứ IV của Đảng được tổ chức vào năm nào?',
    ['1960','1976','1982','1986'],1,
    'Đại hội IV của Đảng diễn ra vào tháng 12/1976.'),
  q('d04','kien-thiet-dat-nuoc',4,'Đại hội nào được xem là dấu mốc khởi xướng đường lối Đổi mới toàn diện?',
    ['Đại hội III','Đại hội IV','Đại hội V','Đại hội VI'],3,
    'Đại hội VI (tháng 12/1986) đề ra đường lối Đổi mới toàn diện đất nước.'),
  q('d05','kien-thiet-dat-nuoc',5,'Một điểm quan trọng của chủ trương Đổi mới 1986 là gì?',
    ['Dừng mọi hoạt động kinh tế đối ngoại','Chỉ tập trung thay đổi về văn hóa','Đổi mới tư duy và cơ chế quản lý kinh tế','Xóa bỏ mọi hình thức sở hữu'],2,
    'Đổi mới nhấn mạnh đổi mới tư duy kinh tế, khắc phục cơ chế quản lý tập trung quan liêu bao cấp.'),

  q('e01','khat-vong-vuon-xa',1,'Đại hội VI, dấu mốc mở đầu công cuộc Đổi mới, diễn ra vào năm nào?',
    ['1975','1986','1995','2007'],1,
    'Đại hội VI diễn ra tháng 12/1986, mở đầu công cuộc Đổi mới.'),
  q('e02','khat-vong-vuon-xa',2,'Việt Nam chính thức gia nhập ASEAN vào năm nào?',
    ['1995','1986','2000','2007'],0,
    'Việt Nam gia nhập ASEAN vào ngày 28/7/1995.'),
  q('e03','khat-vong-vuon-xa',3,'Nghị quyết 08-NQ/TW (5/2/2007) đề cập chính sách phát triển khi Việt Nam gia nhập tổ chức nào?',
    ['ASEAN','UNESCO','WTO','Liên đoàn bóng đá thế giới'],2,
    'Session 25, trang 19 nhắc đến Nghị quyết 08-NQ/TW về chủ trương, chính sách khi Việt Nam là thành viên WTO.'),
  q('e04','khat-vong-vuon-xa',4,'Chủ trương kết hợp phát triển đất nước với mở rộng quan hệ quốc tế được gọi là gì?',
    ['Đóng cửa kinh tế','Tách biệt khu vực','Tự cô lập','Hội nhập quốc tế'],3,
    'Hội nhập quốc tế là quá trình chủ động tham gia, hợp tác và gắn kết với khu vực, thế giới.'),
  q('e05','khat-vong-vuon-xa',5,'Về kinh tế, Đổi mới ở Việt Nam gắn với sự phát triển mô hình nào?',
    ['Kinh tế tự cấp tự túc duy nhất','Kinh tế thị trường định hướng xã hội chủ nghĩa','Kinh tế không có trao đổi hàng hóa','Chỉ có một loại hình doanh nghiệp'],1,
    'Đường lối Đổi mới từng bước hình thành và hoàn thiện mô hình kinh tế thị trường định hướng xã hội chủ nghĩa.')
];

const baseEvents = [
  ['t01','1930','03.02.1930','Thành lập Đảng Cộng sản Việt Nam','Bước ngoặt lịch sử, thống nhất sự lãnh đạo cách mạng.','1930–1945',1],
  ['t02','1931','1930–1931','Xô viết Nghệ – Tĩnh','Đỉnh cao phong trào cách mạng 1930–1931.','1930–1945',2],
  ['t03','1941','19.05.1941','Thành lập Mặt trận Việt Minh','Tập hợp lực lượng cho sự nghiệp giải phóng dân tộc.','1930–1945',3],
  ['t04','1945','02.09.1945','Tuyên ngôn Độc lập','Nước Việt Nam Dân chủ Cộng hòa ra đời.','1930–1945',4],
  ['t05','1946','19.12.1946','Toàn quốc kháng chiến','Mở đầu cuộc kháng chiến toàn quốc chống thực dân Pháp.','1945–1954',5],
  ['t06','1954','07.05.1954','Chiến thắng Điện Biên Phủ','Chiến thắng quân sự có ý nghĩa quyết định.','1945–1954',6],
  ['t07','1960','20.12.1960','Mặt trận Dân tộc Giải phóng miền Nam','Ra đời trong phong trào đấu tranh ở miền Nam.','1954–1975',7],
  ['t08','1973','27.01.1973','Ký Hiệp định Paris','Thỏa thuận về chấm dứt chiến tranh, lập lại hòa bình ở Việt Nam.','1954–1975',8],
  ['t09','1975','30.04.1975','Giải phóng Sài Gòn','Kết thúc chiến tranh, mở ra thời kỳ đất nước thống nhất.','1954–1975',9],
  ['t10','1976','02.07.1976','Tên nước CHXHCN Việt Nam','Quốc hội khóa VI quyết định tên nước và nhiều vấn đề của quốc gia thống nhất.','1975–1986',10],
  ['t11','1986','12.1986','Đại hội VI – Khởi xướng Đổi mới','Đề ra đường lối Đổi mới toàn diện đất nước.','1975–1986',11],
  ['t12','1995','28.07.1995','Việt Nam gia nhập ASEAN','Bước tiến quan trọng trong hội nhập khu vực.','1986–2007',12],
  ['t13','2007','11.01.2007','Gia nhập WTO','Một dấu mốc trong tiến trình hội nhập kinh tế quốc tế.','1986–2007',13]
];


// Mỗi câu hỏi/nhân vật lịch sử được gắn nguồn gốc PDF cụ thể để kiểm chứng.
export const sourcedQuestions = [
  ...questions.map(item => {
    const [session, page] = existingQuestionSources[item.id];
    return { ...item, sourceDoc: `session-${String(session).padStart(2,'0')}`, sourcePage: page };
  }),
  ...pdfQuestions
];
export const events = baseEvents.map(item => {
  const [session, page] = eventSources[item[0]];
  return [...item, `session-${String(session).padStart(2,'0')}`, page];
});
