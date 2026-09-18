CONFIG_AIC8800_BTLPM_SUPPORT := m
CONFIG_AIC8800_WLAN_SUPPORT := m
CONFIG_AIC_WLAN_SUPPORT := m

obj-$(CONFIG_AIC8800_BTLPM_SUPPORT) += aic8800_btlpm/
obj-$(CONFIG_AIC8800_WLAN_SUPPORT) += aic8800_fdrv/
obj-$(CONFIG_AIC_WLAN_SUPPORT) += aic8800_bsp/

KDIR  = /rockchip/Liontron-D3588.git/linux-6.6.y.git/
PWD   = $(shell pwd)
KVER = $(shell uname -r)
MODDESTDIR = /tmp/
ARCH = arm64
CROSS_COMPILE = aarch64-linux-gnu-
KBUILD_BUILD_USER = "builder"
KBUILD_BUILD_HOST = "kdevbuilder"

all: modules
modules:
	make -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules CONFIG_AIC_FW_PATH="/vendor/etc/firmware/aic8800"

clean:
	make -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean

