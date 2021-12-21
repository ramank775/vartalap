# Vartalap

[Vartalap](https://vartalap.one9x.org) is an open source personal chat application. It is design to provide the level of transparency in the personal messaging application with your data.

## Supported Platform

- [x] Android
- [ ] Ios

## Features
- Texts with emoji 
- Group Chat

## Setup

### Local setup

- Download or clone the repo `https://github.com/ramank775/vartalap.git`
- Get the required dependencies `flutter pub get`

- Setup local chatsever by following instruction in [chat-server](https://www.github.com/ramank775/chat-server) repo.
- Create copy of `config.json.tmpl` to `config.local.json` (for development setup) and `config.json` (for production build).
- Update `api_url` and `ws_url` of  [chat-server](https://www.github.com/ramank775/chat-server)


### Setup with gitpod
Click on the gitpod badge to start cloud IDE 

[![Gitpod ready-to-code](https://img.shields.io/badge/Gitpod-ready--to--code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/ramank775/vartalap) 

Localhost command
- Feel free to use your own ports configuration

    `SMARTPHONE_INTERNAL_IP = 192.168.0.10`

    `SMARTPHONE_INTERNAL_PORT = 5555`

-  To switch adb on your device to work over the network using port 5555

    `adb tcpip SMARTPHONE_INTERNAL_PORT`

- Check connection from localhost

    `adb connect SMARTPHONE_INTERNAL_IP:SMARTPHONE_INTERNAL_PORT`

-  Ngrok tcp forward to your mobile or Forward a chosen port on your router

    `ngrok tcp SMARTPHONE_INTERNAL_IP:SMARTPHONE_INTERNAL_PORT`

Gitpod command
- Connect from your Gitpod to your localhost for debugging
    `adb connect NGROK_ADDRESS:NGROK_PORT`

    `flutter run`

Chat Server
- Start chatsever by following instruction in [chat-server](https://www.github.com/ramank775/chat-server) repo.
- Create copy of `config.json.tmpl` to `config.local.json` (for development setup) and `config.json` (for production build).
- Update `api_url` and `ws_url` of  [chat-server](https://www.github.com/ramank775/chat-server)



# Contribution
[Vartalap](https://vartalap.one9x.org) is an open source project. We are looking for building the community around the project, welcoming everyone or anyone who is interested in contributing.

- Facing any issue? Raise an issue [here](https://github.com/ramank775/vartalap/issues/new?assignees=&labels=bug&template=bug_report.md&title=%5BBUG%5D) with the necessary details.

- Looking for a new feture? Raise an feature request [here](https://github.com/ramank775/vartalap/issues/new?assignees=&labels=enhancement&template=feature_request.md&title=%5BFEAT%5D).

- Found a security issue? Report it responsibility, view our security policy [here](https://github.com/ramank775/vartalap/security/policy).

- Wants to resolve an issue? **Thanks!** initiate the discussion on issue of your choice.

## Code Of Conduct

[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

Vartalap has adopted [Contributor Covenant](code_of_conduct.md), we expect project participants to adhere to. Please read the [full text](code_of_conduct.md) to understand what action will and will not be tolerated.


# LICENSE
[GNU GENERAL PUBLIC LICENSE](./LICENSE)

# Contact us
- Twitter [@vartalap_app](https://twitter.com/vartalap_app).

