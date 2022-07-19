ARG ALPINE_VER="3.16"
FROM alpine:${ALPINE_VER} as fetch-stage

############## fetch stage ##############

# install fetch packages
RUN \
	apk add --no-cache \
		bash \
		curl \
		git

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
	&& curl -o \
	/tmp/rasterbar.tar.gz -L \
	"https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_RELEASE}/libtorrent-rasterbar-${LIBTORRENT_RELEASE}.tar.gz" \
	&& tar xf \
	/tmp/rasterbar.tar.gz -C \
	/source/rasterbar --strip-components=1 \
	&& git clone -b "deluge-${DELUGE_RELEASE}" git://deluge-torrent.org/deluge.git \
		/source/deluge

FROM alpine:${ALPINE_VER} as packages-stage

############## packages stage ##############

# install build packages
RUN \
	apk add --no-cache \
		boost-dev \
		ca-certificates \
		cargo \
		cmake \
		curl \
		g++ \
		git \
		libffi-dev \
		libjpeg-turbo-dev \
		linux-headers \
		musl-dev \
		openssl-dev \
		py3-pip \
		py3-setuptools \
		python3-dev \
		samurai \
		tzdata \
		zlib-dev

FROM packages-stage as rasterbar-stage

############## rasterbar build stage ##############

# add artifacts from source stage
COPY --from=fetch-stage /source /source

# set workdir
WORKDIR /source/rasterbar

# build rasterbar
RUN \
	set -ex \
	&& cmake \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX="/usr" \
		-DCMAKE_INSTALL_LIBDIR="lib" \
		-Dpython-bindings=ON \
		-Dboost-python-module-name="python" \
		-Dpython-egg-info=ON \
		-GNinja . \
	&& ninja \
	&& DESTDIR=/build ninja install

FROM packages-stage as deluge-stage

############## deluge_build stage  ##############

# add artifacts from fetch and rasterbar stages
COPY --from=fetch-stage /source/deluge /source/deluge
COPY --from=rasterbar-stage /build/usr /usr

WORKDIR /source/deluge

# install pip packages
RUN \
	pip3 install --no-cache-dir -U \
		pip \
		wheel \
	&& pip3 install --no-cache-dir -U \
		-r requirements.txt \
		-t /build/usr/lib/python3.10/site-packages

# install deluge
RUN \
	python3 setup.py build \
	&& python3 setup.py \
		install \
		--prefix=/usr \
		--root="/build"

FROM alpine:${ALPINE_VER} as strip-stage

############## strip stage ##############

# add artifacts from deluge, pip and rasterbar stages
COPY --from=deluge-stage /build/usr /build/usr
COPY --from=deluge-stage /build/usr/lib/python3.10/site-packages /build/usr/lib/python3.10/site-packages
COPY --from=rasterbar-stage /build/usr /build/usr

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
	&& find /build/usr/lib/python3.10/site-packages -type f | \
		while read -r files ; \
		do strip "${files}" || true \
	; done

# strip packages
RUN \
	set -ex \
	&& for dirs in /usr/bin /usr/lib /usr/include /usr/share; \
	do \
		find /build/"${dirs}" -type f | \
		while read -r files ; do strip "${files}" || true \
		; done \
	; done

# remove unneeded files
RUN \	
	set -ex \
	&& for cleanfiles in *.la *.pyc *.pyo; \
	do \
	find /build/usr/lib/python3.10/site-packages -iname "${cleanfiles}" -exec rm -vf '{}' + \
	; done


FROM sparklyballs/alpine-test:${ALPINE_VER}

############## runtime stage ##############

# add unrar and GeoIP.dat
# builds will fail unless you download a copy of the build artifacts and place in a folder called build
# sourced from the relevant builds here https://ci.sparklyballs.com/job/App-Builds/

ADD /build/unrar-*.tar.gz /usr/bin/
ADD /build/GeoIP.dat /usr/share/GeoIP/GeoIP.dat

# add artifacts from strip stage
COPY --from=strip-stage /build/usr /usr

# environment settings
ENV PYTHON_EGG_CACHE="/config/plugins/.python-eggs"

# runtime packages
RUN \
	apk add --no-cache \
		bash \
		boost1.78-python3 \
		geoip \
		libffi \
		p7zip \
		python3 \
		unzip

# add local files
COPY root/ /

# ports and volumes
EXPOSE 8112 58846 58946 58946/udp
VOLUME /config /downloads
