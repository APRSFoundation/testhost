#================================================================#
# Copyright (c) 2010-2011 Zipline Games, Inc.
# All Rights Reserved.
# http://getmoai.com
#================================================================#

LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)

LOCAL_MODULE 		:= moai
LOCAL_LDLIBS 		:= -llog -lGLESv1_CM -lGLESv2

#Disable Modules Below

	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_ADCOLONY=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_CHARTBOOST=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_CRITTERCISM=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_DELTADNA=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_FACEBOOK=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_FLURRY=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_GOOGLE_PLAY_SERVICES=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_TAPJOY=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_TWITTER=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_ANDROID_VUNGLE=0
	MY_LOCAL_CFLAGS += -DAKU_WITH_BOX2D=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_CRYPTO=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_HTTP_CLIENT=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_HTTP_SERVER=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_IMAGE_JPG=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_IMAGE_PNG=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_IMAGE_PVR=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_IMAGE_WEBP=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_LUAEXT=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_SIM=1
	MY_LOCAL_CFLAGS += -DAKU_WITH_UNTZ=1
	MY_LOCAL_CFLAGS += -DNDEBUG
	MY_LOCAL_CFLAGS += -DMOAI_KEEP_ASSERT=1



#remove unused libraries from this list (be sure to disable the aku flag above too)
#these libraries will never be optimised out by the linker so need to be removed from this list when not in use.
#LOCAL_STATIC_JNI_LIBRARIES += libmoai-adcolony
#LOCAL_STATIC_JNI_LIBRARIES += libmoai-chartboost
#LOCAL_STATIC_JNI_LIBRARIES += libmoai-deltadna
#LOCAL_STATIC_JNI_LIBRARIES += libmoai-facebook
#LOCAL_STATIC_JNI_LIBRARIES += libmoai-flurry
#LOCAL_STATIC_JNI_LIBRARIES += libmoai-google-play-services
#LOCAL_STATIC_JNI_LIBRARIES += libmoai-tapjoy
#LOCAL_STATIC_JNI_LIBRARIES += libmoai-vungle
LOCAL_STATIC_JNI_LIBRARIES += libmoai-android

LOCAL_CFLAGS		:= $(MY_LOCAL_CFLAGS) -DAKU_WITH_PLUGINS=1 -include $(MOAI_SDK_HOME)/src/zl-vfs/zl_replace.h
LOCAL_C_INCLUDES 	:= $(LOCAL_PATH)/src $(MY_HEADER_SEARCH_PATHS)

LOCAL_SRC_FILES 	+= src/jni.cpp
LOCAL_SRC_FILES 	+= $(wildcard $(LOCAL_PATH)/src/host-modules/*.cpp)
LOCAL_SRC_FILES 	+= src/aku_plugins.cpp

LOCAL_STATIC_LIBRARIES := $(LOCAL_STATIC_JNI_LIBRARIES)  libmoai-box2d libmoai-http-client libmoai-http-server libmoai-image-jpg libmoai-image-png libmoai-image-pvr libmoai-image-webp libmoai-luaext libmoai-untz libmoai-sim libmoai-crypto libzl-gfx libzl-crypto libbox2d libuntz libvorbis libogg libpvr libfreetype libjpg libpng libwebp libtess libmongoose libcurl libcares libmbedtls libmoai-util libmoai-core libzl-core libcontrib libexpat libjson liblua libsfmt libsqlite liblsqlite3 libstruct libtinyxml libzl-vfs libzlib libcpufeatures libkissfft
LOCAL_WHOLE_STATIC_LIBRARIES := libmoai-sim libmoai-core libmoai-android

include $(BUILD_SHARED_LIBRARY)

$(call import-module,android/cpufeatures)
