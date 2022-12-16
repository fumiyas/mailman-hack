FML 4 → Mailman 2.1 移行スクリプト
======================================================================

* Copyright (C) 2013-2022 SATOH Fumiyasu @ OSSTech Corp., Japan
* License: GNU General Public License version 3
* URL: <https://github.com/fumiyas/mailman-hack>

これはなに?
----------------------------------------------------------------------

FML 4 のメーリングリストを Mailman 2.1 のメーリングリストに雑に
移行するスクリプトです。

使い方
----------------------------------------------------------------------

あとでちゃんと書く、きっと書く。

### Mailman の設定

`mm_cfg.py`:

```python
DEFAULT_SUBJECT_PREFIX = "[%(real_name)s:%%05d] "
DEFAULT_MAX_DAYS_TO_HOLD = 14 ## days
```

### 実行

```console
# mailman-migrate-from-fml.bash <リストディレクトリ> <aliases> [<URLホスト>]
```

* `<リストディレクトリ>`
    * 移行元 FML のメーリングリストのディレクトリを指定します。
    * 例: `/var/spool/fml/<リスト名>`
* `<aliases>`
    * 移行元 FML のメーリングリストのメールエイリアス情報を含む
      `aliases`(5) ファイルを指定します。
    * `<リスト名>-admin` の転送先アドレスを移行先 Mailman
      メーリングリストの管理者として登録するために参照します。
    * FML ホストで稼働する MTA が参照している `aliases`
      ファイルを指定する必要があります。
      FML メーリングリストディレクトリ下の `aliases` ファイルは
      MTA から参照されていません。
    * 例: `/etc/aliases`
* `[<URLホスト>]`
    * 移行先 Mailman メーリングリストの Web UI の URL
      に採用するホスト名を指定します。
    * デフォルトは `mm_cfg.py` に依ります。

### 移行元データ

* `/var/spool/ml/<リスト名>` (FML メーリングリストディレクトリ)
    * `config.ph` (設定)
    * `seq` (連番)
    * `members-admin` (管理者メールアドレスリスト)
    * `include-admin` (管理者メールアドレスリスト)
        * `:include:` を含む可能性があるが、それには非対応。
    * `moderators` (司会者メールアドレスリスト)
    * `members` (投稿許可メールアドレスリスト)
    * `actives` (配信先メールアドレスリスト)
    * `spool/*` (保存書庫。任意)

余計なファイルを概ね取り除いたアーカイブを作成するには
`fml-listsdir-mkcpio.bash` を利用してみてください。

```console
# bash fml-listsdir-mkcpio.bash /var/spool/ml /srv/work/fml-lists.cpio.gz
```

cpio 形式アーカイブの展開例:

```console
$ mkdir fml-lists
$ zcat /srv/work/fml-list-files.cpio.gz |cpio -idm
```

### 環境変数 (デフォルト値)

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

### 移行対象の FML メーリングリスト情報

* メーリングリスト名
* ドメイン名
* 管理者のメールアドレスリスト
* 司会者のメールアドレスリスト
* 配信先メールアドレスリストと設定
    * メールアドレス
    * 配信有無の設定
    * 配信メールの個別/まとめ読みの設定
* 投稿許可メールアドレスリスト
* 投稿メールの連番 (`seq`)
* 設定パラメーターのいくつか (`config.ph`)

### 移行対象の FML メーリングリストのパラメーター

* `$PERMIT_POST_FROM`
    * 投稿メールの投稿者メールアドレス制限。
    * `anyone` (投稿者制限なし)、`members_only` (会員のみ許可)、`moderator` (司会者の承認が必要) のすべてに対応。
* `$REJECT_POST_HANDLER`
    * `$PERMIT_POST_FROM = "members_only"` 時の非会員からの投稿メールの扱い。
    * `reject` (拒否した旨を示すメールを投稿者に返信)、`ignore` (無視) に対応。
    * `auto_subscribe` (投稿者メールアドレスを自動的に会員登録して投稿メールを配信) は非対応。保留 (`generic_nonmember_action=1`) に移行する。
* `$SUBJECT_TAG_TYPE`
    * 配信メールの `Subject:` ヘッダーフィールドに付加する接頭辞。
    * `( )`、`[ ]`、`(:)`、`[:]`、`(,)`、`[,]`、`(ID)`、`[ID]`、`()`、`[]` に対応。
    * 上記以外は未対応 (通常は上記以外の設定値は使用されません)。
* `$INCOMING_MAIL_SIZE_LIMIT`
    * 投稿メールのサイズ制限。接尾辞 `k`, `K` は kiB 単位、`m`, `M` は MiB 単位を示す。
    * Mailman は kB 単位、ヘッダー部を除外したサイズ制限となる。
* `$REJECT_ADDR`
    * 投稿を破棄する投稿者メールアドレスの正規表現パターン。
    * Perl 固有の正規表現を用いている場合は手動で Python 向けに書き換える必要があります。
    * パラメーター名は拒否 (`reject`) するかのように読めるが、実際は破棄 (`discard`) する。
    * FML は破棄するだけでなくリスト管理者に転送する。Mailman でも転送するには、
      「非会員で自動的に破棄すると決めたメールはリスト司会者へ転送」(`forward_auto_discards`)
      を「はい」(デフォルト) に設定する必要がある。
* `$USE_RFC2369`
    * RFC 2369 標準のヘッダー追加の有無。
* `$AUTO_HTML_GEN`
    * HTML 形式の保存書庫の作成有無。
* `$HTML_INDEX_UNIT`
    * HTML 形式の保存書庫の分割単位。
    * `month` (月ごと)、`week` (週ごと)、`day` (日ごと) に対応。
    * `infinite` (分割なし) は年ごとに移行。
    * `number` (一定の投稿数ごと) は未対応。

### 移行対象外の FML メーリングリストのパラメーター

上記「移行対象の FML メーリングリストのパラメーター」以外の
パラメーターは、デフォルトの設定値 (`makefml` 時に生成される
最初期の `config.ph` の設定値) のままであれば、概ね同等の Mailman
メーリングリスト設定になる。カスタマイズしている場合は
個別に対応する必要があります。

`config.ph` はメーリングリストの設定値だけでなくとても柔軟な
内容 (Perl スクリプト) を記述できますが、それらは移行対象外です。

以下に FML おいてよくカスタマイズされるパラメーターの代表例を挙げる。
***これらは移行スクリプトは感知しない*** ため、可能であれば個別に対応するか、
移行を諦める必要があります。

* `$NOT_USE_SPOOL = <真偽値>;`
    * メール形式の保存書庫の作成有無。
    * Mailman はメーリングリストごとの設定ができない。
      (HTML 形式の保存書庫の作成有無はリストごとに設定可能)
* `$START_HOOK = <Perl スクリプト>;`
* `$DISTRIBUTE_START_HOOK = <Perl スクリプト>;`
    * 投稿メールを処理する前に実行する Perl スクリプト。
    * 配信メールの `Reply-To:` ヘッダーフィールドを投稿者メールアドレスに強制
      (`&DEFINE_FIELD_FORCED('Reply-To' , $From_address);`)、
      したり、各種の設定やヘッダーの上書きを条件付きで適用する場合などによく利用される。
    * Mailman は Python でハンドラーモジュールを作成する必要がある。
* `$USE_DISTRIBUTE_FILTER = 1`
    * 下記のようなフィルター設定の有効化に利用される。
        * `&DEFINE_FIELD_PAT_TO_REJECT(<ヘッダーフィルド名>, <正規表現>);`
        * `$DISTRIBUTE_FILTER_HOOK = <Perl スクリプト>;`

### そのほか留意事項

* 移行先の Mailman メーリングリストの管理者パスワードは自動生成され
    `<Mailmanデータディレクトリ>/lists/<リスト名>/ownerpassword` ファイル
    に保存される。参照後は削除して構わない。

Mailman の FML との主な違い
----------------------------------------------------------------------

* Web UI の管理者/司会者の認証はパスワードのみ。
    * FML は Webサーバー提供の任意の認証方式 (通常はユーザー名とパスワード)
      が利用可能。
    * Mailman でも可能だが要手動設定、かつ管理者/司会者パスワード認証は無効化できない。
    * OSSTech Mailman なら LDAP 認証が可能、かつ管理者/司会者パスワード認証を無効化可能。
* メーリングリスト管理者とメーリングリスト司会者のほかに、サイト管理者が存在する。
    * サイト管理者パスワードは全メーリングリストの管理者と司会者の権限を持つ。
    * パスワードは `mmsitepass` コマンドで変更可能。
* メールによるリモート管理機能はない。
* Mailman は会員と非会員で別々に投稿の許可・拒否・保留・破棄が判定される。
    * 会員からの投稿の場合 (会員リストに載っているメールアドレスからの投稿):
        * 制限オプション無効の会員
          → 投稿可能
        * 制限オプション有効の会員 (制限会員)
          → 投稿は保留、拒否、破棄いずれかに設定可能 (`member_moderation_action`)
    * 非会員からの投稿の場合 (会員リストに載っていないメールアドレスからの投稿):
        * 投稿許可リスト (`accept_these_nonmembers`)
          → 投稿可能
        * 投稿保留リスト (`hold_these_nonmembers`)
          → 投稿可能 (司会者が許可した場合)
        * 投稿拒否リスト (`reject_these_nonmembers`)
          → 投稿不可能 (投稿者に拒否通知メールを返送)
        * 投稿破棄リスト (`discard_these_nonmembers`)
          → 投稿不可能 (なにも返送しない)
    * 会員からの投稿には非会員フィルタは適用されない点に注意。
        * FML の投稿を破棄する投稿者メールアドレスの正規表現パターン設定 (`$REJECT_ADDR`) は
          Mailman の非会員フィルター (`reject_these_nonmembers`) に移行するため、
          会員には適用されない。
    * FML はメール投稿許可アドレスリスト (`members` ファイル) と投稿メール配信先アドレスリスト
      (`actives` ファイル) を別々に管理できるが、Mailman では別々の管理は不可。
* `Reply-To:` ヘッダーフィールドの書き換え:
    * Mailman は「投稿メールの `Reply-To:` を削除する/しない」(`first_strip_reply_to`)
      と「`Reply-To: <リスト投稿アドレスあるいは指定の任意アドレス>`
      を追加する/しない」(`reply_goes_to_list`) の設定があるが、
      条件による削除や追加はできない。
    * FML のデフォルトは「投稿メールに `Reply-To:` があればそのまま、
      なければ `Reply-To: <リスト投稿アドレス>` を追加する」となる。
    * FML は `$START_HOOK` に記述する Perl スクリプトで自由に書き換えることが可能。
* 配信メールへの `X-ML-Name: <リスト名>` ヘッダーフィールドの付加は非対応。
* 配信メールへの `X-Mail-Count: <連番>` ヘッダーフィールドの付加は非対応。
