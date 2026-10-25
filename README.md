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
- Run a build variant: `flutter run --flavor devFoss` (no Google code;
  push through a push app such as ntfy) or `--flavor devGms` (adds the
  opt-in Google Play services push). `prodFoss` / `prodGms` are the
  release apps.

- Setup local chat-sever by following instruction in [chat-server](https://www.github.com/ramank775/chat-server) repo.
- Create copy of `config.json.tmpl` to `config.local.json` (for development setup) and `config.json` (for production build).
- Update `api_url` and `ws_url` of  [chat-server](https://www.github.com/ramank775/chat-server)




# Contribution
[Vartalap](https://vartalap.one9x.org) is an open source project. We are looking for building the community around the project, welcoming everyone or anyone who is interested in contributing.

- Facing any issue? Raise an issue [here](https://github.com/ramank775/vartalap/issues/new?assignees=&labels=bug&template=bug_report.md&title=%5BBUG%5D) with the necessary details.

- Looking for a new feature? Raise an feature request [here](https://github.com/ramank775/vartalap/issues/new?assignees=&labels=enhancement&template=feature_request.md&title=%5BFEAT%5D).

- Found a security issue? Report it responsibility, view our security policy [here](https://github.com/ramank775/vartalap/security/policy).

- Wants to resolve an issue? **Thanks!** initiate the discussion on issue of your choice.

## Code Of Conduct

[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](./CODE_OF_CONDUCT.md)

Vartalap has adopted [Contributor Covenant](./CODE_OF_CONDUCT.md), we expect project participants to adhere to. Please read the [full text](./CODE_OF_CONDUCT.md) to understand what action will and will not be tolerated.


# LICENSE
[GNU GENERAL PUBLIC LICENSE](./LICENCE)

# Contact us
- Twitter [@vartalap_app](https://twitter.com/vartalap_app).

