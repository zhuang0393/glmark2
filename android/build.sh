#!/bin/bash

# Copyright 2019 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ -z "${ANDROID_SDK}" ];
then echo "Please set ANDROID_SDK, exiting"; exit 1;
else echo "ANDROID_SDK is ${ANDROID_SDK}";
fi

if [ -z "${ANDROID_NDK}" ];
then echo "Please set ANDROID_NDK, exiting"; exit 1;
else echo "ANDROID_NDK is ${ANDROID_NDK}";
fi

if [ -z "${JAVA_HOME}" ];
then echo "Please set JAVA_HOME, exiting"; exit 1;
else echo "JAVA_HOME is ${JAVA_HOME}";
fi

BUILD_TOOLS_VERSION=34.0.0
BUILD_TOOLS=$ANDROID_SDK/build-tools/$BUILD_TOOLS_VERSION
#if [ ! -d "${BUILD_TOOLS}" ];
#then echo "Please download correct build-tools version: ${BUILD_TOOLS_VERSION}, exiting"; exit 1;
#else echo "BUILD_TOOLS is ${BUILD_TOOLS}";
#fi

set -ev

GLMARK2_BUILD_DIR=$PWD
GLMARK2_BASE_DIR=$GLMARK2_BUILD_DIR/..
echo GLMARK2_BASE_DIR="${GLMARK2_BASE_DIR}"
echo GLMARK2_BUILD_DIR="${GLMARK2_BUILD_DIR}"

# Android 16 is the minSdkVersion supported
ANDROID_JAR=$ANDROID_SDK/platforms/android-34/android.jar

function create_APK() {
    mkdir -p bin/lib obj
    cp -r $GLMARK2_BUILD_DIR/libs/* $GLMARK2_BUILD_DIR/bin/lib
    cp -r $GLMARK2_BASE_DIR/data $GLMARK2_BUILD_DIR/bin/assets
    $BUILD_TOOLS/aapt package -f -m -S res -J src -M AndroidManifest.xml -I $ANDROID_JAR
    $JAVA_HOME/bin/javac -d ./obj -source 1.7 -target 1.7 -bootclasspath $JAVA_HOME/jre/lib/rt.jar -classpath $ANDROID_JAR:obj -sourcepath src src/org/linaro/glmark2c/*.java
    # 创建输出目录
    mkdir -p bin/classes
    # 修改D8命令，指定输出目录并正确指向class文件
    $BUILD_TOOLS/d8 --output bin/classes ./obj/org/linaro/glmark2c/*.class
    # 将生成的classes.dex移动到正确位置
    cp bin/classes/classes.dex bin/
    $BUILD_TOOLS/aapt package -f -M AndroidManifest.xml -S res -I $ANDROID_JAR -F $1-unaligned.apk bin
    # 定义密钥库目录和路径
    KEYSTORE_DIR=~/.android
    KEYSTORE_PATH=$KEYSTORE_DIR/debug.keystore
    # 确保密钥库目录存在
    mkdir -p $KEYSTORE_DIR
    # 检查debug.keystore是否存在
    if [ -f $KEYSTORE_PATH ]; then
        echo "Found debug.keystore at $KEYSTORE_PATH"
        # 使用apksigner签名，明确启用v2签名并添加错误检查
        echo "Signing APK with apksigner (V2 scheme)..."
        $BUILD_TOOLS/apksigner sign -v --v2-signing-enabled true --ks $KEYSTORE_PATH --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey $1-unaligned.apk
        if [ $? -ne 0 ]; then
            echo "Error: Failed to sign APK!"
            exit 1
        fi
        # 验证签名
        echo "Verifying signature..."
        $BUILD_TOOLS/apksigner verify -v --print-certs $1-unaligned.apk
        if [ $? -ne 0 ]; then
            echo "Error: Signature verification failed!"
            exit 1
        fi
    else
        echo "debug.keystore not found! Generating a new one at $KEYSTORE_PATH..."
        # 生成新的调试密钥库
        keytool -genkey -v -keystore $KEYSTORE_PATH -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug, OU=Android, O=Google Inc., L=Mountain View, ST=California, C=US"
        # 签名，明确启用v2签名并添加错误检查
        echo "Signing APK with apksigner (V2 scheme)..."
        $BUILD_TOOLS/apksigner sign -v --v2-signing-enabled true --ks $KEYSTORE_PATH --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey $1-unaligned.apk
        if [ $? -ne 0 ]; then
            echo "Error: Failed to sign APK!"
            exit 1
        fi
        # 验证签名
        echo "Verifying signature..."
        $BUILD_TOOLS/apksigner verify -v --print-certs $1-unaligned.apk
        if [ $? -ne 0 ]; then
            echo "Error: Signature verification failed!"
            exit 1
        fi
    fi
    # 先执行 zipalign
    echo "Aligning APK..."
    $BUILD_TOOLS/zipalign -f 4 $1-unaligned.apk $1-aligned.apk
    if [ $? -ne 0 ]; then
        echo "Error: Failed to align APK!"
        exit 1
    fi

    if [ -f $KEYSTORE_PATH ]; then
        echo "Found debug.keystore at $KEYSTORE_PATH"
        # 签名已对齐的 APK
        echo "Signing APK with apksigner (V2 scheme)..."
        $BUILD_TOOLS/apksigner sign -v --v2-signing-enabled true --ks $KEYSTORE_PATH --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey $1-aligned.apk
        if [ $? -ne 0 ]; then
            echo "Error: Failed to sign APK!"
            exit 1
        fi
        # 验证签名
        echo "Verifying signature..."
        $BUILD_TOOLS/apksigner verify -v --print-certs $1-aligned.apk
        if [ $? -ne 0 ]; then
            echo "Error: Signature verification failed!"
            exit 1
        fi
        # 重命名最终 APK
        mv $1-aligned.apk $1.apk
    else
        echo "debug.keystore not found! Generating a new one at $KEYSTORE_PATH..."
        # 生成新的调试密钥库
        keytool -genkey -v -keystore $KEYSTORE_PATH -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug, OU=Android, O=Google Inc., L=Mountain View, ST=California, C=US"
        # 签名已对齐的 APK
        echo "Signing APK with apksigner (V2 scheme)..."
        $BUILD_TOOLS/apksigner sign -v --v2-signing-enabled true --ks $KEYSTORE_PATH --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey $1-aligned.apk
        if [ $? -ne 0 ]; then
            echo "Error: Failed to sign APK!"
            exit 1
        fi
        # 验证签名
        echo "Verifying signature..."
        $BUILD_TOOLS/apksigner verify -v --print-certs $1-aligned.apk
        if [ $? -ne 0 ]; then
            echo "Error: Signature verification failed!"
            exit 1
        fi
        # 重命名最终 APK
        mv $1-aligned.apk $1.apk
    fi
}

#
# build native libraries
#
$ANDROID_NDK/build/ndk-build -j $cores

#
# build glmark2c APK
#
create_APK glmark2c

echo Builds succeeded
exit 0
