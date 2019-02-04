ARG ALPINE_VER="edge"
FROM alpine:${ALPINE_VER} as fetch-stage

############## fetch stage ##############

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
		"https://dl.bintray.com/boostorg/release/${BOOST_VER}/source/boost_${BOOST_VER_1}.tar.bz2" \
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

############## boost build stage ##############

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

FROM alpine:${ALPINE_VER} as libtorrent_build-stage

############## libtorrent build  stage ##############

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

FROM alpine:${ALPINE_VER} as deluge_build-stage

############## deluge build  stage ##############

# copy artifacts from fetch and libtorrent build stages
COPY --from=fetch-stage /src/deluge /src/deluge
COPY --from=libtorrent_build-stage /build/libtorrent /build/libtorrent

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

FROM alpine:${ALPINE_VER} as pip-stage

# install build packages
RUN \
	apk add --no-cache \
		g++ \
		libffi-dev \
		make \
		openssl-dev \
		py2-pip \
		python-dev

# install pip packages
RUN \
	set -ex \
	&& pip install --no-cache-dir -U \
		chardet \
		enum \
		mako \
		pyOpenSSL \
		pyxdg \
		resources \
		service_identity \
		twisted \
		zope.interface

FROM alpine:${ALPINE_VER} as strip-stage

############## strip packages stage ##############

# copy artifacts build stages
COPY --from=boost_build-stage /build/boost/lib  /build/all/usr/lib/
COPY --from=deluge_build-stage /build/deluge/usr/ /build/all/usr/
COPY --from=libtorrent_build-stage /build/libtorrent/usr/ /build/all/usr/
COPY --from=pip-stage /usr/lib/python2.7/site-packages /build/all/usr/lib/python2.7/site-packages

# install strip packages
RUN \
	apk add --no-cache \
		binutils

# strip packages
RUN \
	set -ex \
	&& for dirs in usr/bin bin usr/lib lib usr/sbin sbin usr/lib/python2.7/site-packages; \
	do \
		find /build/all/$dirs -type f | \
		while read -r files ; do strip ${files} || true \
		; done \
	; done

# remove unneeded files
RUN \	
	set -ex \
	&& for cleanfiles in deluge-console deluge-gtk *.la *.pyc *.pyo; \
	do \
	find /build/all/ -iname "${cleanfiles}" -exec rm -vf '{}' + \
	; done

# remove uneeded folders
RUN \
	set -ex \
	&& rm -rvf \
		/build/all/usr/include \
		/build/all/usr/lib/pkgconfig \
		/build/all/usr/share/applications \
		/build/all/usr/share/icons \
		/build/all/usr/share/man \
		/build/all/usr/share/pixmaps \
 		/build/all/usr/lib/python*/site-packages/deluge/share/pixmaps \
		/build/all/usr/lib/python*/site-packages/deluge/share/man \
		/build/all/usr/lib/python*/site-packages/deluge/ui/gtkui \
		/build/all/usr/lib/python*/site-packages/deluge/ui/console

FROM lsiobase/alpine:${ALPINE_VER}

############## runtime stage ##############

# copy artifacts strip stage
COPY --from=strip-stage /build/all/usr/  /usr/

# environment variables
ENV PYTHON_EGG_CACHE="/config/plugins/.python-eggs"

# install runtime packages
RUN \	
	apk add --no-cache \
		libstdc++ \
		py2-setuptools \
		python

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8112 58846 58946 58946/udp
VOLUME /config /downloads
