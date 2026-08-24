<?php
/**
 * 首页模板
 *
 * @package videoplayer
 */

get_header();

$features = array(
	array(
		'num' => '01',
		'cn'  => '双解码引擎',
		'en'  => 'Dual Decode Engine',
		'desc'=> 'AVFoundation 硬件解码默认省电流畅，FFmpeg 软解兜底通吃冷门格式；无法播放时约 3ms 自动切换，也可以 ⌥⌘R 手动切换。',
		'kicker' => 'Dual Engine',
		'title'  => '两种引擎，一种体验，没有打不开的文件。',
		'lead'   => '常见格式走硬件解码，冷门格式自动落入 FFmpeg 软解。对使用者而言，切换完全无感——你只需要双击文件，其余交给播放器。',
		'minis'  => array(
			array( 'b' => 'AVFoundation 硬解（默认）', 's' => 'GPU 解码，省电、流畅，覆盖 MP4 / MOV / MKV / WebM 等常见格式。' ),
			array( 'b' => 'FFmpeg 软解兜底', 's' => 'DivX/Xvid AVI、FLV、WMV、FFV1、DTS 音轨等一切冷门格式，无死角。' ),
			array( 'b' => '自动回退（约 3ms）', 's' => 'AVPlayer 解码失败瞬间切换到 FFmpeg 后端，几乎无感。' ),
			array( 'b' => 'VideoToolbox GPU 加速', 's' => '软解后端同样支持硬件解码，4K 更流畅省电。' ),
		),
		'visual' => 'engine',
	),
	array(
		'num' => '02',
		'cn'  => '字幕系统',
		'en'  => 'Subtitles',
		'desc'=> '外挂 srt/vtt 自动加载，MKV 内嵌字幕提取与选择；字号、颜色、位置可调，G/H 一键同步微调。',
		'kicker' => 'Subtitles',
		'title'  => '字幕这件事，本来就不该折腾。',
		'lead'   => '同目录同名字幕自动挂上；内嵌字幕轨随意切换，并按文件记住你的选择。字幕对不上轴？按两下 G/H 就好。',
		'minis'  => array(
			array( 'b' => '外挂字幕自动加载', 's' => '同名 .srt / .vtt（含 .zh / .chs 等命名）打开视频即挂载。' ),
			array( 'b' => '内嵌字幕轨提取', 's' => 'MKV/MP4 内嵌 SRT/ASS/VTT/mov_text 一次性提取，右键切换。' ),
			array( 'b' => '样式可调', 's' => '字号 14–48、颜色、距底距离，偏好设置里所见即所得。' ),
			array( 'b' => '同步微调 G/H', 's' => '±0.5 秒逐档调整，带屏显提示，支持 ±60 秒范围。' ),
		),
		'visual' => 'subtitle',
	),
	array(
		'num' => '03',
		'cn'  => '多音轨与章节',
		'en'  => 'Audio Tracks & Chapters',
		'desc'=> '双语 MKV 中英音轨一键切换并按文件记忆；章节跳转、进度条刻度、媒体信息面板一应俱全。',
		'kicker' => 'Audio & Chapters',
		'title'  => '多音轨、章节、媒体信息，专业播放器的标配。',
		'lead'   => '双语电影一键切中文/英文音轨，下次打开自动恢复；章节直接显示在进度条上；⌘I 查看编码、码率、分辨率。',
		'minis'  => array(
			array( 'b' => '多音轨切换', 's' => '右键 → 音轨，任意切换；软解模式重建解码器无缝续播。' ),
			array( 'b' => '按文件记忆', 's' => '音轨与字幕轨选择按文件持久化，重开自动恢复。' ),
			array( 'b' => '章节跳转', 's' => 'MKV/MP4 章节刻度显示在进度条上，右键直达任意章节。' ),
			array( 'b' => '媒体信息 ⌘I', 's' => '容器、编码、分辨率、帧率、码率、声道，一览无余。' ),
		),
		'visual' => 'audio',
	),
	array(
		'num' => '04',
		'cn'  => '播放控制',
		'en'  => 'Playback Control',
		'desc'=> '0.25x–4x 倍速跨启动记忆、A-B 循环、迷你模式、画中画、音频延迟微调、媒体键与 Now Playing。',
		'kicker' => 'Playback',
		'title'  => '看片、学外语、扒素材，每种场景都顺手。',
		'lead'   => 'A/B 循环反复听一段对白；迷你模式悬浮置顶摸鱼看比赛；倍速自动记住，下次打开还是 1.5x。',
		'minis'  => array(
			array( 'b' => '倍速 0.25–4x', 's' => '控制条倍速按钮一键切换，跨启动记忆。' ),
			array( 'b' => 'A-B 循环', 's' => 'A/B 键设点反复播放，学外语、扒片神器。' ),
			array( 'b' => '迷你模式 ⌘M', 's' => '无边框置顶小窗，双击或 Esc 退出。' ),
			array( 'b' => '画中画 + 媒体键', 's' => 'macOS 画中画；F7/F8/F9 播放键与控制中心 Now Playing。' ),
		),
		'visual' => 'playback',
	),
	array(
		'num' => '05',
		'cn'  => '快捷键与播放列表',
		'en'  => 'Shortcuts & Playlist',
		'desc'=> '空格/K 播放、J/L 快进快退、←→ 微调、G/H 字幕、A/B 循环点；列表拖拽排序、自然排序连播。',
		'kicker' => 'Shortcuts & Playlist',
		'title'  => '手不离键盘，连续剧一部接一部。',
		'lead'   => '打开文件夹自动按自然顺序连播（第2集在第10集前）；播放列表侧栏拖拽排序、双击切换；关闭后从上次位置续播。',
		'minis'  => array(
			array( 'b' => '完整快捷键', 's' => '空格/K 播放暂停，J/L 快进 10 秒，←→ 5 秒，↑↓ 音量。' ),
			array( 'b' => '播放列表侧栏', 's' => '⌘⇧L 开关，双击切换、Delete 移除、拖拽排序。' ),
			array( 'b' => '自然排序连播', 's' => '文件夹连播按数字感知排序，剧集顺序不乱。' ),
			array( 'b' => '断点续播', 's' => '每个文件记忆播放位置，最近播放菜单显示进度。' ),
		),
		'visual' => 'playlist',
	),
	array(
		'num' => '06',
		'cn'  => '更新与分发',
		'en'  => 'Updates & Distribution',
		'desc'=> 'Sparkle 自动更新静默升级；Developer ID 签名 + Apple 公证，双击即装零拦截；MIT 开源、零外部依赖。',
		'kicker' => 'Updates & Distribution',
		'title'  => '装一次，之后每次更新都自动完成。',
		'lead'   => '应用启动时静默检查新版本，一键更新。全部代码开源在 GitHub，构建脚本与发布流水线完全透明。',
		'minis'  => array(
			array( 'b' => 'Sparkle 自动更新', 's' => '后台检查新版本，应用菜单内随时手动检查。' ),
			array( 'b' => '签名 + 公证', 's' => 'Apple Developer ID 签名并通过公证，无 Gatekeeper 拦截。' ),
			array( 'b' => 'MIT 开源', 's' => '全部源码、构建脚本、发布流水线公开可查。' ),
			array( 'b' => '零外部依赖', 's' => 'FFmpeg 全部动态库内嵌，单文件分发，无需安装任何组件。' ),
		),
		'visual' => 'update',
	),
);

$changelog_cat = vp_changelog_cat_id();
$changelog = array();
if ( $changelog_cat ) {
	$changelog = get_posts(
		array(
			'category'       => $changelog_cat,
			'numberposts'    => 3,
			'orderby'        => 'date',
			'order'          => 'DESC',
		)
	);
}
?>

<main id="main">

<!-- ============ Hero ============ -->
<section class="hero">
	<div class="wrap">
		<div class="hero-inner">
			<div>
				<span class="eyebrow"><span class="dot"></span><?php echo esc_html( vp_mod( 'hero_eyebrow' ) ); ?></span>
				<h1>
					<?php echo esc_html( vp_mod( 'hero_title' ) ); ?><br>
					<span class="grad"><?php echo esc_html( vp_mod( 'hero_title_grad' ) ); ?></span>
					<span class="hero-title-note"><?php echo esc_html( vp_mod( 'hero_title_note' ) ); ?></span>
				</h1>
				<p class="hero-desc"><?php echo esc_html( vp_mod( 'hero_desc' ) ); ?></p>
				<div class="hero-actions">
					<a class="btn btn-primary" href="<?php echo esc_url( vp_mod( 'download_url' ) ); ?>">⬇ <?php echo esc_html( vp_mod( 'download_label' ) ); ?></a>
					<a class="btn btn-ghost" href="#features">查看功能</a>
					<a class="btn btn-ghost" href="#changelog">更新日志</a>
				</div>
				<div class="hero-facts">
					<span><i class="tick">✓</i> 免费开源</span>
					<span><i class="tick">✓</i> Apple Silicon 原生</span>
					<span><i class="tick">✓</i> <?php echo esc_html( vp_mod( 'app_version' ) ? 'v' . vp_mod( 'app_version' ) : '' ); ?></span>
					<span><i class="tick">✓</i> 零外部依赖</span>
				</div>
			</div>
			<div class="hero-visual reveal">
				<div class="app-frame">
					<img src="<?php echo esc_url( get_template_directory_uri() . '/assets/img/hero.png' ); ?>" alt="视频播放器界面截图：双解码引擎、自绘控制条、播放列表侧栏" width="1176" height="662">
					<div class="frame-bar"><i></i><i></i><i></i></div>
				</div>
			</div>
		</div>
	</div>
</section>

<!-- ============ 六特性总览 ============ -->
<section class="section" id="features">
	<div class="wrap">
		<div class="section-head reveal">
			<div class="section-kicker">Six Parts, One Player</div>
			<h2 class="section-title">六个部分，组成一个顺手的播放器。</h2>
			<p class="section-sub">从双击文件开始，到字幕、音轨、章节、快捷键与自动更新——每件事都被安排得明明白白。</p>
		</div>
		<div class="feature-grid">
			<?php foreach ( $features as $f ) : ?>
			<a class="feature-card reveal" href="#feature-<?php echo esc_attr( $f['num'] ); ?>">
				<div class="num"><?php echo esc_html( $f['num'] ); ?></div>
				<h3><?php echo esc_html( $f['cn'] ); ?></h3>
				<span class="en"><?php echo esc_html( $f['en'] ); ?></span>
				<p><?php echo esc_html( $f['desc'] ); ?></p>
			</a>
			<?php endforeach; ?>
		</div>
	</div>
</section>

<!-- ============ 深潜区块 ============ -->
<?php foreach ( $features as $i => $f ) : ?>
<section class="section <?php echo ( 0 === $i % 2 ) ? 'alt' : ''; ?>" id="feature-<?php echo esc_attr( $f['num'] ); ?>">
	<div class="wrap">
		<div class="deep <?php echo ( 1 === $i % 2 ) ? 'rev' : ''; ?>">
			<div class="reveal">
				<span class="kicker-en"><?php echo esc_html( $f['kicker'] ); ?></span>
				<h2><?php echo esc_html( $f['title'] ); ?></h2>
				<p class="lead"><?php echo esc_html( $f['lead'] ); ?></p>
				<div class="mini-grid">
					<?php foreach ( $f['minis'] as $m ) : ?>
					<div class="mini-card">
						<b><?php echo esc_html( $m['b'] ); ?></b>
						<span><?php echo esc_html( $m['s'] ); ?></span>
					</div>
					<?php endforeach; ?>
				</div>
			</div>
			<div class="visual reveal">
				<?php get_template_part( 'template-parts/visual', $f['visual'] ); ?>
			</div>
		</div>
	</div>
</section>
<?php endforeach; ?>

<!-- ============ 下载 ============ -->
<section class="section" id="download">
	<div class="wrap">
		<div class="download-panel reveal">
			<div>
				<span class="eyebrow"><span class="dot"></span>macOS 12+ · Apple Silicon</span>
				<h2 style="margin-top:24px;">现在下载，<?php echo esc_html( vp_mod( 'app_version' ) ? 'v' . vp_mod( 'app_version' ) : '' ); ?> 正式版</h2>
				<p class="sub">签名 + 公证安装包，双击即装，无任何拦截。安装后自动检查更新，之后每次升级都是静默完成。</p>
				<div class="hero-actions">
					<a class="btn btn-primary" href="<?php echo esc_url( vp_mod( 'download_url' ) ); ?>">⬇ <?php echo esc_html( vp_mod( 'download_label' ) ); ?></a>
					<a class="btn btn-ghost" href="<?php echo esc_url( vp_mod( 'github_url' ) . '/releases' ); ?>" rel="noopener" target="_blank">查看全部版本</a>
				</div>
				<div class="download-meta">
					<span class="chip">版本 <b>v<?php echo esc_html( vp_mod( 'app_version' ) ); ?></b></span>
					<span class="chip">大小 <b>约 17 MB</b></span>
					<span class="chip">系统 <b>macOS 12+</b></span>
					<span class="chip">芯片 <b>Apple Silicon</b></span>
					<span class="chip">协议 <b>MIT 开源</b></span>
				</div>
			</div>
			<div>
				<ol class="install-steps">
					<li><span class="step">1</span><div><b>下载并挂载 DMG</b><span>双击 VideoPlayer-<?php echo esc_html( vp_mod( 'app_version' ) ); ?>.dmg 打开安装镜像。</span></div></li>
					<li><span class="step">2</span><div><b>拖入 Applications</b><span>把「视频播放器」拖进 Applications 文件夹即可完成安装。</span></div></li>
					<li><span class="step">3</span><div><b>开始播放</b><span>双击视频文件，或右键选择「打开方式 → 视频播放器」。</span></div></li>
				</ol>
			</div>
		</div>
	</div>
</section>

<!-- ============ 更新日志 ============ -->
<section class="section alt" id="changelog">
	<div class="wrap">
		<div class="section-head reveal">
			<div class="section-kicker">Changelog</div>
			<h2 class="section-title">更新日志</h2>
			<p class="section-sub">最新版本改进一览。完整历史见 <a style="color:var(--flink)" href="<?php echo esc_url( vp_mod( 'github_url' ) . '/releases' ); ?>" rel="noopener" target="_blank">GitHub Releases</a>。</p>
		</div>
		<?php if ( $changelog ) : ?>
		<div class="changelog-list">
			<?php foreach ( $changelog as $post ) : setup_postdata( $post ); ?>
			<article class="changelog-item reveal">
				<time datetime="<?php echo esc_attr( get_the_date( 'c' ) ); ?>"><?php echo esc_html( get_the_date( 'Y-m-d' ) ); ?> · v<?php echo esc_html( get_the_title() ); ?></time>
				<h3><a href="<?php the_permalink(); ?>"><?php the_title(); ?> 发布</a></h3>
				<p><?php echo esc_html( wp_trim_words( get_the_excerpt(), 42, '…' ) ); ?></p>
			</article>
			<?php endforeach; wp_reset_postdata(); ?>
		</div>
		<?php else : ?>
		<div class="changelog-item">
			<h3>还没有更新日志文章</h3>
			<p>在 WordPress 后台创建文章，并选择「更新日志」分类，这里会自动展示最近 3 条。</p>
		</div>
		<?php endif; ?>
	</div>
</section>

<!-- ============ FAQ ============ -->
<section class="section" id="faq">
	<div class="wrap">
		<div class="section-head reveal">
			<div class="section-kicker">FAQ</div>
			<h2 class="section-title">常见问题</h2>
		</div>
		<div class="faq-list">
			<?php foreach ( vp_faq_items() as $fq ) : ?>
			<details class="faq-item reveal">
				<summary><?php echo esc_html( $fq['q'] ); ?></summary>
				<div class="faq-body"><?php echo esc_html( $fq['a'] ); ?></div>
			</details>
			<?php endforeach; ?>
		</div>
	</div>
</section>

<?php
// FAQPage 结构化数据（利于 Google 富摘要）
$faq_schema = array(
	'@context'   => 'https://schema.org',
	'@type'      => 'FAQPage',
	'mainEntity' => array(),
);
foreach ( vp_faq_items() as $fq ) {
	$faq_schema['mainEntity'][] = array(
		'@type'          => 'Question',
		'name'           => $fq['q'],
		'acceptedAnswer' => array(
			'@type' => 'Answer',
			'text'  => $fq['a'],
		),
	);
}
echo '<script type="application/ld+json">' . wp_json_encode( $faq_schema, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES ) . '</script>' . "\n";
?>

</main>

<?php
get_footer();
