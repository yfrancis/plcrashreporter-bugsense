TARGET = iphone:4.2
TARGET_CXX = xcrun -sdk iphoneos clang++

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = BugSense
BugSense_FILES = $(wildcard *.m) $(wildcard Support/*/*.m)
BugSense_INSTALL_PATH = /Library/Frameworks
BugSense_FRAMEWORKS += UIKit SystemConfiguration
BugSense_LDFLAGS += -LCrashReporter/lib -lCrashReporter -lz
BugSense_CFLAGS  += -Iinclude -ICrashReporter/include
BugSense_CFLAGS  += -Wno-deprecated-objc-isa-usage -Wno-format
BugSense_CFLAGS  += -D__IPHONE_OS_VERSION_MIN_REQUIRED=__IPHONE_4_2
BugSense_CFLAGS  += -ISupport/AFNetworking \
				    -ISupport/JSONKit \
				    -ISupport/OpenUDID \
				    -ISupport/Reachability

# Do nothing on stage, we really just want the object files for linking
_THEOS_STAGING_RULES_LOADED := 1
_THEOS_PACKAGE_RULES_LOADED := 1
stage: ;
package: ;

include $(THEOS_MAKE_PATH)/framework.mk

# Set the paths for the framework stub
PRODUCT_PATH_ = .products
FMWK_PATH_ = $(PRODUCT_PATH_)/$(FRAMEWORK_NAME).framework

after-BugSense-all::
	$(ECHO_NOTHING)mkdir -p Resources/Headers$(ECHO_END)
	$(ECHO_NOTHING)cp -pR include/* Resources/Headers/$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(FMWK_PATH_)$(ECHO_END)
	$(ECHO_NOTHING)cd $(FMWK_PATH_) && \
		ln -Fs ../../Resources/* . && \
		ln -Fs $(THEOS_OBJ_DIR)/$(FRAMEWORK_NAME) . && \
		$(TARGET_STRIP) -cx $(FRAMEWORK_NAME_) \
	$(ECHO_END)

internal-clean::
	$(ECHO_NOTHING)rm -rf $(PRODUCT_PATH_)$(ECHO_END)

