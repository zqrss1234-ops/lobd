export TARGET = iphone:clang:latest:7.0
export ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = YallaLite

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = abdulilah
abdulilah_FILES = Tweak.xm
abdulilah_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
