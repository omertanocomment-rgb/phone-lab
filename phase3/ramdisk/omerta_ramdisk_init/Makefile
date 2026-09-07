export THEOS_DEVICE_IP =
ARCHS = arm64
TARGET := iphone:clang:12.4:12.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = omerta_ramdisk_init

omerta_ramdisk_init_FILES = main.c
omerta_ramdisk_init_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
