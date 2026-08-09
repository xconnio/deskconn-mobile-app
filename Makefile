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

# Builds the iOS static libraries for the QUIC FFI (device + simulator) from the
# dart-quic Rust crate, then copies them where the Xcode project expects them.
# Requires: Rust toolchain (rustup) with aarch64-apple-ios and
# aarch64-apple-ios-sim targets. The deskconn server expects the wamp.2.quic
# ALPN, so the crate default (h3/hq-29) is patched before building.
setup-quic-ios:
	@set -e; \
	if [ ! -d /tmp/dart-quic ]; then \
		git clone --depth 1 https://github.com/arcticfox1919/dart-quic.git /tmp/dart-quic; \
	fi; \
	rustup target add aarch64-apple-ios aarch64-apple-ios-sim; \
	cd /tmp/dart-quic/dart-quic-ffi && \
		sed -i '' 's/crate-type = \[.*\]/crate-type = ["staticlib"]/' Cargo.toml; \
		sed -i '' 's/vec!\[b"h3".to_vec(), b"hq-29".to_vec()\]/vec![b"wamp.2.quic".to_vec()]/g' src/quic/quic_config.rs; \
	cargo build --release --target aarch64-apple-ios; \
	cargo build --release --target aarch64-apple-ios-sim; \
	mkdir -p ios/Runner/QuicFFI; \
	cp target/aarch64-apple-ios/release/libdart_quic_ffi.a \
		ios/Runner/QuicFFI/libdart_quic_ffi-device.a; \
	cp target/aarch64-apple-ios-sim/release/libdart_quic_ffi.a \
		ios/Runner/QuicFFI/libdart_quic_ffi-sim.a

build-apk:
	flutter build apk --no-tree-shake-icons
