![Build and push Docker image](https://github.com/jkbys/cloudflare-ddns-multi/workflows/Build%20and%20push%20Docker%20image/badge.svg)

# cloudflare-ddns-multi
Cloudflare DDNS Multiple Zone/Recoerd Updater - Docker micro image / Shell script

This is a small Docker image for using CloudFlare DNS as Dynamic DNS. It periodically fetches global IP addresses (IPv4 and IPv6) and sets them to A and AAAA records in multiple zones on CloudFlare DNS. You can also run this script from a program such as cron instead of using the Docker.

## Features
<dl>
<dt>A small Docker image</dt>
<dd>The download size (compressed size) of this image is less than 4MB.</dd>
<dt>Support for Multiple Architectures</dt>
<dd>You can use Docker images for amd64, 386, arm64, arm/v7, arm/v6. Additinally, you can run this shell script without Docker even on other architectures.</dd>
<dt>Shell script that can be executed by BusyBox</dt>
<dd>It is designed to work with the shells in BusyBox. It also works with Bash, of course, but also with dash, which has been adopted by Debian and Ubuntu as /bin/sh.</dd>
<dt>Support for multiple zones and records</dt>
<dd>You can update multiple records contained in multiple zones.</dt>
<dt>Support for both IPv4 and IPv6</dt>
<dd>Not only IPv4 addresses, but also IPv6 addresses are supported.</dt>
<dt>Reliable acquisition of global IP addresses</dt>
<dd>To avoid setting a wrong global IP address, addresses are obtained from multiple sources and confirmed to match before processing.</dd>
<dt>Custimizable the method of IP address acquisition</dt>
<dd>IP address is obtained from an external HTTPS servers by default. It is also possible to obtain the IP address from an external DNS server by configuring it. You can also set up your own command to retrieve the IP address. It is also possible to specify a fixed IP address or a unique command for obtaining an IP address for each record.</dd>
<dt>Saving on the number of Cloudflare API calls by caching</dt>
<dd>Caching the configuration state of each record saves the number of API calls. API accesses will not be performed until the cache expires, unless the global IP address is changed. The validity period of the cache can be changed in the configuration file (default is one hour).</dd>
<dt>External commands can be configured to be executed in conjunction with processing</dt>
<dd>You can set any command to execute when records are created, updated, or deleted. You can use this feature, for example, to send POST data to a Webhook URL by executing the curl command to notify your smartphone.</dd>
</dl>

## Requirements
If you are using a Docker image, you will need to install Docker.
If you are running this script without using Docker, you will need to install the curl and jq commands.

## How to use

1. Prepare the environment for Docker to run.

1. Create an API_TOKEN for each zone in CloudFlare. Set the permissions to edit the zone DNS. The detailed instructions are described in the following pages:

    https://support.cloudflare.com/hc/en-us/articles/200167836

1. Create directory of your choice, and create config.json file. It will contain the Cloudflare Access Token or key, so set the permissions so that no other user can read it.

    ```
    $ mkdir /some/where
    $ cd /some/where
    $ touch config.json
    $ chmod 600 config.json
    ```

1. Edit config.json. The following is an example. Describe the zone name (domain name), API token, and record name. To specify the root domain, put an @ for the record name.

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

    See the end of this document for a complete example of a configuration file.

1. Execute the following command:

    ```
    $ docker run -t -d --name cloudflare-ddns-multi -v $PWD/config.json:/etc/cloudflare-ddns-multi/config.json jkbys/cloudflare-ddns-multi
    ```

1. Check the log using the following command. If you get an error, review your settings.

    ````
    $ docker logs cloudflare-ddns-multi
    ````

This quick method only updates A records (IPv4 addresses). How to update AAAA records (IPv6 addresses) is described below.

## Docker Compose

You can also use Docker Compose to create and run containers. The following is an example of docker-compose.yml, created in the same directory as config.json.

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

​If your Docker host can access the Internet with an IPv6 address, you can set your global IPv6 address to a AAAA record. The following is an example of config.json description.

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

As in this example, add "AAAA" to the "types" of the record for which you want to set an IPv6 address.

In this example, both example.com and home.example.com are set with both IPv4 and IPv6 addresses, and home-v4.example.com is set with only IPv4 addresses, and home-v6.example.com is set with only IPv6 addresses.

In order to configure IPv6, the Docker container must be able to communicate with the Internet using IPv6. The easiest way to do this is to use the host network mode, which can be set by specifying the "--net=host" option when running the docker run command.

```
$ docker run -t -d --name cloudflare-ddns-multi -v $PWD/config.json:etc/cloudflare-ddns-multi/config.json --net=host jkbyscloudflare-ddns-multi
```

The following is an example of specifying the host network mode in docker-compose.yml.
​
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
To use IPv6 in the default bridge network mode, you need to enable IPv6 support for the Docker daemon and also configure the routing and other settings correctly.

## Command execution when an event occurs

You can configure a command to be executed at each event. This feature allows you to, for example, send a POST request to a Webhook URL when a DNS record is updated. See the examples in the configuration file at the end of this document for instructions.
​
## Use without Docker

If you don't want to use Docker, get the cloudflare-ddns-multi.sh file from the <a href="https://github.com/jkbys/cloudflare-ddns-multi">Github repository</a> and execute as follows:
​
```
$ sh cloudflare-ddns-multi.sh config.json
```

The configuration files are searched in the following order and the first one found is loaded.

 * The first argument
 * .config/cloudflare-ddns-multi/config.json
 * /etc/cloudflare-ddns-multi/config.json
​
## A complete example of a configuration file

Items that begin with "_" have explanatory text.
​
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
  "_commands": "The "%MESSAGE%" in the command string is replaced by the process or error content.",
  "commands": {
    "_on_error": "commands to be executed when an error occurs",
    "on_error": [
      "command1",
      "command2"
    ],
    "_on_update": "commands to be executed when record is updated",
    "on_update": [
      "command1"
    ],
    "_on_create": "commands to be executed when record is created",
    "on_create": [
      "command1"
    ],
    "_on_remove": "commands to be executed when record is removed",
    "on_remove": [
      "command1"
    ],
    "_on_address_check": "commands to be executed when global addresses are checked",
    "on_address_check": [
      "command1"
    ],
    "_on_address_change": "commands to be executed when global addresses are changed",
    "on_address_change": [
      "command1"
    ],
    "_on_launch": "commands to be executed when this script is launched",
    "on_launch": [
      "command1"
    ],
    "_on_exit": "commands to be executed when this script is existing",
    "on_exit": [
      "command1"
    ]
  }
}
```
