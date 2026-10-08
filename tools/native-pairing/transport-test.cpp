#include "Arduino.h"
#include <cassert>
#include <iostream>
#include <vector>
std::vector<int> calls;
struct BasicClient { bool open=true; void stop(){open=false;calls.push_back(1);} };
struct AsyncClient { void stopAsync(bool all){assert(all);calls.push_back(2);} };
struct SecureClient {
    BasicClient* basic; bool secure=true;
    void stop() {
        // Models both ESP_SSLClient branches: early return after failed TLS,
        // or a flush that would block while a half-spoken TCP socket is open.
        assert(!basic->open);
        calls.push_back(3);
        if(!secure)return;
        secure=false;
    }
};
class FirebaseClientWrap {
public:
    BasicClient basicClient;
    AsyncClient aClient;
    SecureClient sslClient{&basicClient};
    void configureTransport(){calls.push_back(4);}
    void resetTransport();
};
#define ENABLE_DATABASE
#include "firebase-reset-transport.inc"
int main() {
    for(bool secure:{true,false}) {
        FirebaseClientWrap client;
        client.sslClient.secure=secure;
        calls.clear();client.resetTransport();
        assert(!client.basicClient.open && calls==std::vector<int>({1,2,3,4}));
        calls.clear();client.resetTransport(); // Idempotent reset after failure.
        assert(calls==std::vector<int>({1,2,3,4}));
    }
    std::cout<<"Native transport tests passed: TCP closes before SSL reset for active/failed sessions\n";
}
