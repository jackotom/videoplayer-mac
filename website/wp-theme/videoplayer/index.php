<?php
/**
 * 文章列表（更新日志归档）
 *
 * @package videoplayer
 */
get_header();
?>
<main id="main">
	<section class="page-hero">
		<div class="wrap">
			<span class="eyebrow"><span class="dot"></span>Changelog</span>
			<h1><?php echo is_category() ? single_cat_title( '', false ) : __( '更新日志', 'videoplayer' ); ?></h1>
			<?php if ( is_category() && category_description() ) : ?>
				<div class="meta"><?php echo wp_kses_post( category_description() ); ?></div>
			<?php endif; ?>
		</div>
	</section>
	<section class="wrap post-list">
		<?php if ( have_posts() ) : ?>
			<?php while ( have_posts() ) : the_post(); ?>
				<article class="changelog-item reveal">
					<time datetime="<?php echo esc_attr( get_the_date( 'c' ) ); ?>"><?php echo esc_html( get_the_date( 'Y-m-d' ) ); ?></time>
					<h2><a href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h2>
					<p><?php echo esc_html( wp_trim_words( get_the_excerpt(), 60, '…' ) ); ?></p>
				</article>
			<?php endwhile; ?>
			<div class="post-nav" style="display:flex;justify-content:center;gap:18px;padding:20px 0;">
				<?php echo get_next_posts_link( '← 更早的文章' ); ?>
				<?php echo get_previous_posts_link( '更新的文章 →' ); ?>
			</div>
		<?php else : ?>
			<div class="changelog-item"><h2><?php esc_html_e( '暂无文章', 'videoplayer' ); ?></h2></div>
		<?php endif; ?>
	</section>
</main>
<?php
get_footer();
