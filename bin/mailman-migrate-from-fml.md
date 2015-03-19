fml → Mailman 移行スクリプト
======================================================================

  * Copyright (C) 2013-2015 SATOH Fumiyasu @ OSS Technology Corp., Japan
  * License: GNU General Public License version 3
  * URL: <https://github.com/fumiyas/mailman-hack>

使い方
----------------------------------------------------------------------

あとでかく、きっとかく。

### 実行

```console
# mailman-migrate-from-fml.ksh <fmlメーリングリストディレクトリ> [<URLホスト>]
```

### 移行元データ

  * `fml メーリングリストディレクトリ/`
    * `config.ph` (設定)
    * `seq` (連番)
    * `members-admin` (管理者アドレス)
    * `include-admin` (管理者アドレス)
    * `moderators` (司会者アドレス)
    * `actives` (会員アドレス)
    * `members` (投稿者アドレス)
    * `spool/*` (保存書庫。任意)

`spool/*` (保存書庫。任意) を除いて fml リストデータをアーカイブ (cpio形式) する例:

```console
# cd /var/spool/ml
# find \
  -mindepth 2 \
  -maxdepth 2 \
  ! -name log \
  ! -name summary \
  -type f \
|cpio  \
  -o \
  >fml-list-dirs.cpio \
;
```

cpio 形式アーカイブの展開例:

```console
# cpio -idR 0:0 <fml-list-dirs.cpio
```

### 環境変数

  * `MAILMAN_USER` (mailman)
    * Mailman の実行ユーザーを指定する。
  * `MAILMAN_SITE_EMAIL` (fml)
    * fml の代表メールアドレス fml の移行先メールアドレスを指定する。
  * `MAILMAN_DIR` (`/opt/osstech/lib/mailman`)
    * Mailman のインストールディレクトリを指定する。
  * `MAILMAN_VAR_DIR` (`/opt/osstech/var/lib/mailman`)
    * Mailman のデータディレクトリを指定する。

移行対象
----------------------------------------------------------------------

### 移行対象の fml メーリングリスト情報

  * メーリングリスト名
  * ドメイン名
  * 管理者のメールアドレス
  * 司会者のメールアドレス
  * 会員情報
    * メールアドレス
    * 配信有無の設定
    * 配信メールの個別/まとめ読みの設定
  * 投稿メールの連番
  * パラメーターのいくつか (`config.ph`)

### 移行対象の fml メーリングリストのパラメーター

  * `$PERMIT_POST_FROM`
    * 投稿メールの投稿者アドレス制限。
    * `anyone` (投稿者制限なし)、`members_only` (会員のみ許可) に対応。
    * `moderator` (司会者の許可が必要) は未対応。
  * `$REJECT_POST_HANDLER`
    * `$PERMIT_POST_FROM = "members_only"` 時の会員以外からの投稿メールの扱い。
    * `reject` (拒否した旨を示すメールを投稿者に返信)、`ignore` (無視) に対応。
    * `auto_subscribe` (投稿者アドレスを自動的に会員登録して投稿メールを配信) は未対応。
  * `$SUBJECT_TAG_TYPE`
    * 配信メールの `Subject:` ヘッダーフィールドに付加する接頭辞。
    * `( )`、`[ ]`、`(:)`、`[:]`、`(,)`、`[,]`、`(ID)`、`[ID]`、`()`、`[]` に対応。
    * 上記以外は未対応 (通常は上記以外の設定値は使用されない)。
  * `$INCOMING_MAIL_SIZE_LIMIT`
    * 投稿メールのサイズ制限。
  * `$REJECT_ADDR`
    * 投稿を拒否する投稿者アドレスの正規表現パターン。
  * `$AUTO_HTML_GEN`
    * HTML 形式の保存書庫の作成有無。
  * `$HTML_INDEX_UNIT`
    * HTML 形式の保存書庫の分割単位。
    * `month` (月ごと)、`week` (週ごと)、`day` (日ごと) に対応。
    * `infinite` (分割なし) は年ごとに移行。
    * `number` (一定の投稿数ごと) は未対応。

### 移行対象外の fml メーリングリストのパラメーター

上記「移行対象の fml メーリングリストのパラメーター」以外の
パラメーターは、デフォルトの設定値 (`makefml` 時に生成される
最初期の `config.ph` の設定値) のままであれば、概ね同等の Mailman
メーリングリスト設定になる。カスタマイズしている場合は
個別に対応する必要がある。

以下に fml おいてよくカスタマイズされるパラメーターの代表例を挙げる。
これらは移行スクリプトは感知しないため、可能であれば個別に対応するか、
移行を諦める必要がある。

  * `$NOT_USE_SPOOL`
    * メール形式の保存書庫の作成有無。
    * Mailman はメーリングリストごとの設定ができない。
  * `$START_HOOK`
    * 投稿メールを処理する前に実行する Perl スクリプト。
    * 配信メールの `Reply-To:` ヘッダーフィールドを投稿者アドレスにする
      (`&DEFINE_FIELD_FORCED('Reply-To' , $From_address);`)、
      条件付きで書き換える場合などによく利用される。
    * Mailman は Python でハンドラーモジュールを作成する必要がある。

### そのほか留意事項

  * 移行先の Mailman メーリングリストの管理者パスワードは自動生成され
    `<Mailmanデータディレクトリ>/lists/<リスト名>/adminpass` ファイル
    に保存される。参照後は削除して構わない。

Mailman の fml との主な違い
----------------------------------------------------------------------

  * Web UI の管理者/司会者の認証はパスワードのみ。
    * fml は Webサーバー提供の任意の認証方式 (通常はユーザー名とパスワード)
      が利用可能。
    * Mailman でも可能だが要手動設定、かつ管理者/司会者パスワード認証は無効化できない。
  * メーリングリスト管理者とメーリングリスト司会者のほかに、サイト管理者が存在する。
    * サイト管理者パスワードは全メーリングリストの管理者と司会者の権限を持つ。
    * パスワードは `mmsitepass` コマンドで変更可能。
  * メールによるリモート管理機能はない。
  * 配信メールへの `X-ML-Name: リスト名` ヘッダーフィールドの付加は非対応。
  * 配信メールへの `X-ML-Count: 連番` ヘッダーフィールドの付加は非対応。

