ARG ALPINE_VER="edge"
FROM alpine:${ALPINE_VER} as fetch-stage

# package versions
ARG BOOST_VER="1.67.0"
ARG DELUGE_VER="1.3.15"
ARG LIBTORRENT_VER="1.1.12"

# install fetch packages
RUN \
	apk add --no-cache \
		bzip2 \
		curl \
		tar

# fetch source code
RUN \
	set -ex \
	&& BOOST_VER_1="${BOOST_VER//[.]/_}" \
	&& LIBTORRENT_VER_1="${LIBTORRENT_VER//[.]/_}" \
	&& curl -o \
	/tmp/boost.tar.bz2 -L \
		"http://downloads.sourceforge.net/project/boost/boost/${BOOST_VER}/boost_${BOOST_VER_1}.tar.bz2" \
	&& curl -o \
	/tmp/deluge.tar.bz2 -L \
		"http://download.deluge-torrent.org/source/deluge-${DELUGE_VER}.tar.bz2" \
	&& curl -o \
	/tmp/libtorrent.tar.gz -L \
		"https://github.com/arvidn/libtorrent/releases/download/libtorrent_${LIBTORRENT_VER_1}/libtorrent-rasterbar-${LIBTORRENT_VER}.tar.gz"

# extract source code
RUN \
	set -ex \
	&& mkdir -p \
		/src/boost \
		/src/deluge \
		/src/libtorrent \
	&& tar xf \
	/tmp/boost.tar.bz2 -C \
	/src/boost --strip-components=1 \
	&& tar xf \
	/tmp/deluge.tar.bz2 -C \
	/src/deluge --strip-components=1 \
	&& tar xf \
	/tmp/libtorrent.tar.gz -C \
	/src/libtorrent --strip-components=1

FROM alpine:${ALPINE_VER} as boost_build-stage

# copy artifacts from fetch stage
COPY --from=fetch-stage /src/boost /src/boost

# install build packages
RUN \
	apk add --no-cache \
		bison \
		bzip2-dev \
		file \
		flex \
		g++ \
		linux-headers \
		make \
		python-dev \
		zlib-dev

# build package
RUN \
	set -ex \
	&& cd /src/boost \
	&& sh bootstrap.sh \
			--with-icu \
			--with-libraries=chrono,random,system,python \
			--with-python-version=2.7 \
			--with-toolset=gcc \
	&& ./b2 \
			variant=release \
			link=shared \
			threading=single \
			runtime-link=shared \
			--prefix=/build/boost \
			--layout=system \
			install

# strip package
RUN \
	set -ex \
	&& for dirs in usr/bin bin usr/lib lib usr/sbin sbin ; \
	do \
		find /build/boost/$dirs -type f | \
		while read -r files ; do strip ${files} 2>/dev/null || true \
		; done \
	; done

FROM alpine:${ALPINE_VER} as libtorrent_build-stage

# copy artifacts from fetch and boost build stages
COPY --from=fetch-stage /src/libtorrent /src/libtorrent
COPY --from=boost_build-stage /build/boost /build/boost

# build environment variables 
ARG BOOST_LDFLAGS="-L/build/boost/lib"
ARG BOOST_CPPFLAGS="-I/build/boost/include"

# install build packages
RUN \
	apk add --no-cache \
		file \
		g++ \
		linux-headers \
		make \
		openssl-dev \
		python-dev

# build package
RUN \
	set -ex \
	&& cd /src/libtorrent \
	&& ./configure \
		--disable-static \
	--enable-python-binding \
	--enable-shared \
	--prefix=/usr \
	&& make DESTDIR=/build/libtorrent install \
	&& make -C bindings/python DESTDIR=/build/libtorrent install

# strip package
RUN \
	set -ex \
	&& for dirs in usr/bin bin usr/lib lib usr/sbin sbin ; \
	do \
		find /build/libtorrent/$dirs -type f | \
		while read -r files ; do strip ${files} 2>/dev/null || true \
		; done \
	; done

FROM alpine:${ALPINE_VER} as deluge_build-stage

# copy artifacts from fetch and libtorrent build stages
COPY --from=fetch-stage /src/deluge /src/deluge
COPY --from=libtorrent_build-stage /build/libtorrent /build/libtorrent

# build environment variables 
ARG BOOST_LDFLAGS="-L/build/boost/lib"
ARG BOOST_CPPFLAGS="-I/build/boost/include"

# install build packages
RUN \
	apk add --no-cache \
		bash \
		g++ \
		intltool \
		librsvg-dev \
		make \
		openssl-dev \
		py2-pip \
		python-dev

# build pacakge
RUN \
	set -ex \
	&& cd /src/deluge \
	&& python -B setup.py install \
		--no-compile \
		--prefix=/usr \
		--root=/build/deluge

# strip package
RUN \
	set -ex \
	&& for dirs in usr/bin bin usr/lib lib usr/sbin sbin ; \
	do \
		find /build/deluge/$dirs -type f | \
		while read -r files ; do strip ${files} 2>/dev/null || true \
		; done \
	; done

FROM lsiobase/alpine:${ALPINE_VER}

# copy artifacts build stages
COPY --from=boost_build-stage /build/boost/lib  /usr/lib/
COPY --from=deluge_build-stage /build/deluge/usr/ /usr/
COPY --from=libtorrent_build-stage /build/libtorrent/usr/ /usr/

# environment variables
ENV PYTHON_EGG_CACHE="/config/plugins/.python-eggs"

# install build packages
RUN \
	apk add --no-cache --virtual=build-dependencies \
		g++ \
		libffi-dev \
		make \
		openssl-dev \
		py2-pip \
		python-dev \
	\
# install pip packages
	\
	&& pip install --no-cache-dir -U \
		chardet \
		enum \
		mako \
		pyOpenSSL \
		pyxdg \
		resources \
		service_identity \
		twisted \
		zope.interface \
	\
# uninstall build packages
	\
	&& apk del \
		build-dependencies \
	\
# install runtime packages
	\
	&& apk add --no-cache \
		libstdc++ \
		py2-setuptools \
		python \
# cleanup
	\
	&& rm -rf \
		/tmp/* \
		/root \
	&& mkdir -p \
		/root

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8112 58846 58946 58946/udp
VOLUME /config /downloads
