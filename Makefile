THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SCMusicPlusRevanced

SCMusicPlusRevanced_FILES = Tweak.x
SCMusicPlusRevanced_CFLAGS = -fobjc-arc
SCMusicPlusRevanced_FRAMEWORKS = UIKit Foundation
SCMusicPlusRevanced_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
