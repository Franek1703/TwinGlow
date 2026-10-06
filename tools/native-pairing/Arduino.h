#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <algorithm>
#include <cctype>
class String {
    std::string s;
public:
    String()=default;
    String(const char* v):s(v?v:""){}
    String(const std::string& v):s(v){}
    String(unsigned long long n):s(std::to_string(n)){}
    const char* c_str()const{return s.c_str();}
    char* begin(){return s.data();}
    size_t length()const{return s.size();}
    bool isEmpty()const{return s.empty();}
    bool reserve(size_t n){s.reserve(n);return true;}
    bool concat(const char* v){s+=v;return true;}
    bool concat(const char* v,size_t n){s.append(v,n);return true;}
    String& operator=(const char* v){s=v?v:"";return *this;}
    String& operator+=(const char* v){s+=v;return *this;}
    String& operator+=(const String& v){s+=v.s;return *this;}
    char operator[](size_t n)const{return s[n];}
    bool startsWith(const char* prefix)const{return s.rfind(prefix,0)==0;}
    void toUpperCase(){std::transform(s.begin(),s.end(),s.begin(),[](unsigned char c){return std::toupper(c);});}
    friend bool operator==(const String& a,const String& b){return a.s==b.s;}
    friend bool operator!=(const String& a,const String& b){return !(a==b);}
    friend String operator+(const String& a,const String& b){return String(a.s+b.s);}
};
struct SerialMock {template<class T>void print(const T&){} template<class T>void println(const T&){} void println(){} };
inline SerialMock Serial;
extern unsigned long fakeMillis;
inline unsigned long millis(){return fakeMillis;}
#define F(x) x
