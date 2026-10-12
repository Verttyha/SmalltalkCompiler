#pragma once

#include <cmath>
#include <cstddef>
#include <stdexcept>
#include <string>
#include <variant>

enum TokenKind {
    IDENTIFIER = 256, KEYWORD, BINARY_SELECTOR, MINUS, BAR,
    SELF, SUPER, TRUE_VALUE, FALSE_VALUE, NIL_VALUE,
    INTEGER, FLOAT_VALUE, SCALED_DECIMAL, CHAR_VALUE, STRING_VALUE,
    SYMBOL, SELECTOR, ASSIGN, RETURN, LPAREN, RPAREN,
    LBRACKET, RBRACKET, HASH, COLON, PERIOD, SEMICOLON, CHUNK_END, LBRACE, RBRACE, SCOPE_SEPARATOR, LEX_ERROR
};

struct Position {
    std::size_t line = 1, column = 1, offset = 0;
};

// добавить точность для целых больше long long?
using IntegerValue = long long;

// добавить точность для scaled decimal?
struct DecimalValue {
    double value;
    std::size_t scale;
};

using TokenValue = std::variant<std::monostate, IntegerValue, double,
                                DecimalValue, char, bool, std::string>;

struct Token {
    TokenKind type;
    TokenValue value;
    std::string details;
    std::string lexeme;
    Position start, end;
};

struct NumberValue {
    std::size_t length = 0;
    TokenKind type = INTEGER;
    TokenValue value;
    std::string details;
};

class Buffer {
public:
    Position position;
    Position tokenStart;
    std::string lexeme;

    void trackPosition(const char* text, std::size_t length) {
        tokenStart = position;

        if (collecting)
            lexeme.append(text, length);
        else
            lexeme.assign(text, length);

        for (std::size_t i = 0; i < length; ++i) {
            unsigned char c = text[i];
            ++position.offset;

            if (c == '\r') {
                ++position.line;
                position.column = 1;
            } else if (c == '\n') {
                if (!previousCR) ++position.line;
                position.column = 1;
            } else {
                ++position.column;
            }

            previousCR = c == '\r';
        }
    }

    void keepPrefix(std::size_t length) {
        lexeme.resize(length);
        position = tokenStart;
        position.column += length;
        position.offset += length;
        previousCR = false;
    }

    void reset() {
        content.clear();
        literalStart = tokenStart;
        collecting = true;
    }

    void append(const char* text, std::size_t length) {
        content.append(text, length);
    }

    const std::string& current() const {
        return content;
    }

    void restoreStart() {
        tokenStart = literalStart;
        collecting = false;
    }

    // 16rFF -> 255, 1.25s3 -> 1.25 scale=3
    static NumberValue parseNumber(const std::string& text) {
        std::size_t i = 0;
        auto digits = [&](unsigned base) {
            std::string part;
            while (i < text.size()) {
                char c = text[i];
                if (c == '_') {
                    ++i;
                    continue;
                }
                if (digit(c) >= base) break;
                part += c;
                ++i;
            }
            return part;
        };

        NumberValue result;
        std::string integer = digits(10), fraction, exponent, scale, message;
        unsigned base = 10;
        bool radix = i < text.size() && text[i] == 'r';
        bool negative = false;
        if (integer.empty()) message = "Missing integer digits";
        if (radix) {
            base = 0;
            for (char c : integer) {
                base = base * 10 + unsigned(c - '0');
                if (base > 36) break;
            }
            if (base < 1 || base > 36) {
                message = "Radix must be 1..36";
                base = 10;
            }
            ++i;
            if (i < text.size() && text[i] == '-') {
                negative = true;
                ++i;
            }
            integer = digits(base);
            if (integer.empty() && message.empty()) message = "Missing integer digits";
        }

        if (i + 1 < text.size() && text[i] == '.' && digit(text[i + 1]) < base) {
            ++i;
            fraction = digits(base);
            result.type = FLOAT_VALUE;
        }
        if (i < text.size() && text[i] == 's') {
            std::size_t next = i + 1;
            bool name = next < text.size() && ((text[next] >= 'A' && text[next] <= 'Z')
                     || (text[next] >= 'a' && text[next] <= 'z') || text[next] == '_' || text[next] == '$');
            if (!name) {
                ++i;
                if (i < text.size() && digit(text[i]) < 10) scale = digits(10);
                result.type = SCALED_DECIMAL;
            }
        } else if (i < text.size() && (text[i] == 'e' || text[i] == 'd' || text[i] == 'q')) {
            result.type = FLOAT_VALUE;
            result.details = std::string("format=") + text[i++];
            if (i < text.size() && text[i] == '-') {
                ++i;
                exponent = "-" + digits(10);
                if (exponent == "-" && message.empty()) message = "Missing exponent digits";
            } else if (i < text.size() && digit(text[i]) < 10) {
                exponent = digits(10);
            }
        }

        result.length = i;
        if (!message.empty()) return {i, LEX_ERROR, message, ""};

        try {
            std::string mantissa = integer;
            if (!fraction.empty()) mantissa += "." + fraction;
            if (negative) mantissa = "-" + mantissa;
            if (result.type == INTEGER) {
                if (base == 1) base = 2;
                result.value = std::stoll(mantissa, nullptr, base);
            } else {
                // добавить отдельную точность для e d q?
                double value = 0;
                if (!radix) {
                    if (!exponent.empty()) mantissa += "e" + exponent;
                    value = std::stod(mantissa);
                } else {
                    // добавить точное округление дробей с основанием?
                    int power = 0;
                    if (!exponent.empty()) power = std::stoi(exponent);
                    for (char c : integer) value = value * base + digit(c);
                    double place = 1;
                    for (char c : fraction) {
                        place /= base;
                        value += digit(c) * place;
                    }
                    if (value != 0) value *= std::pow(double(base), power);
                    if (!std::isfinite(value)) throw std::out_of_range("Float is outside double range");
                    if (negative) value = -value;
                }
                if (result.type == SCALED_DECIMAL) {
                    // добавить scale больше size_t?
                    std::size_t places = fraction.size();
                    if (!scale.empty()) places = std::stoull(scale);
                    result.value = DecimalValue{value, places};
                    result.details = "scale=" + std::to_string(places);
                } else {
                    result.value = value;
                }
            }
        } catch (const std::out_of_range&) {
            message = "Number is outside the supported range";
        } catch (const std::invalid_argument& exception) {
            message = exception.what();
        }
        if (!message.empty()) {
            result.type = LEX_ERROR;
            result.value = message;
            result.details.clear();
        }
        return result;
    }

private:
    static unsigned digit(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'A' && c <= 'Z') return c - 'A' + 10;
        return 36;
    }

    std::string content;
    Position literalStart;
    bool previousCR = false;
    bool collecting = false;
};
