<?php
/**
 * 页脚
 *
 * @package videoplayer
 */
$footer_text = str_replace( '{year}', gmdate( 'Y' ), vp_mod( 'footer_text' ) );
?>
<footer class="site-footer">
	<div class="wrap">
		<div class="footer-grid">
			<div>
				<a class="brand" href="<?php echo esc_url( home_url( '/' ) ); ?>">
					<img src="<?php echo esc_url( get_template_directory_uri() . '/assets/img/icon.png' ); ?>" alt="<?php bloginfo( 'name' ); ?> 图标" width="30" height="30">
					<span><?php bloginfo( 'name' ); ?></span>
				</a>
				<p style="margin:14px 0 0;line-height:1.8;"><?php echo esc_html( vp_truncate( vp_site_description(), 90 ) ); ?>……</p>
			</div>
			<div>
				<h4>产品</h4>
				<ul>
					<li><a href="<?php echo esc_url( home_url( '/#features' ) ); ?>">功能特性</a></li>
					<li><a href="<?php echo esc_url( home_url( '/#download' ) ); ?>">下载安装</a></li>
					<li><a href="<?php echo esc_url( home_url( '/#changelog' ) ); ?>">更新日志</a></li>
					<li><a href="<?php echo esc_url( home_url( '/#faq' ) ); ?>">常见问题</a></li>
				</ul>
			</div>
			<div>
				<h4>资源</h4>
				<ul>
					<li><a href="<?php echo esc_url( vp_mod( 'github_url' ) ); ?>" rel="noopener" target="_blank">GitHub 仓库</a></li>
					<li><a href="<?php echo esc_url( vp_mod( 'github_url' ) . '/releases' ); ?>" rel="noopener" target="_blank">全部版本</a></li>
					<li><a href="<?php echo esc_url( vp_mod( 'github_url' ) . '/issues' ); ?>" rel="noopener" target="_blank">问题反馈</a></li>
				</ul>
			</div>
			<div>
				<h4>协议</h4>
				<ul>
					<li><a href="<?php echo esc_url( vp_mod( 'github_url' ) ); ?>" rel="noopener" target="_blank">MIT 开源协议</a></li>
					<li><a href="<?php echo esc_url( home_url( '/privacy' ) ); ?>">隐私说明</a></li>
				</ul>
			</div>
		</div>
		<div class="footer-bottom">
			<span><?php echo esc_html( $footer_text ); ?></span>
			<span><?php echo esc_html( vp_mod( 'app_version' ) ? '当前版本 v' . vp_mod( 'app_version' ) : '' ); ?></span>
		</div>
	</div>
</footer>
</div><!-- /.site-shell -->
<?php wp_footer(); ?>
</body>
</html>
