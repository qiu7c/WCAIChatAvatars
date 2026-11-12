ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = WeChat

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WCAIChatAvatars
WCAIChatAvatars_FILES = Tweak.x
WCAIChatAvatars_OBJCFLAGS = -fobjc-arc
WCAIChatAvatars_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
