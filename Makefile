ARCHS  = arm64 arm64e
TARGET = iphone:clang:16.5:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = RedditTranslator
RedditTranslator_FILES     = Tweak.x
RedditTranslator_CFLAGS    = -fobjc-arc
RedditTranslator_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/library.mk
