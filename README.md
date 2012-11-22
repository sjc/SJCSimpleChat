SJCSimpleChat
=============

This repo contains three things:

1. A set of classes based on Apple's [WiTap example code](http://developer.apple.com/library/ios/#samplecode/WiTap/Introduction/Intro.html) which advertise and find each other via bonjour and then create a socket connection over which data can be transfered. (client+server+connection)
2. A set of classes for implementing a simple chat client. (chat)
3. An example chat server daemon. (simplechatd)

This repo also contains a copy of Apple's TCPServer class.

The chat client classes (and thus the daemon) require [FMDB](https://github.com/ccgus/fmdb), which is used for message storage.

