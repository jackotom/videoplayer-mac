<?php
/**
 * 单篇文章（更新日志详情）
 *
 * @package videoplayer
 */
get_header();
?>
<main id="main">
	<?php while ( have_posts() ) : the_post(); ?>
	<article>
		<section class="page-hero">
			<div class="wrap">
				<span class="eyebrow"><span class="dot"></span>
					<?php
					$cats = get_the_category();
					if ( $cats ) {
						echo '<a href="' . esc_url( get_category_link( $cats[0] ) ) . '">' . esc_html( $cats[0]->name ) . '</a>';
					}
					?>
				</span>
				<h1><?php the_title(); ?></h1>
				<div class="meta">
					<time datetime="<?php echo esc_attr( get_the_date( 'c' ) ); ?>">发布于 <?php echo esc_html( get_the_date( 'Y 年 m 月 d 日' ) ); ?></time>
					· <?php the_author(); ?>
				</div>
			</div>
		</section>
		<section class="wrap">
			<div class="entry-content">
				<?php the_content(); ?>
			</div>
		</section>
	</article>
	<?php endwhile; ?>
</main>
<?php
get_footer();
