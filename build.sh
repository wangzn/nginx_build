#!/bin/bash

debugf() {
	echo -en "\033[32m[DEBUG] $1\033[0m\n"
}

errorf() {
	echo -en "\033[31m[ERROR] $1\033[0m\n"
	exit 1
}


basic_install() {
	apt-get update
	apt-get -y install git libxml2 libxml2-dev libxslt-dev libgd-dev libgeoip-dev
	[ $? ] || errorf "basic install error"
	debugf "basic package installed"
}

install_luajit() {
	#git clone https://github.com/LuaJIT/LuaJIT.git
	git_clone "github.com/LuaJIT/LuaJIT.git"
	cd LuaJIT; make && make install
	[ $? ] || errorf "install luajit error" 
	cd ..;
}

endwith() {
        [ $# -lt 2 ] && exit 1
        echo $1 | grep -qE "$2$"
	return $?
}

dl() {
	[ $# -lt 2 ] && exit 1
        file=`basename $2`
	if [ "$uselocal" == "true" ] && [ -f "$localrepo/$file" ]; then
		debugf "Download $1 to $file with local repo"
		cp $localrepo/$file $file
	else
		debugf "Download $1 to $file with remote url"
		wget $1 -O $file
	fi
}

git_clone() {
	[ $# -lt 1 ] && exit 1
	dir=`basename $1 | sed s/\.git//g`
	if [ "$uselocal" == "true" ] && [ -d "$localrepo/git/$dir" ]; then
		debugf "git clone $m with local repo"
		cp -r $localrepo/git/$dir $dir
	else
		debugf "git clone $m with remote git"
		git clone "https://$1"
	fi
}

download() {
        mkdir -p "download"
        cd "download"
	dl "${nginx_url}/${nginx_file}" ${nginx_file}
	dl "${pcre_url}/${pcre_file}" ${pcre_file}
	dl "${zlib_url}/${zlib_file}" ${zlib_file}
	dl "${openssl_url}/${openssl_file}" ${openssl_file}
        cd ..
        for m in `echo $addons` ; do
            #debugf "git clone $m"
            #git clone "https://$m"
		git_clone $m
        done
}

extract() {
    for f in `ls ./download/`; do
	endwith $f ".tar.gz"
        [ $? ] && tar -xzvf "download/$f" && continue
	endwith $f ".tar"
        [ $? ] && tar -xvf "download/$f" && continue
	endwith $f ".zip"
        [ $? ] && unzip "download/$f" && continue
    done
}

addon_modules() {
        ret=""
	for m in `echo $addons`; do
			ret="${ret} --add-module=../`basename $m | sed s/\.git//g`/"
        done
	echo "$ret"
}

build() {
cd "nginx-${nginx_ver}"
addons_module=`addon_modules`

debugf "addon modules: $addons_module"

./configure --with-cc-opt='-g -O2 -fstack-protector --param=ssp-buffer-size=4 -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2' --with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro' \
--prefix=${nginx_prefix:-/usr/local/nginx} \
--lock-path=/var/lock/nginx.lock \
--pid-path=${nginx_prefix}/nginx.pid \
--http-client-body-temp-path=${nginx_prefix}/temp/body \
--http-fastcgi-temp-path=${nginx_prefix}/temp/fastcgi \
--http-proxy-temp-path=${nginx_prefix}/temp/proxy \
--http-scgi-temp-path=${nginx_prefix}/temp/scgi \
--http-uwsgi-temp-path=${nginx_prefix}/uwsgi \
--with-debug --with-pcre-jit --with-ipv6 \
--with-http_ssl_module \
--with-http_stub_status_module \
--with-http_realip_module \
--with-http_addition_module \
--with-http_dav_module \
--with-http_geoip_module \
--with-http_gzip_static_module \
--with-http_image_filter_module \
--with-http_spdy_module \
--with-http_sub_module \
--with-http_xslt_module \
--with-mail \
--with-mail_ssl_module \
--with-pcre=../pcre-${pcre_ver}/ \
--with-openssl=../openssl-${openssl_ver}/ \
--with-zlib=../zlib-${zlib_ver}/ \
${addons_module}

make && make install

}

run() {
	#basic_install
	install_luajit
	download
	extract
	build
}

source $PWD/conf.ini

export LUAJIT_LIB=${luajit_lib_dir:-/usr/local/lib}
export LUAJIT_INC=${luajit_inc_dir:-/usr/local/include/luajit-2.0}

nginx_file="nginx-${nginx_ver:-1.8.1}.tar.gz"
pcre_file="${pcre_ver}/pcre-${pcre_ver:-8.38}.zip"
zlib_file="zlib-${zlib_ver:-1.2.8}.tar.gz"
openssl_file="openssl-${openssl_ver}.tar.gz"


if [ ${mode:-PROD} == "DEBUG" ] ; then
	build_dir="build_debug"
else
	ts=`date +%Y%m%d_%H%M%S`
	build_dir="build_$ts"
fi

build_dir="${build_home_dir:-.}/${build_dir}"

mkdir -p $build_dir
cd ${build_dir}

run
