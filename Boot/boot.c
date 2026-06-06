#include "boot.h"



// #define FLASH_SECTOR_0     ((uint32_t)0)  // 地址: 0x08000000, 16KB
// #define FLASH_SECTOR_1     ((uint32_t)1)  // 地址: 0x08004000, 16KB
// #define FLASH_SECTOR_2     ((uint32_t)2)  // 地址: 0x08008000, 16KB
// #define FLASH_SECTOR_3     ((uint32_t)3)  // 地址: 0x0800C000, 16KB
// #define FLASH_SECTOR_4     ((uint32_t)4)  // 地址: 0x08010000, 64KB
// #define FLASH_SECTOR_5     ((uint32_t)5)  // 地址: 0x08020000, 128KB
// #define FLASH_SECTOR_6     ((uint32_t)6)  // 地址: 0x08040000, 128KB
// #define FLASH_SECTOR_7     ((uint32_t)7)  // 地址: 0x08060000, 128KB
// #define FLASH_SECTOR_8     ((uint32_t)8)  // 地址: 0x08080000, 128KB
// #define FLASH_SECTOR_9     ((uint32_t)9)  // 地址: 0x080A0000, 128KB
// #define FLASH_SECTOR_10    ((uint32_t)10) // 地址: 0x080C0000, 128KB
// #define FLASH_SECTOR_11    ((uint32_t)11) // 地址: 0x080E0000, 128KB


/**
 * @brief 擦除扇区（F4使用扇区擦除）
 *
 * @param start_addr  扇区编号	
 * @param num          删除扇区数
 * @return HAL状态
 */


void Erase_Sector(uint32_t start_addr, uint32_t num)
{


    HAL_FLASH_Unlock();
 
    /* 擦除FLASH扇区 */
    FLASH_EraseInitTypeDef FlashSet;
    FlashSet.TypeErase = FLASH_TYPEERASE_SECTORS;
    FlashSet.VoltageRange = FLASH_VOLTAGE_RANGE_3;  /* 2.7V - 3.6V */    
    FlashSet.Sector = start_addr; 
    FlashSet.NbSectors = 1;  /* 每次擦除一个扇区 */
    
    uint32_t PageError = 0;
    HAL_FLASHEx_Erase(&FlashSet, &PageError);
    HAL_FLASH_Lock();
    
}



/**
 * @bieaf 写若干个数据
 *
 * @param addr       写入的地址
 * @param buff       写入数据的起始地址
 * @param word_size  长度
 * @return 
 */
void WriteFlash(uint32_t addr, uint32_t * buff, int word_size)
{	
	/* 1/4解锁FLASH*/
	HAL_FLASH_Unlock();
	
	for(int i = 0; i < word_size; i++)	
	{
		/* 3/4对FLASH烧写*/
		HAL_FLASH_Program(FLASH_TYPEPROGRAM_WORD, addr + 4 * i, buff[i]);	
	}
 
	/* 4/4锁住FLASH*/
	HAL_FLASH_Lock();
}


/**
 * @bieaf 读若干个数据
 *
 * @param addr       读数据的地址
 * @param buff       读出数据的数组指针
 * @param word_size  长度
 * @return 
 */
void ReadFlash(uint32_t addr, uint32_t * buff, uint16_t word_size)
{
	for(int i =0; i < word_size; i++)
	{
		buff[i] = *(__IO uint32_t*)(addr + 4 * i);
	}
	return;
}




