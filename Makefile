TARGET = iphone:4.2
TARGET_CXX = xcrun -sdk iphoneos clang++

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = BugSense
BugSense_FILES = $(wildcard *.m) $(wildcard Support/*/*.m)
BugSense_INSTALL_PATH = /Library/Frameworks
BugSense_FRAMEWORKS += UIKit SystemConfiguration
BugSense_LDFLAGS += -FFrameworks -framework CrashReporter -lz
BugSense_CFLAGS  += -Wno-deprecated-objc-isa-usage -Wno-format
BugSense_CFLAGS  += -D__IPHONE_OS_VERSION_MIN_REQUIRED=__IPHONE_4_2
BugSense_CFLAGS  += -IFrameworks/CrashReporter.framework/Headers/ \
				        -ISupport/AFNetworking \
				    	-ISupport/JSONKit \
				    	-ISupport/OpenUDID \
				    	-ISupport/Reachability

include $(THEOS_MAKE_PATH)/framework.mk
