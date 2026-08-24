<?php
/**
 * 页头
 *
 * @package videoplayer
 */
?><!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
<meta charset="<?php bloginfo( 'charset' ); ?>">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="theme-color" content="#050505">
<?php
if ( has_custom_logo() ) {
	$custom_logo_id = get_theme_mod( 'custom_logo' );
	echo '<link rel="icon" href="' . esc_url( wp_get_attachment_image_url( $custom_logo_id, 'full' ) ) . '">' . "\n";
} else {
	echo '<link rel="icon" href="' . esc_url( get_template_directory_uri() . '/assets/img/icon.png' ) . '">' . "\n";
}
?>
<?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>
<?php wp_body_open(); ?>
<canvas id="space-canvas" aria-hidden="true"></canvas>
<div class="site-shell">

<header class="topbar" id="topbar">
	<div class="topbar-inner">
		<a class="brand" href="<?php echo esc_url( home_url( '/' ) ); ?>" aria-label="<?php bloginfo( 'name' ); ?>">
			<?php if ( has_custom_logo() ) : ?>
				<?php the_custom_logo(); ?>
			<?php else : ?>
				<img src="<?php echo esc_url( get_template_directory_uri() . '/assets/img/icon.png' ); ?>" alt="<?php bloginfo( 'name' ); ?> 图标" width="30" height="30">
			<?php endif; ?>
			<span>
				<?php bloginfo( 'name' ); ?>
				<small><?php echo esc_html( vp_mod( 'app_version' ) ? 'v' . vp_mod( 'app_version' ) : '' ); ?></small>
			</span>
		</a>

		<nav class="nav" aria-label="<?php esc_attr_e( '主导航', 'videoplayer' ); ?>">
			<?php
			if ( has_nav_menu( 'primary' ) ) {
				wp_nav_menu(
					array(
						'theme_location' => 'primary',
						'container'      => false,
						'items_wrap'     => '%3$s',
						'fallback_cb'    => false,
					)
				);
			} else {
				// 默认锚点导航（未配置菜单时）
				echo '<a href="#features">功能</a>';
				echo '<a href="#download">下载</a>';
				echo '<a href="#changelog">更新日志</a>';
				echo '<a href="#faq">常见问题</a>';
			}
			?>
		</nav>

		<div class="topbar-actions">
			<a class="btn btn-ghost btn-sm" href="<?php echo esc_url( vp_mod( 'github_url' ) ); ?>" rel="noopener" target="_blank">GitHub</a>
			<a class="btn btn-primary btn-sm" href="<?php echo esc_url( vp_mod( 'download_url' ) ); ?>"><?php echo esc_html( vp_mod( 'download_label' ) ); ?></a>
		</div>
	</div>
</header>
