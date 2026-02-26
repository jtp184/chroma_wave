/*
 * Mock HAL backend for development/testing without GPIO/SPI hardware.
 * NOTE: This implementation is single-threaded only. The static
 * mock_busy_state toggle is not thread-safe and will produce
 * non-deterministic results under parallel or forked test execution.
 */
#ifdef EPD_MOCK_BACKEND

#include "mock_hal.h"

int EPD_RST_PIN  = 17;
int EPD_DC_PIN   = 25;
int EPD_CS_PIN   = 8;
int EPD_BUSY_PIN = 24;
int EPD_PWR_PIN  = 18;
int EPD_MOSI_PIN = 10;
int EPD_SCLK_PIN = 11;

static UBYTE mock_busy_state = 0;

void DEV_Digital_Write(UWORD Pin, UBYTE Value) { (void)Pin; (void)Value; }

UBYTE DEV_Digital_Read(UWORD Pin) {
    (void)Pin;
    /* Alternate between 0 and 1 to prevent busy-wait hangs
       for both active-HIGH and active-LOW polarity patterns */
    mock_busy_state = !mock_busy_state;
    return mock_busy_state;
}

void DEV_GPIO_Mode(UWORD Pin, UWORD Mode) { (void)Pin; (void)Mode; }
void DEV_SPI_WriteByte(UBYTE Value) { (void)Value; }
void DEV_SPI_Write_nByte(uint8_t *pData, uint32_t Len) { (void)pData; (void)Len; }
void DEV_SPI_SendData(UBYTE Reg) { (void)Reg; }
void DEV_SPI_SendnData(UBYTE *Reg) { (void)Reg; }
UBYTE DEV_SPI_ReadData(void) { return 0; }
void DEV_Delay_ms(UDOUBLE xms) { (void)xms; }
UBYTE DEV_Module_Init(void) { return 0; }
void DEV_Module_Exit(void) {}

#endif /* EPD_MOCK_BACKEND */
