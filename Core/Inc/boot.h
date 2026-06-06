#ifndef BOOT_H
#define BOOT_H
#include "stm32f4xx_hal.h"
/* F4系列扇区大小定义（以STM32F407为例，1MB Flash）*/
/* 根据具体芯片调整扇区大小 */
 HAL_StatusTypeDef Erase_Sector(uint32_t start_addr, uint32_t num);

#endif /* BOOT_H */