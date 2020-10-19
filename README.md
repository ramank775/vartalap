[![Gitpod ready-to-code](https://img.shields.io/badge/Gitpod-ready--to--code-blue?logo=gitpod)](https://gitpod.io/#https://github.com/ramank775/vartalap)

# Vartalap
Vartalap is an open source personal chat application. It is design to provide the level of transparency in the personal messaging application with your data.

<a href='https://play.google.com/store/apps/details?id=com.one9x.vartalap'><img alt='Get it on Google Play' src='https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png' width="150" /></a>

## Setup with gitpod

`
flutter channel master
`

`
flutter doctor -v
`

#### Feel free to use your own ports configuration

`
SMARTPHONE_INTERNAL_IP = 192.168.0.10
`

`
SMARTPHONE_INTERNAL_PORT = 5555
`

#### [Localhost command] To switch adb on your device to work over the network using port 5555

`
adb tcpip SMARTPHONE_INTERNAL_PORT
`

#### [Localhost command] Check connection from localhost

`
adb connect SMARTPHONE_INTERNAL_IP:SMARTPHONE_INTERNAL_PORT
`

#### [Localhost command] Ngrok tcp forward to your mobile or Forward a chosen port on your router

`
ngrok tcp SMARTPHONE_INTERNAL_IP:SMARTPHONE_INTERNAL_PORT
`

#### [Gitpod command] Connect from your Gitpod to your localhost for debugging

`
adb connect NGROK_ADDRESS:NGROK_PORT
`

`
flutter run
`
