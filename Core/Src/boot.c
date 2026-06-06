#include "boot.h"




/**
 * @brief 擦除扇区（F4使用扇区擦除）
 *
 * @param start_addr  起始地址	
 * @param num   删除字节数
 * @return HAL状态
 */


HAL_StatusTypeDef Erase_Sector(uint32_t start_addr, uint32_t num)
{
    HAL_StatusTypeDef status = HAL_OK;

    HAL_FLASH_Unlock();
 
    /* 擦除FLASH扇区 */
    FLASH_EraseInitTypeDef FlashSet;
    FlashSet.TypeErase = FLASH_TYPEERASE_SECTORS;
    FlashSet.VoltageRange = FLASH_VOLTAGE_RANGE_3;  /* 2.7V - 3.6V */    
    FlashSet.NbSectors = 1;  /* 每次擦除一个扇区 */
    
    uint32_t PageError = 0;
    status = HAL_FLASHEx_Erase(&FlashSet, &PageError);
    HAL_FLASH_Lock();
    return status;
}




