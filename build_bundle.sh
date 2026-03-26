#!/bin/bash
flutter build appbundle --release "$@" && cd build/app/outputs/bundle/release
