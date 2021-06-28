#!/bin/bash
#
# Simple script for packing chaldea kernel for android
#
SELFPATH=$(dirname $(realpath $0))
REL_SELFPATH=$(realpath --relative-to=. $SELFPATH)

if [[ "$1" == "--auto" ]]; then
  flashmode=auto
fi

[[ -f "$SELFPATH/buildzip.conf" ]] || { echo "missing buildzip.conf. exiting"; exit 1; }
. $SELFPATH/buildzip.conf

# KBUILD_OUT, used to get kernel, dtbo file, and version directly from it
[[ -f "$KBUILD_OUT/include/generated/utsrelease.h" ]] || { echo "missing $KBUILD_OUT. exiting"; exit 1; }

# get kernel directly from KBUILD_OUT
if [[ "$appended_dtb" == "true" ]]; then
  src_kernel=$KBUILD_OUT/arch/arm64/boot/Image.gz-dtb
else
  src_kernel=$KBUILD_OUT/arch/arm64/boot/Image.gz
fi
[[ -f "$src_kernel" ]] || { echo "src_kernel ($src_kernel) cannot be found. exiting"; exit 1; }

# get dtbo directly from KBUILD_OUT
if [[ "$with_dtbo" == "true" ]]; then
  src_dtbo=$KBUILD_OUT/arch/arm64/boot/dtbo.img
  [[ -f "$src_dtbo" ]] || { echo "src_dtbo ($src_dtbo) cannot be found. exiting"; exit 1; }
fi

# Setup file zip name
kernelver=$(cat $KBUILD_OUT/include/generated/utsrelease.h | cut -d\" -f2 | cut -d\- -f3-)
datename=$(date +%B-%d |  tr '[:upper:]' '[:lower:]')
zipname=${kernelid// /-}-$devicename-$kernelver-$datename.zip

create_dtb() {
  target=$1
  source_dtbs=$KBUILD_OUT/arch/arm64/boot/dts

  if [[ -f "$target" ]]; then
    # clean up it first
    rm $target
  fi
  find $source_dtbs -iname '*.dtb' | while read dt; do
    cat $dt >> $target
  done
}

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
  if [[ "$flashmode" == "auto" ]]; then
      echo ":: Rebooting to recovery..."
      adb reboot recovery
      echo ":: Waiting the recovery..."
      adb wait-for-recovery
      echo ":: Begin installation..."
      adb push $REL_SELFPATH/$zipname /cache/kernel.zip
      adb shell "twrp install /cache/kernel.zip; rm /cache/kernel.zip"
      adb reboot
  else
    read -p ":: Flash from recovery ? (y/n) > " ASKREC
    if [[ $ASKREC =~ ^[Yy]$ ]]; then
      echo ":: Rebooting to recovery..."
      adb reboot recovery
    fi

    echo ":: Waiting the recovery..."
    adb wait-for-recovery
    echo ":: Begin installation..."
    adb push $REL_SELFPATH/$zipname /cache/kernel.zip
    adb shell "twrp install /cache/kernel.zip; rm /cache/kernel.zip"
    read -p ":: reboot the device ? (y/n) > " ASKREBOOT
    [[ $ASKREBOOT =~ ^[Yy]$ ]] && adb reboot
  fi
}

push_to_device() {
  if [[ "$flashmode" == "auto" ]]; then
    adb push $SELFPATH/$zipname /sdcard/
  else
    read -p ":: Push $zipname to /sdcard/ ? (y/n) > " ASKPUSH
    [[ $ASKPUSH =~ ^[Yy]$ ]] && adb push $SELFPATH/$zipname /sdcard/
  fi
}

mode_autoflash() {
  adb push $SELFPATH/$zipname /sdcard/
  echo ":: Rebooting to recovery..."
  adb reboot recovery
  echo ":: Waiting the recovery..."
  adb wait-for-recovery
  echo ":: Begin installation..."
  adb push $REL_SELFPATH/$zipname /cache/kernel.zip
  adb shell "twrp install /cache/kernel.zip; rm /cache/kernel.zip"
  adb reboot
}

main() {
  echo "building $zipname..."

  # Setup folder and files that will be included in the zip
  sources=($SELFPATH/META-INF
          $SELFPATH/tools
          $SELFPATH/anykernel.sh
          $SELFPATH/banner
          $src_kernel)

  if [[ "$with_dtbo" == "true" ]]; then
    sources+=($src_dtbo)
  fi

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
    if [[ "$appended_dtb" != "true" ]]; then
      create_dtb dtb.img
    fi

    zip -r9 -q --exclude=*placeholder $WORKDIR/$zipname *
  command popd > /dev/null

  find $SELFPATH -iname "*$devicename-$kernelver*" -delete
  # copy generated zip file to ak3 dir
  cp -f $WORKDIR/$zipname $SELFPATH/

  # cleanup working directory
  rm -rf $WORKDIR
  echo "done, your package are located at : $REL_SELFPATH/$zipname"

  push_to_device
  flash_from_rec
}

main $@
