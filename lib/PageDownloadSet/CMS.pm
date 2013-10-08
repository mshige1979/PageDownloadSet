package PageDownloadSet::CMS;

use strict;
use warnings;
use MT::Util qw( format_ts );
use MT::Entry;
use MT::Page;
use MT::FileInfo;
use File::Path qw( rmtree );

use Encode;
use utf8;
use MT::Util::YAML;

use MT;
use MT::Util qw( dirify );
use MT::Tag;
use MT::Placement;

my $puluginName = "PageDownloadSet";

# debug
use Data::Dumper;

# ウェブページダウンロード処理
sub download_webpage {

    # パラメータ取得
    my $app = shift;
    my %param;
    
    # チェック
    my $zlib = "Archive::Zip";
    unless (eval "use $zlib ; 1") {
        die $app->translate('Archive: There : Is no Zip module. Archive: Please : Install a Zip module.');
    };
    
    # パラメータコンテキスト取得
    my $q = $app->param;
    
    # ブログID取得
    my $blog_id = $q->param('blog_id');
    my $blog = MT::Blog->load({id => $blog_id});
    my $blog_title = $blog->name;
    
    # 文字セットを取得
    my $charset = $app->charset;
    
    # ファイルマネージャー
    my $fmgr = MT::FileMgr->new('Local');
    
	# プラグインディレクトリ
    my $plugin_path = MT->instance->mt_dir . '/plugins/' . $puluginName;
	
    # 作業ディレクトリを作成
    my $tmp_path = $plugin_path . "/tmp";
    $fmgr->mkpath($tmp_path);
    
    # 任意の文字列
    my @ts = MT::Util::offset_time_list( time, $blog_id );
	my $ts = sprintf '%04d%02d%02d%02d%02d%02d', $ts[5] + 1900, $ts[4] + 1, @ts[ 3, 2, 1, 0 ];
    
    my $wrk_path = $tmp_path . "/" . $ts . "/" . $puluginName;
    $fmgr->mkpath($wrk_path);

    # 設定ファイル名
    my $yaml_path = $wrk_path . '/webpage_list.yaml';
    
    # 設定エリア
    my $webpage_hash = {};
    $webpage_hash->{blog_id} = $blog_id;
    $webpage_hash->{blog_name} = $blog_title;
    $webpage_hash->{pages} = {};
    
    # ウェブページを全て取得
    my $iter = MT::Page->load_iter(
    		# 抽出条件
    		{blog_id => $blog_id}, 
    		# ソート条件
    		{sort => "id", direction => "ascend"}
    );
    
    # 全てのウェブページをダウンロード
    while(my $page = $iter->()){
    	
    	# IDを取得
    	my $set_id = $page->id;
    	my $id_name = sprintf( "%06d", $set_id );
    	
    	# ディレクトリを作成
    	my $local_path = $wrk_path . "/" . $id_name;
    	$fmgr->mkpath($local_path);
    	
    	# text
    	my $text = $page->text;
    	my $text_more = $page->text_more;
    	
    	# 出力
    	$fmgr->put_data($text, $local_path . '/text.txt');
    	$fmgr->put_data($text_more, $local_path . '/text_more.txt');
    	
    	# ハッシュリファレンスに詳細を設定
    	my $page_info = {};
    	$page_info->{id} = $set_id;
    	$page_info->{title} = $page->title;
    	$page_info->{text} = ($page->text) ? "1": "0";
    	$page_info->{text_more} = ($page->text_more) ? "1": "0";
    	$page_info->{status} = $page->status;
    	
    	# ID別に追加
    	$webpage_hash->{pages}->{$id_name} = $page_info;
    	
    }
    
    # 定義情報を出力
    $fmgr->put_data(MT::Util::YAML::Dump($webpage_hash), $yaml_path);
    
    # 作業エリアを圧縮
    require MT::Util::Archive;
    my $arcfile = File::Temp::tempnam( $tmp_path, $ts ); # 圧縮ファイルを生成
	
	my $arctype = "zip";
	my $arc_info = MT->registry( archivers => $arctype )
            or die "Unknown archiver type : $arctype";
	
	# zipの圧縮ファイルを生成し、データを追加
    my $arc = MT::Util::Archive->new( $arctype, $arcfile )
        or die "Cannot load archiver : " . MT::Util::Archive->errstr;
    $arc->add_tree($tmp_path . "/" . $ts);
    $arc->close;
    
    # ファイル名
    my $filename = "webpage_" . $ts . "." . $arctype;
    
    # 圧縮したファイルを開き、出力する
    open my $fh, "<", $arcfile;
    binmode $fh;
    $app->{no_print_body} = 1;
    $app->set_header(
        "Content-Disposition" => "attachment; filename=$filename" );
    $app->send_http_header( $arc_info->{mimetype} );
    my $data;
    
    # 一定単位にデータを読み込み
    while ( read $fh, my ($chunk), 8192 ) {
        $data .= $chunk;
    }
    close $fh;
    $app->print($data);
    
    # ファイルの削除
    $fmgr->delete($arcfile);
    
    # ディレクトリの削除
    rmtree($tmp_path . "/" . $ts);
    
    return 1;
}

1;
