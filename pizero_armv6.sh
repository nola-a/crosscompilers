#!/bin/sh

# Raspberry Pi Zero armv6 cross compiler (can easily be modified to support other targets)

# Useful links
# http://preshing.com/20141119/how-to-build-a-gcc-cross-compiler/
# https://www.raspberrypi.org/documentation/linux/kernel/building.md
# http://www.ifp.illinois.edu/~nakazato/tips/xgcc.html

# NOTE
# if the target runtime is too old and you want to use the latest version of GCC
# running an executable (a.out) built with this compiler could raise the following error:
#./a.out: /usr/lib/arm-linux-gnueabihf/libstdc++.so.6: version `GLIBCXX_3.4.32' not found (required by ./a.out)
# this issue could be solved static linking stdc++ and libgcc with the options -static-libstd -static-libgcc 
# To reduce the size of the executable more options can be used:
# $ /opt/pi-gcc-armv6/bin/arm-linux-gnueabihf-g++ -s -fdata-sections -ffunction-sections -static-libstdc++ -static-libgcc main.cpp -o a.out -Wl,--gc-sections

BINUTILS=2.30
GCC=13.2.0
GLIBC=2.28
CROSSC=/opt/pi-gcc-armv6

echo "Install dependecies"
sudo apt install build-essential gawk git texinfo bison rsync

echo "Download software"
wget https://ftpmirror.gnu.org/binutils/binutils-$BINUTILS.tar.bz2
wget https://ftpmirror.gnu.org/gcc/gcc-$GCC/gcc-$GCC.tar.gz
wget https://ftpmirror.gnu.org/glibc/glibc-$GLIBC.tar.bz2
git clone -b rpi-5.4.y --single-branch  --depth=1 https://github.com/raspberrypi/linux

echo "Extract archives"
tar xf binutils-$BINUTILS.tar.bz2
tar xf glibc-$GLIBC.tar.bz2
tar xf gcc-$GCC.tar.gz
rm *.tar.*

echo "Download GCC deps"
cd gcc-*
contrib/download_prerequisites
rm *.tar.*
cd ..

echo "Fixing limits.h for PATH_MAX"
for i in $(find . -name limits.h);
do 
	echo "Patching $i"
	cat <<EOF >> $i
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
EOF
done;
find gcc-$GCC/libsanitizer -type f -exec sed -i 's/<limits.h>/<linux\/limits.h>/g' {} \;

echo "Create cross compiler folder"
sudo rm -rf $CROSSC
sudo mkdir -p $CROSSC
sudo chown $(whoami) $CROSSC
export PATH=$CROSSC/bin:$PATH

echo "Build binutils"
mkdir build-binutils && cd build-binutils
../binutils-$BINUTILS/configure --prefix=$CROSSC --target=arm-linux-gnueabihf --with-arch=armv6 --with-fpu=vfp --with-float=hard --disable-multilib
make -j 8
make install
cd ..

echo "Install kernel headers"
cd linux
KERNEL=kernel7
make ARCH=arm INSTALL_HDR_PATH=$CROSSC/arm-linux-gnueabihf headers_install

echo "Build compilers"
cd ..
mkdir build-gcc && cd build-gcc
../gcc-$GCC/configure --prefix=$CROSSC --target=arm-linux-gnueabihf --enable-languages=c,c++,fortran --with-arch=armv6 --with-fpu=vfp --with-float=hard --disable-multilib
make -j8 all-gcc
make install-gcc

echo "Build glibc #1"
cd ..
mkdir build-glibc && cd build-glibc
../glibc-$GLIBC/configure --prefix=$CROSSC/arm-linux-gnueabihf --build=$MACHTYPE --host=arm-linux-gnueabihf --target=arm-linux-gnueabihf --with-arch=armv6 --with-fpu=vfp --with-float=hard --with-headers=$CROSSC/arm-linux-gnueabihf/include --disable-multilib libc_cv_forced_unwind=yes --disable-werror
make install-bootstrap-headers=yes install-headers
make -j8 csu/subdir_lib
install csu/crt1.o csu/crti.o csu/crtn.o $CROSSC/arm-linux-gnueabihf/lib
arm-linux-gnueabihf-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o $CROSSC/arm-linux-gnueabihf/lib/libc.so
touch $CROSSC/arm-linux-gnueabihf/include/gnu/stubs.h

echo "Build libgcc"
cd ..
cd build-gcc
make -j8 all-target-libgcc
make install-target-libgcc

echo "Build glibc #2"
cd ..
cd build-glibc
make -j8
make install

echo "Build all GCC"
cd ..
cd build-gcc
make -j8
make install
cd ..

