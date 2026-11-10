#!/bin/bash
# MacroGen 安卓出包脚本（无 Gradle）
# 用法: ./build_android.sh 2.5 14
set -e
VER_NAME=${1:-2.5}
VER_CODE=${2:-14}

export JAVA_HOME=${JAVA_HOME:-/home/user/tools/jdk-17.0.9+9}
BT=/home/user/tools/sdk/build-tools/34.0.0
JAR=/home/user/tools/sdk/platforms/android-34/android.jar
B=build_$VER_CODE

rm -rf $B && mkdir -p $B/gen $B/dex   # 目录必须先建，否则 d8 报 Invalid output

$BT/aapt2 compile --dir res -o $B/res.zip
$BT/aapt2 link -o $B/base.apk --manifest AndroidManifest.xml -R $B/res.zip \
    -I $JAR --java $B/gen \
    --min-sdk-version 21 --target-sdk-version 34 \
    --version-code $VER_CODE --version-name $VER_NAME

$JAVA_HOME/bin/javac -source 8 -target 8 -nowarn -bootclasspath $JAR -classpath $JAR \
    -d $B/classes $(find src -name "*.java") $(find $B/gen -name "R.java")

$BT/d8 --lib $JAR --min-api 21 --output $B/dex $(find $B/classes -name "*.class")

cp $B/base.apk $B/unaligned.apk
(cd $B && zip -q -j unaligned.apk dex/classes.dex)
$BT/zipalign -f 4 $B/unaligned.apk $B/aligned.apk

$BT/apksigner sign --ks macrogen.jks --ks-pass pass:${KS_PASS:?set KS_PASS} \
    --key-pass pass:${KS_PASS:?set KS_PASS} --ks-key-alias macrogen --out MacroGen.apk $B/aligned.apk

$BT/apksigner verify MacroGen.apk
$BT/aapt2 dump badging MacroGen.apk | head -1
ls -l MacroGen.apk && md5sum MacroGen.apk
