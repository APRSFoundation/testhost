#================================================================#
# Copyright (c) 2010-2011 Zipline Games, Inc.
# All Rights Reserved.
# http://getmoai.com
#================================================================#

	LOCAL_PATH := $(call my-dir)
	
	include $(CLEAR_VARS)
	
	MOAI_SDK_HOME	:= $(abspath ../../../)
	
	MY_ARM_MODE		:= arm
	MY_ARM_ARCH		:= armeabi-v7a arm64-v8a x86

	MY_LOCAL_CFLAGS		:=
	MY_INCLUDES			:=
	
	MOAI_MODULES	:= $(abspath ../../../util/ant-libmoai/)

	#----------------------------------------------------------------#
	# recursive wildcard function
	#----------------------------------------------------------------#

	rwildcard=$(foreach d,$(wildcard $1*),$(call rwildcard,$d/,$2)$(filter $(subst *,%,$2),$d))

#================================================================#
# 3rd party (core)
#================================================================#

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/contrib
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/expat-2.1.0/amiga
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/expat-2.1.0/lib
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/expat-2.1.0/xmlwf
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/kissfft
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/jansson-2.7/src
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/lsqlite3-0.9.5-1
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/lua-5.1.3/src
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/ooid-0.99
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/sfmt-1.4
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/sqlite-3.24.0
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/struct-0.3
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/tinyxml
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/tlsf-2.0
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/zlib-1.2.3

	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-contrib.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-expat.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-json.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-kissfft.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-lsqlite3.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-lua.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-sfmt.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-sqlite.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-struct.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-tinyxml.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-zlib.mk

#================================================================#
# moai core
#================================================================#

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/src/zl-vfs
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/src
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/src/config-default

	MY_INCLUDES += $(MOAI_MODULES)/modules/zl-core.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/zl-vfs.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-core.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-util.mk

#================================================================#
# moai modules
#================================================================#

	#--------------------------------------------------------------#
	# ANDROID

	MY_HEADER_SEARCH_PATHS += 
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-android.mk

	#--------------------------------------------------------------#
	# BOX2D

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/box2d-2.3.0/
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/box2d-2.3.0/Box2D
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/box2d-2.3.0/Box2D/Collision/Shapes
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/box2d-2.3.0/Box2D/Collision
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/box2d-2.3.0/Box2D/Common
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/box2d-2.3.0/Box2D/Dynamics
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/box2d-2.3.0/Box2D/Dynamics/Contacts
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/box2d-2.3.0/Box2D/Dynamics/Joints
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-box2d.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-box2d.mk

	#--------------------------------------------------------------#
	# CRYPTO

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/mbedtls/include
	MY_INCLUDES += $(MOAI_MODULES)/modules/zl-crypto.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-crypto.mk

	#--------------------------------------------------------------#
	# HTTP_CLIENT

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/c-ares-1.7.5
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/c-ares-1.7.5/include-android
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/curl/include
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/src/custom-include/curl/android
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/src/custom-include/curl/android/curl
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-c-ares.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-curl.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-mbedtls.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-http-client.mk

	#--------------------------------------------------------------#
	# HTTP_SERVER

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/mongoose
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-mongoose.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-http-server.mk

	#--------------------------------------------------------------#
	# IMAGE_JPG

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/jpeg-8c
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-jpg.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-image-jpg.mk

	#--------------------------------------------------------------#
	# IMAGE_PNG

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/lpng140
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-png.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-image-png.mk

	#--------------------------------------------------------------#
	# IMAGE_PVR

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/libpvr-3.4
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-pvr.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-image-pvr.mk

	#--------------------------------------------------------------#
	# IMAGE_WEBP

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-webp.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-image-webp.mk

	#--------------------------------------------------------------#
	# LUAEXT

	MY_HEADER_SEARCH_PATHS += 
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-luaext.mk

	#--------------------------------------------------------------#
	# SIM

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/freetype-2.4.4/include
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/freetype-2.4.4/include/freetype
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/freetype-2.4.4/include/freetype2
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/freetype-2.4.4/builds
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/freetype-2.4.4/src
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/freetype-2.4.4/config
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/libtess2/Include
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-freetype.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-tess.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/zl-gfx.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-sim.mk

	#--------------------------------------------------------------#
	# UNTZ

	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/src/moai-untz
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/untz/include
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/untz/src
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/untz/src/native/android
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/libvorbis-1.3.2/include
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/libvorbis-1.3.2/lib
	MY_HEADER_SEARCH_PATHS += $(MOAI_SDK_HOME)/3rdparty/libogg-1.2.2/include
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-ogg.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-vorbis.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/3rdparty-untz.mk
	MY_INCLUDES += $(MOAI_MODULES)/modules/moai-untz.mk


#================================================================#
# targets
#================================================================#

	include libraries.mk
  ifdef USE_PREBUILT
   include $(MOAI_SDK_HOME)/libmoai/jni/prebuiltcore.mk
   include $(MOAI_SDK_HOME)/libmoai/jni/prebuilt.mk
  else
	include $(MY_INCLUDES)
  endif
