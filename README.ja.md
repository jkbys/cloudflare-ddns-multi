![Build and push Docker image](https://github.com/jkbys/cloudflare-ddns-multi/workflows/Build%20and%20push%20Docker%20image/badge.svg)

# cloudflare-ddns-multi
Cloudflare DDNS Multiple Zone/Recoerd Updater - Docker micro image / Shell script

CloudFlare DNSをDynamic DNSとして利用するための小さなDockerイメージです。グローバルIPアドレス（IPv4とIPv6）を定期的に取得し、CloudFlare DNS上の複数ゾーンのAとAAAAAレコードに設定します。Dockerを使わずにcronなどのプログラムからこのスクリプトを実行することもできます。

## 特徴
<dl>
<dt>小さなDockerイメージ</dt>
<dd>このイメージのダウンロードサイズ（圧縮サイズ）は4MB未満です。</dd>
<dt>複数のアーキテクチャに対応</dt>
<dd>Dockerイメージはamd64, 386, arm64, arm/v7, arm/v6に対応しています。さらに、他のアーキテクチャであってもDockerを使わずにこのシェルスクリプトを実行することができます。</dd>
<dt>BusyBoxで実行可能なシェルスクリプト</dt>
<dd>BusyBox のシェルで動作するように設計されています。他にも、Bashはもちろん、DebianやUbuntuの/bin/shとして採用されているdashでも動作します。</dd> 
<dt>複数のゾーン・レコードに対応</dt>
<dd>複数のゾーンに含まれる、複数のレコードを更新することができます。</dd>
<dt>IPv4とIPv6の両方をサポート</dt>
<dd>IPv4 アドレスだけでなく、IPv6 アドレスにも対応しています。</dd>
<dt>グローバルIPアドレスの確実な取得</dt>
<dd>間違ったグローバルIPアドレスを設定しないよう、複数の取得元からアドレスを取得し、一致することを確認してから処理を実行します。</dd>
<dt>IPアドレス取得方法のカスタマイズが可能</dt>
<dd>デフォルトでは、IPアドレスを外部HTTPSサーバーより取得します。設定により、外部DNSサーバーから取得させることも可能です。また、IPアドレスを取得する独自のコマンドを設定することもできます。レコードごとに、固定IPアドレスや独自のIPアドレス取得用コマンドの指定も可能です。</dd>
<dt>キャッシュ機能によるCloudflare API呼び出し回数の節約</dt>
<dd>各レコードの設定状態をキャッシュすることにより、API呼び出し回数を節約します。キャッシュの期限が切れるまで、グローバルIPアドレスが変わらない限り、APIアクセスを行いません。キャッシュの有効期間は設定ファイルで変更できます（デフォルトは1時間）。</dd>
<dt>処理にあわせて実行する外部コマンドを設定可能</dt>
<dd>レコードの作成・更新・削除時などに、外部コマンドを実行することができます。curlコマンドを使って、WebhookにPOSTリクエストを送信するといったことも可能です。</dd>
</dl>

## 動作要件
Dockerイメージを用いる場合、Dockerのインストールが必要です。Dockerを用いずスクリプトを実行する場合、curlコマンドとjqコマンドが必要です。

## 使い方

1. Dockerが動作する環境を用意します。

1. CloudFlareでゾーンごとにAPI_TOKENを作成します。ゾーンDNSを編集する権限を設定してください。詳しい方法は、以下のページで解説されています。

    https://support.cloudflare.com/hc/ja/articles/200167836

1. 任意の場所にディレクトリを作成し、以下のコマンドでconfig.jsonを作成します。CloudflareのAccess TokenもしくはAccess Keyを記述するので、他のユーザーが読むことができないようパーミッションを設定しておきます。

    ```
    $ mkdir /some/where
    $ cd /some/where
    $ touch config.json
    $ chmod 600 config.json
    ```

1. config.jsonを編集します。以下は例です。設定対象のゾーン名（ドメイン名）、APIトークン、レコード名を記述してください。ルートドメインを指定するには、レコード名に「@」を記述します。

    ```
    {
      "zones": [
        {
          "name": "example.com",
          "api_token": "your api token here",
          "records": [
            {
              "name": "@",
              "types": ["A"],
              "proxied": true,
              "create": true
            },
            {
              "name": "home",
              "types": ["A"],
              "proxied": false,
              "create": true
            }
          ]
        }
      ]
    }
    ```

    設定ファイルの完全な例はこのドキュメントの最後を参照してください。

1. 以下のコマンドを実行します。

    ```
    $ docker run -t -d --name cloudflare-ddns-multi -v $PWD/config.json:/etc/cloudflare-ddns-multi/config.json jkbys/cloudflare-ddns-multi
    ```

1. 以下のコマンドでログを確認できます。エラーが出ている場合は、設定を見直してください。

    ````
    $ docker logs cloudflare-ddns-multi
    ````

この方法では、Aレコード（IPv4アドレス）だけが更新されます。AAAAレコード（IPv6アドレス）を更新する方法は後述します。

## Docker Compose

Docker Composeを用いてコンテナの作成と実行を行うこともできます。以下は、docker-compose.ymlの記述例です。config.jsonと同じディレクトリに作成します。

```
version: '3'
​
services:
  cloudflare-ddns-multi:
    image: jkbys/cloudflare-ddns-multi
    restart: always
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config.json:/etc/cloudflare-ddns-multi/config.json:ro
```

## IPv6 (AAAA record)

DockerホストがIPv6アドレスでインターネットにアクセスできるなら、グローバルIPv6アドレスをAAAAレコードに設定することができます。以下は、config.jsonの記述例です。

```
{
  "interval_sec": 300,
  "cache_timeout_sec": 3600,
  "enable_ipv6": true,
  "zones": [
    {
      "name": "example.com",
      "api_token": "your api token here",
      "records": [
        {
          "name": "@",
          "types": ["A", "AAAA"],
          "proxied": true,
          "create": true
        },
        {
          "name": "home",
          "types": ["A", "AAAA"],
          "proxied": false,
          "create": true
        },
        {
          "name": "home-v4",
          "types": ["A"],
          "proxied": false,
          "create": true
        },
        {
          "name": "home-v6",
          "types": ["AAAA"],
          "proxied": false,
          "create": true
        }
      ]
    }
  ]
}
```

このように、IPv6アドレスを設定したいレコードの"types"に、"AAAA"を追加します。

この例では、example.comとhome.example.comにはIPv4アドレスとIPv6アドレスの両方が設定され、home-v4.example.comにはIPv4アドレスだけが、home-v6.example.comにはIPv6アドレスだけが設定されます。

なお、IPv6を設定するためには、DockerコンテナがIPv6でインターネットと通信できるよう設定する必要があります。最も簡単な方法は、hostネットワークモードを用いることです。以下の例のように、docker runコマンドの実行時に、「--net=host」オプションを指定するとhostネットワークモードとなります。

```
$ docker run -t -d --name cloudflare-ddns-multi -v $PWD/config.json:etc/cloudflare-ddns-multi/config.json --net=host jkbyscloudflare-ddns-multi
```

以下は、docker-compose.ymlでhostネットワークモードを指定する例です。

```
version: '3'
​
services:
  cloudflare-ddns-multi:
    image: jkbys/cloudflare-ddns-multi
    restart: always
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - ./config.json:/etc/cloudflare-ddns-multi/config.json:ro
    network_mode: "host"
```
​
デフォルトのbridgeネットワークモードでIPv6を用いるには、DockerデーモンのIPv6サポートを有効にし、さらにルーティングなどを正しく設定する必要があります。

## イベント発生時のコマンド実行

各イベント発生時に実行するコマンドを設定できます。この機能により、たとえば、DNSレコード更新時にWebhook URLへPOSTリクエストを送信するといったことができます。設定方法は、このドキュメントの最後の設定ファイルの例を参照してください。

## Dockerを使わずに利用

Dockerを使わずに利用する場合、<a href="https://github.com/jkbys/cloudflare-ddns-multi">Githubレポジトリ</a>からcloudflare-ddns-multi.shファイルを取得し、以下のように実行してください。

```
$ sh cloudflare-ddns-multi.sh config.json
```
​
設定ファイルは以下の順番で検索され、最初に見つかったものが読み込まれます。

 * 第1引数
 * .config/cloudflare-ddns-multi/config.json
 * /etc/cloudflare-ddns-multi/config.json

## 設定ファイルの完全な例

"_"で始まる項目には解説文を記述しています。

```
{
  "interval_sec": 300,
  "interval_after_fail_sec": 1800,
  "cache_timeout_sec": 3600,
  "enable_ipv4": true,
  "enable_ipv6": true,
  "_ipv4_ipv6_command_type": "'curl', 'drill' or 'dig'. add drill or dig package on the container or the system as needed",
  "ipv4_command_type": "curl",
  "ipv6_command_type": "curl",
  "_oneshot": "if true, run once and exit",
  "oneshot": false,
  "zones": [
    {
      "name": "example.com",
      "api_token": "your token here",
      "records": [
        {
          "name": "@",
          "_types": "record types, A or AAAA",
          "types": ["A", "AAAA"],
          "proxied": false,
          "_ttl": "1(default) is auto",
          "ttl": 1,
          "_create": "if it doesn't exist on cloudflare, automatically create it or not",
          "create": true
        },
        {
          "name": "fixed",
          "types": ["A", "AAAA"],
          "proxied": false,
          "fixed_ipv4": "203.0.113.119",
          "fixed_ipv6": "2001:db8::c7",
          "create": true
        },
        {
          "name": "command",
          "types": ["A", "AAAA"],
          "proxied": false,
          "_command_ipv4": "command for return IPv4 address",
          "command_ipv4": "/usr/local/bin/get-ipv4-address.sh",
          "_command_ipv6": "command for return IPv6 address",
          "command_ipv6": "/usr/local/bin/get-ipv6-address.sh",
          "create": true
        }
      ]
    },
    {
      "name": "example.net",
      "_email_and_api_key": "email and api_key for authentication instead of api_token",
      "email": "your email here",
      "api_key": "your key here",
      "records": [
        {
          "name": "tmp",
          "types": ["A", "AAAA"],
          "proxied": true,
          "create": true,
          "_remove_on_exit": "if true, remove this record when exiting",
          "remove_on_exit": true
        }
      ]
    }
  ],
  "_command_timeout": "timeout in seconds for each commands",
  "command_timeout": 30,
  "_commands": "%MESSAGE% in the command string is replaced by the process or error content.",
  "commands": {
    "_on_error": "commands to be executed when an error occurs",
    "on_error": [
      "command1 \"%MESSAGE%\"",
      "command2 \"%MESSAGE%\""
    ],
    "_on_update": "commands to be executed when record is updated",
    "on_update": [
      "command1 \"%MESSAGE%\""
    ],
    "_on_create": "commands to be executed when record is created",
    "on_create": [
      "command1 \"%MESSAGE%\""
    ],
    "_on_remove": "commands to be executed when record is removed",
    "on_remove": [
      "command1 \"%MESSAGE%\""
    ],
    "_on_address_check": "commands to be executed when global addresses are checked",
    "on_address_check": [
      "command1 \"%MESSAGE%\""
    ],
    "_on_address_change": "commands to be executed when global addresses are changed",
    "on_address_change": [
      "command1 \"%MESSAGE%\""
    ],
    "_on_launch": "commands to be executed when this script is launched",
    "on_launch": [
      "command1 \"%MESSAGE%\""
    ],
    "_on_exit": "commands to be executed when this script is existing",
    "on_exit": [
      "command1 \"%MESSAGE%\""
    ]
  }
}
```
​
