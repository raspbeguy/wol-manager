include $(TOPDIR)/rules.mk

PKG_NAME:=wol-manager
PKG_VERSION:=$(shell sed -n '1p' $(CURDIR)/VERSION)
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Guy Godfroy <guy.godfroy@gugod.fr>

include $(INCLUDE_DIR)/package.mk

define Package/wol-manager
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Wake-on-LAN API with per-user host lists
  URL:=https://github.com/raspbeguy/wol-manager
  DEPENDS:=+etherwake +uhttpd +ucode +ucode-mod-fs +ucode-mod-uci +ucode-mod-digest
  PKGARCH:=all
endef

define Package/wol-manager/description
  HTTP API (uhttpd CGI) to send Wake-on-LAN packets. Each user
  authenticates with a Bearer token and can wake only the host lists
  that the administrator allows.
endef

define Package/wol-manager/conffiles
/etc/config/wol_manager
endef

define Build/Compile
endef

define Package/wol-manager/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/wol_manager.config $(1)/etc/config/wol_manager
	$(INSTALL_DIR) $(1)/usr/share/ucode
	$(INSTALL_DATA) ./files/wol_manager.uc $(1)/usr/share/ucode/wol_manager.uc
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) ./files/wol.cgi $(1)/www/cgi-bin/wol
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/wol-manager.cli $(1)/usr/sbin/wol-manager
endef

$(eval $(call BuildPackage,wol-manager))
