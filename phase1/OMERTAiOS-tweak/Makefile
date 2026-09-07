export THEOS_DEVICE_IP =
ARCHS = arm64
TARGET := iphone:clang:12.4:12.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OMERTAiOS

OMERTAiOS_FILES = Tweak.xm OwnerLock.m OMLockViewController.m
OMERTAiOS_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
OMERTAiOS_FRAMEWORKS = UIKit Security

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
