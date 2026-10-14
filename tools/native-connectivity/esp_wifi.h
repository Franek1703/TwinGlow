#pragma once
#include "WiFi.h"
using esp_err_t = int;
constexpr int ESP_OK=0, WIFI_IF_STA=0, WIFI_BW_HT20=0;
constexpr uint8_t WIFI_PROTOCOL_11B=1, WIFI_PROTOCOL_11G=2, WIFI_PROTOCOL_11N=4;
struct RadioMock {
    uint8_t protocols = 0;
    int protocolError = ESP_OK, bandwidthError = ESP_OK;
    int powerError = ESP_OK, powerReadError = ESP_OK;
    int8_t power = 72;
    unsigned configurations = 0;
} inline radioMock;
inline int esp_wifi_set_protocol(int, uint8_t protocols) {
    radioMock.protocols=protocols; ++radioMock.configurations;
    return radioMock.protocolError;
}
inline int esp_wifi_set_bandwidth(int, int) { return radioMock.bandwidthError; }
inline int esp_wifi_set_max_tx_power(int8_t power) {
    if (radioMock.powerError == ESP_OK) radioMock.power = power;
    return radioMock.powerError;
}
inline int esp_wifi_get_max_tx_power(int8_t* power) {
    *power = radioMock.power; return radioMock.powerReadError;
}
