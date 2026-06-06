#ifndef BOOT_H
#define BOOT_H
#include "stm32f4xx_hal.h"
/* F4系列扇区大小定义（以STM32F407为例，1MB Flash）*/
/* 根据具体芯片调整扇区大小 */
void Erase_Sector(uint32_t start_addr, uint32_t num);
void WriteFlash(uint32_t addr, uint32_t * buff, int word_size);
void ReadFlash(uint32_t addr, uint32_t * buff, uint16_t word_size);
#endif /* BOOT_H */