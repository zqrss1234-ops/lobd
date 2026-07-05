export TARGET = iphone:clang:latest:7.0
export ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = Yalla

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = yallatweak
yallatweak_FILES = Tweak.xm
yallatweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
