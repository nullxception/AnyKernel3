#!/bin/bash
#
# Simple script for packing chaldea kernel for android
#
SELFPATH=$(dirname $(realpath $0))
REL_SELFPATH=$(realpath --relative-to=. $SELFPATH)

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
datename=$(date +%B-%d |  tr '[:upper:]' '[:lower:]')
zipname=${kernelid// /-}-$devicename-$kernelver-$datename.zip

prepare_ak3_metadata(){
  sed -i "s|.*fstab.*$||;
          s|.*init.*rc.*$||;
          s|.*_perm.*amdis.*$||;
          s|^block=.*$|block=$deviceboot|;
          s|^device\.\(.*\)=.*$|device.\1=|;
          s|^kernel\.string=.*$|kernel.string=$kerneldesc|;
          s|#.*$||; s|\;$||; /^$/d;" $1

  num=0
  for device in ${deviceids[@]};do
    num=$(($num+1))
    sed -i "s|^device\.name$num=.*$|device.name$num=$device|" $1
  done
}

prepare_ak3_installer() {
  sed -i 's|\s"\s"| |g;s|ui_print \" \"\;||;' $1
}

flash_from_rec() {
  echo ":: Waiting the recovery..."
  adb wait-for-recovery
  echo ":: Begin installation..."
  adb push $REL_SELFPATH/$zipname /cache/kernel.zip
  adb shell "twrp install /cache/kernel.zip; rm /cache/kernel.zip"
  read -p ":: reboot the device ? (y/n) > " ASKREBOOT
  [[ $ASKREBOOT =~ ^[Yy]$ ]] && adb reboot
}

push_to_device() {
  read -p ":: Push $zipname to /sdcard/ ? (y/n) > " ASKPUSH
  [[ $ASKPUSH =~ ^[Yy]$ ]] && adb push $SELFPATH/$zipname /sdcard/

  read -p ":: Flash from recovery ? (y/n) > " ASKREC
  if [[ $ASKREC =~ ^[Yy]$ ]]; then
    echo ":: Rebooting to recovery..."
    adb reboot recovery
    flash_from_rec
  fi
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
    prepare_ak3_installer META-INF/com/google/android/update-binary
    prepare_ak3_installer tools/ak3-core.sh
    prepare_ak3_metadata anykernel.sh
    zip -r9 -q --exclude=*placeholder $WORKDIR/$zipname *
  command popd > /dev/null

  find $SELFPATH -iname "*$devicename-$kernelver*" -delete
  # copy generated zip file to ak3 dir
  cp -f $WORKDIR/$zipname $SELFPATH/

  # cleanup working directory
  rm -rf $WORKDIR
  echo "done, your package are located at : $REL_SELFPATH/$zipname"

  push_to_device
}

main $@
