TARGET=iphone:4.2
TARGET_CXX = xcrun -sdk iphoneos clang++

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libBugSense
libBugSense_FILES = $(wildcard *.m) $(wildcard Support/*/*.m)
libBugSense_INSTALL_PATH = /usr/local/lib
libBugSense_FRAMEWORKS += UIKit SystemConfiguration
libBugSense_LDFLAGS += -FFrameworks -framework CrashReporter -lz
libBugSense_CFLAGS  += -Wno-deprecated-objc-isa-usage -Wno-format
libBugSense_CFLAGS  += -D__IPHONE_OS_VERSION_MIN_REQUIRED=__IPHONE_4_2
libBugSense_CFLAGS  += -IFrameworks/CrashReporter.framework/Headers/ \
				        -ISupport/AFNetworking \
				    	-ISupport/JSONKit \
				    	-ISupport/OpenUDID \
				    	-ISupport/Reachability

include $(THEOS_MAKE_PATH)/library.mk
