#!/bin/bash
flutter build apk --release --dart-define=GITHUB_BUILD=true "$@" && cd build/app/outputs/apk/release
