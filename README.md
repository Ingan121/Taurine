# Taurine (Unofficial)

iOS 14 untethered jailbreak.
Ported kfd exploit.

# Untether
Made this as the KFD exploit is faster and (seemingly) more stable than cicuta_virosa.<br>
It has an intentional 10 seconds delay, as the KFD exploit is super unstable right after boot.<br>
Untether is based on [haxx](https://github.com/asdfugil/haxx).<br>
This also implemented the Fugu14's NVRAM check for safeguard, so follow [this](https://github.com/LinusHenze/Fugu14#recovery) if you're stuck in a panic loop.

**I don't recommend using it if you don't know what you're doing. Use at your own risk!**

# Building and Installation (WIP)
1. Open `external/SwiftZSTD` with Xcode and build it
2. Edit `TaurineHeadless/Makefile`'s third line's `-F` argument to point to your SwiftZSTD build directory
3. `cd TaurineHeadless` and `make`
4. `cd ../untether` and `make`
5. On your iDevice, first jailbreak with Taurine (Original or KFD) and put permasigned `Taurine.app` to `/Applications`. (Use permasigneriOS, TrollStore+Filza, etc. for this)
6. Put built `TaurineHeadless` to `/Applications/Taurine.app` and `fileproviderctl_internal` to `/usr/local/bin`
7. Rename `/System/Library/PrivateFrameworks/CoreAnalytics.framework/Support/analyticsd` to `analyticsd.back`
8. Copy `/usr/bin/fileproviderctl` as `/System/Library/PrivateFrameworks/CoreAnalytics.framework/Support/analyticsd`

# Supported Devices

All A8-A11 devices on iOS 14.0-14.4.2<br>
It also works on 14.3 Xs. (Not sure about other 14.0-14.3 A12+ devices)

# License

Taurine is licensed under the 4-Clause BSD License
