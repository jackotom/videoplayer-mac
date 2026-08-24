<?php
/**
 * 普通页面（隐私说明等）
 *
 * @package videoplayer
 */
get_header();
?>
<main id="main">
	<?php while ( have_posts() ) : the_post(); ?>
	<section class="page-hero">
		<div class="wrap">
			<span class="eyebrow"><span class="dot"></span><?php bloginfo( 'name' ); ?></span>
			<h1><?php the_title(); ?></h1>
		</div>
	</section>
	<section class="wrap">
		<div class="entry-content">
			<?php the_content(); ?>
		</div>
	</section>
	<?php endwhile; ?>
</main>
<?php
get_footer();
