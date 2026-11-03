import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity, ArrowLeft, ArrowRight, ArrowUpRight, Award, BookOpen, Check,
  CheckCircle2, ChevronRight, CircleHelp, Clock3, Compass, Crown, Flag,
  Gem, Home, Layers3, LockKeyhole, LogOut, Medal, Menu, Orbit, Play,
  RotateCcw, ScrollText, Shield, Sparkles, Star, Swords, Target,
  TrendingUp, Trophy, UserRound, X, XCircle, Zap, Search, FileText, ExternalLink, ChevronLeft
} from 'lucide-react';

const KEY = 'vnr202_player_id_v1';
const filters = ['Tất cả', '1930–1945', '1945–1954', '1954–1975', '1975–1986', '1986–2007'];
const avatarIcons = { astronaut: Orbit, bolt: Zap, crown: Crown, star: Star };
const avatarLabels = { astronaut: 'Nhà thám hiểm', bolt: 'Tia chớp', crown: 'Vương miện', star: 'Ngôi sao' };

async function api(path, options) {
  const response = await fetch(`/api${path}`, {
    headers: { 'Content-Type': 'application/json' }, ...options
  });
  let data;
  try { data = await response.json(); } catch { data = {}; }
  if (!response.ok) throw new Error(data.error || `API trả về lỗi ${response.status}`);
  return data;
}
const format = (n) => Intl.NumberFormat('vi-VN').format(n || 0);
const levelOf = (xp) => Math.floor((xp || 0) / 250) + 1;
const percent = (part, total) => total ? Math.round(part / total * 100) : 0;

function Avatar({ type = 'astronaut', size = 'md' }) {
  const Icon = avatarIcons[type] || Orbit;
  return <span className={`avatar avatar-${size}`}><Icon size={size === 'lg' ? 27 : size === 'sm' ? 17 : 21} strokeWidth={2.1}/></span>;
}

function SectionHead({ eyebrow, title, desc, action, onAction }) {
  return <div className="section-head">
    <div><div className="eyebrow"><span className="tiny-diamond"/>{eyebrow}</div>
      <h2>{title}</h2>{desc && <p>{desc}</p>}</div>
    {action && <button className="text-link" onClick={onAction}>{action}<ArrowRight size={17}/></button>}
  </div>;
}

function Sidebar({ view, go, onSwitch, player, mobileOpen, setMobileOpen }) {
  const links = [
    { id: 'dashboard', label: 'Tổng quan', icon: Home },
    { id: 'missions', label: 'Chiến dịch', icon: Swords },
    { id: 'timeline', label: 'Dòng thời gian', icon: Clock3 },
    { id: 'library', label: 'Thư viện bài học', icon: BookOpen },
    { id: 'leaderboard', label: 'Bảng xếp hạng', icon: Trophy }
  ];
  return <>
    {mobileOpen && <div className="mobile-scrim" onClick={() => setMobileOpen(false)} />}
    <aside className={`sidebar ${mobileOpen ? 'mobile-open' : ''}`}>
      <button className="brand" onClick={() => go('dashboard')} aria-label="VNR202 Quest - Tổng quan">
        <span className="brand-mark"><Sparkles size={27} strokeWidth={2.5}/></span>
        <span className="brand-words"><b>VNR<span>QUEST</span></b><small>HISTORY ADVENTURE</small></span>
      </button>
      <div className="side-separator"/>
      <div className="side-label">KHÁM PHÁ</div>
      <nav className="nav-list" aria-label="Điều hướng chính">
        {links.map((l) => <button key={l.id} className={`nav-link ${view === l.id ? 'active' : ''}`} onClick={() => go(l.id)}>
          <l.icon size={19} strokeWidth={2}/><span>{l.label}</span>{l.id === view && <span className="active-dot"/>}
        </button>)}
      </nav>
      <div className="side-bottom">
        <div className="side-challenge">
          <span className="challenge-stars"><Sparkles size={21}/><Star size={13}/></span>
          <b>Lịch sử gọi tên bạn!</b>
          <p>Chinh phục từng chương, tích lũy XP và leo bảng xếp hạng.</p>
          <button onClick={() => go('missions')}>Khám phá ngay <ArrowUpRight size={15}/></button>
        </div>
        <div className="side-person">
          <Avatar type={player?.avatar_key}/>
          <div><b>{player?.nickname || 'Khách tham quan'}</b><small>{player ? `Nhà thám hiểm • Cấp ${levelOf(player.xp)}` : 'Tạo tài khoản khách'}</small></div>
          <button title="Đổi người chơi" className="icon-plain" onClick={onSwitch}><LogOut size={17}/></button>
        </div>
      </div>
    </aside>
  </>;
}

function Stat({ icon: Icon, label, value, subtitle, color }) {
  return <div className="stat-card">
    <div className={`stat-icon icon-${color}`}><Icon size={22}/></div>
    <div className="stat-label">{label}</div>
    <div className="stat-value">{value}</div>
    <div className="stat-sub"><TrendingUp size={13}/>{subtitle}</div>
  </div>;
}

function MissionCard({ mission, index, onStart }) {
  const status = mission.completed ? 'done' : mission.unlocked ? 'ready' : 'locked';
  return <article className={`mission-card mission-${mission.color_key} ${status}`}>
    <div className="mission-cover">
      <div className="cover-shape cover-shape-1"/><div className="cover-shape cover-shape-2"/>
      <div className="mission-symbol">{mission.cover_symbol}</div>
      <span className="mission-index">CHƯƠNG {String(index + 1).padStart(2, '0')}</span>
      <span className={`mission-status ${status}`}>
        {status === 'done' ? <><Check size={12}/> ĐÃ HOÀN THÀNH</> : status === 'ready' ? <><Zap size={12}/> ĐÃ MỞ KHÓA</> : <><LockKeyhole size={12}/> CHƯA MỞ KHÓA</>}
      </span>
    </div>
    <div className="mission-body">
      <div className="mission-era"><Clock3 size={13}/>{mission.era}</div>
      <h3>{mission.title}</h3><p>{mission.description}</p>
      <div className="mission-meta"><span><CircleHelp size={14}/>{mission.question_count} thử thách</span><span><Gem size={14}/> Tối đa {mission.question_count * 35 + 60} XP</span></div>
      <div className="mission-progress-row"><span>Tiến độ kỷ lục</span><b>{mission.bestCorrect}/{mission.question_count}</b></div>
      <div className="progress-track"><span style={{ width: `${percent(mission.bestCorrect, mission.question_count)}%` }}/></div>
      <button className={`mission-action ${status}`} disabled={!mission.unlocked} onClick={() => onStart(mission)}>
        {status === 'locked' ? 'Hoàn thành chương trước' : status === 'done' ? 'Chơi lại để cải thiện' : 'Bắt đầu chinh phục'}
        {status === 'locked' ? <LockKeyhole size={15}/> : <ArrowRight size={17}/>} 
      </button>
    </div>
  </article>;
}

function LeaderboardPanel({ list, playerId, openAll }) {
  return <section className="panel leaderboard-panel">
    <div className="panel-title"><span className="panel-icon"><Trophy size={18}/></span><div><b>Bảng vinh danh</b><small>Top nhà thám hiểm</small></div><button title="Xem bảng xếp hạng" onClick={openAll}><ArrowUpRight size={18}/></button></div>
    {list.length ? <div className="rank-list">
      {list.slice(0, 5).map((p, index) => <div className={`rank-item ${p.id === playerId ? 'you' : ''}`} key={p.id}>
        <span className={`rank-number rank-${index + 1}`}>{index === 0 ? <Crown size={17}/> : String(index + 1).padStart(2,'0')}</span>
        <Avatar type={p.avatar_key} size="sm"/>
        <div className="rank-name"><b>{p.nickname}{p.id === playerId ? ' (Bạn)' : ''}</b><small>{p.missions_done} chiến dịch</small></div>
        <span className="rank-score">{format(p.xp)} <small>XP</small></span>
      </div>)}
    </div> : <div className="empty-mini">Chưa có người chơi nào. Bạn có thể là người đầu tiên!</div>}
    <button className="panel-bottom-button" onClick={openAll}>Xem toàn bộ bảng xếp hạng <ChevronRight size={17}/></button>
  </section>;
}

function Dashboard({ data, go, onStart }) {
  const { player, missions, leaderboard, stats } = data;
  const next = missions.find((m) => m.unlocked && !m.completed) || missions.find((m) => m.unlocked);
  const completed = missions.filter((m) => m.completed).length;
  return <div className="page-enter">
    <div className="page-top"><div><span className="greeting-dot"/> TRUNG TÂM HUẤN LUYỆN LỊCH SỬ</div><div className="page-top-right"><Shield size={14}/> Học • Chơi • Ghi nhớ</div></div>
    <div className="welcome-line"><div><h1>Chào {player?.nickname || 'nhà thám hiểm'} <span className="wave">✌</span></h1><p>Sẵn sàng viết tiếp hành trình chinh phục lịch sử hôm nay?</p></div><div className="date-pill"><Activity size={16}/> HÀNH TRÌNH VNR202</div></div>
    <section className="hero-banner">
      <div className="hero-grid"/>
      <div className="hero-copy"><div className="hero-kicker"><span/> THE HISTORY QUEST • SEASON 01</div>
        <h2>Lịch sử không chỉ để nhớ.<br/><em>Lịch sử để chinh phục.</em></h2>
        <p>Mỗi câu trả lời là một bước tiến. Vượt qua 6 chiến dịch, mở khóa kiến thức và chạm đỉnh vinh quang!</p>
        <div className="hero-actions">
          <button className="btn btn-primary" onClick={() => next ? onStart(next) : go('missions')}><Play size={17} fill="currentColor"/> {completed ? 'Tiếp tục hành trình' : 'Bắt đầu phiêu lưu'}</button>
          <button className="btn btn-ghost" onClick={() => go('timeline')}>Xem dòng thời gian <ArrowUpRight size={17}/></button>
        </div>
      </div>
      <div className="hero-art" aria-hidden="true"><div className="orbit orbit-outer"/><div className="orbit orbit-middle"/><div className="orbit orbit-inner"/><div className="planet-core"><span>VNR</span><strong>202</strong><small>QUEST</small></div><span className="float-chip float-one"><Sparkles size={16}/> KHÁM PHÁ</span><span className="float-chip float-two"><Zap size={15}/> LEVEL UP</span><span className="hero-spark hs-1">✦</span><span className="hero-spark hs-2">✧</span><span className="hero-spark hs-3">✦</span></div>
    </section>
    <div className="stats-grid">
      <Stat icon={Zap} color="purple" label="TỔNG ĐIỂM KINH NGHIỆM" value={format(player?.xp)} subtitle={`Cấp độ ${levelOf(player?.xp)}`}/>
      <Stat icon={Flag} color="teal" label="CHIẾN DỊCH HOÀN THÀNH" value={`${completed} / ${missions.length}`} subtitle={`${missions.length - completed} chiến dịch phía trước`}/>
      <Stat icon={Target} color="pink" label="TỶ LỆ CHÍNH XÁC" value={`${stats.accuracy}%`} subtitle={`${stats.totalCorrect}/${stats.totalAnswers} câu đúng`}/>
      <Stat icon={Medal} color="amber" label="HẠNG HIỆN TẠI" value={stats.rank ? `#${stats.rank}` : '—'} subtitle={`${format(player?.coins)} xu tích lũy`}/>
    </div>
    <div className="dashboard-lower">
      <section className="main-feed">
        <SectionHead eyebrow="BẢN ĐỒ CHINH PHỤC" title="Các chiến dịch lịch sử" desc="Mở khóa từng chương và thăng cấp bằng kiến thức." action="Xem tất cả" onAction={() => go('missions')}/>
        <div className="mission-grid compact">{missions.slice(0, 3).map((m, i) => <MissionCard key={m.slug} mission={m} index={i} onStart={onStart}/>)}</div>
      </section>
      <aside className="feed-aside">
        <LeaderboardPanel list={leaderboard} playerId={player?.id} openAll={() => go('leaderboard')}/>
        <section className="panel journey-panel"><div className="journey-heading"><div className="journey-icon"><Layers3 size={19}/></div><div><b>Hành trình của bạn</b><small>Tiến trình đến cấp tiếp theo</small></div></div>
          <div className="level-row"><span>LEVEL {levelOf(player?.xp).toString().padStart(2,'0')}</span><strong>{(player?.xp || 0) % 250} <small>/ 250 XP</small></strong></div>
          <div className="progress-track level-progress"><span style={{ width: `${percent((player?.xp || 0) % 250, 250)}%` }}/></div>
          <p>Hoàn thành chiến dịch mới để nhận thưởng và mở khóa chương tiếp theo.</p>
        </section>
      </aside>
    </div>
  </div>;
}

function Missions({ missions, onStart, player }) {
  const done = missions.filter((m) => m.completed).length;
  return <div className="page-enter">
    <div className="page-top"><div><span className="greeting-dot"/> NHIỆM VỤ CỦA NHÀ THÁM HIỂM</div><div className="page-top-right"><Gem size={14}/> {format(player?.coins)} xu</div></div>
    <div className="inner-header"><span className="eyebrow">CHỌN CUỘC PHIÊU LƯU</span><h1>Bản đồ chiến dịch <span className="heading-purple">✦</span></h1><p>6 chặng kiến thức, mỗi chặng 10 câu hỏi từ tài liệu PDF. Hoàn thành lần lượt để mở khóa chặng mới.</p></div>
    <div className="journey-progress"><div className="journey-progress-icon"><Compass size={28}/></div><div className="journey-progress-text"><b>Tiến trình chinh phục</b><span>Đã hoàn thành {done} trên {missions.length} chiến dịch</span></div><div className="journey-progress-bar"><div className="progress-track"><span style={{width: `${percent(done,missions.length)}%`}}/></div><strong>{percent(done,missions.length)}%</strong></div></div>
    <div className="mission-grid full">{missions.map((m,i) => <MissionCard key={m.slug} mission={m} index={i} onStart={onStart}/>)}</div>
    <div className="info-note"><CircleHelp size={19}/><span><b>Cách nhận XP:</b> +35 XP cho mỗi câu đúng cải thiện kỷ lục của bạn, thêm +60 XP khi hoàn thành chiến dịch lần đầu. Chơi lại chỉ cộng điểm khi vượt kỷ lục trước đó.</span></div>
  </div>;
}

function Timeline({ events }) {
  const [filter, setFilter] = useState('Tất cả');
  const [active, setActive] = useState(null);
  const shown = useMemo(() => events.filter((e) => filter === 'Tất cả' || e.period_key === filter), [events, filter]);
  const selected = events.find((e) => e.id === active) || shown[0];
  return <div className="page-enter">
    <div className="page-top"><div><span className="greeting-dot"/> THƯ VIỆN SỰ KIỆN</div><div className="page-top-right"><Clock3 size={14}/> {events.length} cột mốc</div></div>
    <div className="inner-header"><span className="eyebrow">LỊCH SỬ THEO DÒNG THỜI GIAN</span><h1>Những cột mốc <span className="heading-purple">không thể quên.</span></h1><p>Khám phá các sự kiện đã định hình hành trình lịch sử Việt Nam.</p></div>
    <div className="filter-bar">{filters.map((f) => <button key={f} className={f === filter ? 'chosen' : ''} onClick={() => {setFilter(f);setActive(null);}}>{f}</button>)}</div>
    <div className="timeline-layout"><div className="timeline-list">
      {shown.map((e, i) => <button key={e.id} className={`timeline-item ${(selected?.id === e.id) ? 'selected' : ''}`} onClick={() => setActive(e.id)}>
        <span className="timeline-node"><span/></span>
        <span className="timeline-year">{e.event_year}</span>
        <span className="timeline-text"><b>{e.title}</b><small>{e.event_date}</small></span>
        <ChevronRight size={18}/>
      </button>)}
      {!shown.length && <div className="empty-mini">Chưa có dữ liệu trong giai đoạn này.</div>}
    </div>
    <div className="timeline-detail">{selected ? <>
      <div className="detail-top"><span>HỒ SƠ LỊCH SỬ</span><ScrollText size={24}/></div>
      <div className="detail-year">{selected.event_year}<span>✦</span></div>
      <div className="detail-date"><Clock3 size={15}/>{selected.event_date}</div>
      <h2>{selected.title}</h2><p>{selected.summary}</p>
      {selected.source_file_path && <a className="resource-link" target="_blank" rel="noreferrer" href={`${selected.source_file_path}#page=${selected.source_page}`}><FileText size={17}/> Xem PDF tham chiếu • Trang {selected.source_page} <ExternalLink size={15}/></a>}
      <div className="detail-bottom"><Shield size={16}/> VNR202 • DÒNG CHẢY LỊCH SỬ</div>
    </> : <div>Chọn một mốc thời gian để xem thông tin.</div>}</div></div>
    <p className="source-note">Các mốc thời gian có đính kèm slide gốc. Dữ liệu từ PDF của học phần; bạn có thể mở trang nguồn để đối chiếu.</p>
  </div>;
}

function Library() {
  const [chapter, setChapter] = useState('');
  const [search, setSearch] = useState('');
  const [documents, setDocuments] = useState([]);
  const [selected, setSelected] = useState(null);
  const [lesson, setLesson] = useState(null);
  const [pageNumber, setPageNumber] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const chapters = [
    ['', 'Tất cả'], ['intro','Nhập môn'], ['chapter1','Chương 1'],
    ['chapter2','Chương 2'],['chapter3','Chương 3']
  ];

  useEffect(() => {
    let current = true;
    const query = new URLSearchParams();
    if (chapter) query.set('chapter',chapter);
    if (search.trim()) query.set('search',search.trim());
    api(`/library?${query.toString()}`).then(r => {if(current){setDocuments(r.documents);setError('');}})
      .catch(e => {if(current) setError(e.message);});
    return () => {current=false;};
  }, [chapter,search]);

  const openLesson = async (doc) => {
    setSelected(doc);setLesson(null);setPageNumber(1);setBusy(true);setError('');
    try { const d=await api(`/library/${encodeURIComponent(doc.id)}`);setLesson(d); }
    catch(e){setError(e.message);}finally{setBusy(false);}
  };
  const page = lesson?.pages?.find(p => p.page_number === pageNumber);
  const filePath = lesson?.document?.file_path;
  return <div className="page-enter">
    <div className="page-top"><div><span className="greeting-dot"/> KHO TRI THỨC VNR202</div><div className="page-top-right"><BookOpen size={14}/> TÀI LIỆU HỌC PHẦN</div></div>
    <div className="inner-header"><span className="eyebrow">TÀI LIỆU NGUỒN CỦA BẠN</span>
      <h1>Thư viện <span className="heading-purple">29 buổi học.</span></h1>
      <p>435 trang từ 29 PDF gốc. Xem nội dung theo chương, tìm kiếm kiến thức và mở slide trực tiếp.</p></div>
    <div className="library-toolbar"><div className="library-search"><Search size={18}/>
      <input aria-label="Tìm trong bài học" value={search} onChange={e=>setSearch(e.target.value)} placeholder="Tìm theo tên bài hoặc nội dung slide..."/></div>
      <div className="library-filter">{chapters.map(([id,label])=><button key={id} onClick={()=>setChapter(id)} className={chapter===id?'chosen':''}>{label}</button>)}</div>
    </div>
    {error && <div className="library-alert">{error}</div>}
    <div className="library-grid">
      <section className="library-list" aria-label="Danh sách các buổi học">
        <div className="library-list-header"><b>{documents.length} bài học</b><span>Chọn để xem chi tiết</span></div>
        {documents.map(d=><button key={d.id} className={`library-item ${selected?.id===d.id?'current':''}`} onClick={()=>openLesson(d)}>
          <span className="library-item-num">{String(d.session_number).padStart(2,'0')}</span>
          <span className="library-item-text"><small>{d.chapter_label}</small><b>{d.title}</b><span>{d.page_count} trang PDF {search.trim() ? `• ${d.match_count} trang khớp` : ''}</span></span><ChevronRight size={18}/>
        </button>)}
        {!documents.length && !error && <div className="library-empty">Không tìm thấy bài học phù hợp.</div>}
      </section>
      <section className="library-reader">
        {busy ? <div className="library-empty">Đang tải nội dung buổi học...</div> : lesson ? <>
          <div className="library-reader-head"><div><small>SESSION {String(lesson.document.session_number).padStart(2,'0')} • {lesson.document.chapter_label}</small>
            <h2>{lesson.document.title}</h2></div><a className="library-open" href={filePath} target="_blank" rel="noreferrer">Mở toàn bộ PDF <ExternalLink size={15}/></a></div>
          <div className="library-page-controls"><button disabled={pageNumber===1} onClick={()=>setPageNumber(n=>Math.max(1,n-1))}><ChevronLeft size={17}/> Trang trước</button>
            <span>Trang <strong>{pageNumber}</strong> / {lesson.pages.length}</span>
            <button disabled={pageNumber===lesson.pages.length} onClick={()=>setPageNumber(n=>Math.min(lesson.pages.length,n+1))}>Trang tiếp <ChevronRight size={17}/></button></div>
          <iframe className="library-pdf" title={`Slide gốc buổi ${lesson.document.session_number}, trang ${pageNumber}`} key={`${lesson.document.id}-${pageNumber}`} src={`${filePath}#page=${pageNumber}&toolbar=0`}/>
          <div className="library-page-text"><div><FileText size={18}/> <b>Nội dung trích xuất • Trang {pageNumber}</b></div><p>{page?.content || 'Trang này không chứa văn bản trích xuất được. Hãy xem trực tiếp hình ảnh PDF ở trên.'}</p></div>
          <p className="library-disclaimer">Văn bản được trích xuất tự động từ slide; với bảng và sơ đồ, PDF gốc là bản trình bày đầy đủ và chính xác hơn.</p>
        </> : <div className="library-placeholder"><div className="library-placeholder-icon"><BookOpen size={42}/></div>
          <h2>Mở một buổi học</h2><p>Chọn một tài liệu bên trái để đọc nội dung, lật trang và xem slide gốc ngay tại đây.</p>
          <div className="library-facts"><span>29 PDF</span><span>435 trang</span><span>4 phần kiến thức</span></div>
        </div>}
      </section>
    </div>
  </div>;
}

function Leaderboard({ leaderboard, player }) {
  const podium = leaderboard.slice(0, 3);
  return <div className="page-enter">
    <div className="page-top"><div><span className="greeting-dot"/> HALL OF FAME</div><div className="page-top-right"><Trophy size={14}/> VNR202 QUEST</div></div>
    <div className="inner-header"><span className="eyebrow">NHỮNG NHÀ CHINH PHỤC XUẤT SẮC</span><h1>Bảng xếp hạng <span className="heading-purple">vinh quang.</span></h1><p>Thứ hạng được tính theo XP thực tế lưu trên Neon PostgreSQL.</p></div>
    <div className="podium">
      {[podium[1],podium[0],podium[2]].map((p, i) => <div className={`podium-card podium-${i}`} key={p?.id || i}>
        <span className="podium-medal">{['🥈','🥇','🥉'][i]}</span>
        {p ? <><Avatar type={p.avatar_key} size="lg"/><h3>{p.nickname}{p.id === player?.id ? ' (Bạn)' : ''}</h3><span>{format(p.xp)} XP</span><small>Hạng {i === 1 ? 1 : i === 0 ? 2 : 3}</small></> : <><div className="podium-empty"><UserRound/></div><h3>Chưa có</h3><span>— XP</span><small>Hạng {i === 1 ? 1 : i === 0 ? 2 : 3}</small></>}
      </div>)}
    </div>
    <div className="leaderboard-table"><div className="table-heading"><span>THỨ HẠNG</span><span>NGƯỜI CHƠI</span><span>CHIẾN DỊCH</span><span>XP</span></div>
      {leaderboard.map((p, i) => <div className={`table-row ${p.id === player?.id ? 'self' : ''}`} key={p.id}>
        <span className="table-position">#{String(i+1).padStart(2,'0')}</span><span className="table-user"><Avatar type={p.avatar_key} size="sm"/><b>{p.nickname}</b>{p.id === player?.id && <small>BẠN</small>}</span><span>{p.missions_done}/6</span><strong>{format(p.xp)} <small>XP</small></strong>
      </div>)}
      {!leaderboard.length && <div className="empty-mini">Chưa có dữ liệu xếp hạng.</div>}
    </div>
    <div className="info-note"><Shield size={18}/><span>Bảng xếp hạng trong bản MVP dùng hồ sơ khách lưu theo mã UUID trên thiết bị. Để triển khai công khai, cần thêm đăng nhập xác thực và giới hạn lượt chơi.</span></div>
  </div>;
}

function Game({ session, index, choice, feedback, answering, finishing, onAnswer, onNext, onExit }) {
  const question = session.questions[index];
  const total = session.questions.length;
  return <div className="game-screen page-enter">
    <div className="game-top"><button className="back-button" onClick={onExit}><ArrowLeft size={17}/> Rời lượt chơi</button><span className="game-top-pill"><Swords size={16}/> {session.mission.title}</span></div>
    <div className="game-intro"><div className="eyebrow"><span className="tiny-diamond"/> THỬ THÁCH LỊCH SỬ</div><h1>Đấu trường trí tuệ <span>⚡</span></h1><p>Trả lời chính xác, tích lũy kiến thức, mở khóa chặng tiếp theo.</p></div>
    <div className="quiz-shell"><div className="quiz-topline"><span>CÂU HỎI <strong>{String(index+1).padStart(2,'0')}</strong> / {String(total).padStart(2,'0')}</span><span><Target size={16}/> {percent(index, total)}% HOÀN THÀNH</span></div>
      <div className="quiz-segments">{Array.from({length:total}).map((_,i) => <span key={i} className={i < index ? 'finished' : i === index ? 'current' : ''}/>)}</div>
      <div className="quiz-question-tag"><BookOpen size={16}/> {session.mission.era} • KIẾN THỨC CỐT LÕI</div>
      <h2>{question.prompt}</h2>
      <div className="answers">{question.options.map((option, i) => {
        const isSelected = choice === i;
        const isRight = feedback && feedback.correctIndex === i;
        const isWrong = feedback && isSelected && !feedback.correct;
        return <button key={i} disabled={choice !== null || answering} onClick={() => onAnswer(i)} className={`answer ${isSelected ? 'selected' : ''} ${isRight ? 'correct' : ''} ${isWrong ? 'wrong' : ''}`}>
          <span className="answer-letter">{String.fromCharCode(65+i)}</span><span>{option}</span>{isRight ? <CheckCircle2 size={22}/> : isWrong ? <XCircle size={22}/> : <span className="answer-circle"/>}
        </button>;
      })}</div>
      {answering && <div className="answer-loading">Đang kiểm tra đáp án trên máy chủ...</div>}
      {feedback && <div className={`feedback ${feedback.correct ? 'good' : 'bad'}`}>
        <div className="feedback-heading">{feedback.correct ? <><CheckCircle2 size={22}/> Chính xác! Tuyệt vời.</> : <><CircleHelp size={22}/> Chưa chính xác, nhưng bạn vừa học thêm!</>}</div>
        <p>{feedback.explanation}</p>
        {question.source_file_path && <a className="resource-link" href={`${question.source_file_path}#page=${question.source_page}`} target="_blank" rel="noreferrer"><FileText size={16}/> Kiểm tra slide gốc: {question.source_title}, trang {question.source_page} <ExternalLink size={14}/></a>}
      </div>}
      <div className="quiz-footer"><span><Shield size={15}/> Đáp án được kiểm tra ở máy chủ</span><button className="btn btn-primary" disabled={!feedback || finishing} onClick={onNext}>{finishing ? 'Đang tổng kết...' : index === total-1 ? 'Hoàn thành chiến dịch' : 'Câu tiếp theo'}<ArrowRight size={17}/></button></div>
    </div>
  </div>;
}

function Result({ result, onRetry, onHome, onMissions }) {
  const accuracy = percent(result.correct, result.total);
  const praise = accuracy === 100 ? 'Xuất sắc! Tuyệt đối!' : accuracy >= 60 ? 'Hoàn thành tốt lắm!' : 'Bạn đã vượt qua thử thách!';
  return <div className="result-screen page-enter">
    <div className="result-halo"><Award size={60}/></div><div className="eyebrow">CHIẾN DỊCH HOÀN THÀNH</div>
    <h1>{praise}</h1><p className="result-desc">Bạn đã hoàn tất <b>{result.mission.title}</b>. Mỗi lần ôn tập là một bước tiến mới.</p>
    <div className="result-score"><strong>{result.correct}<span> / {result.total}</span></strong><small>CÂU TRẢ LỜI ĐÚNG</small></div>
    <div className="result-grid"><div><CheckCircle2 size={22}/><span>Độ chính xác</span><b>{accuracy}%</b></div><div><Zap size={22}/><span>XP nhận được</span><b>+{format(result.xpEarned)}</b></div><div><Gem size={22}/><span>Xu nhận được</span><b>+{format(result.coinsEarned)}</b></div></div>
    {result.xpEarned === 0 && <p className="result-tip">Bạn đã hoàn thành lượt chơi nhưng chưa vượt kỷ lục cá nhân. Lần tới cố gắng trả lời đúng nhiều câu hơn nhé!</p>}
    <div className="result-actions"><button className="btn btn-ghost" onClick={onRetry}><RotateCcw size={17}/> Chơi lại</button><button className="btn btn-primary" onClick={onMissions}>Chặng tiếp theo <ArrowRight size={17}/></button></div>
    <button className="return-link" onClick={onHome}>Trở về tổng quan</button>
  </div>;
}

function JoinModal({ onJoin, working, error }) {
  const [nickname, setNickname] = useState('');
  const [avatar, setAvatar] = useState('astronaut');
  return <div className="modal-layer" role="presentation"><div className="join-modal" role="dialog" aria-modal="true" aria-label="Tạo hồ sơ người chơi">
    <div className="join-brand"><span className="brand-mark"><Sparkles size={25}/></span><b>VNR<span>QUEST</span></b></div>
    <div className="join-illustration"><div className="join-glow"/><div className="join-center"><Orbit size={55}/></div><span>✦</span><span>✧</span></div>
    <div className="eyebrow">CHÀO MỪNG ĐẾN VỚI THẾ GIỚI LỊCH SỬ</div><h2>Đặt tên cho hành trình của bạn</h2><p>Chọn biệt danh và nhân vật đại diện để lưu điểm trên Neon PostgreSQL.</p>
    <form onSubmit={(e) => {e.preventDefault();onJoin(nickname, avatar);}}>
      <label className="field-label" htmlFor="nickname">BIỆT DANH CỦA BẠN</label>
      <input id="nickname" minLength={2} maxLength={32} value={nickname} onChange={(e) => setNickname(e.target.value)} required placeholder="Ví dụ: Nhà sử học trẻ" autoFocus/>
      <label className="field-label">CHỌN BIỂU TƯỢNG</label>
      <div className="avatar-picker">{Object.entries(avatarIcons).map(([id, Icon]) => <button type="button" aria-label={avatarLabels[id]} title={avatarLabels[id]} className={avatar === id ? 'picked' : ''} onClick={() => setAvatar(id)} key={id}><Icon size={24}/></button>)}</div>
      {error && <div className="form-error">{error}</div>}
      <button type="submit" className="btn btn-primary join-submit" disabled={working || nickname.trim().length < 2}>{working ? 'Đang tạo hồ sơ...' : 'Bắt đầu khám phá'}<ArrowRight size={18}/></button>
    </form>
    <small className="join-note"><Shield size={13}/> Phiên bản khách: lưu mã người chơi trên trình duyệt, chưa có đăng nhập bằng mật khẩu.</small>
  </div></div>;
}

export default function App() {
  const [view, setView] = useState('dashboard');
  const [overview, setOverview] = useState(null);
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [fatal, setFatal] = useState('');
  const [toast, setToast] = useState('');
  const [showJoin, setShowJoin] = useState(false);
  const [joining, setJoining] = useState(false);
  const [joinError, setJoinError] = useState('');
  const [mobileOpen, setMobileOpen] = useState(false);
  const [session, setSession] = useState(null);
  const [questionIndex, setQuestionIndex] = useState(0);
  const [choice, setChoice] = useState(null);
  const [feedback, setFeedback] = useState(null);
  const [answering, setAnswering] = useState(false);
  const [finishing, setFinishing] = useState(false);
  const [result, setResult] = useState(null);
  const [starting, setStarting] = useState(false);

  const load = useCallback(async (id) => {
    try {
      const [o, t] = await Promise.all([api(`/overview${id ? `?playerId=${encodeURIComponent(id)}` : ''}`),api('/timeline')]);
      setOverview(o);setEvents(t.events);setFatal('');
      if (!o.player) setShowJoin(true);
    } catch (err) { setFatal(err.message); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => {
    const id = localStorage.getItem(KEY);
    load(id);
  }, [load]);

  const go = (name) => {setView(name);setMobileOpen(false);window.scrollTo({top:0,behavior:'smooth'});};
  const playerId = overview?.player?.id;
  const notify = (error) => setToast(error.message || String(error));

  const join = async (nickname, avatar) => {
    setJoining(true); setJoinError('');
    try {
      const r = await api('/players', { method: 'POST', body: JSON.stringify({ nickname, avatar }) });
      localStorage.setItem(KEY, r.player.id);
      await load(r.player.id);
      setShowJoin(false);go('dashboard');
    } catch (e) { setJoinError(e.message); }
    finally { setJoining(false); }
  };
  const switchPlayer = async () => {
    if (view === 'game') return;
    localStorage.removeItem(KEY);
    setOverview((old) => old ? { ...old, player: null } : old);
    setShowJoin(true);setJoinError('');go('dashboard');
  };
  const startMission = async (mission) => {
    if (!mission?.unlocked) return;
    if (!playerId) { setShowJoin(true); return; }
    if (starting) return;
    setStarting(true);
    try {
      const r = await api('/sessions', { method: 'POST', body: JSON.stringify({ playerId, missionSlug: mission.slug }) });
      setSession({ ...r, mission });setQuestionIndex(0);setChoice(null);setFeedback(null);setResult(null);go('game');
    } catch (err) { notify(err); }
    finally { setStarting(false); }
  };
  const answer = async (index) => {
    if (answering || choice !== null || !session) return;
    setChoice(index);setAnswering(true);
    try {
      const response = await api(`/sessions/${session.sessionId}/answer`, {method:'POST',body:JSON.stringify({ playerId, questionId: session.questions[questionIndex].id, choiceIndex: index })});
      setFeedback(response);
    } catch (err) { setChoice(null);notify(err); }
    finally { setAnswering(false); }
  };
  const next = async () => {
    if (!feedback || !session) return;
    if (questionIndex < session.questions.length - 1) {
      setQuestionIndex((n) => n + 1);setChoice(null);setFeedback(null);
      return;
    }
    if (finishing) return;
    setFinishing(true);
    try {
      const score = await api(`/sessions/${session.sessionId}/finish`, { method: 'POST', body: JSON.stringify({ playerId }) });
      setResult({ ...score, mission: session.mission });setSession(null);go('result');
      await load(playerId);
    } catch (err) { notify(err); }
    finally { setFinishing(false); }
  };
  const exitGame = () => {
    if (answering || finishing) return;
    if (window.confirm('Rời lượt chơi? Các câu đã trả lời trong lượt này sẽ không được tính XP.')) { setSession(null);go('missions'); }
  };

  if (loading) return <div className="boot-screen"><div className="boot-logo"><Sparkles size={32}/></div><h2>VNR QUEST</h2><p>Đang tải hành trình lịch sử...</p><div className="spinner"/></div>;
  if (fatal && !overview) return <div className="boot-screen error-boot"><div className="boot-logo"><XCircle size={32}/></div><h2>Chưa kết nối được dữ liệu</h2><p>{fatal}</p><div className="error-instructions">Kiểm tra file <code>.env</code> có <code>DATABASE_URL</code>, chạy <code>npm run db:init</code> rồi chạy <code>npm run dev</code>.</div><button className="btn btn-primary" onClick={() => {setLoading(true);load(localStorage.getItem(KEY));}}>Thử kết nối lại <RotateCcw size={16}/></button></div>;
  if (!overview) return null;
  const { missions, leaderboard } = overview;
  return <div className="app-shell">
    <Sidebar view={view} go={go} onSwitch={switchPlayer} player={overview.player} mobileOpen={mobileOpen} setMobileOpen={setMobileOpen}/>
    <div className="content-area"><header className="topbar"><button className="mobile-menu" aria-label="Mở điều hướng" onClick={() => setMobileOpen(true)}><Menu size={24}/></button>
      <div className="topbar-breadcrumb"><span>VNR202 QUEST</span><ChevronRight size={15}/><b>{({dashboard:'Tổng quan',missions:'Chiến dịch',timeline:'Dòng thời gian',library:'Thư viện bài học',leaderboard:'Bảng xếp hạng',game:'Thử thách',result:'Kết quả'})[view]}</b></div>
      <div className="topbar-actions"><div className="topbar-chip"><Gem size={17}/><b>{format(overview.player?.coins)}</b><span>XU</span></div><div className="topbar-xp"><Zap size={17} fill="currentColor"/><b>{format(overview.player?.xp)}</b><span>XP</span></div><button className="topbar-user" title="Đổi người chơi" onClick={switchPlayer}><Avatar type={overview.player?.avatar_key} size="sm"/><span>{overview.player?.nickname || 'Khách'}</span></button></div>
    </header>
    <main className="main-content">
      {view === 'dashboard' && <Dashboard data={overview} go={go} onStart={startMission}/>}
      {view === 'missions' && <Missions missions={missions} player={overview.player} onStart={startMission}/>}
      {view === 'timeline' && <Timeline events={events}/>}
      {view === 'library' && <Library/>}
      {view === 'leaderboard' && <Leaderboard leaderboard={leaderboard} player={overview.player}/>}
      {view === 'game' && session && <Game session={session} index={questionIndex} choice={choice} feedback={feedback} answering={answering} finishing={finishing} onAnswer={answer} onNext={next} onExit={exitGame}/>}
      {view === 'result' && result && <Result result={result} onRetry={() => startMission(missions.find((m) => m.slug === result.mission.slug))} onMissions={() => go('missions')} onHome={() => go('dashboard')}/>}
    </main>
    <footer className="footer"><span>© VNR202 QUEST • HỌC LỊCH SỬ THEO CÁCH CỦA BẠN</span><span>Built with ♥ for curious minds.</span></footer>
    </div>
    {showJoin && !fatal && <JoinModal onJoin={join} working={joining} error={joinError}/>}
    {toast && <div className="toast-error"><XCircle size={18}/><span>{toast}</span><button onClick={() => setToast('')}><X size={18}/></button></div>}
    {starting && <div className="starting-overlay"><div className="spinner"/><b>Đang khởi tạo chiến dịch...</b></div>}
  </div>;
}
