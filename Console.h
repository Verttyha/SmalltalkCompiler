#pragma once

#include "Buffer.h"
#include <iomanip>
#include <iostream>
#include <limits>

inline const char* TokenName(TokenKind type) {
    static const char* const names[] = {
        "IDENTIFIER", "KEYWORD", "BINARY_SELECTOR", "MINUS", "BAR",
        "SELF", "SUPER", "TRUE", "FALSE", "NIL", "INTEGER", "FLOAT",
        "SCALED_DECIMAL", "CHARACTER", "STRING", "SYMBOL_LITERAL", "SELECTOR_LITERAL",
        "ASSIGN", "RETURN", "LPAREN", "RPAREN", "LBRACKET", "RBRACKET",
        "HASH", "COLON", "PERIOD", "SEMICOLON", "CHUNK_END", "LBRACE", "RBRACE", "SCOPE_SEPARATOR", "ERROR"
    };
    static_assert(sizeof(names) / sizeof(names[0]) == LEX_ERROR - IDENTIFIER + 1);
    return names[type - IDENTIFIER];
}

// Оформление вывода токенов и сообщений об ошибках.
class Console {
public:
    static void Log(const Token& token) {
        std::cout << std::setprecision(std::numeric_limits<double>::max_digits10)
                  << token.start.line << ':' << token.start.column
                  << "  " << TokenName(token.type) << "  value=";

        switch (token.type) {
        case IDENTIFIER: case KEYWORD: case BINARY_SELECTOR: case MINUS: case BAR:
        case STRING_VALUE: case SYMBOL: case SELECTOR:
            PrintString(std::get<std::string>(token.value));
            break;

        case LEX_ERROR:
            PrintString(std::get<std::string>(token.value));
            std::cout << " lexeme=";
            PrintString(token.lexeme);
            break;

        case CHAR_VALUE: {
            unsigned code = static_cast<unsigned char>(std::get<char>(token.value));
            std::cout << code << " (U+" << std::hex << std::uppercase << code
                      << std::dec << std::nouppercase << ')';
            break;
        }

        case INTEGER:
            std::cout << std::get<IntegerValue>(token.value);
            break;

        case FLOAT_VALUE:
            std::cout << std::get<double>(token.value);
            break;

        case SCALED_DECIMAL:
            std::cout << std::get<DecimalValue>(token.value).value;
            break;

        case TRUE_VALUE: case FALSE_VALUE:
            std::cout << (std::get<bool>(token.value) ? "true" : "false");
            break;

        default:
            std::cout << '-';
        }

        if (!token.details.empty()) std::cout << " (" << token.details << ')';
        std::cout << '\n';
    }

    static void Error(const std::string& message) {
        std::cerr << message << '\n';
    }

    static void Summary(std::size_t tokens, std::size_t errors) {
        std::cout << tokens << " tokens, " << errors << " lexical errors\n";
    }

private:
    // Видимое оформление LF/TAB/backslash в логе. Значение токена не изменяется.
    static void PrintString(const std::string& text) {
        std::cout << '"';
        for (unsigned char c : text) {
            if (c == '\n')      std::cout << "\\n";
            else if (c == '\r') std::cout << "\\r";
            else if (c == '\t') std::cout << "\\t";
            else if (c == '\\' || c == '"') std::cout << '\\' << char(c);
            else if (c < 32 || c >= 127) {
                std::cout << "\\x" << std::hex << std::setw(2) << std::setfill('0')
                          << unsigned(c) << std::dec << std::setfill(' ');
            } else {
                std::cout << char(c);
            }
        }
        std::cout << '"';
    }
};
