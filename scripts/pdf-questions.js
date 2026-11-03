// Câu hỏi được biên soạn dựa trên slide của học phần do người dùng cung cấp.
// sourceDoc + sourcePage là số trang PDF thực tế (đếm từ trang bìa).
export const introMission = {
  slug: 'nhap-mon-lich-su-dang', title: 'Cánh cổng lịch sử', era: 'Nhập môn',
  description: 'Khởi động hành trình: đối tượng, chức năng và phương pháp học Lịch sử Đảng.',
  shortLabel: 'Nhập môn VNR202', sortOrder: 0, symbol: '◈', color: 'teal'
};
// Xoay vị trí đáp án theo câu hỏi để các câu mới không dồn toàn bộ đáp án về A.
const Q = (id, mission, position, prompt, options, correct, explanation, sourceDoc, sourcePage) => {
  const shift = (position + sourceDoc) % 4;
  const shuffled = options.map((_, index) => options[(index - shift + 4) % 4]);
  return { id, mission, position, prompt, options: shuffled, correct: (correct + shift) % 4,
    explanation, sourceDoc: `session-${String(sourceDoc).padStart(2,'0')}`, sourcePage };
};

export const pdfQuestions = [
  Q('i01','nhap-mon-lich-su-dang',1,'Nội dung nào thuộc đối tượng nghiên cứu của môn Lịch sử Đảng Cộng sản Việt Nam?',
    ['Cương lĩnh và đường lối của Đảng','Các định luật vật lý','Cấu tạo địa chất','Ngữ pháp tiếng Anh'],0,
    'Đối tượng nghiên cứu bao gồm các sự kiện lịch sử, Cương lĩnh, đường lối, tổ chức và kinh nghiệm lãnh đạo của Đảng.',1,4),
  Q('i02','nhap-mon-lich-su-dang',2,'Theo slide, chức năng nào SAU ĐÂY là một chức năng của khoa học Lịch sử Đảng?',
    ['Chức năng dự báo và phê phán','Chức năng dự báo thời tiết','Chức năng kế toán','Chức năng thiết kế kỹ thuật'],0,
    'Slide nêu ba nhóm: chức năng nhận thức, giáo dục, dự báo và phê phán.',1,6),
  Q('i03','nhap-mon-lich-su-dang',3,'Chức năng nhận thức của môn học giúp người học hiểu điều gì?',
    ['Chỉ cách vẽ bản đồ','Quy luật ra đời và phát triển của Đảng','Cách vận hành máy tính','Quy tắc bóng đá'],1,
    'Chức năng nhận thức hướng tới nhận thức quy luật ra đời và phát triển của Đảng cùng vai trò lãnh đạo trong lịch sử.',1,7),
  Q('i04','nhap-mon-lich-su-dang',4,'Chức năng giáo dục góp phần bồi dưỡng điều gì?',
    ['Tinh thần yêu nước và ý chí tự cường','Kỹ năng sửa chữa động cơ','Cách phân tích biểu đồ chứng khoán','Kiến thức thiên văn'],0,
    'Slide đặt tinh thần yêu nước, lý tưởng cách mạng và đạo đức cách mạng trong nhóm chức năng giáo dục.',1,8),
  Q('i05','nhap-mon-lich-su-dang',5,'Chức năng dự báo và phê phán có nội dung nào?',
    ['Bỏ qua hoàn toàn quá khứ','Nhận thức quá khứ để hiểu hiện tại và dự báo tương lai','Chỉ ghi nhớ năm sinh','Không đánh giá sự kiện'],1,
    'Slide nhấn mạnh nhận thức quá khứ để hiểu hiện tại, dự báo tương lai và phê phán biểu hiện tiêu cực.',1,9),
  Q('i06','nhap-mon-lich-su-dang',6,'Phương pháp lịch sử chú trọng cách tìm hiểu nào?',
    ['Trình bày quá trình phát triển trong tính cụ thể, sinh động','Chỉ sử dụng suy đoán','Chỉ so sánh công thức','Bỏ qua trình tự lịch sử'],0,
    'Phương pháp lịch sử trình bày tiến trình phát triển với những điều kiện và diễn biến cụ thể.',2,5),
  Q('i07','nhap-mon-lich-su-dang',7,'Phương pháp logic chú trọng thao tác nào?',
    ['Ghi chép nguyên văn mọi tài liệu','Phân tích, so sánh, tổng hợp để khái quát bản chất','Đo chiều dài di tích','Chỉ sắp xếp theo thứ tự ngày'],1,
    'Phương pháp logic đi vào bản chất, cái phổ biến và sử dụng tư duy phân tích, so sánh, tổng hợp.',2,5),
  Q('i08','nhap-mon-lich-su-dang',8,'Theo phương pháp luận sử học trong slide, tiêu chuẩn của chân lý là gì?',
    ['Thực tiễn','Tin đồn','Số đông mạng xã hội','Sự suy diễn'],0,
    'Slide nêu rõ thực tiễn là tiêu chuẩn của chân lý.',2,4),
  Q('i09','nhap-mon-lich-su-dang',9,'Tính khoa học trong nghiên cứu lịch sử yêu cầu điều gì?',
    ['Phản ánh khách quan, trung thực và có luận cứ khoa học','Chỉ nêu cảm xúc cá nhân','Không cần kiểm tra dữ kiện','Chỉ dùng một nguồn tin không đối chiếu'],0,
    'Tính khoa học đòi hỏi phản ánh lịch sử khách quan, trung thực, dựa trên luận cứ khoa học.',2,7),
  Q('i10','nhap-mon-lich-su-dang',10,'Giai đoạn nào gắn với Đảng lãnh đạo đấu tranh giành chính quyền?',
    ['1930–1945','1975–1986','1986–2000','2001–2020'],0,
    'Slide phân chia giai đoạn 1930–1945 với sự ra đời của Đảng và đấu tranh giải phóng dân tộc.',2,8),

  Q('a06','ngon-lua-khoi-dau',6,'Theo slide, thực dân Pháp nổ súng tấn công Đà Nẵng vào thời điểm nào?',
    ['1/9/1858','2/9/1945','19/12/1946','7/5/1954'],0,
    'Ngày 1/9/1858 được ghi trong slide như mốc Pháp nổ súng tấn công Đà Nẵng.',3,5),
  Q('a07','ngon-lua-khoi-dau',7,'Báo Thanh niên gắn với quá trình chuẩn bị nào của Nguyễn Ái Quốc?',
    ['Chuẩn bị về tổ chức và tuyên truyền cách mạng','Thành lập Quốc hội năm 1976','Ký Hiệp định Pari','Gia nhập ASEAN'],0,
    'Slide nhắc tới xuất bản Báo Thanh niên trong tiến trình chuẩn bị điều kiện thành lập Đảng.',3,19),
  Q('a08','ngon-lua-khoi-dau',8,'Hội nghị Trung ương lần thứ nhất tháng 10/1930 thông qua văn kiện nào?',
    ['Luận cương chính trị','Hiến pháp 1946','Hiệp định Genève','Cương lĩnh 2011'],0,
    'Slide Session 5, trang 10 ghi hội nghị tháng 10/1930 thông qua Luận cương chính trị.',5,10),
  Q('a09','ngon-lua-khoi-dau',9,'Phong trào dân chủ 1936–1939 nhấn mạnh yêu cầu trước mắt nào?',
    ['Tự do, dân chủ, cơm áo và hòa bình','Thành lập WTO','Thống nhất nhà nước năm 1976','Đổi mới quản lý kinh tế năm 1986'],0,
    'Chủ trương giai đoạn 1936–1939 nêu các yêu cầu dân sinh, dân chủ, hòa bình.',6,6),
  Q('a10','ngon-lua-khoi-dau',10,'Hội nghị Trung ương lần thứ VIII (5/1941) họp tại đâu?',
    ['Pác Bó (Cao Bằng)','Hà Nội','Điện Biên','Đà Nẵng'],0,
    'Slide ghi rõ Hội nghị Trung ương lần thứ VIII diễn ra tại Pác Bó, Cao Bằng, tháng 5/1941.',7,5),

  Q('b06','bao-ve-doc-lap',6,'Biện pháp nào được vận động để chống nạn đói sau Cách mạng Tháng Tám?',
    ['Tăng gia sản xuất và lập hũ gạo tiết kiệm','Đóng cửa mọi hoạt động sản xuất','Dừng chia sẻ lương thực','Chỉ dùng biện pháp quân sự'],0,
    'Slide về xây dựng chính quyền 1945–1946 nêu tăng gia sản xuất, tiết kiệm và lập hũ gạo.',11,8),
  Q('b07','bao-ve-doc-lap',7,'Ngày 6/1/1946 nhân dân cả nước tham gia sự kiện nào?',
    ['Bầu cử Quốc hội','Ký Hiệp định Pari','Giải phóng Sài Gòn','Đại hội VI'],0,
    'Slide Session 11, trang 10 ghi ngày 6/1/1946 nhân dân cả nước đi bầu cử.',11,10),
  Q('b08','bao-ve-doc-lap',8,'Đường lối cơ bản của cuộc kháng chiến chống Pháp được nêu bằng cụm từ nào?',
    ['Kháng chiến, kiến quốc','Chỉ đấu tranh ngoại giao','Không cần hậu phương','Hạn chế sự tham gia của nhân dân'],0,
    'Slide về kinh nghiệm kháng chiến nêu đường lối cơ bản là kháng chiến, kiến quốc.',14,9),
  Q('b09','bao-ve-doc-lap',9,'Kế hoạch quân sự Navarre được nêu trong slide vào năm nào?',
    ['1953','1930','1975','1986'],0,
    'Slide giai đoạn 1951–1954 ghi Kế hoạch Navarre từ tháng 5/1953.',13,14),
  Q('b10','bao-ve-doc-lap',10,'Sự kiện nào được đặt cạnh Hiệp định Genève trên slide tổng kết kháng chiến chống Pháp?',
    ['Chiến thắng Điện Biên Phủ','Tổng khởi nghĩa 1945','Đại hội XII','Gia nhập ASEAN'],0,
    'Session 13, trang 16 giới thiệu chiến thắng Điện Biên Phủ và Hiệp định Genève.',13,16),

  Q('c06','non-song-lien-mot-dai',6,'Tên gọi gắn với Đường 559 trong slide là gì?',
    ['Đường mòn Hồ Chí Minh','Đường sắt Bắc–Nam','Đường ven biển ASEAN','Đại lộ Thăng Long'],0,
    'Slide Session 15, trang 11 ghi Đường 559 là Đường mòn Hồ Chí Minh.',15,11),
  Q('c07','non-song-lien-mot-dai',7,'Ai được nêu là Chủ tịch Mặt trận Dân tộc Giải phóng miền Nam Việt Nam?',
    ['Nguyễn Hữu Thọ','Hà Huy Tập','Đỗ Mười','Lê Duẩn'],0,
    'Slide Session 15, trang 11 ghi Nguyễn Hữu Thọ làm Chủ tịch Mặt trận.',15,11),
  Q('c08','non-song-lien-mot-dai',8,'Theo slide, cách mạng miền Bắc giai đoạn này có nhiệm vụ chiến lược nào?',
    ['Cách mạng xã hội chủ nghĩa','Chỉ công nghiệp hóa thương mại','Khởi nghĩa năm 1930','Cải tổ Liên Xô'],0,
    'Slide nêu hai chiến lược: cách mạng XHCN ở miền Bắc và cách mạng dân tộc dân chủ nhân dân ở miền Nam.',15,13),
  Q('c09','non-song-lien-mot-dai',9,'Theo slide, miền Nam có nhiệm vụ chiến lược nào trong giai đoạn 1954–1975?',
    ['Cách mạng dân tộc dân chủ nhân dân','Chỉ xây dựng các nhà máy','Tham gia ASEAN','Soạn Cương lĩnh 2011'],0,
    'Slide Session 15, trang 13 xác định cách mạng dân tộc dân chủ nhân dân ở miền Nam.',15,13),
  Q('c10','non-song-lien-mot-dai',10,'Sự kiện ngày 30/4/1975 trên slide được gọi là gì?',
    ['Chiến dịch Hồ Chí Minh toàn thắng','Ký Hiệp định Genève','Hội nghị Trung ương VIII','Đại hội Đảng lần thứ VI'],0,
    'Session 17, trang 13 ghi ngày 30/4/1975 gắn với thắng lợi Chiến dịch Hồ Chí Minh.',17,13),

  Q('d06','kien-thiet-dat-nuoc',6,'Hội nghị Hiệp thương chính trị hai miền Bắc–Nam diễn ra vào thời điểm nào?',
    ['15–21/11/1975','3–7/2/1930','12–19/1/2011','28/7/1995'],0,
    'Session 19, trang 6 nêu Hội nghị Hiệp thương chính trị từ ngày 15 đến 21/11/1975.',19,6),
  Q('d07','kien-thiet-dat-nuoc',7,'Tổng tuyển cử ngày 25/4/1976 bầu Quốc hội chung với bao nhiêu đại biểu theo slide?',
    ['492','333','158','1.198'],0,
    'Session 19, trang 7 ghi 23 triệu cử tri bầu ra 492 đại biểu.',19,7),
  Q('d08','kien-thiet-dat-nuoc',8,'Kỳ họp thứ nhất Quốc hội nước Việt Nam thống nhất quyết định đổi tên Sài Gòn thành gì?',
    ['Thành phố Hồ Chí Minh','Thành phố Huế','Thành phố Đà Nẵng','Thành phố Hà Nội'],0,
    'Session 19, trang 8 trình bày quyết định đổi tên Sài Gòn thành Thành phố Hồ Chí Minh.',19,8),
  Q('d09','kien-thiet-dat-nuoc',9,'Đại hội đại biểu toàn quốc lần thứ V của Đảng diễn ra năm nào?',
    ['1982','1976','1991','2001'],0,
    'Slide Session 21, trang 3 ghi Đại hội V họp từ 27 đến 31/3/1982.',21,3),
  Q('d10','kien-thiet-dat-nuoc',10,'Chương trình ba mục tiêu kinh tế nêu trong slide Đại hội V gồm những nhóm hàng nào?',
    ['Lương thực–thực phẩm, hàng tiêu dùng, hàng xuất khẩu','Chỉ hàng nhập khẩu, vàng và bất động sản','Dầu mỏ, ô tô, máy bay','Chỉ nông nghiệp'],0,
    'Session 21, trang 5 nêu ba chương trình: lương thực–thực phẩm, hàng tiêu dùng và hàng xuất khẩu.',21,5),

  Q('e06','khat-vong-vuon-xa',6,'Đại hội VII thông qua Cương lĩnh xây dựng đất nước trong thời kỳ quá độ lên CNXH vào năm nào?',
    ['1991','1975','1930','2016'],0,
    'Session 22, trang 15 ghi Đại hội VII họp tháng 6/1991 và thông qua Cương lĩnh.',22,15),
  Q('e07','khat-vong-vuon-xa',7,'Đại hội đại biểu toàn quốc lần thứ VIII diễn ra năm nào?',
    ['1996','1982','2011','1945'],0,
    'Session 23, trang 3 ghi Đại hội VIII diễn ra từ 28/6 đến 1/7/1996.',23,3),
  Q('e08','khat-vong-vuon-xa',8,'Đại hội XI (2011) bổ sung và phát triển văn kiện nào?',
    ['Cương lĩnh 1991','Hiệp định Sơ bộ 1946','Luận cương 1930','Hiệp định Genève'],0,
    'Session 26, trang 5 nêu Cương lĩnh năm 2011 bổ sung, phát triển Cương lĩnh 1991.',26,5),
  Q('e09','khat-vong-vuon-xa',9,'Đại hội XII của Đảng diễn ra vào năm nào?',
    ['2016','1986','1996','2001'],0,
    'Session 27, trang 3 ghi Đại hội XII diễn ra 20–28/1/2016.',27,3),
  Q('e10','khat-vong-vuon-xa',10,'Theo slide về nguyên nhân tham nhũng, hạn chế nào thuộc nhóm pháp luật?',
    ['Sự chồng chéo, mâu thuẫn trong các quy định pháp luật','Thiếu trang thiết bị thiên văn','Khí hậu thay đổi theo mùa','Sự khác biệt múi giờ quốc tế'],0,
    'Session 29, trang 4 liệt kê sự chồng chéo, mâu thuẫn và thiếu minh bạch trong pháp luật.',29,4)
];

// Ánh xạ các câu hỏi vốn có của bản MVP tới trang tham chiếu phù hợp trong bộ PDF.
export const existingQuestionSources = {
  a01:[4,6],a02:[4,6],a03:[5,7],a04:[7,8],a05:[9,12],
  b01:[11,10],b02:[11,14],b03:[12,5],b04:[12,10],b05:[13,16],
  c01:[15,11],c02:[15,11],c03:[16,11],c04:[17,7],c05:[17,13],
  d01:[19,7],d02:[19,8],d03:[20,3],d04:[22,4],d05:[22,6],
  e01:[22,4],e02:[22,23],e03:[25,19],e04:[23,10],e05:[22,6]
};

export const eventSources = {
  t01:[4,6], t02:[5,7], t03:[7,8], t04:[9,12], t05:[12,5],
  t06:[13,16], t07:[15,11], t08:[17,7], t09:[17,13], t10:[19,8],
  t11:[22,4], t12:[22,23], t13:[25,19]
};
