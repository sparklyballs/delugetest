ARG ALPINE_VER="3.12"
FROM alpine:${ALPINE_VER} as fetch-stage

############## fetch stage ##############

# install fetch packages
RUN \
	apk add --no-cache \
		bash \
		curl \
		xz

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
		/source/rasterbar \
		/source/deluge \
	&& curl -o \
	/tmp/rasterbar.tar.gz	-L \
		"https://github.com/arvidn/libtorrent/releases/download/libtorrent-${LIBTORRENT_RELEASE}/libtorrent-rasterbar-${LIBTORRENT_RELEASE}.tar.gz" \
	&& tar xf \
	/tmp/rasterbar.tar.gz -C \
	/source/rasterbar --strip-components=1 \
	&& curl -o \
	/tmp/deluge.tar.xz -L \
		"http://download.deluge-torrent.org/source/${DELUGE_RELEASE%.*}/deluge-${DELUGE_RELEASE}.tar.xz" \
	&& tar xf \
	/tmp/deluge.tar.xz -C \
	/source/deluge --strip-components=1

FROM alpine:${ALPINE_VER} as packages-stage

############## packages stage ##############

# install build packages
RUN \
	apk add --no-cache \
		boost-dev \
		freetype-dev \
		g++ \
		gcc \
		git \
		lcms2-dev \
		libffi-dev \
		libimagequant-dev \
		libjpeg-turbo-dev \
		libpng-dev \
		libwebp-dev \
		libxcb-dev \
		make \
		openjpeg-dev \
		openssl-dev \
		py3-pip \
		python3-dev \
		tiff-dev \
		zlib-dev

FROM packages-stage as rasterbar-build-stage

############## rasterbar build stage ##############

# add artifacts from source stage
COPY --from=fetch-stage /source /source

# set workdir
WORKDIR /source/rasterbar

# build rasterbar
RUN \
	set -ex \
	&& ./configure \
		--enable-python-binding \
		--enable-tests \
		--localstatedir=/var \
		--mandir=/usr/share/man \
		--prefix=/usr \
		--sysconfdir=/etc \
		--with-boost-system=python3.8 \
	&& make -j4 \
	&& make DESTDIR=/output/rasterbar install

FROM packages-stage as pip-stage

############## pip stage ##############

# install pip and python packages
RUN \
	pip3 install -U \
		pip \
		wheel

RUN \
	apk add --no-cache \
		py3-cairo \
		py3-gobject3 \
		py3-openssl \
		py3-xdg \
	&& pip3 install -U \
		asn1 \
		chardet \
		hyperlink \
		mako \
		markupsafe \
		pillow \
		pyhamcrest \
		rencode \
		service-identity \
		setproctitle \
		setuptools \
		six \
		slimit \
		twisted \
		zope-interface

FROM packages-stage as deluge-build-stage

############## deluge stage ##############
	
# add patch and artifacts from fetch and rasterbar stages
COPY --from=fetch-stage /source /source
COPY --from=pip-stage /usr/lib/python3.8/site-packages /usr/lib/python3.8/site-packages
COPY --from=rasterbar-build-stage /output/rasterbar/usr /usr
COPY patches /patches

# set workdir
WORKDIR /source/deluge


# build app
RUN \
	set -ex \
	&& git apply /patches/logging.patch \
	&& git apply /patches/locale.patch \
	&& python3 setup.py \
		build \
	&& python3 setup.py \
		install \
		--prefix=/usr \
		--root="/builds/deluge"

FROM alpine:${ALPINE_VER} as strip-stage

############## strip stage ##############

# add artifacts from deluge, pip and rasterbar stages
COPY --from=deluge-build-stage /builds/deluge/usr /builds/usr
COPY --from=pip-stage /usr/lib/python3.8/site-packages /usr/lib/python3.8/site-packages
COPY --from=rasterbar-build-stage /output/rasterbar/usr /builds/usr

# install strip packages
RUN \
	apk add --no-cache \
		bash \
		binutils

# set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# strip pip packages
RUN \
	set -ex \
	&& find /usr/lib/python3.8/site-packages -type f | \
		while read -r files ; \
		do strip "${files}" || true \
	; done

# strip packages
RUN \
	set -ex \
	&& for dirs in /usr/bin /usr/lib /usr/include /usr/share; \
	do \
		find /builds/"${dirs}" -type f | \
		while read -r files ; do strip "${files}" || true \
		; done \
	; done

# remove unneeded files
RUN \	
	set -ex \
	&& for cleanfiles in *.la *.pyc *.pyo; \
	do \
	find /usr/lib/python3.8/site-packages -iname "${cleanfiles}" -exec rm -vf '{}' + \
	; done

FROM sparklyballs/alpine-test:${ALPINE_VER}

############## runtime stage ##############

# add unrar
# sourced from self builds here:- 
# https://ci.sparklyballs.com:9443/job/App-Builds/job/unrar-build/
# builds will fail unless you download a copy of the build artifacts and place in a folder called build
ADD /build/unrar-*.tar.gz /usr/bin/

# add artifacts from strip stage
COPY --from=strip-stage /usr/lib/python3.8/site-packages /usr/lib/python3.8/site-packages
COPY --from=strip-stage /builds/usr /usr

# environment settings
ENV PYTHON_EGG_CACHE="/config/plugins/.python-eggs"

# install packages
RUN \
	apk add --no-cache \
		boost-python3 \
#		freetype \
#		gettext \
#		lcms2 \
		libffi \
#		libimagequant \
#		libjpeg-turbo \
#		libpng \
#		libstdc++ \
#		libwebp \
#		libxcb \
#		openjpeg \
		p7zip \
#		py3-cairo \
#		py3-gobject3 \
#		py3-openssl \
#		tiff \
		unzip

# add local files
COPY root/ /
COPY GeoIP.dat /usr/share/GeoIP/GeoIP.dat

# ports and volumes
EXPOSE 8112 58846 58946 58946/udp
VOLUME /config /downloads
