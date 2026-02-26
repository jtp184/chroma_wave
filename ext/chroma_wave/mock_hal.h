#ifndef MOCK_HAL_H
#define MOCK_HAL_H

#ifdef EPD_MOCK_BACKEND

#include <stdint.h>

/* Type definitions matching DEV_Config.h */
#define UBYTE   uint8_t
#define UWORD   uint16_t
#define UDOUBLE uint32_t

/* Pin definitions */
extern int EPD_RST_PIN;
extern int EPD_DC_PIN;
extern int EPD_CS_PIN;
extern int EPD_BUSY_PIN;
extern int EPD_PWR_PIN;
extern int EPD_MOSI_PIN;
extern int EPD_SCLK_PIN;

/* HAL function stubs */
void DEV_Digital_Write(UWORD Pin, UBYTE Value);
UBYTE DEV_Digital_Read(UWORD Pin);
void DEV_GPIO_Mode(UWORD Pin, UWORD Mode);
void DEV_SPI_WriteByte(UBYTE Value);
void DEV_SPI_Write_nByte(uint8_t *pData, uint32_t Len);
void DEV_SPI_SendData(UBYTE Reg);
void DEV_SPI_SendnData(UBYTE *Reg);
UBYTE DEV_SPI_ReadData(void);
void DEV_Delay_ms(UDOUBLE xms);
UBYTE DEV_Module_Init(void);
void DEV_Module_Exit(void);

#endif /* EPD_MOCK_BACKEND */
#endif /* MOCK_HAL_H */
