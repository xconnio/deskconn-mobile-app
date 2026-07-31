install:
	flutter pub get

lint:
	dart analyze --fatal-infos

lint-fix:
	dart fix --apply

check-format:
	dart format --output=none --set-exit-if-changed --line-length 120 .

format:
	dart format --line-length 120 .

setup-quic:
	mkdir -p android/app/src/main/jniLibs/arm64-v8a
	curl -L https://github.com/xconnio/xconn-dart/releases/latest/download/libdart_quic_ffi-android-arm64.so \
		-o android/app/src/main/jniLibs/arm64-v8a/libdart_quic_ffi.so

build-apk:
	flutter build apk --no-tree-shake-icons
