<?php
/**
 * 404
 *
 * @package videoplayer
 */
get_header();
?>
<main id="main">
	<section class="nf wrap">
		<h1>404</h1>
		<p>页面不存在或已被移动。返回首页继续探索吧。</p>
		<a class="btn btn-primary" href="<?php echo esc_url( home_url( '/' ) ); ?>">返回首页</a>
	</section>
</main>
<?php
get_footer();
