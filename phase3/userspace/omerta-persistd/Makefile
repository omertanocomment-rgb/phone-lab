export THEOS_DEVICE_IP =
ARCHS = arm64
TARGET := iphone:clang:12.4:12.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = omerta_persistd

omerta_persistd_FILES = main.m ../../../phase1/OMERTAiOS-tweak/OwnerLock.m
omerta_persistd_CFLAGS = -fobjc-arc -I../../../phase1/OMERTAiOS-tweak
omerta_persistd_FRAMEWORKS = Foundation Security
omerta_persistd_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tool.mk

after-install::
	install.exec "chmod 644 /Library/LaunchDaemons/com.omerta.iosui.daemon.plist && chown root:wheel /Library/LaunchDaemons/com.omerta.iosui.daemon.plist && launchctl load /Library/LaunchDaemons/com.omerta.iosui.daemon.plist"
