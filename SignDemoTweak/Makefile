TARGET := iphone:clang:latest:15.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SignDemo

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SignDemoTweak

SignDemoTweak_FILES = Tweak.x
SignDemoTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
