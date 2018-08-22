include config.mk

MAKE_J ?= -j 8

repo_base_url = https://github.com/frida
repo_suffix := .git

libiconv_version := 1.15
elfutils_version := 0.173
libdwarf_version := 20180724
openssl_version := 1.1.0h
v8_api_version := 7.0


build_platform := $(shell uname -s | tr '[A-Z]' '[a-z]' | sed 's,^darwin$$,macos,')
build_arch := $(shell releng/detect-arch.sh)
build_platform_arch := $(build_platform)-$(build_arch)

ifeq ($(build_platform), linux)
	download := wget -O - -q
else
	download := curl -sS
endif

ifdef FRIDA_HOST
	host_platform := $(shell echo $(FRIDA_HOST) | cut -f1 -d"-")
else
	host_platform := $(build_platform)
endif
ifdef FRIDA_HOST
	host_arch := $(shell echo $(FRIDA_HOST) | cut -f2 -d"-")
else
	host_arch := $(build_arch)
endif
host_platform_arch := $(host_platform)-$(host_arch)

enable_diet := $(shell echo $(host_platform_arch) | egrep -q "^(linux-arm|linux-mips|linux-mipsel|qnx-.+)$$" && echo 1 || echo 0)


ifeq ($(host_platform), macos)
	iconv := build/fs-%/lib/libiconv.a
	glib_tls_provider := build/fs-%/lib/pkgconfig/glib-openssl-static.pc
	glib_tls_args := -Dca_certificates=no
ifeq ($(host_arch), x86)
	openssl_arch_args := darwin-i386-cc
endif
ifeq ($(host_arch), x86_64)
	openssl_arch_args := darwin64-x86_64-cc enable-ec_nistp_64_gcc_128
endif
endif
ifeq ($(host_platform), ios)
	iconv := build/fs-%/lib/libiconv.a
endif
ifeq ($(host_platform), linux)
	unwind := build/fs-%/lib/pkgconfig/libunwind.pc
	elf := build/fs-%/lib/libelf.a
	dwarf := build/fs-%/lib/libdwarf.a
	glib_tls_provider := build/fs-%/lib/pkgconfig/glib-openssl-static.pc
	glib_tls_args := -Dca_certificates=no
ifeq ($(host_arch), x86)
	openssl_arch_args := linux-x86
endif
ifeq ($(host_arch), x86_64)
	openssl_arch_args := linux-x86_64
endif
ifeq ($(host_arch), arm)
	openssl_arch_args := linux-armv4
endif
ifeq ($(host_arch), mipsel)
	openssl_arch_args := linux-mips32
endif
ifeq ($(host_arch), mips)
	openssl_arch_args := linux-mips32
endif
endif
ifeq ($(host_platform), android)
	unwind := build/fs-%/lib/pkgconfig/libunwind.pc
	iconv := build/fs-%/lib/libiconv.a
	elf := build/fs-%/lib/libelf.a
	dwarf := build/fs-%/lib/libdwarf.a
endif
ifeq ($(host_platform), qnx)
	unwind := build/fs-%/lib/pkgconfig/libunwind.pc
	iconv := build/fs-%/lib/libiconv.a
	elf := build/fs-%/lib/libelf.a
	dwarf := build/fs-%/lib/libdwarf.a
endif
ifeq ($(enable_diet), 0)
	v8 := build/fs-%/lib/pkgconfig/v8-$(v8_api_version).pc
endif

ifneq ($(iconv),)
	glib_iconv_option := -Diconv=native
endif

all: build/sdk-$(host_platform)-$(host_arch).tar.bz2
	@echo ""
	@echo -e "\033[0;32mSuccess!\033[0;39m Here's your SDK: \033[1m$<\033[0m"
	@echo ""
	@echo "It will be picked up automatically if you now proceed to build Frida."
	@echo ""


build/sdk-$(host_platform)-$(host_arch).tar.bz2: build/fs-tmp-$(host_platform_arch)/.package-stamp
	tar \
		-C build/fs-tmp-$(host_platform_arch)/package \
		-cjf $(abspath $@.tmp) \
		.
	mv $@.tmp $@

build/fs-tmp-%/.package-stamp: \
		build/fs-%/lib/pkgconfig/liblzma.pc \
		build/fs-%/lib/pkgconfig/sqlite3.pc \
		$(unwind) \
		$(iconv) \
		$(elf) \
		$(dwarf) \
		build/fs-%/lib/pkgconfig/glib-2.0.pc \
		$(glib_tls_provider) \
		build/fs-%/lib/pkgconfig/gee-0.8.pc \
		build/fs-%/lib/pkgconfig/json-glib-1.0.pc \
		build/fs-%/lib/pkgconfig/libsoup-2.4.pc \
		$(v8)
	$(RM) -r $(@D)/package
	mkdir -p $(@D)/package
	cd build/fs-$* \
		&& [ -d lib/gio/modules ] && gio_modules=lib/gio/modules/*.a || gio_modules= \
		&& [ -d lib32 ] && lib32=lib32 || lib32= \
		&& [ -d lib64 ] && lib64=lib64 || lib64= \
		&& tar -c \
			include \
			lib/*.a \
			lib/*.la \
			lib/glib-2.0 \
			lib/libffi* \
			lib/pkgconfig \
			$$gio_modules \
			$$lib32 \
			$$lib64 \
			share/aclocal \
			share/glib-2.0/schemas \
			share/vala \
			| tar -C $(abspath $(@D)/package) -xf -
	releng/relocatify.sh $(@D)/package $(abspath build/fs-$*)
ifeq ($(host_platform), ios)
	cp $(shell xcrun --sdk macosx --show-sdk-path)/usr/include/mach/mach_vm.h $(@D)/package/include/frida_mach_vm.h
endif
	@touch $@


build/.libiconv-stamp:
	$(RM) -r libiconv
	mkdir libiconv
	cd libiconv \
		&& $(download) https://gnuftp.uib.no/libiconv/libiconv-$(libiconv_version).tar.gz | tar -xz --strip-components 1 \
		&& patch -p1 < ../releng/patches/libiconv-android.patch
	@mkdir -p $(@D)
	@touch $@

build/fs-tmp-%/libiconv/Makefile: build/fs-env-%.rc build/.libiconv-stamp
	$(RM) -r $(@D)
	mkdir -p $(@D)
	. $< \
		&& cd $(@D) \
		&& ../../../libiconv/configure \
			--enable-static \
			--disable-shared \
			--enable-relocatable \
			--disable-rpath

build/fs-%/lib/libiconv.a: build/fs-env-%.rc build/fs-tmp-%/libiconv/Makefile
	. $< \
		&& cd build/fs-tmp-$*/libiconv \
		&& make $(MAKE_J) \
		&& make $(MAKE_J) install
	@touch $@


build/.elfutils-stamp:
	$(RM) -r elfutils
	mkdir elfutils
	cd elfutils \
		&& $(download) https://sourceware.org/pub/elfutils/$(elfutils_version)/elfutils-$(elfutils_version).tar.bz2 | tar -xj --strip-components 1 \
		&& patch -p1 < ../releng/patches/elfutils-android.patch
	@mkdir -p $(@D)
	@touch $@

build/fs-tmp-%/elfutils/Makefile: build/fs-env-%.rc build/.elfutils-stamp build/fs-%/lib/pkgconfig/liblzma.pc
	$(RM) -r $(@D)
	mkdir -p $(@D)
	. $< \
		&& cd $(@D) \
		&& if [ -n "$$FRIDA_GCC" ]; then \
			export CC="$$FRIDA_GCC"; \
		fi \
		&& ../../../elfutils/configure

build/fs-%/lib/libelf.a: build/fs-env-%.rc build/fs-tmp-%/elfutils/Makefile
	. $< \
		&& cd build/fs-tmp-$*/elfutils \
		&& make $(MAKE_J) -C libelf libelf.a
	install -d build/fs-$*/include
	install -m 644 elfutils/libelf/libelf.h build/fs-$*/include
	install -m 644 elfutils/libelf/elf.h build/fs-$*/include
	install -m 644 elfutils/libelf/gelf.h build/fs-$*/include
	install -m 644 elfutils/libelf/nlist.h build/fs-$*/include
	install -d build/fs-$*/lib
	install -m 644 build/fs-tmp-$*/elfutils/libelf/libelf.a build/fs-$*/lib
	@touch $@


build/.libdwarf-stamp:
	$(RM) -r libdwarf
	mkdir libdwarf
	cd libdwarf \
		&& $(download) https://www.prevanders.net/libdwarf-$(libdwarf_version).tar.gz | tar -xz --strip-components 1
	@mkdir -p $(@D)
	@touch $@

build/fs-tmp-%/libdwarf/Makefile: build/fs-env-%.rc build/.libdwarf-stamp build/fs-%/lib/libelf.a
	$(RM) -r $(@D)
	mkdir -p $(@D)
	. $< && cd $(@D) && ../../../libdwarf/libdwarf/configure

build/fs-%/lib/libdwarf.a: build/fs-env-%.rc build/fs-tmp-%/libdwarf/Makefile
	. $< \
		&& cd build/fs-tmp-$*/libdwarf \
		&& make $(MAKE_J) HOSTCC="gcc" HOSTCFLAGS="" HOSTLDFLAGS="" libdwarf.a
	install -d build/fs-$*/include
	install -m 644 libdwarf/libdwarf/dwarf.h build/fs-$*/include
	install -m 644 build/fs-tmp-$*/libdwarf/libdwarf.h build/fs-$*/include
	install -d build/fs-$*/lib
	install -m 644 build/fs-tmp-$*/libdwarf/libdwarf.a build/fs-$*/lib
	@touch $@


define make-git-autotools-module-rules
build/.$1-stamp:
	$(RM) -r $1
	git clone $(repo_base_url)/$1$(repo_suffix)
	cd $1 && git submodule init && git submodule update
	@mkdir -p $$(@D)
	@touch $$@

$1/configure: build/fs-env-$(build_platform_arch).rc build/.$1-stamp
	. $$< \
		&& cd $$(@D) \
		&& [ -f autogen.sh ] && NOCONFIGURE=1 ./autogen.sh || autoreconf -ifv

build/fs-tmp-%/$1/Makefile: build/fs-env-%.rc $1/configure $3
	$(RM) -r $$(@D)
	mkdir -p $$(@D)
	. $$< && cd $$(@D) && ../../../$1/configure

$2: build/fs-env-%.rc build/fs-tmp-%/$1/Makefile
	. $$< \
		&& cd build/fs-tmp-$$*/$1 \
		&& make $(MAKE_J) \
		&& make $(MAKE_J) install
	@touch $$@
endef

define make-git-meson-module-rules
build/.$1-stamp:
	$(RM) -r $1
	git clone $(repo_base_url)/$1$(repo_suffix)
	cd $1 && git submodule init && git submodule update
	@mkdir -p $$(@D)
	@touch $$@

build/fs-tmp-%/$1/build.ninja: build/fs-env-$(build_platform_arch).rc build/fs-env-%.rc build/.$1-stamp $3 releng/meson/meson.py
	$(RM) -r $$(@D)
	(. build/fs-meson-env-$(build_platform_arch).rc \
		&& . build/fs-config-$$*.site \
		&& if [ $$* = $(build_platform_arch) ]; then \
			cross_args=""; \
		else \
			cross_args="--cross-file build/fs-$$*.txt"; \
		fi \
		&& $(MESON) \
			--prefix $$$$frida_prefix \
			--libdir $$$$frida_prefix/lib \
			--default-library static \
			--buildtype minsize \
			$$$$cross_args \
			$4 \
			$$(@D) \
			$1)

$2: build/fs-env-%.rc build/fs-tmp-%/$1/build.ninja
	(. $$< \
		&& $(NINJA) -C build/fs-tmp-$$*/$1 install)
	@touch $$@
endef

$(eval $(call make-git-meson-module-rules,zlib,build/fs-%/lib/pkgconfig/zlib.pc,))

$(eval $(call make-git-autotools-module-rules,xz,build/fs-%/lib/pkgconfig/liblzma.pc,))

$(eval $(call make-git-meson-module-rules,sqlite,build/fs-%/lib/pkgconfig/sqlite3.pc,,))

$(eval $(call make-git-autotools-module-rules,libunwind,build/fs-%/lib/pkgconfig/libunwind.pc,build/fs-%/lib/pkgconfig/liblzma.pc))

$(eval $(call make-git-meson-module-rules,libffi,build/fs-%/lib/pkgconfig/libffi.pc,,))

$(eval $(call make-git-meson-module-rules,glib,build/fs-%/lib/pkgconfig/glib-2.0.pc,$(iconv) build/fs-%/lib/pkgconfig/zlib.pc build/fs-%/lib/pkgconfig/libffi.pc,$(glib_iconv_option) -Dselinux=false -Dlibmount=false -Dinternal_pcre=true -Dtests=false))

build/.openssl-stamp:
	$(RM) -r openssl
	mkdir openssl
	$(download) https://www.openssl.org/source/openssl-$(openssl_version).tar.gz | tar -C openssl -xz --strip-components 1
	@mkdir -p $(@D)
	@touch $@

build/fs-tmp-%/openssl/Configure: build/.openssl-stamp
	$(RM) -r $(@D)
	mkdir -p build/fs-tmp-$*
	cp -a openssl $(@D)
	@touch $@

build/fs-%/lib/pkgconfig/openssl.pc: build/fs-env-%.rc build/fs-tmp-%/openssl/Configure
	. $< \
		&& . $$CONFIG_SITE \
		&& export CC CFLAGS \
		&& cd build/fs-tmp-$*/openssl \
		&& perl Configure \
			--prefix=$$frida_prefix \
			--openssldir=/etc/ssl \
			no-comp \
			no-ssl2 \
			no-ssl3 \
			no-zlib \
			no-shared \
			enable-cms \
			$(openssl_arch_args) \
		&& make depend \
		&& make \
		&& make install_sw

$(eval $(call make-git-meson-module-rules,glib-openssl,build/fs-%/lib/pkgconfig/glib-openssl-static.pc,build/fs-%/lib/pkgconfig/glib-2.0.pc build/fs-%/lib/pkgconfig/openssl.pc,$(glib_tls_args)))

$(eval $(call make-git-meson-module-rules,libgee,build/fs-%/lib/pkgconfig/gee-0.8.pc,build/fs-%/lib/pkgconfig/glib-2.0.pc))

$(eval $(call make-git-meson-module-rules,json-glib,build/fs-%/lib/pkgconfig/json-glib-1.0.pc,build/fs-%/lib/pkgconfig/glib-2.0.pc,-Dintrospection=false -Dtests=false))

$(eval $(call make-git-meson-module-rules,libpsl,build/fs-%/lib/pkgconfig/libpsl.pc,,))

$(eval $(call make-git-meson-module-rules,libxml2,build/fs-%/lib/pkgconfig/libxml-2.0.pc,build/fs-%/lib/pkgconfig/zlib.pc build/fs-%/lib/pkgconfig/liblzma.pc,))

$(eval $(call make-git-meson-module-rules,libsoup,build/fs-%/lib/pkgconfig/libsoup-2.4.pc,build/fs-%/lib/pkgconfig/glib-2.0.pc build/fs-%/lib/pkgconfig/sqlite3.pc build/fs-%/lib/pkgconfig/libpsl.pc build/fs-%/lib/pkgconfig/libxml-2.0.pc,-Dgssapi=false -Dtls_check=false -Dgnome=false -Dintrospection=false -Dtests=false))


v8_common_args := \
	is_official_build=true \
	is_debug=false \
	v8_enable_v8_checks=false \
	symbol_level=0 \
	v8_monolithic=true \
	v8_use_external_startup_data=false \
	is_component_build=false \
	v8_enable_debugging_features=false \
	v8_enable_disassembler=false \
	v8_enable_gdbjit=false \
	v8_enable_i18n_support=false \
	strip_absolute_paths_from_debug_symbols=true \
	use_goma=false \
	v8_embedder_string="-frida" \
	$(NULL)

ifeq ($(host_arch), x86)
	v8_cpu := ia32
endif
ifeq ($(host_arch), x86_64)
	v8_cpu := x64
endif
ifeq ($(host_arch), arm)
	v8_cpu := arm
	v8_abi_args := arm_float_abi="softfp"
endif
ifeq ($(host_arch), armeabi)
	v8_cpu := arm
	v8_abi_args := arm_float_abi="softfp"
endif
ifeq ($(host_arch), armhf)
	v8_cpu := arm
	v8_abi_args := arm_float_abi="hard"
endif
ifeq ($(host_arch), arm64)
	v8_cpu := arm64
endif

v8_build_platform := $(shell echo $(build_platform) | sed 's,^macos$$,mac,')
ifeq ($(build_platform), macos)
	v8_platform_args := use_xcode_clang=true
endif
ifeq ($(host_platform), macos)
	v8_platform_args := mac_deployment_target="10.9.0"
endif
ifeq ($(host_platform), ios)
	v8_platform_args := mac_deployment_target="10.9.0" ios_deployment_target="7.0"
endif
ifeq ($(host_platform), linux)
	v8_libs_private := "-lrt"
endif
ifeq ($(host_platform), android)
	v8_libs_private := "-llog -lm"
endif

v8-checkout/depot_tools/gclient:
	$(RM) -r v8-checkout/depot_tools
	git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git v8-checkout/depot_tools

v8-checkout/.gclient: v8-checkout/depot_tools/gclient
	cd v8-checkout && depot_tools/gclient config --spec 'solutions = [ \
  { \
    "url": "$(repo_base_url)/v8.git", \
    "managed": False, \
    "name": "v8", \
    "deps_file": "DEPS", \
    "custom_deps": {}, \
  }, \
] \
'

v8-checkout/v8: v8-checkout/.gclient
	cd v8-checkout \
		&& export PATH=$(abspath v8-checkout/depot_tools):$$PATH \
		&& gclient sync
	@touch $@

build/fs-tmp-%/v8/build.ninja: v8-checkout/v8
	cd v8-checkout/v8 && ../depot_tools/gn gen $(abspath $(@D)) --args='target_cpu="$(v8_cpu)" $(v8_abi_args) $(v8_common_args) $(v8_platform_args)'

build/fs-tmp-%/v8/obj/libv8_monolith.a: build/fs-tmp-%/v8/build.ninja
	$(NINJA) -C build/fs-tmp-$*/v8 v8_monolith
	@touch $@

build/fs-%/lib/pkgconfig/v8-$(v8_api_version).pc: build/fs-tmp-%/v8/obj/libv8_monolith.a
	install -d build/fs-$*/include/v8-$(v8_api_version)/v8
	install -m 644 v8-checkout/v8/include/*.h build/fs-$*/include/v8-$(v8_api_version)/v8/
	install -d build/fs-$*/include/v8-$(v8_api_version)/v8/inspector
	install -m 644 build/fs-tmp-$*/v8/gen/include/inspector/*.h build/fs-$*/include/v8-$(v8_api_version)/v8/inspector/
	install -d build/fs-$*/include/v8-$(v8_api_version)/v8/libplatform
	install -m 644 v8-checkout/v8/include/libplatform/*.h build/fs-$*/include/v8-$(v8_api_version)/v8/libplatform/
	install -d build/fs-$*/lib
	install -m 644 $< build/fs-$*/lib/libv8-$(v8_api_version).a
	install -d $(@D)
	echo "prefix=\$${frida_sdk_prefix}" > $@.tmp
	echo "libdir=\$${prefix}/lib" >> $@.tmp
	echo "includedir=\$${prefix}/include/v8-$(v8_api_version)" >> $@.tmp
	echo "" >> $@.tmp
	echo "Name: V8" >> $@.tmp
	echo "Description: V8 JavaScript Engine" >> $@.tmp
	echo "Version: 7.0.242" >> $@.tmp
	echo "Libs: -L\$${libdir} -lv8-$(v8_api_version)" >> $@.tmp
ifdef v8_libs_private
	echo Libs.private: $(v8_libs_private) >> $@.tmp
endif
	echo "Cflags: -I\$${includedir} -I\$${includedir}/v8" >> $@.tmp
	mv $@.tmp $@


build/fs-env-%.rc:
	FRIDA_HOST=$* \
		FRIDA_OPTIMIZATION_FLAGS="$(FRIDA_OPTIMIZATION_FLAGS)" \
		FRIDA_DEBUG_FLAGS="$(FRIDA_DEBUG_FLAGS)" \
		FRIDA_ASAN=$(FRIDA_ASAN) \
		FRIDA_ENV_NAME=fs \
		FRIDA_ENV_SDK=none \
		./releng/setup-env.sh

releng/meson/meson.py:
	git submodule init releng/meson
	git submodule update releng/meson
	@touch $@


.PHONY: all
.SECONDARY:
