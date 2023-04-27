FML 4 → Mailman 2.1 移行スクリプト
======================================================================

* Copyright (C) 2013-2023 SATOH Fumiyasu @ OSSTech Corp., Japan
* License: GNU General Public License version 3
* URL: <https://github.com/fumiyas/mailman-hack>

これはなに?
----------------------------------------------------------------------

FML 4 のメーリングリストを Mailman 2.1 のメーリングリストに雑に
移行するスクリプトです。

無保証です。[OSSTech 社の有償 Mailman 製品とコンサルティングサービス](https://www.osstech.co.jp/product/mailman/) の利用をご検討ください。

使い方
----------------------------------------------------------------------

あとでちゃんと書く、きっと書く。

### Mailman の設定

Mailman の設定例 (一部) を示します。

`mm_cfg.py`:

```python
## Subscribe policy
## 0: open list (only when ALLOW_OPEN_SUBSCRIBE is set to 1) **
## 1: confirmation required for subscribes
## 2: admin approval required for subscribes
## 3: both confirmation and admin approval required
DEFAULT_SUBSCRIBE_POLICY = 3

## Unsubscribe policy
## 0: unmoderated unsubscribes
## 1: unsubscribes require admin approval
DEFAULT_UNSUBSCRIBE_POLICY = 1

## What shold happen to non-member posts which are do not match explicit
## non-member actions?
## 0: Accept
## 1: Hold
## 2: Reject
## 3: Discard
DEFAULT_GENERIC_NONMEMBER_ACTION = 2

## Subject prefixing
DEFAULT_SUBJECT_PREFIX = "[%(real_name)s:%%05d] "
OLD_STYLE_PREFIXING = False
```

上記の設定により Mailman で新規作成するメーリングリストのデフォルト値が以下のようになります。
(この設定は任意です。移行ツールはこの設定の影響を受けません)

* リスト会員への入会・退会はリスト管理者が実施。(自由に入会・退会できない)
* 投稿は会員のみ許可。非会員からの投稿メールは拒否。
* 会員への配信メールの表題 (`Subject:`) に `[<リスト名>:<投稿メール連番 0 埋め 5 桁>]` を追加。
  (FML の標準)

### 実行

```console
# mailman-migrate-from-fml.bash [オプション] <FML リストディレクトリ>
```

* `<FML リストディレクトリ>`
    * 移行元 FML のメーリングリストのディレクトリを指定します。
    * 例: `/var/spool/fml/<リスト名>`

### 移行元データ

* `/var/spool/ml/etc/aliases` (FML メールエイリアスファイル)
    * FML ホストで稼働する MTA が参照しているメールエイリアスファイル。
    * 必要ならば `--fml-aliases` オプションで指定する必要がある。
      デフォルト値は `/var/spool/ml/<リスト名>/aliases`。
    * 通常このファイルは `/var/spool/ml/*/aliases` を統合した内容になっているはずだが、
      稀に手動で直接書き換える運用をしている例もある。
    * `makefml recollect-aliases` で再作成可能。手動で直接書き換えている場合は変更が失なわれるので注意。
* `/var/spool/ml/<リスト名>` (FML メーリングリストディレクトリ)
    * `aliases` (メールエイリアス)
    * `config.ph` (設定)
    * `seq` (投稿メール連番)
    * `members-admin` (管理者メールアドレスリスト)
    * `include-admin` (管理者メールアドレスリスト)
        * `:include:` を含む可能性があるが、それには非対応。
    * `moderators` (司会者メールアドレスリスト)
    * `members` (投稿許可メールアドレスリスト)
    * `actives` (配信先メールアドレスリスト)
    * `spool/*` (保存書庫。任意)

FML メーリングリストディレクトリにはログや保存書庫が含まれているため、
丸ごと移行先にコピーすると結構な容量を喰います。
余計なファイルを概ね取り除いたアーカイブを作成するには
`fml-listsdir-mkcpio.bash` を利用してみてください。
(保存書庫の移行が不要であれば `--without-spool` オプションを追加)

```console
# bash fml-listsdir-mkcpio.bash /var/spool/ml /srv/work/fml-lists.cpio.gz
```

cpio 形式アーカイブの展開例:

```console
$ mkdir fml-lists
$ zcat /srv/work/fml-list-files.cpio.gz |cpio -idm
```

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
        * 上記リストのいずれにも該当しない非会員からの投稿
          → 許可・拒否・保留・破棄いずれかに設定可能 (`generic_nonmember_action`)
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
