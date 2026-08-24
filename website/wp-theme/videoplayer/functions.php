<?php
/**
 * VideoPlayer 官网主题功能
 *
 * @package videoplayer
 */

if ( ! defined( 'ABSPATH' ) ) { exit; }

define( 'VP_THEME_VERSION', '1.0.0' );

/* ============ 主题初始化 ============ */
function vp_setup() {
	load_theme_textdomain( 'videoplayer', get_template_directory() . '/languages' );
	add_theme_support( 'title-tag' );
	add_theme_support( 'post-thumbnails' );
	add_theme_support( 'automatic-feed-links' );
	add_theme_support(
		'html5',
		array( 'search-form', 'comment-form', 'comment-list', 'gallery', 'caption', 'style', 'script' )
	);
	add_theme_support(
		'custom-logo',
		array( 'height' => 120, 'width' => 120, 'flex-height' => true, 'flex-width' => true )
	);

	register_nav_menus(
		array(
			'primary' => __( '顶部导航', 'videoplayer' ),
			'footer'  => __( '页脚导航', 'videoplayer' ),
		)
	);
}
add_action( 'after_setup_theme', 'vp_setup' );

/* ============ 静态资源 ============ */
function vp_assets() {
	wp_enqueue_style( 'videoplayer-style', get_stylesheet_uri(), array(), VP_THEME_VERSION );
	wp_enqueue_script( 'videoplayer-site', get_template_directory_uri() . '/assets/js/site.js', array(), VP_THEME_VERSION, true );
}
add_action( 'wp_enqueue_scripts', 'vp_assets' );

/* 移除部分默认头部噪音（对爬虫更干净） */
remove_action( 'wp_head', 'wp_generator' );
remove_action( 'wp_head', 'wlwmanifest_link' );
remove_action( 'wp_head', 'rsd_link' );
remove_action( 'wp_head', 'wp_shortlink_wp_head' );
remove_action( 'wp_head', 'print_emoji_detection_script', 7 );
remove_action( 'wp_print_styles', 'print_emoji_styles' );

/* ============ 定制器（后台可改首页文案与下载地址，内容管理友好） ============ */
function vp_customize_register( $wp_customize ) {
	$wp_customize->add_section(
		'vp_home',
		array( 'title' => __( '首页内容', 'videoplayer' ), 'priority' => 30 )
	);

	$fields = array(
		'hero_eyebrow'    => array( 'label' => __( 'Hero 眉题', 'videoplayer' ), 'default' => 'macOS 原生 · 免费开源' ),
		'hero_title'      => array( 'label' => __( 'Hero 主标题', 'videoplayer' ), 'default' => '视频播放器' ),
		'hero_title_grad' => array( 'label' => __( '主标题渐变词', 'videoplayer' ), 'default' => '通吃所有格式' ),
		'hero_title_note' => array( 'label' => __( '主标题注释', 'videoplayer' ), 'default' => 'VideoPlayer — 轻量原生 macOS 视频播放器，专为 Apple Silicon 优化' ),
		'hero_desc'       => array( 'label' => __( 'Hero 描述', 'videoplayer' ), 'default' => '双解码后端，真正通吃所有格式：AVFoundation 硬件解码省电流畅，FFmpeg 软解兜底无死角。字幕、多音轨、章节、画中画、A-B 循环……原生体验，零外部依赖。' ),
		'download_url'    => array( 'label' => __( '下载链接', 'videoplayer' ), 'default' => 'https://github.com/jackotom/videoplayer-mac/releases/latest/download/VideoPlayer-1.0.6.dmg' ),
		'download_label'  => array( 'label' => __( '下载按钮文字', 'videoplayer' ), 'default' => '免费下载 macOS 版' ),
		'github_url'      => array( 'label' => __( 'GitHub 仓库链接', 'videoplayer' ), 'default' => 'https://github.com/jackotom/videoplayer-mac' ),
		'app_version'     => array( 'label' => __( '当前版本号', 'videoplayer' ), 'default' => '1.0.6' ),
		'footer_text'     => array( 'label' => __( '页脚版权文字', 'videoplayer' ), 'default' => '© {year} 视频播放器 · 轻量原生 macOS 播放器' ),
	);

	foreach ( $fields as $id => $conf ) {
		$wp_customize->add_setting(
			'vp_' . $id,
			array(
				'default'           => $conf['default'],
				'sanitize_callback' => 'sanitize_text_field',
			)
		);
		$wp_customize->add_control(
			'vp_' . $id,
			array(
				'label'   => $conf['label'],
				'section' => 'vp_home',
				'type'    => ( 'hero_desc' === $id ) ? 'textarea' : 'text',
			)
		);
	}
}
add_action( 'customize_register', 'vp_customize_register' );

function vp_mod( $key ) {
	$defaults = array(
		'hero_eyebrow'    => 'macOS 原生 · 免费开源',
		'hero_title'      => '视频播放器',
		'hero_title_grad' => '通吃所有格式',
		'hero_title_note' => 'VideoPlayer — 轻量原生 macOS 视频播放器，专为 Apple Silicon 优化',
		'hero_desc'       => '双解码后端，真正通吃所有格式：AVFoundation 硬件解码省电流畅，FFmpeg 软解兜底无死角。字幕、多音轨、章节、画中画、A-B 循环……原生体验，零外部依赖。',
		'download_url'    => 'https://github.com/jackotom/videoplayer-mac/releases/latest/download/VideoPlayer-1.0.6.dmg',
		'download_label'  => '免费下载 macOS 版',
		'github_url'      => 'https://github.com/jackotom/videoplayer-mac',
		'app_version'     => '1.0.6',
		'footer_text'     => '© {year} 视频播放器 · 轻量原生 macOS 播放器',
	);
	return get_theme_mod( 'vp_' . $key, $defaults[ $key ] );
}

/* ============ SEO：meta description / Open Graph / Twitter / JSON-LD ============ */

/** 站点描述 */
function vp_site_description() {
	if ( is_front_page() ) {
		return vp_mod( 'hero_desc' );
	}
	if ( is_singular() ) {
		$excerpt = get_the_excerpt();
		if ( $excerpt ) {
			return wp_strip_all_tags( $excerpt );
		}
	}
	if ( is_category() || is_tag() || is_tax() ) {
		return sprintf( '%s 相关文章归档 - %s', single_term_title( '', false ), get_bloginfo( 'name' ) );
	}
	return get_bloginfo( 'description' );
}

function vp_head_meta() {
	$desc = vp_site_description();
	$desc = trim( vp_truncate( $desc, 160 ) );
	$url  = ( is_singular() ) ? get_permalink() : home_url( '/' );
	$type = ( is_singular( 'post' ) ) ? 'article' : 'website';
	$title = wp_get_document_title();

	echo '<meta name="description" content="' . esc_attr( $desc ) . '" />' . "\n";
	echo '<meta property="og:site_name" content="' . esc_attr( get_bloginfo( 'name' ) ) . '" />' . "\n";
	echo '<meta property="og:type" content="' . esc_attr( $type ) . '" />' . "\n";
	echo '<meta property="og:title" content="' . esc_attr( $title ) . '" />' . "\n";
	echo '<meta property="og:description" content="' . esc_attr( $desc ) . '" />' . "\n";
	echo '<meta property="og:url" content="' . esc_url( $url ) . '" />' . "\n";
	echo '<meta property="og:locale" content="zh_CN" />' . "\n";
	if ( is_singular() && has_post_thumbnail() ) {
		$img = get_the_post_thumbnail_url( null, 'full' );
		echo '<meta property="og:image" content="' . esc_url( $img ) . '" />' . "\n";
	} else {
		echo '<meta property="og:image" content="' . esc_url( get_template_directory_uri() . '/assets/img/og-image.png' ) . '" />' . "\n";
	}
	echo '<meta name="twitter:card" content="summary_large_image" />' . "\n";
	echo '<meta name="twitter:title" content="' . esc_attr( $title ) . '" />' . "\n";
	echo '<meta name="twitter:description" content="' . esc_attr( $desc ) . '" />' . "\n";
	echo '<meta name="robots" content="index,follow,max-image-preview:large" />' . "\n";
}
add_action( 'wp_head', 'vp_head_meta', 1 );

/** JSON-LD：软件信息（首页）+ 面包屑（文章页） */
function vp_jsonld() {
	$schema = array();

	if ( is_front_page() ) {
		$schema[] = array(
			'@context'            => 'https://schema.org',
			'@type'               => 'SoftwareApplication',
			'name'                => get_bloginfo( 'name' ),
			'description'         => vp_mod( 'hero_desc' ),
			'operatingSystem'     => 'macOS 12 及以上（Apple Silicon）',
			'applicationCategory' => 'MultimediaApplication',
			'softwareVersion'     => vp_mod( 'app_version' ),
			'downloadUrl'         => vp_mod( 'download_url' ),
			'url'                 => home_url( '/' ),
			'offers'              => array(
				'@type'         => 'Offer',
				'price'         => '0',
				'priceCurrency' => 'CNY',
			),
			'author'              => array(
				'@type' => 'Organization',
				'name'  => get_bloginfo( 'name' ),
				'url'   => home_url( '/' ),
			),
		);
	}

	if ( is_singular( 'post' ) ) {
		$crumb = array(
			array(
				'@type'    => 'ListItem',
				'position' => 1,
				'name'     => __( '首页', 'videoplayer' ),
				'item'     => home_url( '/' ),
			),
		);
		$cat_id = vp_changelog_cat_id();
		if ( $cat_id ) {
			$crumb[] = array(
				'@type'    => 'ListItem',
				'position' => 2,
				'name'     => __( '更新日志', 'videoplayer' ),
				'item'     => get_category_link( $cat_id ),
			);
		}
		$crumb[] = array(
			'@type'    => 'ListItem',
			'position' => count( $crumb ) + 1,
			'name'     => get_the_title(),
		);
		$schema[] = array(
			'@context'        => 'https://schema.org',
			'@type'           => 'BreadcrumbList',
			'itemListElement' => $crumb,
		);
	}

	foreach ( $schema as $s ) {
		echo '<script type="application/ld+json">' . wp_json_encode( $s, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES ) . '</script>' . "\n";
	}
}
add_action( 'wp_head', 'vp_jsonld', 2 );

/* ============ 工具函数 ============ */

/** 按字符安全截断（兼容无 mbstring 的环境） */
function vp_truncate( $text, $len ) {
	if ( function_exists( 'mb_substr' ) ) {
		return mb_substr( $text, 0, $len );
	}
	return substr( $text, 0, $len );
}

/* ============ 更新日志分类 ============ */

/** 更新日志分类 ID（不存在则自动创建） */
function vp_changelog_cat_id() {
	$id = get_option( 'vp_changelog_cat' );
	if ( $id && term_exists( (int) $id, 'category' ) ) {
		return (int) $id;
	}
	$term = term_exists( '更新日志', 'category' );
	if ( ! $term ) {
		$term = wp_insert_term( '更新日志', 'category', array( 'slug' => 'changelog' ) );
	}
	if ( is_wp_error( $term ) ) {
		return 0;
	}
	$id = is_array( $term ) ? (int) $term['term_id'] : (int) $term;
	update_option( 'vp_changelog_cat', $id );
	return $id;
}

/** 首页 FAQ 数据（可见手风琴 + FAQPage 结构化数据共用一份） */
function vp_faq_items() {
	return array(
		array(
			'q' => '支持哪些视频格式？',
			'a' => '几乎全部。默认使用 AVFoundation 硬件解码，覆盖 MP4 / MOV / MKV / WebM 等常见格式；遇到无法解码的冷门格式（DivX/Xvid AVI、FLV、WMV、FFV1、DTS 音轨等）会自动切换 FFmpeg 软解，也可以按 ⌥⌘R 手动切换。',
		),
		array(
			'q' => '系统要求是什么？',
			'a' => 'Apple Silicon（M 系列芯片）Mac，macOS 12 或更高版本。应用零外部依赖，无需安装 FFmpeg 等任何组件。',
		),
		array(
			'q' => '收费吗？',
			'a' => '完全免费、开源（MIT 协议）。代码托管在 GitHub，欢迎提 Issue 与 PR。',
		),
		array(
			'q' => '安装时提示「无法打开，因为无法验证开发者」怎么办？',
			'a' => '本应用使用 Apple Developer ID 签名并经过 Apple 公证，正常情况下双击即可安装。若仍被拦截，右键点击安装包 → 「打开」，确认一次即可；也可以执行 xattr -dr com.apple.quarantine VideoPlayer.app 解除隔离标记。',
		),
		array(
			'q' => '如何让字幕、音轨选择自动记住？',
			'a' => '播放器会按文件记忆你选择的音轨、内嵌字幕轨，以及是否关闭字幕。再次打开同一文件时自动恢复。',
		),
		array(
			'q' => '会自动更新吗？',
			'a' => '会。应用内置 Sparkle 自动更新，启动时静默检查新版本并提示安装；也可以在应用菜单中点「检查更新…」手动检查。',
		),
		array(
			'q' => '支持画中画和投屏吗？',
			'a' => '支持画中画（macOS 12+，硬解模式），控制条上也有隔空播放（AirPlay）输出路由按钮。',
		),
	);
}
