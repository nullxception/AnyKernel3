#!/bin/bash
#
# Simple script for packing chaldea kernel for android
#
SELFPATH=$(dirname $(realpath $0))

[[ -f "$SELFPATH/buildzip.conf" ]] || { echo "missing buildzip.conf. exiting"; exit 1; }
. $SELFPATH/buildzip.conf

# KBUILD_OUT, used to get kernel, dtbo file, and version directly from it
[[ -f "$KBUILD_OUT/include/generated/utsrelease.h" ]] || { echo "missing $KBUILD_OUT. exiting"; exit 1; }

# get kernel and dtbo directly from KBUILD_OUT
src_kernel=$KBUILD_OUT/arch/arm64/boot/Image.gz-dtb
src_dtbo=$KBUILD_OUT/arch/arm64/boot/dtbo.img

# Requirement checking
[[ -f "$src_kernel" ]] || { echo "src_kernel ($src_kernel) cannot be found. exiting"; exit 1; }
[[ -f "$src_dtbo" ]] || { echo "src_dtbo ($src_dtbo) cannot be found. exiting"; exit 1; }

# Setup file zip name
kernelver=$(cat $KBUILD_OUT/include/generated/utsrelease.h | cut -d\" -f2 | cut -d\- -f3-)
zipname=${kernelid// /-}-$devicename-$kernelver.zip

ak3-filldevices() {
  num=0
  sed -i 's/^device\.\(.*\)=.*$/device.\1=/' anykernel.sh
  for device in ${deviceids[@]};do
    num=$(($num+1))
    sed -i "s|^device\.name$num=.*$|device.name$num=$device|" anykernel.sh
  done
}

ak3-makedata(){
  sed -i 's/#.*$//;s/.*init.*rc.*$//;s/.*fstab.*$//;s/.*_perm.*amdis.*$//;s/\;$//;/^$/d' anykernel.sh
  sed -i "s|^block=.*$|block=$deviceboot|;s|^kernel\.string=.*$|kernel.string=$kerneldesc|" anykernel.sh
  ak3-filldevices
}

ak3-stripinstaller() {
  sed -i 's|\s"\s"| |g;s/ui_print \" \"\;//;' $1
}

main() {
  echo "building $zipname..."

  # Setup folder and files that will be included in the zip
  sources=($SELFPATH/META-INF
          $SELFPATH/tools
          $SELFPATH/anykernel.sh
          $SELFPATH/banner
          $src_kernel
          $src_dtbo)

  # prepare working directory in the /tmp
  WORKDIR=/tmp/build-$kernelid-$USER
  rm -rf $WORKDIR
  mkdir $WORKDIR

  # copy needed files
  for file in "${sources[@]}"; do
      (test -f $file || test -d $file) && cp -af $file $WORKDIR/
  done

  # creating zip file
  command pushd "$WORKDIR" > /dev/null
    ak3-stripinstaller META-INF/com/google/android/update-binary
    ak3-stripinstaller tools/ak3-core.sh
    ak3-makedata
    zip -r9 -q --exclude=*placeholder $WORKDIR/$zipname *
  command popd > /dev/null

  # copy generated zip file to ak3 dir
  cp -f $WORKDIR/$zipname $SELFPATH/

  # cleanup working directory
  # rm -rf $WORKDIR
  echo "done, your package are located at :"
  realpath --relative-to=. $SELFPATH/$zipname
}

main $@
