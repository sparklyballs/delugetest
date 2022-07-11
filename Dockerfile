ARG ALPINE_VER="3.16"
FROM alpine:${ALPINE_VER} as fetch-stage

############## fetch stage ##############

# install fetch packages
RUN \
	apk add --no-cache \
		bash \
		curl

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# fetch version file
RUN \
	set -ex \
	&& curl -o \
	/tmp/version.txt -L \
	"https://raw.githubusercontent.com/sparklyballs/versioning/master/version.txt"

# fetch source code
# hadolint ignore=SC1091
RUN \
	. /tmp/version.txt \
	&& set -ex \
	&& mkdir -p \
		/tmp/libtorrent_src \
		/tmp/deluge_src \
	&& curl -o \
	/tmp/libtorrent.tar.gz -L \
	"https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_RELEASE}/libtorrent-rasterbar-${LIBTORRENT_RELEASE}.tar.gz" \
	&& tar xf \
	/tmp/libtorrent.tar.gz -C \
	/tmp/libtorrent_src --strip-components=1 \
	&& curl -o \
	/tmp/deluge.tar.xz -L \
	"http://download.deluge-torrent.org/source/${DELUGE_RELEASE%.*}/deluge-${DELUGE_RELEASE}.tar.xz" \
	&& tar xf \
	/tmp/deluge.tar.xz -C \
	/tmp/deluge_src --strip-components=1


FROM alpine:${ALPINE_VER} as libtorrent_build-stage

############## libtorrent build stage ##############

# copy artifacts from fetch stage
COPY --from=fetch-stage /tmp/libtorrent_src /tmp/libtorrent_src

# set workdir
WORKDIR /tmp/libtorrent_src

# install build packages
RUN \
	set -ex \
	&& apk add --no-cache \
	alpine-sdk \
	boost-dev \
	cmake \
	linux-headers \
	openssl-dev \
	py3-setuptools \
	python3-dev \
	samurai

# build libtorrent package
RUN \
	cmake -B build -G Ninja \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_CXX_STANDARD=17 \
		-DCMAKE_VERBOSE_MAKEFILE=ON \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-Dbuild_tests="$(want_check && echo ON || echo OFF)" \
		-Dpython-bindings=ON \
		-Dpython-egg-info=ON \
	&& cmake --build build

# install libtorrent package
RUN \
	DESTDIR=/build/libtorrent cmake --install build
