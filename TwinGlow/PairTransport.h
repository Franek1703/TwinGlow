#pragma once
#include "PairSnapshot.h"
class PairTransport {
public:
    virtual ~PairTransport() = default;
    virtual bool isStarted() const = 0;
    virtual bool requestPairState() = 0;
    virtual bool requestPairSend(PairSend*) = 0;
    virtual bool requestPairFetch(PairMeta*) = 0;
    virtual bool requestPairAck(PairMeta*,bool) = 0;
};
